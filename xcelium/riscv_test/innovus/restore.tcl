
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xrun -top riscv_tb -sdf_cmd_file MCU.sdfcmd -sdfstats log/sdf_stats.log -v200x -work work -access +r -controlrelax nlstex -relax /home/mseminario2/lib/TSMC65-IP/tsmc/pads/tphn65gpgv2od3_sl/verilog/tphn65gpgv2od3_sl.v /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/verilog/tsmc65_hvt_sc_adv10.v ../../../hdl/myshkin/constants.vhd ../../../hdl/myshkin/macros/macros.vhd ../../../hdl/myshkin/MemoryMap.vhd ../../../ip/rom_hvt_pg/rom_hvt_pg.v ../../../ip/sram1p16k_hvt_pg/sram1p16k_hvt_pg.v ../../../innovus/myshkin/out/MCU.xsim.v ../../../hdl/myshkin/tb/serial_flash.vhd ../../../hdl/myshkin/sim/GlitchFilter_behav.vhd ../../../hdl/myshkin/sim/PowerOnResetCheng_behav.vhd ../../../hdl/myshkin/sim/OscillatorCurrentStarved_simulation.vhd ../../../hdl/myshkin/tb/tb_defs.vhd ../../../hdl/myshkin/tb/riscv_tb.vhd ../../../hdl/myshkin/tb/riscv_tb.vhd -s -input restore.tcl
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
alias . run
alias quit exit
database -open -shm -into waves.shm waves -default
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.prt1_out[6] :prt1[6]
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.prt1_out[6] :prt1[6]
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :ram_file_name
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.irq_comb
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.prt1_out[6] :prt1[6]
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.irq_comb
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.irq_comb
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :ram_file_name
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.irq_comb
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.prt1_out[6] :prt1[6]
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.irq_comb
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.clk_mux.resetn :dut.timer1.clk_mux.Sel :dut.timer1.clk_mux.EnQ :dut.timer1.clk_mux.ClkOut :dut.timer1.clk_mux.ClkIn :dut.timer1.clk_mux.ClkGated :dut.timer1.clk_mux.ClkEn :dut.timer1.clock_gate_timer.En :dut.timer1.clock_gate_timer.ClkOut :dut.timer1.clock_gate_timer.ClkIn
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.irq_comb
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.en_mem :dut.spi0.tx_in_progress
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :prt1[6]
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :dut.spi0.s_spi_tcif
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :dut.timer1.read_data :dut.timer1.write_data :dut.timer1.control_reg :dut.timer1.clock_source :dut.timer1.clk_mem :dut.timer1.timer_value_write :dut.timer1.timer_value
probe -create -database waves :dut.core.pc :dut.core.instr_curr
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :dut.core.clk_cpu :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.irq_active :dut.core.irq_save :dut.core.irq_restore :dut.uart1.irq_rc
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.irq_comb
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :dut.spi0.clk_baud_src :dut.spi0.baud_counter
probe -create -database waves :dut.ram0.CEN :dut.ram0.D :dut.ram0.CLK :dut.ram0.GWEN :dut.ram0.Q :dut.ram0.A :dut.ram0.WEN
probe -create -database waves :ram_file_name
probe -create -database waves :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:ReadyBit :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:ProgramAddress :spi_slave_flash:awake :dut.mclk :dut.mem_addr :dut.smclk :dut.read_data :dut.write_data :dut.mem_en :dut.mem_en_periph
probe -create -database waves :ram_file_name

simvision -input restore.tcl.svcf
