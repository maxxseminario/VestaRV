# VestaRV: the itemised CDC waiver list read by census_cdc_crossings.
# One entry per capturing register group that crosses a clock domain WITHOUT a `sync`
# chain, as {instance-name-glob "justification"}. The glob names registers, never a
# whole block, and the justification names the RTL or the constraint that makes the
# crossing safe. //hdl/common/cdc:cdc_manifest_test grades the shape and refuses a
# blanket pattern or a reason too short to be one. Brackets are ESCAPED: `reg\[*\]`.
# Tcl string match reads a bare [*] as a character class and would match nothing.
#
# NO COMMENTS INSIDE THE `return {...}` LIST. A `#` line there is not a Tcl comment: the
# braced word is a LIST, so every whitespace-separated word of the sentence becomes an
# element and its first word becomes a live waiver glob. W5b wrote
# `# i3c0 (9 endpoints) and spi?/s_spi_teif_reg (2) are DEFECTS` inside the braces and
# thereby waived both endpoints the sentence declared unwaivable. cdc_manifest_test now
# parses the list the way Tcl does and fails on any element that is not a
# {glob "justification"} pair, so the trap is closed by the gate and not by care.
# Commentary belongs here, above the proc.
#
# Grouping, for the reader: the first block is T4's pin-event captures (its bus-strobe
# shadow block is gone, see the Z4 note below); then W5b's rtc0, dtm0, i2c, spi, timer and system0 entries; then
# W5a's nfc0 and dm0 entries. nfc0 is quasi-static register-file config latched at
# rx_soc or tx_start, dm0 is one mechanism, the DMI request multi-cycle path. Evidence,
# failure scenarios and the per-entry hit counts are in the W5a and W5b reports; the
# three former defects (nfc0 resp_bytes, i3c0 ibi_req, spi s_spi_teif) are fixed in RTL
# by W10 and are covered by their sync instances, not by a waiver.
#
# W11a (2026-09-14) added the last two entries the armed census wanted, both beside the twin
# they share a mechanism with: spi?/s_gap_reg beside spi?/s_counter_reg, and nfc0/t_etu_reg\[*\]
# beside nfc0/t_etu_half_reg\[*\]. Both registers are W10 creations or W10 survivors, not new
# crossing classes. With them the census on genus/MCU_PENTA_pt reads 0 NOT waived and
# GENUS_CDC_STRICT defaults to 1.
#
# Z2a (2026-09-15) oversampled the I2C slave, the SPI slave and the I3C target-START sensor, so
# SDA_IN, SCL_IN and sck_slave stopped being clocks. i3c0/ibi_req_reg is DELETED: the register is
# gone (the sensor is ibi_req_s2_reg on clk, with no crossing in its cone), and a waiver glob that
# matches nothing is the hazard this file's header is about. The i2c ClearStartSlaveRX and spi
# s_gap justifications are rewritten because the domains they named no longer exist; the mechanism
# each waives, a quasi-static control word in the D cone, is unchanged. The remaining i2c slave
# entries (SlaveData, SlaveState, SlaveJustAddressed, I2CSA, I2CSXC, I2CSTXE, I2CSOVF, ClearI2CSC)
# and spi s_counter / s_spi_tcif keep their wording: every one of them waives the address compare
# or the spi_dl compare, which crosses into the slave whatever clocks the slave. THESE ENTRIES ARE
# NOT RE-CENSUSED: Genus was not run in this wave, so the endpoint names are read from the RTL and
# the next armed census is what confirms the set.
#
# Z2b (2026-09-15) removed NFC's bus pre-latch, so the four nfc0/*_ltch_reg globs are DELETED for
# the reason above: they match nothing now.
#
# Z4 (2026-09-15) is that next armed census, and it retires the rest of the bus-strobe shadow block.
# Genus MCU_PENTA_pt (out.z4b_20260915, CDC gate ARMED) and MCU_PENTA (out.z4a_20260915) report the
# SAME 32 waivers matching 0 endpoints. FOURTEEN of them are this block -- gpio?/PxIF_ltch,
# i2c?/I2CxSRLat, i2c?/I2CxSRXLat, i3c0/I3CxRX_ltch, i3c0/I3CxSR_ltch, qspi0/QSPIxRX_ltch,
# qspi0/QSPIxSR_ltch, spi?/SPIxRX_ltch, spi?/SPIxSR_ltch, timer?/capture0_latched,
# timer?/capture1_latched, timer?/status_reg_latched, uart?/UART_RX_ltch, uart?/UART_SR_ltch --
# and all fourteen are DELETED here. Nine carry `_ltch` in the name; the Z2b note above called the
# set "eight", which was a miscount of the same block. The registers do not exist: a grep of
# hdl/common/ for each signal name returns nothing outside hdl/myshkin/, which is another chip.
#
# The other EIGHTEEN zero-hit waivers are NOT this agent's to retire and stay: timer?/capture0_reg,
# timer?/capture1_reg and timer?/RC_CG_HIER_INST*/RC_CGIC_INST (X2's parked item, the pin-event
# capture class f1082c42 deleted), and the eleven i2c slave plus four spi slave entries that went
# dead when Z2a oversampled those slaves. Z2a kept them deliberately, pending exactly this census;
# whoever owns that decision now has the measurement.
#
# Z5 (2026-09-15) writes the five globs Z4's armed census was short: the 248 NOT-waived
# endpoints are four register classes and all four are the toggle-qualified multi-cycle
# payload this file already waives for rtc0/snap_sync_reg, rtc0/snap_lfxt_reg and
# dtm0/shadow_reg. timer?/capture0_mem and capture1_mem take a glob each, following the
# capture0_reg / capture1_reg precedent above, so four classes are five lines. Each
# justification names the synchroniser that carries the toggle (u_sync_cap_tgl,
# u_sync_rf_pub), the RTL line where the payload and the toggle are written on one source
# edge, and the line where the destination copies the group. The 18 zero-hit waivers Z4
# listed are STILL zero-hit on Z5's cuts (out.z5b_20260915, out.z5a_20260915) and are
# still left in place: they are X2's and Z2a's to retire, not this agent's.

