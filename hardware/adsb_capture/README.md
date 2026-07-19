# ADS-B capture hardware

## Build record

| Item | Value |
| --- | --- |
| Vivado | 2024.1 |
| Board | ZCU111 |
| Board part | `xilinx.com:zcu111:part0:1.2` |
| Device | `xczu28dr-ffvg1517-2-e` |
| Block design | `adsb_capture` |

The project is recreated from Tcl. The generated Vivado workspace is
`hardware/adsb_capture/build/` and is excluded from Git.

## Source layout

| Path | Contents |
| --- | --- |
| `scripts/adsb_capture_bd.tcl` | Exported IP Integrator block design |
| `scripts/create_project.tcl` | Portable project creation script |
| `rtl/axis_capture_gate.v` | Finite-frame gate and DMA `TLAST` generator |
| `ip_repo/xsg_bwselector_v1_1/` | Packaged programmable-logic decimator |

## Recreate the editable project

Working directory:

```text
hardware/adsb_capture
```

Project creation:

```bash
vivado -mode batch -source scripts/create_project.tcl
```

GUI launch:

```bash
vivado build/adsb_capture.xpr
```

The block design remains editable through the normal IP Integrator diagram.
After a saved diagram change, the current block design is exported from the
Vivado Tcl Console:

```tcl
set hw [file normalize "/path/to/repository/hardware/adsb_capture"]
validate_bd_design
save_bd_design
write_bd_tcl -force [file join $hw scripts adsb_capture_bd.tcl]
```

The block design uses Global synthesis. `create_project.tcl` applies
`synth_checkpoint_mode None` when the project is recreated.

## Runtime artifacts

Normal PYNQ operation requires a matched pair from the same implementation
run:

```text
adsb_capture.bit
adsb_capture.hwh
```

The deployment destination is `pynq/adsb_capture/bitstream/`. Vivado working
files, checkpoints, logs, and run directories remain outside version control.
