"""ZCU111/PYNQ capture package."""

from .iq_protocol import (
    EXPECTED_OUTPUT_VALID_INTERVAL,
    EXPECTED_AXIS_CLOCKS_PER_MS,
    HARDWARE_BUILD_ID,
    IQ_SAMPLE_RATE_HZ,
    PL_DECIMATION,
    PL_DECIMATION_SELECT,
    RFDC_DECIMATION,
    RFDC_FABRIC_WORDS,
    RFDC_FABRIC_CLOCK_HZ,
)

__all__ = [
    "AdsbCapture",
    "EXPECTED_OUTPUT_VALID_INTERVAL",
    "EXPECTED_AXIS_CLOCKS_PER_MS",
    "HARDWARE_BUILD_ID",
    "IQ_SAMPLE_RATE_HZ",
    "PL_DECIMATION",
    "PL_DECIMATION_SELECT",
    "RFDC_DECIMATION",
    "RFDC_FABRIC_WORDS",
    "RFDC_FABRIC_CLOCK_HZ",
    "unpack_iq",
]


def __getattr__(name):
    # Lazy board imports keep the shared protocol available on non-PYNQ hosts.
    if name in {"AdsbCapture", "unpack_iq"}:
        from .adsb_capture import AdsbCapture, unpack_iq

        return {"AdsbCapture": AdsbCapture, "unpack_iq": unpack_iq}[name]
    raise AttributeError(name)
