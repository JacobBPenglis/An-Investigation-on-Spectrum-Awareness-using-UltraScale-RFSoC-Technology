import numpy as np
import numpy.typing as npt
from queue import Queue
from datetime import datetime
from pathlib import Path
import config
import pyModeS as pms

class SaveQueue:
    def __init__(self):
        self.queue: Queue[dict[str, datetime | float | npt.NDArray]] = Queue()
        self.record_dir = Path(__file__).parent.parent / "data"
        self.active = True
        self.count = 0

    def enqueue(self, sample: dict[str, datetime | float | npt.NDArray]) -> None:
        # Add new sample to the save queue
        self.queue.put(sample)

    def dequeue_and_save(self) -> None:
        # Save first element in queue
        try:
            sample = self.queue.get(timeout=1)
        except:
            return

        if len(sample["iq"]) == config.sig_len:
            # Decode signal
            mag = np.abs(sample["iq"])
            snr: float = 0
            payload = mag.reshape(-1, config.fs_mult).mean(axis=1)[len(config.preamble_mask):]
            payload_bits = payload[0::2] > payload[1::2]
            msg = np.packbits(payload_bits).tobytes().hex().upper()

            # Ignore signals with an invalid CRC
            if pms.crc(msg) != 0:
                return

            # Save signal to file
            filename = "6_bladeRF_record.npy"
            if config.mode == config.producer.FILE:
                filename = "test_record.npy"
            with open(self.record_dir / filename, "ab") as f:
                np.save(f, sample["timestamp"])
                np.save(f, sample["noise_floor"])
                np.save(f, sample["iq"])

            if sample["noise_floor"] > 0:
                total_power = np.mean(mag**2)
                noise_power = sample["noise_floor"]**2
                snr_db = 10 * np.log10((total_power - noise_power)/noise_power)
            print(f"{self.count} | SNR: {snr_db:.2f}dB, {sample['timestamp'].time()} | DF: {pms.adsb.df(msg)}, ICAO: {pms.adsb.icao(msg)}, CRC Valid: {pms.crc(msg) == 0}")
            self.count += 1
    
    def close(self) -> None:
        self.active = False

    def is_active(self) -> bool:
        return self.active