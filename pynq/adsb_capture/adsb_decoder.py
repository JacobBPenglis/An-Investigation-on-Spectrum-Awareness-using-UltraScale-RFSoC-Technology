"""Pure-NumPy Mode S / ADS-B detection and decoding for PYNQ.

The detector consumes complex baseband I/Q samples.  It searches magnitude
squared for the 8 us Mode S preamble, demodulates the following 1 Mbit/s
pulse-position-modulated data and only returns CRC-valid DF17/DF18 extended
squitters by default.  No host-side service or third-party ADS-B package is
required.

At the overlay's 10 MSPS output rate, a 0.5 us PPM half-symbol is five
samples, the preamble is 80 samples and a 112-bit extended squitter occupies
1,200 samples including its preamble.
"""

from __future__ import annotations

import math
import time
from dataclasses import asdict, dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np


MODE_S_POLYNOMIAL = 0xFFF409
MODE_S_PREAMBLE_US = 8.0
MODE_S_BIT_US = 1.0
MODE_S_LONG_BITS = 112
MODE_S_SHORT_BITS = 56

# Six-bit ADS-B callsign alphabet.  Underscore is transmitted as a space.
_CALLSIGN_CHARSET = (
    "#ABCDEFGHIJKLMNOPQRSTUVWXYZ#####_###############0123456789######"
)


@dataclass(frozen=True)
class DetectionStats:
    """Measurements from one detector call."""

    samples: int
    signal_duration_s: float
    processing_elapsed_s: float
    noise_power: float
    preamble_candidates: int
    crc_rejected: int
    accepted_messages: int
    candidate_samples: Tuple[int, ...]

    @property
    def realtime_headroom(self) -> float:
        """Signal duration divided by processing time (greater than one is good)."""
        if self.processing_elapsed_s <= 0:
            return math.inf
        return self.signal_duration_s / self.processing_elapsed_s

    def as_dict(self) -> Dict[str, object]:
        result = asdict(self)
        result["realtime_headroom"] = self.realtime_headroom
        return result


@dataclass(frozen=True)
class DetectionBatch:
    """Decoded messages and timing statistics for one I/Q frame."""

    messages: Tuple[Dict[str, object], ...]
    stats: DetectionStats


def mode_s_crc(message: bytes) -> int:
    """Return the 24-bit Mode S polynomial remainder for a complete message.

    A CRC-protected DF17 or DF18 message is valid when the returned remainder
    is zero.  The function accepts the complete 7-byte or 14-byte message,
    including its transmitted parity field.
    """
    remainder = 0
    for byte in message:
        for shift in range(7, -1, -1):
            incoming = (byte >> shift) & 1
            top = (remainder >> 23) & 1
            remainder = ((remainder << 1) & 0xFFFFFF) | incoming
            if top:
                remainder ^= MODE_S_POLYNOMIAL
    return remainder


def _bits_from_bytes(message: bytes) -> np.ndarray:
    return np.unpackbits(np.frombuffer(message, dtype=np.uint8))


def _uint(bits: np.ndarray, start: int, stop: int) -> int:
    value = 0
    for bit in bits[start:stop]:
        value = (value << 1) | int(bit)
    return value


def _decode_altitude_12(code: int) -> Optional[int]:
    """Decode a 12-bit ADS-B barometric altitude when the Q bit is set."""
    if not (code & 0x10):
        # Gillham/Gray-code altitude is intentionally left undecoded.  Modern
        # extended squitters normally set Q and use 25 ft increments.
        return None
    n_value = ((code & 0xFE0) >> 1) | (code & 0x0F)
    return n_value * 25 - 1000


def _decode_callsign(me: np.ndarray) -> str:
    chars = []
    for start in range(8, 56, 6):
        value = _uint(me, start, start + 6)
        chars.append(_CALLSIGN_CHARSET[value])
    return "".join(chars).replace("_", " ").replace("#", "").strip()


