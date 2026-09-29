import numpy as np

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
    import time

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
    import sys
    import time
    import matplotlib.pyplot as plt
    from IPython.display import clear_output, display
    import importlib.util
    import sys

    LOCAL_DIR = '/home/xilinx/jupyter_notebooks/JACOBS_FILES/recents'  

    def load_module_from_path(module_name, file_path):
        spec = importlib.util.spec_from_file_location(module_name, file_path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module   # register BEFORE exec, so internal imports resolve here too
        spec.loader.exec_module(module)
        return module

    iq_protocol = load_module_from_path('iq_protocol', f'{LOCAL_DIR}/iq_protocol.py')
    adsb_capture = load_module_from_path('adsb_capture', f'{LOCAL_DIR}/adsb_capture.py')

    AdsbCapture = adsb_capture.AdsbCapture
    unpack_iq = adsb_capture.unpack_iq
    IQ_SAMPLE_RATE_HZ = iq_protocol.IQ_SAMPLE_RATE_HZ

    BITFILE = '/home/xilinx/jupyter_notebooks/JACOBS_FILES/recents/JACOBS.bit'
    capture = AdsbCapture(bitfile=BITFILE, centre_frequency_mhz=1090)

    # Start producing
    try:
        while buffer.is_active():
            # Get samples and write them to the buffer
            raw = capture.capture(config.READ_BLOCK_SIZE)
            iq = unpack_iq(raw, normalize=True)
            buffer.push_samples(iq)

    except Exception as e:
        print("\nProducer exited with the following error:\n", e)

    finally:
        if buffer.is_active():
            buffer.close()    

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

    # Setup synchronous stream
    sdr.sync_config(
        layout = _bladerf.ChannelLayout.RX_X1,
        fmt = _bladerf.Format.SC16_Q11, # int16
        num_buffers    = 16,
        buffer_size    = 8192,
        num_transfers  = 8,
        stream_timeout = 3500
    )

    # Create receive buffer
    bytes_per_sample = 4 # I and Q int16s
    buf = bytearray(config.READ_BLOCK_SIZE * bytes_per_sample)

    rx_ch.enable = True

    # Start producing
    try:
        while buffer.is_active():
            # Get samples
            sdr.sync_rx(buf, config.READ_BLOCK_SIZE)

            raw_samples = np.frombuffer(buf, dtype=np.int16)

            # Transform raw samples into IQ data and write them to the buffer
            iq = raw_samples[0::2] + 1j * raw_samples[1::2]
            buffer.push_samples(iq)

    except Exception as e:
        print("\nProducer exited with the following error:\n", e)

    finally:
        rx_ch.enable = False

        if buffer.is_active():
            buffer.close()