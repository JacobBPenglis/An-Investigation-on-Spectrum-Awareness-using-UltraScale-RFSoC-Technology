"""PYNQ control code for the ZCU111 ADS-B capture overlay.

DMA words use little-endian complex int16:

    bits 15:0   signed I
    bits 31:16  signed Q

This module covers capture, DMA, local files and host streaming only.
"""

from __future__ import annotations

import json
import math
import socket
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import xrfdc
import xrfclk
from pynq import Overlay, allocate

try:
    from .iq_protocol import (
        ADC_SAMPLE_RATE_HZ,
        EXPECTED_AXIS_CLOCKS_PER_MS,
        EXPECTED_OUTPUT_VALID_INTERVAL,
        HARDWARE_BUILD_ID,
        IQ_SAMPLE_RATE_HZ,
        LEGACY_HARDWARE_BUILD_ID,
        PL_DECIMATION,
        PL_DECIMATOR_KIND,
        PL_DECIMATION_SELECT,
        PL_FIR_INSTANCE_NAMES,
        RFDC_DECIMATION,
        RFDC_FABRIC_WORDS,
        RFDC_FABRIC_CLOCK_HZ,
        UDP_HEADER,
        UDP_IQ_BYTES,
        UDP_MAGIC,
    )
except ImportError:  # Allow direct execution on the board.
    from iq_protocol import (
        ADC_SAMPLE_RATE_HZ,
        EXPECTED_AXIS_CLOCKS_PER_MS,
        EXPECTED_OUTPUT_VALID_INTERVAL,
        HARDWARE_BUILD_ID,
        IQ_SAMPLE_RATE_HZ,
        LEGACY_HARDWARE_BUILD_ID,
        PL_DECIMATION,
        PL_DECIMATOR_KIND,
        PL_DECIMATION_SELECT,
        PL_FIR_INSTANCE_NAMES,
        RFDC_DECIMATION,
        RFDC_FABRIC_WORDS,
        RFDC_FABRIC_CLOCK_HZ,
        UDP_HEADER,
        UDP_IQ_BYTES,
        UDP_MAGIC,
    )


DEFAULT_CENTRE_FREQUENCY_MHZ = 1090.0
REFERENCE_CLOCK_MHZ = 409.6
DEFAULT_ADC_TILE = 1  # XM500 J2, 1-4 GHz path, ADC225_T1_Ch0.


def unpack_iq(words: np.ndarray, normalize: bool = False) -> np.ndarray:
    """Convert packed DMA words into complex NumPy samples."""
    packed = np.asarray(words, dtype=np.uint32)
    i = (packed & np.uint32(0xFFFF)).astype(np.uint16).view(np.int16)
    q = (packed >> np.uint32(16)).astype(np.uint16).view(np.int16)
    scale = 32768.0 if normalize else 1.0
    return i.astype(np.float32) / scale + 1j * q.astype(np.float32) / scale


