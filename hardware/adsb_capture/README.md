# ADS-B capture hardware

Vivado version: 2024.1

Board: ZCU111
Board part: `xilinx.com:zcu111:part0:1.2`
Device: `xczu28dr-ffvg1517-2-e`

## Recreate the editable project

From this directory:

```bash
vivado -mode batch -source scripts/create_project.tcl
vivado build/adsb_capture.xpr