def _decode_velocity(me: np.ndarray) -> Dict[str, object]:
    result: Dict[str, object] = {"velocity_subtype": _uint(me, 5, 8)}
    subtype = int(result["velocity_subtype"])
    scale = 1 if subtype in (1, 3) else 4

    if subtype in (1, 2):
        east_west_raw = _uint(me, 14, 24)
        north_south_raw = _uint(me, 25, 35)
        if east_west_raw and north_south_raw:
            east_west = (east_west_raw - 1) * scale
            north_south = (north_south_raw - 1) * scale
            if int(me[13]):
                east_west = -east_west
            if int(me[24]):
                north_south = -north_south
            result["ground_speed_kt"] = round(
                math.hypot(east_west, north_south), 1
            )
            result["track_deg"] = round(
                math.degrees(math.atan2(east_west, north_south)) % 360.0,
                1,
            )
    elif subtype in (3, 4):
        if int(me[13]):
            result["heading_deg"] = round(
                _uint(me, 14, 24) * 360.0 / 1024.0,
                1,
            )
        airspeed_raw = _uint(me, 25, 35)
        if airspeed_raw:
            result["airspeed_kt"] = (airspeed_raw - 1) * scale
            result["airspeed_type"] = "TAS" if int(me[24]) else "IAS"

    vertical_rate_raw = _uint(me, 37, 46)
    if vertical_rate_raw:
        vertical_rate = (vertical_rate_raw - 1) * 64
        if int(me[36]):
            vertical_rate = -vertical_rate
        result["vertical_rate_fpm"] = vertical_rate
        result["vertical_rate_source"] = "barometric" if int(me[35]) else "GNSS"

    return result


def decode_adsb_message(message: bytes) -> Dict[str, object]:
    """Decode commonly useful fields from one Mode S extended squitter."""
    if len(message) not in (7, 14):
        raise ValueError("Mode S messages must contain 7 or 14 bytes")

    bits = _bits_from_bytes(message)
    downlink_format = _uint(bits, 0, 5)
    result: Dict[str, object] = {
        "raw": message.hex().upper(),
        "df": downlink_format,
        "crc_ok": mode_s_crc(message) == 0,
        "parity": message[-3:].hex().upper(),
    }

    if len(message) != 14 or downlink_format not in (17, 18):
        return result

    result["address"] = message[1:4].hex().upper()
    if downlink_format == 17:
        result["capability"] = int(bits[5]) * 4 + int(bits[6]) * 2 + int(bits[7])
    else:
        result["control_field"] = _uint(bits, 5, 8)

    me = bits[32:88]
    type_code = _uint(me, 0, 5)
    result["type_code"] = type_code

    if 1 <= type_code <= 4:
        category = _uint(me, 5, 8)
        result["callsign"] = _decode_callsign(me)
        result["emitter_category"] = f"{chr(ord('A') + 4 - type_code)}{category}"

    elif 5 <= type_code <= 8:
        result.update(
            {
                "position_type": "surface",
                "cpr_odd": bool(me[21]),
                "cpr_lat": _uint(me, 22, 39),
                "cpr_lon": _uint(me, 39, 56),
            }
        )

    elif 9 <= type_code <= 18:
        altitude_code = _uint(me, 8, 20)
        result.update(
            {
                "position_type": "airborne_barometric",
                "altitude_code": altitude_code,
                "altitude_ft": _decode_altitude_12(altitude_code),
                "cpr_odd": bool(me[21]),
                "cpr_lat": _uint(me, 22, 39),
                "cpr_lon": _uint(me, 39, 56),
            }
        )

    elif type_code == 19:
        result.update(_decode_velocity(me))

    elif 20 <= type_code <= 22:
        result.update(
            {
                "position_type": "airborne_gnss_height",
                "height_code": _uint(me, 8, 20),
                "cpr_odd": bool(me[21]),
                "cpr_lat": _uint(me, 22, 39),
                "cpr_lon": _uint(me, 39, 56),
            }
        )

    return result


def _cpr_nl(latitude_deg: float) -> int:
    latitude = abs(float(latitude_deg))
    if latitude >= 87.0:
        return 1
    numerator = 1.0 - math.cos(math.pi / 30.0)
    denominator = math.cos(math.radians(latitude)) ** 2
    argument = 1.0 - numerator / denominator
    argument = min(1.0, max(-1.0, argument))
    return max(1, int(math.floor(2.0 * math.pi / math.acos(argument))))


