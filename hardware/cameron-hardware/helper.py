import argparse
import csv
import json
import math
from pathlib import Path
import socket
import struct
import sys
import time

import numpy as np
import serial

TLAST_SAMPLES = 256
DMA_WORD_BYTES = 8
DMA_FRAME_BYTES = TLAST_SAMPLES * DMA_WORD_BYTES
PAYLOAD_BYTES = 1024  # IQ bytes per UDP fragment, excluding the header.
HEADER = struct.Struct("!HB")  # uint16 detection ID, uint8 fragment index.
DATAGRAM_BYTES = HEADER.size + PAYLOAD_BYTES
FRAGMENTS_PER_DETECTION = DMA_FRAME_BYTES // PAYLOAD_BYTES
DEFAULT_PORT = 5005
VALUES_PER_SAMPLE = 4
SAMPLES_PER_PACKET = PAYLOAD_BYTES // (VALUES_PER_SAMPLE * 2)
WIRE_DTYPE = np.dtype("<i2")

def unpack_packet(payload: bytes):
    """Decode one 1027-byte datagram to (128, 4) int16 [I0,Q0,I1,Q1].

    Each DMA word is {Q1[15:0], I1[15:0], Q0[15:0], I0[15:0]},
    from bit 63 down to bit 0. Little-endian memory puts I0 first.
    Each fragment can be correlated independently; no reassembly is needed.
    """
    if len(payload) != DATAGRAM_BYTES:
        raise ValueError(f"Expected {DATAGRAM_BYTES} datagram bytes, got {len(payload)}")
    _detection_count, fragment_index = HEADER.unpack_from(payload)
    if fragment_index >= FRAGMENTS_PER_DETECTION:
        raise ValueError(f"Unexpected fragment index {fragment_index}; expected 0 or 1")
    return np.frombuffer(payload, dtype=WIRE_DTYPE, offset=HEADER.size).reshape(SAMPLES_PER_PACKET, 4)


def complex_channels(samples):
    """Convert [I0,Q0,I1,Q1] rows to complex128 [channel 0, channel 1]."""
    return samples[:, 0::2].astype(np.float64) + 1j * samples[:, 1::2].astype(np.float64)

# class KeyReader:
#     """Read one key immediately, without requiring ENTER on Windows or Linux."""

#     def __enter__(self):
#         if sys.platform == "win32":
#             import msvcrt
#             self.msvcrt = msvcrt
#         else:
#             import select
#             import termios
#             import tty
#             self.select = select
#             self.termios = termios
#             self.fd = sys.stdin.fileno()
#             if not sys.stdin.isatty():
#                 raise RuntimeError("Run from an interactive terminal to use SPACE/ENTER.")
#             self.old_settings = termios.tcgetattr(self.fd)
#             tty.setcbreak(self.fd)
#         return self

#     def __exit__(self, *_args):
#         if sys.platform != "win32":
#             self.termios.tcsetattr(self.fd, self.termios.TCSADRAIN, self.old_settings)

#     def poll(self):
#         if sys.platform == "win32":
#             return self.msvcrt.getwch() if self.msvcrt.kbhit() else None
#         if self.select.select([sys.stdin], [], [], 0)[0]:
#             return sys.stdin.read(1)
#         return None

from queue import Queue, Empty


class KeyReader:
    """Jupyter-compatible KeyReader using buttons."""

    def __init__(self):
        import ipywidgets as widgets
        self.events = Queue()

        self.enter_button = widgets.Button(
            description="Finish Calibration",
            button_style="info"
        )

        self.space_button = widgets.Button(
            description="Record Position",
            button_style="success"
        )

        self.quit_button = widgets.Button(
            description="Stop",
            button_style="danger"
        )

        # Buttons simulate keyboard presses
        self.enter_button.on_click(
            lambda b: self.events.put("\n")
        )

        self.space_button.on_click(
            lambda b: self.events.put(" ")
        )

        self.quit_button.on_click(
            lambda b: self.events.put("q")
        )

        self.ui = widgets.HBox([
            self.enter_button,
            self.space_button,
            self.quit_button
        ])

    def show(self):
        from IPython.display import display
        display(self.ui)
        return self

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.enter_button.disabled = True
        self.space_button.disabled = True
        self.quit_button.disabled = True

    def poll(self):
        try:
            return self.events.get_nowait()
        except Empty:
            return None


