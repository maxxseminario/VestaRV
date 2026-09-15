-- VestaRV: I2C controller
-- Combined master/slave: memory-mapped registers, open-drain pads and one interrupt line per event.
-- Bus specification: https://www.nxp.com/docs/en/user-guide/UM10204.pdf
-- The slave is OVERSAMPLED: SDA and SCL reach the logic through work.sync on smclk and a spike filter, START/STOP and the two SCL edges are decoded from the filtered values, and every slave flop is on smclk. No flop in this file has SDA_IN or SCL_IN on its clock pin, which is what makes the block implementable on an FPGA without two pin clocks and what buys the fast-mode spike suppression the pin-clocked sampler could not give. PCLK_HZ / SCL_MAX_HZ state the ratio the sampler needs and are asserted at elaboration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;
-- Word offsets, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/i2c.rdl, which replaces the work.MemoryMap clause (both would make every slot name an ambiguous homograph).
use work.i2c_regs_pkg.all;


entity I2C is
	generic (
		default_SAD	: std_logic_vector(6 downto 0) := (others => '0');	-- The default slave address for this I2C peripheral
		-- The peripheral clock (the smclk port) and the fastest SCL this instance must serve, both in Hz. They infer no logic: they state the ratio the oversampled slave needs and are checked at elaboration. Software owns the other half of the rule, because smclk is divisible at run time -- see the SYS_CLK_CR=0 rule in MCU.vhd.
		PCLK_HZ		: natural := 24000000;
		SCL_MAX_HZ	: natural := 400000
	);
	port
	(
		-- System Signals
		smclk			: in	std_logic;	-- Sub-main clock
		resetn			: in	std_logic;	-- System reset
		irq_str 		: out std_logic;
		irq_spr 		: out std_logic;
		irq_msts 		: out std_logic;
		irq_msps 		: out std_logic;
		irq_marb 		: out std_logic;
		irq_mtxe 		: out std_logic;
		irq_mnr 		: out std_logic;
		irq_mxc 		: out std_logic;
		irq_sa 			: out std_logic;
		irq_stxe 		: out std_logic;
		irq_sovf 		: out std_logic;
		irq_snr 		: out std_logic;
		irq_sxc 		: out std_logic;

		-- Memory Bus
		ClkMem			: in	std_logic;
		EnMemPeriph		: in	std_logic;
		WEn				: in	std_logic_vector(3 downto 0);
		MABPart			: in	std_logic_vector(7 downto 2);
		wdata			: in	std_logic_vector(31 downto 0);
		rdata_out		: out	std_logic_vector(31 downto 0);

		-- Pin Inputs/Outputs
		SDA_IN			: in	std_logic;
		SDA_OUT			: out	std_logic;
		SDA_DIR			: out	std_logic;
		SDA_REN_in		: in	std_logic;
		SDA_REN			: out	std_logic;

		SCL_IN			: in	std_logic;
		SCL_OUT			: out	std_logic;
		SCL_DIR			: out	std_logic;
		SCL_REN_in		: in	std_logic;
		SCL_REN			: out	sl
	);
end I2C;

