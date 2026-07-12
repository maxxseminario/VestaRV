
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xrun -top riscv_tb -sdf_cmd_file MCU.sdfcmd -sdfstats log/sdf_stats.log -v200x -work work -access +r -controlrelax nlstex -relax -input ./restore.tcl /home/mseminario2/lib/TSMC65-IP/tsmc/pads/tphn65gpgv2od3_sl/verilog/tphn65gpgv2od3_sl.v /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/verilog/tsmc65_hvt_sc_adv10.v ../../../hdl/myshkin/constants.vhd ../../../hdl/myshkin/macros/macros.vhd ../../../hdl/myshkin/MemoryMap.vhd ../../../hdl/myshkin/tb/serial_flash.vhd ../../../hdl/myshkin/sim/GlitchFilter_behav.vhd ../../../hdl/myshkin/sim/PowerOnResetCheng_behav.vhd ../../../hdl/myshkin/sim/OscillatorCurrentStarved_simulation.vhd ../../../ip/rom_hvt_pg/rom_hvt_pg.v ../../../ip/sram1p16k_hvt_pg/sram1p16k_hvt_pg.v ../../../ip/sram1p8k_hvt_pg/sram1p8k_hvt_pg.v ../../../ip/sram1p1k_hvt_pg/sram1p1k_hvt_pg.v ../../../genus/out/MCU.genus.v ../../../hdl/myshkin/tb/tb_defs.vhd ../../../hdl/myshkin/tb/TestbenchLibrary.vhd ../../../hdl/myshkin/tb/rv4th_tb.vhd ../../../hdl/myshkin/tb/riscv_tb.vhd -input restore.tcl
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
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :clk_hfxt :resetn
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :clk_hfxt :resetn
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :clk_hfxt :resetn
probe -create -database waves :dut.resetn :dut.resetn_por :dut.resetn_in
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :clk_hfxt :resetn
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :clk_hfxt :resetn
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :spi_slave_flash:\$PROCESS_000:Address :spi_slave_flash:state :spi_slave_flash:SPCLK :spi_slave_flash:CSb :spi_slave_flash:MOSI :spi_slave_flash:MISO :spi_slave_flash:awake :dut.core.pc_next
probe -create -database waves :dut.timer0.write_data :dut.timer0.read_data :dut.timer0.mclk :dut.timer0.smclk :dut.timer0.clk_mem :dut.timer0.clk_lfxt :dut.timer0.clk_hfxt
probe -create -database waves :clk_hfxt :resetn
probe -create -database waves :dut.resetn :dut.resetn_por :dut.resetn_in
probe -create -database waves :dut.afe0.AFE_CR :dut.saradc0.SARADC_CR :dut.irq_comb :dut.uart0.clk_mem :dut.uart0.read_data :dut.uart0.wen :dut.uart0.write_data :dut.uart0.clk_tx :dut.uart0.UART_CR :dut.uart0.UART_TX :dut.uart0.UART_RX :dut.uart0.UART_RX_ltch :dut.uart0.UART_SR_ltch :dut.uart0.RX_IN :dut.uart0.TX_OUT

simvision -input restore.tcl.svcf
