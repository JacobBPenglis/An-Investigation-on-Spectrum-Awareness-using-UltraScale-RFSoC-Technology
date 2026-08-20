from dataclasses import dataclass
import numpy as np
import numpy.typing as npt

@dataclass
class Config:
    fs: float = 2e6
    fs_mult: int = 4
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


    BUFFER_SIZE: int = 65536
    READ_BLOCK_SIZE: int = 8192
    WINDOW_SIZE: int = 512
    OVERLAP: int = WINDOW_SIZE/2
    STEP: int = WINDOW_SIZE - OVERLAP

    POWER_THRESH: int = 32
    CORRELATION_STD_THRESH: int = 4

config = Config()