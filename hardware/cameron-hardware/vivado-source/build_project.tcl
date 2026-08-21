# ============================================================
# ZCU111 Vivado Project Build Script
#
# Repository:
#
# repo/
#   build.bat
#   vivado-source/
#       build_project.tcl
#       top_design.tcl
#
# All generated Vivado files are placed under:
#
# repo/build/
# ============================================================


# ============================================================
# Configuration
# ============================================================

set project_name "zcu111_adsb_project"
set bd_name      "top_design"

set board_part "xilinx.com:zcu111:part0:1.4"
set device_part "xczu28dr-ffvg1517-2-e"


# Set to 1 if you want build.bat to generate a bitstream.
# Set to 0 if you only want to recreate the Vivado project.
set build_bitstream 0


# ============================================================
# Repository paths
# ============================================================

# vivado-source/
set script_dir [file dirname [file normalize [info script]]]

# repository root
set repo_root [file normalize [file join $script_dir ".."]]

# generated build directory
set build_dir [file join $repo_root "build"]

# actual Vivado project directory
set project_dir [file join $build_dir $project_name]

# block design Tcl
set bd_script [file join $script_dir "${bd_name}.tcl"]


puts ""
puts "============================================================"
puts " ZCU111 Vivado Build"
puts "============================================================"
puts "Repository root : $repo_root"
puts "Source directory: $script_dir"
puts "Build directory : $build_dir"
puts "Project         : $project_name"
puts "Block design    : $bd_name"
puts "============================================================"
puts ""


# ============================================================
# Check required source files
# ============================================================

if {![file exists $bd_script]} {
    puts "ERROR: Block design Tcl script not found:"
    puts "       $bd_script"
    exit 1
}


# ============================================================
# Create build directory
# ============================================================

file mkdir $build_dir


# ============================================================
# Create Vivado project
# ============================================================

puts "Creating Vivado project..."

create_project -force \
    $project_name \
    $project_dir \
    -part $device_part

set_property board_part $board_part [current_project]

# Optional project settings
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]


# ============================================================
# Add RTL sources
#
# Any hand-written RTL can later be stored in:
#
# vivado-source/rtl/
# ============================================================

set rtl_dir [file join $script_dir "rtl"]

if {[file isdirectory $rtl_dir]} {

    set rtl_files [concat \
        [glob -nocomplain [file join $rtl_dir "*.v"]] \
        [glob -nocomplain [file join $rtl_dir "*.sv"]] \
        [glob -nocomplain [file join $rtl_dir "*.vhd"]] \
        [glob -nocomplain [file join $rtl_dir "*.vhdl"]] \
    ]

    if {[llength $rtl_files] > 0} {

        puts "Adding RTL sources..."

        foreach rtl_file $rtl_files {
            puts "  $rtl_file"
        }

        add_files -norecurse $rtl_files
    }
}


# ============================================================
# Recreate block design
# ============================================================

puts ""
puts "Recreating block design from:"
puts "  $bd_script"
puts ""

source $bd_script


# ============================================================
# Find reconstructed block design
# ============================================================

set bd_files [get_files -quiet "${bd_name}.bd"]

if {[llength $bd_files] != 1} {
    puts "ERROR: Expected exactly one ${bd_name}.bd after sourcing:"
    puts "       $bd_script"
    puts ""
    puts "Found:"
    puts "$bd_files"
    exit 1
}

set bd_file [lindex $bd_files 0]

puts ""
puts "Block design created:"
puts "  $bd_file"


# ============================================================
# Validate block design
# ============================================================

puts ""
puts "Validating block design..."

open_bd_design $bd_file
validate_bd_design
save_bd_design


# ============================================================
# Generate block design output products
# ============================================================

puts ""
puts "Generating block design output products..."

generate_target all $bd_file


# ============================================================
# Generate HDL wrapper
# ============================================================

puts ""
puts "Generating HDL wrapper..."

make_wrapper \
    -files $bd_file \
    -top


# Vivado places the generated wrapper here:
set wrapper_dir [file join \
    $project_dir \
    "${project_name}.gen" \
    "sources_1" \
    "bd" \
    $bd_name \
    "hdl"]

# Support either Verilog or VHDL wrappers
set wrapper_files [concat \
    [glob -nocomplain [file join $wrapper_dir "${bd_name}_wrapper.v"]] \
    [glob -nocomplain [file join $wrapper_dir "${bd_name}_wrapper.vhd"]] \
]


if {[llength $wrapper_files] != 1} {
    puts "ERROR: Could not uniquely locate generated HDL wrapper."
    puts "Expected under:"
    puts "  $wrapper_dir"
    puts ""
    puts "Found:"
    puts "$wrapper_files"
    exit 1
}

set wrapper_file [lindex $wrapper_files 0]

puts "Wrapper:"
puts "  $wrapper_file"

add_files -norecurse $wrapper_file

set_property top "${bd_name}_wrapper" [current_fileset]

update_compile_order -fileset sources_1


# ============================================================
# Save project
# ============================================================

#save_project

# ============================================================
# Optional full FPGA build
# ============================================================

if {$build_bitstream} {

    puts ""
    puts "============================================================"
    puts " Starting synthesis"
    puts "============================================================"

    launch_runs synth_1 -jobs 8
    wait_on_run synth_1

    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
        puts "ERROR: Synthesis failed."
        exit 1
    }


    puts ""
    puts "============================================================"
    puts " Starting implementation and bitstream generation"
    puts "============================================================"

    launch_runs impl_1 \
        -to_step write_bitstream \
        -jobs 8

    wait_on_run impl_1

    if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
        puts "ERROR: Implementation failed."
        exit 1
    }


    # --------------------------------------------------------
    # Copy useful build products to build/output/
    # --------------------------------------------------------

    set output_dir [file join $build_dir "output"]
    file mkdir $output_dir

    set bit_file [get_property BITSTREAM.FILE [get_runs impl_1]]

    if {[file exists $bit_file]} {
        file copy -force \
            $bit_file \
            [file join $output_dir "${bd_name}.bit"]

        puts "Bitstream copied to:"
        puts "  [file join $output_dir ${bd_name}.bit]"
    }


    # --------------------------------------------------------
    # Export hardware platform
    # --------------------------------------------------------

    set xsa_file [file join $output_dir "${bd_name}.xsa"]

    write_hw_platform \
        -fixed \
        -include_bit \
        -force \
        -file $xsa_file

    puts "Hardware platform:"
    puts "  $xsa_file"
}


# ============================================================
# Finished
# ============================================================

puts ""
puts "============================================================"
puts " BUILD COMPLETE"
puts "============================================================"
puts "Vivado project:"
puts "  $project_dir/${project_name}.xpr"

if {!$build_bitstream} {
    puts ""
    puts "NOTE:"
    puts "  Project recreation only."
    puts "  Set build_bitstream to 1 in build_project.tcl"
    puts "  to run synthesis, implementation and write_bitstream."
}

puts "============================================================"
puts ""

exit 0