architecture behavioral of I2C is


	-- Register and Bit Field Signal Declarations ----------
	-- Registers
	signal I2CxCR		: std_logic_vector(21 downto 0);	-- I2C control register
	signal I2CxSR		: std_logic_vector(15 downto 0);	-- I2C status register
	signal I2CxSR_mem	: std_logic_vector(15 downto 0);	-- I2CxSR carried into ClkMem, sixteen independent flag chains
	signal I2CxSR_rd	: std_logic_vector(15 downto 0);	-- ... with the clear shadow applied
	signal sr_clr_now	: std_logic_vector(15 downto 0);	-- I2CxSR bits this access writes a 1 to
	signal sr_clr_pipe0	: std_logic_vector(15 downto 0);	-- ... held over the two ClkMem edges the asynchronous clear needs
	signal sr_clr_pipe1	: std_logic_vector(15 downto 0);
	signal I2CxMTX		: std_logic_vector(7 downto 0);	-- I2C master mode transmit register
	signal I2CxMRX		: std_logic_vector(7 downto 0);	-- I2C master mode receive register
	signal I2CxSTX		: std_logic_vector(7 downto 0);	-- I2C slave mode transmit register
	signal I2CxSRX		: std_logic_vector(7 downto 0);	-- I2C slave mode receive register
	signal I2CxSRX_mem	: std_logic_vector(7 downto 0);	-- ClkMem copy of I2CxSRX, loaded at the synchronized slave receive event
	signal I2CxMRX_mem	: std_logic_vector(7 downto 0);	-- ClkMem copy of I2CxMRX, loaded at the synchronized master receive event
	-- The receive events as toggles, and their crossing into ClkMem. A toggle
	-- rather than the completion flag: I2CSXC and I2CMXC are sticky, so a second
	-- byte before software clears one raises no new edge and the copy would freeze
	-- on the first, where the pre-latch returned the newest.
	signal srx_tgl		: std_logic;	-- smclk domain (was the SCL_IN falling-edge domain): slave receive-byte event
	signal mrx_tgl		: std_logic;	-- ClkMaster domain: master receive-byte event
	signal rx_tgl_d, rx_tgl_q : std_logic_vector(1 downto 0);	-- bit 1 slave, bit 0 master
	signal srx_tgl_prev, mrx_tgl_prev : std_logic;	-- ClkMem edge-detect stage
	signal I2CxAR		: std_logic_vector(6 downto 0);	-- I2C slave address register for this device
	-- I2C slave address mask.
	-- A '1' bit here makes the matching bit of the slave address register accept both '0' and '1' when listening for the slave address.
	signal I2CxAMR		: std_logic_vector(6 downto 0);

	-- I2CxCR
	signal I2CSTRIE		: std_logic;	-- I2C start received interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CSPRIE		: std_logic;	-- I2C stop received interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMSTSIE	: std_logic;	-- I2C master mode start condition sent interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMSPSIE	: std_logic;	-- I2C master mode stop condition sent interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMARBIE	: std_logic;	-- I2C master mode arbitration error interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMTXEIE	: std_logic;	-- I2C master transmit register empty interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMNRIE		: std_logic;	-- I2C master mode NACK received interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMXCIE		: std_logic;	-- I2C master transfer complete interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CSAIE		: std_logic;	-- I2C slave mode addressed interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CSTXEIE	: std_logic;	-- I2C slave transmit register empty interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CSOVFIE	: std_logic;	-- I2C slave receive register overflow interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CSNRIE		: std_logic;	-- I2C slave mode NACK received from master interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CSXCIE		: std_logic;	-- I2C slave mode transfer complete interrupt enable ('0' = disabled, '1' = enabled)
	signal I2CMDIV		: std_logic_vector(3 downto 0);	-- I2C master mode clock divider: the master FSM clock is smclk divided by 4 * 2^I2CMDIV
	signal I2CGCE		: std_logic;	-- I2C slave general call enable: when enabled, this slave is addressed by a global call issued for slave receiver mode ('0' = disabled, '1' = enabled)
	signal I2CSN		: std_logic;	-- I2C slave NACK next byte received: reply with a NACK when this slave receives its address or a data byte from the master ('0' = send an ACK, '1' = send a NACK)
	signal I2CSCS		: std_logic;	-- I2C slave clock stretching enable: when enabled, the slave holds SCL low during the slave ACK states ('0' = SCL forced to '0' while in the slave ACK state, '1' = SCL released to '1' during all slave states)
	-- I2C slave enable ('0' = disabled, '1' = enabled): the device listens for its address.
	-- With master mode also enabled it stays a slave until I2CMST commands a start condition, acts as master for that transfer, then goes back to being a slave.
	signal I2CSEN		: std_logic;
	-- I2C master enable ('0' = disabled, '1' = enabled): the device waits for I2CMST to send a start condition, then acts as master until I2CMSP sends a stop condition.
	signal I2CMEN		: std_logic;

	-- I2CxFCR (everything in this register is write-1 only, and reads as all '0's)
	signal I2CSC		: std_logic;	-- I2C slave continue: with clock stretching enabled, set this bit to make the slave release SCL and continue with the ACK/NACK phase of the transfer.
	signal I2CMRB		: std_logic;	-- I2C master read byte: enter master receiver mode and begin reading a byte from the slave.
	signal I2CMSP		: std_logic;	-- I2C master send stop condition.
	signal I2CMST		: std_logic;	-- I2C master send start condition; this must be the ONLY way a START condition is sent.

	-- I2CxSR
	signal I2CSTR		: std_logic;	-- I2C start received interrupt flag ('0' = none pending, '1' = pending)
	signal I2CSPR		: std_logic;	-- I2C stop received interrupt flag ('0' = none pending, '1' = pending)
	signal I2CMXC		: std_logic;	-- I2C master transfer complete interrupt flag ('0' = none pending, '1' = pending)
	signal I2CMNR		: std_logic;	-- I2C master mode NACK received interrupt flag.
	signal I2CMTXE		: std_logic;	-- I2C master transmit register empty interrupt flag: the transmit register is ready to accept another byte ('0' = none pending, '1' = pending)
	signal I2CMARB		: std_logic;	-- I2C master mode arbitration error interrupt flag ('0' = no arbitration error, '1' = arbitration error)
	signal I2CMSPS		: std_logic;	-- I2C master mode stop condition sent interrupt flag ('0' = none pending, '1' = pending)
	signal I2CMSTS		: std_logic;	-- I2C master mode start condition sent interrupt flag ('0' = none pending, '1' = pending)

	signal I2CSXC		: std_logic;	-- I2C slave mode transfer complete interrupt flag ('0' = none pending, '1' = pending)
	signal I2CSNR		: std_logic;	-- I2C slave mode NACK received from master interrupt flag ('0' = no NACK received, '1' = NACK received, interrupt pending)
	signal I2CSOVF		: std_logic;	-- I2C slave receive register overflow interrupt flag: this slave failed to read one or more bytes from I2CxSRX before they were overwritten ('0' = none pending, '1' = pending)
	signal I2CSTXE		: std_logic;	-- I2C slave transmit register empty interrupt flag: the transmit register is ready to accept another byte ('0' = none pending, '1' = pending)
	signal I2CSA		: std_logic;	-- I2C slave mode addressed interrupt flag: this slave has been addressed ('0' = none pending, '1' = pending)
	signal I2CSTM		: std_logic;	-- I2C slave transmitter mode: the slave has been addressed for slave transmitter mode, valid only if I2CSA = '1' ('0' = slave receiver mode, read bit was '0'; '1' = slave transmitter mode, read bit was '1')
	signal I2CMCB		: std_logic;	-- I2C master controls bus flag ('0' = this master does not currently control the bus, '1' = this master controls the bus)
	signal I2CBS		: std_logic;	-- I2C bus state ('0' = bus idle, '1' = bus active)


	-- Memory Bus Signal Declarations ----------
	-- The bus side is one periph_regs instance driven by i2c_regs_pkg's tables; see hdl/common/regs/REGFILE.md.
	signal regs_q	: reg_arr_t;						-- the stored words
	signal hw_rd_s	: reg_arr_t;						-- the read source for every word this module does not store
	signal w1c_s	: reg_arr_t;						-- a 1 written to an I2CxSR flag
	signal wrh_s	: std_logic_vector(0 to NWORDS-1);	-- combinational: a lane write lands on this word now
	signal sr_sync_d : std_logic_vector(15 downto 0);
	signal acc_s	: std_logic_vector(0 to NWORDS-1);	-- combinational: this slot is addressed now
	signal wr_inh	: std_logic_vector(0 to NWORDS-1);	-- per word: refuse the write
	signal fcr_wr	: std_logic;						-- a lane-0 write to I2CxFCR, this cycle
	signal mtx_wr	: std_logic;						-- a lane-0 write to I2CxMTX, this cycle

	-- Zero-extend a register field to a bus word.
	function pad(v : std_logic_vector) return word is
		variable r : word := (others => '0');
	begin
		r(v'length - 1 downto 0) := v;
		return r;
	end function;

	-- I2CxAR resets to default_SAD, a GENERIC of this entity, so the reset is not
	-- a property of the description and the .rdl cannot carry it. RSTVAL_OR is
	-- the one table the instance supplies rather than the package; every other
	-- word takes the package's RSTVAL unchanged.
	constant RSTVAL_OR_I2C : reg_arr_t := (RegSlotI2CxAR => pad(default_SAD),
	                                       others        => (others => '0'));



	-- I2C Core Signal Declarations ----------
	type MasterState_t is (MasterStateStart1, MasterStateStart2, MasterStateDataTransmitter1, MasterStateDataTransmitter2, MasterStateDataTransmitter3, MasterStateDataTransmitter4, MasterStateAckTransmitter1, MasterStateAckTransmitter2, MasterStateAckTransmitter3, MasterStateAckTransmitter4, MasterStateDataReceiver1, MasterStateDataReceiver2, MasterStateDataReceiver3, MasterStateDataReceiver4, MasterStateAckReceiver1, MasterStateAckReceiver2, MasterStateAckReceiver3, MasterStateAckReceiver4, MasterStateStop1, MasterStateStop2, MasterStateStop3);
	type SlaveState_t is (SlaveStateAddr, SlaveStateAck, SlaveStateReceiver, SlaveStateTransmitter, SlaveStateNotAddressed);
	
	signal StartSlaveRX			: std_logic;	-- A start condition was just received; this signals the slave process to awaken
	signal ClearStartSlaveRX	: std_logic;	-- Clears StartSlaveRX one SCL falling edge after it is set
	
	-- The desired value of SDA and SCL while in Master mode.
	-- Write the value the line should actually take ('0' for pulled low, '1' for released high); the SDA_DIR and SCL_DIR polarity is handled elsewhere, so ignore it here.
	signal MasterSDA			: std_logic;
	signal MasterSCL			: std_logic;
	signal ClkMaster			: std_logic;	-- The clock for the Master mode FSM
	signal EnClkMaster			: std_logic;	-- Enable for the master clock divider (a transfer is pending or in progress)
	signal MasterState			: MasterState_t;	-- The state of the master FSM
	signal MasterBit			: std_logic_vector(2 downto 0);	-- The master mode bit number to transfer next
	signal MasterData			: std_logic_vector(7 downto 0);	-- The data being sent/received in Master mode
	-- Clear requests for the write-1-only flow control bits, raised by the FSM that consumes each command.
	signal ClearI2CMST			: std_logic;
	signal ClearI2CMSP			: std_logic;
	signal ClearI2CMRB			: std_logic;

	-- Clear requests for the status flags, raised by a write-1 to the matching I2CxSR bit.
	signal ClearI2CSPR			: std_logic;
	signal ClearI2CSTR			: std_logic;

	signal ClearI2CMXC			: std_logic;
	signal ClearI2CMNR			: std_logic;
	signal ClearI2CMTXE			: std_logic;
	signal ClearI2CMARB			: std_logic;
	signal ClearI2CMSPS			: std_logic;
	signal ClearI2CMSTS			: std_logic;
	
	signal ClearI2CSXC			: std_logic;
	signal ClearI2CSNR			: std_logic;
	signal ClearI2CSOVF			: std_logic;
	signal ClearI2CSTXE			: std_logic;
	signal ClearI2CSA			: std_logic;

	signal MasterWrite			: std_logic;	-- The master should enter master transmitter mode and begin sending a byte to the slave
	signal ClearMasterWrite		: std_logic;	-- Clear request for MasterWrite, raised once the byte has been taken

	-- The desired value of SDA and SCL while in Slave mode.
	-- Write the value the line should actually take ('0' for pulled low, '1' for released high); the SDA_DIR and SCL_DIR polarity is handled elsewhere, so ignore it here.
	signal SlaveSDA				: std_logic;
	signal SlaveFsmSDA			: std_logic;	-- The value of SDA dictated by the slave FSM, used whenever the slave is not ACKing or NACKing
	signal SlaveSCL				: std_logic;
	signal SlaveState			: SlaveState_t;	-- The state of the slave FSM
	signal SDA_LAT				: std_logic;	-- A sampled value of SDA on the rising edge of SCL, for use in the slave FSM
	signal SlaveBit				: std_logic_vector(2 downto 0);	-- The slave mode bit number to receive next
	signal SlaveData			: std_logic_vector(7 downto 0);	-- The slave data
	signal SlaveJustAddressed	: std_logic;	-- The slave was just addressed and no bytes have been sent or received yet in the current transmission
	signal ClearI2CSC			: std_logic;	-- Clear request for I2CSC, held asserted except while a slave ACK state may consume it

	-- Pin sampling, the smclk side of the slave. See the block above `u_sync_pins`.
	signal pin_sync_d			: std_logic_vector(1 downto 0);	-- (1) SDA_IN, (0) SCL_IN
	signal pin_sync_q			: std_logic_vector(1 downto 0);
	signal sda_s, scl_s			: std_logic;	-- synchronized
	signal sda_h1, sda_h2		: std_logic;	-- the two older samples the filter votes with
	signal scl_h1, scl_h2		: std_logic;
	signal sda_f, scl_f			: std_logic;	-- filtered: three agreeing samples
	signal sda_fd, scl_fd		: std_logic;	-- ... one smclk edge old, for the edge decode
	signal scl_rise, scl_fall	: std_logic;	-- one smclk wide
	signal start_det, stop_det	: std_logic;	-- one smclk wide

	/* Minimum peripheral-clock-to-SCL ratio, and where the number comes from.
	   The sampler passes a pin level only after three agreeing smclk samples
	   behind a two-flop synchroniser, so an SCL phase must last six smclk
	   periods to be decoded: two to clear the synchroniser, three to agree and
	   one to raise the edge pulse. UM10204 gives fast mode a minimum SCL high
	   time of 0.6 us in a 2.5 us bit, 24 % of the period, so six samples in the
	   high phase need 6 / 0.24 = 25 smclk periods per bit; 32 is that rounded
	   up, and standard mode (tHIGH at least 40 % of the period) clears it with
	   room to spare. At 24 MHz the ratio permits SCL up to 750 kHz, against the
	   400 kHz fast-mode maximum this design supports.
	   The data setup time is the other side of the same coin and is not the
	   binding one: SDA and SCL take the same path, so the sampler sees them
	   with the same latency and only the sampling jitter, one smclk period,
	   eats into tSU;DAT. That is 42 ns at 24 MHz against the 100 ns fast mode
	   requires. */
	constant MIN_PCLK_PER_SCL : natural := 32;

begin

	assert PCLK_HZ >= MIN_PCLK_PER_SCL * SCL_MAX_HZ
		report "I2C: peripheral clock " & integer'image(PCLK_HZ)
		       & " Hz is below the " & integer'image(MIN_PCLK_PER_SCL)
		       & "x minimum for SCL_MAX_HZ " & integer'image(SCL_MAX_HZ)
		       & " Hz; the oversampled slave cannot follow that bus."
		severity failure;

	-- Register Signal Routing ----------
	-- The five stored registers are periph_regs' storage; the field slices below
	-- are the package's, so no bit literal in this file describes a register.
	I2CxCR	<= regs_q(RegSlotI2CxCR)(I2CxCR'range);
	I2CxMTX	<= regs_q(RegSlotI2CxMTX)(I2CxMTX'range);
	I2CxSTX	<= regs_q(RegSlotI2CxSTX)(I2CxSTX'range);
	I2CxAR	<= regs_q(RegSlotI2CxAR)(I2CxAR'range);
	I2CxAMR	<= regs_q(RegSlotI2CxAMR)(I2CxAMR'range);

	-- I2CxCR
	I2CSPRIE	<= I2CxCR(I2CSPRIE_LSB);
	I2CSTRIE	<= I2CxCR(I2CSTRIE_LSB);
	I2CMXCIE	<= I2CxCR(I2CMXCIE_LSB);
	I2CMNRIE	<= I2CxCR(I2CMNRIE_LSB);
	I2CMTXEIE	<= I2CxCR(I2CMTXEIE_LSB);
	I2CMARBIE	<= I2CxCR(I2CMARBIE_LSB);
	I2CMSPSIE	<= I2CxCR(I2CMSPSIE_LSB);
	I2CMSTSIE	<= I2CxCR(I2CMSTSIE_LSB);
	I2CSXCIE	<= I2CxCR(I2CSXCIE_LSB);
	I2CSNRIE	<= I2CxCR(I2CSNRIE_LSB);
	I2CSOVFIE	<= I2CxCR(I2CSOVFIE_LSB);
	I2CSTXEIE	<= I2CxCR(I2CSTXEIE_LSB);
	I2CSAIE		<= I2CxCR(I2CSAIE_LSB);
	I2CMDIV		<= I2CxCR(I2CMDIV_MSB downto I2CMDIV_LSB);
	I2CGCE		<= I2CxCR(I2CGCE_LSB);
	I2CSCS		<= I2CxCR(I2CSCS_LSB);
	I2CSN		<= I2CxCR(I2CSN_LSB);
	I2CSEN		<= I2CxCR(I2CSEN_LSB);
	I2CMEN		<= I2CxCR(I2CMEN_LSB);
	

	-- I2CxFCR
	-- See the Register Write section with RegSlotI2CxFCR to see which bits go where

	-- I2CxSR (WARNING: Must update the status register entry in the Register Memory Interface below if you change this!)
	I2CxSR <= (
		0	=> I2CSPR,
		1	=> I2CSTR,
		2	=> I2CMXC,
		3	=> I2CMNR,
		4	=> I2CMTXE,
		5	=> I2CMARB,
		6	=> I2CMSPS,
		7	=> I2CMSTS,
		8	=> I2CSXC,
		9	=> I2CSNR,
		10	=> I2CSOVF,
		11	=> I2CSTXE,
		12	=> I2CSA,
		13	=> I2CSTM,
		14	=> I2CMCB,
		15	=> I2CBS
	);



	/* -------- I2C Core ----------
	   Signal Routing
	   The pads are open-drain: output data is tied low and the direction pin drives, so a released line floats up to the bus pull-up, and I2CMCB picks whether the master or the slave supplies the level. */
	SDA_OUT <= '0';
	SCL_OUT <= '0';
	SDA_REN <= SDA_REN_in;
	SCL_REN <= SCL_REN_in;
	SDA_DIR <= (not MasterSDA) when I2CMCB = '1' else (not SlaveSDA);
	SCL_DIR <= (not MasterSCL) when I2CMCB = '1' else (not SlaveSCL);



	-- Interrupts
	irq_str 	<= (I2CSTR and I2CSTRIE);
	irq_spr 	<= (I2CSPR and I2CSPRIE);
	irq_msts 	<= (I2CMSTS and I2CMSTSIE);
	irq_msps 	<= (I2CMSPS and I2CMSPSIE);
	irq_marb 	<= (I2CMARB and I2CMARBIE);
	irq_mtxe 	<= (I2CMTXE and I2CMTXEIE);
	irq_mnr 	<= (I2CMNR and I2CMNRIE);
	irq_mxc 	<= (I2CMXC and I2CMXCIE);
	irq_sa 		<= (I2CSA and I2CSAIE);
	irq_stxe 	<= (I2CSTXE and I2CSTXEIE);
	irq_sovf 	<= (I2CSOVF and I2CSOVFIE);
	irq_snr 	<= (I2CSNR and I2CSNRIE);
	irq_sxc 	<= (I2CSXC and I2CSXCIE);



	/* -------- Pin sampling ----------
	   SDA and SCL are asynchronous open-drain lines and were, until 2026-09-15,
	   the clock pins of five flops in this file. They are now sampled on smclk.

	   Two stages: work.sync carries each line into smclk (two INDEPENDENT
	   chains, which is what WIDTH is for; the lines are unrelated bits and
	   never a word), then a three-sample agreement filter passes a level only
	   once the synchronised value has held for three consecutive edges. The
	   filter is the fast-mode spike suppression UM10204 asks for (tSP, 50 ns):
	   a pulse narrower than two smclk periods is seen on at most two samples
	   and never wins the vote, which is 83 ns at 24 MHz. The pin-clocked
	   sampler had no such floor -- any SDA edge was a START to it, and a
	   glitch left the bus latched busy with no SCL edge coming to retire it.

	   START and STOP require SCL filtered high on BOTH samples either side of
	   the SDA edge, so a coincident SCL transition cannot be read as either. */
	pin_sync_d <= SDA_IN & SCL_IN;

	u_sync_pins : entity work.sync
		generic map (WIDTH => 2, DEPTH => 2, RST_VAL => "11")
		port map (clk => smclk, areset => resetn, d => pin_sync_d, q => pin_sync_q);

	sda_s <= pin_sync_q(1);
	scl_s <= pin_sync_q(0);

	pin_filter_proc: process(smclk, resetn)
	begin
		if resetn = '0' then
			-- An idle I2C bus is both lines released, so the whole chain resets high and no edge is manufactured at reset release.
			sda_h1 <= '1'; sda_h2 <= '1'; sda_f <= '1'; sda_fd <= '1';
			scl_h1 <= '1'; scl_h2 <= '1'; scl_f <= '1'; scl_fd <= '1';
		elsif rising_edge(smclk) then
			sda_h1 <= sda_s;  sda_h2 <= sda_h1;
			scl_h1 <= scl_s;  scl_h2 <= scl_h1;
			if sda_s = sda_h1 and sda_h1 = sda_h2 then
				sda_f <= sda_s;
			end if;
			if scl_s = scl_h1 and scl_h1 = scl_h2 then
				scl_f <= scl_s;
			end if;
			sda_fd <= sda_f;
			scl_fd <= scl_f;
		end if;
	end process;

	scl_rise  <= scl_f and not scl_fd;
	scl_fall  <= (not scl_f) and scl_fd;
	-- A start condition (or restart condition) is a falling edge of SDA while SCL is stable on '1'; a stop condition is a rising edge of SDA while SCL is stable on '1'.
	start_det <= (not sda_f) and sda_fd and scl_f and scl_fd;
	stop_det  <= sda_f and (not sda_fd) and scl_f and scl_fd;


	/* -------- I2C Bus State Sensor ----------
	   The three sensors below keep the shape they had when SDA_IN and SCL_IN
	   were their clocks: an asynchronous clear or level branch, then one edge
	   branch that sets. Only the edge changed, from the pin to smclk qualified
	   by the decoded pulse. The Clear* levels stay ASYNCHRONOUS on purpose:
	   they are raised in the ClkMem domain and smclk is divisible against it,
	   so a synchronous clear could be missed where a level cannot be. */
	process (resetn, I2CMEN, I2CSEN, ClearStartSlaveRX, smclk)
	begin
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') or ClearStartSlaveRX = '1' then
			StartSlaveRX <= '0';
		elsif rising_edge(smclk) then
			if start_det = '1' then
				StartSlaveRX <= '1';
			end if;
		end if;
	end process;

	process (resetn, I2CMEN, I2CSEN, ClearI2CSTR, smclk)
	begin
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') or ClearI2CSTR = '1' then
			I2CSTR <= '0';
		elsif rising_edge(smclk) then
			if start_det = '1' then
				I2CSTR <= '1';
			end if;
		end if;
	end process;

	-- Retire the start flag one SCL falling edge after the start condition was seen.
	process (resetn, I2CMEN, I2CSEN, smclk)
	begin
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') then
			ClearStartSlaveRX <= '0';
		elsif rising_edge(smclk) then
			if scl_fall = '1' then
				-- Clear the start slave RX line
				-- One known limitation: a start condition immediately followed by a stop condition (no data sent, so no SCL transitions) is not recognized as a stop.
				ClearStartSlaveRX <= StartSlaveRX;
			end if;
		end if;
	end process;

	-- Bus busy tracking and the stop-received flag.
	process (resetn, I2CMEN, I2CSEN, StartSlaveRX, ClearI2CSPR, smclk)
	begin
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') then
			I2CBS <= '0';
		elsif StartSlaveRX = '1' then
			I2CBS <= '1';
		elsif rising_edge(smclk) then
			if stop_det = '1' then
				I2CBS <= '0';
				I2CSPR <= '1';
			end if;
		end if;

		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') or ClearI2CSPR = '1' then
			I2CSPR <= '0';
		end if;
	end process;




	-- Master Mode Clock Divider
	EnClkMaster <= I2CMST or ClearI2CMST or I2CMCB;

	CGMaster: entity work.ClkDivPower2
	generic map
	(
		nbits	=> 4	-- 4 bits gives 16 selections, so a maximum divider of 2^15 (32768)
	)
	port map
	(
		resetn	=> resetn,
		En		=> EnClkMaster,
		ClkIn	=> smclk,
		DivSel	=> I2CMDIV,
		ClkOut	=> ClkMaster
	);

	-- Master Mode FSM
	process (resetn, I2CMEN, ClearI2CMXC, ClearI2CMNR, ClearI2CMTXE, ClearI2CMARB, ClearI2CMSPS, ClearI2CMSTS, ClkMaster)
	begin
		if resetn = '0' or I2CMEN = '0' then
			MasterState <= MasterStateStart1;
			MasterBit <= (others => '1');
			I2CMCB <= '0';
			MasterSDA <= '1';
			MasterSCL <= '1';
			MasterData <= (others => '0');
			ClearI2CMST <= '0';
			ClearI2CMSP <= '0';
			ClearI2CMRB <= '0';
			ClearMasterWrite <= '0';
		elsif rising_edge(ClkMaster) then
			ClearI2CMST <= '0';
			ClearI2CMSP <= '0';
			ClearMasterWrite <= '0';
			ClearI2CMRB <= '0';
			
			case MasterState is
				when MasterStateStart1 =>
					-- This state checks whether the bus is available and, if so, generates the first part of the start condition: the falling edge of SDA.
					-- If the bus is not available it waits here until it is, then generates the start condition.
					ClearI2CMST <= '1';
					MasterBit <= "111";
					
					-- Ensure SCL is not asserted
					MasterSCL <= '1';

					-- Check the bus state unless this master already controls the bus, i.e. unless this is a repeated start.
					if (I2CMCB = '1' or I2CBS = '0') and MasterSCL = '1' then
						-- The bus is (probably) idle.
						-- Claim control of the bus and create a falling edge of SDA to begin the start condition.
						I2CMSTS <= '1';
						I2CMCB <= '1';
						MasterSDA <= '0';
						MasterState <= MasterStateStart2;
					end if;
				when MasterStateStart2 =>
					-- This state finishes sending the start condition with the second part: the falling edge of SCL.
					MasterSCL <= '0';

					-- Wait until the command is given to begin transmitting (the master MUST send the first byte after a start condition)
					if MasterWrite = '1' then
						ClearMasterWrite <= '1';
						MasterData <= I2CxMTX;
						MasterState <= MasterStateDataTransmitter1;
					end if;
				
				-- These next master transmitter states send a byte of data.
				-- They also watch for arbitration errors and for slaves that stretch the clock.
				when MasterStateDataTransmitter1 =>
					-- This state configures SDA with the data to be sent
					-- Send the next data bit on SDA, MSB first
					MasterSDA <= MasterData(7);
					MasterData <= MasterData(6 downto 0) & '1';

					-- If this is the first bit of a master transmitter, indicate that the transmit register is empty
					if ClearMasterWrite = '1' then
						I2CMTXE <= '1';	-- Transmit register empty flag
					end if;

					MasterState <= MasterStateDataTransmitter2;
				when MasterStateDataTransmitter2 =>
					-- This state makes a rising edge on SCL
					MasterSCL <= '1';
					MasterState <= MasterStateDataTransmitter3;
				when MasterStateDataTransmitter3 =>
					-- This state watches for loss of arbitration and clock stretching
					-- Wait until SCL is '1' in case the slave employs clock stretching
					if SCL_IN = '1' then
						-- The slave has released the clock, so check for a loss of arbitration.
						if SDA_IN /= MasterSDA then
							-- Arbitration lost.
							-- Give up control of the bus by releasing SDA (SCL is already '1' at this point).
							I2CMARB <= '1';
							MasterSDA <= '1';
							MasterState <= MasterStateStop1;
						else
							-- This master (maybe) still controls this bus
							MasterState <= MasterStateDataTransmitter4;
						end if;
					end if;
				when MasterStateDataTransmitter4 =>
					-- This state makes a falling edge on SCL and watches for the last bit to be sent
					MasterSCL <= '0';
					MasterBit <= MasterBit - 1;

					-- If this is the last bit in the data...
					if MasterBit = "000" then
						-- The last bit has been sent, time to receive the ACK
						MasterState <= MasterStateAckTransmitter1;
					else
						-- Need to send more bits, cycle back through the states
						MasterState <= MasterStateDataTransmitter1;
					end if;
				when MasterStateAckTransmitter1 =>
					-- This state starts the master transmitter ACK reading sequence by releasing SDA
					MasterSDA <= '1';
					MasterState <= MasterStateAckTransmitter2;
				when MasterStateAckTransmitter2 =>
					-- This state makes a rising edge on SCL
					MasterSCL <= '1';
					MasterState <= MasterStateAckTransmitter3;
				when MasterStateAckTransmitter3 =>
					-- This state samples SDA for an ACK/NACK while watching for clock stretching
					-- Wait until SCL is '1' in case the slave employs clock stretching
					if SCL_IN = '1' then
						-- Sample SDA and generate a NACK flag if a NACK was received
						if SDA_IN = '1' then
							-- A NACK was received
							I2CMNR <= '1';
						end if;

						MasterState <= MasterStateAckTransmitter4;
					end if;
				when MasterStateAckTransmitter4 =>
					-- This state makes a falling edge on SCL, indicates that the master transmitter transfer is complete, and waits for the next command to either send a repeated start, send another byte, receive a byte, or send a stop condition.
					MasterSCL <= '0';

					-- Generate a transfer complete flag ONLY the first time through this state
					if MasterSCL = '1' then
						I2CMXC <= '1';
					end if;

					-- Wait for the next command
					if I2CMSP = '1' then
						MasterState <= MasterStateStop1;
					elsif I2CMST = '1' then
						MasterState <= MasterStateStart1;
					elsif MasterWrite = '1' then
						ClearMasterWrite <= '1';
						MasterData <= I2CxMTX;
						MasterState <= MasterStateDataTransmitter1;
					elsif I2CMRB = '1' then
						MasterState <= MasterStateDataReceiver1;
					end if;
				
				-- These next master receiver states are responsible for receiving a byte of data.
				when MasterStateDataReceiver1 =>
					-- This state releases SDA so the slave can write to it
					MasterSDA <= '1';
					MasterState <= MasterStateDataReceiver2;
					ClearI2CMRB <= '1';
				when MasterStateDataReceiver2 =>
					-- This state makes a rising edge on SCL
					MasterSCL <= '1';
					MasterState <= MasterStateDataReceiver3;
				when MasterStateDataReceiver3 =>
					-- This state samples SDA to get the next data bit, watching for clock stretching
					if SCL_IN = '1' then
						-- Sample SDA and place its value in the LSB of MasterData, left shifting the rest of MasterData.
						MasterData <= MasterData(6 downto 0) & SDA_IN;
						MasterState <= MasterStateDataReceiver4;
					end if;
				when MasterStateDataReceiver4 =>
					-- This state causes the falling edge of SCL.
					-- If this is the last bit it latches the new receive register, sets the transfer complete flag, and waits for a command to read another byte or send a stop condition.
					MasterSCL <= '0';
					MasterBit <= MasterBit - 1;	-- Might get overridden below, this is intentional

					if MasterBit = "000" then
						-- This is the last bit
						-- Set the transfer complete flag and latch in the received data only the first time through this state
						if MasterSCL = '1' then
							I2CMXC <= '1';
							I2CxMRX <= MasterData;
							mrx_tgl <= not mrx_tgl;	-- receive-byte event into ClkMem
						end if;
						
						-- Wait for a command to either read another byte, send a repeated start condition, or send a stop condition
						if I2CMRB = '1' or I2CMST = '1' or I2CMSP = '1' then
							-- Got a command, move on to the next state
							MasterState <= MasterStateAckReceiver1;
						else
							-- Haven't got a command yet, stay in this state
							MasterBit <= "000";
						end if;
					else
						-- Need to receive more bits, cycle back through the states
						MasterState <= MasterStateDataReceiver1;
					end if;
				when MasterStateAckReceiver1 =>
					-- This state sets SDA so that the master can either ACK to tell the slave that it wants to send another byte, or NACK to tell the slave that the transaction is done.
					if I2CMSP = '1' or I2CMST = '1' then
						-- The master wants to end the transaction with a stop condition or begin a brand new one; either way, send a NACK.
						MasterSDA <= '1';
					else
						-- The master wishes to receive another byte, so send an ACK
						MasterSDA <= '0';
					end if;
					MasterState <= MasterStateAckReceiver2;
				when MasterStateAckReceiver2 =>
					-- This state makes a rising edge on SCL
					MasterSCL <= '1';
					MasterState <= MasterStateAckReceiver3;
				when MasterStateAckReceiver3 =>
					-- This state just waits for a cycle to allow the slave to read the ACK/NACK
					-- Sample SDA and generate a NACK flag if a NACK was sent
					if SDA_IN = '1' then
						-- A NACK was sent
						I2CMNR <= '1';
					end if;
					MasterState <= MasterStateAckReceiver4;
				when MasterStateAckReceiver4 =>
					-- This state makes a falling edge on SCL and determines what to do next
					MasterSCL <= '0';

					if I2CMSP = '1' then
						-- The master wishes to end the transaction and send a stop condition
						MasterState <= MasterStateStop1;
					elsif I2CMST = '1' then
						-- The master wishes to end the transaction and begin a new one with a repeated start condition
						if MasterSCL = '0' then
							MasterState <= MasterStateStart1;
							MasterSCL <= '1';
						end if;
					else
						-- The master wishes to receive another byte
						MasterState <= MasterStateDataReceiver1;
					end if;
				
				-- These next states control the stop condition cadence
				when MasterStateStop1 =>
					-- Set SDA to '0' to prepare it for a rising edge (SCL should already be '0' at this point)
					MasterSDA <= '0';
					MasterState <= MasterStateStop2;
				when MasterStateStop2 =>
					-- Set SCL to '1'
					MasterSCL <= '1';
					ClearI2CMST <= '1';
					ClearI2CMSP <= '1';
					ClearI2CMRB <= '1';
					ClearMasterWrite <= '1';
					MasterState <= MasterStateStop3;
				when MasterStateStop3 =>
					-- Send a rising edge of SDA
					MasterSDA <= '1';
					I2CMSPS <= '1';
					I2CMCB <= '0';
					MasterState <= MasterStateStart1;
			end case;
		end if;
	
		-- Status Register synchronizers
		if resetn = '0' or ClearI2CMXC = '1' then
			I2CMXC <= '0';
		end if;

		if resetn = '0' or ClearI2CMNR = '1' then
			I2CMNR <= '0';
		end if;

		if resetn = '0' or ClearI2CMTXE = '1' then
			I2CMTXE <= '0';
		end if;

		if resetn = '0' or ClearI2CMARB = '1' then
			I2CMARB <= '0';
		end if;

		if resetn = '0' or ClearI2CMSPS = '1' then
			I2CMSPS <= '0';
		end if;

		if resetn = '0' or ClearI2CMSTS = '1' then
			I2CMSTS <= '0';
		end if;

		if resetn = '0' then
			I2CxMRX <= (others => '0');
			mrx_tgl <= '0';
		end if;
		
	end process;



	-- Slave Mode FSM
	-- Sample SDA at each decoded SCL rising edge; the FSM below consumes SDA_LAT, not the live pin.
	-- The value taken is the FILTERED SDA, which carries the same latency as the filtered SCL that produced the pulse, so the bit captured is the bit that stood on the wire when SCL rose.
	process (resetn, I2CSEN, I2CBS, I2CMCB, smclk)
	begin
		if resetn = '0' or I2CSEN = '0' or I2CBS = '0' or I2CMCB = '1' then
			SDA_LAT <= '0';
		elsif rising_edge (smclk) then
			if scl_rise = '1' then
				SDA_LAT <= sda_f;
			end if;
		end if;
	end process;

	-- SDA is ordinarily controlled by the slave FSM, except while the slave ACKs or NACKs after receiving its address or a data byte from the master.
	SlaveSDA <= I2CSN when (SlaveJustAddressed = '1' or I2CSTM = '0') and SlaveState = SlaveStateAck else SlaveFsmSDA;
	-- The slave usually does not assert SCL, except when it wants to stretch the clock.
	-- The only clock stretching in this implementation is optional (I2CSCS = '1') and happens during the ACK/NACK phase, to let the slave prepare for the next byte transfer.
	SlaveSCL <= '0' when I2CSCS = '1' and I2CSC = '0' and SlaveState = SlaveStateAck else '1';

	-- Slave transfer sequencer: address match, ACK/NACK, then receiver or transmitter.
	-- Everything below advances on the decoded SCL falling edge, on smclk. The ACK drive and the clock stretch are combinational on SlaveState as before, so both now move about three smclk periods into the SCL low phase instead of at its edge: 125 ns at 24 MHz against a fast-mode minimum low time of 1.3 us.
	process (resetn, I2CSEN, I2CBS, StartSlaveRX, I2CMCB, ClearI2CSXC, ClearI2CSNR, ClearI2CSOVF, ClearI2CSTXE, ClearI2CSA, smclk)
	begin
		if resetn = '0' or I2CSEN = '0' or I2CBS = '0' or StartSlaveRX = '1' or I2CMCB = '1' then
			SlaveState <= SlaveStateAddr;
			SlaveFsmSDA <= '1';
			SlaveBit <= "111";
			SlaveJustAddressed <= '0';
			ClearI2CSC <= '1';
			I2CSTM <= '0';
		elsif rising_edge(smclk) then
		  if scl_fall = '1' then
			SlaveJustAddressed <= '0';
			ClearI2CSC <= '1';
			
			-- Decrement the slave bit by default
			SlaveBit <= SlaveBit - 1;
				
			-- Latch the next bit from SDA by default
			SlaveData <= SlaveData(6 downto 0) & SDA_LAT;
			
			case SlaveState is
				when SlaveStateAddr =>
					-- This state is responsible for receiving the 7-bit address from the master, checking it against this slave's address, and receiving the read/write bit
					-- Is this the last bit?
					if SlaveBit = "000" then
						-- This is the last bit
						-- Check the address
						if and_reduct((SlaveData(6 downto 0) xnor I2CxAR(6 downto 0)) or I2CxAMR(6 downto 0)) = '1' or (I2CGCE = '1' and or_reduct(SlaveData(6 downto 0)) = '0' and SDA_LAT = '0') then
							-- This slave has been addressed, or a general call for slave receiver mode was issued.
							I2CSA <= '1';	-- The slave addressed flag needs a separate signal from SlaveAddressed because it should be able to be cleared in the status register

							-- Latch the receive register
							I2CxSRX <= SlaveData(6 downto 0) & SDA_LAT;
							srx_tgl <= not srx_tgl;	-- receive-byte event into ClkMem

							-- Check for an overflow
							if I2CSXC = '1' then
								I2CSOVF <= '1';
							end if;

							-- Latch the read/write mode on SDA
							I2CSTM <= SDA_LAT;

							-- Prepare for the ACK state
							SlaveFsmSDA <= '1';	-- Release SDA; the actual ACK/NACK is driven by combinational logic outside the FSM
							SlaveJustAddressed <= '1';
							ClearI2CSC <= '0';	-- Allow I2CSC to be set
							SlaveState <= SlaveStateAck;
						else
							-- The address did not match, so ignore the rest of this transaction.
							SlaveState <= SlaveStateNotAddressed;
						end if;
					end if;
				when SlaveStateAck =>
					-- The ACK/NACK has just been sent
					SlaveFsmSDA <= '1';	-- By default, release SDA

					if I2CSTM = '1' then
						-- Indicate if a NACK was received
						I2CSNR <= SDA_LAT;	-- If SDA is '1', then a NACK was received

						-- Begin transmitting the MSB, and set the transmit register empty flag
						SlaveData <= I2CxSTX(6 downto 0) & '0';
						I2CSTXE <= '1';

						-- If an ACK was received from the master, begin sending the next byte of data.
						-- If a NACK was received, release SDA instead.
						if SDA_LAT = '1' then
							-- NACK received, release SDA so the master can send a stop condition
							SlaveFsmSDA <= '1';
						else
							-- ACK received, send next data bit	
							SlaveFsmSDA <= I2CxSTX(7);
						end if;

						-- Go to slave transmitter mode
						SlaveState <= SlaveStateTransmitter;
					else
						-- Go to slave receiver mode
						SlaveState <= SlaveStateReceiver;
					end if;
					SlaveBit <= "111";
				when SlaveStateReceiver =>
					-- This state is responsible for receiving a byte of data from the master
					-- Is this the last bit?
					if SlaveBit = "000" then
						-- This is the last bit
						-- Latch the receive register
						I2CxSRX <= SlaveData(6 downto 0) & SDA_LAT;
						srx_tgl <= not srx_tgl;	-- receive-byte event into ClkMem

						-- Check for an overflow
						if I2CSXC = '1' then
							I2CSOVF <= '1';
						end if;

						-- Indicate that the transfer is complete
						I2CSXC <= '1';

						-- Prepare for the ACK state
						SlaveFsmSDA <= '1';	-- Release SDA; the actual ACK/NACK is driven by combinational logic outside the FSM
						ClearI2CSC <= '0';	-- Allow I2CSC to be set
						SlaveState <= SlaveStateAck;
					end if;
				when SlaveStateTransmitter =>
					-- Sends a byte of data to the master; SlaveData was already latched from I2CxSTX and I2CSTXE was already set.
					-- Send the next bit on SDA by default: never the MSB, which the ACK state sends.
					SlaveFsmSDA <= SlaveData(7);

					-- Is this the last bit?
					if SlaveBit = "000" then
						-- This is the last bit
						-- Release SDA so that the master can ACK/NACK
						SlaveFsmSDA <= '1';

						-- Indicate that the transfer is complete
						I2CSXC <= '1';

						-- Go to the ACK state
						ClearI2CSC <= '0';	-- Allow I2CSC to be set
						SlaveState <= SlaveStateAck;
					end if;
				when SlaveStateNotAddressed =>
					-- Wait here until the end of the transaction
					SlaveFsmSDA <= '1';
			end case;
		  end if;
		end if;

		-- Status Register synchronizers
		if resetn = '0' or ClearI2CSXC = '1' then
			I2CSXC <= '0';
		end if;

		if resetn = '0' or ClearI2CSNR = '1' then
			I2CSNR <= '0';
		end if;

		if resetn = '0' or ClearI2CSOVF = '1' then
			I2CSOVF <= '0';
		end if;

		if resetn = '0' or ClearI2CSTXE = '1' then
			I2CSTXE <= '0';
		end if;

		if resetn = '0' or ClearI2CSA = '1' then
			I2CSA <= '0';
		end if;

		if resetn = '0' then
			I2CxSRX <= (others => '0');
			srx_tgl <= '0';
			SlaveData <= (others => '0');
		end if;

	end process;



	/* -------- Register read CDC ----------
	   Nothing here is clocked by EnMemPeriph. The three volatile words are carried
	   into ClkMem permanently, and the word the read path presents is one
	   register's value from one ClkMem edge. I2C's rdata_out is COMBINATIONAL
	   (REGISTERED_READ = false) and MCU.vhd's i2c_rdata_bridge is the flop that
	   captures it, on the rising mclk edge of the access; that edge is the
	   snapshot edge, and these copies are what it samples.

	   I2CxSR is sixteen INDEPENDENT flags in the ClkMaster and smclk domains,
	   which is what work.sync's WIDTH is for; each bit is two ClkMem edges
	   behind its source. Four of them stood in the SDA_IN and SCL_IN domains
	   until the slave was oversampled; none does now.

	   I2CxMRX and I2CxSRX are 8-bit words and may not cross bit by bit, so they do
	   not go through work.sync at all: each receive EVENT crosses as a toggle and
	   the byte is copied by an ordinary ClkMem flop on the synchronized edge. At
	   that edge the source has been stable for two ClkMem periods, because the
	   next byte is a further eight SCL periods away. I2CxMRX used to be read
	   COMBINATIONALLY out of the ClkMaster domain with no snapshot at all; it now
	   crosses like its slave counterpart. */
	sr_sync_d <= I2CxSR;
	u_sync_I2CxSR : entity work.sync
		generic map (WIDTH => 16, DEPTH => 2)
		port map (clk => ClkMem, areset => resetn, d => sr_sync_d, q => I2CxSR_mem);

	rx_tgl_d <= srx_tgl & mrx_tgl;
	u_sync_rx_tgl : entity work.sync
		generic map (WIDTH => 2, DEPTH => 2)
		port map (clk => ClkMem, areset => resetn, d => rx_tgl_d, q => rx_tgl_q);

	rx_cap_proc: process(ClkMem, resetn)
	begin
		if resetn = '0' then
			mrx_tgl_prev <= '0';
			srx_tgl_prev <= '0';
			I2CxMRX_mem  <= (others => '0');
			I2CxSRX_mem  <= (others => '0');
		elsif rising_edge(ClkMem) then
			mrx_tgl_prev <= rx_tgl_q(0);
			srx_tgl_prev <= rx_tgl_q(1);
			if rx_tgl_q(0) /= mrx_tgl_prev then
				I2CxMRX_mem <= I2CxMRX;
			end if;
			if rx_tgl_q(1) /= srx_tgl_prev then
				I2CxSRX_mem <= I2CxSRX;
			end if;
		end if;
	end process;

	/* Clear shadow. The thirteen W1C flags are cleared ASYNCHRONOUSLY in their own
	   domains, so a clear needs the same two ClkMem edges to travel back through
	   u_sync_I2CxSR that the set needed coming in, and a read on the access after
	   the clearing write would still see the old 1. The armed pattern is held over
	   exactly those two edges, so a flag retires on the next access as it did off
	   the falling-EnMemPeriph pre-latch. A hardware set inside the window is not
	   lost: the source flag is sticky and reappears when the mask retires. The
	   arming term is the COMBINATIONAL wr_hit, valid AT the access edge; the held
	   Clear* levels rise after it and retire on deselect, so no ClkMem edge ever
	   samples them high. */
	sr_clr_now <= (W1C(RegSlotI2CxSR)(15 downto 8) and wdata(15 downto 8) and (15 downto 8 => not WEn(1)))
	            & (W1C(RegSlotI2CxSR)(7 downto 0)  and wdata(7 downto 0)  and (7 downto 0 => not WEn(0)))
	              when wrh_s(RegSlotI2CxSR) = '1' else (others => '0');

	sr_shadow_proc: process(ClkMem, resetn)
	begin
		if resetn = '0' then
			sr_clr_pipe0 <= (others => '0');
			sr_clr_pipe1 <= (others => '0');
		elsif rising_edge(ClkMem) then
			sr_clr_pipe0 <= sr_clr_now;
			sr_clr_pipe1 <= sr_clr_pipe0;
		end if;
	end process;

	I2CxSR_rd <= I2CxSR_mem and not (sr_clr_pipe0 or sr_clr_pipe1);



	-- Register Memory Interface ----------
	-- One periph_regs instance replaces the slot decode, the byte-lane write case,
	-- the write-1-to-clear arm and the read mux. What stays here is the datapath:
	-- the flow-control command flops, which the consuming FSM clears, and the read
	-- CDC above, which is a CDC judgement.
	--
	-- REGISTERED_READ is FALSE. I2C's read has always been combinational and
	-- MCU.vhd's i2c_rdata_bridge is the flop that captures it at the access edge;
	-- registering it here as well would land the data a cycle after the arbiter
	-- samples it. See hdl/common/regs/REGFILE.md, "The read path".
	--
	-- STROBE_HOLD is TRUE: the status clear requests are asynchronous clears in
	-- the smclk and pin-edge domains and must last the whole select window, which
	-- is what `if EnMemPeriph /= '0' then Clear* <= '0'` used to say.
	u_regs: entity work.periph_regs
		generic map (
			NWORDS          => NWORDS,
			RSTVAL          => RSTVAL,
			RSTVAL_OR       => RSTVAL_OR_I2C,
			IMPL            => IMPL,
			W1C             => W1C,
			WOSET           => WOSET,
			WOT             => WOT,
			PULSE           => PULSE,
			RCLR            => RCLR,
			HWOWN           => HWOWN,
			STROBE_HOLD     => true,
			REGISTERED_READ => false)
		port map (
			ClkMem      => ClkMem,
			resetn      => resetn,
			EnMemPeriph => EnMemPeriph,
			WEn         => WEn,
			MABPart     => MABPart,
			wdata       => wdata,
			rdata_out   => rdata_out,
			regs        => regs_q,
			wr_inhibit  => wr_inh,
			hw_rd       => hw_rd_s,
			acc_hit     => acc_s,
			wr_hit      => wrh_s,
			rd_strobe   => open,
			wr_strobe   => open,
			wr_pulse    => open,
			w1c_hit     => w1c_s,
			woset_hit   => open,
			wot_hit     => open,
			rd_clr      => open);

	-- The three words that hold no flop here: I2CxSR, I2CxMRX and I2CxSRX read the
	-- ClkMem copies built above. I2CxFCR is write-1-only and reads 0, which it does
	-- by holding no storage and no hw_rd row.
	hw_rd_s <= (RegSlotI2CxSR  => pad(I2CxSR_rd),
	            RegSlotI2CxMRX => pad(I2CxMRX_mem),
	            RegSlotI2CxSRX => pad(I2CxSRX_mem),
	            others         => (others => '0'));

	-- I2CxMTX is the one storage word whose write is conditional: it lands only
	-- while the master is enabled, because the same write launches a byte.
	wr_inh <= (RegSlotI2CxMTX => not I2CMEN, others => '0');

	-- The thirteen status clear requests.
	/* Each reaches an ASYNCHRONOUS clear in the ClkMaster or smclk domain, so
	   its WIDTH is what makes it land. The clears stay ASYNCHRONOUS after the
	   oversampling: smclk is divisible against ClkMem at run time, so a level
	   two and a half ClkMem periods wide is not guaranteed to meet an smclk
	   edge, and a level-sensitive clear does not need to. Each takes the registered held
	   strobe as before, WIDENED by the ClkMem clear shadow: the combinational
	   access condition plus the two shadow stages is a level about two and a half
	   ClkMem periods wide, in the ClkMem domain, and it does not depend on how long
	   the fabric holds the select. The held strobe alone does: periph_regs retires
	   it asynchronously on EnMemPeriph, which the MCU deasserts on the same mclk
	   edge the strobe is set, so with the falling-mclk en_q shim gone it would be a
	   runt. Additive: nothing the held strobe did is taken away. */
	ClearI2CSPR	<= w1c_s(RegSlotI2CxSR)(I2CSPR_LSB) or sr_clr_now(I2CSPR_LSB)
					or sr_clr_pipe0(I2CSPR_LSB) or sr_clr_pipe1(I2CSPR_LSB);
	ClearI2CSTR	<= w1c_s(RegSlotI2CxSR)(I2CSTR_LSB) or sr_clr_now(I2CSTR_LSB)
					or sr_clr_pipe0(I2CSTR_LSB) or sr_clr_pipe1(I2CSTR_LSB);
	ClearI2CMXC	<= w1c_s(RegSlotI2CxSR)(I2CMXC_LSB) or sr_clr_now(I2CMXC_LSB)
					or sr_clr_pipe0(I2CMXC_LSB) or sr_clr_pipe1(I2CMXC_LSB);
	ClearI2CMNR	<= w1c_s(RegSlotI2CxSR)(I2CMNR_LSB) or sr_clr_now(I2CMNR_LSB)
					or sr_clr_pipe0(I2CMNR_LSB) or sr_clr_pipe1(I2CMNR_LSB);
	ClearI2CMTXE	<= w1c_s(RegSlotI2CxSR)(I2CMTXE_LSB) or sr_clr_now(I2CMTXE_LSB)
					or sr_clr_pipe0(I2CMTXE_LSB) or sr_clr_pipe1(I2CMTXE_LSB);
	ClearI2CMARB	<= w1c_s(RegSlotI2CxSR)(I2CMARB_LSB) or sr_clr_now(I2CMARB_LSB)
					or sr_clr_pipe0(I2CMARB_LSB) or sr_clr_pipe1(I2CMARB_LSB);
	ClearI2CMSPS	<= w1c_s(RegSlotI2CxSR)(I2CMSPS_LSB) or sr_clr_now(I2CMSPS_LSB)
					or sr_clr_pipe0(I2CMSPS_LSB) or sr_clr_pipe1(I2CMSPS_LSB);
	ClearI2CMSTS	<= w1c_s(RegSlotI2CxSR)(I2CMSTS_LSB) or sr_clr_now(I2CMSTS_LSB)
					or sr_clr_pipe0(I2CMSTS_LSB) or sr_clr_pipe1(I2CMSTS_LSB);
	ClearI2CSXC	<= w1c_s(RegSlotI2CxSR)(I2CSXC_LSB) or sr_clr_now(I2CSXC_LSB)
					or sr_clr_pipe0(I2CSXC_LSB) or sr_clr_pipe1(I2CSXC_LSB);
	ClearI2CSNR	<= w1c_s(RegSlotI2CxSR)(I2CSNR_LSB) or sr_clr_now(I2CSNR_LSB)
					or sr_clr_pipe0(I2CSNR_LSB) or sr_clr_pipe1(I2CSNR_LSB);
	ClearI2CSOVF	<= w1c_s(RegSlotI2CxSR)(I2CSOVF_LSB) or sr_clr_now(I2CSOVF_LSB)
					or sr_clr_pipe0(I2CSOVF_LSB) or sr_clr_pipe1(I2CSOVF_LSB);
	ClearI2CSTXE	<= w1c_s(RegSlotI2CxSR)(I2CSTXE_LSB) or sr_clr_now(I2CSTXE_LSB)
					or sr_clr_pipe0(I2CSTXE_LSB) or sr_clr_pipe1(I2CSTXE_LSB);
	ClearI2CSA	<= w1c_s(RegSlotI2CxSR)(I2CSA_LSB) or sr_clr_now(I2CSA_LSB)
					or sr_clr_pipe0(I2CSA_LSB) or sr_clr_pipe1(I2CSA_LSB);

	-- A write that LAUNCHES something on the edge it lands takes the unregistered
	-- hook, qualified with its own lane exactly as the raw decode was: a registered
	-- strobe would raise the command one ClkMem edge late.
	fcr_wr <= acc_s(RegSlotI2CxFCR) and not WEn(0);
	mtx_wr <= acc_s(RegSlotI2CxMTX) and not WEn(0);

	-- The flow-control commands: a written 1 raises one, and the FSM that consumes
	-- it clears it asynchronously. The stop and read-byte commands are accepted
	-- only while this master controls the bus.
	cmd_proc: process(resetn, ClkMem, I2CMEN, I2CMCB, ClearI2CMST, ClearI2CMSP, ClearI2CMRB, ClearMasterWrite, ClearI2CSC, I2CSCS)
	begin
		if rising_edge(ClkMem) then
			if fcr_wr = '1' then
				if wdata(I2CSC_LSB) = '1' then
					I2CSC <= '1';
				end if;
				if wdata(I2CMST_LSB) = '1' then
					I2CMST <= '1';
				end if;
				if wdata(I2CMSP_LSB) = '1' and I2CMCB = '1' then
					I2CMSP <= '1';
				end if;
				if wdata(I2CMRB_LSB) = '1' and I2CMCB = '1' then
					I2CMRB <= '1';
				end if;
			end if;
			if mtx_wr = '1' and I2CMEN = '1' then
				-- Issue the command to send the byte written to I2CxMTX; the byte
				-- itself is periph_regs' storage, gated by the same enable.
				MasterWrite <= '1';
			end if;
		end if;

		-- Latch clear signal(s)
		if (resetn = '0') or (ClearI2CMST = '1') or (I2CMEN = '0') then
			I2CMST <= '0';
		end if;

		if (resetn = '0') or (ClearI2CMSP = '1') or (I2CMCB = '0') then
			I2CMSP <= '0';
		end if;

		if (resetn = '0') or (ClearI2CMRB = '1') or (I2CMCB = '0') then
			I2CMRB <= '0';
		end if;

		if (resetn = '0') or (ClearMasterWrite = '1') or (I2CMEN = '0') then
			MasterWrite <= '0';
		end if;

		if (resetn = '0') or (ClearI2CSC = '1') or (I2CSCS = '0') then
			I2CSC <= '0';
		end if;
	end process;

end behavioral;
