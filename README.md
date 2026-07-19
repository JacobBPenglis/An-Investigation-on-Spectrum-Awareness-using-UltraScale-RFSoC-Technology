# An Investigation on Spectrum Awareness using UltraScale+ RFSoC Technology

Honours Project - 2026

The repository contains the ZCU111 ADS-B capture hardware, PYNQ runtime,
board experiments, and offline signal-analysis work.

## Repository layout

| Path | Contents | Execution environment |
| --- | --- | --- |
| `hardware/adsb_capture/` | Vivado 2024.1 block design, RTL, and custom IP | Vivado build machine |
| `pynq/adsb_capture/` | Overlay loader, DMA capture, file output, and UDP transfer | ZCU111 PYNQ image and host receiver |
| `pynq/experiments/` | Earlier RFSoC-SAM and QPSK capture experiments | ZCU111 with the referenced overlays installed |
| `analysis/notebooks/` | I/Q classification and transmitter-identification experiments | Host Python environment |
| `analysis/signal_detection/` | Sliding-window detector and time-domain features | Host Python environment |
| `matlab/` | Decimator design and earlier system constants | MATLAB |

The deployable board directory is `pynq/adsb_capture/`. The matching
`adsb_capture.bit` and `adsb_capture.hwh` files occupy its `bitstream/`
directory on the board.
