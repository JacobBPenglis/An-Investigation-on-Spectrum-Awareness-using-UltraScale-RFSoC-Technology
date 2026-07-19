"""ZCU111/PYNQ capture package."""

from .iq_protocol import IQ_SAMPLE_RATE_HZ

__all__ = ["AdsbCapture", "IQ_SAMPLE_RATE_HZ", "unpack_iq"]


def __getattr__(name):
    # Lazy board imports keep the shared protocol available on non-PYNQ hosts.
    if name in {"AdsbCapture", "unpack_iq"}:
        from .adsb_capture import AdsbCapture, unpack_iq

        return {"AdsbCapture": AdsbCapture, "unpack_iq": unpack_iq}[name]
    raise AttributeError(name)