def decode_airborne_cpr(
    even: Tuple[int, int, int],
    odd: Tuple[int, int, int],
    max_pair_age_s: float = 10.0,
) -> Optional[Tuple[float, float]]:
    """Globally decode an airborne CPR even/odd pair.

    Each tuple contains ``(encoded_latitude, encoded_longitude, timestamp_ns)``.
    The newer frame determines the returned longitude zone.
    """
    even_lat, even_lon, even_time_ns = even
    odd_lat, odd_lon, odd_time_ns = odd
    if abs(even_time_ns - odd_time_ns) > max_pair_age_s * 1e9:
        return None

    lat_even = even_lat / 131072.0
    lat_odd = odd_lat / 131072.0
    lon_even = even_lon / 131072.0
    lon_odd = odd_lon / 131072.0

    latitude_index = math.floor(59.0 * lat_even - 60.0 * lat_odd + 0.5)
    resolved_even = 6.0 * ((latitude_index % 60) + lat_even)
    resolved_odd = (360.0 / 59.0) * ((latitude_index % 59) + lat_odd)
    if resolved_even >= 270.0:
        resolved_even -= 360.0
    if resolved_odd >= 270.0:
        resolved_odd -= 360.0
    if _cpr_nl(resolved_even) != _cpr_nl(resolved_odd):
        return None

    longitude_index = math.floor(
        lon_even * (_cpr_nl(resolved_even) - 1)
        - lon_odd * _cpr_nl(resolved_even)
        + 0.5
    )
    if even_time_ns >= odd_time_ns:
        latitude = resolved_even
        zones = max(_cpr_nl(latitude), 1)
        longitude = (360.0 / zones) * ((longitude_index % zones) + lon_even)
    else:
        latitude = resolved_odd
        zones = max(_cpr_nl(latitude) - 1, 1)
        longitude = (360.0 / zones) * ((longitude_index % zones) + lon_odd)
    if longitude > 180.0:
        longitude -= 360.0
    return latitude, longitude


class AircraftTracker:
    """Maintain a small in-memory aircraft table from decoded messages."""

    def __init__(self, cpr_pair_age_s: float = 10.0) -> None:
        self.cpr_pair_age_s = float(cpr_pair_age_s)
        self._aircraft: Dict[str, Dict[str, object]] = {}

    def update(self, message: Dict[str, object]) -> Optional[Dict[str, object]]:
        address = message.get("address")
        if not address:
            return None
        address = str(address)
        timestamp_ns = int(message.get("timestamp_ns", time.time_ns()))
        state = self._aircraft.setdefault(
            address,
            {"address": address, "messages": 0},
        )
        state["messages"] = int(state["messages"]) + 1
        state["last_seen_ns"] = timestamp_ns

        copy_fields = (
            "df",
            "callsign",
            "emitter_category",
            "altitude_ft",
            "ground_speed_kt",
            "track_deg",
            "heading_deg",
            "airspeed_kt",
            "airspeed_type",
            "vertical_rate_fpm",
            "type_code",
        )
        for field in copy_fields:
            if message.get(field) is not None:
                state[field] = message[field]

        if (
            message.get("position_type") == "airborne_barometric"
            and message.get("cpr_lat") is not None
            and message.get("cpr_lon") is not None
        ):
            cpr_value = (
                int(message["cpr_lat"]),
                int(message["cpr_lon"]),
                timestamp_ns,
            )
            key = "_cpr_odd" if message.get("cpr_odd") else "_cpr_even"
            state[key] = cpr_value
            if "_cpr_even" in state and "_cpr_odd" in state:
                position = decode_airborne_cpr(
                    state["_cpr_even"],
                    state["_cpr_odd"],
                    max_pair_age_s=self.cpr_pair_age_s,
                )
                if position is not None:
                    state["latitude_deg"] = round(position[0], 6)
                    state["longitude_deg"] = round(position[1], 6)

        return self._public_state(state)

    @staticmethod
    def _public_state(state: Dict[str, object]) -> Dict[str, object]:
        return {key: value for key, value in state.items() if not key.startswith("_")}

    def rows(
        self,
        max_age_s: Optional[float] = 60.0,
        now_ns: Optional[int] = None,
    ) -> List[Dict[str, object]]:
        if now_ns is None:
            now_ns = time.time_ns()
        rows = []
        for state in self._aircraft.values():
            age_s = (now_ns - int(state["last_seen_ns"])) / 1e9
            if max_age_s is not None and age_s > max_age_s:
                continue
            row = self._public_state(state)
            row["age_s"] = max(0.0, age_s)
            rows.append(row)
        rows.sort(key=lambda row: float(row["age_s"]))
        return rows


