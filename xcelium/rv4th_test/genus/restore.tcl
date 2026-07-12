
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xrun -top rv4th_tb -sdf_cmd_file MCU.sdfcmd -sdfstats log/sdf_stats.log -sdf_verbose -v200x -work work -access +r -controlrelax nlstex -relax /home/mseminario2/lib/TSMC65-IP/tsmc/pads/tphn65gpgv2od3_sl/verilog/tphn65gpgv2od3_sl.v /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/verilog/tsmc65_hvt_sc_adv10.v ../../../hdl/myshkin/constants.vhd ../../../hdl/myshkin/macros/macros.vhd ../../../hdl/myshkin/MemoryMap.vhd ../../../hdl/myshkin/tb/serial_flash.vhd ../../../hdl/myshkin/sim/GlitchFilter_behav.vhd ../../../hdl/myshkin/sim/PowerOnResetCheng_behav.vhd ../../../hdl/myshkin/sim/OscillatorCurrentStarved_simulation.vhd ../../../ip/rom_hvt_pg/rom_hvt_pg.v ../../../ip/sram1p16k_hvt_pg/sram1p16k_hvt_pg.v ../../../ip/sram1p8k_hvt_pg/sram1p8k_hvt_pg.v ../../../ip/sram1p1k_hvt_pg/sram1p1k_hvt_pg.v ../../../genus/out/MCU.genus.v ../../../hdl/myshkin/tb/tb_defs.vhd ../../../hdl/myshkin/tb/TestbenchLibrary.vhd ../../../hdl/myshkin/tb/rv4th_tb.vhd ../../../hdl/myshkin/tb/rv4th_tb.vhd -s -input restore.tcl
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
database -open -shm -into waves.shm waves -default
probe -create -database waves :dut.spi0.en_clk_baud_src
probe -create -database waves :dut.spi0.clk_baud
probe -create -database waves :dut.spi1.wen
probe -create -database waves :dut.spi1.rc_gclk
probe -create -database waves :dut.spi0.addr_periph
probe -create -database waves :dut.npu0.Decision :dut.npu0.NpuState :dut.npu0.NpuDone :dut.npu0.NpuClkEn :dut.npu0.NpuClk :dut.npu0.NpuActive :dut.npu0.NPUWVSAR :dut.npu0.NPUOVSAR :dut.npu0.NPUIVSAR :dut.npu0.NPUCR
probe -create -database waves :dut.core.datapath_inst.rf.@{\registers[31] } :dut.core.datapath_inst.rf.@{\registers[30] } :dut.core.datapath_inst.rf.@{\registers[29] } :dut.core.datapath_inst.rf.@{\registers[28] } :dut.core.datapath_inst.rf.@{\registers[27] } :dut.core.datapath_inst.rf.@{\registers[26] } :dut.core.datapath_inst.rf.@{\registers[25] } :dut.core.datapath_inst.rf.@{\registers[24] } :dut.core.datapath_inst.rf.@{\registers[23] } :dut.core.datapath_inst.rf.@{\registers[22] } :dut.core.datapath_inst.rf.@{\registers[21] } :dut.core.datapath_inst.rf.@{\registers[20] } :dut.core.datapath_inst.rf.@{\registers[19] } :dut.core.datapath_inst.rf.@{\registers[18] } :dut.core.datapath_inst.rf.@{\registers[17] } :dut.core.datapath_inst.rf.@{\registers[16] } :dut.core.datapath_inst.rf.@{\registers[15] } :dut.core.datapath_inst.rf.@{\registers[14] } :dut.core.datapath_inst.rf.@{\registers[13] } :dut.core.datapath_inst.rf.@{\registers[12] } :dut.core.datapath_inst.rf.@{\registers[11] } :dut.core.datapath_inst.rf.@{\registers[10] } :dut.core.datapath_inst.rf.@{\registers[9] } :dut.core.datapath_inst.rf.@{\registers[8] } :dut.core.datapath_inst.rf.@{\registers[7] } :dut.core.datapath_inst.rf.@{\registers[6] } :dut.core.datapath_inst.rf.@{\registers[5] } :dut.core.datapath_inst.rf.@{\registers[4] } :dut.core.datapath_inst.rf.@{\registers[3] } :dut.core.datapath_inst.rf.@{\registers[1] } :dut.core.irq_handler_inst.irq_active :dut.core.irq_handler_inst.irq_restore :dut.core.irq_handler_inst.irq_save :dut.core.irq_handler_inst.irq_found_reg :dut.core.irq_handler_inst.irq :dut.core.irq_handler_inst.irq_save_ack :dut.core.irq_handler_inst.isr_ret
probe -create -database waves :prt1
probe -create -database waves :dut.core.irq_handler_inst.current_state
probe -create -database waves :dut.spi0.n_202
probe -create -database waves :dut.spi1.s_tx_sreg
probe -create -database waves :prt2 :prt2_dir :prt2_in :prt2_out :prt2_ren :dut.gpio1.write_data :dut.gpio1.wen :dut.gpio1.read_data :dut.gpio1.addr_periph :dut.gpio1.PxDIR :dut.gpio1.PxOUT :dut.gpio1.PxSEL :dut.spi1.SPIxTX :dut.spi1.SPIxCR :dut.spi1.mosi_in :dut.spi1.miso_out :dut.spi1.cs_in :dut.spi1.sck_in
probe -create -database waves :dut.spi0.n_4 :dut.spi0.n_175 :dut.spi0.n_369
probe -create -database waves :dut.core.pc_next
probe -create -database waves :dut.spi0.m_tx_sreg
probe -create -database waves :dut.spi0.tx_in_progress
probe -create -database waves :dut.GWEN
probe -create -database waves :dut.uart1.clr_start_tx :dut.uart1.addr_periph
probe -create -database waves :dut.uart0.ud_cntr :dut.uart0.ud_cntr_next
probe -create -database waves :dut.spi0.baud_counter
probe -create -database waves :dut.core.pc :dut.core.pc_src :dut.core.datapath_inst.mainalu.divider.D_Abs :dut.core.datapath_inst.mainalu.divider.Q :dut.core.datapath_inst.mainalu.divider.R :dut.core.datapath_inst.mainalu.divider.a :dut.core.datapath_inst.mainalu.divider.clk :dut.core.datapath_inst.mainalu.divider.cnt :dut.core.datapath_inst.mainalu.divider.b :dut.core.current_state
probe -create -database waves :dut.core.wen :dut.core.wen_controller :dut.core.datapath_inst.sp_write_en :dut.core.datapath_inst.sp_out :dut.core.datapath_inst.sp_in
probe -create -database waves :dut.core.en_clk_cpu :dut.core.irq_handler_inst.ivt_jump :dut.core.irq_handler_inst.ivt_entry
probe -create -database waves :dut.spi0.SPIxRX_ltch
probe -create -database waves :dut.core.datapath_inst.loadextender.mask_latched :dut.core.datapath_inst.loadextender.mask :dut.core.datapath_inst.loadextender.funct3 :dut.core.datapath_inst.loadextender.extended_data :dut.core.datapath_inst.loadextender.clk
probe -create -database waves :dut.core.datapath_inst.alu_control
probe -create -database waves :dut.spi1.write_data :dut.spi1.read_data
probe -create -database waves :dut.uart1.tx_in_progress :dut.uart1.rx_in_progress :dut.uart1.clr_rx_in_progress
probe -create -database waves :dut.spi0.clr_start_tx
probe -create -database waves :dut.spi0.clr_spi_teif
probe -create -database waves :dut.system0.resetn_sync
probe -create -database waves :dut.spi1.s_SPIxRX
probe -create -database waves :dut.uart1.en_clk_baud :dut.uart1.en_baud_clk_src :dut.uart1.baud_cntr :dut.uart1.baud_clk_src
probe -create -database waves :dut.core.datapath_inst.mainalu.ALU_result :dut.core.datapath_inst.result_Src
probe -create -database waves :dut.spi1.s_rx_sreg :dut.spi1.s_counter :dut.spi1.sck_slave
probe -create -database waves :dut.uart0.RX_IN :dut.uart0.TX_OUT :dut.uart1.TX_OUT :dut.uart1.RX_IN
probe -create -database waves :dut.gpio0.PxDIR
probe -create -database waves :dut.spi0.mosi_out
probe -create -database waves :dut.spi0.clk_baud_src
probe -create -database waves :dut.spi0.m_spi_tcif
probe -create -database waves :dut.system0.resetn_por
probe -create -database waves :dut.spi0.m_rx_sreg :dut.spi0.miso_in
probe -create -database waves :dut.uart0.rx_sr :dut.uart0.start_tx :dut.uart0.tx_sr :dut.uart0.clk_tx :dut.uart0.clk_mem :dut.uart0.clk_baud :dut.uart0.clk :dut.uart0.UART_TX :dut.uart0.UART_SR_ltch :dut.uart0.UART_RX_ltch :dut.uart0.UART_RX :dut.uart0.UART_CR :dut.uart0.UART_BR :dut.uart1.clk_baud :dut.uart1.clk_mem :dut.uart1.clk_tx :dut.uart1.UART_TX :dut.uart1.UART_SR_ltch :dut.uart1.UART_RX_ltch :dut.uart1.UART_RX :dut.uart1.UART_CR :dut.uart1.UART_BR :dut.uart1.read_data :dut.uart1.write_data :dut.uart1.tx_sr :dut.uart1.start_tx :dut.uart1.rx_sr
probe -create -database waves :dut.core.datapath_inst.mainalu.divider.start :dut.core.datapath_inst.mainalu.divider.start_reg
probe -create -database waves :dut.gpio0.prt_out_out
probe -create -database waves :dut.gpio0.wen
probe -create -database waves :dut.spi0.n_382 :dut.spi0.m_spi_teif
probe -create -database waves :dut.core.reg_write_dp
probe -create -database waves :dut.spi0.n_195
probe -create -database waves :dut.core.resetn
probe -create -database waves :dut.gpio0.alt_func_dir_in :dut.gpio0.alt_func_ren_in
probe -create -database waves :dut.gpio0.addr_periph
probe -create -database waves :dut.core.pc_target :dut.core.pc_plus_4 :dut.core.instr_curr :dut.core.instr_decomp :dut.core.instr_lower_half :dut.core.instr_to_decomp :dut.core.is_compressed
probe -create -database waves :dut.core.datapath_inst.mainalu.divider.N_Abs :dut.core.datapath_inst.mainalu.divider.Q_unsigned :dut.core.datapath_inst.mainalu.divider.R_unsigned :dut.core.datapath_inst.mainalu.divider.complete :dut.core.datapath_inst.mainalu.divider.resetn :dut.core.datapath_inst.mainalu.divider.rdy :dut.core.datapath_inst.mainalu.divider.state
probe -create -database waves :dut.spi1.mosi_dir :dut.spi1.sck_dir
probe -create -database waves :dut.spi0.s_spi_tcif :dut.spi0.s_spi_teif
probe -create -database waves :dut.core.datapath_inst.mainalu.divider.sel_rem :dut.core.datapath_inst.mainalu.divider.sel_signed :dut.core.datapath_inst.mainalu.divider.result :dut.core.datapath_inst.mainalu.divider.N_u :dut.core.datapath_inst.mainalu.divider.D_u
probe -create -database waves :dut.gpio0.alt_func_out_in :dut.gpio0.PxSEL
probe -create -database waves :dut.spi0.n_87
probe -create -database waves :dut.system0.addr_periph :dut.system0.clk_mem :dut.system0.en_mem :dut.system0.mclk_out :dut.system0.resetn_sys :dut.system0.write_data :dut.system0.read_data :dut.system0.SYS_WDT_VAL :dut.system0.SYS_WDT_CR :dut.system0.SYS_CRC_STATE :dut.system0.SYS_CRC_DATA :dut.system0.SYS_CLK_DIV_CR :dut.system0.SYS_CLK_CR
probe -create -database waves :dut.mem_en_periph :dut.gpio0.alt_func_out_in :dut.gpio0.alt_func_dir_in :dut.gpio0.prt_dir_out :dut.gpio0.alt_func_ren_in :dut.gpio0.PxOUT :dut.gpio0.PxSEL :dut.gpio0.write_data :dut.gpio0.prt_out_out :dut.gpio0.wen :dut.gpio0.addr_periph :dut.gpio0.en :dut.gpio0.PxDIR :dut.prt1_ren :dut.prt1_dir :dut.prt1_out :dut.prt1_in
probe -create -database waves :dut.prt1_in :dut.prt1_out
probe -create -database waves :dut.system0.crc_prev
probe -create -database waves :dut.gpio0.en :dut.gpio0.PxOUT
probe -create -database waves :dut.core.datapath_inst.mainalu.div_start :dut.core.datapath_inst.mainalu.div_sel_signed :dut.core.datapath_inst.mainalu.div_sel_rem :dut.core.datapath_inst.mainalu.div_result :dut.core.datapath_inst.mainalu.div_rdy :dut.core.datapath_inst.mainalu.div_complete :dut.core.datapath_inst.mainalu.clk :dut.core.datapath_inst.mainalu.b :dut.core.datapath_inst.mainalu.alu_state :dut.core.datapath_inst.mainalu.alu_done :dut.core.datapath_inst.mainalu.alu_control :dut.core.datapath_inst.mainalu.a :dut.core.datapath_inst.mainalu.Zero
probe -create -database waves :dut.core.data_addr
probe -create -database waves :dut.core.datapath_inst.rf.a0 :dut.core.datapath_inst.rf.a1 :dut.core.datapath_inst.rf.a2 :dut.core.datapath_inst.rf.a3 :dut.core.datapath_inst.rf.clk :dut.core.datapath_inst.rf.resetn :dut.core.datapath_inst.rf.wd3 :dut.core.datapath_inst.rf.we3
probe -create -database waves :dut.ram0.PGEN :dut.ram0.GWEN :dut.ram0.D :dut.ram0.A :dut.ram0.WEN :dut.ram0.CEN :dut.ram0.CLK :dut.ram0.Q
probe -create -database waves :dut.spi0.sck_dir
probe -create -database waves :dut.spi0.n_69
probe -create -database waves :dut.gpio1.write_data :dut.gpio1.wen :dut.gpio1.read_data :dut.gpio1.addr_periph :dut.spi1.SPIxTX :dut.spi1.SPIxCR :dut.spi1.s_SPIxRX :dut.spi1.write_data :dut.spi1.read_data :dut.spi1.s_rx_sreg :dut.spi1.s_tx_sreg :dut.spi1.s_counter :dut.spi1.sck_in :dut.spi1.sck_slave :dut.spi1.mosi_in :dut.spi1.miso_out :dut.spi1.cs_in :dut.spi0.en_mem :dut.spi0.clk_mem :dut.spi0.read_data :dut.spi0.write_data :dut.spi0.wen :dut.spi0.SPIxTX :dut.spi0.SPIxCR :dut.spi0.m_rx_sreg :dut.spi0.miso_in :dut.spi0.m_tx_sreg :dut.spi0.clk_baud :dut.spi0.m_counter :prt1 :dut.prt1_ren :dut.prt1_dir :dut.prt1_out :dut.prt1_in :prt2 :prt2_dir :prt2_in :prt2_out :prt2_ren :dut.mem_addr :dut.gpio0.alt_func_out_in :dut.gpio0.alt_func_dir_in :dut.gpio0.prt_dir_out :dut.gpio0.alt_func_ren_in :dut.gpio0.PxDIR :dut.gpio0.PxOUT :dut.gpio0.PxSEL :dut.gpio0.read_data :dut.gpio0.write_data :dut.gpio0.prt_out_out :dut.gpio1.PxDIR :dut.gpio1.PxOUT :dut.gpio1.PxSEL
probe -create -database waves :dut.gpio0.write_data
probe -create -database waves :dut.spi1.en_mem :dut.spi1.clk_mem
probe -create -database waves :dut.@{\mem_dout[0] } :dut.clk_mem[0]
probe -create -database waves :dut.spi0.start_tx
probe -create -database waves :dut.gpio0.read_data
probe -create -database waves :dut.prt1_dir :dut.prt1_ren
probe -create -database waves :dut.spi0.SPIxSR_ltch
probe -create -database waves :dut.spi0.wen :dut.spi0.read_data :dut.spi0.write_data :dut.spi0.SPIxTX :dut.spi0.SPIxCR
probe -create -database waves :dut.spi0.m_counter
probe -create -database waves :dut.core.repeat_if :dut.core.read_data
probe -create -database waves :dut.timer0.read_data :dut.timer0.write_data :dut.timer1.read_data :dut.timer1.write_data
probe -create -database waves :dut.mem_addr
probe -create -database waves :dut.adddec0.resetn :dut.adddec0.mem_en :dut.adddec0.mem_en_periph :dut.adddec0.mem_sel_int :dut.adddec0.mem_sel_periph_int :dut.adddec0.clk
probe -create -database waves :dut.spi0.en_mem :dut.spi0.clk_mem
probe -create -database waves :dut.spi0.n_88
probe -create -database waves :dut.spi0.clk
probe -create -database waves :dut.gpio0.prt_dir_out
probe -create -database waves :dut.mem_en

simvision -input restore.tcl.svcf
