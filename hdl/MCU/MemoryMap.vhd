-- MemoryMap.vhd
-- Memory map VHDL package
-- Defines the memory map of the MCU, including which RAM and peripheral slots are activated, as well as which slot each peripheral is allocated to, and the slot each register within each peripheral is allocated to
-- Generated on 2026/02/14 at 17:36:07 with the MemoryMap.py memory map generator
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
	concoant UsePeriph05			: boolean := true;	-- base address = 0x4500
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
	constant PeriphSlotNN0			: natural := 10;	-- base address = 0x4A00
	constant PeriphSlotSARADC0		: natural := 11;	-- base address = 0x4B00
	constant PeriphSlotAFE0			: natural := 12;	-- base address = 0x4C00
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
	constant RegSlotPxIFG			: natural := 06;	-- offset = 24 bytes
	constant RegSlotPxIES			: natural := 07;	-- offset = 28 bytes
	constant RegSlotPxIE			: natural := 08;	-- offset = 32 bytes
	constant RegSlotPxSEL			: natural := 09;	-- offset = 36 bytes
	constant RegSlotPxREN			: natural := 10;	-- offset = 40 bytes

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
	constant RegSlotMEMPWRCR		: natural := 02;	-- offset = 8 bytes
	constant RegSlotCRCDATA			: natural := 03;	-- offset = 12 bytes
	constant RegSlotCRCSTATE		: natural := 04;	-- offset = 16 bytes
	constant RegSlotIRQEN			: natural := 05;	-- offset = 20 bytes
	constant RegSlotIRQPRI			: natural := 06;	-- offset = 24 bytes
	constant RegSlotWDTPASS			: natural := 07;	-- offset = 28 bytes
	constant RegSlotWDTCR			: natural := 08;	-- offset = 32 bytes
	constant RegSlotWDTSR			: natural := 09;	-- offset = 36 bytes
	constant RegSlotWDTVAL			: natural := 10;	-- offset = 40 bytes
	constant RegSlotDCO0FREQ		: natural := 11;	-- offset = 44 bytes
	constant RegSlotDCO1FREQ		: natural := 12;	-- offset = 48 bytes
	constant RegSlotTPMR			: natural := 13;	-- offset = 52 bytes
	constant RegSlotBIASCR			: natural := 14;	-- offset = 56 bytes
	constant RegSlotBIASDBP			: natural := 15;	-- offset = 60 bytes
	constant RegSlotBIASDBPC		: natural := 16;	-- offset = 64 bytes
	constant RegSlotBIASDBNC		: natural := 17;	-- offset = 68 bytes
	constant RegSlotBIASDBN			: natural := 18;	-- offset = 72 bytes

	-- NNx
	constant RegSlotNNxCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotNNxIVA			: natural := 01;	-- offset = 4 bytes
	constant RegSlotNNxOVA			: natural := 02;	-- offset = 8 bytes
	constant RegSlotNNxWMA			: natural := 03;	-- offset = 12 bytes
	constant RegSlotNNxLSI			: natural := 04;	-- offset = 16 bytes
	constant RegSlotNNxLSO			: natural := 05;	-- offset = 20 bytes

	-- SARADCx
	constant RegSlotSARADCxCR		: natural := 00;	-- offset = 0 bytes
	constant RegSlotSARADCxCDIV		: natural := 01;	-- offset = 4 bytes
	constant RegSlotSARADCxSR		: natural := 02;	-- offset = 8 bytes
	constant RegSlotSARADCxDATA		: natural := 03;	-- offset = 12 bytes
	constant RegSlotSARADCxTPR		: natural := 04;	-- offset = 16 bytes

	-- AFEx
	constant RegSlotAFExCR0			: natural := 00;	-- offset = 0 bytes
	constant RegSlotAFExCR1			: natural := 01;	-- offset = 4 bytes
	constant RegSlotAFExCFB			: natural := 02;	-- offset = 8 bytes
	constant RegSlotAFExRFB			: natural := 03;	-- offset = 12 bytes
	constant RegSlotAFExTHR			: natural := 04;	-- offset = 16 bytes
	constant RegSlotAFExTPR			: natural := 05;	-- offset = 20 bytes
	constant RegSlotAFExSPT			: natural := 06;	-- offset = 24 bytes
	constant RegSlotAFExPIT			: natural := 07;	-- offset = 28 bytes
	constant RegSlotAFExEIT			: natural := 08;	-- offset = 32 bytes
	constant RegSlotAFExLIT			: natural := 09;	-- offset = 36 bytes
	constant RegSlotAFExRJT			: natural := 10;	-- offset = 40 bytes
	constant RegSlotAFExRST			: natural := 11;	-- offset = 44 bytes
	constant RegSlotAFExAOFST		: natural := 12;	-- offset = 48 bytes
	constant RegSlotAFExBLLT		: natural := 13;	-- offset = 52 bytes
	constant RegSlotAFExCSAREF		: natural := 14;	-- offset = 56 bytes
	constant RegSlotAFExCSABP		: natural := 15;	-- offset = 60 bytes
	constant RegSlotAFExCSABPC		: natural := 16;	-- offset = 64 bytes
	constant RegSlotAFExCSABNC		: natural := 17;	-- offset = 68 bytes
	constant RegSlotAFExCSABN		: natural := 18;	-- offset = 72 bytes
	constant RegSlotAFExCMSHR		: natural := 19;	-- offset = 76 bytes
	constant RegSlotAFExCLPF		: natural := 20;	-- offset = 80 bytes
	constant RegSlotAFExSR			: natural := 21;	-- offset = 84 bytes
	constant RegSlotAFExADCVAL		: natural := 22;	-- offset = 88 bytes
	constant RegSlotAFExVPC			: natural := 23;	-- offset = 92 bytes
	constant RegSlotAFExTPC			: natural := 24;	-- offset = 96 bytes

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
	constant picorv32_TWO_STAGE_SHIFT					: sl				:= '1';
	constant picorv32_BARREL_SHIFTER					: sl				:= '1';
	constant picorv32_TWO_CYCLE_COMPARE					: sl				:= '0';
	constant picorv32_TWO_CYCLE_ALU						: sl				:= '0';
	constant picorv32_COMPRESSED_ISA					: sl				:= '0';
	constant picorv32_CATCH_MISALIGN					: sl				:= '1';
	constant picorv32_CATCH_ILLINSN						: sl				:= '1';
	constant picorv32_ENABLE_PCPI						: sl				:= '0';
	constant picorv32_ENABLE_MUL						: sl				:= '1';
	constant picorv32_ENABLE_FAST_MUL					: sl				:= '1';
	constant picorv32_ENABLE_DIV						: sl				:= '1';
	constant picorv32_ENABLE_IRQ						: sl				:= '1';
	constant picorv32_ENABLE_IRQ_FAST_CONTEXT_SWITCHING	: sl				:= '1';
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

	-- PxIFG
	constant PxIFG_MSB				: natural := 31;
	constant PxIFG_LSB				: natural := 00;

	-- PxIES
	constant PxIES_MSB				: natural := 31;
	constant PxIES_LSB				: natural := 00;

	-- PxIE
	constant PxIE_MSB				: natural := 31;
	constant PxIE_LSB				: natural := 00;

	-- PxSEL
	constant PxSEL_MSB				: natural := 31;
	constant PxSEL_LSB				: natural := 00;

	-- PxREN
	constant PxREN_MSB				: natural := 31;
	constant PxREN_LSB				: natural := 00;


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
	constant SPIxTX_MSB				: natural := 31;
	constant SPIxTX_LSB				: natural := 00;

	-- SPIxRX
	constant SPIxRX_MSB				: natural := 31;
	constant SPIxRX_LSB				: natural := 00;

	-- SPIxFOS
	constant SPIxFOS_MSB			: natural := 23;
	constant SPIxFOS_LSB			: natural := 00;


	------ UARTx
	-- UARTxCR
	constant UEN_LSB				: natural := 05;
	constant UPEN_LSB				: natural := 04;
	constant UPODD_LSB				: natural := 03;
	constant URCIE_LSB				: natural := 02;
	constant UTEIE_LSB				: natural := 01;
	constant UTCIE_LSB				: natural := 00;

	-- UARTxSR
	constant URBF_LSB				: natural := 07;
	constant UTBF_LSB				: natural := 06;
	constant UFEF_LSB				: natural := 05;
	constant UPEF_LSB				: natural := 04;
	constant UOVF_LSB				: natural := 03;
	constant URCIF_LSB				: natural := 02;
	constant UTEIF_LSB				: natural := 01;
	constant UTCIF_LSB				: natural := 00;

	-- UARTxBR
	constant UBR_MSB				: natural := 11;
	constant UBR_LSB				: natural := 00;

	-- UARTxRX
	constant UARTxRX_MSB			: natural := 07;
	constant UARTxRX_LSB			: natural := 00;

	-- UARTxTX
	constant UARTxTX_MSB			: natural := 07;
	constant UARTxTX_LSB			: natural := 00;


	------ TIMERx
	-- TIMxCR
	constant TIMDIV_MSB				: natural := 19;
	constant TIMDIV_LSB				: natural := 16;
	constant TIMCMP1IH_LSB			: natural := 15;
	constant TIMCMP0IH_LSB			: natural := 14;
	constant TIMCAP1FE_LSB			: natural := 13;
	constant TIMCAP0FE_LSB			: natural := 12;
	constant TIMCAP1EN_LSB			: natural := 11;
	constant TIMCAP0EN_LSB			: natural := 10;
	constant TIMSSEL_MSB			: natural := 09;
	constant TIMSSEL_LSB			: natural := 08;
	constant TIMCMP2RST_LSB			: natural := 07;
	constant TIMEN_LSB				: natural := 06;
	constant TIMCAP1IE_LSB			: natural := 05;
	constant TIMCAP0IE_LSB			: natural := 04;
	constant TIMOVIE_LSB			: natural := 03;
	constant TIMCMP2IE_LSB			: natural := 02;
	constant TIMCMP1IE_LSB			: natural := 01;
	constant TIMCMP0IE_LSB			: natural := 00;

	-- TIMxSR
	constant TCMP1_LSB				: natural := 07;
	constant TCMP0_LSB				: natural := 06;
	constant TIMCAP1IF_LSB			: natural := 05;
	constant TIMCAP0IF_LSB			: natural := 04;
	constant TIMOVIF_LSB			: natural := 03;
	constant TIMCMP2IF_LSB			: natural := 02;
	constant TIMCMP1IF_LSB			: natural := 01;
	constant TIMCMP0IF_LSB			: natural := 00;

	-- TIMxVAL
	constant TIMxVAL_MSB			: natural := 31;
	constant TIMxVAL_LSB			: natural := 00;

	-- TIMxCMP0
	constant TIMxCMP0_MSB			: natural := 31;
	constant TIMxCMP0_LSB			: natural := 00;

	-- TIMxCMP1
	constant TIMxCMP1_MSB			: natural := 31;
	constant TIMxCMP1_LSB			: natural := 00;

	-- TIMxCMP2
	constant TIMxCMP2_MSB			: natural := 31;
	constant TIMxCMP2_LSB			: natural := 00;

	-- TIMxCAP0
	constant TIMxCAP0_MSB			: natural := 31;
	constant TIMxCAP0_LSB			: natural := 00;

	-- TIMxCAP1
	constant TIMxCAP1_MSB			: natural := 31;
	constant TIMxCAP1_LSB			: natural := 00;


	------ SYSTEM
	-- SYSCLKCR
	constant DCO1OFF_LSB			: natural := 11;
	constant DCO0OFF_LSB			: natural := 10;
	constant HFXTOFF_LSB			: natural := 09;
	constant LFXTOFF_LSB			: natural := 08;
	constant SMCLKOFF_LSB			: natural := 06;
	constant SMCLKSEL_MSB			: natural := 04;
	constant SMCLKSEL_LSB			: natural := 03;
	constant MCLKSEL_MSB			: natural := 01;
	constant MCLKSEL_LSB			: natural := 00;

	-- CLKDIVCR
	constant SMCLKDIV_MSB			: natural := 05;
	constant SMCLKDIV_LSB			: natural := 03;
	constant MCLKDIV_MSB			: natural := 02;
	constant MCLKDIV_LSB			: natural := 00;

	-- MEMPWRCR
	constant SRAM15OFF_LSB			: natural := 15;
	constant SRAM14OFF_LSB			: natural := 14;
	constant SRAM13OFF_LSB			: natural := 13;
	constant SRAM12OFF_LSB			: natural := 12;
	constant SRAM11OFF_LSB			: natural := 11;
	constant SRAM10OFF_LSB			: natural := 10;
	constant SRAM09OFF_LSB			: natural := 09;
	constant SRAM08OFF_LSB			: natural := 08;
	constant SRAM07OFF_LSB			: natural := 07;
	constant SRAM06OFF_LSB			: natural := 06;
	constant SRAM05OFF_LSB			: natural := 05;
	constant SRAM04OFF_LSB			: natural := 04;
	constant SRAM03OFF_LSB			: natural := 03;
	constant SRAM02OFF_LSB			: natural := 02;
	constant ROMOFF_LSB				: natural := 00;

	-- CRCDATA
	constant CRCDATA_MSB			: natural := 07;
	constant CRCDATA_LSB			: natural := 00;

	-- CRCSTATE
	constant CRCSTATE_MSB			: natural := 15;
	constant CRCSTATE_LSB			: natural := 00;

	-- IRQEN
	constant IRQEN_MSB				: natural := 31;
	constant IRQEN_LSB				: natural := 00;

	-- IRQPRI
	constant IRQPRI_MSB				: natural := 31;
	constant IRQPRI_LSB				: natural := 00;

	-- WDTPASS
	constant WDTPASS_MSB			: natural := 31;
	constant WDTPASS_LSB			: natural := 00;

	-- WDTCR
	constant HWRST_LSB				: natural := 06;
	constant WDTCDIV_MSB			: natural := 05;
	constant WDTCDIV_LSB			: natural := 02;
	constant WDTIE_LSB				: natural := 01;
	constant WDTREN_LSB				: natural := 00;

	-- WDTSR
	constant WDTIF_LSB				: natural := 01;
	constant WDTRF_LSB				: natural := 00;

	-- WDTVAL
	constant WDTVAL_MSB				: natural := 31;
	constant WDTVAL_LSB				: natural := 00;

	-- DCO0FREQ
	constant DCO0MFREQ_MSB			: natural := 11;
	constant DCO0MFREQ_LSB			: natural := 00;

	-- DCO1FREQ
	constant DCO1MFREQ_MSB			: natural := 11;
	constant DCO1MFREQ_LSB			: natural := 00;

	-- TPMR
	constant TPMR_MSB				: natural := 03;
	constant TPMR_LSB				: natural := 00;

	-- BIASCR
	constant EnBG_LSB				: natural := 10;
	constant UseExtBias_LSB			: natural := 09;
	constant UseBiasDac_LSB			: natural := 08;
	constant EnBiasBuf_LSB			: natural := 07;
	constant EnBiasGen_LSB			: natural := 06;
	constant BiasAdj_MSB			: natural := 05;
	constant BiasAdj_LSB			: natural := 00;

	-- BIASDBP
	constant BIASDBP_MSB			: natural := 13;
	constant BIASDBP_LSB			: natural := 00;

	-- BIASDBPC
	constant BIASDBPC_MSB			: natural := 13;
	constant BIASDBPC_LSB			: natural := 00;

	-- BIASDBNC
	constant BIASDBNC_MSB			: natural := 13;
	constant BIASDBNC_LSB			: natural := 00;

	-- BIASDBN
	constant BIASDBN_MSB			: natural := 13;
	constant BIASDBN_LSB			: natural := 00;


	------ NNx
	-- NNxCR
	constant NNCIE_LSB				: natural := 22;
	constant NNCIF_LSB				: natural := 21;
	constant NNLSIS_LSB				: natural := 20;
	constant NNCS_LSB				: natural := 19;
	constant NNBIAS_LSB				: natural := 18;
	constant NNAFS_LSB				: natural := 17;
	constant NNRUN_LSB				: natural := 16;
	constant NNO_MSB				: natural := 15;
	constant NNO_LSB				: natural := 08;
	constant NNI_MSB				: natural := 07;
	constant NNI_LSB				: natural := 00;

	-- NNxIVA
	constant NNIVA_MSB				: natural := 13;
	constant NNIVA_LSB				: natural := 02;

	-- NNxOVA
	constant NNOVA_MSB				: natural := 13;
	constant NNOVA_LSB				: natural := 02;

	-- NNxWMA
	constant NNWMA_MSB				: natural := 13;
	constant NNWMA_LSB				: natural := 02;

	-- NNxLSI
	constant NNxLSI_MSB				: natural := 31;
	constant NNxLSI_LSB				: natural := 00;

	-- NNxLSO
	constant NNxLSO_MSB				: natural := 15;
	constant NNxLSO_LSB				: natural := 00;


	------ SARADCx
	-- SARADCxCR
	constant SARADCCONTMEAS_LSB		: natural := 08;
	constant SARADCDATAIE_LSB		: natural := 07;
	constant SARADCDEBUG_LSB		: natural := 06;
	constant SARADCEN_LSB			: natural := 05;
	constant SARADCSAMPLESTEP_MSB	: natural := 04;
	constant SARADCSAMPLESTEP_LSB	: natural := 01;
	constant SARADCRESET_LSB		: natural := 00;

	-- SARADCxCDIV
	constant SARADCCDIV_MSB			: natural := 07;
	constant SARADCCDIV_LSB			: natural := 00;

	-- SARADCxSR
	constant SARADCRDY_LSB			: natural := 03;
	constant SARADCOVF_LSB			: natural := 02;
	constant SARADCDATAVALID_LSB	: natural := 01;
	constant SARADCBUSY_LSB			: natural := 00;

	-- SARADCxDATA
	constant SARADCDATA_MSB			: natural := 09;
	constant SARADCDATA_LSB			: natural := 00;

	-- SARADCxTPR
	constant SARADCDTP1SEL_MSB		: natural := 07;
	constant SARADCDTP1SEL_LSB		: natural := 04;
	constant SARADCDTP0SEL_MSB		: natural := 03;
	constant SARADCDTP0SEL_LSB		: natural := 00;


	------ AFEx
	-- AFExCR0
	constant AdcExtIn_LSB			: natural := 29;
	constant AdcMidSel_LSB			: natural := 28;
	constant AdcMuxTest_LSB			: natural := 27;
	constant BufCMMid_LSB			: natural := 26;
	constant CsaBiasSel_LSB			: natural := 25;
	constant CsaForceRst_LSB		: natural := 24;
	constant CsaForceUnRst_LSB		: natural := 23;
	constant CsaRstMode_LSB			: natural := 22;
	constant EnAfe_LSB				: natural := 21;
	constant EnCM_LSB				: natural := 20;
	constant EnCsa_LSB				: natural := 19;
	constant EnAdc_LSB				: natural := 18;
	constant EnThresh_LSB			: natural := 17;
	constant EnDma_LSB				: natural := 16;
	constant EnPURej_LSB			: natural := 15;
	constant EnPsd_LSB				: natural := 14;
	constant EnBLLT_LSB				: natural := 13;
	constant ForceThresh_LSB		: natural := 12;
	constant OpenInput_LSB			: natural := 11;
	constant PsdOrder_LSB			: natural := 10;
	constant PUPara_LSB				: natural := 09;
	constant RamOff_LSB				: natural := 08;
	constant RejectMode_LSB			: natural := 07;
	constant SHPwrMode_LSB			: natural := 06;
	constant ThreshSel_MSB			: natural := 05;
	constant ThreshSel_LSB			: natural := 04;
	constant PulseDoneWait_LSB		: natural := 03;
	constant PulseDoneIE_LSB		: natural := 02;
	constant AdcConvDoneIE_LSB		: natural := 01;
	constant PsdFullIE_LSB			: natural := 00;

	-- AFExCR1
	constant AdcClkDivN_MSB			: natural := 31;
	constant AdcClkDivN_LSB			: natural := 29;
	constant AdcClkDivM_MSB			: natural := 28;
	constant AdcClkDivM_LSB			: natural := 25;
	constant AdcCp_MSB				: natural := 24;
	constant AdcCp_LSB				: natural := 18;
	constant AdcSampT_MSB			: natural := 17;
	constant AdcSampT_LSB			: natural := 15;
	constant ClkSel_MSB				: natural := 14;
	constant ClkSel_LSB				: natural := 13;
	constant CMSHClkDiv_MSB			: natural := 12;
	constant CMSHClkDiv_LSB			: natural := 09;
	constant CsaCmAdj_MSB			: natural := 08;
	constant CsaCmAdj_LSB			: natural := 06;
	constant ISink_MSB				: natural := 05;
	constant ISink_LSB				: natural := 00;

	-- AFExCFB
	constant AFExCFB_MSB			: natural := 07;
	constant AFExCFB_LSB			: natural := 00;

	-- AFExRFB
	constant AFExRFB_MSB			: natural := 13;
	constant AFExRFB_LSB			: natural := 00;

	-- AFExTHR
	constant AFExTHR_MSB			: natural := 13;
	constant AFExTHR_LSB			: natural := 00;

	-- AFExTPR
	constant AfeAtp1BufEn_LSB		: natural := 29;
	constant AfeAtp1Sel_MSB			: natural := 28;
	constant AfeAtp1Sel_LSB			: natural := 25;
	constant AfeAtp0BufEn_LSB		: natural := 24;
	constant AfeAtp0Sel_MSB			: natural := 23;
	constant AfeAtp0Sel_LSB			: natural := 20;
	constant AfeDtp3Sel_MSB			: natural := 19;
	constant AfeDtp3Sel_LSB			: natural := 15;
	constant AfeDtp2Sel_MSB			: natural := 14;
	constant AfeDtp2Sel_LSB			: natural := 10;
	constant AfeDtp1Sel_MSB			: natural := 09;
	constant AfeDtp1Sel_LSB			: natural := 05;
	constant AfeDtp0Sel_MSB			: natural := 04;
	constant AfeDtp0Sel_LSB			: natural := 00;

	-- AFExSPT
	constant AFExSPT_MSB			: natural := 07;
	constant AFExSPT_LSB			: natural := 00;

	-- AFExPIT
	constant AFExPIT_MSB			: natural := 15;
	constant AFExPIT_LSB			: natural := 00;

	-- AFExEIT
	constant AFExEIT_MSB			: natural := 15;
	constant AFExEIT_LSB			: natural := 00;

	-- AFExLIT
	constant AFExLIT_MSB			: natural := 15;
	constant AFExLIT_LSB			: natural := 00;

	-- AFExRJT
	constant AFExRJT_MSB			: natural := 15;
	constant AFExRJT_LSB			: natural := 00;

	-- AFExRST
	constant AFExRST_MSB			: natural := 07;
	constant AFExRST_LSB			: natural := 00;

	-- AFExAOFST
	constant AFExAOFST_MSB			: natural := 13;
	constant AFExAOFST_LSB			: natural := 00;

	-- AFExBLLT
	constant AFExBLLT_MSB			: natural := 13;
	constant AFExBLLT_LSB			: natural := 00;

	-- AFExCSAREF
	constant AFExCSAREF_MSB			: natural := 13;
	constant AFExCSAREF_LSB			: natural := 00;

	-- AFExCSABP
	constant AFExCSABP_MSB			: natural := 13;
	constant AFExCSABP_LSB			: natural := 00;

	-- AFExCSABPC
	constant AFExCSABPC_MSB			: natural := 13;
	constant AFExCSABPC_LSB			: natural := 00;

	-- AFExCSABNC
	constant AFExCSABNC_MSB			: natural := 13;
	constant AFExCSABNC_LSB			: natural := 00;

	-- AFExCSABN
	constant AFExCSABN_MSB			: natural := 13;
	constant AFExCSABN_LSB			: natural := 00;

	-- AFExCMSHR
	constant AFExCMSHR_MSB			: natural := 13;
	constant AFExCMSHR_LSB			: natural := 00;

	-- AFExCLPF
	constant AFExCLPF_MSB			: natural := 05;
	constant AFExCLPF_LSB			: natural := 00;

	-- AFExSR
	constant DTP1VAL_LSB			: natural := 07;
	constant DTP0VAL_LSB			: natural := 06;
	constant AdcActive_LSB			: natural := 05;
	constant AdcDataReady_LSB		: natural := 04;
	constant DmaEnabled_LSB			: natural := 03;
	constant PulseDone_LSB			: natural := 02;
	constant AdcConvDone_LSB		: natural := 01;
	constant PsdFull_LSB			: natural := 00;

	-- AFExADCVAL
	constant AFExADCVAL_MSB			: natural := 09;
	constant AFExADCVAL_LSB			: natural := 00;

	-- AFExVPC
	constant AFExVPC_MSB			: natural := 31;
	constant AFExVPC_LSB			: natural := 00;

	-- AFExTPC
	constant AFExTPC_MSB			: natural := 31;
	constant AFExTPC_LSB			: natural := 00;


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
