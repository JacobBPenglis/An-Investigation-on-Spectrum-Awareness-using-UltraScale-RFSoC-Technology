import numpy as np
import time

import config
from config import producer
from circular_buffer import WindowedCircularBuffer

def start_producer(buffer: WindowedCircularBuffer) -> None:
    match config.mode:
        case producer.FILE:
            file_producer(buffer)
        case producer.ZCU111:
            zcu111_producer(buffer)
        case producer.PLUTO_SDR:
            pluto_producer(buffer)
        case producer.BLADE_RF:
            blade_producer(buffer)

def file_producer(buffer: WindowedCircularBuffer) -> None:
    from pathlib import Path

    sample_data = Path(__file__).parent.parent / "data/adsb_sample.bit"

    # Start producing
    try:
        with open(sample_data, "rb") as f:
            while buffer.is_active():
                # Get raw samples of format (I, Q, I, Q, ...)
                raw_samples = np.fromfile(f, dtype=np.int16, count=config.WINDOW_SIZE * 2)

                # Transform raw samples into IQ data and write them to the buffer
                iq = raw_samples[0::2] + 1j * raw_samples[1::2]
                buffer.push_samples(iq)

                # Add delay to simulate a live producer
                time.sleep(config.WINDOW_SIZE/config.fs)

                # Exit if at end of file
                if len(raw_samples) < config.WINDOW_SIZE*2:
                    break

    except Exception as e:
        print("\nProducer exited with the following error:\n", e)

    finally:
        if buffer.is_active():
            buffer.close()

def zcu111_producer(buffer: WindowedCircularBuffer) -> None:
    return

def pluto_producer(buffer: WindowedCircularBuffer) -> None:
    import adi

    # Initialise the SDR
    sdr = adi.Pluto("ip:192.168.3.1")
    sdr.gain_control_mode_chan0 = "manual"
    sdr.rx_hardwaregain_chan0 = 0
    sdr.rx_lo = int(config.f)
    sdr.sample_rate = int(config.fs * config.fs_mult)
    sdr.rx_rf_bandwidth = int(config.bandwidth)
    sdr.rx_buffer_size = config.READ_BLOCK_SIZE

    # Start producing
    try:
        while buffer.is_active():
            # Get samples and write them to the buffer
            buffer.push_samples(sdr.rx())

    except Exception as e:
        print("\nProducer exited with the following error:\n", e)

    finally:
        if buffer.is_active():
            buffer.close()

def blade_producer(buffer: WindowedCircularBuffer) -> None:
    from bladerf import _bladerf

    # Initialise the SDR
    sdr = _bladerf.BladeRF()
    rx_ch = sdr.Channel(_bladerf.CHANNEL_RX(0))
    rx_ch.gain_mode = _bladerf.GainMode.Manual
    rx_ch.gain = 0
    rx_ch.frequency = int(config.f)
    rx_ch.sample_rate = int(config.fs * config.fs_mult)
    rx_ch.bandwidth = int(config.bandwidth)
    rx_ch.enable = True

    # Start producing
    try:
        while buffer.is_active():
            # Get samples and write them to the buffer
            buffer.push_samples(sdr.rx())

    except Exception as e:
        print("\nProducer exited with the following error:\n", e)

    finally:
        if buffer.is_active():
            buffer.close()