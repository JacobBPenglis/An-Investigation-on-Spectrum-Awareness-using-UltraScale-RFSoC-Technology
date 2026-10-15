"""Calibrate magnetometer heading against IQ phase directly on the PYNQ board.

Terminal: python3 doa_calibration.py --bitstream top_design.bit
The ESP32 magnetometer defaults to /dev/ttyUSB0 at 115200 baud.
"""
import argparse
import math
import os
from pathlib import Path
import sys
import time
import traceback

import numpy as np
import serial
import matplotlib.pyplot as plt

from helper import (
    KeyReader as NotebookKeyReader,
    Magnetometer,
    calibrate_magnetometer,
    circular_stats,
    complex_channels,
    magnetic_angle,
)

BAUD = 115200
POSITIONS = 11
SECONDS_PER_POSITION = 10.0
DEFAULT_SERIAL_PORT = "/dev/ttyUSB0"
TLAST_SAMPLES = 256
DMA_DTYPE = np.dtype("<u8")
DMA_FRAME_BYTES = TLAST_SAMPLES * DMA_DTYPE.itemsize


class DMAError(RuntimeError):
    """A DMA transfer failed; stop rather than reuse a failed channel."""


class CaptureError(RuntimeError):
    """No usable position measurement; the user can retry."""


class TerminalKeyReader:
    """Nonblocking ENTER / SPACE / Q controls for a board terminal."""

    def __enter__(self):
        if not sys.stdin.isatty():
            raise RuntimeError(
                "Use an interactive board terminal, or run main(['--notebook']) "
                "in a notebook worker thread as described in README.md."
            )
        if sys.platform == "win32":
            import msvcrt
            self.msvcrt = msvcrt
        else:
            import select
            import termios
            import tty
            self.select = select
            self.termios = termios
            self.fd = sys.stdin.fileno()
            self.old_settings = termios.tcgetattr(self.fd)
            self.tty = tty
            self.refresh()
        return self

    def __exit__(self, *_args):
        if sys.platform != "win32":
            self.termios.tcsetattr(self.fd, self.termios.TCSADRAIN, self.old_settings)

    def poll(self):
        if sys.platform == "win32":
            return self.msvcrt.getwch() if self.msvcrt.kbhit() else None
        if self.select.select([self.fd], [], [], 0)[0]:
            # Avoid mixing select(fd) with TextIOWrapper's separate read buffer.
            return os.read(self.fd, 1).decode("utf-8", errors="ignore") or None
        return None

    def refresh(self):
        """Reapply cbreak after overlay/runtime setup, retaining original settings."""
        if sys.platform != "win32":
            self.tty.setcbreak(self.fd)


