# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Vivado out-of-context synthesis and implementation flow for ibex_top.
# Run through run.sh, or directly with:
#   vivado -mode batch -source syn/vivado/run_vivado.tcl -tclargs \
#     --part xc7a100tcsg324-1 --period 10.0 --config small

proc usage {} {
  puts "Usage: run_vivado.tcl ?options?"
  puts "  --part <part>          Xilinx part (default: xc7a100tcsg324-1)"
  puts "  --period <ns>          clk_i period in ns (default: 10.0)"
  puts "  --io-delay <ns>        Input/output delay (default: 20% of period)"
  puts "  --uncertainty <ns>     Clock uncertainty (default: 0.1)"
  puts "  --config <name>        small or maxperf (default: small)"
  puts "  --jobs <count>         Parallel Vivado jobs (default: 8)"
  puts "  --out <directory>      Output directory (default: build/vivado_ibex)"
  puts "  --help                 Show this help"
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]

set part           "xc7a100tcsg324-1"
set clk_period_ns  10.0
set io_delay_ns    ""
set uncertainty_ns 0.1
set ibex_config    "small"
set jobs           8
set out_dir        [file join $repo_root build vivado_ibex]

for {set i 0} {$i < [llength $argv]} {incr i} {
  set option [lindex $argv $i]
  if {$option eq "--help"} {
    usage
    exit 0
  }
  if {$i + 1 >= [llength $argv]} {
    error "Missing value for $option"
  }
  incr i
  set value [lindex $argv $i]
  switch -- $option {
    "--part"        { set part $value }
    "--period"      { set clk_period_ns $value }
    "--io-delay"    { set io_delay_ns $value }
    "--uncertainty" { set uncertainty_ns $value }
    "--config"      { set ibex_config $value }
    "--jobs"        { set jobs $value }
    "--out"         { set out_dir [file normalize $value] }
    default          { error "Unknown option: $option" }
  }
}

if {![string is double -strict $clk_period_ns] || $clk_period_ns <= 0.0} {
  error "--period must be a positive number"
}
if {$io_delay_ns eq ""} {
  set io_delay_ns [expr {$clk_period_ns * 0.20}]
}
if {![string is double -strict $io_delay_ns] || $io_delay_ns < 0.0} {
  error "--io-delay must be a non-negative number"
}
if {![string is double -strict $uncertainty_ns] || $uncertainty_ns < 0.0} {
  error "--uncertainty must be a non-negative number"
}
if {![string is integer -strict $jobs] || $jobs < 1} {
  error "--jobs must be a positive integer"
}
if {$out_dir eq $repo_root} {
  error "Refusing to use the repository root as --out"
}

# These values correspond to ibex_configs.yaml. Enum parameters use their
# integer encodings from rtl/ibex_pkg.sv.
switch -- $ibex_config {
  "small" {
    set generics [list \
      BaseIsa=0 RV32E=0 RV32M=2 RV32B=0 RV32ZC=3 RegFile=0 \
      BranchTargetALU=0 WritebackStage=0 ICache=0 ICacheECC=0 \
      BranchPredictor=0 DbgTriggerEn=0 SecureIbex=0 PMPEnable=0 \
      PMPGranularity=0 PMPNumRegions=4 MHPMCounterNum=0 MHPMCounterWidth=40]
  }
  "maxperf" {
    set generics [list \
      BaseIsa=0 RV32E=0 RV32M=3 RV32B=0 RV32ZC=3 RegFile=0 \
      BranchTargetALU=1 WritebackStage=1 ICache=0 ICacheECC=0 \
      BranchPredictor=0 DbgTriggerEn=0 SecureIbex=0 PMPEnable=0 \
      PMPGranularity=0 PMPNumRegions=4 MHPMCounterNum=0 MHPMCounterWidth=40]
  }
  default {
    error "Unsupported --config '$ibex_config'; choose small or maxperf"
  }
}

set project_dir [file join $out_dir project]
set report_dir  [file join $out_dir reports]
set generated_dir [file join $out_dir generated]
file mkdir $project_dir
file mkdir $report_dir
file mkdir $generated_dir

puts "============================================================"
puts "Ibex Vivado out-of-context flow"
puts "  part:          $part"
puts "  configuration: $ibex_config"
puts "  clock period:  $clk_period_ns ns ([format %.3f [expr {1000.0 / $clk_period_ns}]] MHz)"
puts "  I/O delay:     $io_delay_ns ns"
puts "  output:        $out_dir"
puts "============================================================"

create_project -force ibex_ooc $project_dir -part $part
set_property target_language Verilog [current_project]
set_property source_mgmt_mode All [current_project]

set prim_rtl        [file join $repo_root vendor lowrisc_ip ip prim rtl]
set prim_xilinx_rtl [file join $repo_root vendor lowrisc_ip ip prim_xilinx rtl]
set prim_generic_rtl [file join $repo_root vendor lowrisc_ip ip prim_generic rtl]

