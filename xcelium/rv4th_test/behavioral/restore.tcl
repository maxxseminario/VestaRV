
# XM-Sim Command File
# TOOL:	xmsim(64)	20.09-s006
#
#
# You can restore this configuration with:
#
#      xrun /home/mseminario2/lib/TSMC65-IP/tsmc/pads/tphn65gpgv2od3_sl/verilog/tphn65gpgv2od3_sl.v ../../../hdl/MCU/commune/fixed_float_types_c.vhdl ../../../hdl/MCU/commune/fixed_pkg_c.vhdl ../../../hdl/MCU/commune/FPMac.vhd ../../../hdl/MCU/commune/FPSigmoid.vhd ../../../hdl/MCU/commune/TieLow.vhd ../../../hdl/MCU/constants.vhd ../../../hdl/MCU/macros/macros.vhd ../../../hdl/MCU/MemoryMap.vhd ../../../hdl/MCU/tb/serial_flash.vhd ../../../hdl/MCU/sim/ClkGate.vhd ../../../hdl/MCU/sim/ClockMuxGlitchFree.vhd ../../../hdl/MCU/sim/PowerOnResetCheng_behav.vhd ../../../hdl/MCU/sim/OscillatorCurrentStarved_simulation.vhd ../../../hdl/MCU/commune/CRC16.vhd ../../../hdl/MCU/sim/GlitchFilter_behav.vhd ../../../hdl/MCU/commune/ClkDivPower2.vhd ../../../hdl/MCU/periph/GPIO.vhd ../../../hdl/MCU/periph/SPI.vhd ../../../hdl/MCU/periph/UART.vhd ../../../hdl/MCU/periph/I2C.vhd ../../../hdl/MCU/periph/TIMER.vhd ../../../hdl/MCU/periph/SYSTEM.vhd ../../../hdl/MCU/periph/NPU.vhd ../../../hdl/MCU/periph/SARADC.vhd ../../../hdl/MCU/periph/AFE_FSM.vhd ../../../hdl/MCU/periph/AFE.vhd ../../../hdl/MCU/vesta/div.vhd ../../../hdl/MCU/vesta/alu.vhd ../../../hdl/MCU/vesta/extend.vhd ../../../hdl/MCU/vesta/regfile_sbirq.vhd ../../../hdl/MCU/vesta/irq_handler.vhd ../../../hdl/MCU/vesta/loadext.vhd ../../../hdl/MCU/vesta/store_ext.vhd ../../../hdl/MCU/vesta/branch_valid.vhd ../../../hdl/MCU/vesta/datapath.vhd ../../../hdl/MCU/vesta/maindec.vhd ../../../hdl/MCU/vesta/controller.vhd ../../../hdl/MCU/vesta/c_dec.vhd ../../../hdl/MCU/vesta/vesta.vhd ../../../hdl/MCU/sim/ARM_IP_ROM.vhd ../../../hdl/MCU/sim/ARM_IP_RAM.vhd ../../../hdl/MCU/adddec.vhd ../../../hdl/MCU/MCU.vhd ../../../hdl/MCU/tb/tb_defs.vhd ../../../hdl/MCU/tb/tb_defs.vhd ../../../hdl/MCU/tb/TestbenchLibrary.vhd ../../../hdl/MCU/tb/rv4th_tb.vhd -top rv4th_tb -v200x -work work -access +r -controlrelax nlstex -relax -input ./restore.tcl -input ../../disable_x_warnings.tcl -input restore.tcl
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
probe -create -database waves :dut:spi0:tx_in_progress
probe -create -database waves :dut:spi0:m_tx_sreg
probe -create -database waves :dut:spi1:s_tx_sreg
probe -create -database waves :dut:spi0:rx_order_sel
probe -create -database waves :dut:spi0:SPIxRX_ltch
probe -create -database waves :dut:spi0:clr_start_tx
probe -create -database waves :dut:gpio0:en :dut:gpio0:PxOUT
probe -create -database waves :dut:uart0:en_addr_periph
probe -create -database waves :dut:system0:resetn_por
probe -create -database waves :dut:spi0:clr_spi_teif
probe -create -database waves :dut:spi0:addr_periph
probe -create -database waves :resetn_dir :resetn_in :resetn_out :resetn_ren
probe -create -database waves :dut:uart1:clk_tx
probe -create -database waves :dut:uart0:clk_mem
probe -create -database waves :dut:uart0:baud_cntr
probe -create -database waves :dut:gpio0:read_data_buff :dut:gpio0:read_data
probe -create -database waves :dut:core:datapath_inst:rf:sp_write :dut:core:datapath_inst:rf:sp_in :dut:core:datapath_inst:rf:sp_out
probe -create -database waves :dut:gpio0:alt_func_out_in :dut:gpio0:PxSEL
probe -create -database waves :dut:system0:en_mem :dut:system0:read_data :dut:system0:write_data
probe -create -database waves :dut:uart1:read_data
probe -create -database waves :dut:rom0:Q :dut:rom0:PGEN :dut:rom0:EMA :dut:rom0:CLK :dut:rom0:CEN :dut:rom0:AdrLat :dut:rom0:A
probe -create -database waves :dut:system0:unlock_timer
probe -create -database waves :dut:timer0:clk_hfxt :dut:timer0:clk_lfxt
probe -create -database waves :dut:uart1:start_tx
probe -create -database waves :dut:core:mem_access_instr
probe -create -database waves :dut:uart0:start_tx :dut:uart0:clk_tx :dut:uart0:tx_clk_cntr :dut:uart0:en_clk_baud :dut:uart0:en_clk_tx
probe -create -database waves :TXStr :TX0 :TXing
probe -create -database waves :dut:uart0:clr_start_tx
probe -create -database waves :dut:spi0:m_rx_data_align
probe -create -database waves :dut:gpio2:PxSEL :dut:gpio2:PxREN :dut:gpio2:PxOUT :dut:gpio2:PxIN :dut:gpio2:PxDIR
probe -create -database waves :dut:system0:resetn_sys
probe -create -database waves :dut:spi0:spi_rx_sb :dut:spi0:spi_msb
probe -create -database waves :dut:gpio0:en_addr_periph
probe -create -database waves :dut:system0:mclk_undiv :dut:system0:mclk_divider :dut:system0:mclk_div
probe -create -database waves :prt3 :prt3_dir :prt3_in :prt3_out :prt3_ren
probe -create -database waves :dut:core:write_data
probe -create -database waves :dut:gpio0:wen
probe -create -database waves :dut:spi1:resetn
probe -create -database waves :dut:spi0:miso_out :dut:spi0:clk
probe -create -database waves :dut:system0:en_addr_periph
probe -create -database waves :dut:uart0:USR_UTCIF
probe -create -database waves :dut:core:next_state
probe -create -database waves :dut:spi1:s_SPIxRX
probe -create -database waves :dut:gpio0:clk_mem
probe -create -database waves :dut:spi0:spi_teie
probe -create -database waves :dut:mem_addr
probe -create -database waves :dut:core:datapath_inst:rf:registers
probe -create -database waves :dut:gpio0:write_data
probe -create -database waves :dut:spi0:clk_baud_src
probe -create -database waves :dut:timer0:smclk :dut:timer0:mclk
probe -create -database waves :dut:core:isr_ret
probe -create -database waves :dut:gpio0:prt_dir_out
probe -create -database waves :dut:spi0:clr_spi_tcif
probe -create -database waves :dut:spi0:en_mem :dut:spi0:clk_mem
probe -create -database waves :dut:system0:SYS_BLOCK_PWR
probe -create -database waves :dut:system0:sel_hfxt_as_mclk :dut:system0:en_clk_hfxt
probe -create -database waves :dut:spi1:spi_en :dut:spi1:spi_mode
probe -create -database waves :dut:system0:SYS_CLK_CR :dut:system0:SYS_CLK_DIV_CR :dut:system0:SYS_CRC_DATA :dut:system0:SYS_CRC_STATE :dut:system0:SYS_IRQ_EN :dut:system0:SYS_IRQ_PRI :dut:system0:SYS_WDT_CR :dut:system0:SYS_WDT_SR :dut:system0:clk_mem :dut:system0:clk_hfxt :dut:system0:clk_lfxt :dut:system0:addr_periph
probe -create -database waves :prt1_out
probe -create -database waves :dut:spi0:s_rx_sreg :dut:spi0:s_rx_data_align
probe -create -database waves :dut:spi1:addr_periph
probe -create -database waves :dut:spi0:spi_mode
probe -create -database waves :dut:timer0:cap1_in
probe -create -database waves :dut:spi0:sck_slave
probe -create -database waves :dut:uart0:TX_OUT :dut:uart0:RX_OUT :dut:uart0:RX_IN :dut:uart1:RX_IN :dut:uart1:RX_OUT :dut:uart1:TX_OUT
probe -create -database waves :dut:core:current_state
probe -create -database waves :dut:spi1:SPIxRX_ltch :dut:spi1:en_mem :dut:spi1:clk_mem
probe -create -database waves :dut:gpio0:prt_out_out
probe -create -database waves :prt1
probe -create -database waves :resetn_pad
probe -create -database waves :dut:core:pc_next_trad :dut:core:pc_target :dut:core:pc_src
probe -create -database waves :dut:uart0:clr_UTCIF
probe -create -database waves :dut:spi0:clk_baud
probe -create -database waves :dut:spi0:en_clk_baud :dut:spi0:baud_counter :dut:spi0:en_clk_baud_src
probe -create -database waves :dut:resetn
probe -create -database waves :dut:system0:resetn_wdt
probe -create -database waves :dut:prt1_dir :dut:prt1_ren
probe -create -database waves :dut:gpio0:PxDIR
probe -create -database waves :dut:uart1:rx_bit_cntr :dut:uart1:rx_clk_cntr :dut:uart1:clk_baud :dut:uart1:rx_sr :dut:uart1:rx_parity :dut:uart1:clr_rx_in_progress :dut:uart1:UCR_PEN :dut:uart0:tx_bit_cntr :dut:uart0:tx_sr
probe -create -database waves :dut:system0:wdt_cdiv
probe -create -database waves :dut:timer0:read_data :dut:timer0:write_data :dut:timer0:addr_periph
probe -create -database waves :dut:system0:mclk_div_mux:Sel :dut:system0:mclk_div_mux:EnQQQN :dut:system0:mclk_div_mux:EnQQQ :dut:system0:mclk_div_mux:EnQQ :dut:system0:mclk_div_mux:EnQ :dut:system0:mclk_div_mux:En :dut:system0:mclk_div_mux:ClkSel :dut:system0:mclk_div_mux:ClkOut :dut:system0:mclk_div_mux:ClkIn :dut:system0:mclk_div_mux:ClkGated :dut:system0:mclk_div_mux:ClkEn :dut:system0:mclk_div_mux:CLK_DEFAULT :dut:system0:mclk_div_mux:CLK_COUNT
probe -create -database waves :dut:system0:clk_hfxt_off
probe -create -database waves :dut:timer0:clk_mux:ClkIn :dut:timer0:clk_mux:resetn :dut:timer0:clk_mux:resetp :dut:timer0:clk_mux:En :dut:timer0:clk_mux:EnQ :dut:timer0:clk_mux:EnQQ :dut:timer0:clk_mux:EnQQQ :dut:timer0:clk_mux:EnQQQN :dut:timer0:clk_mux:Sel :dut:timer0:clk_mux:ClkOut :dut:timer0:clk_mux:ClkGated
probe -create -database waves :dut:system0:smclk_div
probe -create -database waves :dut:system0:wdt_interrupt_ret
probe -create -database waves :prt1_in
probe -create -database waves :dut:npu0:NpuSramD
probe -create -database waves :dut:spi0:start_tx
probe -create -database waves :dut:npu0:Decision :dut:npu0:AccOutLtchd
probe -create -database waves :dut:RAM_Dout
probe -create -database waves :dut:gpio0:PxREN
probe -create -database waves :dut:uart1:clr_SR_RX
probe -create -database waves :dut:uart0:en_baud_clk_src
probe -create -database waves :dut:spi0:m_spi_tcif
probe -create -database waves :dut:npu0:MacOut
probe -create -database waves :dut:clk_hfxt :dut:clk_lfxt
probe -create -database waves :dut:spi0:en_addr_periph
probe -create -database waves :dut:core:read_data
probe -create -database waves :dut:core:data_addr
probe -create -database waves :dut:timer1:read_data :dut:timer1:write_data
probe -create -database waves :dut:prt1_in :dut:prt1_out
probe -create -database waves :dut:spi0:m_rx_sreg :dut:spi0:miso_in
probe -create -database waves :dut:mclk :dut:smclk
probe -create -database waves :dut:smclk :dut:core:en_clk_cpu :dut:core:current_state :dut:mclk :dut:core:pc :dut:core:pc_en :dut:core:pc_next :dut:core:instr :dut:core:instr_curr :dut:core:instr_assembled :dut:core:instr_decomp :dut:core:sleep :dut:core:irq_active :dut:core:irq_en :dut:core:irq_save :dut:core:irq_save_ack :dut:core:irq_save_int :dut:core:irq_restore :dut:core:datapath_inst:rf:registers :dut:core:datapath_inst:rf:reg_context :dut:core:datapath_inst:rf:clk_irq :dut:spi0:wen :dut:core:irq_handler_inst:pending_irqs_comb :dut:core:irq_handler_inst:next_state :dut:core:irq_handler_inst:ivt_jump :dut:core:irq_handler_inst:ivt_entry :dut:core:irq_handler_inst:isr_ret :dut:core:irq_handler_inst:irq_save_ack :dut:core:irq_handler_inst:irq_save :dut:core:irq_handler_inst:irq_restore :dut:core:irq_handler_inst:irq_found_reg :dut:core:irq_handler_inst:irq_found :dut:core:irq_handler_inst:irq_en :dut:core:irq_handler_inst:irq_active :dut:core:irq_handler_inst:irq :dut:core:irq_handler_inst:highest_priority_irq_reg :dut:core:irq_handler_inst:highest_priority_irq_comb :dut:core:irq_handler_inst:context_saved :dut:core:irq_handler_inst:current_state :dut:core:irq_handler_inst:clk :prt1_dir :prt1_in :prt2_dir :prt2_out :prt2_in :prt3_dir :prt3_in :prt3_out :prt3_ren :prt1 :prt2 :prt3 :dut:spi0:resetn :dut:spi0:clk :dut:spi0:write_data :dut:spi0:read_data :dut:spi0:sck_slave :dut:spi0:SPIxTX :dut:spi0:SPIxCR :dut:spi0:SPIxRX :dut:spi0:m_SPIxRX :dut:spi0:m_rx_data_align :dut:spi0:m_rx_sreg :dut:spi0:rx_order_sel :dut:spi0:spi_rx_sb :dut:spi0:spi_msb :dut:spi0:spi_dl :dut:spi0:SPIxSR :dut:spi0:m_spi_tcif :dut:spi0:clr_spi_tcif :dut:spi0:start_tx :dut:spi0:clk_baud :dut:spi0:baud_counter :dut:spi0:clk_baud_src :dut:spi0:tx_in_progress :dut:spi0:en_addr_periph :dut:spi0:miso_out :dut:spi0:miso_in :dut:spi0:en_mem :dut:spi0:clk_mem :dut:spi0:sck_out :dut:spi0:spi_teie :dut:spi0:s_rx_sreg :dut:spi0:s_rx_data_align :dut:spi1:sck_slave :dut:spi1:spi_mode :dut:spi1:spi_en :dut:spi1:spi_dl :dut:spi1:SPIxTX :dut:spi1:SPIxSR :dut:spi1:SPIxRX :dut:spi1:SPIxRX_ltch :dut:spi1:addr_periph :dut:spi1:SPIxCR :dut:spi1:en_mem :dut:spi1:clk_mem :dut:spi1:read_data :dut:spi1:write_data :dut:gpio0:PxSEL :dut:gpio0:PxREN :dut:gpio0:PxOUT :dut:gpio0:PxIN :dut:gpio0:PxDIR :dut:gpio0:prt_dir_out :dut:gpio0:clk_mem :dut:gpio0:en :dut:gpio0:en_addr_periph :dut:gpio0:wen :dut:gpio1:PxSEL :dut:gpio1:PxREN :dut:gpio1:PxOUT :dut:gpio1:PxIN :dut:gpio1:PxDIR :dut:gpio2:PxSEL :dut:gpio2:PxREN :dut:gpio2:PxOUT :dut:gpio2:PxIN :dut:gpio2:PxDIR :dut:uart0:RX_OUT :dut:uart0:TX_OUT :dut:uart0:en_mem :dut:uart0:clk_mem :dut:uart0:en_addr_periph :dut:uart0:clr_UTCIF :dut:uart0:USR_UTCIF :dut:uart0:tx_bit_cntr :dut:uart0:read_data :dut:uart0:start_tx :dut:uart0:clr_start_tx :dut:uart0:clk_tx :dut:uart0:clk_baud :dut:uart0:tx_clk_cntr :dut:uart0:en_clk_baud :dut:uart0:baud_cntr :dut:uart0:en_baud_clk_src :dut:uart0:en_clk_tx :dut:uart0:tx_sr :dut:uart0:tx_in_progress :dut:uart0:write_data :dut:uart0:wen :dut:uart0:UART_TX :dut:uart0:UART_SR_ltch :dut:uart0:UART_SR :dut:uart0:UART_RX_ltch :dut:uart0:UART_RX :dut:uart0:UART_CR :dut:uart0:UART_BR :dut:uart0:RX_IN :dut:uart1:addr_periph :dut:uart1:clk_mem :dut:uart1:rx_in_progress :dut:uart1:UART_BR :dut:uart1:UART_CR :dut:uart1:UART_RX :dut:uart1:UART_SR :dut:uart1:UART_TX :dut:uart1:clr_SR_RX :dut:uart1:wen :dut:uart1:write_data :dut:uart1:read_data :dut:uart1:rx_bit_cntr :dut:uart1:rx_clk_cntr :dut:uart1:clk_baud :dut:uart1:rx_sr :dut:uart1:rx_parity :dut:uart1:clr_rx_in_progress :dut:uart1:UCR_PEN :dut:uart1:start_tx :dut:uart1:tx_in_progress :dut:uart1:tx_bit_cntr :dut:uart1:tx_clk_cntr :dut:uart1:clk_tx :dut:uart1:RX_IN :dut:uart1:RX_OUT :dut:uart1:TX_OUT :dut:timer0:clk_hfxt :dut:timer0:mclk :dut:timer0:clk_lfxt :dut:timer0:smclk :dut:timer0:cap1_in :dut:timer0:read_data :dut:timer0:write_data :dut:timer0:addr_periph :dut:timer1:read_data :dut:timer1:write_data :dut:system0:mclk_div_mux:Sel :dut:system0:mclk_div_mux:EnQQQN :dut:system0:mclk_div_mux:EnQQQ :dut:system0:mclk_div_mux:EnQQ :dut:system0:mclk_div_mux:EnQ :dut:system0:mclk_div_mux:En :dut:system0:mclk_div_mux:ClkSel :dut:system0:mclk_div_mux:ClkOut :dut:system0:mclk_div_mux:ClkIn :dut:system0:mclk_div_mux:ClkGated :dut:system0:mclk_div_mux:ClkEn :dut:system0:mclk_div_mux:CLK_DEFAULT :dut:system0:mclk_div_mux:CLK_COUNT :dut:clk_hfxt :dut:clk_lfxt :dut:system0:smclk_div :dut:system0:clk_lfxt :dut:system0:clk_hfxt :dut:system0:smclk :dut:system0:unlocked :dut:system0:mclk :dut:system0:wen :dut:system0:en_addr_periph :dut:system0:read_data :dut:system0:write_data :dut:system0:SYS_CLK_CR :dut:system0:SYS_CLK_DIV_CR :dut:system0:SYS_CRC_DATA :dut:system0:SYS_BLOCK_PWR :dut:system0:irq :dut:system0:irq_en :dut:system0:SYS_CRC_STATE :dut:system0:SYS_IRQ_EN :dut:system0:SYS_IRQ_PRI :dut:system0:SYS_WDT_CR :dut:system0:SYS_WDT_SR :dut:system0:clk_mem :dut:system0:en_mem :dut:system0:addr_periph :dut:ram0:WEN :dut:ram0:RETN :dut:ram0:Q :dut:ram0:PGEN :dut:ram0:GWEN :dut:ram0:EMA :dut:ram0:D :dut:ram0:CLK :dut:ram0:CEN :dut:ram0:A :dut:npu0:NPUBEN :dut:npu0:NPUAEN :dut:npu0:NPUCR :dut:npu0:NPUIVSAR :dut:npu0:NPUNI :dut:npu0:NPUNN :dut:npu0:NPUOVSAR :dut:npu0:NpuActive :dut:npu0:NpuClk :dut:npu0:NPUTHINK :dut:npu0:NpuDone :dut:npu0:NpuClkEn :dut:npu0:NpuSramD :dut:npu0:Decision :dut:npu0:AccOutLtchd :dut:npu0:MacOut :dut:npu0:NpuState :dut:npu0:NpuSramA_out :dut:npu0:NpuSramWEN_out :dut:npu0:NpuSramGWEN_out :dut:npu0:NpuSramCLK_out :dut:npu0:NpuSramCEN_out :dut:npu0:NeuronDone :dut:adddec0:data_addr :dut:mem_addr :dut:rom0:Q :dut:rom0:PGEN :dut:rom0:EMA :dut:rom0:CLK :dut:rom0:CEN :dut:rom0:AdrLat :dut:rom0:A
probe -create -database waves :dut:core:datapath_inst:rf:clk_irq
probe -create -database waves :dut:spi0:spi_dl :dut:spi0:m_counter
probe -create -database waves :dut:spi1:spi_cpol
probe -create -database waves :dut:spi0:sck_out
probe -create -database waves :dut:system0:mclk_sel
probe -create -database waves :dut:gpio0:addr_periph
probe -create -database waves :dut:uart0:USR_UTCIF
probe -create -database waves :dut:system0:resetn_sync
probe -create -database waves :dut:npu0:NpuDone :dut:npu0:NpuClkEn
probe -create -database waves :dut:system0:smclk
probe -create -database waves :dut:system0:clk_unlock
probe -create -database waves :dut:npu0:NPUAEN :dut:npu0:NPUBEN :dut:npu0:NPUCR :dut:npu0:NPUIVSAR :dut:npu0:NPUNI :dut:npu0:NPUNN :dut:npu0:NPUOVSAR :dut:npu0:NpuActive :dut:npu0:NpuClk :dut:npu0:NPUTHINK :dut:npu0:NpuState :dut:npu0:NpuSramA_out :dut:npu0:NpuSramWEN_out :dut:npu0:NpuSramGWEN_out :dut:npu0:NpuSramCLK_out :dut:npu0:NpuSramCEN_out
probe -create -database waves :dut:core:pc :dut:core:pc_en :dut:core:pc_next :dut:core:instr :dut:core:instr_curr :dut:core:instr_assembled :dut:core:instr_decomp
probe -create -database waves :dut:spi0:wen :dut:spi0:read_data :dut:spi0:write_data :dut:spi0:SPIxSR :dut:spi0:SPIxTX :dut:spi0:SPIxRX :dut:spi0:SPIxCR
probe -create -database waves :dut:spi1:rx_order_sel
probe -create -database waves :dut:core:datapath_inst:rf:clk
probe -create -database waves :dut:smclk :dut:core:en_clk_cpu :dut:core:current_state :dut:mclk :dut:core:pc :dut:core:pc_en :dut:core:pc_next :dut:core:instr :dut:core:instr_curr :dut:core:instr_assembled :dut:core:instr_decomp :dut:core:datapath_inst:rf:registers :dut:spi0:wen :dut:uart0:RX_OUT :dut:uart0:TX_OUT :dut:uart0:en_mem :dut:uart0:clk_mem :dut:uart0:en_addr_periph :dut:uart0:clr_UTCIF :dut:uart0:USR_UTCIF :dut:uart0:tx_bit_cntr :dut:uart0:read_data :dut:uart0:start_tx :dut:uart0:clr_start_tx :dut:uart0:clk_tx :dut:uart0:clk_baud :dut:uart0:tx_clk_cntr :dut:uart0:en_clk_baud :dut:uart0:baud_cntr :dut:uart0:en_baud_clk_src :dut:uart0:en_clk_tx :dut:uart0:tx_sr :dut:uart0:tx_in_progress :dut:uart0:write_data :dut:uart0:wen :dut:uart0:UART_TX :dut:uart0:UART_SR_ltch :dut:uart0:UART_SR :dut:uart0:UART_RX_ltch :dut:uart0:UART_RX :dut:uart0:UART_CR :dut:uart0:UART_BR :dut:uart0:RX_IN :dut:adddec0:data_addr :dut:mem_addr :dut:rom0:Q :dut:rom0:PGEN :dut:rom0:EMA :dut:rom0:CLK :dut:rom0:CEN :dut:rom0:AdrLat :dut:rom0:A :prt1_dir :prt1_in :prt2_dir :prt2_out :prt2_in :prt3_dir :prt3_in :prt3_out :prt3_ren :prt1 :prt2 :prt3 :dut:spi0:resetn :dut:spi0:clk :dut:spi0:write_data :dut:spi0:read_data :dut:spi0:sck_slave :dut:spi0:SPIxTX :dut:spi0:SPIxCR :dut:spi0:SPIxRX :dut:spi0:m_SPIxRX :dut:spi0:m_rx_data_align :dut:spi0:m_rx_sreg :dut:spi0:rx_order_sel :dut:spi0:spi_rx_sb :dut:spi0:spi_msb :dut:spi0:spi_dl :dut:spi0:SPIxSR :dut:spi0:m_spi_tcif :dut:spi0:clr_spi_tcif :dut:spi0:start_tx :dut:spi0:clk_baud :dut:spi0:baud_counter :dut:spi0:clk_baud_src :dut:spi0:tx_in_progress :dut:spi0:en_addr_periph :dut:spi0:miso_out :dut:spi0:miso_in :dut:spi0:en_mem :dut:spi0:clk_mem :dut:spi0:sck_out :dut:spi0:spi_teie :dut:spi0:s_rx_sreg :dut:spi0:s_rx_data_align :dut:spi1:sck_slave :dut:spi1:spi_mode :dut:spi1:spi_en :dut:spi1:spi_dl :dut:spi1:SPIxTX :dut:spi1:SPIxSR :dut:spi1:SPIxRX :dut:spi1:SPIxRX_ltch :dut:spi1:addr_periph :dut:spi1:SPIxCR :dut:spi1:en_mem :dut:spi1:clk_mem :dut:spi1:read_data :dut:spi1:write_data :dut:gpio0:PxSEL :dut:gpio0:PxREN :dut:gpio0:PxOUT :dut:gpio0:PxIN :dut:gpio0:PxDIR :dut:gpio0:prt_dir_out :dut:gpio0:clk_mem :dut:gpio0:en :dut:gpio0:en_addr_periph :dut:gpio0:wen :dut:gpio1:PxSEL :dut:gpio1:PxREN :dut:gpio1:PxOUT :dut:gpio1:PxIN :dut:gpio1:PxDIR :dut:gpio2:PxSEL :dut:gpio2:PxREN :dut:gpio2:PxOUT :dut:gpio2:PxIN :dut:gpio2:PxDIR :dut:uart1:addr_periph :dut:uart1:clk_mem :dut:uart1:rx_in_progress :dut:uart1:UART_BR :dut:uart1:UART_CR :dut:uart1:UART_RX :dut:uart1:UART_SR :dut:uart1:UART_TX :dut:uart1:clr_SR_RX :dut:uart1:wen :dut:uart1:write_data :dut:uart1:read_data :dut:uart1:rx_bit_cntr :dut:uart1:rx_clk_cntr :dut:uart1:clk_baud :dut:uart1:rx_sr :dut:uart1:rx_parity :dut:uart1:clr_rx_in_progress :dut:uart1:UCR_PEN :dut:uart1:start_tx :dut:uart1:tx_in_progress :dut:uart1:tx_bit_cntr :dut:uart1:tx_clk_cntr :dut:uart1:clk_tx :dut:uart1:RX_IN :dut:uart1:RX_OUT :dut:uart1:TX_OUT :dut:timer0:clk_hfxt :dut:timer0:mclk :dut:timer0:clk_lfxt :dut:timer0:smclk :dut:timer0:cap1_in :dut:timer0:read_data :dut:timer0:write_data :dut:timer0:addr_periph :dut:timer1:read_data :dut:timer1:write_data :dut:system0:mclk_div_mux:Sel :dut:system0:mclk_div_mux:EnQQQN :dut:system0:mclk_div_mux:EnQQQ :dut:system0:mclk_div_mux:EnQQ :dut:system0:mclk_div_mux:EnQ :dut:system0:mclk_div_mux:En :dut:system0:mclk_div_mux:ClkSel :dut:system0:mclk_div_mux:ClkOut :dut:system0:mclk_div_mux:ClkIn :dut:system0:mclk_div_mux:ClkGated :dut:system0:mclk_div_mux:ClkEn :dut:system0:mclk_div_mux:CLK_DEFAULT :dut:system0:mclk_div_mux:CLK_COUNT :dut:clk_hfxt :dut:clk_lfxt :dut:system0:smclk_div :dut:system0:clk_lfxt :dut:system0:clk_hfxt :dut:system0:smclk :dut:system0:unlocked :dut:system0:mclk :dut:system0:wen :dut:system0:en_addr_periph :dut:system0:read_data :dut:system0:write_data :dut:system0:SYS_CLK_CR :dut:system0:SYS_CLK_DIV_CR :dut:system0:SYS_CRC_DATA :dut:system0:SYS_BLOCK_PWR :dut:system0:irq :dut:system0:irq_en :dut:system0:SYS_CRC_STATE :dut:system0:SYS_IRQ_EN :dut:system0:SYS_IRQ_PRI :dut:system0:SYS_WDT_CR :dut:system0:SYS_WDT_SR :dut:system0:clk_mem :dut:system0:en_mem :dut:system0:addr_periph :dut:ram0:WEN :dut:ram0:RETN :dut:ram0:Q :dut:ram0:PGEN :dut:ram0:GWEN :dut:ram0:EMA :dut:ram0:D :dut:ram0:CLK :dut:ram0:CEN :dut:ram0:A :dut:npu0:NPUBEN :dut:npu0:NPUAEN :dut:npu0:NPUCR :dut:npu0:NPUIVSAR :dut:npu0:NPUNI :dut:npu0:NPUNN :dut:npu0:NPUOVSAR :dut:npu0:NpuActive :dut:npu0:NpuClk :dut:npu0:NPUTHINK :dut:npu0:NpuDone :dut:npu0:NpuClkEn :dut:npu0:NpuSramD :dut:npu0:Decision :dut:npu0:AccOutLtchd :dut:npu0:MacOut :dut:npu0:NpuState :dut:npu0:NpuSramA_out :dut:npu0:NpuSramWEN_out :dut:npu0:NpuSramGWEN_out :dut:npu0:NpuSramCLK_out :dut:npu0:NpuSramCEN_out :dut:npu0:NeuronDone
probe -create -database waves :dut:mem_en
probe -create -database waves :prt1_dir
probe -create -database waves :dut:core:sleep :dut:core:irq_handler_inst:pending_irqs_comb :dut:core:irq_handler_inst:next_state :dut:core:irq_handler_inst:ivt_jump :dut:core:irq_handler_inst:ivt_entry :dut:core:irq_handler_inst:isr_ret :dut:core:irq_handler_inst:irq_save_ack :dut:core:irq_handler_inst:irq_save :dut:core:irq_handler_inst:irq_restore :dut:core:irq_handler_inst:irq_found_reg :dut:core:irq_handler_inst:irq_found :dut:core:irq_handler_inst:irq_en :dut:core:irq_handler_inst:irq_active :dut:core:irq_handler_inst:irq :dut:core:irq_handler_inst:highest_priority_irq_reg :dut:core:irq_handler_inst:highest_priority_irq_comb :dut:core:irq_handler_inst:context_saved :dut:core:irq_handler_inst:current_state :dut:core:irq_handler_inst:clk
probe -create -database waves :dut:system0:unlock :dut:system0:unlocked :dut:system0:clr_wdt
probe -create -database waves :clk_hfxt
probe -create -database waves :dut:spi0:tx_data_align
probe -create -database waves :dut:core:irq_active :dut:core:irq_en :dut:core:irq_save :dut:core:irq_save_ack :dut:core:irq_save_int :dut:core:irq_restore :dut:core:datapath_inst:rf:reg_context
probe -create -database waves :dut:system0:wdt_hwrst
probe -create -database waves :dut:gpio0:alt_func_dir_in :dut:gpio0:alt_func_ren_in
probe -create -database waves :dut:system0:irq :dut:system0:irq_en
probe -create -database waves :dut:npu0:NeuronDone
probe -create -database waves :dut:system0:resetn_in
probe -create -database waves :prt2 :prt2_dir :prt2_in :prt2_out :prt2_ren :dut:gpio1:write_data :dut:gpio1:wen :dut:gpio1:read_data :dut:gpio1:addr_periph :dut:gpio1:PxDIR :dut:gpio1:PxIN :dut:gpio1:PxOUT :dut:gpio1:PxREN :dut:gpio1:PxSEL :dut:spi1:SPIxTX :dut:spi1:SPIxSR :dut:spi1:SPIxRX :dut:spi1:SPIxCR :dut:spi1:mosi_in :dut:spi1:miso_out :dut:spi1:cs_in :dut:spi1:sck_in
probe -create -database waves :dut:system0:wdt_en :dut:system0:wdt_ie
probe -create -database waves :dut:spi1:s_rx_sreg :dut:spi1:s_rx_data_align :dut:spi1:s_counter :dut:spi1:sck_slave
probe -create -database waves :dut:adddec0:data_addr
probe -create -database waves :dut:afunc2_dir
probe -create -database waves :dut:uart0:clk_baud
probe -create -database waves :dut:spi1:write_data :dut:spi1:read_data
probe -create -database waves :dut:core:en_clk_cpu
probe -create -database waves :dut:core:clk_cpu
probe -create -database waves :dut:spi0:resetn
probe -create -database waves :dut:gpio2:PxIF_ltch :dut:gpio2:PxIF :dut:gpio2:PxIES :dut:gpio2:PxIE :dut:gpio3:PxSEL :dut:gpio3:PxREN :dut:gpio3:PxOUT :dut:gpio3:PxIN :dut:gpio3:PxDIR :dut:gpio3:PxIES :dut:gpio3:PxIE :dut:gpio3:PxIF_ltch :dut:gpio3:PxIF :prt4
probe -create -database waves :dut:uart0:rx_clk_cntr :dut:uart0:rx_bit_cntr :dut:uart0:rx_in_progress :dut:uart1:tx_in_progress :dut:uart1:tx_bit_cntr :dut:uart1:tx_clk_cntr
probe -create -database waves :dut:gpio0:PxIN
probe -create -database waves :dut:spi1:spi_dl
probe -create -database waves :dut:spi0:spi_en
probe -create -database waves :dut:uart0:en_mem :dut:uart0:read_data :dut:uart0:tx_in_progress :dut:uart0:write_data :dut:uart0:wen :dut:uart0:UART_TX :dut:uart0:UART_SR_ltch :dut:uart0:UART_SR :dut:uart0:UART_RX_ltch :dut:uart0:UART_RX :dut:uart0:UART_CR :dut:uart0:UART_BR :dut:uart1:addr_periph :dut:uart1:clk_mem :dut:uart1:rx_in_progress :dut:uart1:UART_BR :dut:uart1:UART_CR :dut:uart1:UART_RX :dut:uart1:UART_SR :dut:uart1:UART_TX :dut:uart1:wen :dut:uart1:write_data
probe -create -database waves :dut:spi0:SPIxSR_ltch
probe -create -database waves :dut:ram0:WEN :dut:ram0:RETN :dut:ram0:Q :dut:ram0:PGEN :dut:ram0:GWEN :dut:ram0:EMA :dut:ram0:D :dut:ram0:CLK :dut:ram0:CEN :dut:ram0:A
probe -create -database waves :dut:core:ALU_result
probe -create -database waves :dut:spi0:m_SPIxRX
probe -create -database waves :dut:core:controller_inst:md:isr_ret
probe -create -database waves :dut:system0:wen
probe -create -database waves :dut:system0:mclk

simvision -input restore.tcl.svcf
