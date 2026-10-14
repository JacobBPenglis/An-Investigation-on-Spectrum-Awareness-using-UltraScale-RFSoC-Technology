import numpy as np
import numpy.typing as npt
from datetime import datetime
from pathlib import Path

class RecordingBuffer:
    def __init__(self):
        self.timestamp = datetime.now()
        self.noise_floor: float = 0
        self.buffer: list[npt.NDArray] = []
        self.record_dir = Path(__file__).parent.parent / "data"

    def set_noise_floor(self, noise_floor: float) -> None:
        self.noise_floor = noise_floor

    def append_window(self, window: npt.NDArray) -> None:
        if not self.buffer:
            self.timestamp = datetime.now()
        self.buffer.append(window.copy())

    def get_buffer(self) -> dict[str, datetime | float | npt.NDArray]:
        if len(self.buffer) > 1:
            return {"timestamp": self.timestamp, "noise_floor": self.noise_floor, "iq": np.concatenate(self.buffer)}
        return {"timestamp": self.timestamp, "noise_floor": self.noise_floor, "iq": self.buffer[0]}

    def clear_buffer(self) -> None:
        self.noise_floor = 0
        self.buffer.clear()