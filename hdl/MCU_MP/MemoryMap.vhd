library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;

package MemoryMap is

	---------- Memory Block Memory Slot Assignments ----------
	constant MemSlotROM			: natural := 00;		-- base address = 0x00000
	constant MemSlotRAM0		: natural := 01;		-- base address = 0x08000
	constant MemSlotRAM1		: natural := 02;		-- base address = 0x0C000
	constant MemSlotPeriph		: natural := 04;		-- base address = 0x04000
	

	---------- Peripheral Memory Slot Assignments ----------
	constant PeriphSlotGPIO0		: natural := 00;		-- base address = 0x4000 
	constant PeriphSlotGPIO1		: natural := 01;		-- base address = 0x4100
	constant PeriphSlotSPI0			: natural := 02;		-- base address = 0x4200
	constant PeriphSlotSPI1			: natural := 03;		-- base address = 0x4300
	constant PeriphSlotUART0		: natural := 04;		-- base address = 0x4400
	constant PeriphSlotUART1		: natural := 05;		-- base address = 0x4500
	constant PeriphSlotTIMER0		: natural := 06;		-- base address = 0x4600
	constant PeriphSlotTIMER1		: natural := 07;		-- base address = 0x4700
	constant PeriphSlotGPIO2		: natural := 08;		-- base address = 0x4800 
	constant PeriphSlotSystem0		: natural := 09;		-- base address = 0x4900 
	constant PeriphSlotNPU0			: natural := 10;		-- base address = 0x4A00
	constant PeriphSlotSARADC0		: natural := 11;		-- base address = 0x4B00
	constant PeriphSlotAFE0			: natural := 12;		-- base address = 0x4C00
	constant PeriphSlotGPIO3		: natural := 13;		-- base address = 0x4D00 
	constant PeriphSlotI2C0			: natural := 14;		-- base address = 0x4E00
	constant PeriphSlotI2C1			: natural := 15;		-- base address = 0x4F00


	constant GPIO0_MASK 	: natural := 2 ** PeriphSlotGPIO0;
	constant GPIO1_MASK 	: natural := 2 ** PeriphSlotGPIO1;
	constant GPIO2_MASK 	: natural := 2 ** PeriphSlotGPIO2;
	constant SPI0_MASK  	: natural := 2 ** PeriphSlotSPI0;
	constant SPI1_MASK  	: natural := 2 ** PeriphSlotSPI1;
	constant UART0_MASK 	: natural := 2 ** PeriphSlotUART0;
	constant UART1_MASK 	: natural := 2 ** PeriphSlotUART1;
	constant TIMER0_MASK 	: natural := 2 ** PeriphSlotTIMER0;
	constant TIMER1_MASK 	: natural := 2 ** PeriphSlotTIMER1;
	constant SYSTEM0_MASK 	: natural := 2 ** PeriphSlotSystem0;
	constant NPU0_MASK 		: natural := 2 ** PeriphSlotNPU0;
	constant SARADC0_MASK 	: natural := 2 ** PeriphSlotSARADC0;
	constant AFE0_MASK 		: natural := 2 ** PeriphSlotAFE0;
	constant GPIO3_MASK 	: natural := 2 ** PeriphSlotGPIO3;
	constant I2C0_MASK 		: natural := 2 ** PeriphSlotI2C0;
	constant I2C1_MASK 		: natural := 2 ** PeriphSlotI2C1;
	
	---------- GPIO Constants ----------
	constant gpio_dir_out		: std_logic := '1';		-- GPIO output direction
	constant gpio_dir_in		: std_logic := '0';		-- GPIO input direction
	constant gpio_ren_en		: std_logic := '1';		-- GPIO resistor enable
	constant gpio_ren_dis		: std_logic := '0';		-- GPIO resistor disable
	constant gpio_out_high		: std_logic := '1';		-- GPIO output high
	constant gpio_out_low		: std_logic := '0';		-- GPIO output low

	---------------------- Peripheral Register Address Offsets ----------------------
	-- GPIOx 
	constant RegSlotPxIN			: natural := 00;		-- offset = 0 bytes
	constant RegSlotPxOUT			: natural := 01;		-- offset = 4 bytes
	constant RegSlotPxOUTS			: natural := 02;		-- offset = 8 bytes
	constant RegSlotPxOUTC			: natural := 03;		-- offset = 12 bytes
	constant RegSlotPxOUTT			: natural := 04;		-- offset = 16 bytes
	constant RegSlotPxDIR			: natural := 05;		-- offset = 20 bytes
	constant RegSlotPxIF			: natural := 06;		-- offset = 24 bytes
	constant RegSlotPxIES			: natural := 07;		-- offset = 28 bytes
	constant RegSlotPxIE			: natural := 08;		-- offset = 32 bytes
	constant RegSlotPxSEL			: natural := 09;		-- offset = 36 bytes
	constant RegSlotPxREN			: natural := 10;		-- offset = 40 bytes

	-- SPIx
	constant RegSlotSPIxCR			: natural := 00;		-- offset = 0 bytes
	constant RegSlotSPIxSR			: natural := 01;		-- offset = 4 bytes
	constant RegSlotSPIxTX			: natural := 02;		-- offset = 8 bytes
	constant RegSlotSPIxRX			: natural := 03;		-- offset = 12 bytes
	constant RegSlotSPIxFOS			: natural := 04;		-- offset = 16 bytes

	-- TIMERx
	constant RegSlotTIMxCR			: natural := 00;		-- offset = 0 bytes
	constant RegSlotTIMxSR			: natural := 01;		-- offset = 4 bytes
	constant RegSlotTIMxVAL			: natural := 02;		-- offset = 8 bytes
	constant RegSlotTIMxCMP0		: natural := 03;		-- offset = 12 bytes
	constant RegSlotTIMxCMP1		: natural := 04;		-- offset = 16 bytes
	constant RegSlotTIMxCMP2		: natural := 05;		-- offset = 20 bytes
	constant RegSlotTIMxCAP0		: natural := 06;		-- offset = 24 bytes
	constant RegSlotTIMxCAP1		: natural := 07;		-- offset = 28 bytes

	-- UARTx
	constant RegSlotUARTxCR			: natural := 00;		-- offset = 0 bytes
	constant RegSlotUARTxSR			: natural := 01;		-- offset = 4 bytes
	constant RegSlotUARTxBR			: natural := 02;		-- offset = 8 bytes
	constant RegSlotUARTxRX			: natural := 03;		-- offset = 12 bytes
	constant RegSlotUARTxTX			: natural := 04;		-- offset = 16 bytes

	-- SYSTEMx
	constant RegSlotSYS_CLK_CR		: natural := 00;		-- offset = 0 bytes
	constant RegSlotSYS_CLK_DIV_CR	: natural := 01;		-- offset = 4 bytes
	constant RegSlotSYS_BLOCK_PWR	: natural := 02;		-- offset = 8 bytes
	constant RegSlotSYS_CRC_DATA	: natural := 03;		-- offset = 12 bytes
	constant RegSlotSYS_CRC_STATE	: natural := 04;		-- offset = 16 bytes
	constant RegSlotSYS_IRQ_ENL		: natural := 05;		-- offset = 20 bytes
	constant RegSlotSYS_IRQ_ENM		: natural := 06;		-- offset = 24 bytes
	constant RegSlotSYS_IRQ_ENU		: natural := 07;		-- offset = 28 bytes
	constant RegSlotSYS_IRQ_PRIL	: natural := 08;		-- offset = 32 bytes
	constant RegSlotSYS_IRQ_PRIM	: natural := 09;		-- offset = 36 bytes
	constant RegSlotSYS_IRQ_PRIU	: natural := 10;		-- offset = 40 bytes
	constant RegSlotSYS_IRQ_CR		: natural := 11;		-- offset = 44 bytes
	constant RegSlotSYS_WDT_PASS	: natural := 12;		-- offset = 48 bytes
	constant RegSlotSYS_WDT_CR		: natural := 13;		-- offset = 52 bytes
	constant RegSlotSYS_WDT_SR		: natural := 14;		-- offset = 56 bytes
	constant RegSlotSYS_WDT_VAL		: natural := 15;		-- offset = 60 bytes
	constant RegSlotDCO0_BIAS		: natural := 16;		-- offset = 64 bytes
	constant RegSlotDCO1_BIAS		: natural := 17;		-- offset = 68 bytes

	-- I2Cx
	constant RegSlotI2CxCR			: natural := 00;		-- offset = 0 bytes
	constant RegSlotI2CxFCR			: natural := 01;		-- offset = 4 bytes
	constant RegSlotI2CxSR			: natural := 02;		-- offset = 8 bytes
	constant RegSlotI2CxMTX			: natural := 03;		-- offset = 12 bytes
	constant RegSlotI2CxMRX			: natural := 04;		-- offset = 16 bytes
	constant RegSlotI2CxSTX			: natural := 05;		-- offset = 20 bytes
	constant RegSlotI2CxSRX			: natural := 06;		-- offset = 24 bytes
	constant RegSlotI2CxAR			: natural := 07;		-- offset = 28 bytes
	constant RegSlotI2CxAMR			: natural := 08;		-- offset = 32 bytes

	--NPUx
	constant MmrAddrNPUCR		: natural	:= 00;	-- offset = 0 bytes
	constant MmrAddrNPUIVSAR	: natural	:= 01;	-- offset = 4 bytes
	constant MmrAddrNPUWVSAR	: natural	:= 02;	-- offset = 8 bytes
	constant MmrAddrNPUOVSAR	: natural	:= 03;	-- offset = 12 bytes

	-- AFEx
	constant RegSlotAFE_CR			: natural	:= 00;	-- offset = 0 bytes
	constant RegSlotAFE_TPR			: natural	:= 01;	-- offset = 4 bytes
	constant RegSlotAFE_SR			: natural	:= 02;	-- offset = 8 bytes
	constant RegSlotAFE_ADC_VAL		: natural	:= 03;	-- offset = 12 bytes
	constant RegSlotBIAS_CR			: natural	:= 04;	-- offset = 16 bytes
	constant RegSlotBIAS_ADJ		: natural	:= 05;	-- offset = 20 bytes
	constant RegSlotBIAS_DBP		: natural	:= 06;	-- offset = 24 bytes
	constant RegSlotBIAS_DBPC		: natural	:= 07;	-- offset = 28 bytes
	constant RegSlotBIAS_DBNC		: natural	:= 08;	-- offset = 32 bytes
	constant RegSlotBIAS_DBN		: natural	:= 09;	-- offset = 36 bytes
	constant RegSlotBIAS_TC_POT		: natural	:= 10;	-- offset = 40 bytes
	constant RegSlotBIAS_LC_POT		: natural	:= 11;	-- offset = 44 bytes
	constant RegSlotBIAS_TIA_G_POT	: natural	:= 12;	-- offset = 48 bytes
	constant RegSlotBIAS_DSADC_VCM	: natural	:= 13;	-- offset = 52 bytes
	constant RegSlotBIAS_REV_POT	: natural	:= 14;	-- offset = 56 bytes
	constant RegSlotBIAS_TC_DSADC	: natural	:= 15;	-- offset = 60 bytes
	constant RegSlotBIAS_LC_DSADC	: natural	:= 16;	-- offset = 64 bytes
	constant RegSlotBIAS_RIN_DSADC	: natural	:= 17;	-- offset = 68 bytes
	constant RegSlotBIAS_RFB_DSADC	: natural	:= 18;	-- offset = 72 bytes

	--SARADCx
	constant RegSlotSARADC_CR		: natural	:= 00;	-- offset = 0 bytes
	constant RegSlotSARADC_CDIV		: natural	:= 01;	-- offset = 4 bytes
	constant RegSlotSARADC_SR		: natural	:= 02;	-- offset = 8 bytes
	constant RegSlotSARADC_DATA		: natural	:= 03;	-- offset = 12 bytes
	constant RegSlotSARADC_TPR		: natural	:= 04;	-- offset = 16 bytes




	---------- Interrupt Bit Assignments ----------------------------------------

	-- New Interrupt System (Priority from 0 to max, 0 = Highest Priority)
	constant IVT_BASE_ADDR 	: integer := 16#8000#; -- IVT base address = 0xa000
	constant IRQB_SYS_WDT	: natural := 00;	-- Watchdog Timer Interrupt IVT address = 0xa000	
	constant IRQB_GPIO0_B0	: natural := 01;	-- GPIO0 Bit 0 Interrupt IVT address = 0xa004
	constant IRQB_GPIO0_B1	: natural := 02;	-- GPIO0 Bit 1 Interrupt IVT address = 0xa008
	constant IRQB_GPIO0_B2	: natural := 03;	-- GPIO0 Bit 2 Interrupt IVT address = 0xa00C
	constant IRQB_GPIO0_B3	: natural := 04;	-- GPIO0 Bit 3 Interrupt IVT address = 0xa010
	constant IRQB_GPIO0_B4	: natural := 05;	-- GPIO0 Bit 4 Interrupt IVT address = 0xa014
	constant IRQB_GPIO0_B5	: natural := 06;	-- GPIO0 Bit 5 Interrupt IVT address = 0xa018
	constant IRQB_GPIO0_B6	: natural := 07;	-- GPIO0 Bit 6 Interrupt IVT address = 0xa01C
	constant IRQB_GPIO0_B7	: natural := 08;	-- GPIO0 Bit 7 Interrupt IVT address = 0xa020
	constant IRQB_SPI0_TC	: natural := 09;	-- SPI0 Transmission Complete Interrupt IVT address = 0xa024
	constant IRQB_SPI0_TE	: natural := 10;	-- SPI0 Transmission Buffer Empty Interrupt IVT address = 0xa028
	constant IRQB_SPI1_TC	: natural := 11;	-- SPI1 Transmission Complete Interrupt IVT address = 0xa02C
	constant IRQB_SPI1_TE	: natural := 12;	-- SPI1 Transmission Buffer Empty Interrupt IVT address = 0xa030
	constant IRQB_UART0_RC	: natural := 13;	-- UART0 Receive Complete Interrupt IVT address = 0xa034
	constant IRQB_UART0_TE	: natural := 14;	-- UART0 Transmission Buffer Empty Interrupt IVT address = 0xa038
	constant IRQB_UART0_TC	: natural := 15;	-- UART0 Transmission Complete Interrupt IVT address = 0xa03C
	constant IRQB_TIM0_CAP0	: natural := 16;	-- TIMER0 Capture 0 Interrupt IVT address = 0xa040
	constant IRQB_TIM0_CAP1	: natural := 17;	-- TIMER0 Capture 1 Interrupt IVT address = 0xa044
	constant IRQB_TIM0_OVF	: natural := 18;	-- TIMER0 Overflow Interrupt IVT address = 0xa048
	constant IRQB_TIM0_CMP0	: natural := 19;	-- TIMER0 Compare 0 Interrupt IVT address = 0xa04C
	constant IRQB_TIM0_CMP1	: natural := 20;	-- TIMER0 Compare 1 Interrupt IVT address = 0xa050
	constant IRQB_TIM0_CMP2	: natural := 21;	-- TIMER0 Compare 2 Interrupt IVT address = 0xa054
	constant IRQB_TIM1_CAP0	: natural := 22;	-- TIMER1 Capture 0 Interrupt IVT address = 0xa058
	constant IRQB_TIM1_CAP1	: natural := 23;	-- TIMER1 Capture 1 Interrupt IVT address = 0xa05C
	constant IRQB_TIM1_OVF	: natural := 24;	-- TIMER1 Overflow Interrupt IVT address = 0xa060
	constant IRQB_TIM1_CMP0	: natural := 25;	-- TIMER1 Compare 0 Interrupt IVT address = 0xa064
	constant IRQB_TIM1_CMP1	: natural := 26;	-- TIMER1 Compare 1 Interrupt IVT address = 0xa068
	constant IRQB_TIM1_CMP2	: natural := 27;	-- TIMER1 Compare 2 Interrupt IVT address = 0xa06C
	constant IRQB_GPIO1_B0	: natural := 28;	-- GPIO1 Bit 0 Interrupt IVT address = 0xa070
	constant IRQB_GPIO1_B1	: natural := 29;	-- GPIO1 Bit 1 Interrupt IVT address = 0xa074
	constant IRQB_GPIO1_B2	: natural := 30;	-- GPIO1 Bit 2 Interrupt IVT address = 0xa078
	constant IRQB_GPIO1_B3	: natural := 31;	-- GPIO1 Bit 3 Interrupt IVT address = 0xa07C
	constant IRQB_GPIO1_B4	: natural := 32;	-- GPIO1 Bit 4 Interrupt IVT address = 0xa080
	constant IRQB_GPIO1_B5	: natural := 33;	-- GPIO1 Bit 5 Interrupt IVT address = 0xa084
	constant IRQB_GPIO1_B6	: natural := 34;	-- GPIO1 Bit 6 Interrupt IVT address = 0xa088
	constant IRQB_GPIO1_B7	: natural := 35;	-- GPIO1 Bit 7 Interrupt IVT address = 0xa08C
	constant IRQB_GPIO2_B0	: natural := 36;	-- GPIO2 Bit 0 Interrupt IVT address = 0xa090
	constant IRQB_GPIO2_B1	: natural := 37;	-- GPIO2 Bit 1 Interrupt IVT address = 0xa094
	constant IRQB_GPIO2_B2	: natural := 38;	-- GPIO2 Bit 2 Interrupt IVT address = 0xa098
	constant IRQB_GPIO2_B3	: natural := 39;	-- GPIO2 Bit 3 Interrupt IVT address = 0xa09C
	constant IRQB_GPIO2_B4	: natural := 40;	-- GPIO2 Bit 4 Interrupt IVT address = 0xa0A0
	constant IRQB_GPIO2_B5	: natural := 41;	-- GPIO2 Bit 5 Interrupt IVT address = 0xa0A4
	constant IRQB_GPIO2_B6	: natural := 42;	-- GPIO2 Bit 6 Interrupt IVT address = 0xa0A8
	constant IRQB_GPIO2_B7	: natural := 43;	-- GPIO2 Bit 7 Interrupt IVT address = 0xa0AC
	constant IRQB_GPIO3_B0	: natural := 44;	-- GPIO3 Bit 0 Interrupt IVT address = 0xa0B0
	constant IRQB_GPIO3_B1	: natural := 45;	-- GPIO3 Bit 1 Interrupt IVT address = 0xa0B4
	constant IRQB_GPIO3_B2	: natural := 46;	-- GPIO3 Bit 2 Interrupt IVT address = 0xa0B8
	constant IRQB_GPIO3_B3	: natural := 47;	-- GPIO3 Bit 3 Interrupt IVT address = 0xa0BC
	constant IRQB_GPIO3_B4	: natural := 48;	-- GPIO3 Bit 4 Interrupt IVT address = 0xa0C0
	constant IRQB_GPIO3_B5	: natural := 49;	-- GPIO3 Bit 5 Interrupt IVT address = 0xa0C4
	constant IRQB_GPIO3_B6	: natural := 50;	-- GPIO3 Bit 6 Interrupt IVT address = 0xa0C8
	constant IRQB_GPIO3_B7	: natural := 51;	-- GPIO3 Bit 7 Interrupt IVT address = 0xa0CC
	constant IRQB_UART1_RC	: natural := 52;	-- UART1 Receive Complete Interrupt IVT address = 0xa0D0
	constant IRQB_UART1_TE	: natural := 53;	-- UART1 Transmission Buffer Empty Interrupt IVT address = 0xa0D4
	constant IRQB_UART1_TC	: natural := 54;	-- UART1 Transmission Complete Interrupt IVT address = 0xa0D8
	constant IRQB_AFE0_RC	: natural := 55;	-- AFE0 Receive Complete Interrupt IVT address = 0xa0DC
	constant IRQB_SAR0_RC	: natural := 56;	-- SARADC0 Conversion Complete Interrupt IVT address = 0xa0E8
	constant IRQB_I2C0_STR	: natural := 57;	-- I2C0 start received IVT address = 0xa0EC
	constant IRQB_I2C0_spr	: natural := 58;	-- I2C0 Stop Received Interrupt IVT address = 0xa0F0
	constant IRQB_I2C0_msts	: natural := 59;	-- I2C0 master mode start condition sent Interrupt IVT address = 0xa0F4
	constant IRQB_I2C0_msps	: natural := 60;	-- I2C0 master mode stop condition sent Interrupt IVT address = 0xa0F8
	constant IRQB_I2C0_marb	: natural := 61;	-- I2C0 Master Arbitration Lost Interrupt IVT address = 0xa0FC
	constant IRQB_I2C0_mtxe	: natural := 62;	-- I2C0 Master Transmit Empty Interrupt IVT address = 0xa100
	constant IRQB_I2C0_mnr 	: natural := 63;	-- I2C0 master mode NACK received Interrupt IVT address = 0xa104
	constant IRQB_I2C0_mxc 	: natural := 64;	-- I2C0 Master Transfer Complete Interrupt IVT address = 0xa108
	constant IRQB_I2C0_sa 	: natural := 65;	-- I2C0 Slave Address Interrupt IVT address = 0xa10C
	constant IRQB_I2C0_stxe	: natural := 66;	-- I2C0 Slave Transmit Empty Interrupt IVT address = 0xa110
	constant IRQB_I2C0_sovf	: natural := 67;	-- I2C0 Slave Overflow Interrupt IVT address = 0xa114
	constant IRQB_I2C0_snr 	: natural := 68;	-- I2C0 slave mode NACK received Interrupt IVT address = 0xa118
	constant IRQB_I2C0_sxc 	: natural := 69;	-- I2C0 Slave Transfer Complete Interrupt IVT address = 0xa11C
	constant IRQB_I2C1_STR	: natural := 70;	-- I2C1 start received IVT address = 0xa120
	constant IRQB_I2C1_spr	: natural := 71;	-- I2C1 Stop Received Interrupt IVT address = 0xa124
	constant IRQB_I2C1_msts	: natural := 72;	-- I2C1 master mode start condition sent Interrupt IVT address = 0xa128
	constant IRQB_I2C1_msps	: natural := 73;	-- I2C1 master mode stop condition sent Interrupt IVT address = 0xa12C
	constant IRQB_I2C1_marb	: natural := 74;	-- I2C1 master mode arbitration lost Interrupt IVT address = 0xa130
	constant IRQB_I2C1_mtxe	: natural := 75;	-- I2C1 master mode transmit empty Interrupt IVT address = 0xa134
	constant IRQB_I2C1_mnr 	: natural := 76;	-- I2C1 master mode NACK received Interrupt IVT address = 0xa138
	constant IRQB_I2C1_mxc 	: natural := 77;	-- I2C1 master mode transfer complete Interrupt IVT address = 0xa13C
	constant IRQB_I2C1_sa 	: natural := 78;	-- I2C1 Slave Address Interrupt IVT address = 0xa140
	constant IRQB_I2C1_stxe	: natural := 79;	-- I2C1 Slave Transmit Empty Interrupt IVT address = 0xa144
	constant IRQB_I2C1_sovf	: natural := 80;	-- I2C1 Slave Overflow Interrupt IVT address = 0xa148
	constant IRQB_I2C1_snr 	: natural := 81;	-- I2C1 slave mode NACK received Interrupt IVT address = 0xa14C
	constant IRQB_I2C1_sxc 	: natural := 82;	-- I2C1 Slave Transfer Complete Interrupt IVT address = 0xa150
	constant NUM_IRQS		: natural := 83;	-- Total number of IRQs
	constant NUM_GF_INSTANCES : natural := (NUM_IRQS + 31) / 32;



	---------- GPIO Register Reset Values ----------
	-- GPIO0
	-- constant RstValP1OUT	: std_logic_vector(31 downto 0) := X"00000001"; -- cs0 default to '1' to disable flash
	-- constant RstValP1DIR	: std_logic_vector(31 downto 0) := X"00000041"; -- only cs0, and trap is an output
	-- constant RstValP1SEL	: std_logic_vector(31 downto 0) := X"0000007E"; -- all alt fn except boot, cs0
	-- constant RstValP1REN	: std_logic_vector(31 downto 0) := X"00000080"; -- only boot has pullup/pulldown - should default to '1' to load from flash

	constant RstValP1OUT	: std_logic_vector(31 downto 0) := X"00000001"; -- cs0 default to '1' to disable flash
	constant RstValP1DIR	: std_logic_vector(31 downto 0) := X"00000041"; -- only cs0, and trap is an output
	constant RstValP1SEL	: std_logic_vector(31 downto 0) := X"0000004E"; -- all alt fn except boot, cs0
	constant RstValP1REN	: std_logic_vector(31 downto 0) := X"00000080"; -- only boot has pullup/pulldown - should default to '1' to load from flash



	-- GPIO0 Pin Assignments (Serial Flash) ---------------------------------
	constant pnum_gpio0_cs_flash	: natural := 00;		-- P1.0
	constant pnum_gpio0_miso		: natural := 01;		-- P1.1
	constant pnum_gpio0_mosi		: natural := 02;		-- P1.2
	constant pnum_gpio0_spi_clk		: natural := 03;		-- P1.3
	constant pnum_gpio0_lfxt		: natural := 04;		-- P1.4
	constant pnum_gpio0_hfxt		: natural := 05;		-- P1.5
	constant pnum_gpio0_trap		: natural := 06;		-- P1.6
	constant pnum_gpio0_boot		: natural := 07;		-- P1.7

	-- GPIO1 -----------------------------------------------------------------
	constant RstValP2OUT	: std_logic_vector(31 downto 0) := X"00000000"; -- all pads output low
	constant RstValP2DIR	: std_logic_vector(31 downto 0) := X"00000010"; -- tx0 is output
	constant RstValP2SEL	: std_logic_vector(31 downto 0) := X"00000030"; -- uart0 default to alt fn
	constant RstValP2REN	: std_logic_vector(31 downto 0) := X"00000000"; -- disable rens

	-- GPIO1 Pin Assignments (SPI1, UART0, UART1) ---------------------------
	constant pnum_gpio1_cs1			: natural := 00;		-- P2.0
	constant pnum_gpio1_miso1		: natural := 01;		-- P2.1
	constant pnum_gpio1_mosi1		: natural := 02;		-- P2.2
	constant pnum_gpio1_sck1		: natural := 03;		-- P2.3
	constant pnum_gpio1_tx0			: natural := 04;		-- P2.4
	constant pnum_gpio1_rx0			: natural := 05;		-- P2.5
	constant pnum_gpio1_tx1			: natural := 06;		-- P2.6
	constant pnum_gpio1_rx1			: natural := 07;		-- P2.7

	-- GPIO2 -----------------------------------------------------------------
	constant RstValP3OUT	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3DIR	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3SEL	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3REN	: std_logic_vector(31 downto 0) := X"00000000";
	-- GPIO2 Pin Assignments (TIMER0, TIMER1) ---------------------------
	constant pnum_gpio2_t0_cmp0		: natural := 00;		-- P3.0
	constant pnum_gpio2_t0_cmp1		: natural := 01;		-- P3.1
	constant pnum_gpio2_t0_cap0		: natural := 02;		-- P3.2
	constant pnum_gpio2_t0_cap1		: natural := 03;		-- P3.3
	constant pnum_gpio2_t1_cmp0		: natural := 04;		-- P3.4
	constant pnum_gpio2_t1_cmp1		: natural := 05;		-- P3.5
	constant pnum_gpio2_t1_cap0		: natural := 06;		-- P3.6
	constant pnum_gpio2_t1_cap1		: natural := 07;		-- P3.7



	-- GPIO3 -----------------------------------------------------------------
	constant RstValP4OUT	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4DIR	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4SEL	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4REN	: std_logic_vector(31 downto 0) := X"00000000";

	-- GPIO3 Pin Assignments (DTP) ---------------------------
	constant pnum_gpio3_sda0		: natural := 00;		-- P4.0
	constant pnum_gpio3_scl0		: natural := 01;		-- P4.1
	constant pnum_gpio3_sda1		: natural := 02;		-- P4.2
	constant pnum_gpio3_scl1		: natural := 03;		-- P4.3
	constant pnum_gpio3_dtp0		: natural := 04;		-- P4.4
	constant pnum_gpio3_dtp1		: natural := 05;		-- P4.5
	constant pnum_gpio3_dtp2		: natural := 06;		-- P4.6
	constant pnum_gpio3_dtp3		: natural := 07;		-- P4.7






end package MemoryMap;