class Magnetometer:
    def __init__(self, connection, debug=False):
        self.serial = connection
        self.debug = debug
        self.buffer = b""
        self.latest = None
        self.bytes_received = 0
        self.invalid_lines = 0
        self.last_raw_line = None

    def poll(self):
        """Nonblocking; returns new X,Y readings (may be several)."""
        count = self.serial.in_waiting
        if count:
            chunk = self.serial.read(count)
            self.bytes_received += len(chunk)
            self.buffer += chunk
            if self.debug:
                print(f"\nMAG RX ({len(chunk)} bytes): {chunk[:256]!r}", flush=True)
        if len(self.buffer) > 8192:
            self.buffer = self.buffer[-1024:]
        lines = self.buffer.split(b"\n")
        self.buffer = lines.pop()
        readings = []
        for line in lines:
            self.last_raw_line = line[:256]
            try:
                fields = line.decode("ascii", errors="ignore").strip().split(",")
                if len(fields) != 2:
                    self.invalid_lines += 1
                    continue
                xy = np.array((float(fields[0]), float(fields[1])), dtype=float)
                if np.all(np.isfinite(xy)):
                    self.latest = xy
                    readings.append(xy)
                else:
                    self.invalid_lines += 1
            except ValueError:
                self.invalid_lines += 1
        return readings


def fit_ellipse(readings):
    """Same 2D hard-iron/soft-iron ellipse fit as magnetometer_calibration.py."""
    p = np.asarray(readings, dtype=float)
    if len(p) < 40 or min(np.ptp(p, axis=0)) < 5.0:
        raise ValueError("Need >=40 samples spanning a full level 360-degree rotation.")
    span = np.ptp(p, axis=0)
    midpoint = (p.max(axis=0) + p.min(axis=0)) / 2
    scale = float(np.mean(span) / 2)
    u, v = ((p - midpoint) / scale).T
    design = np.column_stack((u*u, 2*u*v, v*v, u, v))
    (a, b, c, d, e), _, rank, _ = np.linalg.lstsq(design, np.ones(len(p)), rcond=None)
    if rank < 5:
        raise ValueError("Rotate through more different orientations.")
    quad = np.array([[a, b], [b, c]], dtype=float)
    if np.min(np.linalg.eigvalsh(quad)) <= 0:
        raise ValueError("Readings do not form a valid ellipse.")
    center0 = -0.5 * np.linalg.solve(quad, [d, e])
    factor = 1.0 + center0 @ quad @ center0
    if factor <= 0:
        raise ValueError("Invalid ellipse fit.")
    eigenvals, axes = np.linalg.eigh(quad / factor)
    correction = (axes @ np.diag(np.sqrt(eigenvals)) @ axes.T) / scale
    center = midpoint + scale * center0
    return center, correction


def magnetic_angle(xy, center, correction):
    corrected = correction @ (xy - center)
    angle = math.degrees(math.atan2(corrected[1], corrected[0]))
    return angle


def circular_stats(degrees):
    """Circular mean and standard deviation, both in degrees."""
    if not degrees:
        return float("nan"), float("nan")
    phasors = np.exp(1j * np.deg2rad(degrees))
    avg = np.mean(phasors)
    mean = math.degrees(np.angle(avg)) % 360.0
    if math.isclose(mean, 360.0, abs_tol=1e-9):
        mean = 0.0
    std = math.degrees(math.sqrt(max(0.0, -2.0 * math.log(max(abs(avg), 1e-12)))))
    return mean, std


def calibrate_magnetometer(mag, keys, service=None):
    print("\nMAGNETOMETER CALIBRATION")
    print("Keep the sensor level and rotate 3-5 full turns.")
    print("Hold it at your desired 0-degree direction, then press ENTER.\n")
    readings = []
    last_status = 0.0
    last_valid = time.monotonic()
    last_warning = last_valid
    while True:
        new_readings = mag.poll()
        readings.extend(new_readings)
        now = time.monotonic()
        if new_readings:
            last_valid = now
        if service is not None:
            service()  # Keep direct DMA captures moving while the sensor rotates.
        key = keys.poll()
        if key and key.lower() == "q":
            raise KeyboardInterrupt
        if key in ("\r", "\n"):
            try:
                center, correction = fit_ellipse(readings)
            except (ValueError, np.linalg.LinAlgError) as exc:
                print(f"\n{exc} Continue rotating, then press ENTER again.")
                continue
            if mag.latest is None:
                continue
            zero = magnetic_angle(mag.latest, center, correction)
            return center, correction, zero
        now = time.monotonic()
        if now - last_status > 0.5:
            print(f"\rMagnetometer calibration readings: {len(readings):5d}  ", end="", flush=True)
            last_status = now
        if now - last_valid >= 3.0 and now - last_warning >= 3.0:
            print(f"\nNo valid magnetometer X,Y readings for {now-last_valid:.1f}s. "
                  f"Total serial bytes={getattr(mag, 'bytes_received', 'unknown')}; "
                  f"invalid lines={getattr(mag, 'invalid_lines', 'unknown')}; "
                  f"last line={getattr(mag, 'last_raw_line', None)!r}", flush=True)
            last_warning = now
        time.sleep(0.01)


