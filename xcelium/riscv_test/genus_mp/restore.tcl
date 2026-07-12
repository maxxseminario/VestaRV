
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xrun /home/mseminario2/lib/TSMC65-IP/tsmc/pads/tphn65gpgv2od3_sl/verilog/tphn65gpgv2od3_sl.v /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/verilog/tsmc65_hvt_sc_adv10.v /home/mseminario2/chips/myshkin/ip/rom_hvt_pg/rom_hvt_pg.v /home/mseminario2/chips/myshkin/ip/sram1p16k_hvt_pg/sram1p16k_hvt_pg.v ../../../genus/out/MCU_MP.genus.v ../../../hdl/common/constants.vhd ../../../hdl/common/macros/macros.vhd ../../../hdl/common/MemoryMap.vhd ../../../hdl/common/tb/serial_flash.vhd ../../../hdl/common/sim/GlitchFilter_behav.vhd ../../../hdl/common/sim/PowerOnResetCheng_behav.vhd ../../../hdl/common/sim/OscillatorCurrentStarved_simulation.vhd ../../../hdl/common/tb/tb_defs.vhd ./riscv_tb_gate.vhd -top riscv_tb -generic TEST_FILE=>"../rcf/xxxrv32ui-p-simple.rcf" -sdf_cmd_file MCU_MP.sdfcmd -sdfstats log/sdf_stats.log -v200x -work work -access +rwc -controlrelax nlstex -relax -input ../../disable_x_warnings.tcl -input log/gate_run.tcl -input restore.tcl
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
alias . run
alias quit exit

simvision -input restore.tcl.svcf
