
################################################################
# This is a generated script based on design: decimator_pipeline
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
# source decimator_pipeline_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xczu28dr-ffvg1517-2-e
   set_property BOARD_PART xilinx.com:zcu111:part0:1.4 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name decimator_pipeline

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
xilinx.com:ip:fir_compiler:7.2\
xilinx.com:ip:axis_combiner:1.1\
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
  set M_AXIS_DATA [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_DATA ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {320000000} \
   ] $M_AXIS_DATA

  set S_AXIS_DATA_I [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_DATA_I ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {320000000} \
   CONFIG.HAS_TKEEP {0} \
   CONFIG.HAS_TLAST {0} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {16} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $S_AXIS_DATA_I

  set S_AXIS_DATA_Q [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_DATA_Q ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {320000000} \
   CONFIG.HAS_TKEEP {0} \
   CONFIG.HAS_TLAST {0} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {16} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $S_AXIS_DATA_Q


  # Create ports
  set aclk [ create_bd_port -dir I -type clk -freq_hz 320000000 aclk ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S_AXIS_DATA_I:M_AXIS_DATA:S_AXIS_DATA_Q} \
   CONFIG.ASSOCIATED_RESET {aresetn} \
   CONFIG.CLK_DOMAIN {top_design_clk_wiz_0_0_clk_out1} \
 ] $aclk
  set aresetn [ create_bd_port -dir I -type rst aresetn ]

  # Create instance: stage1_I, and set properties
  set stage1_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage1_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage1.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {2560} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage1_I


  # Create instance: stage1_Q, and set properties
  set stage1_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage1_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage1.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {2560} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage1_Q


  # Create instance: axis_combiner_0, and set properties
  set axis_combiner_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_combiner:1.1 axis_combiner_0 ]

  # Create instance: stage2_I, and set properties
  set stage2_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage2_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage2.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {1280} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage2_I


  # Create instance: stage2_Q, and set properties
  set stage2_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage2_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage2.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {1280} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage2_Q


  # Create instance: stage3_I, and set properties
  set stage3_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage3_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage3.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {640} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage3_I


  # Create instance: stage3_Q, and set properties
  set stage3_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage3_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage3.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {640} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage3_Q


  # Create instance: stage4_I, and set properties
  set stage4_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage4_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage4.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {320} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage4_I


  # Create instance: stage4_Q, and set properties
  set stage4_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage4_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage4.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {320} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage4_Q


  # Create instance: stage5_I, and set properties
  set stage5_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage5_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage5.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {160} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage5_I


  # Create instance: stage5_I1, and set properties
  set stage5_I1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage5_I1 ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage5.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {160} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage5_I1


  # Create instance: stage6_I, and set properties
  set stage6_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage6_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage6.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {80} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage6_I


  # Create instance: stage6_Q, and set properties
  set stage6_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage6_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage6.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {80} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage6_Q


  # Create instance: stage7_I, and set properties
  set stage7_I [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage7_I ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage7.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {40} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage7_I


  # Create instance: stage7_Q, and set properties
  set stage7_Q [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 stage7_Q ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {320} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {/home/cameron/An-Investigation-on-Spectrum-Awareness-using-UltraScale-RFSoC-Technology/hardware/cameron-hardware/vivado-source/coefficients/stage7.coe} \
    CONFIG.Coefficient_Fractional_Bits {0} \
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
    CONFIG.Output_Rounding_Mode {Symmetric_Rounding_to_Zero} \
    CONFIG.Output_Width {16} \
    CONFIG.Quantization {Integer_Coefficients} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.Sample_Frequency {40} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $stage7_Q


  # Create instance: axis_data_fifo_0, and set properties
  set axis_data_fifo_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_data_fifo_0 ]
  set_property CONFIG.FIFO_DEPTH {4096} $axis_data_fifo_0


  # Create interface connections
  connect_bd_intf_net -intf_net S_AXIS_DATA_Q_1 [get_bd_intf_ports S_AXIS_DATA_Q] [get_bd_intf_pins stage1_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net axis_combiner_0_M_AXIS [get_bd_intf_pins axis_combiner_0/M_AXIS] [get_bd_intf_pins axis_data_fifo_0/S_AXIS]
  connect_bd_intf_net -intf_net axis_data_fifo_0_M_AXIS [get_bd_intf_ports M_AXIS_DATA] [get_bd_intf_pins axis_data_fifo_0/M_AXIS]
  connect_bd_intf_net -intf_net stage1_I_M_AXIS_DATA [get_bd_intf_pins stage1_I/M_AXIS_DATA] [get_bd_intf_pins stage2_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage1_Q_M_AXIS_DATA [get_bd_intf_pins stage2_Q/S_AXIS_DATA] [get_bd_intf_pins stage1_Q/M_AXIS_DATA]
  connect_bd_intf_net -intf_net stage2_I_M_AXIS_DATA [get_bd_intf_pins stage2_I/M_AXIS_DATA] [get_bd_intf_pins stage3_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage2_Q_M_AXIS_DATA [get_bd_intf_pins stage2_Q/M_AXIS_DATA] [get_bd_intf_pins stage3_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage3_I_M_AXIS_DATA [get_bd_intf_pins stage3_I/M_AXIS_DATA] [get_bd_intf_pins stage4_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage3_Q_M_AXIS_DATA [get_bd_intf_pins stage3_Q/M_AXIS_DATA] [get_bd_intf_pins stage4_Q/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage4_I_M_AXIS_DATA [get_bd_intf_pins stage4_I/M_AXIS_DATA] [get_bd_intf_pins stage5_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage4_Q_M_AXIS_DATA [get_bd_intf_pins stage4_Q/M_AXIS_DATA] [get_bd_intf_pins stage5_I1/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage5_I1_M_AXIS_DATA [get_bd_intf_pins stage6_Q/S_AXIS_DATA] [get_bd_intf_pins stage5_I1/M_AXIS_DATA]
  connect_bd_intf_net -intf_net stage5_I_M_AXIS_DATA [get_bd_intf_pins stage6_I/S_AXIS_DATA] [get_bd_intf_pins stage5_I/M_AXIS_DATA]
  connect_bd_intf_net -intf_net stage6_I_M_AXIS_DATA [get_bd_intf_pins stage6_I/M_AXIS_DATA] [get_bd_intf_pins stage7_I/S_AXIS_DATA]
  connect_bd_intf_net -intf_net stage6_Q_M_AXIS_DATA [get_bd_intf_pins stage7_Q/S_AXIS_DATA] [get_bd_intf_pins stage6_Q/M_AXIS_DATA]
  connect_bd_intf_net -intf_net stage7_I_M_AXIS_DATA [get_bd_intf_pins stage7_I/M_AXIS_DATA] [get_bd_intf_pins axis_combiner_0/S00_AXIS]
  connect_bd_intf_net -intf_net stage7_Q_M_AXIS_DATA [get_bd_intf_pins stage7_Q/M_AXIS_DATA] [get_bd_intf_pins axis_combiner_0/S01_AXIS]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m00_axis [get_bd_intf_ports S_AXIS_DATA_I] [get_bd_intf_pins stage1_I/S_AXIS_DATA]

  # Create port connections
  connect_bd_net -net aresetn_0_1 [get_bd_ports aresetn] [get_bd_pins axis_combiner_0/aresetn] [get_bd_pins axis_data_fifo_0/s_axis_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out1 [get_bd_ports aclk] [get_bd_pins stage1_I/aclk] [get_bd_pins stage1_Q/aclk] [get_bd_pins axis_combiner_0/aclk] [get_bd_pins stage2_I/aclk] [get_bd_pins stage2_Q/aclk] [get_bd_pins stage3_I/aclk] [get_bd_pins stage3_Q/aclk] [get_bd_pins stage4_I/aclk] [get_bd_pins stage4_Q/aclk] [get_bd_pins stage5_I/aclk] [get_bd_pins stage5_I1/aclk] [get_bd_pins stage6_I/aclk] [get_bd_pins stage6_Q/aclk] [get_bd_pins stage7_I/aclk] [get_bd_pins stage7_Q/aclk] [get_bd_pins axis_data_fifo_0/s_axis_aclk]

  # Create address segments


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


