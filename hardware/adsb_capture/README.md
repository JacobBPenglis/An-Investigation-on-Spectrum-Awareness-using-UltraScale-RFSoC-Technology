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
`hardware/adsb_capture/build_rfdc8_fir32_clk160_v2/` and is excluded from Git.
The versioned directory prevents reuse of generated IP, run data, HWH metadata,
or a bitstream from the earlier selectable-decimator design.

## Source layout

| Path | Contents |
| --- | --- |
| `scripts/adsb_capture_bd.tcl` | Exported IP Integrator block design |
| `scripts/create_project.tcl` | Portable project creation script |
| `coefficients/adsb_decimator.coe` | Shared fixed divide-by-32 FIR coefficients for I and Q |
| `rtl/axis_capture_gate.v` | Finite-frame gate and DMA `TLAST` generator |
| `ip_repo/xsg_bwselector_v1_1/` | Legacy selectable decimator, retained as a reference but not instantiated by the current block design |

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
vivado build_rfdc8_fir32_clk160_v2/adsb_capture.xpr
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
`synth_checkpoint_mode None`, rebuilds the local IP catalog, and audits all
rate-defining RFDC and AXI-stream width properties when the project is
recreated. The current design instantiates separate `JACOBS_FIR_I` and
`JACOBS_FIR_Q` FIR Compiler blocks with a fixed decimation factor of 32.

The block-design Tcl resolves the coefficient file relative to its own
location:

```text
hardware/adsb_capture/coefficients/adsb_decimator.coe
```

Both `JACOBS_FIR_I` and `JACOBS_FIR_Q` use this file. Project creation stops
with a direct error if it is missing, and does not depend on Vivado's launch
directory or a developer-specific absolute path.

The RFDC tile output clock is explicitly fixed at 160 MHz. The capture status
register identifies this source as build `0xA834`, reports the most recently
measured output-TVALID gap, and independently counts the RFDC fabric clock
against the 100 MHz PS control clock. It must report about 160,000 edges/ms.
The fixed FIR path averages one output per 16 fabric cycles (10 MSPS), although
individual gaps can be one clock when valid transfers are scheduled adjacently.
Software therefore validates the average using complete timed DMA frames.
Build `0xA833` identifies the earlier selectable-decimator bitstream.

## Runtime artifacts

Normal PYNQ operation requires a matched pair from the same implementation
run:

```text
adsb_capture.bit
adsb_capture.hwh
```

The deployment destination is `pynq/adsb_capture/bitstream/`. Vivado working
files, checkpoints, logs, and run directories remain outside version control.
Never copy the `.hwh` from one run and the `.bit` from another.