proc cdc_waiver_list {} {
	return {
		{timer?/capture0_reg_reg\\[*\\] "pin-event capture: the free-running counter sampled on the capture pin edge and read later through capture0_latched (TIMER.vhd:333, F12 block (c))"}
		{timer?/capture1_reg_reg\\[*\\] "pin-event capture: the free-running counter sampled on the capture pin edge and read later through capture1_latched (TIMER.vhd:333, F12 block (c))"}
		{timer?/RC_CG_HIER_INST*/RC_CGIC_INST "the clock gate Genus inserts for the pin-event capture bank; its enable is the bank's own bus-domain enable, and the instance number is renumbered every synthesis, hence the wildcard"}

		{timer?/capture0_mem_reg\\[*\\] "multi-cycle payload, toggle-qualified: capture0_reg and capture0_tgl are written on the SAME timer_clock edge (TIMER.vhd:409-411) and the clk_mem copy is taken only at the edge of the synchronised toggle cap_tgl_q(0) out of u_sync_cap_tgl, WIDTH 2 DEPTH 2 (TIMER.vhd:576-578, 591); the toggle needs two clk_mem edges to resolve, and a second capture needs at least three more timer_clock edges because the capture pin itself goes through a level synchroniser and an edge detector (TIMER.vhd:395), so the word is still the one the toggle announced. The data bits never cross bit by bit: only the toggle does. Same idiom as rtc0/snap_sync_reg and dtm0/shadow_reg above. Census class named by Z4, 32 endpoints per timer, clk_lfxt to mclk"}
		{timer?/capture1_mem_reg\\[*\\] "the capture-1 twin of the entry above: capture1_reg and capture1_tgl written on one timer_clock edge (TIMER.vhd:450-452), copied on the synchronised edge of cap_tgl_q(1) from the same u_sync_cap_tgl (TIMER.vhd:576-578, 594). 32 endpoints per timer, clk_lfxt to mclk"}

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
		{i2c?/ClearStartSlaveRX_reg "smclk flop since the slave was oversampled: it samples StartSlaveRX, another smclk flop, at the DECODED falling SCL, so the only crossing left in its cone is the quasi-static I2CMEN / I2CSEN enable pair on its asynchronous clear (I2C.vhd:398-410)"}
		{i2c?/ClearI2CSC_reg "clock-stretch retire, qualified by the quasi-static I2CSCS control bit and by the same address compare (I2C.vhd:660, 707)"}
		{i2c?/I2CMSTS_reg "master start flag: its branch condition I2CBS is a level polled on every ClkMaster edge and monotone once the bus frees, so a metastable sample only defers the START by one ClkMaster period (I2C.vhd:400-405)"}
		{i2c?/RC_CG_HIER_INST*/RC_CGIC_INST "the clock gates Genus inserts for the slave flag bank; their enable is the same quasi-static address compare and held W1C level that qualifies the D pins, and Genus renumbers the instance every run"}

		{spi?/s_counter_reg\\[*\\] "the terminal count that wraps the slave bit counter is selected by the quasi-static spi_dl field of SPIxCR (SPI.vhd:223, 548-566)"}
		{spi?/s_gap_reg "the inter-transfer gap, one clk flop raised at the decoded sck_slave edge that opens it, whose D cone reaches mclk only through the quasi-static spi_dl field of SPIxCR that selects the terminal count, the same dependence spi?/s_counter_reg is waived for; spi_dl is programmed before CS falls and holds still for the whole selected window, because the slave sample process is held in asynchronous reset whenever spi_en, spi_mode or the synchronised cs_s deselects the slave, so a mid-word spi_dl change can move nothing but SPITEIF, by one sck edge, with no data captured on it. The sck_slave domain this register used to live in is gone: the slave is oversampled on clk and u_sync_s_gap went with the crossing"}
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

		{nfc0/t_uid_reg\\[*\\] "quasi-static NFCxUID latched at rx_soc (NFC.vhd:750), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_atqa_reg\\[*\\] "quasi-static NFCxCFG.ATQA latched at rx_soc (NFC.vhd:751), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_sak_reg\\[*\\] "quasi-static NFCxCFG.SAK latched at rx_soc (NFC.vhd:752), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_fdt_reg\\[*\\] "quasi-static NFCxTIM.FDT latched at rx_soc (NFC.vhd:753), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_etu_half_reg\\[*\\] "quasi-static NFCxTIM.ETU halved and latched at the SOC pause edge (NFC.vhd:582), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721); Genus merged t_etu bits 7 to 1 into this bank"}
		{nfc0/t_etu_reg\\[*\\] "the transaction-locally latched timing word: quasi-static NFCxTIM.ETU zero-extended and latched at the SOC pause edge (NFC.vhd:611,619), programmed while NFCxCR.NFCEN is clear and latched in the rf domain, with nfcen_r2, the 2-FF copy of NFCEN, holding the decoder in asynchronous reset until the enable releases it (NFC.vhd:541,590); bit 0 is the only bit of t_etu that survives as its own flop, because t_etu(7 downto 1) carries the same NFCxTIM bits as t_etu_half(6 downto 0) and Genus merged them into nfc0/t_etu_half_reg, waived above, while t_etu(15 downto 8) is constant zero"}
		{nfc0/t_eoc_thresh_reg\\[*\\] "quasi-static NFCxTIM.ETU summed as 2*ETU+ETU/2 and latched at the SOC pause edge (NFC.vhd:583), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/t_subc_reg\\[*\\] "quasi-static NFCxTIM.SUBCDIV latched at tx_start in TXP_IDLE (NFC.vhd:653), programmed while NFCxCR.NFCEN is clear and latched transaction-locally in the rf domain; nfcen_r2, the 2-FF copy of NFCEN, holds the rf core in asynchronous reset until the enable releases it (NFC.vhd:528,721)"}
		{nfc0/rxbuf_sh_reg\\[*\\]\\[*\\] "multi-cycle payload, toggle-qualified: the de-framer writes rxbuf_mem(0 to 8) in the rf_clk domain and the rf side flips rx_pub_tgl on entry to ACT_DECIDE, where the command, length, parity and CRC verdicts are all final (NFC.vhd:784, 766-774); the toggle crosses on u_sync_rf_pub, WIDTH 2 DEPTH 2, and an ordinary ClkMem flop copies the whole nine-byte group at the edge of pub_tgl_q(0) (NFC.vhd:356-358, 372-376). The window is rewritten once per frame, so at the copy edge it has been stable for far more than the two ClkMem periods the synchroniser costs. Only the toggle crosses; no payload bit does. 72 endpoints, nfc0_rf to mclk, census class named by Z4"}
		{nfc0/rxst_mem_reg\\[*\\] "the receive-status word of the same group and the same toggle: rx_parok, rx_crcok, rx_len and rx_cmd are rf_clk registers, final before rx_pub_ev flips rx_pub_tgl, and copied at the edge of pub_tgl_q(0) in the same ClkMem process (NFC.vhd:375, 784). 16 endpoints, nfc0_rf to mclk"}
		{nfc0/dbg_mem_reg\\[*\\] "the counter group of the same idiom on its own toggle: tx_frame_count and rx_frame_count are rf_clk registers, dbg_tgl flips at each frame count (NFC.vhd:787), crosses on the second bit of u_sync_rf_pub and the ClkMem flop copies both counters at the edge of pub_tgl_q(1) (NFC.vhd:355, 377-379). A frame is thousands of rf_clk periods, so the counters hold still across the copy. 32 endpoints, nfc0_rf to mclk"}
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
		{nfc0/resp_bytes_reg\\[*\\]\\[*\\] "AUTOREAD copy of the payload window, interlocked rather than handshaked: the 16-byte copy is taken on one rf_clk edge (NFC.vhd:948-950) and payload_mem is written on ClkMem (NFC.vhd:397), so the rf side snapshots the payload-write toggle carried in on u_sync_pay_wr_tgl at the copy (NFC.vhd:569) and compares it again before the reply is composed; any write whose ClkMem edge fell in that span, the coincident one included, has reached pay_wr_s2 by then and the reply is DROPPED, which an ISO 14443-3 reader retries, so a torn byte cannot be CRCed onto the air. NFC_tb GROUP 5b drives the race. Was defect W5a-1"}


		{dm0/RC_CG_HIER_INST*/RC_CGIC_INST "the mclk clock gates of the DM register banks; every enable is a dmi_req_addr or dmi_req_op decode ANDed with the mclk-registered dmi_req_valid, so the TCK-domain decode can only reach the gate in a cycle where the payload is already held still (debug_module.vhd:1022), and Genus renumbers the instance every run"}
	}
}
