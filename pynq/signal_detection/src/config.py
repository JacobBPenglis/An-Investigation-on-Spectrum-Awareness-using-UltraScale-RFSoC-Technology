from enum import Enum
import numpy as np
import numpy.typing as npt

class producer(Enum):
    FILE = 0
    ZCU111 = 1
    PLUTO_SDR = 2
    BLADE_RF = 3

mode: producer = producer.FILE

fs: float = 2e6
fs_mult: int = 5
bandwidth: float = 2e6
f: float = 1090e6
sig_len: int = 120e-6 * fs * fs_mult
preamble_mask: npt.NDArray = np.array(
    [True,False,True,False,False,False,False,True,False,True,False,False,False,False,False,False],
    dtype=bool
)
df_mask: npt.NDArray = np.array(
    [True,False,False,False,True],
    dtype=bool
)


BUFFER_SIZE: int = 262144
READ_BLOCK_SIZE: int = 8192
WINDOW_SIZE: int = 2048
OVERLAP: int = int(WINDOW_SIZE/4)
STEP: int = WINDOW_SIZE - OVERLAP

POWER_THRESH_DB: int = 4
CORRELATION_STD_THRESH: int = 3.5