def phase_correlation(packet):
    """Sum conj(ch0)*ch1; phase is channel 1 relative to channel 0."""
    samples = unpack_packet(packet)
    z = complex_channels(samples)
    a, b = z[:, 0], z[:, 1]
    return np.vdot(a, b), float(np.vdot(a, a).real), float(np.vdot(b, b).real)


def capture_position(sock, mag, center, correction, zero, seconds, keys=None):
    until = time.monotonic() + seconds
    corr = 0j
    p1 = p2 = 0.0
    packets = bad_packets = 0
    headings = []
    # 1-second correlation summaries help reveal phase changing during capture.
    one_sec_correlations = {}
    payload_buffer = bytearray(65535)  # Read the full UDP datagram before length checks.
    last_print = 0.0
    while time.monotonic() < until:
        if keys is not None:
            key = keys.poll()
            if key and key.lower() == "q":
                raise KeyboardInterrupt
        for xy in mag.poll():
            heading = (magnetic_angle(xy, center, correction) - zero) % 360.0
            headings.append(heading)

        got_packets = False
        for _ in range(256):
            if time.monotonic() >= until:
                break
            try:
                size, _addr = sock.recvfrom_into(payload_buffer)
            except BlockingIOError:
                break
            got_packets = True
            if size != DATAGRAM_BYTES:
                bad_packets += 1
                continue
            try:
                cross, power_a, power_b = phase_correlation(memoryview(payload_buffer)[:size])
            except ValueError:
                bad_packets += 1
                continue
            corr += cross
            p1 += power_a
            p2 += power_b
            packets += 1
            second = min(int(seconds), int(seconds - (until - time.monotonic())))
            one_sec_correlations[second] = one_sec_correlations.get(second, 0j) + cross

        now = time.monotonic()
        if now - last_print >= 1.0:
            heading_text = f"{headings[-1]:6.1f} deg" if headings else "waiting"
            phase = math.degrees(math.atan2(corr.imag, corr.real)) if packets else float("nan")
            print(f"\r  {max(0.0, until - now):4.1f}s remaining  "
                  f"heading={heading_text}  phase={phase:+7.2f} deg   packets={packets:6d}",
                  end="", flush=True)
            last_print = now
        if not got_packets:
            time.sleep(0.001)

    if not packets or not headings:
        raise RuntimeError(f"No {'UDP packets' if not packets else 'magnetometer readings'} captured.")

    heading, heading_std = circular_stats(headings)
    phase = math.degrees(math.atan2(corr.imag, corr.real))
    coherence = abs(corr) / math.sqrt(p1 * p2) if p1 > 0 and p2 > 0 else 0.0
    if len(one_sec_correlations) >= 2:
        sec_phases = np.angle(list(one_sec_correlations.values()))
        phase_error = np.rad2deg(np.angle(np.exp(1j * (sec_phases - np.angle(corr)))))
        phase_drift = float(np.max(np.abs(phase_error)))
    else:
        phase_drift = 0.0
    print()
    return {
        "phase_deg": phase,
        "angle_deg": heading,
        "angle_std_deg": heading_std,
        "phase_max_deviation_deg": phase_drift,
        "coherence": coherence,
        "packets": packets,
        "mag_samples": len(headings),
        "bad_packets": bad_packets,
    }


def drain_packets(sock):
    """Discard stale packets while waiting for the user to press SPACE."""
    discarded = 0
    buf = bytearray(65535)
    for _ in range(256):
        try:
            sock.recvfrom_into(buf)
        except BlockingIOError:
            break
        discarded += 1
    return discarded