class DMAReader:
    """Continuously receive 256 x uint64, returning signed [I0,Q0,I1,Q1].

    poll() checks completion rather than waiting for a pending transfer.
    PYNQ driver/MMIO/cache operations can still block if hardware is stalled.
    Completed samples are copied before the buffer is rearmed.
    """

    def __init__(self, dma, timeout=2.0, debug=False):
        from pynq import allocate
        self.channel = dma.recvchannel
        self.timeout = timeout
        self.buffer = allocate(shape=(TLAST_SAMPLES,), dtype=DMA_DTYPE)
        self.pending = False
        self.closed = False
        self.skip_next = False
        self.debug = debug
        self.frames = 0

    def __enter__(self):
        try:
            if not self.channel.running:
                self._trace("Restarting receive channel")
                self.channel.start()
            self._start()
        except BaseException:
            if self.debug:
                traceback.print_exc()
            self.close()
            raise
        return self

    def __exit__(self, *_args):
        self.close()

    def _start(self):
        self.pending = True  # Stop safely even if transfer() fails partway.
        try:
            self._trace("Arming 2048-byte receive")
            self.channel.transfer(self.buffer)
            self._trace("Receive armed")
        except (RuntimeError, ValueError) as exc:
            raise DMAError(f"Cannot start DMA receive: {exc}") from exc
        self.deadline = time.monotonic() + self.timeout

    def _trace(self, message):
        if self.debug and self.frames < 2:
            print(f"\nDMA debug: {message}", flush=True)

    def poll(self):
        if self.closed:
            raise DMAError("DMA reader is closed")
        if self.channel.error:
            raise DMAError("DMA receive error; check TLAST, stream width and the bitstream")
        if not self.channel.running:
            raise DMAError("DMA receive channel halted unexpectedly")
        if not self.channel.idle:
            if time.monotonic() >= self.deadline:
                raise DMAError(
                    f"DMA timed out after {self.timeout:g}s waiting for "
                    f"{TLAST_SAMPLES} 64-bit words and TLAST"
                )
            return None
        try:
            self._trace("Completion detected; calling PYNQ wait/cache sync")
            self.channel.wait()  # Already idle; performs PYNQ bookkeeping/cache invalidation.
            self._trace("PYNQ wait returned")
        except RuntimeError as exc:
            raise DMAError(f"DMA receive failed: {exc}") from exc
        if self.channel.transferred != DMA_FRAME_BYTES:
            raise DMAError(
                f"Expected {DMA_FRAME_BYTES} DMA bytes; got {self.channel.transferred}. "
                "Check TLAST=256 and the 64-bit stream width."
            )
        self.buffer.invalidate()
        self._trace("Buffer cache invalidated")
        # Bits [63:0]={Q1,I1,Q0,I0}; little-endian memory=[I0,Q0,I1,Q1].
        samples = self.buffer.view("<i2").reshape(TLAST_SAMPLES, 4).copy()
        discard = self.skip_next
        self.skip_next = False
        self.frames += 1
        self._start()
        return None if discard else samples

    def close(self):
        if not self.closed:
            if self.pending:
                self.channel.stop()  # Halt DMA before releasing its target memory.
                self.pending = False
            self.buffer.freebuffer()
            self.closed = True


def wait_for_position(mag, center, correction, zero, position, positions, keys):
    """Wait for user input without arming, polling, or accessing DMA."""
    last_status = 0.0
    while True:
        key = keys.poll()
        if key and key.lower() == "q":
            raise KeyboardInterrupt
        if key in (" ", "\r", "\n"):
            return
        mag.poll()
        now = time.monotonic()
        if now-last_status > 0.5:
            text = "no serial data"
            if mag.latest is not None:
                heading = (magnetic_angle(mag.latest, center, correction)-zero) % 360.0
                text = f"{heading:6.2f} deg"
            print(f"\rPosition {position}/{positions}: {text}. "
                  "Hold steady; press ENTER or SPACE to record, Q to quit ...   ",
                  end="", flush=True)
            last_status = now
        time.sleep(0.005)


