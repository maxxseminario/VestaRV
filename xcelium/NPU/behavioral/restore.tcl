
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xrun ../../../hdl/MCU/commune/fixed_float_types_c.vhdl ../../../hdl/MCU/commune/fixed_pkg_c.vhdl ../../../hdl/MCU/constants.vhd ../../../hdl/MCU/MemoryMap.vhd ../../../hdl/MCU/commune/ClkGate.vhd ../../../hdl/MCU/ARM_IP_RAM.vhd ../../../hdl/MCU/commune/FPMac.vhd ../../../hdl/MCU/commune/FPSigmoid.vhd ../../../hdl/MCU/periph/NPU.vhd ../../../hdl/MCU/tb/NPU_tb.vhd -top NPU_tb -v200x -work work -access +r -controlrelax nlstex -relax -s -input restore.tcl
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
set pack_assert_off {std_logic_arith numeric_std}
set severity_pack_assert_off warning
set assert_output_stop_level failed
set tcl_debug_level 0
set relax_path_name 1
set vhdl_vcdmap XX01ZX01X
set intovf_severity_level warning
set probe_screen_format 0
set rangecnst_severity_level warning
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
probe -create -database waves :Clk :ResetN :MabMmrA :MabMmrCEN :MabMmrD :MabMmrCLK :MabMmrQ :MabMmrWEN :MabSramA :MabSramCEN :MabSramCLK :MabSramD :MabSramGWEN :MabSramPGEN :MabSramQ :MabSramWEN
probe -create -database waves :NPU_INST:NpuActive
probe -create -database waves :NpuSramWEN_out :NpuSramGWEN_out :NpuSramQ_out :NpuSramD_out :NpuSramCLK_out :NpuSramCEN_out :NpuSramA_out
probe -create -database waves :NpuSramQ
probe -create -database waves :SRAM_INST:WEN :SRAM_INST:RETN :SRAM_INST:Q :SRAM_INST:PGEN :SRAM_INST:GWEN :SRAM_INST:EMA :SRAM_INST:D :SRAM_INST:CLK :SRAM_INST:CEN :SRAM_INST:A
probe -create -database waves :NPU_INST:NpuState

simvision -input restore.tcl.svcf
