# Folder containing your source files and export scripts
cd V:/

# Validate and save the current top_design block design
validate_bd_design
save_bd_design

# Export the block design, including its visual layout
write_bd_tcl -force -include_layout ./top_design.tcl

# Export the complete project recreation script
write_project_tcl -force \
    -paths_relative_to . \
    -target_proj_dir ./build_recreated \
    ./project_recreate.tcl