class AdsbCapture:
    """Load the overlay and capture samples."""

    def __init__(
        self,
        bitfile: Optional[str] = None,
        centre_frequency_mhz: float = DEFAULT_CENTRE_FREQUENCY_MHZ,
        adc_tile_index: int = DEFAULT_ADC_TILE,
    ) -> None:
        here = Path(__file__).resolve().parent
        if bitfile is None:
            bitfile = str(here / "bitstream" / "adsb_capture.bit")
        bitfile_path = Path(bitfile)
        hwh_path = bitfile_path.with_suffix(".hwh")
        if not bitfile_path.exists() or not hwh_path.exists():
            raise FileNotFoundError(
                f"Expected matching overlay files {bitfile_path} and {hwh_path}"
            )
        self.bitfile_path = bitfile_path
        self.hwh_path = hwh_path

        # Load order: HWH metadata, RF reference clocks, then PL configuration.
        self.overlay = Overlay(str(bitfile_path), download=False)
        self._validate_hwh_metadata()
        xrfclk.set_all_ref_clks(REFERENCE_CLOCK_MHZ)
        self.overlay.download()

        # Attribute names correspond to the Vivado block instance names.
        required_ip = {"rfdc", "axi_dma", "capture_control", "capture_status"}
        missing_ip = required_ip - set(self.overlay.ip_dict)
        if missing_ip:
            raise RuntimeError(
                "The HWH is missing PYNQ-controlled ADS-B IP instances: "
                f"{sorted(missing_ip)}"
            )
        self.dma = self.overlay.axi_dma
        self.control = self.overlay.capture_control
        self.status = self.overlay.capture_status
        self.rfdc = self.overlay.rfdc
        self.adc_tile = self.rfdc.adc_tiles[int(adc_tile_index)]
        self.adc_block = self.adc_tile.blocks[0]
        self._arm_toggle = 0

        status_word = int(self.status.channel1.read())
        hardware_build_id = (status_word >> 16) & 0xFFFF
        if hardware_build_id != HARDWARE_BUILD_ID:
            if hardware_build_id == LEGACY_HARDWARE_BUILD_ID:
                raise RuntimeError(
                    "The HWH describes the fixed-FIR ADS-B design, but the "
                    f"programmed FPGA reports legacy build ID "
                    f"0x{hardware_build_id:04x}. This normally means the new "
                    ".hwh was paired with the older selectable-decimator .bit. "
                    "Re-run synthesis/implementation in "
                    "build_rfdc8_fir32_clk160_v2, then deploy its .bit and "
                    ".hwh together. Do not change the expected sample rate."
                )
            raise RuntimeError(
                "The programmed FPGA is not the fixed-FIR RFDC8/PL32 build: "
                f"hardware ID 0x{hardware_build_id:04x}, expected "
                f"0x{HARDWARE_BUILD_ID:04x}. Deploy the matched .bit and "
                ".hwh generated from build_rfdc8_fir32_clk160_v2."
            )

        deadline = time.monotonic() + 0.25
        axis_clocks_per_ms = 0
        while time.monotonic() < deadline:
            axis_clocks_per_ms = int(self.status.channel2.read())
            if axis_clocks_per_ms:
                break
            time.sleep(0.005)
        clock_tolerance = max(32, EXPECTED_AXIS_CLOCKS_PER_MS // 1000)
        if abs(axis_clocks_per_ms - EXPECTED_AXIS_CLOCKS_PER_MS) > clock_tolerance:
            raise RuntimeError(
                "The implemented RFDC fabric clock is wrong: the FPGA "
                f"measured {axis_clocks_per_ms} axis clocks/ms "
                f"(~{axis_clocks_per_ms / 1000:.3f} MHz), expected "
                f"{EXPECTED_AXIS_CLOCKS_PER_MS} clocks/ms "
                f"({RFDC_FABRIC_CLOCK_HZ / 1e6:.3f} MHz)."
            )

        self._configure_receiver(centre_frequency_mhz)

    def _validate_hwh_metadata(self) -> None:
        """Reject metadata that does not describe the current fixed-FIR design."""
        try:
            parameters = self.overlay.ip_dict["rfdc"]["parameters"]
        except (KeyError, TypeError) as exc:
            raise RuntimeError(
                "The HWH does not contain RFDC parameters for instance 'rfdc'. "
                "Deploy the HWH generated beside the matching bitstream."
            ) from exc

        expected = {
            "C_ADC1_Fabric_Freq": 160.0,
            "C_ADC1_Outclk_Freq": 160.0,
            "C_ADC1_Sampling_Rate": 2.56,
            "C_ADC_Data_Width10": 2.0,
            "C_ADC_Decimation_Mode10": 8.0,
        }
        mismatches = []
        for name, wanted in expected.items():
            try:
                actual = float(parameters[name])
            except (KeyError, TypeError, ValueError):
                mismatches.append(f"{name}=missing")
                continue
            if not np.isclose(actual, wanted, rtol=0, atol=1e-6):
                mismatches.append(f"{name}={actual:g} (expected {wanted:g})")
        if mismatches:
            raise RuntimeError(
                "The HWH describes the wrong RFDC clock/rate interface: "
                + ", ".join(mismatches)
            )

        # The latest adsb_capture_bd.tcl replaced the AXI-controlled
        # xsg_bwselector with separate, fixed divide-by-32 FIR Compiler blocks.
        # Validate the HWH itself so a stale bitstream/HWH pair cannot reach a
        # register write for an IP that is no longer present.
        try:
            root = ET.parse(self.hwh_path).getroot()
        except (ET.ParseError, OSError) as exc:
            raise RuntimeError(f"Could not parse HWH metadata: {self.hwh_path}") from exc

        modules = {}
        for element in root.iter():
            if element.tag.rsplit("}", 1)[-1] != "MODULE":
                continue
            instance = element.attrib.get("INSTANCE", "")
            if not instance:
                continue
            parameters = {}
            for child in element.iter():
                if child.tag.rsplit("}", 1)[-1] == "PARAMETER":
                    name = child.attrib.get("NAME")
                    if name:
                        parameters[name.lower()] = child.attrib.get("VALUE", "")
            modules[instance.lower()] = {
                "vlnv": element.attrib.get("VLNV", ""),
                "parameters": parameters,
            }

        missing_firs = [
            name for name in PL_FIR_INSTANCE_NAMES if name.lower() not in modules
        ]
        if missing_firs:
            raise RuntimeError(
                "The HWH does not describe the latest fixed-FIR ADS-B path; "
                f"missing instances {missing_firs}. Rebuild/deploy the matched "
                ".bit and .hwh generated from the updated adsb_capture_bd.tcl."
            )

        fir_mismatches = []
        for name in PL_FIR_INSTANCE_NAMES:
            module = modules[name.lower()]
            if "fir_compiler" not in module["vlnv"].lower():
                fir_mismatches.append(f"{name} VLNV={module['vlnv']}")
            parameters = module["parameters"]
            checks = {
                "decimation_rate": "32",
                "filter_type": "Decimation",
                "output_width": "16",
            }
            for parameter, wanted in checks.items():
                actual = parameters.get(parameter)
                if actual is not None and str(actual).lower() != wanted.lower():
                    fir_mismatches.append(
                        f"{name} {parameter}={actual} (expected {wanted})"
                    )
        if fir_mismatches:
            raise RuntimeError(
                "The HWH fixed-FIR configuration is incompatible: "
                + ", ".join(fir_mismatches)
            )

    def _configure_receiver(self, centre_frequency_mhz: float) -> None:
        # Decimation and fabric width affect the physical PL interface and are
        # therefore fixed in Vivado. Do not rewrite them at runtime. A driver
        # write can make the RFDC register readback look correct while leaving
        # an implemented interface that is incompatible with the new rate.
        self.adc_tile.SetupFIFO(True)
        self.adc_block.NyquistZone = 1

        reported_decimation = int(self.adc_block.DecimationFactor)
        reported_words = int(self.adc_block.FabRdVldWords)
        if (
            reported_decimation != RFDC_DECIMATION
            or reported_words != RFDC_FABRIC_WORDS
        ):
            raise RuntimeError(
                "The implemented RFDC interface does not match the Python "
                f"protocol: decimation={reported_decimation}, words/beat="
                f"{reported_words}; expected {RFDC_DECIMATION} and "
                f"{RFDC_FABRIC_WORDS}. Rebuild the overlay; do not correct "
                "these physical-interface settings at runtime."
            )

        self.adc_block.MixerSettings = {
            "CoarseMixFreq": xrfdc.COARSE_MIX_BYPASS,
            "EventSource": xrfdc.EVNT_SRC_TILE,
            "FineMixerScale": xrfdc.MIXER_SCALE_1P0,
            "Freq": -float(centre_frequency_mhz),
            "MixerMode": xrfdc.MIXER_MODE_R2C,
            "MixerType": xrfdc.MIXER_TYPE_FINE,
            "PhaseOffset": 0.0,
        }
        self.adc_block.UpdateEvent(xrfdc.EVENT_MIXER)

        # PL decimation is fixed in the two FIR Compiler instances described by
        # the HWH. There is intentionally no run-time selector/register write.
        # 2.56 GSPS / 8 / 32 = 10 MSPS complex output.

        # The final stream is clocked at 160 MHz and the fixed FIR path must
        # assert TVALID once every 16 cycles: 160 MHz / 16 = 10 MSPS. This measures
        # the implemented datapath rather than trusting register readback.
        deadline = time.monotonic() + 0.5
        valid_interval = 0
        while time.monotonic() < deadline:
            status_word = int(self.status.channel1.read())
            valid_interval = (status_word >> 3) & 0x1FFF
            if valid_interval:
                break
            time.sleep(0.005)
        if valid_interval != EXPECTED_OUTPUT_VALID_INTERVAL:
            measured_rate_hz = 160_000_000 / max(valid_interval, 1)
            if valid_interval == 1:
                detail = (
                    " The one-clock interval is the signature of a bypass or "
                    "non-decimating path; the legacy xsg_bwselector resets to "
                    "selector zero. Check that implementation completed and "
                    "that the deployed .bit came from the same fixed-FIR run "
                    "as the HWH."
                )
            elif valid_interval == 128:
                detail = (
                    " An interval of 128 identifies the former deepest /256 "
                    "PL path and explains the observed x8 FFT-frequency error."
                )
            else:
                detail = ""
            raise RuntimeError(
                "Implemented PL sample rate is wrong: output TVALID interval "
                f"is {valid_interval} fabric clocks "
                f"(~{measured_rate_hz / 1e6:.3f} MSPS), expected "
                f"{EXPECTED_OUTPUT_VALID_INTERVAL} clocks (10.000 MSPS)."
                + detail
            )

        sampling_ghz = float(self.adc_block.BlockStatus["SamplingFreq"])
        if not np.isclose(sampling_ghz, 2.56, rtol=0, atol=0.005):
            raise RuntimeError(
                f"RFDC reports {sampling_ghz:.6f} GSPS, expected 2.560 GSPS. "
                "Check the Vivado RFDC PLL and the 409.6 MHz xrfclk setup."
            )

    @property
    def centre_frequency_mhz(self) -> float:
        return abs(float(self.adc_block.MixerSettings["Freq"]))

    @property
    def pl_decimator_kind(self) -> str:
        """Return the implemented programmable-logic decimator variant."""
        return PL_DECIMATOR_KIND

    @property
    def hardware_build_id(self) -> int:
        """Return the build identifier implemented in the FPGA fabric."""
        return (int(self.status.channel1.read()) >> 16) & 0xFFFF

    @property
    def output_valid_interval(self) -> int:
        """Return fabric-clock cycles per final complex output sample."""
        return (int(self.status.channel1.read()) >> 3) & 0x1FFF

    @property
    def fabric_clock_hz(self) -> int:
        """Return the independently measured RFDC AXI-stream clock."""
        return int(self.status.channel2.read()) * 1000

    @centre_frequency_mhz.setter
    def centre_frequency_mhz(self, value: float) -> None:
        settings = dict(self.adc_block.MixerSettings)
        settings["Freq"] = -float(value)
        self.adc_block.MixerSettings = settings
        self.adc_block.UpdateEvent(xrfdc.EVENT_MIXER)

    def capture(self, samples: int = 262_144):
        """Capture one frame and return its PYNQ DMA buffer.

        Call ``freebuffer()`` after using the returned buffer.
        """
        samples = int(samples)
        if samples <= 0 or samples > 16_000_000:
            raise ValueError("samples must be in the range 1..16,000,000")

        buffer = allocate(shape=(samples,), dtype=np.uint32)
        try:
            # DMA starts before the live sample path is armed.
            self.dma.recvchannel.transfer(buffer)
            self.control.channel1.write(samples, 0xFFFFFFFF)
            self._arm_toggle ^= 1
            self.control.channel2.write(self._arm_toggle, 0x1)
            self.dma.recvchannel.wait()
            buffer.sync_from_device()

            status = int(self.status.channel1.read())
            done = bool(status & 0x1)
            overflow = bool(status & 0x2)
            if overflow or not done:
                raise RuntimeError(
                    f"Invalid capture status 0x{status:08x}; "
                    "increase FIFO depth or inspect DMA/clocking."
                )
            return buffer
        except Exception:
            buffer.freebuffer()
            raise

    def save(self, path: str, samples: int = 262_144) -> Tuple[Path, Path]:
        """Capture I/Q and save a raw file plus JSON metadata."""
        data_path = Path(path)
        if data_path.suffix == "":
            data_path = data_path.with_suffix(".ci16")
        metadata_path = data_path.with_suffix(data_path.suffix + ".json")
        data_path.parent.mkdir(parents=True, exist_ok=True)

        buffer = self.capture(samples)
        try:
            # The A53 view produces interleaved signed int16 I/Q values.
            np.asarray(buffer).view(np.int16).tofile(data_path)
        finally:
            buffer.freebuffer()

        metadata = {
            "format": "little-endian signed int16 interleaved I,Q",
            "complex_samples": int(samples),
            "sample_rate_hz": IQ_SAMPLE_RATE_HZ,
            "centre_frequency_hz": int(round(self.centre_frequency_mhz * 1e6)),
            "adc_sample_rate_hz": ADC_SAMPLE_RATE_HZ,
            "rfdc_decimation": RFDC_DECIMATION,
            "rfdc_fabric_words": RFDC_FABRIC_WORDS,
            "rfdc_fabric_clock_hz": self.fabric_clock_hz,
            "pl_decimation": PL_DECIMATION,
            "pl_decimation_select": PL_DECIMATION_SELECT,
            "pl_decimator_kind": PL_DECIMATOR_KIND,
            "hardware_build_id": f"0x{self.hardware_build_id:04X}",
            "output_valid_interval": self.output_valid_interval,
            "utc_unix_ns": time.time_ns(),
        }
        metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
        return data_path, metadata_path

    @staticmethod
    def send_udp_frame(
        sock: socket.socket,
        destination: Tuple[str, int],
        buffer,
        frame_id: int,
    ) -> None:
        """Send one frame as ordered 1024-byte I/Q chunks over UDP."""
        raw = memoryview(buffer).cast("B")
        total_packets = math.ceil(len(raw) / UDP_IQ_BYTES)
        timestamp_ns = time.time_ns()
        for packet_id in range(total_packets):
            start = packet_id * UDP_IQ_BYTES
            stop = min(start + UDP_IQ_BYTES, len(raw))
            header = UDP_HEADER.pack(
                UDP_MAGIC,
                frame_id & 0xFFFFFFFF,
                packet_id,
                total_packets,
                timestamp_ns,
            )
            # sendmsg transmits the header and payload without concatenation.
            sock.sendmsg([header, raw[start:stop]], [], 0, destination)

    def stream_udp(
        self,
        host: str,
        port: int = 50000,
        frame_samples: int = 262_144,
        frames: Optional[int] = None,
    ) -> None:
        """Repeatedly capture frames and send them to the host.

        Simple DMA leaves a short gap while the next frame is armed. Use
        scatter/gather DMA for an unbroken recording.
        """
        destination = (host, int(port))
        sent = 0
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            while frames is None or sent < frames:
                buffer = self.capture(frame_samples)
                try:
                    self.send_udp_frame(sock, destination, buffer, sent)
                finally:
                    buffer.freebuffer()
                sent += 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Capture ZCU111 ADS-B IQ data")
    parser.add_argument("output", help="Output .ci16 file")
    parser.add_argument("--samples", type=int, default=262_144)
    parser.add_argument("--bitfile")
    parser.add_argument("--frequency-mhz", type=float, default=1090.0)
    args = parser.parse_args()

    capture = AdsbCapture(args.bitfile, args.frequency_mhz)
    data, metadata = capture.save(args.output, args.samples)
    print(f"Wrote {data} and {metadata}")
