# Overlay artifacts

The board runtime expects the following matched files in this directory:

```text
adsb_capture.bit
adsb_capture.hwh
```

These files come from

```text
<project>.runs/impl_1/adsb_capture_wrapper.bit : rename to adsb_capture.bit
<project>.gen/sources_1/bd/adsb_capture/hw_handoff/adsb_capture.hwh
```

Both files originate from the same Vivado implementation run and retain the
same base name. PYNQ reads the `.hwh` metadata to locate the RFDC, DMA, GPIO,
and decimator instances.

The normal board deployment does not require the Vivado project or an `.xsa`
file.
