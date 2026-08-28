
################################################################
# This is a generated script based on design: top_design
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2024.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source top_design_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xczu28dr-ffvg1517-2-e
   set_property BOARD_PART xilinx.com:zcu111:part0:1.2 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name top_design

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:zynq_ultra_ps_e:3.5\
xilinx.com:ip:clk_wiz:6.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:axi_dma:7.1\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:ip:fir_compiler:7.2\
xilinx.com:ip:axis_subset_converter:1.1\
xilinx.com:ip:axis_data_fifo:2.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################


# Hierarchical cell: decimation_pipeline
proc create_hier_cell_decimation_pipeline { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_decimation_pipeline() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_DATA_I

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I areset

  # Create instance: stage1_I, and set properties
  set stage1_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage1_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage1.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {4} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {17} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {2560} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage1_I


  # Create instance: stage1_Q, and set properties
  set stage1_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage1_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage1.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {4} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {17} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {2560} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage1_Q


  # Create instance: stage2_I, and set properties
  set stage2_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage2_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage2.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {4} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {false} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {18} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {1280} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage2_I


  # Create instance: stage2_Q, and set properties
  set stage2_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage2_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage2.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {4} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {18} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {1280} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage2_Q


  # Create instance: axis_subset_converter_0, and set properties
  set axis_subset_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 axis_subset_converter_0 ]
  set_property -dict [list \
    CONFIG.DEFAULT_TLAST {256} \
    CONFIG.M_HAS_TLAST {1} \
    CONFIG.M_TDATA_NUM_BYTES {2} \
    CONFIG.S_TDATA_NUM_BYTES {3} \
    CONFIG.TDATA_REMAP {tdata[15:0]} \
  ] $axis_subset_converter_0


  # Create instance: axis_data_fifo_0, and set properties
  set axis_data_fifo_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_data_fifo_0 ]
  set_property CONFIG.FIFO_DEPTH {4096} $axis_data_fifo_0


  # Create instance: stage3_I, and set properties
  set stage3_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage3_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage3.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {4} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {19} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {640} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage3_I


  # Create instance: stage3_Q, and set properties
  set stage3_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage3_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage3.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {4} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {19} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {640} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage3_Q


  # Create instance: stage4_I, and set properties
  set stage4_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage4_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage4.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {20} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {320} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage4_I


  # Create instance: stage4_Q, and set properties
  set stage4_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage4_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage4.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {20} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {320} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage4_Q


  # Create instance: stage5_I, and set properties
  set stage5_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage5_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage5.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {21} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {160} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage5_I


  # Create instance: stage5_Q, and set properties
  set stage5_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage5_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage5.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {21} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {160} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage5_Q


  # Create instance: stage6_I, and set properties
  set stage6_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage6_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage6.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {22} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {80} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage6_I


  # Create instance: stage6_Q, and set properties
  set stage6_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage6_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage6.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {2} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {22} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {80} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage6_Q


  # Create instance: stage7_I, and set properties
  set stage7_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage7_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage7.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {4} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {23} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {40} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage7_I


  # Create instance: stage7_Q, and set properties
  set stage7_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage7_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/CAMERON-An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/coeffs/stage7.coe} \
    CONFIG.Coefficient_Fractional_Bits {15} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {16} \
    CONFIG.ColumnConfig {1} \
    CONFIG.Decimation_Rate {4} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Decimation} \
    CONFIG.Interpolation_Rate {1} \
    CONFIG.Number_Channels {1} \
    CONFIG.Output_Rounding_Mode {Convergent_Rounding_to_Even} \
    CONFIG.Output_Width {23} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {40} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage7_Q


  # Create interface connections
  connect_bd_intf_net -intf_net axis_data_fifo_0_M_AXIS [get_bd_intf_pins axis_subset_converter_0/S_AXIS] [get_bd_intf_pins axis_data_fifo_0/M_AXIS]
  connect_bd_intf_net -intf_net axis_subset_converter_0_M_AXIS [get_bd_intf_pins M_AXIS] [get_bd_intf_pins axis_subset_converter_0/M_AXIS]
  connect_bd_intf_net -intf_net rfdc_m00_axis [get_bd_intf_pins S_AXIS_DATA_I] [get_bd_intf_pins stage1_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage1_I_M_AXIS_DATA [get_bd_intf_pins stage1_I/M_AXIS_DATA] [get_bd_intf_pins stage2_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage1_Q_M_AXIS_DATA [get_bd_intf_pins stage1_Q/M_AXIS_DATA] [get_bd_intf_pins stage2_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage2_I_M_AXIS_DATA [get_bd_intf_pins stage2_I/M_AXIS_DATA] [get_bd_intf_pins stage3_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage2_Q_M_AXIS_DATA [get_bd_intf_pins stage2_Q/M_AXIS_DATA] [get_bd_intf_pins stage3_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage3_I_M_AXIS_DATA [get_bd_intf_pins stage4_I/S_AXIS_DATA] [get_bd_intf_pins stage3_I/M_AXIS_DATA]
  connect_bd_intf_net -intf_net stage3_Q_M_AXIS_DATA [get_bd_intf_pins stage3_Q/M_AXIS_DATA] [get_bd_intf_pins stage4_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage4_I_M_AXIS_DATA [get_bd_intf_pins stage5_I/S_AXIS_DATA] [get_bd_intf_pins stage4_I/M_AXIS_DATA]
  connect_bd_intf_net -intf_net stage4_Q_M_AXIS_DATA [get_bd_intf_pins stage4_Q/M_AXIS_DATA] [get_bd_intf_pins stage5_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage5_I_M_AXIS_DATA [get_bd_intf_pins stage5_I/M_AXIS_DATA] [get_bd_intf_pins stage6_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage5_Q_M_AXIS_DATA [get_bd_intf_pins stage5_Q/M_AXIS_DATA] [get_bd_intf_pins stage6_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage6_I_M_AXIS_DATA [get_bd_intf_pins stage6_I/M_AXIS_DATA] [get_bd_intf_pins stage7_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage6_Q_M_AXIS_DATA [get_bd_intf_pins stage6_Q/M_AXIS_DATA] [get_bd_intf_pins stage7_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage7_I_M_AXIS_DATA [get_bd_intf_pins axis_data_fifo_0/S_AXIS] [get_bd_intf_pins stage7_I/M_AXIS_DATA]

  # Create port connections
  connect_bd_net -net areset_1 [get_bd_pins areset] [get_bd_pins axis_subset_converter_0/aresetn] [get_bd_pins axis_data_fifo_0/s_axis_aresetn]
  connect_bd_net -net rfdc_clk_adc0 [get_bd_pins aclk] [get_bd_pins stage1_I/aclk] [get_bd_pins stage2_I/aclk] [get_bd_pins stage1_Q/aclk] [get_bd_pins stage2_Q/aclk] [get_bd_pins axis_subset_converter_0/aclk] [get_bd_pins axis_data_fifo_0/s_axis_aclk] [get_bd_pins stage3_I/aclk] [get_bd_pins stage3_Q/aclk] [get_bd_pins stage4_I/aclk] [get_bd_pins stage4_Q/aclk] [get_bd_pins stage5_Q/aclk] [get_bd_pins stage5_I/aclk] [get_bd_pins stage6_I/aclk] [get_bd_pins stage6_Q/aclk] [get_bd_pins stage7_I/aclk] [get_bd_pins stage7_Q/aclk]

  # Perform GUI Layout
  regenerate_bd_layout -hierarchy [get_bd_cells /decimation_pipeline] -layout_string {
   "ActiveEmotionalView":"Default View",
   "Default View_ScaleFactor":"0.625003",
   "Default View_TopLeft":"1698,-94",
   "ExpandedHierarchyInLayout":"",
   "guistr":"# # String gsaved with Nlview 7.7.1 2023-07-26 3bc4126617 VDI=43 GEI=38 GUI=JA:21.0 TLS
#  -string -flagsOSRD
preplace port S_AXIS_DATA_I -pg 1 -lvl 0 -x -20 -y 50 -defaultsOSRD
preplace port M_AXIS -pg 1 -lvl 10 -x 2950 -y 250 -defaultsOSRD
preplace port port-id_aclk -pg 1 -lvl 0 -x -20 -y 190 -defaultsOSRD
preplace port port-id_areset -pg 1 -lvl 0 -x -20 -y 380 -defaultsOSRD
preplace inst stage1_I -pg 1 -lvl 1 -x 170 -y 20 -defaultsOSRD
preplace inst stage1_Q -pg 1 -lvl 1 -x 170 -y 280 -defaultsOSRD
preplace inst stage2_I -pg 1 -lvl 2 -x 460 -y 30 -defaultsOSRD
preplace inst stage2_Q -pg 1 -lvl 2 -x 460 -y 290 -defaultsOSRD
preplace inst axis_subset_converter_0 -pg 1 -lvl 9 -x 2740 -y 260 -defaultsOSRD
preplace inst axis_data_fifo_0 -pg 1 -lvl 8 -x 2300 -y 110 -defaultsOSRD
preplace inst stage3_I -pg 1 -lvl 3 -x 740 -y 40 -defaultsOSRD
preplace inst stage3_Q -pg 1 -lvl 3 -x 740 -y 300 -defaultsOSRD
preplace inst stage4_I -pg 1 -lvl 4 -x 1020 -y 50 -defaultsOSRD
preplace inst stage4_Q -pg 1 -lvl 4 -x 1020 -y 310 -defaultsOSRD
preplace inst stage5_I -pg 1 -lvl 5 -x 1300 -y 60 -defaultsOSRD
preplace inst stage5_Q -pg 1 -lvl 5 -x 1300 -y 320 -defaultsOSRD
preplace inst stage6_I -pg 1 -lvl 6 -x 1580 -y 70 -defaultsOSRD
preplace inst stage6_Q -pg 1 -lvl 6 -x 1580 -y 330 -defaultsOSRD
preplace inst stage7_I -pg 1 -lvl 7 -x 1940 -y 90 -defaultsOSRD
preplace inst stage7_Q -pg 1 -lvl 7 -x 1940 -y 370 -defaultsOSRD
preplace netloc areset_1 1 0 9 30J 210 NJ 210 NJ 210 NJ 210 NJ 210 NJ 210 NJ 210 2170 280 N
preplace netloc rfdc_clk_adc0 1 0 9 20 90 320 100 600 110 880 120 1160 130 1440 140 1800 160 2180 260 N
preplace netloc rfdc_m00_axis 1 0 1 0J 10n
preplace netloc stage1_I_M_AXIS_DATA 1 1 1 N 20
preplace netloc stage1_Q_M_AXIS_DATA 1 1 1 N 280
preplace netloc stage2_I_M_AXIS_DATA 1 2 1 N 30
preplace netloc stage2_Q_M_AXIS_DATA 1 2 1 N 290
preplace netloc stage3_I_M_AXIS_DATA 1 3 1 N 40
preplace netloc stage3_Q_M_AXIS_DATA 1 3 1 N 300
preplace netloc stage4_I_M_AXIS_DATA 1 4 1 N 50
preplace netloc stage4_Q_M_AXIS_DATA 1 4 1 N 310
preplace netloc stage5_I_M_AXIS_DATA 1 5 1 N 60
preplace netloc stage5_Q_M_AXIS_DATA 1 5 1 N 320
preplace netloc stage6_I_M_AXIS_DATA 1 6 1 1730 70n
preplace netloc stage6_Q_M_AXIS_DATA 1 6 1 1720 330n
preplace netloc axis_data_fifo_0_M_AXIS 1 8 1 2420 110n
preplace netloc stage7_I_M_AXIS_DATA 1 7 1 N 90
preplace netloc axis_subset_converter_0_M_AXIS 1 9 1 2890 250n
levelinfo -pg 1 -20 170 460 740 1020 1300 1580 1940 2300 2740 2950
pagesize -pg 1 -db -bbox -sgen -180 -170 3460 580
"
}

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports

  # Create ports

  # Create instance: zynq_ultra_ps_e_0, and set properties
  set zynq_ultra_ps_e_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0 ]
  set_property -dict [list \
    CONFIG.PSU_DDR_RAM_HIGHADDR {0x7FFFFFFF} \
    CONFIG.PSU_DDR_RAM_HIGHADDR_OFFSET {0x00000002} \
    CONFIG.PSU_DDR_RAM_LOWADDR_OFFSET {0x80000000} \
    CONFIG.PSU__ACT_DDR_FREQ_MHZ {799.992004} \
    CONFIG.PSU__CRF_APB__ACPU_CTRL__ACT_FREQMHZ {1333.320068} \
    CONFIG.PSU__CRF_APB__DBG_FPD_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRF_APB__DBG_TSTMP_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRF_APB__DDR_CTRL__ACT_FREQMHZ {399.996002} \
    CONFIG.PSU__CRF_APB__DPDMA_REF_CTRL__ACT_FREQMHZ {599.994019} \
    CONFIG.PSU__CRF_APB__GDMA_REF_CTRL__ACT_FREQMHZ {599.994019} \
    CONFIG.PSU__CRF_APB__TOPSW_LSBUS_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRF_APB__TOPSW_MAIN_CTRL__ACT_FREQMHZ {533.328003} \
    CONFIG.PSU__CRL_APB__ADMA_REF_CTRL__ACT_FREQMHZ {533.328003} \
    CONFIG.PSU__CRL_APB__AMS_REF_CTRL__ACT_FREQMHZ {49.999500} \
    CONFIG.PSU__CRL_APB__CPU_R5_CTRL__ACT_FREQMHZ {533.328003} \
    CONFIG.PSU__CRL_APB__DBG_LPD_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRL_APB__DLL_REF_CTRL__ACT_FREQMHZ {999.989990} \
    CONFIG.PSU__CRL_APB__IOU_SWITCH_CTRL__ACT_FREQMHZ {266.664001} \
    CONFIG.PSU__CRL_APB__LPD_LSBUS_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__LPD_SWITCH_CTRL__ACT_FREQMHZ {533.328003} \
    CONFIG.PSU__CRL_APB__PCAP_CTRL__ACT_FREQMHZ {199.998001} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__TIMESTAMP_REF_CTRL__ACT_FREQMHZ {33.333000} \
    CONFIG.PSU__DDR_HIGH_ADDRESS_GUI_ENABLE {0} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__MAXIGP1__DATA_WIDTH {128} \
    CONFIG.PSU__PROTECTION__MASTERS {USB1:NonSecure;0|USB0:NonSecure;0|S_AXI_LPD:NA;0|S_AXI_HPC1_FPD:NA;0|S_AXI_HPC0_FPD:NA;0|S_AXI_HP3_FPD:NA;0|S_AXI_HP2_FPD:NA;0|S_AXI_HP1_FPD:NA;1|S_AXI_HP0_FPD:NA;0|S_AXI_ACP:NA;0|S_AXI_ACE:NA;0|SD1:NonSecure;0|SD0:NonSecure;0|SATA1:NonSecure;0|SATA0:NonSecure;0|RPU1:Secure;1|RPU0:Secure;1|QSPI:NonSecure;0|PMU:NA;1|PCIe:NonSecure;0|NAND:NonSecure;0|LDMA:NonSecure;1|GPU:NonSecure;1|GEM3:NonSecure;0|GEM2:NonSecure;0|GEM1:NonSecure;0|GEM0:NonSecure;0|FDMA:NonSecure;1|DP:NonSecure;0|DAP:NA;1|Coresight:NA;1|CSU:NA;1|APU:NA;1}\
\
    CONFIG.PSU__PROTECTION__SLAVES {LPD;USB3_1_XHCI;FE300000;FE3FFFFF;0|LPD;USB3_1;FF9E0000;FF9EFFFF;0|LPD;USB3_0_XHCI;FE200000;FE2FFFFF;0|LPD;USB3_0;FF9D0000;FF9DFFFF;0|LPD;UART1;FF010000;FF01FFFF;0|LPD;UART0;FF000000;FF00FFFF;0|LPD;TTC3;FF140000;FF14FFFF;0|LPD;TTC2;FF130000;FF13FFFF;0|LPD;TTC1;FF120000;FF12FFFF;0|LPD;TTC0;FF110000;FF11FFFF;0|FPD;SWDT1;FD4D0000;FD4DFFFF;0|LPD;SWDT0;FF150000;FF15FFFF;0|LPD;SPI1;FF050000;FF05FFFF;0|LPD;SPI0;FF040000;FF04FFFF;0|FPD;SMMU_REG;FD5F0000;FD5FFFFF;1|FPD;SMMU;FD800000;FDFFFFFF;1|FPD;SIOU;FD3D0000;FD3DFFFF;1|FPD;SERDES;FD400000;FD47FFFF;1|LPD;SD1;FF170000;FF17FFFF;0|LPD;SD0;FF160000;FF16FFFF;0|FPD;SATA;FD0C0000;FD0CFFFF;0|LPD;RTC;FFA60000;FFA6FFFF;1|LPD;RSA_CORE;FFCE0000;FFCEFFFF;1|LPD;RPU;FF9A0000;FF9AFFFF;1|LPD;R5_TCM_RAM_GLOBAL;FFE00000;FFE3FFFF;1|LPD;R5_1_Instruction_Cache;FFEC0000;FFECFFFF;1|LPD;R5_1_Data_Cache;FFED0000;FFEDFFFF;1|LPD;R5_1_BTCM_GLOBAL;FFEB0000;FFEBFFFF;1|LPD;R5_1_ATCM_GLOBAL;FFE90000;FFE9FFFF;1|LPD;R5_0_Instruction_Cache;FFE40000;FFE4FFFF;1|LPD;R5_0_Data_Cache;FFE50000;FFE5FFFF;1|LPD;R5_0_BTCM_GLOBAL;FFE20000;FFE2FFFF;1|LPD;R5_0_ATCM_GLOBAL;FFE00000;FFE0FFFF;1|LPD;QSPI_Linear_Address;C0000000;DFFFFFFF;1|LPD;QSPI;FF0F0000;FF0FFFFF;0|LPD;PMU_RAM;FFDC0000;FFDDFFFF;1|LPD;PMU_GLOBAL;FFD80000;FFDBFFFF;1|FPD;PCIE_MAIN;FD0E0000;FD0EFFFF;0|FPD;PCIE_LOW;E0000000;EFFFFFFF;0|FPD;PCIE_HIGH2;8000000000;BFFFFFFFFF;0|FPD;PCIE_HIGH1;600000000;7FFFFFFFF;0|FPD;PCIE_DMA;FD0F0000;FD0FFFFF;0|FPD;PCIE_ATTRIB;FD480000;FD48FFFF;0|LPD;OCM_XMPU_CFG;FFA70000;FFA7FFFF;1|LPD;OCM_SLCR;FF960000;FF96FFFF;1|OCM;OCM;FFFC0000;FFFFFFFF;1|LPD;NAND;FF100000;FF10FFFF;0|LPD;MBISTJTAG;FFCF0000;FFCFFFFF;1|LPD;LPD_XPPU_SINK;FF9C0000;FF9CFFFF;1|LPD;LPD_XPPU;FF980000;FF98FFFF;1|LPD;LPD_SLCR_SECURE;FF4B0000;FF4DFFFF;1|LPD;LPD_SLCR;FF410000;FF4AFFFF;1|LPD;LPD_GPV;FE100000;FE1FFFFF;1|LPD;LPD_DMA_7;FFAF0000;FFAFFFFF;1|LPD;LPD_DMA_6;FFAE0000;FFAEFFFF;1|LPD;LPD_DMA_5;FFAD0000;FFADFFFF;1|LPD;LPD_DMA_4;FFAC0000;FFACFFFF;1|LPD;LPD_DMA_3;FFAB0000;FFABFFFF;1|LPD;LPD_DMA_2;FFAA0000;FFAAFFFF;1|LPD;LPD_DMA_1;FFA90000;FFA9FFFF;1|LPD;LPD_DMA_0;FFA80000;FFA8FFFF;1|LPD;IPI_CTRL;FF380000;FF3FFFFF;1|LPD;IOU_SLCR;FF180000;FF23FFFF;1|LPD;IOU_SECURE_SLCR;FF240000;FF24FFFF;1|LPD;IOU_SCNTRS;FF260000;FF26FFFF;1|LPD;IOU_SCNTR;FF250000;FF25FFFF;1|LPD;IOU_GPV;FE000000;FE0FFFFF;1|LPD;I2C1;FF030000;FF03FFFF;0|LPD;I2C0;FF020000;FF02FFFF;0|FPD;GPU;FD4B0000;FD4BFFFF;0|LPD;GPIO;FF0A0000;FF0AFFFF;1|LPD;GEM3;FF0E0000;FF0EFFFF;0|LPD;GEM2;FF0D0000;FF0DFFFF;0|LPD;GEM1;FF0C0000;FF0CFFFF;0|LPD;GEM0;FF0B0000;FF0BFFFF;0|FPD;FPD_XMPU_SINK;FD4F0000;FD4FFFFF;1|FPD;FPD_XMPU_CFG;FD5D0000;FD5DFFFF;1|FPD;FPD_SLCR_SECURE;FD690000;FD6CFFFF;1|FPD;FPD_SLCR;FD610000;FD68FFFF;1|FPD;FPD_DMA_CH7;FD570000;FD57FFFF;1|FPD;FPD_DMA_CH6;FD560000;FD56FFFF;1|FPD;FPD_DMA_CH5;FD550000;FD55FFFF;1|FPD;FPD_DMA_CH4;FD540000;FD54FFFF;1|FPD;FPD_DMA_CH3;FD530000;FD53FFFF;1|FPD;FPD_DMA_CH2;FD520000;FD52FFFF;1|FPD;FPD_DMA_CH1;FD510000;FD51FFFF;1|FPD;FPD_DMA_CH0;FD500000;FD50FFFF;1|LPD;EFUSE;FFCC0000;FFCCFFFF;1|FPD;Display\
Port;FD4A0000;FD4AFFFF;0|FPD;DPDMA;FD4C0000;FD4CFFFF;0|FPD;DDR_XMPU5_CFG;FD050000;FD05FFFF;1|FPD;DDR_XMPU4_CFG;FD040000;FD04FFFF;1|FPD;DDR_XMPU3_CFG;FD030000;FD03FFFF;1|FPD;DDR_XMPU2_CFG;FD020000;FD02FFFF;1|FPD;DDR_XMPU1_CFG;FD010000;FD01FFFF;1|FPD;DDR_XMPU0_CFG;FD000000;FD00FFFF;1|FPD;DDR_QOS_CTRL;FD090000;FD09FFFF;1|FPD;DDR_PHY;FD080000;FD08FFFF;1|DDR;DDR_LOW;0;7FFFFFFF;1|DDR;DDR_HIGH;800000000;800000000;0|FPD;DDDR_CTRL;FD070000;FD070FFF;1|LPD;Coresight;FE800000;FEFFFFFF;1|LPD;CSU_DMA;FFC80000;FFC9FFFF;1|LPD;CSU;FFCA0000;FFCAFFFF;1|LPD;CRL_APB;FF5E0000;FF85FFFF;1|FPD;CRF_APB;FD1A0000;FD2DFFFF;1|FPD;CCI_REG;FD5E0000;FD5EFFFF;1|LPD;CAN1;FF070000;FF07FFFF;0|LPD;CAN0;FF060000;FF06FFFF;0|FPD;APU;FD5C0000;FD5CFFFF;1|LPD;APM_INTC_IOU;FFA20000;FFA2FFFF;1|LPD;APM_FPD_LPD;FFA30000;FFA3FFFF;1|FPD;APM_5;FD490000;FD49FFFF;1|FPD;APM_0;FD0B0000;FD0BFFFF;1|LPD;APM2;FFA10000;FFA1FFFF;1|LPD;APM1;FFA00000;FFA0FFFF;1|LPD;AMS;FFA50000;FFA5FFFF;1|FPD;AFI_5;FD3B0000;FD3BFFFF;1|FPD;AFI_4;FD3A0000;FD3AFFFF;1|FPD;AFI_3;FD390000;FD39FFFF;1|FPD;AFI_2;FD380000;FD38FFFF;1|FPD;AFI_1;FD370000;FD37FFFF;1|FPD;AFI_0;FD360000;FD36FFFF;1|LPD;AFIFM6;FF9B0000;FF9BFFFF;1|FPD;ACPU_GIC;F9010000;F907FFFF;1}\
\
    CONFIG.PSU__SAXIGP3__DATA_WIDTH {32} \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {1} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP3 {1} \
  ] $zynq_ultra_ps_e_0


  # Create instance: clk_wiz_0, and set properties
  set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
  set_property -dict [list \
    CONFIG.CLKIN1_JITTER_PS {100.0} \
    CONFIG.CLKOUT1_JITTER {93.765} \
    CONFIG.CLKOUT1_PHASE_ERROR {87.181} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {320} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {12.000} \
    CONFIG.MMCM_CLKIN1_PERIOD {10.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {3.750} \
    CONFIG.USE_RESET {false} \
  ] $clk_wiz_0


  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]
  set_property -dict [list \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $proc_sys_reset_0


  # Create instance: axi_dma_0, and set properties
  set axi_dma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0 ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axis_mm2s_tdata_width {128} \
    CONFIG.c_sg_length_width {26} \
  ] $axi_dma_0


  # Create instance: decimation_pipeline
  create_hier_cell_decimation_pipeline [current_bd_instance .] decimation_pipeline

  # Create instance: rst_ps8_0_96M, and set properties
  set rst_ps8_0_96M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps8_0_96M ]

  # Create instance: ps8_0_axi_periph, and set properties
  set ps8_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph ]
  set_property -dict [list \
    CONFIG.NUM_MI {2} \
    CONFIG.NUM_SI {2} \
  ] $ps8_0_axi_periph


  # Create instance: axi_smc, and set properties
  set axi_smc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_SI {2} \
  ] $axi_smc


  # Create interface connections
  connect_bd_intf_net -intf_net S_AXIS_DATA_I_1 [get_bd_intf_pins decimation_pipeline/S_AXIS_DATA_I] [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S]
  connect_bd_intf_net -intf_net axi_dma_0_M_AXI_MM2S [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_smc/S01_AXI]
  connect_bd_intf_net -intf_net axi_dma_0_M_AXI_S2MM [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_smc/S00_AXI]
  connect_bd_intf_net -intf_net axi_smc_M00_AXI [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP1_FPD]
  connect_bd_intf_net -intf_net axis_combiner_0_M_AXIS [get_bd_intf_pins decimation_pipeline/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_M00_AXI [get_bd_intf_pins ps8_0_axi_periph/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_M_AXI_HPM0_FPD [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]
  connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_M_AXI_HPM1_FPD [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM1_FPD] [get_bd_intf_pins ps8_0_axi_periph/S01_AXI]

  # Create port connections
  connect_bd_net -net Net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] [get_bd_pins rst_ps8_0_96M/slowest_sync_clk] [get_bd_pins zynq_ultra_ps_e_0/saxihp1_fpd_aclk] [get_bd_pins ps8_0_axi_periph/ACLK] [get_bd_pins ps8_0_axi_periph/S00_ACLK] [get_bd_pins ps8_0_axi_periph/M00_ACLK] [get_bd_pins ps8_0_axi_periph/M01_ACLK] [get_bd_pins axi_smc/aclk1] [get_bd_pins zynq_ultra_ps_e_0/maxihpm1_fpd_aclk] [get_bd_pins ps8_0_axi_periph/S01_ACLK] [get_bd_pins axi_dma_0/s_axi_lite_aclk] [get_bd_pins clk_wiz_0/clk_in1]
  connect_bd_net -net clk_wiz_0_clk_out1 [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins proc_sys_reset_0/slowest_sync_clk] [get_bd_pins decimation_pipeline/aclk] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] [get_bd_pins axi_smc/aclk] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
  connect_bd_net -net clk_wiz_0_locked [get_bd_pins clk_wiz_0/locked] [get_bd_pins proc_sys_reset_0/dcm_locked]
  connect_bd_net -net proc_sys_reset_0_peripheral_aresetn [get_bd_pins proc_sys_reset_0/peripheral_aresetn] [get_bd_pins decimation_pipeline/areset]
  connect_bd_net -net rst_ps8_0_96M_peripheral_aresetn [get_bd_pins rst_ps8_0_96M/peripheral_aresetn] [get_bd_pins axi_dma_0/axi_resetn] [get_bd_pins ps8_0_axi_periph/S00_ARESETN] [get_bd_pins ps8_0_axi_periph/M00_ARESETN] [get_bd_pins ps8_0_axi_periph/ARESETN] [get_bd_pins ps8_0_axi_periph/M01_ARESETN] [get_bd_pins axi_smc/aresetn] [get_bd_pins ps8_0_axi_periph/S01_ARESETN]
  connect_bd_net -net zynq_ultra_ps_e_0_pl_resetn0 [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_ps8_0_96M/ext_reset_in] [get_bd_pins proc_sys_reset_0/ext_reset_in]

  # Create address segments
  assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP3/HP1_DDR_LOW] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP3/HP1_DDR_LOW] -force

  # Exclude Address Segments
  exclude_bd_addr_seg -offset 0xFF000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP3/HP1_LPS_OCM]
  exclude_bd_addr_seg -offset 0xFF000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP3/HP1_LPS_OCM]

  # Perform GUI Layout
  regenerate_bd_layout -layout_string {
   "ActiveEmotionalView":"Default View",
   "Default View_ScaleFactor":"0.619679",
   "Default View_TopLeft":"395,-118",
   "ExpandedHierarchyInLayout":"",
   "guistr":"# # String gsaved with Nlview 7.7.1 2023-07-26 3bc4126617 VDI=43 GEI=38 GUI=JA:21.0 TLS
#  -string -flagsOSRD
preplace inst zynq_ultra_ps_e_0 -pg 1 -lvl 4 -x 2223 -y -160 -defaultsOSRD
preplace inst clk_wiz_0 -pg 1 -lvl 1 -x 490 -y 190 -defaultsOSRD
preplace inst proc_sys_reset_0 -pg 1 -lvl 1 -x 490 -y 340 -defaultsOSRD
preplace inst axi_dma_0 -pg 1 -lvl 3 -x 1700 -y -190 -defaultsOSRD
preplace inst decimation_pipeline -pg 1 -lvl 2 -x 1000 -y -10 -defaultsOSRD
preplace inst rst_ps8_0_96M -pg 1 -lvl 5 -x 2760 -y 90 -defaultsOSRD
preplace inst ps8_0_axi_periph -pg 1 -lvl 6 -x 3120 -y -330 -defaultsOSRD
preplace inst axi_smc -pg 1 -lvl 6 -x 3120 -y -80 -defaultsOSRD
preplace netloc Net 1 0 6 290 -100 N -100 1490 -310 1893 -280 2550 -150 2960
preplace netloc clk_wiz_0_clk_out1 1 0 6 300 110 680 -90 1510 -70 1903 -270 2570 -140 2950
preplace netloc proc_sys_reset_0_peripheral_aresetn 1 1 1 690 10n
preplace netloc rst_ps8_0_96M_peripheral_aresetn 1 2 4 1530 -330 NJ -330 2580J -160 2970
preplace netloc zynq_ultra_ps_e_0_pl_resetn0 1 0 5 280 70 NJ 70 NJ 70 NJ 70 2530
preplace netloc clk_wiz_0_locked 1 0 2 310 120 670
preplace netloc axi_dma_0_M_AXI_S2MM 1 3 3 1913J -250 2540J -120 N
preplace netloc axi_smc_M00_AXI 1 3 4 1923 -510 NJ -510 NJ -510 3280
preplace netloc axis_combiner_0_M_AXIS 1 2 1 1500 -220n
preplace netloc ps8_0_axi_periph_M00_AXI 1 2 5 1520 -500 NJ -500 NJ -500 NJ -500 3270
preplace netloc zynq_ultra_ps_e_0_M_AXI_HPM0_FPD 1 4 2 NJ -190 2940
preplace netloc S_AXIS_DATA_I_1 1 1 3 870 -320 NJ -320 1870
preplace netloc axi_dma_0_M_AXI_MM2S 1 3 3 1880 -260 2560J -130 2940J
preplace netloc zynq_ultra_ps_e_0_M_AXI_HPM1_FPD 1 4 2 NJ -170 2950
levelinfo -pg 1 -10 490 1000 1700 2223 2760 3120 3300
pagesize -pg 1 -db -bbox -sgen -450 -560 5630 440
"
}

  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


