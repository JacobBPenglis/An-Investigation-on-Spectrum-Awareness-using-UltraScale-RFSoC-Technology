#!/usr/bin/env bash
set -e

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
OUTPUT_DIR="./output"
OUTPUT_NAME="top_design"
JOBS=8

# ------------------------------------------------------------
# Find Vivado project
# ------------------------------------------------------------
XPR=$(find . -maxdepth 2 -name "*.xpr" | head -n 1)

if [ -z "$XPR" ]; then
    echo "ERROR: Could not find a Vivado .xpr project."
    exit 1
fi

echo "Using Vivado project:"
echo "  $XPR"

# ------------------------------------------------------------
# Create temporary Tcl build script
# ------------------------------------------------------------
TCL_SCRIPT=$(mktemp --suffix=.tcl)

cat > "$TCL_SCRIPT" <<EOF
open_project {$XPR}

puts "========================================="
puts " Building bitstream"
puts "========================================="

# Build implementation through write_bitstream
launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1

# Check that implementation completed successfully
set status [get_property STATUS [get_runs impl_1]]

puts "Implementation status: \$status"

if {![string match "*Complete*" \$status]} {
    puts "ERROR: Implementation did not complete successfully."
    exit 1
}

close_project
exit
EOF

# ------------------------------------------------------------
# Run Vivado
# ------------------------------------------------------------
vivado -mode batch -source "$TCL_SCRIPT"

rm -f "$TCL_SCRIPT"

# ------------------------------------------------------------
# Locate generated files
# ------------------------------------------------------------
echo
echo "Locating generated files..."

BIT_FILE=$(find . -type f -name "${OUTPUT_NAME}_wrapper.bit" \
    -path "*/impl_1/*" | head -n 1)

HWH_FILE=$(find . -type f -name "${OUTPUT_NAME}.hwh" | head -n 1)

if [ -z "$BIT_FILE" ]; then
    echo "ERROR: Could not find ${OUTPUT_NAME}_wrapper.bit"
    exit 1
fi

if [ -z "$HWH_FILE" ]; then
    echo "ERROR: Could not find ${OUTPUT_NAME}.hwh"
    exit 1
fi

echo "Bitstream:"
echo "  $BIT_FILE"

echo "Hardware handoff:"
echo "  $HWH_FILE"

# ------------------------------------------------------------
# Copy to output directory
# ------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"

cp "$BIT_FILE" "$OUTPUT_DIR/${OUTPUT_NAME}.bit"
cp "$HWH_FILE" "$OUTPUT_DIR/${OUTPUT_NAME}.hwh"

echo
echo "========================================="
echo " Build complete"
echo "========================================="
echo
echo "Output:"
echo "  $OUTPUT_DIR/${OUTPUT_NAME}.bit"
echo "  $OUTPUT_DIR/${OUTPUT_NAME}.hwh"
