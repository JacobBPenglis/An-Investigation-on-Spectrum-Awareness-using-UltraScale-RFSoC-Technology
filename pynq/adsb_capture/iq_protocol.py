"""Rates and UDP values shared by the board and host."""

import struct

ADC_SAMPLE_RATE_HZ = 2_560_000_000
RFDC_DECIMATION = 8
RFDC_FABRIC_WORDS = 2
RFDC_FABRIC_CLOCK_HZ = 160_000_000
PL_DECIMATION = 32
# The current block design uses fixed FIR Compiler instances for I and Q.
# Retain the legacy selector name as ``None`` so older notebooks fail visibly
# rather than writing to an AXI-Lite block that no longer exists.
PL_DECIMATION_SELECT = None
PL_DECIMATOR_KIND = "fir_compiler_fixed_32"
PL_FIR_INSTANCE_NAMES = ("JACOBS_FIR_I", "JACOBS_FIR_Q")
IQ_SAMPLE_RATE_HZ = ADC_SAMPLE_RATE_HZ // (RFDC_DECIMATION * PL_DECIMATION)
LEGACY_HARDWARE_BUILD_ID = 0xA833
HARDWARE_BUILD_ID = 0xA834
EXPECTED_OUTPUT_VALID_INTERVAL = PL_DECIMATION // RFDC_FABRIC_WORDS
EXPECTED_AXIS_CLOCKS_PER_MS = RFDC_FABRIC_CLOCK_HZ // 1000

UDP_MAGIC = b"IQ10"
UDP_HEADER = struct.Struct("!4sIIIQ")
UDP_IQ_BYTES = 1024