def capture_position(reader, mag, center, correction, zero, seconds, keys=None):
    started = time.monotonic()
    until = started + seconds
    reader.skip_next = True  # Discard the transfer armed before recording began.
    corr = 0j
    p0 = p1 = 0.0
    frames = 0
    headings = []
    one_sec_correlations = {}
    last_print = started
    while time.monotonic() < until:
        if keys is not None:
            key = keys.poll()
            if key and key.lower() == "q":
                raise KeyboardInterrupt
        for xy in mag.poll():
            headings.append((magnetic_angle(xy, center, correction) - zero) % 360.0)
        samples = reader.poll()
        if samples is not None:
            z = complex_channels(samples)
            a, b = z[:, 0], z[:, 1]
            cross = np.vdot(a, b)
            corr += cross
            p0 += float(np.vdot(a, a).real)
            p1 += float(np.vdot(b, b).real)
            frames += 1
            second = int(time.monotonic() - started)
            one_sec_correlations[second] = one_sec_correlations.get(second, 0j) + cross
        now = time.monotonic()
        if now - last_print >= 1.0:
            heading_text = f"{headings[-1]:6.1f} deg" if headings else "waiting"
            phase = math.degrees(np.angle(corr)) if frames else float("nan")
            print(f"\r  {max(0.0, until-now):4.1f}s remaining  heading={heading_text}  "
                  f"phase={phase:+7.2f} deg   DMA frames={frames:6d}", end="", flush=True)
            last_print = now
        if samples is None:
            time.sleep(0.0005)
    print()
    if not frames or not headings:
        raise CaptureError(f"No {'DMA frames' if not frames else 'magnetometer readings'} captured.")
    if p0 <= 0 or p1 <= 0 or abs(corr) == 0:
        raise CaptureError("No usable correlated IQ signal; check both RF channels.")
    heading, heading_std = circular_stats(headings)
    sec_phases = np.angle(list(one_sec_correlations.values()))
    phase_error = np.rad2deg(np.angle(np.exp(1j*(sec_phases-np.angle(corr)))))
    return {
        "phase_deg": float(np.rad2deg(np.angle(corr))),
        "angle_deg": heading,
        "angle_std_deg": heading_std,
        "phase_max_deviation_deg": float(np.max(np.abs(phase_error))),
        "coherence": float(abs(corr)/math.sqrt(p0*p1)),
        "dma_frames": frames,
        "iq_samples": frames*TLAST_SAMPLES,
        "mag_samples": len(headings),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("serial_port", nargs="?", default=DEFAULT_SERIAL_PORT,
                        help=f"Magnetometer serial port (default: {DEFAULT_SERIAL_PORT})")
    parser.add_argument("--bitstream", type=Path, default=Path("top_design.bit"))
    parser.add_argument("--dma-name", default="axi_dma_0")
    parser.add_argument("--dma-timeout", type=float, default=2.0)
    parser.add_argument("--seconds", type=float, default=SECONDS_PER_POSITION)
    parser.add_argument("--positions", type=int, default=POSITIONS)
    parser.add_argument("--mag-only", action="store_true", help="Test/calibrate the magnetometer without loading an overlay or touching DMA")
    parser.add_argument("--serial-debug", action="store_true", help="Print raw magnetometer serial chunks for diagnosis")
    parser.add_argument("--debug", action="store_true", help="Print DMA startup progress and a traceback on errors or Ctrl+C")
    parser.add_argument("--notebook", action="store_true", help="Use notebook buttons; run main in a worker thread")
    args = parser.parse_args(argv)
    if (not math.isfinite(args.seconds) or args.seconds <= 0 or args.positions <= 0
            or not math.isfinite(args.dma_timeout) or args.dma_timeout <= 0):
        parser.error("Use finite seconds > 0, positions > 0, and finite dma-timeout > 0")
    if not callable(getattr(serial, "Serial", None)) or not hasattr(serial, "SerialException"):
        print(
            "Calibration error: this script requires pyserial (imported as serial), "
            "but a different serial module was loaded from "
            f"{getattr(serial, '__file__', '<unknown>')}.\n"
            "Fix with the same Python used to run this script:\n"
            "  python -m pip uninstall -y serial\n"
            "  python -m pip install --force-reinstall pyserial\n"
            "Also check that this directory has no serial.py file or serial/ folder.",
            file=sys.stderr,
        )
        return 1
    try:
        if not args.mag_only and not args.bitstream.is_file():
            raise FileNotFoundError(
                f"Bitstream not found: {args.bitstream.resolve()}. "
                "Supply --bitstream /path/to/your_design.bit."
            )
        with serial.Serial(args.serial_port, BAUD, timeout=0) as ser:
            print(f"Magnetometer: {args.serial_port} ({BAUD} baud)")
            time.sleep(2.0)
            ser.reset_input_buffer()
            mag = Magnetometer(ser, debug=args.serial_debug)
            controls = NotebookKeyReader() if args.notebook else TerminalKeyReader()
            with controls as keys:
                if args.notebook:
                    keys.show()
                print("Magnetometer calibration uses serial only; DMA has not been started.")
                center, correction, zero = calibrate_magnetometer(mag, keys)
                if args.mag_only:
                    print("Magnetometer calibration completed; --mag-only run finished.")
                    return 0
                from pynq import Overlay, allocate
                import xrfdc
                import xrfclk
                print(f"Loading bitstream: {args.bitstream}; DMA: {args.dma_name}")
                overlay = Overlay(str(args.bitstream))
                try:
                    dma = getattr(overlay, args.dma_name)
                except AttributeError as exc:
                    raise RuntimeError(f"DMA {args.dma_name!r} was not found; supply --dma-name.") from exc
                print(f"DMA: {TLAST_SAMPLES} x 64-bit words = {DMA_FRAME_BYTES} bytes per frame")
                print("IQ: [I0,Q0,I1,Q1]; phase = channel 1 relative to channel 0")
                if not args.notebook:
                    keys.refresh()
                print("\nHOLD steady; press ENTER or SPACE (Record Position) to record.")
                print(f"Each capture is {args.seconds:g} seconds. Press Q (Stop) to quit.\n")
                measurements = []
                for position in range(1, args.positions+1):
                    while True:
                        wait_for_position(mag, center, correction, zero, position, args.positions, keys)
                        print(f"\nRecording position {position}/{args.positions}; starting DMA ...", flush=True)
                        try:
                            # No DMA buffer is allocated or transfer armed until the user starts.
                            with DMAReader(dma, args.dma_timeout, debug=args.debug) as reader:
                                try:
                                    result = capture_position(reader, mag, center, correction, zero, args.seconds, keys)
                                except BaseException:
                                    # Print before DMA cleanup, so a blocked stop() cannot hide the stack.
                                    if args.debug:
                                        traceback.print_exc()
                                    raise
                        except CaptureError as exc:
                            print(f"  Failed: {exc} Press ENTER or SPACE to retry this position.")
                            continue
                        break
                    measurements.append(result)
                    print(f"  Heading={result['angle_deg']:7.2f} deg (std={result['angle_std_deg']:.2f} deg), "
                          f"phase={result['phase_deg']:+8.2f} deg, coherence={result['coherence']:.3f}, "
                          f"1s phase drift<={result['phase_max_deviation_deg']:.1f} deg")
                    if result["angle_std_deg"] > 3:
                        print("  WARNING: Magnetometer moved during measurement (>3 deg std).")
                    if result["phase_max_deviation_deg"] > 10:
                        print(f"  WARNING: IQ phase moved during the {args.seconds:g}-second measurement.")
    except (OSError, RuntimeError, ImportError, ValueError) as exc:
        if args.debug:
            traceback.print_exc()
        print(f"\nCalibration error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        if args.debug:
            traceback.print_exc()
        print("\nStopped by Ctrl+C or Q before completing table.")
        return 130
    measurements.sort(key=lambda item: item["phase_deg"])
    print("\n   Phase (deg) -> Heading (deg) | Head std | Phase drift | Coherence")
    for item in measurements:
        print(f" {item['phase_deg']:+11.2f} -> {item['angle_deg']:12.2f} | "
              f"{item['angle_std_deg']:8.2f} | {item['phase_max_deviation_deg']:11.2f} | "
              f"{item['coherence']:9.3f}")
        
    ## Plotting code    
    angles = np.linspace(-180, 180, 1000)
    headings = [(m["angle_deg"] + 180) % 360 - 180 for m in measurements]
    phases = [m["phase_deg"] for m in measurements]

    plt.figure(figsize=(9, 5))
    plt.plot(angles, 180 * np.sin(np.deg2rad(angles)), label="Theory: half-wavelength spacing")
    plt.errorbar(headings, phases,
                 xerr=[m["angle_std_deg"] for m in measurements],
                 yerr=[m["phase_max_deviation_deg"] for m in measurements],
                 fmt="o", color="tab:orange", capsize=4, label="Measurements")
    plt.xlabel("Heading (degrees)")
    plt.ylabel("Phase difference (degrees)")
    plt.xlim(-180, 180)
    plt.ylim(-190, 190)
    plt.grid(alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig("phase_vs_angle.png", dpi=200)
    plt.show()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
