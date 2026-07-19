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
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import xrfdc
import xrfclk
from pynq import Overlay, allocate

try:
    from .iq_protocol import (
        ADC_SAMPLE_RATE_HZ,
        IQ_SAMPLE_RATE_HZ,
        PL_DECIMATION,
        RFDC_DECIMATION,
        UDP_HEADER,
        UDP_IQ_BYTES,
        UDP_MAGIC,
    )
except ImportError:  # Allow direct execution on the board.
    from iq_protocol import (
        ADC_SAMPLE_RATE_HZ,
        IQ_SAMPLE_RATE_HZ,
        PL_DECIMATION,
        RFDC_DECIMATION,
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

        # Load order: HWH metadata, RF reference clocks, then PL configuration.
        self.overlay = Overlay(str(bitfile_path), download=False)
        xrfclk.set_all_ref_clks(REFERENCE_CLOCK_MHZ)
        self.overlay.download()

        # Attribute names correspond to the Vivado block instance names.
        self.dma = self.overlay.axi_dma
        self.control = self.overlay.capture_control
        self.status = self.overlay.capture_status
        self.decimator = self.overlay.decimator
        self.rfdc = self.overlay.rfdc
        self.adc_tile = self.rfdc.adc_tiles[int(adc_tile_index)]
        self.adc_block = self.adc_tile.blocks[0]
        self._arm_toggle = 0

        self._configure_receiver(centre_frequency_mhz)

    def _configure_receiver(self, centre_frequency_mhz: float) -> None:
        self.adc_tile.SetupFIFO(True)
        self.adc_block.NyquistZone = 1
        self.adc_block.DecimationFactor = RFDC_DECIMATION
        # Two 16-bit words per 160 MHz beat produce 320 MSPS complex.
        self.adc_block.FabRdVldWords = 2
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

        # The decimator control register stores log2(decimation).
        self.decimator.write(0x00, 5)  # 2**5 = 32

        sampling_ghz = float(self.adc_block.BlockStatus["SamplingFreq"])
        if not np.isclose(sampling_ghz, 2.56, rtol=0, atol=0.005):
            raise RuntimeError(
                f"RFDC reports {sampling_ghz:.6f} GSPS, expected 2.560 GSPS. "
                "Check the Vivado RFDC PLL and the 409.6 MHz xrfclk setup."
            )

    @property
    def centre_frequency_mhz(self) -> float:
        return abs(float(self.adc_block.MixerSettings["Freq"]))

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
            "pl_decimation": PL_DECIMATION,
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
