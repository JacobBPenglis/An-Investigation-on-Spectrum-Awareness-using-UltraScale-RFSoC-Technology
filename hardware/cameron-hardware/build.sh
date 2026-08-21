#!/usr/bin/env bash

# Always run relative to the repository root
cd "$(dirname "$0")" || exit 1

echo "=========================================="
echo "Building ZCU111 Vivado project"
echo "=========================================="

# Update this if Vivado is installed elsewhere
VIVADO="vivado" #"/tools/Xilinx/Vivado/2024.1/bin/vivado"

"$VIVADO" -mode batch -source "vivado-source/build_project.tcl"

if [ $? -ne 0 ]; then
    echo
    echo "ERROR: Vivado build failed."
    exit 1
fi

echo
echo "=========================================="
echo "Vivado build completed successfully"
echo "=========================================="