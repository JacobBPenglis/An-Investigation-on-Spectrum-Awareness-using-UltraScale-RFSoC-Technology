import numpy as np
import numpy.typing as npt
from datetime import datetime
from pathlib import Path

class RecordingBuffer:
    def __init__(self):
        self.buffer: list[npt.NDArray] = []
        self.timestamp = datetime.now()
        self.record_dir = Path(__file__).parent.parent / "data"

    def append_window(self, window: npt.NDArray) -> None:
        if not self.buffer:
            self.timestamp = datetime.now()
        self.buffer.append(window.copy())

    def get_buffer(self) -> dict[str, datetime | npt.NDArray]:
        if len(self.buffer) > 1:
            return {"timestamp": self.timestamp, "iq": np.concatenate(self.buffer)}
        return {"timestamp": self.timestamp, "iq": self.buffer[0]}

    def clear_buffer(self) -> None:
        self.buffer.clear()