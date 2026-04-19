-- MemoryMap.vhd
-- Memory map VHDL package
-- Defines the memory map of the MCU, including which RAM and peripheral slots are activated, as well as which slot each peripheral is allocated to, and the slot each register within each peripheral is allocated to
-- Generated on 2026/04/19 at 14:12:34 with the MemoryMap.py memory map generator
-- WARNING: Do not edit or modify this file!
-- 	If you need to change it, use the MemoryMap.py memory map generator tool

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
library work;
use work.Constants.all;



package MemoryMap is

	---------- Pad IP Logic Levels ----------
	constant PadOUTLogicLevel		: boolean := true;	-- Configured such that setting PxOUT to '1' will drive the output of the pad HIGH
	constant PadDIRLogicLevel		: boolean := false;	-- Configured such that setting PxDIR to '1' will set the pad to OUTPUT mode
	constant PadRENLogicLevel		: boolean := false;	-- Configured such that setting PxREN to '1' will enable the pad pullup/pulldown resistor



	---------- Memory Information ----------
	constant RamStartAddress		: natural := 32768;	-- 0x8000
	constant RamSize				: natural := 32768;	-- 0x8000



	---------- Memory Slot Enables/Disables ----------
	-- Peripheral Slot Enables/Disables
	constant UsePeriph00			: boolean := true;	-- base address = 0x4000
	constant UsePeriph01			: boolean := true;	-- base address = 0x4100
	constant UsePeriph02			: boolean := true;	-- base address = 0x4200
	constant UsePeriph03			: boolean := true;	-- base address = 0x4300
	constant UsePeriph04			: boolean := true;	-- base address = 0x4400
	constant UsePeriph05			: boolean := true;	-- base address = 0x4500
	constant UsePeriph06			: boolean := true;	-- base address = 0x4600
	constant UsePeriph07			: boolean := true;	-- base address = 0x4700
	constant UsePeriph08			: boolean := true;	-- base address = 0x4800
	constant UsePeriph09			: boolean := true;	-- base address = 0x4900
	constant UsePeriph10			: boolean := true;	-- base address = 0x4A00
	constant UsePeriph11			: boolean := true;	-- base address = 0x4B00
	constant UsePeriph12			: boolean := true;	-- base address = 0x4C00
	constant UsePeriph13			: boolean := true;	-- base address = 0x4D00
	constant UsePeriph14			: boolean := true;	-- base address = 0x4E00
	constant UsePeriph15			: boolean := true;	-- base address = 0x4F00

	-- SRAM Slot Enables/Disables
	constant UseSRAM03				: boolean := true;	-- base address = 0xC000
	constant UseSRAM04				: boolean := true;	-- base address = 0x10000



	---------- Peripheral Memory Slot Assignments ----------
	constant PeriphSlotGPIO0		: natural := 00;	-- base address = 0x4000
	constant PeriphSlotGPIO1		: natural := 01;	-- base address = 0x4100
	constant PeriphSlotSPI0			: natural := 02;	-- base address = 0x4200
	constant PeriphSlotSPI1			: natural := 03;	-- base address = 0x4300
	constant PeriphSlotUART0		: natural := 04;	-- base address = 0x4400
	constant PeriphSlotUART1		: natural := 05;	-- base address = 0x4500
	constant PeriphSlotTIMER0		: natural := 06;	-- base address = 0x4600
	constant PeriphSlotTIMER1		: natural := 07;	-- base address = 0x4700
	constant PeriphSlotGPIO2		: natural := 08;	-- base address = 0x4800
	constant PeriphSlotSYSTEM		: natural := 09;	-- base address = 0x4900
	constant PeriphSlotNPU			: natural := 10;	-- base address = 0x4A00
	constant PeriphSlotSARADC		: natural := 11;	-- base address = 0x4B00
	constant PeriphSlotAFE			: natural := 12;	-- base address = 0x4C00
	constant PeriphSlotGPIO3		: natural := 13;	-- base address = 0x4D00
	constant PeriphSlotI2C0			: natural := 14;	-- base address = 0x4E00
	constant PeriphSlotI2C1			: natural := 15;	-- base address = 0x4F00



	---------- Peripheral Register Address Offsets ----------
	-- GPIOx
	constant RegSlotPxIN			: natural := 00;	-- offset = 0 bytes
	constant RegSlotPxOUT			: natural := 01;	-- offset = 4 bytes
	constant RegSlotPxOUTS			: natural := 02;	-- offset = 8 bytes
	constant RegSlotPxOUTC			: natural := 03;	-- offset = 12 bytes
	constant RegSlotPxOUTT			: natural := 04;	-- offset = 16 bytes
	constant RegSlotPxDIR			: natural := 05;	-- offset = 20 bytes
	constant RegSlotPxREN			: natural := 06;	-- offset = 24 bytes
	constant RegSlotPxSEL			: natural := 07;	-- offset = 28 bytes
	constant RegSlotPxIF			: natural := 08;	-- offset = 32 bytes
	constant RegSlotPxIES			: natural := 09;	-- offset = 36 bytes
	constant RegSlotPxIE			: natural := 10;	-- offset = 40 bytes

	-- SPIx
	constant RegSlotSPIxCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotSPIxSR			: natural := 01;	-- offset = 4 bytes
	constant RegSlotSPIxTX			: natural := 02;	-- offset = 8 bytes
	constant RegSlotSPIxRX			: natural := 03;	-- offset = 12 bytes
	constant RegSlotSPIxFOS			: natural := 04;	-- offset = 16 bytes

	-- UARTx
	constant RegSlotUARTxCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotUARTxSR			: natural := 01;	-- offset = 4 bytes
	constant RegSlotUARTxBR			: natural := 02;	-- offset = 8 bytes
	constant RegSlotUARTxRX			: natural := 03;	-- offset = 12 bytes
	constant RegSlotUARTxTX			: natural := 04;	-- offset = 16 bytes

	-- TIMERx
	constant RegSlotTIMxCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotTIMxSR			: natural := 01;	-- offset = 4 bytes
	constant RegSlotTIMxVAL			: natural := 02;	-- offset = 8 bytes
	constant RegSlotTIMxCMP0		: natural := 03;	-- offset = 12 bytes
	constant RegSlotTIMxCMP1		: natural := 04;	-- offset = 16 bytes
	constant RegSlotTIMxCMP2		: natural := 05;	-- offset = 20 bytes
	constant RegSlotTIMxCAP0		: natural := 06;	-- offset = 24 bytes
	constant RegSlotTIMxCAP1		: natural := 07;	-- offset = 28 bytes

	-- SYSTEM
	constant RegSlotSYSCLKCR		: natural := 00;	-- offset = 0 bytes
	constant RegSlotCLKDIVCR		: natural := 01;	-- offset = 4 bytes
	constant RegSlotBLOCKPWR		: natural := 02;	-- offset = 8 bytes
	constant RegSlotCRCDATA			: natural := 03;	-- offset = 12 bytes
	constant RegSlotCRCSTATE		: natural := 04;	-- offset = 16 bytes
	constant RegSlotIRQENL			: natural := 05;	-- offset = 20 bytes
	constant RegSlotIRQENM			: natural := 06;	-- offset = 24 bytes
	constant RegSlotIRQENU			: natural := 07;	-- offset = 28 bytes
	constant RegSlotIRQPRIL			: natural := 08;	-- offset = 32 bytes
	constant RegSlotIRQPRIM			: natural := 09;	-- offset = 36 bytes
	constant RegSlotIRQPRIU			: natural := 10;	-- offset = 40 bytes
	constant RegSlotIRQCR			: natural := 11;	-- offset = 44 bytes
	constant RegSlotWDTCR			: natural := 12;	-- offset = 48 bytes
	constant RegSlotWDTSR			: natural := 13;	-- offset = 52 bytes
	constant RegSlotWDTPASS			: natural := 14;	-- offset = 56 bytes
	constant RegSlotWDTVAL			: natural := 15;	-- offset = 60 bytes
	constant RegSlotDCO0BIAS		: natural := 16;	-- offset = 64 bytes
	constant RegSlotDCO1BIAS		: natural := 17;	-- offset = 68 bytes

	-- NPU
	constant RegSlotNPUCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotNPUIVSAR		: natural := 01;	-- offset = 4 bytes
	constant RegSlotNPUWVSAR		: natural := 02;	-- offset = 8 bytes
	constant RegSlotNPUOVSAR		: natural := 03;	-- offset = 12 bytes

	-- SARADC
	constant RegSlotSARADC_CR		: natural := 00;	-- offset = 0 bytes
	constant RegSlotSARADC_CDIV		: natural := 01;	-- offset = 4 bytes
	constant RegSlotSARADC_SR		: natural := 02;	-- offset = 8 bytes
	constant RegSlotSARADC_DATA		: natural := 03;	-- offset = 12 bytes
	constant RegSlotSARADC_TPR		: natural := 04;	-- offset = 16 bytes

	-- AFE
	constant RegSlotAFE_CR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotAFE_TPR			: natural := 01;	-- offset = 4 bytes
	constant RegSlotAFE_SR			: natural := 02;	-- offset = 8 bytes
	constant RegSlotAFE_ADC_VAL		: natural := 03;	-- offset = 12 bytes
	constant RegSlotBIAS_CR			: natural := 04;	-- offset = 16 bytes
	constant RegSlotBIAS_ADJ		: natural := 05;	-- offset = 20 bytes
	constant RegSlotBIAS_DBP		: natural := 06;	-- offset = 24 bytes
	constant RegSlotBIAS_DBPC		: natural := 07;	-- offset = 28 bytes
	constant RegSlotBIAS_DBNC		: natural := 08;	-- offset = 32 bytes
	constant RegSlotBIAS_DBN		: natural := 09;	-- offset = 36 bytes
	constant RegSlotBIAS_TC_POT		: natural := 10;	-- offset = 40 bytes
	constant RegSlotBIAS_LC_POT		: natural := 11;	-- offset = 44 bytes
	constant RegSlotBIAS_TIA_G_POT	: natural := 12;	-- offset = 48 bytes
	constant RegSlotBIAS_DSADC_VCM	: natural := 13;	-- offset = 52 bytes
	constant RegSlotBIAS_REV_POT	: natural := 14;	-- offset = 56 bytes
	constant RegSlotBIAS_TC_DSADC	: natural := 15;	-- offset = 60 bytes
	constant RegSlotBIAS_LC_DSADC	: natural := 16;	-- offset = 64 bytes
	constant RegSlotBIAS_RIN_DSADC	: natural := 17;	-- offset = 68 bytes
	constant RegSlotBIAS_RFB_DSADC	: natural := 18;	-- offset = 72 bytes

	-- I2Cx
	constant RegSlotI2CxCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotI2CxFCR			: natural := 01;	-- offset = 4 bytes
	constant RegSlotI2CxSR			: natural := 02;	-- offset = 8 bytes
	constant RegSlotI2CxMTX			: natural := 03;	-- offset = 12 bytes
	constant RegSlotI2CxMRX			: natural := 04;	-- offset = 16 bytes
	constant RegSlotI2CxSTX			: natural := 05;	-- offset = 20 bytes
	constant RegSlotI2CxSRX			: natural := 06;	-- offset = 24 bytes
	constant RegSlotI2CxAR			: natural := 07;	-- offset = 28 bytes
	constant RegSlotI2CxAMR			: natural := 08;	-- offset = 32 bytes



	---------- GPIO Pin Numbers ----------
	-- GPIO0
	constant PinNumGPIO0CS_FLASH	: natural := 00;	-- P0.0
	constant PinNumGPIO0MISO0		: natural := 01;	-- P0.1
	constant PinNumGPIO0MOSI0		: natural := 02;	-- P0.2
	constant PinNumGPIO0SCK0		: natural := 03;	-- P0.3
	constant PinNumGPIO0LFXT		: natural := 04;	-- P0.4
	constant PinNumGPIO0HFXT		: natural := 05;	-- P0.5
	constant PinNumGPIO0TRAP		: natural := 06;	-- P0.6

	-- GPIO1
	constant PinNumGPIO1CS1			: natural := 00;	-- P1.0
	constant PinNumGPIO1MISO1		: natural := 01;	-- P1.1
	constant PinNumGPIO1MOSI1		: natural := 02;	-- P1.2
	constant PinNumGPIO1SCK1		: natural := 03;	-- P1.3
	constant PinNumGPIO1TX0			: natural := 04;	-- P1.4
	constant PinNumGPIO1RX0			: natural := 05;	-- P1.5
	constant PinNumGPIO1TX1			: natural := 06;	-- P1.6
	constant PinNumGPIO1RX1			: natural := 07;	-- P1.7

	-- GPIO2
	constant PinNumGPIO2T0CMP0		: natural := 00;	-- P2.0
	constant PinNumGPIO2T0CMP1		: natural := 01;	-- P2.1
	constant PinNumGPIO2T0CAP0		: natural := 02;	-- P2.2
	constant PinNumGPIO2T0CAP1		: natural := 03;	-- P2.3
	constant PinNumGPIO2T1CMP0		: natural := 04;	-- P2.4
	constant PinNumGPIO2T1CMP1		: natural := 05;	-- P2.5
	constant PinNumGPIO2T1CAP0		: natural := 06;	-- P2.6
	constant PinNumGPIO2T1CAP1		: natural := 07;	-- P2.7

	-- GPIO3
	constant PinNumGPIO3SDA0		: natural := 00;	-- P3.0
	constant PinNumGPIO3SCL0		: natural := 01;	-- P3.1
	constant PinNumGPIO3SDA1		: natural := 02;	-- P3.2
	constant PinNumGPIO3SCL1		: natural := 03;	-- P3.3
	constant PinNumGPIO3DTP0		: natural := 04;	-- P3.4
	constant PinNumGPIO3DTP1		: natural := 05;	-- P3.5
	constant PinNumGPIO3DTP2		: natural := 06;	-- P3.6
	constant PinNumGPIO3DTP3		: natural := 07;	-- P3.7



	---------- GPIO Register Reset Values ----------
	-- GPIO0
	constant RstValP0OUT	: slv(31 downto 0) := X"00000001";
	constant RstValP0DIR	: slv(31 downto 0) := X"00000001";
	constant RstValP0SEL	: slv(31 downto 0) := X"0000007E";
	constant RstValP0REN	: slv(31 downto 0) := X"00000080";

	-- GPIO1
	constant RstValP1OUT	: slv(31 downto 0) := X"00000000";
	constant RstValP1DIR	: slv(31 downto 0) := X"00000000";
	constant RstValP1SEL	: slv(31 downto 0) := X"00000030";
	constant RstValP1REN	: slv(31 downto 0) := X"00000000";

	-- GPIO2
	constant RstValP2OUT	: slv(31 downto 0) := X"00000000";
	constant RstValP2DIR	: slv(31 downto 0) := X"00000000";
	constant RstValP2SEL	: slv(31 downto 0) := X"00000000";
	constant RstValP2REN	: slv(31 downto 0) := X"00000000";

	-- GPIO3
	constant RstValP3OUT	: slv(31 downto 0) := X"00000000";
	constant RstValP3DIR	: slv(31 downto 0) := X"00000000";
	constant RstValP3SEL	: slv(31 downto 0) := X"00000000";
	constant RstValP3REN	: slv(31 downto 0) := X"00000000";



	---------- Interrupt Vector Bit Numbers (Priorities) ----------
	constant IrqBitSYSTEM	: natural := 00;	-- IVT address = 0x8000
	constant IrqBitGPIO0	: natural := 01;	-- IVT address = 0x8004
	constant IrqBitSPI0		: natural := 09;	-- IVT address = 0x8024
	constant IrqBitSPI1		: natural := 11;	-- IVT address = 0x802C
	constant IrqBitUART0	: natural := 13;	-- IVT address = 0x8034
	constant IrqBitTIMER0	: natural := 16;	-- IVT address = 0x8040
	constant IrqBitTIMER1	: natural := 22;	-- IVT address = 0x8058
	constant IrqBitGPIO1	: natural := 28;	-- IVT address = 0x8070



	---------- picorv32 CPU Configuration ----------
	constant picorv32_ENABLE_COUNTERS					: sl				:= '0';
	constant picorv32_ENABLE_COUNTERS64					: sl				:= '0';
	constant picorv32_ENABLE_REGS_16_31					: sl				:= '1';
	constant picorv32_ENABLE_REGS_DUALPORT				: sl				:= '1';
	constant picorv32_LATCHED_MEM_RDATA					: sl				:= '0';
	constant picorv32_TWO_STAGE_SHIFT					: sl				:= '0';
	constant picorv32_BARREL_SHIFTER					: sl				:= '0';
	constant picorv32_TWO_CYCLE_COMPARE					: sl				:= '0';
	constant picorv32_TWO_CYCLE_ALU						: sl				:= '0';
	constant picorv32_COMPRESSED_ISA					: sl				:= '1';
	constant picorv32_CATCH_MISALIGN					: sl				:= '1';
	constant picorv32_CATCH_ILLINSN						: sl				:= '1';
	constant picorv32_ENABLE_PCPI						: sl				:= '0';
	constant picorv32_ENABLE_MUL						: sl				:= '1';
	constant picorv32_ENABLE_FAST_MUL					: sl				:= '1';
	constant picorv32_ENABLE_DIV						: sl				:= '1';
	constant picorv32_ENABLE_IRQ						: sl				:= '1';
	constant picorv32_ENABLE_IRQ_FAST_CONTEXT_SWITCHING	: sl				:= '0';
	constant picorv32_ENABLE_IRQ_QREGS					: sl				:= '0';
	constant picorv32_ENABLE_IRQ_TIMER					: sl				:= '0';
	constant picorv32_ENABLE_TRACE						: sl				:= '0';
	constant picorv32_REGS_INIT_ZERO					: sl				:= '0';
	constant picorv32_MASKED_IRQ						: slv(31 downto 0)	:= X"00000000";
	constant picorv32_LATCHED_IRQ						: slv(31 downto 0)	:= X"00000000";
	constant picorv32_PROGADDR_RESET					: slv(31 downto 0)	:= X"00000000";
	constant picorv32_PROGADDR_IRQ						: slv(31 downto 0)	:= X"00009000";
	constant picorv32_PROGADDR_IVT						: slv(31 downto 0)	:= X"00008000";
	constant picorv32_STACKADDR							: slv(31 downto 0)	:= X"FFFFFFFF";



	---------- Bit Field Defines ----------
	------ GPIOx
	-- PxIN
	constant PxIN_MSB				: natural := 31;
	constant PxIN_LSB				: natural := 00;

	-- PxOUT
	constant PxOUT_MSB				: natural := 31;
	constant PxOUT_LSB				: natural := 00;

	-- PxOUTS
	constant PxOUTS_MSB				: natural := 31;
	constant PxOUTS_LSB				: natural := 00;

	-- PxOUTC
	constant PxOUTC_MSB				: natural := 31;
	constant PxOUTC_LSB				: natural := 00;

	-- PxOUTT
	constant PxOUTT_MSB				: natural := 31;
	constant PxOUTT_LSB				: natural := 00;

	-- PxDIR
	constant PxDIR_MSB				: natural := 31;
	constant PxDIR_LSB				: natural := 00;

	-- PxREN
	constant PxREN_MSB				: natural := 31;
	constant PxREN_LSB				: natural := 00;

	-- PxSEL
	constant PxSEL_MSB				: natural := 31;
	constant PxSEL_LSB				: natural := 00;

	-- PxIF
	constant PxIF_MSB				: natural := 31;
	constant PxIF_LSB				: natural := 00;

	-- PxIES
	constant PxIES_MSB				: natural := 31;
	constant PxIES_LSB				: natural := 00;

	-- PxIE
	constant PxIE_MSB				: natural := 31;
	constant PxIE_LSB				: natural := 00;


	------ SPIx
	-- SPIxCR
	constant SPIFEN_LSB				: natural := 19;
	constant SPISM_LSB				: natural := 18;
	constant SPITXSB_LSB			: natural := 17;
	constant SPIRXSB_LSB			: natural := 16;
	constant SPIBR_MSB				: natural := 15;
	constant SPIBR_LSB				: natural := 08;
	constant SPIEN_LSB				: natural := 07;
	constant SPIMSB_LSB				: natural := 06;
	constant SPITCIE_LSB			: natural := 05;
	constant SPITEIE_LSB			: natural := 04;
	constant SPIDL_MSB				: natural := 03;
	constant SPIDL_LSB				: natural := 02;
	constant SPICPOL_LSB			: natural := 01;
	constant SPICPHA_LSB			: natural := 00;

	-- SPIxSR
	constant SPIBUSY_LSB			: natural := 02;
	constant SPITCIF_LSB			: natural := 01;
	constant SPITEIF_LSB			: natural := 00;

	-- SPIxTX
	constant SPITX_MSB				: natural := 31;
	constant SPITX_LSB				: natural := 00;

	-- SPIxRX
	constant SPIRX_MSB				: natural := 31;
	constant SPIRX_LSB				: natural := 00;

	-- SPIxFOS
	constant SPIFOS_MSB				: natural := 23;
	constant SPIFOS_LSB				: natural := 00;


	------ UARTx
	-- UARTxCR
	constant UEN_LSB				: natural := 05;
	constant UPEN_LSB				: natural := 04;
	constant PSEL_LSB				: natural := 03;
	constant CIE_LSB				: natural := 02;
	constant TEIE_LSB				: natural := 01;
	constant TCIE_LSB				: natural := 00;

	-- UARTxSR
	constant RXBF_LSB				: natural := 07;
	constant TXBF_LSB				: natural := 06;
	constant FEF_LSB				: natural := 05;
	constant PEF_LSB				: natural := 04;
	constant OVF_LSB				: natural := 03;
	constant RCIF_LSB				: natural := 02;
	constant TEIF_LSB				: natural := 01;
	constant TCIF_LSB				: natural := 00;

	-- UARTxBR
	constant BR_MSB					: natural := 11;
	constant BR_LSB					: natural := 00;

	-- UARTxRX
	constant RX_MSB					: natural := 07;
	constant RX_LSB					: natural := 00;

	-- UARTxTX
	constant TX_MSB					: natural := 07;
	constant TX_LSB					: natural := 00;


	------ TIMERx
	-- TIMxCR
	constant DIV_MSB				: natural := 19;
	constant DIV_LSB				: natural := 16;
	constant CMP1IH_LSB				: natural := 15;
	constant CMP0IH_LSB				: natural := 14;
	constant CAP1FE_LSB				: natural := 13;
	constant CAP0FE_LSB				: natural := 12;
	constant CAP1EN_LSB				: natural := 11;
	constant CAP0EN_LSB				: natural := 10;
	constant SSEL_MSB				: natural := 09;
	constant SSEL_LSB				: natural := 08;
	constant CMP2RST_LSB			: natural := 07;
	constant TEN_LSB				: natural := 06;
	constant CAP1IE_LSB				: natural := 05;
	constant CAP0IE_LSB				: natural := 04;
	constant OVIE_LSB				: natural := 03;
	constant CMP2IE_LSB				: natural := 02;
	constant CMP1IE_LSB				: natural := 01;
	constant CMP0IE_LSB				: natural := 00;

	-- TIMxSR
	constant CMP1OUT_LSB			: natural := 07;
	constant CMP0OUT_LSB			: natural := 06;
	constant CAP1IF_LSB				: natural := 05;
	constant CAP0IF_LSB				: natural := 04;
	constant OVIF_LSB				: natural := 03;
	constant CMP2IF_LSB				: natural := 02;
	constant CMP1IF_LSB				: natural := 01;
	constant CMP0IF_LSB				: natural := 00;

	-- TIMxVAL
	constant VAL_MSB				: natural := 31;
	constant VAL_LSB				: natural := 00;

	-- TIMxCMP0
	constant CMP0_MSB				: natural := 31;
	constant CMP0_LSB				: natural := 00;

	-- TIMxCMP1
	constant CMP1_MSB				: natural := 31;
	constant CMP1_LSB				: natural := 00;

	-- TIMxCMP2
	constant CMP2_MSB				: natural := 31;
	constant CMP2_LSB				: natural := 00;

	-- TIMxCAP0
	constant CAP0_MSB				: natural := 31;
	constant CAP0_LSB				: natural := 00;

	-- TIMxCAP1
	constant CAP1_MSB				: natural := 31;
	constant CAP1_LSB				: natural := 00;


	------ SYSTEM
	-- SYSCLKCR
	constant DCO1ON_LSB				: natural := 08;
	constant DCO0ON_LSB				: natural := 07;
	constant HFXTOFF_LSB			: natural := 06;
	constant LFXTOFF_LSB			: natural := 05;
	constant SMCLKOFF_LSB			: natural := 04;
	constant SMCLKSEL_MSB			: natural := 03;
	constant SMCLKSEL_LSB			: natural := 02;
	constant MCLKSEL_MSB			: natural := 01;
	constant MCLKSEL_LSB			: natural := 00;

	-- CLKDIVCR
	constant SYSSMCLKDIV_MSB		: natural := 05;
	constant SYSSMCLKDIV_LSB		: natural := 03;
	constant SYSMCLKDIV_MSB			: natural := 02;
	constant SYSMCLKDIV_LSB			: natural := 00;

	-- BLOCKPWR
	constant SYSRAM1OFF_LSB			: natural := 02;
	constant SYSRAM0OFF_LSB			: natural := 01;
	constant SYSROMOFF_LSB			: natural := 00;

	-- CRCDATA
	constant SYSCRCDATA_MSB			: natural := 07;
	constant SYSCRCDATA_LSB			: natural := 00;

	-- CRCSTATE
	constant SYSCRCSTATE_MSB		: natural := 15;
	constant SYSCRCSTATE_LSB		: natural := 00;

	-- IRQENL
	constant SYSIRQENL_MSB			: natural := 31;
	constant SYSIRQENL_LSB			: natural := 00;

	-- IRQENM
	constant SYSIRQENM_MSB			: natural := 31;
	constant SYSIRQENM_LSB			: natural := 00;

	-- IRQENU
	constant SYSIRQENU_MSB			: natural := 31;
	constant SYSIRQENU_LSB			: natural := 00;

	-- IRQPRIL
	constant SYSIRQPRIL_MSB			: natural := 31;
	constant SYSIRQPRIL_LSB			: natural := 00;

	-- IRQPRIM
	constant SYSIRQPRIM_MSB			: natural := 31;
	constant SYSIRQPRIM_LSB			: natural := 00;

	-- IRQPRIU
	constant SYSIRQPRIU_MSB			: natural := 31;
	constant SYSIRQPRIU_LSB			: natural := 00;

	-- IRQCR
	constant SYSIRQRECEN_LSB		: natural := 01;
	constant SYSIRQGEN_LSB			: natural := 00;

	-- WDTCR
	constant SYSWDTEN_LSB			: natural := 07;
	constant SYSWDTCDIV_MSB			: natural := 05;
	constant SYSWDTCDIV_LSB			: natural := 02;
	constant SYSWDTIE_LSB			: natural := 01;
	constant SYSWDTHWRST_LSB		: natural := 00;

	-- WDTSR
	constant SYSWDTIF_LSB			: natural := 01;
	constant SYSWDTRF_LSB			: natural := 00;

	-- WDTPASS
	constant SYSWDTPASS_MSB			: natural := 31;
	constant SYSWDTPASS_LSB			: natural := 00;

	-- WDTVAL
	constant SYSWDTVAL_MSB			: natural := 23;
	constant SYSWDTVAL_LSB			: natural := 00;

	-- DCO0BIAS
	constant SYSDCO0BIAS_MSB		: natural := 11;
	constant SYSDCO0BIAS_LSB		: natural := 00;

	-- DCO1BIAS
	constant SYSDCO1BIAS_MSB		: natural := 11;
	constant SYSDCO1BIAS_LSB		: natural := 00;


	------ NPU
	-- NPUCR
	constant NPUBEN_LSB				: natural := 18;
	constant NPUAEN_LSB				: natural := 17;
	constant NPUTHINK_LSB			: natural := 16;
	constant NPUNI_MSB				: natural := 15;
	constant NPUNI_LSB				: natural := 08;
	constant NPUNN_MSB				: natural := 07;
	constant NPUNN_LSB				: natural := 00;

	-- NPUIVSAR
	constant NPUIVSAR_MSB			: natural := 13;
	constant NPUIVSAR_LSB			: natural := 02;

	-- NPUWVSAR
	constant NPUWVSAR_MSB			: natural := 13;
	constant NPUWVSAR_LSB			: natural := 02;

	-- NPUOVSAR
	constant NPUOVSAR_MSB			: natural := 13;
	constant NPUOVSAR_LSB			: natural := 02;


	------ SARADC
	-- SARADC_CR
	constant SARADCCONTMEAS_LSB		: natural := 08;
	constant SARADCDATAIE_LSB		: natural := 07;
	constant SARADCDEBUG_LSB		: natural := 06;
	constant SARADCEN_LSB			: natural := 05;
	constant SARADCSAMPLESTEP_MSB	: natural := 04;
	constant SARADCSAMPLESTEP_LSB	: natural := 01;
	constant SARADCRESET_LSB		: natural := 00;

	-- SARADC_CDIV
	constant SARADCCDIV_MSB			: natural := 07;
	constant SARADCCDIV_LSB			: natural := 00;

	-- SARADC_SR
	constant SARADCRDY_LSB			: natural := 03;
	constant SARADCOVF_LSB			: natural := 02;
	constant SARADCDATAVALID_LSB	: natural := 01;
	constant SARADCBUSY_LSB			: natural := 00;

	-- SARADC_DATA
	constant SARADCDATA_MSB			: natural := 09;
	constant SARADCDATA_LSB			: natural := 00;

	-- SARADC_TPR
	constant SARADCDTP1SEL_MSB		: natural := 07;
	constant SARADCDTP1SEL_LSB		: natural := 04;
	constant SARADCDTP0SEL_MSB		: natural := 03;
	constant SARADCDTP0SEL_LSB		: natural := 00;


	------ AFE
	-- AFE_CR
	constant AFE_RAMPNUM_MSB		: natural := 23;
	constant AFE_RAMPNUM_LSB		: natural := 12;
	constant AFE_ADCSEL_LSB			: natural := 11;
	constant AFE_ATPSEL_LSB			: natural := 10;
	constant AFE_ATPEN_LSB			: natural := 09;
	constant AFE_ADCEXTIN_LSB		: natural := 08;
	constant AFE_CONTMEAS_LSB		: natural := 04;
	constant AFE_DACEN_LSB			: natural := 03;
	constant AFE_DATARDYIE_LSB		: natural := 02;
	constant AFE_EN_LSB				: natural := 01;
	constant AFE_ADCEN_LSB			: natural := 00;

	-- AFE_TPR
	constant AFE_DTP3SEL_MSB		: natural := 19;
	constant AFE_DTP3SEL_LSB		: natural := 15;
	constant AFE_DTP2SEL_MSB		: natural := 14;
	constant AFE_DTP2SEL_LSB		: natural := 10;
	constant AFE_DTP1SEL_MSB		: natural := 09;
	constant AFE_DTP1SEL_LSB		: natural := 05;
	constant AFE_DTP0SEL_MSB		: natural := 04;
	constant AFE_DTP0SEL_LSB		: natural := 00;

	-- AFE_SR
	constant AFE_OVFIF_LSB			: natural := 02;
	constant AFE_DATARDYIF_LSB		: natural := 01;
	constant AFE_ADCACTIVE_LSB		: natural := 00;

	-- AFE_ADC_VAL
	constant AFE_ADCVAL_MSB			: natural := 11;
	constant AFE_ADCVAL_LSB			: natural := 00;

	-- BIAS_CR
	constant USEDAC_LSB				: natural := 04;
	constant BUFEN_LSB				: natural := 03;
	constant EN_LSB					: natural := 02;

	-- BIAS_ADJ
	constant ADJ_MSB				: natural := 05;
	constant ADJ_LSB				: natural := 00;

	-- BIAS_DBP
	constant DBP_MSB				: natural := 13;
	constant DBP_LSB				: natural := 00;

	-- BIAS_DBPC
	constant DBPC_MSB				: natural := 13;
	constant DBPC_LSB				: natural := 00;

	-- BIAS_DBNC
	constant DBNC_MSB				: natural := 13;
	constant DBNC_LSB				: natural := 00;

	-- BIAS_DBN
	constant DBN_MSB				: natural := 13;
	constant DBN_LSB				: natural := 00;

	-- BIAS_TC_POT
	constant TC_POT_MSB				: natural := 05;
	constant TC_POT_LSB				: natural := 00;

	-- BIAS_LC_POT
	constant LC_POT_MSB				: natural := 05;
	constant LC_POT_LSB				: natural := 00;

	-- BIAS_TIA_G_POT
	constant TIA_G_POT_MSB			: natural := 16;
	constant TIA_G_POT_LSB			: natural := 00;

	-- BIAS_DSADC_VCM
	constant DSADC_VCM_MSB			: natural := 13;
	constant DSADC_VCM_LSB			: natural := 00;

	-- BIAS_REV_POT
	constant REV_POT_MSB			: natural := 13;
	constant REV_POT_LSB			: natural := 00;

	-- BIAS_TC_DSADC
	constant TC_DSADC_MSB			: natural := 05;
	constant TC_DSADC_LSB			: natural := 00;

	-- BIAS_LC_DSADC
	constant LC_DSADC_MSB			: natural := 05;
	constant LC_DSADC_LSB			: natural := 00;

	-- BIAS_RIN_DSADC
	constant RIN_DSADC_MSB			: natural := 05;
	constant RIN_DSADC_LSB			: natural := 00;

	-- BIAS_RFB_DSADC
	constant RFB_DSADC_MSB			: natural := 05;
	constant RFB_DSADC_LSB			: natural := 00;


	------ I2Cx
	-- I2CxCR
	constant I2CMEN_LSB				: natural := 21;
	constant I2CSEN_LSB				: natural := 20;
	constant I2CSN_LSB				: natural := 19;
	constant I2CSCS_LSB				: natural := 18;
	constant I2CGCE_LSB				: natural := 17;
	constant I2CMDIV_MSB			: natural := 16;
	constant I2CMDIV_LSB			: natural := 13;
	constant I2CSAIE_LSB			: natural := 12;
	constant I2CSTXEIE_LSB			: natural := 11;
	constant I2CSOVFIE_LSB			: natural := 10;
	constant I2CSNRIE_LSB			: natural := 09;
	constant I2CSXCIE_LSB			: natural := 08;
	constant I2CMSTSIE_LSB			: natural := 07;
	constant I2CMSPSIE_LSB			: natural := 06;
	constant I2CMARBIE_LSB			: natural := 05;
	constant I2CMTXEIE_LSB			: natural := 04;
	constant I2CMNRIE_LSB			: natural := 03;
	constant I2CMXCIE_LSB			: natural := 02;
	constant I2CSTRIE_LSB			: natural := 01;
	constant I2CSPRIE_LSB			: natural := 00;

	-- I2CxFCR
	constant I2CSC_LSB				: natural := 03;
	constant I2CMST_LSB				: natural := 02;
	constant I2CMSP_LSB				: natural := 01;
	constant I2CMRB_LSB				: natural := 00;

	-- I2CxSR
	constant I2CBS_LSB				: natural := 15;
	constant I2CMCB_LSB				: natural := 14;
	constant I2CSTM_LSB				: natural := 13;
	constant I2CSA_LSB				: natural := 12;
	constant I2CSTXE_LSB			: natural := 11;
	constant I2CSOVF_LSB			: natural := 10;
	constant I2CSNR_LSB				: natural := 09;
	constant I2CSXC_LSB				: natural := 08;
	constant I2CMSTS_LSB			: natural := 07;
	constant I2CMSPS_LSB			: natural := 06;
	constant I2CMARB_LSB			: natural := 05;
	constant I2CMTXE_LSB			: natural := 04;
	constant I2CMNR_LSB				: natural := 03;
	constant I2CMXC_LSB				: natural := 02;
	constant I2CSTR_LSB				: natural := 01;
	constant I2CSPR_LSB				: natural := 00;

	-- I2CxMTX
	constant I2CxMTX_MSB			: natural := 07;
	constant I2CxMTX_LSB			: natural := 00;

	-- I2CxMRX
	constant I2CxMRX_MSB			: natural := 07;
	constant I2CxMRX_LSB			: natural := 00;

	-- I2CxSTX
	constant I2CxSTX_MSB			: natural := 07;
	constant I2CxSTX_LSB			: natural := 00;

	-- I2CxSRX
	constant I2CxSRX_MSB			: natural := 07;
	constant I2CxSRX_LSB			: natural := 00;

	-- I2CxAR
	constant I2CxAR_MSB				: natural := 06;
	constant I2CxAR_LSB				: natural := 00;

	-- I2CxAMR
	constant I2CxAMR_MSB			: natural := 06;
	constant I2CxAMR_LSB			: natural := 00;



end MemoryMap;

package body MemoryMap is
end MemoryMap;
