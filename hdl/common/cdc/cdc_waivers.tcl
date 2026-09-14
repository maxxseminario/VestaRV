# VestaRV: the itemised CDC waiver list read by census_cdc_crossings.
# One entry per capturing register group that crosses a clock domain WITHOUT a `sync`
# chain, as {instance-name-glob "justification"}. The glob names registers, never a
# whole block, and the justification names the RTL or the constraint that makes the
# crossing safe. //hdl/common/cdc:cdc_manifest_test grades the shape and refuses a
# blanket pattern or a reason too short to be one. Brackets are ESCAPED: `reg\[*\]`.
# Tcl string match reads a bare [*] as a character class and would match nothing.

proc cdc_waiver_list {} {
	return {
		{gpio?/PxIF_ltch_reg\\[*\\] "bus-strobe shadow: written on the falling edge of the peripheral enable and read by a LATER access, never inside one (GPIO.vhd:316-318, MCU_PENTA_hier F12 block (a))"}
		{i2c?/I2CxSRLat_reg\\[*\\] "bus-strobe shadow, falling EnMemPeriph (I2C.vhd:846)"}
		{i2c?/I2CxSRXLat_reg\\[*\\] "bus-strobe shadow, falling EnMemPeriph (I2C.vhd:846)"}
		{i3c0/I3CxRX_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{i3c0/I3CxSR_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{nfc0/data_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{nfc0/dbg_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{nfc0/NFCxSR_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{nfc0/rxst_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{qspi0/QSPIxRX_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{qspi0/QSPIxSR_ltch_reg\\[*\\] "bus-strobe shadow on EnMemPeriph, the idiom F12 block (a) declares as its own domain"}
		{spi?/SPIxRX_ltch_reg\\[*\\] "bus-strobe shadow on falling en_mem (SPI.vhd:693, F12 block (a))"}
		{spi?/SPIxSR_ltch_reg\\[*\\] "bus-strobe shadow on falling en_mem (SPI.vhd:693, F12 block (a))"}
		{timer?/capture0_latched_reg\\[*\\] "bus-strobe shadow on falling en_mem (TIMER.vhd:467 reg_sync, F12 block (a))"}
		{timer?/capture1_latched_reg\\[*\\] "bus-strobe shadow on falling en_mem (TIMER.vhd:467 reg_sync, F12 block (a))"}
		{timer?/status_reg_latched_reg\\[*\\] "bus-strobe shadow on falling en_mem (TIMER.vhd:467 reg_sync, F12 block (a))"}
		{uart?/UART_RX_ltch_reg\\[*\\] "bus-strobe shadow on falling en_mem (UART.vhd:537, F12 block (a))"}
		{uart?/UART_SR_ltch_reg\\[*\\] "bus-strobe shadow on falling en_mem (UART.vhd:537, F12 block (a))"}

		{gpio?/PxIF_reg\\[*\\] "pin-event capture: the interrupt flag is set by its own pin through a ClkGate and read back through PxIF_ltch (GPIO.vhd:169-190, F12 block (c))"}
		{gpio?/gen_if_clks\\[*\\].CGClkIFG/CG1 "the RTL clock gate of the pin-event flag bank; its enable is the bus-domain interrupt enable and it gates the pin edge, not a data path (GPIO.vhd:169-190)"}
		{timer?/capture0_reg_reg\\[*\\] "pin-event capture: the free-running counter sampled on the capture pin edge and read later through capture0_latched (TIMER.vhd:333, F12 block (c))"}
		{timer?/capture1_reg_reg\\[*\\] "pin-event capture: the free-running counter sampled on the capture pin edge and read later through capture1_latched (TIMER.vhd:333, F12 block (c))"}
		{timer?/RC_CG_HIER_INST*/RC_CGIC_INST "the clock gate Genus inserts for the pin-event capture bank; its enable is the bank's own bus-domain enable, and the instance number is renumbered every synthesis, hence the wildcard"}

		# --- W5b: rtc, dtm, i2c, i3c, spi, timer, system ---
		{rtc0/snap_sync_reg\\[*\\] "multi-cycle payload: snap_lfxt is written on the same lfxt edge that flips cap_tgl (RTC.vhd:364-365) and is sampled only at the edge of the synchronised toggle u_sync_cap_tgl (RTC.vhd:262-263), which resolves 3 mclk edges later while the word still holds; the argument needs mclk above about 131 kHz, four times lfxt, which is the firmware constraint recorded in W5b_cdc_rest.md"}
		{rtc0/sec_cnt_reg\\[*\\] "atomic set-time load from the staged regs_q(SLOT_SEC), gated by wr_apply, the edge of u_sync_wr_req_tgl (RTC.vhd:332, 347-348); the staged word is held until SR.SYNC clears"}
		{rtc0/snap_lfxt_reg\\[*\\] "the same commit: stage_sub enters the snapshot only under wr_apply, the edge of u_sync_wr_req_tgl (RTC.vhd:349, 364)"}
		{rtc0/alm_live_reg\\[*\\] "quasi-static alarm compare value, loaded from regs_q(SLOT_ALM) only under wr_apply and commit_mask(1) (RTC.vhd:380-381)"}
		{rtc0/per_live_reg\\[*\\] "quasi-static tick reload, loaded from stage_per only under wr_apply and commit_mask(2) (RTC.vhd:401-402)"}
		{rtc0/tick_cnt_reg\\[*\\] "the same commit: the tick down-counter restarts from stage_per only under wr_apply and commit_mask(2) (RTC.vhd:401-403)"}
		{rtc0/RC_CG_HIER_INST*/RC_CGIC_INST "the clock gates Genus inserts for the lfxt commit banks; their enable is wr_apply and commit_mask, the same synchronised-toggle condition that qualifies the D pins, and Genus renumbers the instance every run"}

		{dtm0/shadow_reg\\[*\\] "multi-cycle DMI response: rsp_data_h and rsp_op_h are written on the same mclk edge that flips rsp_tgl (jtag_dtm.vhd:379-381) and are sampled only at the edge of u_sync_rsp_tgl qualified by pending (jtag_dtm.vhd:199-203); the payload cannot change before the TAP arms the next transaction"}

		{i2c?/SlaveData_reg\\[*\\] "slave transmit reload from I2CxSTX at the ACK state (I2C.vhd:723); the refill window is announced by I2CSTXE, set on the same SCL edge as the load (I2C.vhd:724), a full byte time before the next load"}
		{i2c?/SlaveState_reg\\[*\\] "next state comes from the address compare against the quasi-static I2CxAR, I2CxAMR and I2CGCE control words (I2C.vhd:689)"}
		{i2c?/SlaveJustAddressed_reg "set by that same quasi-static address compare on the address-match arm (I2C.vhd:689, 706)"}
		{i2c?/I2CSA_reg "slave status flag set from the quasi-static address compare (I2C.vhd:689-691) and cleared by a W1C level held for the whole select window (periph_regs STROBE_HOLD, I2C.vhd:854, 917)"}
		{i2c?/I2CSXC_reg "slave status flag set at the FSM terminal count and cleared by a W1C level held for the whole select window (periph_regs STROBE_HOLD, I2C.vhd:757, 854, 913)"}
		{i2c?/I2CSTXE_reg "slave status flag set with the transmit reload and cleared by a W1C level held for the whole select window (periph_regs STROBE_HOLD, I2C.vhd:724, 854, 916)"}
		{i2c?/I2CSOVF_reg "slave status flag set on the quasi-static address-compare arm and cleared by a W1C level held for the whole select window (periph_regs STROBE_HOLD, I2C.vhd:697-698, 854, 915)"}
		{i2c?/ClearStartSlaveRX_reg "StartSlaveRX is sampled on the next falling SCL, and the I2C START hold time t_HD;STA of 600 ns in fast mode is the guaranteed setup margin (I2C.vhd:302-324)"}
		{i2c?/ClearI2CSC_reg "clock-stretch retire, qualified by the quasi-static I2CSCS control bit and by the same address compare (I2C.vhd:660, 707)"}
		{i2c?/I2CMSTS_reg "master start flag: its branch condition I2CBS is a level polled on every ClkMaster edge and monotone once the bus frees, so a metastable sample only defers the START by one ClkMaster period (I2C.vhd:400-405)"}
		{i2c?/RC_CG_HIER_INST*/RC_CGIC_INST "the clock gates Genus inserts for the slave flag bank; their enable is the same quasi-static address compare and held W1C level that qualifies the D pins, and Genus renumbers the instance every run"}

		{spi?/s_counter_reg\\[*\\] "the terminal count that wraps the slave bit counter is selected by the quasi-static spi_dl field of SPIxCR (SPI.vhd:223, 548-566)"}
		{spi?/s_spi_tcif_reg "set at that same spi_dl-selected terminal count and cleared by clr_spi_tcif, so the only crossing is the quasi-static data-length field (SPI.vhd:548-566, 583)"}
		{spi?/RC_CG_HIER_INST*/RC_CGIC_INST "the clock gate Genus inserts for the slave counter bank; its enable is the same quasi-static spi_dl compare that qualifies the D pins, and Genus renumbers the instance every run"}

		{timer?/clk_mux/MuxGen\\[*\\].*Slice.SYNCDFF0 "first stage of the clock mux's per-slice two-flop synchroniser: SYNCDFF1 on the same ClkIn resolves it and the break-before-make interlock stops two slices enabling at once (ClockMuxGlitchFree_cmn65gp_ARM.vhd:128-198)"}
		{system0/mclk_mux/MuxGen\\[*\\].*Slice.SYNCDFF0 "first stage of the clock mux's per-slice two-flop synchroniser; a 2-FF sync on the selector would be wrong because the destination is the clock being switched (SYSTEM.vhd:432, ClockMuxGlitchFree_cmn65gp_ARM.vhd:128-198)"}
		{system0/smclk_mux/MuxGen\\[*\\].*Slice.SYNCDFF0 "first stage of the clock mux's per-slice two-flop synchroniser; a 2-FF sync on the selector would be wrong because the destination is the clock being switched (SYSTEM.vhd:432, ClockMuxGlitchFree_cmn65gp_ARM.vhd:128-198)"}
		{system0/mclk_div_mux/MuxGen\\[*\\].*Slice.SYNCDFF0 "first stage of the divider mux's per-slice two-flop synchroniser; the ripple divider it selects is clocked off the same switched clock (SYSTEM.vhd:432, 504-512, ClockMuxGlitchFree_cmn65gp_ARM.vhd:128-198)"}
		{system0/smclk_divider_mux/MuxGen\\[*\\].*Slice.SYNCDFF0 "first stage of the divider mux's per-slice two-flop synchroniser; the ripple divider it selects increments on the falling edge of smclk_undiv for exactly this reason (SYSTEM.vhd:432, 434-442)"}
		{system0/cg_clk_hfxt/CG1 "source-gate enable is the mux's own break-before-make interlock ClkEn = En or EnQQQ (ClockMuxGlitchFree_cmn65gp_ARM.vhd:86, SYSTEM.vhd:362): it keeps the oscillator alive until every slice has released, and the only flops on the gated clock are that mux's synchroniser chain"}
		{system0/cg_clk_lfxt/CG1 "source-gate enable is the mux's own break-before-make interlock ClkEn = En or EnQQQ (ClockMuxGlitchFree_cmn65gp_ARM.vhd:86, SYSTEM.vhd:363): it keeps the oscillator alive until every slice has released, and the only flops on the gated clock are that mux's synchroniser chain"}
		{system0/cg_clk_dco0/CG1 "source-gate enable is the mux's own break-before-make interlock ClkEn = En or EnQQQ (ClockMuxGlitchFree_cmn65gp_ARM.vhd:86, SYSTEM.vhd:364): it keeps the oscillator alive until every slice has released, and the only flops on the gated clock are that mux's synchroniser chain"}
		{system0/cg_clk_dco1/CG1 "source-gate enable is the mux's own break-before-make interlock ClkEn = En or EnQQQ (ClockMuxGlitchFree_cmn65gp_ARM.vhd:86, SYSTEM.vhd:365): it keeps the oscillator alive until every slice has released, and the only flops on the gated clock are that mux's synchroniser chain"}
		# --- end W5b ---

		# --- W5a: nfc, dm ---
		# nfc0 is quasi-static register-file config latched at rx_soc or tx_start; dm0 is one
		# mechanism, the DMI request multi-cycle path. The resp_bytes bank is a DEFECT and is
		# deliberately NOT waived. Evidence and failure scenario in W5a_cdc_nfc_dm.md.
		# A comment inside this braced list is NOT a Tcl comment: every word becomes a list
		# element and therefore a glob, so these lines carry no slash and no glob metacharacter.
		{nfc0/t_uid_reg\\[*\\] "quasi-static NFCxUID latched at rx_soc (NFC.vhd:750), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_atqa_reg\\[*\\] "quasi-static NFCxCFG.ATQA latched at rx_soc (NFC.vhd:751), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_sak_reg\\[*\\] "quasi-static NFCxCFG.SAK latched at rx_soc (NFC.vhd:752), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_fdt_reg\\[*\\] "quasi-static NFCxTIM.FDT latched at rx_soc (NFC.vhd:753), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_etu_half_reg\\[*\\] "quasi-static NFCxTIM.ETU halved and latched at the SOC pause edge (NFC.vhd:582), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721); Genus merged t_etu bits 7 to 1 into this bank"}
		{nfc0/t_eoc_thresh_reg\\[*\\] "quasi-static NFCxTIM.ETU summed as 2*ETU+ETU/2 and latched at the SOC pause edge (NFC.vhd:583), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_subc_reg\\[*\\] "quasi-static NFCxTIM.SUBCDIV latched at tx_start in TXP_IDLE (NFC.vhd:653), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/state_s2_reg\\[*\\] "four-phase MCP: the rf side holds state_cap until state_ack returns, and the clk side takes the whole word only on the synchronised u_sync_state_req edge (NFC.vhd:479,483,510)"}
		{nfc0/nfcen_r1_reg "first stage of the hand-rolled 2-FF synchroniser on NFCxCR.NFCEN in process rfsync, nothing combinational between the stages (NFC.vhd:528)"}
		{nfc0/listen_r1_reg "first stage of the hand-rolled 2-FF synchroniser on NFCxCR.LISTEN in process rfsync, nothing combinational between the stages (NFC.vhd:529)"}
		{nfc0/field_r1_reg "first stage of the hand-rolled 2-FF synchroniser on field_live, itself the smclk-domain output of u_sync_field_detect (NFC.vhd:530)"}
		{nfc0/halt_r1_reg "first stage of the hand-rolled 2-FF synchroniser on the HALTCLR toggle halt_req_tgl, edge-detected as halt_pulse after the second stage (NFC.vhd:531,534)"}
		{nfc0/RC_CG_HIER_INST*/RC_CGIC_INST "the rf_clk clock gates of the rx_raw and tx_bits banks; their enable cones hold only rf_clk flops and the chip reset port, so the reported mclk launch is an attribution artefact, and Genus renumbers the instance every run"}

		{dm0/rsp_data_r_reg\\[*\\] "the DMI read-data word, muxed by dmi_req_addr at the accept (debug_module.vhd:1026); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/m_go_d_reg\\[*\\] "the FLAGS or DATA0 word the DM writes for the hart, taken from dmi_req_data at the accept (debug_module.vhd:1027); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/cmd_r_reg\\[*\\] "the accepted abstract command word, written from dmi_req_data (debug_module.vhd:1218); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/grp_r_reg\\[*\\]\\[*\\] "the halt-group number, written from dmi_req_data bits 4 to 2 (debug_module.vhd:1189); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/hartsel_r_reg\\[*\\] "dmcontrol hartsello, written from dmi_req_data bits 25 to 16 (debug_module.vhd:1071); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/rsthalt_r_reg\\[*\\] "dmcontrol setresethaltreq and clrresethaltreq (debug_module.vhd:1092); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/resume_pend_reg\\[*\\] "the per-hart resume request raised by a dmcontrol write (debug_module.vhd:1042); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/resumeack_r_reg\\[*\\] "the per-hart resume acknowledge cleared by a dmcontrol write (debug_module.vhd:1042); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/havereset_r_reg\\[*\\] "the per-hart havereset bit acknowledged by a dmcontrol write (debug_module.vhd:1042); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/grp_pend_reg\\[*\\] "the halt-group broadcast pending bit raised by a dmcontrol or dmcs2 write (debug_module.vhd:1189); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/s_state_reg\\[*\\] "the DM sequencer state, advanced by the accepted request (debug_module.vhd:1022); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/m_go_a_reg\\[*\\] "the shared-window address the DM master drives, decoded from dmi_req_addr (debug_module.vhd:1026); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/m_go_we_reg\\[*\\] "the DM master byte-lane strobe, decoded from dmi_req_op at the accept (debug_module.vhd:1028); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/rsp_hold_reg\\[*\\] "the re-capture lockout timer armed at the accept (debug_module.vhd:1022); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/cmderr_r_reg\\[*\\] "abstractcs cmderr, set or cleared by the accepted request (debug_module.vhd:1022); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/auto_pb_r_reg\\[*\\] "abstractauto autoexecprogbuf, written from dmi_req_data bits 17 to 16 (debug_module.vhd:1176); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/auto_data_r_reg "abstractauto autoexecdata, written from dmi_req_data bit 0 (debug_module.vhd:1175); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/auto_pend_reg "the abstractauto re-trigger raised by an addressed data or progbuf access (debug_module.vhd:1244); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/dmactive_reg "dmcontrol dmactive, written from dmi_req_data bit 0 (debug_module.vhd:1045); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/haltreq_r_reg "dmcontrol haltreq, written from dmi_req_data bit 31 (debug_module.vhd:1070); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/busy_r_reg "abstractcs busy, raised by the accepted command write (debug_module.vhd:1022); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/pend_wr_reg "the accepted access direction, taken from dmi_req_op (debug_module.vhd:1028); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/rsp_arm_reg "the one-cycle response arm set at the accept (debug_module.vhd:1022); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/m_start_reg "the DM master launch pulse raised by the accepted request (debug_module.vhd:1022); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/tramp_arm_reg "the trampoline plant arm taken on the dmactive rise of an accepted dmcontrol write (debug_module.vhd:1067); req_hold is written in the TCK domain only at an arming Update-DR and held until the response toggle returns, and the DM captures only while dmi_req_valid, raised on the synchronised u_sync_req_tgl edge, is high (jtag_dtm.vhd:291,326,366,391; debug_module.vhd:1022)"}
		{dm0/RC_CG_HIER_INST*/RC_CGIC_INST "the mclk clock gates of the DM register banks; every enable is a dmi_req_addr or dmi_req_op decode ANDed with the mclk-registered dmi_req_valid, so the TCK-domain decode can only reach the gate in a cycle where the payload is already held still (debug_module.vhd:1022), and Genus renumbers the instance every run"}
		# --- end W5a ---
	}
}
