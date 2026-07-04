
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xmsim -64bit -licqueue work.tb_rv32ui_p_simple:behavioral -tcl -update -input restore.tcl
#

set tcl_prompt1 {puts -nonewline "xcelium> "}
set tcl_prompt2 {puts -nonewline "> "}
set vlog_format %h
set vhdl_format %v
set real_precision 6
set display_unit auto
set time_unit module
set heap_garbage_size -200
set heap_garbage_time 0
set assert_report_level note
set assert_stop_level error
set autoscope yes
set assert_1164_warnings yes
set pack_assert_off {}
set severity_pack_assert_off {note warning}
set assert_output_stop_level failed
set tcl_debug_level 0
set relax_path_name 1
set vhdl_vcdmap XX01ZX01X
set intovf_severity_level ERROR
set probe_screen_format 0
set rangecnst_severity_level ERROR
set textio_severity_level ERROR
set vital_timing_checks_on 1
set vlog_code_show_force 0
set assert_count_attempts 1
set tcl_all64 false
set tcl_runerror_exit false
set assert_report_incompletes 0
set show_force 1
set force_reset_by_reinvoke 0
set tcl_relaxed_literal 0
set probe_exclude_patterns {}
set probe_packed_limit 4k
set probe_unpacked_limit 16k
set assert_internal_msg no
set svseed 1
set assert_reporting_mode 0
set vcd_compact_mode 0
database -open -shm -into waves.shm waves -default
probe -create -database waves :uut:dut:mclk :uut:dut:clk_cpu :uut:dut:sh_acked :uut:dut:sh_sel :uut:dut:arb_done :uut:dut:arb_req :uut:dut:arb_gnt :uut:dut:arb_we :uut:dut:core_mem_ready :uut:dut:core_mem_ready_g :uut:dut:data_addr :uut:dut:sh_rdata_reg :uut:dut:sh_en :uut:dut:sh_we :uut:dut:dbg_cpu_ticks :uut:dut:core:current_state
probe -create -database waves :uut:dut:resetn

simvision -input restore.tcl.svcf