class AdsbDetector:
    """Detect and decode CRC-valid extended squitters from one I/Q frame."""

    def __init__(
        self,
        sample_rate_hz: float,
        min_preamble_snr_db: float = 6.0,
        min_preamble_contrast_db: float = 3.0,
        edge_ratio: float = 1.20,
        min_median_bit_confidence: float = 0.04,
        accepted_formats: Sequence[int] = (17, 18),
    ) -> None:
        self.sample_rate_hz = float(sample_rate_hz)
        self.half_samples = int(round(self.sample_rate_hz * 0.5e-6))
        if self.half_samples < 1:
            raise ValueError("sample_rate_hz must provide at least one sample per 0.5 us")
        effective_rate = self.half_samples / 0.5e-6
        if not math.isclose(self.sample_rate_hz, effective_rate, rel_tol=0, abs_tol=1.0):
            raise ValueError(
                "sample_rate_hz must contain an integer number of samples per 0.5 us"
            )
        self.bit_samples = 2 * self.half_samples
        self.preamble_samples = 16 * self.half_samples
        self.min_preamble_snr_ratio = 10.0 ** (min_preamble_snr_db / 10.0)
        self.min_preamble_contrast_ratio = 10.0 ** (
            min_preamble_contrast_db / 10.0
        )
        self.edge_ratio = float(edge_ratio)
        self.min_median_bit_confidence = float(min_median_bit_confidence)
        self.accepted_formats = tuple(int(value) for value in accepted_formats)

    def _half_symbol_energy(self, power: np.ndarray) -> np.ndarray:
        integral = np.empty(power.size + 1, dtype=np.float64)
        integral[0] = 0.0
        np.cumsum(power, dtype=np.float64, out=integral[1:])
        energy = np.empty(power.size - self.half_samples + 1, dtype=np.float32)
        np.subtract(
            integral[self.half_samples :],
            integral[: -self.half_samples],
            out=energy,
            casting="unsafe",
        )
        energy /= self.half_samples
        return energy

    def _decode_bits(
        self,
        half_energy: np.ndarray,
        message_start: int,
        bit_count: int,
        noise_power: float,
    ) -> Tuple[np.ndarray, float]:
        data_start = message_start + self.preamble_samples
        indices = data_start + np.arange(bit_count) * self.bit_samples
        first = half_energy[indices]
        second = half_energy[indices + self.half_samples]
        bits = first > second
        confidence = np.abs(first - second) / (
            first + second + 2.0 * noise_power + np.finfo(np.float32).tiny
        )
        return bits.astype(np.uint8), float(np.median(confidence))

    def _try_candidate(
        self,
        half_energy: np.ndarray,
        candidate: int,
        sample_count: int,
        noise_power: float,
    ) -> Optional[Tuple[bytes, int, float]]:
        best: Optional[Tuple[bytes, int, float]] = None
        # Check a complete half-symbol around the preamble peak.  This absorbs
        # fractional timing, filter ringing and a neighbouring correlation
        # sample winning the preamble score.
        radius = self.half_samples
        offsets = sorted(range(-radius, radius + 1), key=lambda value: abs(value))
        for offset in offsets:
            start = candidate + offset
            if start < 0:
                continue
            prefix_end = start + self.preamble_samples + 5 * self.bit_samples
            if prefix_end > sample_count:
                continue
            prefix, _ = self._decode_bits(
                half_energy, start, 5, noise_power
            )
            downlink_format = _uint(prefix, 0, 5)
            bit_count = MODE_S_LONG_BITS if downlink_format >= 16 else MODE_S_SHORT_BITS
            message_end = start + self.preamble_samples + bit_count * self.bit_samples
            if message_end > sample_count:
                continue
            bits, confidence = self._decode_bits(
                half_energy, start, bit_count, noise_power
            )
            message = np.packbits(bits).tobytes()
            if (
                downlink_format in self.accepted_formats
                and mode_s_crc(message) == 0
                and confidence >= self.min_median_bit_confidence
            ):
                if best is None or confidence > best[2]:
                    best = (message, start, confidence)
        return best

    def detect(
        self,
        iq: np.ndarray,
        frame_start_ns: Optional[int] = None,
    ) -> DetectionBatch:
        """Detect messages in one complex frame.

        ``frame_start_ns`` is an approximate capture-start Unix timestamp.  If
        supplied, each returned message receives a timestamp corrected by its
        sample offset within the frame.
        """
        started = time.monotonic()
        samples = np.asarray(iq)
        if samples.ndim != 1:
            raise ValueError("iq must be a one-dimensional sample array")
        power = np.abs(samples).astype(np.float32, copy=False)
        power = np.square(power)
        sample_count = int(power.size)
        signal_duration_s = sample_count / self.sample_rate_hz
        minimum_samples = (
            self.preamble_samples + MODE_S_SHORT_BITS * self.bit_samples
        )
        if sample_count < minimum_samples:
            elapsed = time.monotonic() - started
            stats = DetectionStats(
                sample_count,
                signal_duration_s,
                elapsed,
                float(np.median(power)) if sample_count else 0.0,
                0,
                0,
                0,
                (),
            )
            return DetectionBatch((), stats)

        noise_power = max(float(np.median(power)), np.finfo(np.float32).tiny)
        half_energy = self._half_symbol_energy(power)
        candidate_count = sample_count - minimum_samples + 1
        bins = [
            half_energy[offset : offset + candidate_count]
            for offset in range(0, self.preamble_samples, self.half_samples)
        ]

        pulse_mean = (bins[0] + bins[2] + bins[7] + bins[9]) * 0.25
        quiet_mean = (
            bins[1]
            + bins[3]
            + bins[4]
            + bins[5]
            + bins[6]
            + bins[8]
            + bins[10]
            + bins[11]
            + bins[12]
            + bins[13]
            + bins[14]
            + bins[15]
        ) / 12.0
        contrast = pulse_mean / (quiet_mean + np.finfo(np.float32).tiny)
        structure = (
            (bins[0] > self.edge_ratio * bins[1])
            & (bins[2] > self.edge_ratio * bins[1])
            & (bins[2] > self.edge_ratio * bins[3])
            & (bins[7] > self.edge_ratio * bins[6])
            & (bins[7] > self.edge_ratio * bins[8])
            & (bins[9] > self.edge_ratio * bins[8])
            & (bins[9] > self.edge_ratio * bins[10])
        )
        candidate_mask = (
            structure
            & (pulse_mean >= noise_power * self.min_preamble_snr_ratio)
            & (contrast >= self.min_preamble_contrast_ratio)
        )
        raw_candidates = np.flatnonzero(candidate_mask)

        candidates: List[int] = []
        if raw_candidates.size:
            split_points = np.flatnonzero(
                np.diff(raw_candidates) > self.half_samples
            ) + 1
            for group in np.split(raw_candidates, split_points):
                best_index = int(group[np.argmax(contrast[group])])
                candidates.append(best_index)

        messages: List[Dict[str, object]] = []
        evaluated_candidates: List[int] = []
        rejected = 0
        skip_before = -1
        for candidate in candidates:
            if candidate < skip_before:
                continue
            evaluated_candidates.append(candidate)
            decoded = self._try_candidate(
                half_energy,
                candidate,
                sample_count,
                noise_power,
            )
            if decoded is None:
                rejected += 1
                continue
            message_bytes, message_start, confidence = decoded
            message = decode_adsb_message(message_bytes)
            pulse_value = float(pulse_mean[candidate])
            quiet_value = max(float(quiet_mean[candidate]), np.finfo(np.float32).tiny)
            message.update(
                {
                    "sample_index": message_start,
                    "preamble_snr_db": round(
                        10.0 * math.log10(pulse_value / noise_power), 2
                    ),
                    "preamble_contrast_db": round(
                        10.0 * math.log10(pulse_value / quiet_value), 2
                    ),
                    "median_bit_confidence": round(confidence, 4),
                }
            )
            if frame_start_ns is not None:
                message["timestamp_ns"] = int(
                    frame_start_ns
                    + round(message_start / self.sample_rate_hz * 1e9)
                )
            messages.append(message)
            skip_before = (
                message_start
                + self.preamble_samples
                + len(message_bytes) * 8 * self.bit_samples
            )

        elapsed = time.monotonic() - started
        stats = DetectionStats(
            samples=sample_count,
            signal_duration_s=signal_duration_s,
            processing_elapsed_s=elapsed,
            noise_power=noise_power,
            preamble_candidates=len(evaluated_candidates),
            crc_rejected=rejected,
            accepted_messages=len(messages),
            candidate_samples=tuple(evaluated_candidates),
        )
        return DetectionBatch(tuple(messages), stats)


def update_tracker(
    tracker: AircraftTracker,
    messages: Iterable[Dict[str, object]],
) -> None:
    """Apply a sequence of decoder outputs to an ``AircraftTracker``."""
    for message in messages:
        tracker.update(message)