# Packages must be parsed before modules that import them.
set rtl_sources [list \
  [file join $prim_generic_rtl prim_ram_1p_pkg.sv] \
  [file join $prim_xilinx_rtl prim_pkg.sv] \
  [file join $prim_xilinx_rtl prim_xilinx_pkg.sv] \
  [file join $prim_rtl prim_util_pkg.sv] \
  [file join $prim_rtl prim_count_pkg.sv] \
  [file join $prim_rtl prim_cipher_pkg.sv] \
  [file join $prim_rtl prim_mubi_pkg.sv] \
  [file join $prim_rtl prim_secded_pkg.sv] \
  [file join $repo_root rtl ibex_pkg.sv] \
  [file join $repo_root rtl ibex_cheriot_pkg.sv] \
  [file join $prim_xilinx_rtl prim_and2.sv] \
  [file join $prim_xilinx_rtl prim_buf.sv] \
  [file join $prim_xilinx_rtl prim_clock_gating.sv] \
  [file join $prim_xilinx_rtl prim_clock_mux2.sv] \
  [file join $prim_xilinx_rtl prim_flop.sv] \
  [file join $prim_xilinx_rtl prim_ram_1p.sv] \
  [file join $prim_rtl prim_count.sv] \
  [file join $prim_rtl prim_lfsr.sv] \
  [file join $prim_rtl prim_fifo_sync_cnt.sv] \
  [file join $prim_rtl prim_fifo_sync.sv] \
  [file join $prim_rtl prim_subst_perm.sv] \
  [file join $prim_rtl prim_present.sv] \
  [file join $prim_rtl prim_prince.sv] \
  [file join $prim_rtl prim_ram_1p_adv.sv] \
  [file join $prim_rtl prim_ram_1p_scr.sv] \
  [file join $prim_rtl prim_onehot_enc.sv] \
  [file join $prim_rtl prim_onehot_mux.sv] \
  [file join $prim_rtl prim_secded_inv_22_16_dec.sv] \
  [file join $prim_rtl prim_secded_inv_22_16_enc.sv] \
  [file join $prim_rtl prim_secded_inv_hamming_22_16_dec.sv] \
  [file join $prim_rtl prim_secded_inv_hamming_22_16_enc.sv] \
  [file join $prim_rtl prim_secded_inv_28_22_dec.sv] \
  [file join $prim_rtl prim_secded_inv_28_22_enc.sv] \
  [file join $prim_rtl prim_secded_inv_39_32_dec.sv] \
  [file join $prim_rtl prim_secded_inv_39_32_enc.sv] \
  [file join $prim_rtl prim_secded_inv_hamming_39_32_dec.sv] \
  [file join $prim_rtl prim_secded_inv_hamming_39_32_enc.sv] \
  [file join $prim_rtl prim_secded_inv_64_57_dec.sv] \
  [file join $prim_rtl prim_secded_inv_64_57_enc.sv] \
  [file join $repo_root vendor pulp_common_cells rtl stream_fork.sv] \
  [file join $repo_root vendor pulp_common_cells rtl stream_join_dynamic.sv] \
  [file join $repo_root rtl ibex_cheriot_ex.sv] \
  [file join $repo_root rtl ibex_alu.sv] \
  [file join $repo_root rtl ibex_branch_predict.sv] \
  [file join $repo_root rtl ibex_compressed_decoder.sv] \
  [file join $repo_root rtl ibex_controller.sv] \
  [file join $repo_root rtl ibex_cs_registers.sv] \
  [file join $repo_root rtl ibex_csr.sv] \
  [file join $repo_root rtl ibex_counter.sv] \
  [file join $repo_root rtl ibex_decoder.sv] \
  [file join $repo_root rtl ibex_ex_block.sv] \
  [file join $repo_root rtl ibex_fetch_fifo.sv] \
  [file join $repo_root rtl ibex_id_stage.sv] \
  [file join $repo_root rtl ibex_if_stage.sv] \
  [file join $repo_root rtl ibex_load_store_unit.sv] \
  [file join $repo_root rtl ibex_multdiv_fast.sv] \
  [file join $repo_root rtl ibex_multdiv_slow.sv] \
  [file join $repo_root rtl ibex_prefetch_buffer.sv] \
  [file join $repo_root rtl ibex_pmp.sv] \
  [file join $repo_root rtl ibex_wb_stage.sv] \
  [file join $repo_root rtl ibex_dummy_instr.sv] \
  [file join $repo_root rtl ibex_icache.sv] \
  [file join $repo_root rtl ibex_core.sv] \
  [file join $repo_root rtl ibex_register_file_ff.sv] \
  [file join $repo_root rtl ibex_register_file_fpga.sv] \
  [file join $repo_root rtl ibex_register_file_latch.sv] \
  [file join $repo_root rtl ibex_trvk.sv] \
  [file join $repo_root rtl ibex_lockstep.sv] \
  [file join $repo_root rtl ibex_top.sv]]

