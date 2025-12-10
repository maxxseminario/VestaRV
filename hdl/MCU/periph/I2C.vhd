library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;
use work.MemoryMap.all;

-- I2C specification: https://www.nxp.com/docs/en/user-guide/UM10204.pdf

entity I2C is
	generic (
		default_SAD	: std_logic_vector(6 downto 0) := (others => '0')	-- The default slave address for this I2C peripheral
	);
	port
	(
		-- System Signals
		smclk			: in	std_logic;	-- Sub-main clock
		resetn			: in	std_logic;	-- System reset
		-- IRQ				: out	std_logic;	-- I2C interrupt output to processor
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

	constant mem_assert : std_logic := '0';


	---------- Register and Bit Field Signal Declarations ----------
	-- Registers
	signal I2CxCR		: std_logic_vector(21 downto 0);	-- I2C control register
	--signal I2CxFCR		: std_logic_vector();	-- I2C flow control register
	signal I2CxSR		: std_logic_vector(15 downto 0);	-- I2C status register
	signal I2CxSRLat	: std_logic_vector(15 downto 0);
	signal I2CxMTX		: std_logic_vector(7 downto 0);	-- I2C master mode transmit register
	signal I2CxMRX		: std_logic_vector(7 downto 0);	-- I2C master mode receive register
	signal I2CxSTX		: std_logic_vector(7 downto 0);	-- I2C slave mode transmit register
	signal I2CxSRX		: std_logic_vector(7 downto 0);	-- I2C slave mode receive register
	signal I2CxSRXLat	: std_logic_vector(7 downto 0);
	signal I2CxAR		: std_logic_vector(6 downto 0);	-- I2C slave address register for this device
	signal I2CxAMR		: std_logic_vector(6 downto 0);	-- I2C slave address mask. Any bits that are a '1' in this register cause the same bits in the slave address register to accept both '0's and '1's when listening for the slave address

	-- I2CxCR
	signal I2CSTRIE		: std_logic;	-- I2C start received interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CSPRIE		: std_logic;	-- I2C stop received interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMSTSIE	: std_logic;	-- I2C master mode start condition sent interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMSPSIE	: std_logic;	-- I2C master mode stop condition sent interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMARBIE	: std_logic;	-- I2C master mode arbitration error interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMTXEIE	: std_logic;	-- I2C master transmit register empty interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMNRIE		: std_logic;	-- I2C master mode NACK received interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMXCIE		: std_logic;	-- I2C master transfer complete interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CSAIE		: std_logic;	-- I2C slave mode addressed interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CSTXEIE	: std_logic;	-- I2C slave transmit register empty interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CSOVFIE	: std_logic;	-- I2C slave receive register overflow interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CSNRIE		: std_logic;	-- I2C slave mode NACK received from master interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CSXCIE		: std_logic;	-- I2C slave mode transfer complete interrupt enable. '0' <= interrupt disabled; '1' <= interrupt enabled
	signal I2CMDIV		: std_logic_vector(3 downto 0);	-- I2C master mode clock divider. The master mode finite state machine clock source is smclk, which is divided by a factor of 4 * 2^I2CMDIV
	signal I2CGCE		: std_logic;	-- I2C slave general call enable. When enabled, this slave will be addressed if a global call is issued for slave receiver mode. '0' <= disabled; '1' <= enabled
	signal I2CSN		: std_logic;	-- I2C slave NACK next byte received. When this slave receives its address or a data byte from the master, send a NACK in reply. '0' <= send an ACK; '1' <= send a NAKC
	signal I2CSCS		: std_logic;	-- I2C slave clock stretching enable. When enabled, the slave will hold the SCL line low during the slave ACK states. '0' <= SCL forced to '0' while in slave ACK state; '1' <= SCL released to '1' during all slave states
	signal I2CSEN		: std_logic;	-- I2C slave enable. When enabled, this device behaves as an I2C slave and begins listening for its address. If master mode is also enabled on this device, then this device will act as a slave until commanded to send a start condition with I2CMST, whereupon it will begin acting as a master. Once the master transfer is complete, it will resume acting as a slave. '0' <= disabled; '1' <= enabled.
	signal I2CMEN		: std_logic;	-- I2C master enable. When enabled, this device awaits a command to send a start condition with I2CMST, and then begins acting as a master until commanded to send a stop condition with I2CMSP. If master mode is also enabled on this device, then this device will act as a slave until commanded to send a start condition with I2CMST, whereupon it will begin acting as a master. Once the master transfer is complete, it will resume acting as a slave. '0' <= disabled; '1' <= enabled.

	-- I2CxFCR (everything in this register is write-1 only, and reads as all '0's)
	signal I2CSC		: std_logic;	-- I2C slave continue. When clock stretching is enabled, set this bit to tell the slave to continue with the ACK/NACK phase of the transfer by releasing SCL.
	signal I2CMRB		: std_logic;	-- I2C master read byte. Enter master receiver mode and begin reading a byte from the slave.
	signal I2CMSP		: std_logic;	-- I2C master send stop condition.
	signal I2CMST		: std_logic;	-- I2C master send start condition. This should be the ONLY way to send a START condition.

	-- I2CxSR
	signal I2CSTR		: std_logic;	-- I2C start received interrupt flag. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CSPR		: std_logic;	-- I2C stop received interrupt flag. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CMXC		: std_logic;	-- I2C master transfer complete interrupt flag. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CMNR		: std_logic;	-- I2C master mode NACK received interrupt flag.
	signal I2CMTXE		: std_logic;	-- I2C master transmit register empty interrupt flag. Indicates that the transmit register is ready to accept another byte. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CMARB		: std_logic;	-- I2C master mode arbitration error interrupt flag. '0' <= no arbitration error; '1' <= arbitration error
	signal I2CMSPS		: std_logic;	-- I2C master mode stop condition sent interrupt flag. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CMSTS		: std_logic;	-- I2C master mode start condition sent interrupt flag. '0' <= no pending interrupt; '1' <= pending interrupt

	signal I2CSXC		: std_logic;	-- I2C slave mode transfer complete interrupt flag. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CSNR		: std_logic;	-- I2C slave mode NACK received from master interrupt flag. '0' <= NACK not received; '1' <= NACK received (interrupt pending)
	signal I2CSOVF		: std_logic;	-- I2C slave receive register overflow interrupt flag. Indicates that this slave has failed to read one or more bytes from the I2CxSRX register before they were overwritten. '0' <= no interrupt pending; '1' <= interrupt pending
	signal I2CSTXE		: std_logic;	-- I2C slave transmit register empty interrupt flag. Indicates that the transmit register is ready to accept another byte. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CSA		: std_logic;	-- I2C slave mode addressed interrupt flag, indicates that this slave has been addressed. '0' <= no pending interrupt; '1' <= pending interrupt
	signal I2CSTM		: std_logic;	-- I2C slave transmitter mode. Indicates that the slave has been addressed for slave transmitter mode. Only valid if I2CSA = '1'. '0' <= slave receiver mode (read bit was '0'); '1' <= slave transmitter mode (read bit was '1')
	signal I2CMCB		: std_logic;	-- I2C master controls bus flag. '0' <= this master is not in currenlty in control of the bus; '1' <= this master controls the bus
	signal I2CBS		: std_logic;	-- I2C bus state. '0' <= bus is idle; '1' <= bus is active


	---------- Memory Bus Signal Declarations ----------
	signal MABPartInteger	: natural range 0 to 63;
	signal rdataPart		: std_logic_vector(21 downto 0);	-- The part of rdata_out that the registers use
	


	---------- I2C Core Signal Declarations ----------
	type MasterState_t is (MasterStateStart1, MasterStateStart2, MasterStateDataTransmitter1, MasterStateDataTransmitter2, MasterStateDataTransmitter3, MasterStateDataTransmitter4, MasterStateAckTransmitter1, MasterStateAckTransmitter2, MasterStateAckTransmitter3, MasterStateAckTransmitter4, MasterStateDataReceiver1, MasterStateDataReceiver2, MasterStateDataReceiver3, MasterStateDataReceiver4, MasterStateAckReceiver1, MasterStateAckReceiver2, MasterStateAckReceiver3, MasterStateAckReceiver4, MasterStateStop1, MasterStateStop2, MasterStateStop3);
	type SlaveState_t is (SlaveStateAddr, SlaveStateAck, SlaveStateReceiver, SlaveStateTransmitter, SlaveStateNotAddressed);
	
	signal StartSlaveRX			: std_logic;	-- Indicates a start condition was just received. Signals the slave process to awaken.
	signal ClearStartSlaveRX	: std_logic;
	
	signal MasterSDA			: std_logic;	-- The desired value of SDA while in Master mode. Write to this what you want the actual value of SDA to be ('0' for pulled low, '1' for released high). Do not pay attention to what the value of SDA_DIR should be when setting this.
	signal MasterSCL			: std_logic;	-- The desired value of SCL while in Master mode. Write to this what you want the actual value of SCL to be ('0' for pulled low, '1' for released high). Do not pay attention to what the value of SCL_DIR should be when setting this.
	signal ClkMaster			: std_logic;	-- The clock for the Master mode FSM
	signal EnClkMaster			: std_logic;
	signal MasterState			: MasterState_t;	-- The state of the master FSM
	signal MasterBit			: std_logic_vector(2 downto 0);	-- The master mode bit number to transfer next
	signal MasterData			: std_logic_vector(7 downto 0);	-- The data being sent/received in Master mode
	signal ClearI2CMST			: std_logic;
	signal ClearI2CMSP			: std_logic;
	signal ClearI2CMRB			: std_logic;

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

	signal MasterWrite			: std_logic;	-- Indicates that the master should enter master transmitter mode and begin sending a byte to the slave
	signal ClearMasterWrite		: std_logic;

	signal SlaveSDA				: std_logic;	-- The desired value of SDA while in Slave mode. Write to this what you want the actual value of SDA to be ('0' for pulled low, '1' for released high). Do not pay attention to what the value of SDA_DIR should be when setting this.
	signal SlaveFsmSDA			: std_logic;	-- The value of SDA as dictated by the slave FSM, which is used whenever the slave is not ACKing/NACKing
	signal SlaveSCL				: std_logic;	-- The desired value of SCL while in Slave mode. Write to this what you want the actual value of SCL to be ('0' for pulled low, '1' for released high). Do not pay attention to what the value of SCL_DIR should be when setting this.
	signal SlaveState			: SlaveState_t;	-- The state of the slave FSM
	signal SDA_LAT				: std_logic;	-- A sampled value of SDA on the rising edge of SCL, for use in the slave FSM
	signal SlaveBit				: std_logic_vector(2 downto 0);	-- The slave mode bit number to receive next
	signal SlaveData			: std_logic_vector(7 downto 0);	-- The slave data
	--signal SlaveAddressed		: std_logic;	-- Indicates that this slave has been addressed (this is different than the slave addressed interrupt flag, which can be cleared in the status register)
	signal SlaveJustAddressed	: std_logic;	-- Indicates that the slave was just addressed, and no bytes have been sent/received in the current transmission
	signal ClearI2CSC			: std_logic;
	
begin

	---------- Register Signal Routing ----------
	-- I2CxCR
	I2CSPRIE	<= I2CxCR(0);
	I2CSTRIE	<= I2CxCR(1);
	I2CMXCIE	<= I2CxCR(2);
	I2CMNRIE	<= I2CxCR(3);
	I2CMTXEIE	<= I2CxCR(4);
	I2CMARBIE	<= I2CxCR(5);
	I2CMSPSIE	<= I2CxCR(6);
	I2CMSTSIE	<= I2CxCR(7);
	I2CSXCIE	<= I2CxCR(8);
	I2CSNRIE	<= I2CxCR(9);
	I2CSOVFIE	<= I2CxCR(10);
	I2CSTXEIE	<= I2CxCR(11);
	I2CSAIE		<= I2CxCR(12);
	I2CMDIV		<= I2CxCR(16 downto 13);
	I2CGCE		<= I2CxCR(17);
	I2CSCS		<= I2CxCR(18);
	I2CSN		<= I2CxCR(19);
	I2CSEN		<= I2CxCR(20);
	I2CMEN		<= I2CxCR(21);
	

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



	---------- I2C Core ----------
	-- Signal Routing
	SDA_OUT <= '0';
	SCL_OUT <= '0';
	SDA_REN <= SDA_REN_in;
	SCL_REN <= SCL_REN_in;
	SDA_DIR <= (not MasterSDA) when I2CMCB = '1' else (not SlaveSDA);
	SCL_DIR <= (not MasterSCL) when I2CMCB = '1' else (not SlaveSCL);



	-- Interrupts
	-- IRQ <= (I2CSTR and I2CSTRIE) or (I2CSPR and I2CSPRIE) or (I2CMSTS and I2CMSTSIE) or (I2CMSPS and I2CMSPSIE) or (I2CMARB and I2CMARBIE) or (I2CMTXE and I2CMTXEIE) or (I2CMNR and I2CMNRIE) or (I2CMXC and I2CMXCIE) or (I2CSA and I2CSAIE) or (I2CSTXE and I2CSTXEIE) or (I2CSOVF and I2CSOVFIE) or (I2CSNR and I2CSNRIE) or (I2CSXC and I2CSXCIE);
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



	-- I2C Bus State Sensor
	process (resetn, I2CMEN, I2CSEN, ClearStartSlaveRX, ClearI2CSTR, SDA_IN)
	begin
		-- Watch for a start condition (or restart condition), which happens when SDA has a falling edge while SCL is stable on '1'
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') or ClearStartSlaveRX = '1' then
			StartSlaveRX <= '0';
		elsif falling_edge(SDA_IN) then
			if SCL_IN = '1' then
				StartSlaveRX <= '1';
				I2CSTR <= '1';
			end if;
		end if;

		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') or ClearI2CSTR = '1' then
			I2CSTR <= '0';
		end if;
	end process;

	process (resetn, I2CMEN, I2CSEN, SCL_IN)
	begin
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') then
			ClearStartSlaveRX <= '0';
		elsif falling_edge(SCL_IN) then
			-- Clear the start slave RX line
			-- There is one major issue with doing it this way: if there is a start condition immediately followed by a stop condition (i.e. no data sent, so no SCL clock transistions), it will fail to recognize the stop condition.
			ClearStartSlaveRX <= StartSlaveRX;
		end if;
	end process;

	process (resetn, I2CMEN, I2CSEN, StartSlaveRX, ClearI2CSPR, SDA_IN)
	begin
		-- Watch for a stop condition, which happens when SDA has a rising edge while SCL is stable on '1'
		if resetn = '0' or (I2CMEN = '0' and I2CSEN = '0') then
			I2CBS <= '0';
		elsif StartSlaveRX = '1' then
			I2CBS <= '1';
		elsif rising_edge(SDA_IN) then
			if SCL_IN = '1' then
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
		nbits	=> 4	-- 4 bits => 16 selections => max divider of 2^15 (32768)
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
					-- This state is responsible for first checking if the bus is available and, if so, generating the first part of the start condition: the falling edge of SDA. If the bus is not available, it waits until the bus is available and then generates a start condition.
					ClearI2CMST <= '1';
					MasterBit <= "111";
					
					-- Ensure SCL is not asserted
					MasterSCL <= '1';

					-- Check the bus state if this master is not already in control of the bus (aka, check unless this is a repeated start)
					if (I2CMCB = '1' or I2CBS = '0') and MasterSCL = '1' then
						-- The bus is (probably) idle. Indicate that this master has control of the bus and create a falling edge of SDA to begin the start condition.
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
						--ClearI2CMST <= '0';	-- Already done at the top
						ClearMasterWrite <= '1';
						MasterData <= I2CxMTX;
						MasterState <= MasterStateDataTransmitter1;
					end if;
				
				-- These next master transmitter states are responsible for sending a byte of data. They also watch for arbitration errors and slaves that stretch the clock.
				when MasterStateDataTransmitter1 =>
					-- This state configures SDA with the data to be sent
					-- Send the next data bit on SDA, MSB first
					MasterSDA <= MasterData(7);
					MasterData <= MasterData(6 downto 0) & '1';

					-- If this is the first bit of a master transmitter, indicate that the transmit register is empty
					if ClearMasterWrite = '1' then
						--ClearMasterWrite <= '0';	-- Already done at the top
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
						-- The slave has released the clock. Check for a loss of arbitration
						if SDA_IN /= MasterSDA then
							-- Arbitration lost. Give up control of the bus by releasing SDA (SCL is already '1' at this point)
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
					-- This state causes the falling edge of SCL. If this is the last byte, then it latches the new receive register, sets the transfer complete flag, and waits for a command to read another byte or send a stop condition.
					MasterSCL <= '0';
					MasterBit <= MasterBit - 1;	-- Might get overridden below, this is intentional

					if MasterBit = "000" then
						-- This is the last bit
						-- Set the transfer complete flag and latch in the received data only the first time through this state
						if MasterSCL = '1' then
							I2CMXC <= '1';
							I2CxMRX <= MasterData;
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
						-- The master either wishes to end the transaction with a stop condition or begin a brand new transaction. Either way, send a NACK
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
					--ClearI2CMST <= '0';	-- Already done at the top
					--ClearI2CMSP <= '0';	-- Already done at the top
					--ClearI2CMRB <= '0';	-- Already done at the top
					--ClearMasterWrite <= '0';	-- Already done at the top
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
		end if;
		
	end process;



	-- Slave Mode FSM
	process (resetn, I2CSEN, I2CBS, I2CMCB, SCL_IN)
	begin
		if resetn = '0' or I2CSEN = '0' or I2CBS = '0' or I2CMCB = '1' then
			SDA_LAT <= '0';
		elsif rising_edge (SCL_IN) then
			SDA_LAT <= SDA_IN;
		end if;
	end process;

	SlaveSDA <= I2CSN when (SlaveJustAddressed = '1' or I2CSTM = '0') and SlaveState = SlaveStateAck else SlaveFsmSDA;	-- SDA is ordinarily controlled by the slave FSM, except for when the slave ACKs/NACKs after receiving its address or after receiving a data byte from the master
	SlaveSCL <= '0' when I2CSCS = '1' and I2CSC = '0' and SlaveState = SlaveStateAck else '1';	-- The slave usually does not assert SCL, except for when it wants to stretch the clock. In this implementation, the only (optional, when I2CSCS = '1') clock stretching done is during the ACK/NACK phase to allow this slave to prepare for the next byte transfer.

	process (resetn, I2CSEN, I2CBS, StartSlaveRX, I2CMCB, ClearI2CSXC, ClearI2CSNR, ClearI2CSOVF, ClearI2CSTXE, ClearI2CSA, SCL_IN)
	begin
		if resetn = '0' or I2CSEN = '0' or I2CBS = '0' or StartSlaveRX = '1' or I2CMCB = '1' then
			SlaveState <= SlaveStateAddr;
			SlaveFsmSDA <= '1';
			SlaveBit <= "111";
			--SlaveAddressed <= '0';
			SlaveJustAddressed <= '0';
			ClearI2CSC <= '1';
			I2CSTM <= '0';
		elsif falling_edge(SCL_IN) then
			SlaveJustAddressed <= '0';
			ClearI2CSC <= '1';
			
			-- Decrement the slave bit by defalut
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
							-- This slave has been addressed, or a general call (for slave receiver mode) has been issued
							-- Indicate that this slave is addressed
							--SlaveAddressed <= '1';
							I2CSA <= '1';	-- The slave addressed flag needs a separate signal from SlaveAddressed because it should be able to be cleared in the status register

							-- Latch the receive register
							I2CxSRX <= SlaveData(6 downto 0) & SDA_LAT;

							-- Check for an overflow
							if I2CSXC = '1' then
								I2CSOVF <= '1';
							end if;

							-- Latch the read/write mode on SDA
							I2CSTM <= SDA_LAT;

							-- Prepare for the ACK state
							SlaveFsmSDA <= '1';	-- Release SDA. The actual ACK/NACK logic will be performed by combinatorial logic outside the FSM
							SlaveJustAddressed <= '1';
							ClearI2CSC <= '0';	-- Allow I2CSC to be set
							SlaveState <= SlaveStateAck;
						else
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

						-- If an ACK was received from the master, begin sending the next byte of data. If a NACK was received, release SDA
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

						-- Check for an overflow
						if I2CSXC = '1' then
							I2CSOVF <= '1';
						end if;

						-- Indicate that the transfer is complete
						I2CSXC <= '1';

						-- Prepare for the ACK state
						SlaveFsmSDA <= '1';	-- Release SDA. The actual ACK/NACK logic will be performed by combinatorial logic outside the FSM
						ClearI2CSC <= '0';	-- Allow I2CSC to be set
						SlaveState <= SlaveStateAck;
					end if;
				when SlaveStateTransmitter =>
					-- This state is responsible for sending a byte of data to the master
					-- SlaveData has already been latched with the new data in I2CxSTX
					-- I2CSTXE has already been set
					-- Send the next bit on SDA by default. This will never be the MSB, since it is sent in the ACK state
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
			SlaveData <= (others => '0');
		end if;

	end process;



	---------- Register Synchronizer ----------
	-- Synchronizes the asynchronous register signals
	-- Only sample the registers when the processor accesses the peripheral's memory space
	-- This is safe because EnMemPeriph has a leading edge exactly one clock cycle before rdata latches a register. Also, the double NOT gates reduce the chance of a undefined bit
	GenRegSync0: if mem_assert = '0' generate
		process (EnMemPeriph)
		begin
			if falling_edge(EnMemPeriph) then
				I2CxSRLat <= not I2CxSR;
				I2CxSRXLat <= not I2CxSRX;
			end if;
		end process;
	end generate;

	GenRegSync1: if mem_assert = '1' generate
		process (EnMemPeriph)
		begin
			if rising_edge(EnMemPeriph) then
				I2CxSRLat <= not I2CxSR;
				I2CxSRXLat <= not I2CxSRX;
			end if;
		end process;
	end generate;



	---------- Register Memory Interface ----------
	MABPartInteger <= slv2uint(MABPart) when (EnMemPeriph = mem_assert) else 0;
	
	-- Register Write
	process(resetn, ClkMem, EnMemPeriph, I2CMEN, I2CMCB, ClearI2CMST, ClearI2CMSP, ClearI2CMRB, ClearMasterWrite, ClearI2CSC, I2CSCS)
	begin
		if resetn = '0' then
			-- Reset clear signal(s)
			-- No signals to reset

			-- Set registers to their default values
			I2CxCR <= (others => '0');
			I2CxMTX <= (others => '0');
			I2CxSTX <= (others => '0');
			-- I2CxAR <= (others => '0');
			I2CxAR <= default_SAD; -- Default address for the I2C slave
			I2CxAMR <= (others => '0');
		elsif rising_edge(ClkMem) then
			-- Initialize clear signal(s)
			-- No signals to clear
			
			-- Memory writes
			if EnMemPeriph = mem_assert then
				case MABPartInteger is
				when RegSlotI2CxCR =>
					if WEn(0) = mem_assert then I2CxCR(07 downto 00) <= wdata(07 downto 00); end if;
					if WEn(1) = mem_assert then I2CxCR(15 downto 08) <= wdata(15 downto 08); end if;
					if WEn(2) = mem_assert then I2CxCR(21 downto 16) <= wdata(21 downto 16); end if;
				when RegSlotI2CxFCR =>
					if WEn(0) = mem_assert then
						if wdata(3) = '1' then
							I2CSC <= '1';
						end if;
						if wdata(2) = '1' then
							I2CMST <= '1';
						end if;
						if wdata(1) = '1' and I2CMCB = '1' then
							I2CMSP <= '1';
						end if;
						if wdata(0) = '1' and I2CMCB = '1' then
							I2CMRB <= '1';
						end if;
					end if;
				when RegSlotI2CxSR =>
					if WEn(0) = mem_assert then
						if wdata(0) = '1' then ClearI2CSPR <= '1'; end if;
						if wdata(1) = '1' then ClearI2CSTR <= '1'; end if;
						if wdata(2) = '1' then ClearI2CMXC <= '1'; end if;
						if wdata(3) = '1' then ClearI2CMNR <= '1'; end if;
						if wdata(4) = '1' then ClearI2CMTXE <= '1'; end if;
						if wdata(5) = '1' then ClearI2CMARB <= '1'; end if;
						if wdata(6) = '1' then ClearI2CMSPS <= '1'; end if;
						if wdata(7) = '1' then ClearI2CMSTS <= '1'; end if;
					end if;
					if WEn(1) = mem_assert then
						if wdata(8) = '1'  then ClearI2CSXC <= '1'; end if;
						if wdata(9) = '1'  then ClearI2CSNR <= '1'; end if;
						if wdata(10) = '1' then ClearI2CSOVF <= '1'; end if;
						if wdata(11) = '1' then ClearI2CSTXE <= '1'; end if;
						if wdata(12) = '1' then ClearI2CSA <= '1'; end if;
					end if;
				when RegSlotI2CxMTX =>
					if WEn(0) = mem_assert and I2CMEN = '1' then
						-- Issue the command to send the byte written to I2CxMTX
						MasterWrite <= '1';
						I2CxMTX <= wdata(07 downto 00);
					end if;
				when RegSlotI2CxSTX =>
					if WEn(0) = mem_assert then I2CxSTX <= wdata(07 downto 00); end if;
				when RegSlotI2CxAR =>
					if WEn(0) = mem_assert then I2CxAR <= wdata(06 downto 00); end if;
				when RegSlotI2CxAMR =>
					if WEn(0) = mem_assert then I2CxAMR <= wdata(06 downto 00); end if;
				when others =>
					null;
				end case;
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

		if (resetn = '0') or (EnMemPeriph /= mem_assert) then
			ClearI2CSPR		<= '0';
			ClearI2CSTR		<= '0';
			ClearI2CMXC		<= '0';
			ClearI2CMNR		<= '0';
			ClearI2CMTXE	<= '0';
			ClearI2CMARB	<= '0';
			ClearI2CMSPS	<= '0';
			ClearI2CMSTS	<= '0';
			ClearI2CSXC		<= '0';
			ClearI2CSNR		<= '0';
			ClearI2CSOVF	<= '0';
			ClearI2CSTXE	<= '0';
			ClearI2CSA		<= '0';
		end if;
	end process;
	
	-- Register Read
	with MABPartInteger select rdataPart <=
								I2CxCR				when RegSlotI2CxCR,
		(21 downto 16 => '0') &	(not I2CxSRLat)		when RegSlotI2CxSR,
		(21 downto 8 => '0') &	I2CxMTX				when RegSlotI2CxMTX,
		(21 downto 8 => '0') &	I2CxMRX				when RegSlotI2CxMRX,
		(21 downto 8 => '0') &	I2CxSTX				when RegSlotI2CxSTX,
		(21 downto 8 => '0') &	(not I2CxSRXLat)	when RegSlotI2CxSRX,
		(21 downto 7 => '0') &	I2CxAR				when RegSlotI2CxAR,
		(21 downto 7 => '0') &	I2CxAMR				when RegSlotI2CxAMR,
		(others => '0') when others;
	
	rdata_out <= "00000000" & "00" & rdataPart;

end behavioral;
