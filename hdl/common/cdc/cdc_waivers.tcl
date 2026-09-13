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
	}
}