foreach source $rtl_sources {
  if {![file exists $source]} {
    error "RTL source not found: $source"
  }
}

add_files -fileset sources_1 -norecurse $rtl_sources
set_property file_type SystemVerilog [get_files $rtl_sources]
set_property include_dirs [list \
  $prim_rtl \
  $prim_xilinx_rtl \
  $prim_generic_rtl \
  [file join $repo_root vendor lowrisc_ip dv sv dv_utils] \
  [file join $repo_root rtl]] [get_filesets sources_1]
set_property verilog_define [list SYNTHESIS FPGA_XILINX] [get_filesets sources_1]
set_property top ibex_top [get_filesets sources_1]
set_property generic $generics [get_filesets sources_1]
update_compile_order -fileset sources_1

# Generate an XDC matching the requested period. In OOC mode, ports are not
# mapped to package pins. Fixed I/O delays keep external paths constrained.
set xdc_file [file join $generated_dir ibex_ooc.xdc]
set xdc [open $xdc_file w]
puts $xdc "create_clock -name clk_i -period $clk_period_ns \[get_ports clk_i\]"
puts $xdc "set_clock_uncertainty $uncertainty_ns \[get_clocks clk_i\]"
puts $xdc "set_false_path -from \[get_ports rst_ni\]"
puts $xdc "set_case_analysis 0 \[get_ports test_en_i\]"
puts $xdc "set_input_delay -clock \[get_clocks clk_i\] -max $io_delay_ns \[get_ports -filter {DIRECTION == IN && NAME != clk_i && NAME != rst_ni && NAME != test_en_i}\]"
puts $xdc "set_input_delay -clock \[get_clocks clk_i\] -min 0.0 \[get_ports -filter {DIRECTION == IN && NAME != clk_i && NAME != rst_ni && NAME != test_en_i}\]"
puts $xdc "set_output_delay -clock \[get_clocks clk_i\] -max $io_delay_ns \[all_outputs\]"
puts $xdc "set_output_delay -clock \[get_clocks clk_i\] -min 0.0 \[all_outputs\]"
close $xdc

add_files -fileset constrs_1 -norecurse $xdc_file
set_property used_in_synthesis true [get_files $xdc_file]
set_property used_in_implementation true [get_files $xdc_file]

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
  -value {-mode out_of_context} -objects [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
  error "Synthesis failed; see [get_property DIRECTORY [get_runs synth_1]]/runme.log"
}

open_run synth_1
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $report_dir post_synth_timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
  -file [file join $report_dir post_synth_critical_paths.rpt]
report_utilization -hierarchical \
  -file [file join $report_dir post_synth_utilization.rpt]
close_design

launch_runs impl_1 -to_step route_design -jobs $jobs
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "route_design Complete!"} {
  error "Implementation failed; see [get_property DIRECTORY [get_runs impl_1]]/runme.log"
}

open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained \
  -file [file join $report_dir post_route_timing_summary.rpt]
report_timing -delay_type max -max_paths 50 -sort_by group -path_type full_clock_expanded \
  -file [file join $report_dir post_route_critical_paths.rpt]
report_utilization -hierarchical \
  -file [file join $report_dir post_route_utilization.rpt]
report_clock_utilization \
  -file [file join $report_dir post_route_clock_utilization.rpt]
report_methodology \
  -file [file join $report_dir post_route_methodology.rpt]
report_drc \
  -file [file join $report_dir post_route_drc.rpt]
write_checkpoint -force [file join $out_dir ibex_post_route.dcp]

set summary_file [file join $report_dir fmax_summary.txt]
set summary [open $summary_file w]
set worst_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_paths] > 0} {
  set wns [get_property SLACK [lindex $worst_paths 0]]
  set estimated_period [expr {$clk_period_ns - $wns}]
  if {$estimated_period > 0.0} {
    set estimated_fmax [expr {1000.0 / $estimated_period}]
  } else {
    set estimated_fmax Inf
  }
  puts $summary "Requested period (ns): $clk_period_ns"
  puts $summary "Requested frequency (MHz): [format %.3f [expr {1000.0 / $clk_period_ns}]]"
  puts $summary "Post-route WNS (ns): $wns"
  puts $summary "Rough Fmax estimate (MHz): [format %.3f $estimated_fmax]"
  puts $summary "Note: rerun with a period near this estimate to obtain a valid result."
  puts "Post-route WNS: $wns ns"
  puts "Rough Fmax estimate: [format %.3f $estimated_fmax] MHz"
} else {
  puts $summary "No setup timing path was found. Check post_route_timing_summary.rpt."
  puts "WARNING: No setup timing path was found."
}
close $summary

puts "============================================================"
puts "Vivado flow complete"
puts "  timing: $report_dir/post_route_timing_summary.rpt"
puts "  Fmax:   $summary_file"
puts "  DCP:    $out_dir/ibex_post_route.dcp"
puts "============================================================"
close_project
