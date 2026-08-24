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
    EXPECTED_OUTPUT_VALID_INTERVAL,
    EXPECTED_AXIS_CLOCKS_PER_MS,
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
)

__all__ = [
    "AdsbCapture",
    "AdsbDetector",
    "AircraftTracker",
    "DetectionBatch",
    "DetectionStats",
    "EXPECTED_OUTPUT_VALID_INTERVAL",
    "EXPECTED_AXIS_CLOCKS_PER_MS",
    "HARDWARE_BUILD_ID",
    "IQ_SAMPLE_RATE_HZ",
    "LEGACY_HARDWARE_BUILD_ID",
    "PL_DECIMATION",
    "PL_DECIMATOR_KIND",
    "PL_DECIMATION_SELECT",
    "PL_FIR_INSTANCE_NAMES",
    "RFDC_DECIMATION",
    "RFDC_FABRIC_WORDS",
    "RFDC_FABRIC_CLOCK_HZ",
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
