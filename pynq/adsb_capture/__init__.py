"""ZCU111/PYNQ capture package."""

from .adsb_decoder import (
    AdsbDetector,
    AircraftTracker,
    DetectionBatch,
    DetectionStats,
    decode_adsb_message,
    mode_s_crc,
)
from .iq_protocol import (
    IQ_SAMPLE_RATE_HZ,
    PL_DECIMATION,
    PL_DECIMATION_SELECT,
    RFDC_DECIMATION,
    RFDC_FABRIC_WORDS,
)

__all__ = [
    "AdsbCapture",
    "AdsbDetector",
    "AircraftTracker",
    "DetectionBatch",
    "DetectionStats",
    "IQ_SAMPLE_RATE_HZ",
    "PL_DECIMATION",
    "PL_DECIMATION_SELECT",
    "RFDC_DECIMATION",
    "RFDC_FABRIC_WORDS",
    "decode_adsb_message",
    "mode_s_crc",
    "unpack_iq",
]


def __getattr__(name):
    # Lazy board imports keep the shared protocol available on non-PYNQ hosts.
    if name in {"AdsbCapture", "unpack_iq"}:
        from .adsb_capture import AdsbCapture, unpack_iq

        return {"AdsbCapture": AdsbCapture, "unpack_iq": unpack_iq}[name]
    raise AttributeError(name)
