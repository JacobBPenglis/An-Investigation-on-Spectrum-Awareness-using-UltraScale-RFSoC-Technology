import numpy as np
import numpy.typing as npt
from queue import Queue
from datetime import datetime
from pathlib import Path
import config
import pyModeS as pms

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
            msg = np.packbits(payload_bits).tobytes().hex().upper()

            # Ignore signals with an invalid CRC
            if pms.crc(msg) != 0:
                return

            # Save signal to file
            with open(self.record_dir / "record.npy", "ab") as f:
                np.save(f, sample["timestamp"])
                np.save(f, sample["iq"])
            print(f"DF: {pms.adsb.df(msg)}, ICAO: {pms.adsb.icao(msg)}, Type Code: {pms.adsb.typecode(msg)}")