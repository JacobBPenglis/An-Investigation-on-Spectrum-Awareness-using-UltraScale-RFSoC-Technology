"""Host-side receiver for UDP I/Q frames."""

from __future__ import annotations

import argparse
import json
import socket
from pathlib import Path

try:
    from .iq_protocol import IQ_SAMPLE_RATE_HZ, UDP_HEADER, UDP_MAGIC
except ImportError:  # Allow direct execution on the host.
    from iq_protocol import IQ_SAMPLE_RATE_HZ, UDP_HEADER, UDP_MAGIC


def receive(bind: str, port: int, output: Path, frame_limit: int) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    completed = 0
    current_frame = None
    expected_packet = 0
    frame_packets = 0
    dropped_packets = 0
    first_timestamp_ns = None

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock, output.open("wb") as fh:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
        sock.bind((bind, port))
        while completed < frame_limit:
            packet, _ = sock.recvfrom(1472)
            if len(packet) < UDP_HEADER.size:
                continue
            magic, frame_id, packet_id, total_packets, timestamp_ns = UDP_HEADER.unpack_from(packet)
            if magic != UDP_MAGIC:
                continue

            if current_frame != frame_id:
                if current_frame is not None and expected_packet != frame_packets:
                    dropped_packets += frame_packets - expected_packet
                current_frame = frame_id
                expected_packet = 0
                frame_packets = total_packets
                if first_timestamp_ns is None:
                    first_timestamp_ns = timestamp_ns

            if packet_id != expected_packet:
                # Missing packet positions are zero-filled to retain timing.
                # The JSON metadata records the missing-packet count.
                missing = max(0, packet_id - expected_packet)
                fh.write(bytes(1024 * missing))
                dropped_packets += missing
            fh.write(packet[UDP_HEADER.size :])
            expected_packet = packet_id + 1

            if packet_id + 1 == total_packets:
                completed += 1
                current_frame = None
                expected_packet = 0

    metadata = {
        "format": "little-endian signed int16 interleaved I,Q",
        "sample_rate_hz": IQ_SAMPLE_RATE_HZ,
        "frames": completed,
        "dropped_udp_packets": dropped_packets,
        "first_board_timestamp_unix_ns": first_timestamp_ns,
    }
    output.with_suffix(output.suffix + ".json").write_text(
        json.dumps(metadata, indent=2) + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Receive ZCU111 IQ UDP frames")
    parser.add_argument("output", type=Path)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=50000)
    parser.add_argument("--frames", type=int, default=100)
    args = parser.parse_args()
    receive(args.bind, args.port, args.output, args.frames)
