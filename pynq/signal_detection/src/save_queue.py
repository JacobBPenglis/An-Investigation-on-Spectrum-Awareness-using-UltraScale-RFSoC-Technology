import numpy as np
import numpy.typing as npt
from queue import Queue
from datetime import datetime
from pathlib import Path
from config import config
from pyModeS import decode

class SaveQueue:
    def __init__(self):
        self.queue: Queue[dict[str, datetime | npt.NDArray]] = Queue()
        self.record_dir = Path(__file__).parent.parent / "data"

    def enqueue(self, sample: dict[str, datetime | npt.NDArray]) -> None:
        # Add new sample to the save queue
        self.queue.put(sample)

    def dequeue_and_save(self) -> None:
        # Save first element in queue
        sample = self.queue.get()

        if len(sample["iq"]) == config.sig_len:
            # Decode signal
            mag = np.abs(sample["iq"])
            payload = mag.reshape(-1, config.fs_mult).mean(axis=1)[16:]
            payload_bits = payload[0::2] > payload[1::2]
            hex_str = np.packbits(payload_bits).tobytes().hex().upper()
            message = decode(hex_str)

            if message.df == 17:
                with open(self.record_dir / "df17_record.npy", "ab") as f:
                    np.save(f, sample["timestamp"])
                    np.save(f, sample["iq"])
                print(message)
                return

        # with open(self.record_dir / "record.npy", "ab") as f:
        #     np.save(f, sample["timestamp"])
        #     np.save(f, sample["iq"])
        # print("Buffer of size", len(sample["iq"]), "recorded")