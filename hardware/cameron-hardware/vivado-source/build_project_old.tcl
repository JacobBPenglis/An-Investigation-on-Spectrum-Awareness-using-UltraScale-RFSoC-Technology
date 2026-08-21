# ============================================================
# ZCU111 Vivado Project Build Script
# ============================================================

# Directory containing this script:
# repo/vivado-source/
set script_dir [file dirname [file normalize [info script]]]

# Repository root:
# repo/
set repo_root [file normalize [file join $script_dir ".."]]

# Generated build directory:
# repo/build/
set build_dir [file join $repo_root "build"]

set project_name "zcu111_adsb_project"
set project_dir  [file join $build_dir $project_name]

puts "============================================================"
puts "Vivado project build"
puts "Repository root: $repo_root"
puts "Source directory: $script_dir"
puts "Build directory: $build_dir"
puts "============================================================"

# ------------------------------------------------------------
# Create build directory
# ------------------------------------------------------------

file mkdir $build_dir

# ------------------------------------------------------------
# Create Vivado project
# ------------------------------------------------------------

create_project -force $project_name $project_dir 
# create_project -force $project_name $project_dir \
#     -part xczu28dr-ffvg1517-2-e
set_property board_part xilinx.com:zcu111:part0:1.4 [current_project]

# ------------------------------------------------------------
# Add RTL sources
# ------------------------------------------------------------

# set rtl_dir [file join $script_dir "rtl"]

# if {[file exists $rtl_dir]} {
#     set rtl_files [glob -nocomplain \
#         [file join $rtl_dir "*.v"] \
#         [file join $rtl_dir "*.sv"] \
#         [file join $rtl_dir "*.vhd"]]

#     if {[llength $rtl_files] > 0} {
#         add_files -norecurse $rtl_files
#     }
# }


# ------------------------------------------------------------
# Recreate block design
# ------------------------------------------------------------

set bd_script [file join \
    $script_dir \
    "top_design.tcl"]

if {[file exists $bd_script]} {
    puts "Creating block design..."
    source $bd_script
} else {
    puts "ERROR: Block design Tcl not found:"
    puts "       $bd_script"
    exit 1
}

# ------------------------------------------------------------
# Validate and save block design
# ------------------------------------------------------------

validate_bd_design
save_bd_design

# ------------------------------------------------------------
# Generate HDL wrapper
# ------------------------------------------------------------

set bd_file [get_files *.bd]

make_wrapper \
    -files $bd_file \
    -top

set wrapper_file [glob \
    [file join \
        $project_dir \
        "${project_name}.gen" \
        "sources_1" \
        "bd" \
        "*" \
        "hdl" \
        "*_wrapper.v"]]

add_files -norecurse $wrapper_file

update_compile_order -fileset sources_1

puts "============================================================"
puts "Project successfully created."
puts "Project location:"
puts "$project_dir"
puts "============================================================"