-- MemoryMap.vhd
-- Memory map VHDL package
-- Defines the memory map of the MCU, including which RAM and peripheral slots are activated, as well as which slot each peripheral is allocated to, and the slot each register within each peripheral is allocated to
-- Generated on 2026/07/19 at 13:21:10 with the MemoryMap.py memory map generator
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
	constant RamSize				: natural := 16384;	-- 0x4000



	---------- Memory Slot Enables/Disables ----------
	-- Peripheral Slot Enables/Disables
	constant UsePeriph00			: boolean := false;	-- base address = 0x4000
	constant UsePeriph01			: boolean := false;	-- base address = 0x4100
	constant UsePeriph02			: boolean := false;	-- base address = 0x4200
	constant UsePeriph03			: boolean := false;	-- base address = 0x4300
	constant UsePeriph04			: boolean := false;	-- base address = 0x4400
	constant UsePeriph05			: boolean := false;	-- base address = 0x4500
	constant UsePeriph06			: boolean := false;	-- base address = 0x4600
	constant UsePeriph07			: boolean := false;	-- base address = 0x4700
	constant UsePeriph08			: boolean := false;	-- base address = 0x4800
	constant UsePeriph09			: boolean := false;	-- base address = 0x4900
	constant UsePeriph10			: boolean := false;	-- base address = 0x4A00
	constant UsePeriph11			: boolean := false;	-- base address = 0x4B00
	constant UsePeriph12			: boolean := false;	-- base address = 0x4C00
	constant UsePeriph13			: boolean := false;	-- base address = 0x4D00
	constant UsePeriph14			: boolean := false;	-- base address = 0x4E00
	constant UsePeriph15			: boolean := false;	-- base address = 0x4F00

	-- SRAM Slot Enables/Disables
	constant UseSRAM02				: boolean := true;	-- base address = 0x8000



	---------- Peripheral Memory Slot Assignments ----------
	--constant PeriphSlot			: natural := 00;	-- base address = 0x4000
	--constant PeriphSlot			: natural := 01;	-- base address = 0x4100
	--constant PeriphSlot			: natural := 02;	-- base address = 0x4200
	--constant PeriphSlot			: natural := 03;	-- base address = 0x4300
	--constant PeriphSlot			: natural := 04;	-- base address = 0x4400
	--constant PeriphSlot			: natural := 05;	-- base address = 0x4500
	--constant PeriphSlot			: natural := 06;	-- base address = 0x4600
	--constant PeriphSlot			: natural := 07;	-- base address = 0x4700
	--constant PeriphSlot			: natural := 08;	-- base address = 0x4800
	--constant PeriphSlot			: natural := 09;	-- base address = 0x4900
	--constant PeriphSlot			: natural := 10;	-- base address = 0x4A00
	--constant PeriphSlot			: natural := 11;	-- base address = 0x4B00
	--constant PeriphSlot			: natural := 12;	-- base address = 0x4C00
	--constant PeriphSlot			: natural := 13;	-- base address = 0x4D00
	--constant PeriphSlot			: natural := 14;	-- base address = 0x4E00
	--constant PeriphSlot			: natural := 15;	-- base address = 0x4F00



	---------- Peripheral Register Address Offsets ----------
	-- GPIOx
	constant RegSlotPxIN			: natural := 00;	-- offset = 0 bytes
	constant RegSlotPxOUT			: natural := 01;	-- offset = 4 bytes
	constant RegSlotPxOUTS			: natural := 02;	-- offset = 8 bytes
	constant RegSlotPxOUTC			: natural := 03;	-- offset = 12 bytes
	constant RegSlotPxOUTT			: natural := 04;	-- offset = 16 bytes
	constant RegSlotPxDIR			: natural := 05;	-- offset = 20 bytes
	constant RegSlotPxIF			: natural := 06;	-- offset = 24 bytes
	constant RegSlotPxIES			: natural := 07;	-- offset = 28 bytes
	constant RegSlotPxIE			: natural := 08;	-- offset = 32 bytes
	constant RegSlotPxSEL			: natural := 09;	-- offset = 36 bytes
	constant RegSlotPxREN			: natural := 10;	-- offset = 40 bytes
	constant RegSlotPxAFS			: natural := 11;	-- offset = 44 bytes

	-- Number of alternate-function planes per GPIO pin (AF0..AF7). PxSEL picks
	-- GPIO vs alternate mode; the pin's PxAFS field (one nibble per pin, low
	-- 3 bits used) picks WHICH alternate function drives the pad. AF0 is the
	-- legacy single alternate function, so PxAFS=0 reproduces the historic
	-- behavior and PxSEL-only software is unaffected.
	constant GPIO_NUM_AFS			: natural := 8;

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
	constant RegSlotWDTPASS			: natural := 12;	-- offset = 48 bytes
	constant RegSlotWDTCR			: natural := 13;	-- offset = 52 bytes
	constant RegSlotWDTSR			: natural := 14;	-- offset = 56 bytes
	constant RegSlotWDTVAL			: natural := 15;	-- offset = 60 bytes
	constant RegSlotDCO0BIAS		: natural := 16;	-- offset = 64 bytes
	constant RegSlotDCO1BIAS		: natural := 17;	-- offset = 68 bytes

	-- PWRCTRL
	constant RegSlotPWRCR			: natural := 00;	-- offset = 0 bytes
	constant RegSlotPWRSR0			: natural := 01;	-- offset = 4 bytes
	constant RegSlotPWRSR1			: natural := 02;	-- offset = 8 bytes
	constant RegSlotPWRSR2			: natural := 03;	-- offset = 12 bytes

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

	-- CLINT
	constant RegSlotMSIP0			: natural := 00;	-- offset = 0 bytes
	constant RegSlotMSIP1			: natural := 01;	-- offset = 4 bytes
	constant RegSlotMSIP2			: natural := 02;	-- offset = 8 bytes
	constant RegSlotMSIP3			: natural := 03;	-- offset = 12 bytes
	constant RegSlotMSIP4			: natural := 04;	-- offset = 16 bytes
	constant RegSlotMSIP5			: natural := 05;	-- offset = 20 bytes
	constant RegSlotMSIP6			: natural := 06;	-- offset = 24 bytes
	constant RegSlotMSIP7			: natural := 07;	-- offset = 28 bytes
	constant RegSlotMSIP8			: natural := 08;	-- offset = 32 bytes
	constant RegSlotMSIP9			: natural := 09;	-- offset = 36 bytes
	constant RegSlotMSIP10			: natural := 10;	-- offset = 40 bytes
	constant RegSlotMSIP11			: natural := 11;	-- offset = 44 bytes
	constant RegSlotMSIP12			: natural := 12;	-- offset = 48 bytes
	constant RegSlotMSIP13			: natural := 13;	-- offset = 52 bytes
	constant RegSlotMSIP14			: natural := 14;	-- offset = 56 bytes
	constant RegSlotMSIP15			: natural := 15;	-- offset = 60 bytes
	constant RegSlotMSIP16			: natural := 16;	-- offset = 64 bytes
	constant RegSlotMSIP17			: natural := 17;	-- offset = 68 bytes
	constant RegSlotMTIMEL			: natural := 20;	-- offset = 80 bytes
	constant RegSlotMTIMEH			: natural := 21;	-- offset = 84 bytes
	constant RegSlotMTIMECMP0L		: natural := 24;	-- offset = 96 bytes
	constant RegSlotMTIMECMP0H		: natural := 25;	-- offset = 100 bytes
	constant RegSlotMTIMECMP1L		: natural := 26;	-- offset = 104 bytes
	constant RegSlotMTIMECMP1H		: natural := 27;	-- offset = 108 bytes
	constant RegSlotMTIMECMP2L		: natural := 28;	-- offset = 112 bytes
	constant RegSlotMTIMECMP2H		: natural := 29;	-- offset = 116 bytes
	constant RegSlotMTIMECMP3L		: natural := 30;	-- offset = 120 bytes
	constant RegSlotMTIMECMP3H		: natural := 31;	-- offset = 124 bytes
	constant RegSlotMTIMECMP4L		: natural := 32;	-- offset = 128 bytes
	constant RegSlotMTIMECMP4H		: natural := 33;	-- offset = 132 bytes
	constant RegSlotMTIMECMP5L		: natural := 34;	-- offset = 136 bytes
	constant RegSlotMTIMECMP5H		: natural := 35;	-- offset = 140 bytes
	constant RegSlotMTIMECMP6L		: natural := 36;	-- offset = 144 bytes
	constant RegSlotMTIMECMP6H		: natural := 37;	-- offset = 148 bytes
	constant RegSlotMTIMECMP7L		: natural := 38;	-- offset = 152 bytes
	constant RegSlotMTIMECMP7H		: natural := 39;	-- offset = 156 bytes
	constant RegSlotMTIMECMP8L		: natural := 40;	-- offset = 160 bytes
	constant RegSlotMTIMECMP8H		: natural := 41;	-- offset = 164 bytes
	constant RegSlotMTIMECMP9L		: natural := 42;	-- offset = 168 bytes
	constant RegSlotMTIMECMP9H		: natural := 43;	-- offset = 172 bytes
	constant RegSlotMTIMECMP10L		: natural := 44;	-- offset = 176 bytes
	constant RegSlotMTIMECMP10H		: natural := 45;	-- offset = 180 bytes
	constant RegSlotMTIMECMP11L		: natural := 46;	-- offset = 184 bytes
	constant RegSlotMTIMECMP11H		: natural := 47;	-- offset = 188 bytes
	constant RegSlotMTIMECMP12L		: natural := 48;	-- offset = 192 bytes
	constant RegSlotMTIMECMP12H		: natural := 49;	-- offset = 196 bytes
	constant RegSlotMTIMECMP13L		: natural := 50;	-- offset = 200 bytes
	constant RegSlotMTIMECMP13H		: natural := 51;	-- offset = 204 bytes
	constant RegSlotMTIMECMP14L		: natural := 52;	-- offset = 208 bytes
	constant RegSlotMTIMECMP14H		: natural := 53;	-- offset = 212 bytes
	constant RegSlotMTIMECMP15L		: natural := 54;	-- offset = 216 bytes
	constant RegSlotMTIMECMP15H		: natural := 55;	-- offset = 220 bytes
	constant RegSlotMTIMECMP16L		: natural := 56;	-- offset = 224 bytes
	constant RegSlotMTIMECMP16H		: natural := 57;	-- offset = 228 bytes
	constant RegSlotMTIMECMP17L		: natural := 58;	-- offset = 232 bytes
	constant RegSlotMTIMECMP17H		: natural := 59;	-- offset = 236 bytes

	-- MUTEX
	constant RegSlotMUTEX0			: natural := 00;	-- offset = 0 bytes
	constant RegSlotMUTEX1			: natural := 01;	-- offset = 4 bytes
	constant RegSlotMUTEX2			: natural := 02;	-- offset = 8 bytes
	constant RegSlotMUTEX3			: natural := 03;	-- offset = 12 bytes
	constant RegSlotMUTEX4			: natural := 04;	-- offset = 16 bytes
	constant RegSlotMUTEX5			: natural := 05;	-- offset = 20 bytes
	constant RegSlotMUTEX6			: natural := 06;	-- offset = 24 bytes
	constant RegSlotMUTEX7			: natural := 07;	-- offset = 28 bytes
	constant RegSlotMUTEX8			: natural := 08;	-- offset = 32 bytes
	constant RegSlotMUTEX9			: natural := 09;	-- offset = 36 bytes
	constant RegSlotMUTEX10			: natural := 10;	-- offset = 40 bytes
	constant RegSlotMUTEX11			: natural := 11;	-- offset = 44 bytes
	constant RegSlotMUTEX12			: natural := 12;	-- offset = 48 bytes
	constant RegSlotMUTEX13			: natural := 13;	-- offset = 52 bytes
	constant RegSlotMUTEX14			: natural := 14;	-- offset = 56 bytes
	constant RegSlotMUTEX15			: natural := 15;	-- offset = 60 bytes
	constant RegSlotMUTEX16			: natural := 16;	-- offset = 64 bytes
	constant RegSlotMUTEX17			: natural := 17;	-- offset = 68 bytes
	constant RegSlotMUTEX18			: natural := 18;	-- offset = 72 bytes
	constant RegSlotMUTEX19			: natural := 19;	-- offset = 76 bytes
	constant RegSlotMUTEX20			: natural := 20;	-- offset = 80 bytes
	constant RegSlotMUTEX21			: natural := 21;	-- offset = 84 bytes
	constant RegSlotMUTEX22			: natural := 22;	-- offset = 88 bytes
	constant RegSlotMUTEX23			: natural := 23;	-- offset = 92 bytes
	constant RegSlotMUTEX24			: natural := 24;	-- offset = 96 bytes
	constant RegSlotMUTEX25			: natural := 25;	-- offset = 100 bytes
	constant RegSlotMUTEX26			: natural := 26;	-- offset = 104 bytes
	constant RegSlotMUTEX27			: natural := 27;	-- offset = 108 bytes
	constant RegSlotMUTEX28			: natural := 28;	-- offset = 112 bytes
	constant RegSlotMUTEX29			: natural := 29;	-- offset = 116 bytes
	constant RegSlotMUTEX30			: natural := 30;	-- offset = 120 bytes
	constant RegSlotMUTEX31			: natural := 31;	-- offset = 124 bytes

	-- IRQROUTER
	constant RegSlotH0ENL			: natural := 00;	-- offset = 0 bytes
	constant RegSlotH0ENM			: natural := 01;	-- offset = 4 bytes
	constant RegSlotH0ENU			: natural := 02;	-- offset = 8 bytes
	constant RegSlotH1ENL			: natural := 04;	-- offset = 16 bytes
	constant RegSlotH1ENM			: natural := 05;	-- offset = 20 bytes
	constant RegSlotH1ENU			: natural := 06;	-- offset = 24 bytes
	constant RegSlotH2ENL			: natural := 08;	-- offset = 32 bytes
	constant RegSlotH2ENM			: natural := 09;	-- offset = 36 bytes
	constant RegSlotH2ENU			: natural := 10;	-- offset = 40 bytes
	constant RegSlotH3ENL			: natural := 12;	-- offset = 48 bytes
	constant RegSlotH3ENM			: natural := 13;	-- offset = 52 bytes
	constant RegSlotH3ENU			: natural := 14;	-- offset = 56 bytes
	constant RegSlotH4ENL			: natural := 16;	-- offset = 64 bytes
	constant RegSlotH4ENM			: natural := 17;	-- offset = 68 bytes
	constant RegSlotH4ENU			: natural := 18;	-- offset = 72 bytes
	constant RegSlotH5ENL			: natural := 20;	-- offset = 80 bytes
	constant RegSlotH5ENM			: natural := 21;	-- offset = 84 bytes
	constant RegSlotH5ENU			: natural := 22;	-- offset = 88 bytes
	constant RegSlotH6ENL			: natural := 24;	-- offset = 96 bytes
	constant RegSlotH6ENM			: natural := 25;	-- offset = 100 bytes
	constant RegSlotH6ENU			: natural := 26;	-- offset = 104 bytes
	constant RegSlotH7ENL			: natural := 28;	-- offset = 112 bytes
	constant RegSlotH7ENM			: natural := 29;	-- offset = 116 bytes
	constant RegSlotH7ENU			: natural := 30;	-- offset = 120 bytes
	constant RegSlotH8ENL			: natural := 32;	-- offset = 128 bytes
	constant RegSlotH8ENM			: natural := 33;	-- offset = 132 bytes
	constant RegSlotH8ENU			: natural := 34;	-- offset = 136 bytes
	constant RegSlotH9ENL			: natural := 36;	-- offset = 144 bytes
	constant RegSlotH9ENM			: natural := 37;	-- offset = 148 bytes
	constant RegSlotH9ENU			: natural := 38;	-- offset = 152 bytes
	constant RegSlotH10ENL			: natural := 40;	-- offset = 160 bytes
	constant RegSlotH10ENM			: natural := 41;	-- offset = 164 bytes
	constant RegSlotH10ENU			: natural := 42;	-- offset = 168 bytes
	constant RegSlotH11ENL			: natural := 44;	-- offset = 176 bytes
	constant RegSlotH11ENM			: natural := 45;	-- offset = 180 bytes
	constant RegSlotH11ENU			: natural := 46;	-- offset = 184 bytes
	constant RegSlotH12ENL			: natural := 48;	-- offset = 192 bytes
	constant RegSlotH12ENM			: natural := 49;	-- offset = 196 bytes
	constant RegSlotH12ENU			: natural := 50;	-- offset = 200 bytes
	constant RegSlotH13ENL			: natural := 52;	-- offset = 208 bytes
	constant RegSlotH13ENM			: natural := 53;	-- offset = 212 bytes
	constant RegSlotH13ENU			: natural := 54;	-- offset = 216 bytes
	constant RegSlotH14ENL			: natural := 56;	-- offset = 224 bytes
	constant RegSlotH14ENM			: natural := 57;	-- offset = 228 bytes
	constant RegSlotH14ENU			: natural := 58;	-- offset = 232 bytes
	constant RegSlotH15ENL			: natural := 60;	-- offset = 240 bytes
	constant RegSlotH15ENM			: natural := 61;	-- offset = 244 bytes
	constant RegSlotH15ENU			: natural := 62;	-- offset = 248 bytes
	constant RegSlotH16ENL			: natural := 64;	-- offset = 256 bytes
	constant RegSlotH16ENM			: natural := 65;	-- offset = 260 bytes
	constant RegSlotH16ENU			: natural := 66;	-- offset = 264 bytes
	constant RegSlotH17ENL			: natural := 68;	-- offset = 272 bytes
	constant RegSlotH17ENM			: natural := 69;	-- offset = 276 bytes
	constant RegSlotH17ENU			: natural := 70;	-- offset = 280 bytes
	constant RegSlotCLAIM			: natural := 512;	-- offset = 2048 bytes
	constant RegSlotPENDL			: natural := 516;	-- offset = 2064 bytes
	constant RegSlotPENDM			: natural := 517;	-- offset = 2068 bytes
	constant RegSlotPENDU			: natural := 518;	-- offset = 2072 bytes
	constant RegSlotINSVCL			: natural := 520;	-- offset = 2080 bytes
	constant RegSlotINSVCM			: natural := 521;	-- offset = 2084 bytes
	constant RegSlotINSVCU			: natural := 522;	-- offset = 2088 bytes



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

	-- GPIO4

	-- GPIO5



	---------- GPIO Register Reset Values ----------
	-- Transcribed from hdl/common/MemoryMap.vhd (RTL port numbering: GPIO0 = P1)
	-- GPIO0
	constant RstValP1OUT	: std_logic_vector(31 downto 0) := X"00000001";	-- cs0 default to '1' to disable flash
	constant RstValP1DIR	: std_logic_vector(31 downto 0) := X"00000041";	-- only cs0, and trap is an output
	constant RstValP1SEL	: std_logic_vector(31 downto 0) := X"0000004E";	-- all alt fn except boot, cs0
	constant RstValP1REN	: std_logic_vector(31 downto 0) := X"00000080";	-- only boot has pullup/pulldown - should default to '1' to load from flash
	constant RstValP1AFS	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins select AF0 (legacy alternate function) at reset

	-- GPIO1
	constant RstValP2OUT	: std_logic_vector(31 downto 0) := X"00000000";	-- all pads output low
	constant RstValP2DIR	: std_logic_vector(31 downto 0) := X"00000010";	-- tx0 is output
	constant RstValP2SEL	: std_logic_vector(31 downto 0) := X"00000030";	-- uart0 default to alt fn
	constant RstValP2REN	: std_logic_vector(31 downto 0) := X"00000000";	-- disable rens
	constant RstValP2AFS	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins select AF0 (legacy alternate function) at reset

	-- GPIO2
	constant RstValP3OUT	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3DIR	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3SEL	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3REN	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP3AFS	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins select AF0 (legacy alternate function) at reset

	-- GPIO3
	constant RstValP4OUT	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4DIR	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4SEL	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4REN	: std_logic_vector(31 downto 0) := X"00000000";
	constant RstValP4AFS	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins select AF0 (legacy alternate function) at reset

	-- GPIO4
	constant RstValP5OUT	: std_logic_vector(31 downto 0) := X"00000000";	-- all pads output low
	constant RstValP5DIR	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins input at reset
	constant RstValP5SEL	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins in GPIO mode at reset
	constant RstValP5REN	: std_logic_vector(31 downto 0) := X"00000000";	-- P5.6/7 (I3C SDA/SCL) pull-ups enabled when I3C present, else none
	constant RstValP5AFS	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins select AF0 (plain GPIO) at reset

	-- GPIO5
	constant RstValP6OUT	: std_logic_vector(31 downto 0) := X"00000000";	-- all pads output low
	constant RstValP6DIR	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins input at reset
	constant RstValP6SEL	: std_logic_vector(31 downto 0) := X"00000000";	-- all pins in GPIO mode at reset
	constant RstValP6REN	: std_logic_vector(31 downto 0) := X"00000000";	-- disable rens
	constant RstValP6AFS	: std_logic_vector(31 downto 0) := X"00000000";	-- P6.0 (NFC rf_clk) resets to AF1 for clock routing when NFC present, else all AF0



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

	-- PxIF
	constant PxIF_MSB				: natural := 31;
	constant PxIF_LSB				: natural := 00;

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

	-- PxAFS
	constant PxAFS7_MSB				: natural := 30;
	constant PxAFS7_LSB				: natural := 28;
	constant PxAFS6_MSB				: natural := 26;
	constant PxAFS6_LSB				: natural := 24;
	constant PxAFS5_MSB				: natural := 22;
	constant PxAFS5_LSB				: natural := 20;
	constant PxAFS4_MSB				: natural := 18;
	constant PxAFS4_LSB				: natural := 16;
	constant PxAFS3_MSB				: natural := 14;
	constant PxAFS3_LSB				: natural := 12;
	constant PxAFS2_MSB				: natural := 10;
	constant PxAFS2_LSB				: natural := 08;
	constant PxAFS1_MSB				: natural := 06;
	constant PxAFS1_LSB				: natural := 04;
	constant PxAFS0_MSB				: natural := 02;
	constant PxAFS0_LSB				: natural := 00;


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

	-- WDTPASS
	constant SYSWDTPASS_MSB			: natural := 31;
	constant SYSWDTPASS_LSB			: natural := 00;

	-- WDTCR
	constant SYSWDTEN_LSB			: natural := 07;
	constant SYSWDTCDIV_MSB			: natural := 05;
	constant SYSWDTCDIV_LSB			: natural := 02;
	constant SYSWDTIE_LSB			: natural := 01;
	constant SYSWDTHWRST_LSB		: natural := 00;

	-- WDTSR
	constant SYSWDTIF_LSB			: natural := 01;
	constant SYSWDTRF_LSB			: natural := 00;

	-- WDTVAL
	constant SYSWDTVAL_MSB			: natural := 23;
	constant SYSWDTVAL_LSB			: natural := 00;

	-- DCO0BIAS
	constant SYSDCO0BIAS_MSB		: natural := 11;
	constant SYSDCO0BIAS_LSB		: natural := 00;

	-- DCO1BIAS
	constant SYSDCO1BIAS_MSB		: natural := 11;
	constant SYSDCO1BIAS_LSB		: natural := 00;


	------ PWRCTRL
	-- PWRCR
	constant PWRGATE_MSB			: natural := 17;
	constant PWRGATE_LSB			: natural := 01;
	constant PWRH0_LSB				: natural := 00;

	-- PWRSR0
	constant PWRST7_MSB				: natural := 31;
	constant PWRST7_LSB				: natural := 28;
	constant PWRST6_MSB				: natural := 27;
	constant PWRST6_LSB				: natural := 24;
	constant PWRST5_MSB				: natural := 23;
	constant PWRST5_LSB				: natural := 20;
	constant PWRST4_MSB				: natural := 19;
	constant PWRST4_LSB				: natural := 16;
	constant PWRST3_MSB				: natural := 15;
	constant PWRST3_LSB				: natural := 12;
	constant PWRST2_MSB				: natural := 11;
	constant PWRST2_LSB				: natural := 08;
	constant PWRST1_MSB				: natural := 07;
	constant PWRST1_LSB				: natural := 04;
	constant PWRST0_MSB				: natural := 03;
	constant PWRST0_LSB				: natural := 00;

	-- PWRSR1
	constant PWRST15_MSB			: natural := 31;
	constant PWRST15_LSB			: natural := 28;
	constant PWRST14_MSB			: natural := 27;
	constant PWRST14_LSB			: natural := 24;
	constant PWRST13_MSB			: natural := 23;
	constant PWRST13_LSB			: natural := 20;
	constant PWRST12_MSB			: natural := 19;
	constant PWRST12_LSB			: natural := 16;
	constant PWRST11_MSB			: natural := 15;
	constant PWRST11_LSB			: natural := 12;
	constant PWRST10_MSB			: natural := 11;
	constant PWRST10_LSB			: natural := 08;
	constant PWRST9_MSB				: natural := 07;
	constant PWRST9_LSB				: natural := 04;
	constant PWRST8_MSB				: natural := 03;
	constant PWRST8_LSB				: natural := 00;

	-- PWRSR2
	constant PWRST17_MSB			: natural := 07;
	constant PWRST17_LSB			: natural := 04;
	constant PWRST16_MSB			: natural := 03;
	constant PWRST16_LSB			: natural := 00;


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


	------ CLINT
	-- MSIP0
	constant CLINTMSIPH0_LSB		: natural := 00;

	-- MSIP1
	constant CLINTMSIPH1_LSB		: natural := 00;

	-- MSIP2
	constant CLINTMSIPH2_LSB		: natural := 00;

	-- MSIP3
	constant CLINTMSIPH3_LSB		: natural := 00;

	-- MSIP4
	constant CLINTMSIPH4_LSB		: natural := 00;

	-- MSIP5
	constant CLINTMSIPH5_LSB		: natural := 00;

	-- MSIP6
	constant CLINTMSIPH6_LSB		: natural := 00;

	-- MSIP7
	constant CLINTMSIPH7_LSB		: natural := 00;

	-- MSIP8
	constant CLINTMSIPH8_LSB		: natural := 00;

	-- MSIP9
	constant CLINTMSIPH9_LSB		: natural := 00;

	-- MSIP10
	constant CLINTMSIPH10_LSB		: natural := 00;

	-- MSIP11
	constant CLINTMSIPH11_LSB		: natural := 00;

	-- MSIP12
	constant CLINTMSIPH12_LSB		: natural := 00;

	-- MSIP13
	constant CLINTMSIPH13_LSB		: natural := 00;

	-- MSIP14
	constant CLINTMSIPH14_LSB		: natural := 00;

	-- MSIP15
	constant CLINTMSIPH15_LSB		: natural := 00;

	-- MSIP16
	constant CLINTMSIPH16_LSB		: natural := 00;

	-- MSIP17
	constant CLINTMSIPH17_LSB		: natural := 00;

	-- MTIMEL
	constant CLINTMTIMEL_MSB		: natural := 31;
	constant CLINTMTIMEL_LSB		: natural := 00;

	-- MTIMEH
	constant CLINTMTIMEH_MSB		: natural := 31;
	constant CLINTMTIMEH_LSB		: natural := 00;

	-- MTIMECMP0L
	constant CLINTMTIMECMP0L_MSB	: natural := 31;
	constant CLINTMTIMECMP0L_LSB	: natural := 00;

	-- MTIMECMP0H
	constant CLINTMTIMECMP0H_MSB	: natural := 31;
	constant CLINTMTIMECMP0H_LSB	: natural := 00;

	-- MTIMECMP1L
	constant CLINTMTIMECMP1L_MSB	: natural := 31;
	constant CLINTMTIMECMP1L_LSB	: natural := 00;

	-- MTIMECMP1H
	constant CLINTMTIMECMP1H_MSB	: natural := 31;
	constant CLINTMTIMECMP1H_LSB	: natural := 00;

	-- MTIMECMP2L
	constant CLINTMTIMECMP2L_MSB	: natural := 31;
	constant CLINTMTIMECMP2L_LSB	: natural := 00;

	-- MTIMECMP2H
	constant CLINTMTIMECMP2H_MSB	: natural := 31;
	constant CLINTMTIMECMP2H_LSB	: natural := 00;

	-- MTIMECMP3L
	constant CLINTMTIMECMP3L_MSB	: natural := 31;
	constant CLINTMTIMECMP3L_LSB	: natural := 00;

	-- MTIMECMP3H
	constant CLINTMTIMECMP3H_MSB	: natural := 31;
	constant CLINTMTIMECMP3H_LSB	: natural := 00;

	-- MTIMECMP4L
	constant CLINTMTIMECMP4L_MSB	: natural := 31;
	constant CLINTMTIMECMP4L_LSB	: natural := 00;

	-- MTIMECMP4H
	constant CLINTMTIMECMP4H_MSB	: natural := 31;
	constant CLINTMTIMECMP4H_LSB	: natural := 00;

	-- MTIMECMP5L
	constant CLINTMTIMECMP5L_MSB	: natural := 31;
	constant CLINTMTIMECMP5L_LSB	: natural := 00;

	-- MTIMECMP5H
	constant CLINTMTIMECMP5H_MSB	: natural := 31;
	constant CLINTMTIMECMP5H_LSB	: natural := 00;

	-- MTIMECMP6L
	constant CLINTMTIMECMP6L_MSB	: natural := 31;
	constant CLINTMTIMECMP6L_LSB	: natural := 00;

	-- MTIMECMP6H
	constant CLINTMTIMECMP6H_MSB	: natural := 31;
	constant CLINTMTIMECMP6H_LSB	: natural := 00;

	-- MTIMECMP7L
	constant CLINTMTIMECMP7L_MSB	: natural := 31;
	constant CLINTMTIMECMP7L_LSB	: natural := 00;

	-- MTIMECMP7H
	constant CLINTMTIMECMP7H_MSB	: natural := 31;
	constant CLINTMTIMECMP7H_LSB	: natural := 00;

	-- MTIMECMP8L
	constant CLINTMTIMECMP8L_MSB	: natural := 31;
	constant CLINTMTIMECMP8L_LSB	: natural := 00;

	-- MTIMECMP8H
	constant CLINTMTIMECMP8H_MSB	: natural := 31;
	constant CLINTMTIMECMP8H_LSB	: natural := 00;

	-- MTIMECMP9L
	constant CLINTMTIMECMP9L_MSB	: natural := 31;
	constant CLINTMTIMECMP9L_LSB	: natural := 00;

	-- MTIMECMP9H
	constant CLINTMTIMECMP9H_MSB	: natural := 31;
	constant CLINTMTIMECMP9H_LSB	: natural := 00;

	-- MTIMECMP10L
	constant CLINTMTIMECMP10L_MSB	: natural := 31;
	constant CLINTMTIMECMP10L_LSB	: natural := 00;

	-- MTIMECMP10H
	constant CLINTMTIMECMP10H_MSB	: natural := 31;
	constant CLINTMTIMECMP10H_LSB	: natural := 00;

	-- MTIMECMP11L
	constant CLINTMTIMECMP11L_MSB	: natural := 31;
	constant CLINTMTIMECMP11L_LSB	: natural := 00;

	-- MTIMECMP11H
	constant CLINTMTIMECMP11H_MSB	: natural := 31;
	constant CLINTMTIMECMP11H_LSB	: natural := 00;

	-- MTIMECMP12L
	constant CLINTMTIMECMP12L_MSB	: natural := 31;
	constant CLINTMTIMECMP12L_LSB	: natural := 00;

	-- MTIMECMP12H
	constant CLINTMTIMECMP12H_MSB	: natural := 31;
	constant CLINTMTIMECMP12H_LSB	: natural := 00;

	-- MTIMECMP13L
	constant CLINTMTIMECMP13L_MSB	: natural := 31;
	constant CLINTMTIMECMP13L_LSB	: natural := 00;

	-- MTIMECMP13H
	constant CLINTMTIMECMP13H_MSB	: natural := 31;
	constant CLINTMTIMECMP13H_LSB	: natural := 00;

	-- MTIMECMP14L
	constant CLINTMTIMECMP14L_MSB	: natural := 31;
	constant CLINTMTIMECMP14L_LSB	: natural := 00;

	-- MTIMECMP14H
	constant CLINTMTIMECMP14H_MSB	: natural := 31;
	constant CLINTMTIMECMP14H_LSB	: natural := 00;

	-- MTIMECMP15L
	constant CLINTMTIMECMP15L_MSB	: natural := 31;
	constant CLINTMTIMECMP15L_LSB	: natural := 00;

	-- MTIMECMP15H
	constant CLINTMTIMECMP15H_MSB	: natural := 31;
	constant CLINTMTIMECMP15H_LSB	: natural := 00;

	-- MTIMECMP16L
	constant CLINTMTIMECMP16L_MSB	: natural := 31;
	constant CLINTMTIMECMP16L_LSB	: natural := 00;

	-- MTIMECMP16H
	constant CLINTMTIMECMP16H_MSB	: natural := 31;
	constant CLINTMTIMECMP16H_LSB	: natural := 00;

	-- MTIMECMP17L
	constant CLINTMTIMECMP17L_MSB	: natural := 31;
	constant CLINTMTIMECMP17L_LSB	: natural := 00;

	-- MTIMECMP17H
	constant CLINTMTIMECMP17H_MSB	: natural := 31;
	constant CLINTMTIMECMP17H_LSB	: natural := 00;


	------ MUTEX
	-- MUTEX0
	constant MTXOWN0_MSB			: natural := 31;
	constant MTXOWN0_LSB			: natural := 00;

	-- MUTEX1
	constant MTXOWN1_MSB			: natural := 31;
	constant MTXOWN1_LSB			: natural := 00;

	-- MUTEX2
	constant MTXOWN2_MSB			: natural := 31;
	constant MTXOWN2_LSB			: natural := 00;

	-- MUTEX3
	constant MTXOWN3_MSB			: natural := 31;
	constant MTXOWN3_LSB			: natural := 00;

	-- MUTEX4
	constant MTXOWN4_MSB			: natural := 31;
	constant MTXOWN4_LSB			: natural := 00;

	-- MUTEX5
	constant MTXOWN5_MSB			: natural := 31;
	constant MTXOWN5_LSB			: natural := 00;

	-- MUTEX6
	constant MTXOWN6_MSB			: natural := 31;
	constant MTXOWN6_LSB			: natural := 00;

	-- MUTEX7
	constant MTXOWN7_MSB			: natural := 31;
	constant MTXOWN7_LSB			: natural := 00;

	-- MUTEX8
	constant MTXOWN8_MSB			: natural := 31;
	constant MTXOWN8_LSB			: natural := 00;

	-- MUTEX9
	constant MTXOWN9_MSB			: natural := 31;
	constant MTXOWN9_LSB			: natural := 00;

	-- MUTEX10
	constant MTXOWN10_MSB			: natural := 31;
	constant MTXOWN10_LSB			: natural := 00;

	-- MUTEX11
	constant MTXOWN11_MSB			: natural := 31;
	constant MTXOWN11_LSB			: natural := 00;

	-- MUTEX12
	constant MTXOWN12_MSB			: natural := 31;
	constant MTXOWN12_LSB			: natural := 00;

	-- MUTEX13
	constant MTXOWN13_MSB			: natural := 31;
	constant MTXOWN13_LSB			: natural := 00;

	-- MUTEX14
	constant MTXOWN14_MSB			: natural := 31;
	constant MTXOWN14_LSB			: natural := 00;

	-- MUTEX15
	constant MTXOWN15_MSB			: natural := 31;
	constant MTXOWN15_LSB			: natural := 00;

	-- MUTEX16
	constant MTXOWN16_MSB			: natural := 31;
	constant MTXOWN16_LSB			: natural := 00;

	-- MUTEX17
	constant MTXOWN17_MSB			: natural := 31;
	constant MTXOWN17_LSB			: natural := 00;

	-- MUTEX18
	constant MTXOWN18_MSB			: natural := 31;
	constant MTXOWN18_LSB			: natural := 00;

	-- MUTEX19
	constant MTXOWN19_MSB			: natural := 31;
	constant MTXOWN19_LSB			: natural := 00;

	-- MUTEX20
	constant MTXOWN20_MSB			: natural := 31;
	constant MTXOWN20_LSB			: natural := 00;

	-- MUTEX21
	constant MTXOWN21_MSB			: natural := 31;
	constant MTXOWN21_LSB			: natural := 00;

	-- MUTEX22
	constant MTXOWN22_MSB			: natural := 31;
	constant MTXOWN22_LSB			: natural := 00;

	-- MUTEX23
	constant MTXOWN23_MSB			: natural := 31;
	constant MTXOWN23_LSB			: natural := 00;

	-- MUTEX24
	constant MTXOWN24_MSB			: natural := 31;
	constant MTXOWN24_LSB			: natural := 00;

	-- MUTEX25
	constant MTXOWN25_MSB			: natural := 31;
	constant MTXOWN25_LSB			: natural := 00;

	-- MUTEX26
	constant MTXOWN26_MSB			: natural := 31;
	constant MTXOWN26_LSB			: natural := 00;

	-- MUTEX27
	constant MTXOWN27_MSB			: natural := 31;
	constant MTXOWN27_LSB			: natural := 00;

	-- MUTEX28
	constant MTXOWN28_MSB			: natural := 31;
	constant MTXOWN28_LSB			: natural := 00;

	-- MUTEX29
	constant MTXOWN29_MSB			: natural := 31;
	constant MTXOWN29_LSB			: natural := 00;

	-- MUTEX30
	constant MTXOWN30_MSB			: natural := 31;
	constant MTXOWN30_LSB			: natural := 00;

	-- MUTEX31
	constant MTXOWN31_MSB			: natural := 31;
	constant MTXOWN31_LSB			: natural := 00;


	------ IRQROUTER
	-- H0ENL
	constant IRQRH0ENL_MSB			: natural := 31;
	constant IRQRH0ENL_LSB			: natural := 00;

	-- H0ENM
	constant IRQRH0ENM_MSB			: natural := 31;
	constant IRQRH0ENM_LSB			: natural := 00;

	-- H0ENU
	constant IRQRH0ENU_MSB			: natural := 20;
	constant IRQRH0ENU_LSB			: natural := 00;

	-- H1ENL
	constant IRQRH1ENL_MSB			: natural := 31;
	constant IRQRH1ENL_LSB			: natural := 00;

	-- H1ENM
	constant IRQRH1ENM_MSB			: natural := 31;
	constant IRQRH1ENM_LSB			: natural := 00;

	-- H1ENU
	constant IRQRH1ENU_MSB			: natural := 20;
	constant IRQRH1ENU_LSB			: natural := 00;

	-- H2ENL
	constant IRQRH2ENL_MSB			: natural := 31;
	constant IRQRH2ENL_LSB			: natural := 00;

	-- H2ENM
	constant IRQRH2ENM_MSB			: natural := 31;
	constant IRQRH2ENM_LSB			: natural := 00;

	-- H2ENU
	constant IRQRH2ENU_MSB			: natural := 20;
	constant IRQRH2ENU_LSB			: natural := 00;

	-- H3ENL
	constant IRQRH3ENL_MSB			: natural := 31;
	constant IRQRH3ENL_LSB			: natural := 00;

	-- H3ENM
	constant IRQRH3ENM_MSB			: natural := 31;
	constant IRQRH3ENM_LSB			: natural := 00;

	-- H3ENU
	constant IRQRH3ENU_MSB			: natural := 20;
	constant IRQRH3ENU_LSB			: natural := 00;

	-- H4ENL
	constant IRQRH4ENL_MSB			: natural := 31;
	constant IRQRH4ENL_LSB			: natural := 00;

	-- H4ENM
	constant IRQRH4ENM_MSB			: natural := 31;
	constant IRQRH4ENM_LSB			: natural := 00;

	-- H4ENU
	constant IRQRH4ENU_MSB			: natural := 20;
	constant IRQRH4ENU_LSB			: natural := 00;

	-- H5ENL
	constant IRQRH5ENL_MSB			: natural := 31;
	constant IRQRH5ENL_LSB			: natural := 00;

	-- H5ENM
	constant IRQRH5ENM_MSB			: natural := 31;
	constant IRQRH5ENM_LSB			: natural := 00;

	-- H5ENU
	constant IRQRH5ENU_MSB			: natural := 20;
	constant IRQRH5ENU_LSB			: natural := 00;

	-- H6ENL
	constant IRQRH6ENL_MSB			: natural := 31;
	constant IRQRH6ENL_LSB			: natural := 00;

	-- H6ENM
	constant IRQRH6ENM_MSB			: natural := 31;
	constant IRQRH6ENM_LSB			: natural := 00;

	-- H6ENU
	constant IRQRH6ENU_MSB			: natural := 20;
	constant IRQRH6ENU_LSB			: natural := 00;

	-- H7ENL
	constant IRQRH7ENL_MSB			: natural := 31;
	constant IRQRH7ENL_LSB			: natural := 00;

	-- H7ENM
	constant IRQRH7ENM_MSB			: natural := 31;
	constant IRQRH7ENM_LSB			: natural := 00;

	-- H7ENU
	constant IRQRH7ENU_MSB			: natural := 20;
	constant IRQRH7ENU_LSB			: natural := 00;

	-- H8ENL
	constant IRQRH8ENL_MSB			: natural := 31;
	constant IRQRH8ENL_LSB			: natural := 00;

	-- H8ENM
	constant IRQRH8ENM_MSB			: natural := 31;
	constant IRQRH8ENM_LSB			: natural := 00;

	-- H8ENU
	constant IRQRH8ENU_MSB			: natural := 20;
	constant IRQRH8ENU_LSB			: natural := 00;

	-- H9ENL
	constant IRQRH9ENL_MSB			: natural := 31;
	constant IRQRH9ENL_LSB			: natural := 00;

	-- H9ENM
	constant IRQRH9ENM_MSB			: natural := 31;
	constant IRQRH9ENM_LSB			: natural := 00;

	-- H9ENU
	constant IRQRH9ENU_MSB			: natural := 20;
	constant IRQRH9ENU_LSB			: natural := 00;

	-- H10ENL
	constant IRQRH10ENL_MSB			: natural := 31;
	constant IRQRH10ENL_LSB			: natural := 00;

	-- H10ENM
	constant IRQRH10ENM_MSB			: natural := 31;
	constant IRQRH10ENM_LSB			: natural := 00;

	-- H10ENU
	constant IRQRH10ENU_MSB			: natural := 20;
	constant IRQRH10ENU_LSB			: natural := 00;

	-- H11ENL
	constant IRQRH11ENL_MSB			: natural := 31;
	constant IRQRH11ENL_LSB			: natural := 00;

	-- H11ENM
	constant IRQRH11ENM_MSB			: natural := 31;
	constant IRQRH11ENM_LSB			: natural := 00;

	-- H11ENU
	constant IRQRH11ENU_MSB			: natural := 20;
	constant IRQRH11ENU_LSB			: natural := 00;

	-- H12ENL
	constant IRQRH12ENL_MSB			: natural := 31;
	constant IRQRH12ENL_LSB			: natural := 00;

	-- H12ENM
	constant IRQRH12ENM_MSB			: natural := 31;
	constant IRQRH12ENM_LSB			: natural := 00;

	-- H12ENU
	constant IRQRH12ENU_MSB			: natural := 20;
	constant IRQRH12ENU_LSB			: natural := 00;

	-- H13ENL
	constant IRQRH13ENL_MSB			: natural := 31;
	constant IRQRH13ENL_LSB			: natural := 00;

	-- H13ENM
	constant IRQRH13ENM_MSB			: natural := 31;
	constant IRQRH13ENM_LSB			: natural := 00;

	-- H13ENU
	constant IRQRH13ENU_MSB			: natural := 20;
	constant IRQRH13ENU_LSB			: natural := 00;

	-- H14ENL
	constant IRQRH14ENL_MSB			: natural := 31;
	constant IRQRH14ENL_LSB			: natural := 00;

	-- H14ENM
	constant IRQRH14ENM_MSB			: natural := 31;
	constant IRQRH14ENM_LSB			: natural := 00;

	-- H14ENU
	constant IRQRH14ENU_MSB			: natural := 20;
	constant IRQRH14ENU_LSB			: natural := 00;

	-- H15ENL
	constant IRQRH15ENL_MSB			: natural := 31;
	constant IRQRH15ENL_LSB			: natural := 00;

	-- H15ENM
	constant IRQRH15ENM_MSB			: natural := 31;
	constant IRQRH15ENM_LSB			: natural := 00;

	-- H15ENU
	constant IRQRH15ENU_MSB			: natural := 20;
	constant IRQRH15ENU_LSB			: natural := 00;

	-- H16ENL
	constant IRQRH16ENL_MSB			: natural := 31;
	constant IRQRH16ENL_LSB			: natural := 00;

	-- H16ENM
	constant IRQRH16ENM_MSB			: natural := 31;
	constant IRQRH16ENM_LSB			: natural := 00;

	-- H16ENU
	constant IRQRH16ENU_MSB			: natural := 20;
	constant IRQRH16ENU_LSB			: natural := 00;

	-- H17ENL
	constant IRQRH17ENL_MSB			: natural := 31;
	constant IRQRH17ENL_LSB			: natural := 00;

	-- H17ENM
	constant IRQRH17ENM_MSB			: natural := 31;
	constant IRQRH17ENM_LSB			: natural := 00;

	-- H17ENU
	constant IRQRH17ENU_MSB			: natural := 20;
	constant IRQRH17ENU_LSB			: natural := 00;

	-- CLAIM
	constant IRQRCLAIM_MSB			: natural := 31;
	constant IRQRCLAIM_LSB			: natural := 00;

	-- PENDL
	constant IRQRPENDL_MSB			: natural := 31;
	constant IRQRPENDL_LSB			: natural := 00;

	-- PENDM
	constant IRQRPENDM_MSB			: natural := 31;
	constant IRQRPENDM_LSB			: natural := 00;

	-- PENDU
	constant IRQRPENDU_MSB			: natural := 20;
	constant IRQRPENDU_LSB			: natural := 00;

	-- INSVCL
	constant IRQRINSVCL_MSB			: natural := 31;
	constant IRQRINSVCL_LSB			: natural := 00;

	-- INSVCM
	constant IRQRINSVCM_MSB			: natural := 31;
	constant IRQRINSVCM_LSB			: natural := 00;

	-- INSVCU
	constant IRQRINSVCU_MSB			: natural := 20;
	constant IRQRINSVCU_LSB			: natural := 00;



	---------- MCU_MP Compatibility ----------
	-- Constants the hand-written hdl/common/MemoryMap.vhd defines beyond the sections
	-- above. Emitted so this generated package is a drop-in replacement for that file;
	-- transcribed values cite it as their source.

	-- Memory Block Memory Slot Assignments
	constant MemSlotROM				: natural := 00;						-- base address = 0x00000
	constant MemSlotRAM0			: natural := 01;						-- base address = 0x08000
	constant MemSlotRAM1			: natural := 02;						-- base address = 0x0C000
	constant MemSlotPeriph			: natural := 04;						-- base address = 0x04000

	-- Peripheral legacy slot numbers (RTL spelling; slots of moved peripherals are
	-- still used to zero their dead 0x4000-page windows)
	constant PeriphSlotGPIO0		: natural := 00;						-- base address = 0x4000 (legacy; peripheral now at 0x4000)
	constant PeriphSlotGPIO1		: natural := 01;						-- base address = 0x4100 (legacy; peripheral now at 0x4100)
	constant PeriphSlotSPI0			: natural := 02;						-- base address = 0x4200 (legacy; peripheral now at 0x4200)
	constant PeriphSlotSPI1			: natural := 03;						-- base address = 0x4300 (legacy; peripheral now at 0x4300)
	constant PeriphSlotUART0		: natural := 04;						-- base address = 0x4400 (legacy; peripheral now at 0x4400)
	constant PeriphSlotUART1		: natural := 05;						-- base address = 0x4500 (legacy; peripheral now at 0x4500)
	constant PeriphSlotTIMER0		: natural := 06;						-- base address = 0x4600 (legacy; peripheral now at 0x4600)
	constant PeriphSlotTIMER1		: natural := 07;						-- base address = 0x4700 (legacy; peripheral now at 0x4700)
	constant PeriphSlotGPIO2		: natural := 08;						-- base address = 0x4800 (legacy; peripheral now at 0x4800)
	constant PeriphSlotSystem0		: natural := 09;						-- base address = 0x4900 (legacy; peripheral now at 0x4900)
	constant PeriphSlotPWRCTRL		: natural := 11;						-- base address = 0x4B00 (legacy; peripheral now at 0x4B00)
	constant PeriphSlotGPIO3		: natural := 13;						-- base address = 0x4D00 (legacy; peripheral now at 0x4D00)
	constant PeriphSlotI2C0			: natural := 14;						-- base address = 0x4E00 (legacy; peripheral now at 0x4E00)
	constant PeriphSlotI2C1			: natural := 15;						-- base address = 0x4F00 (legacy; peripheral now at 0x4F00)

	-- Peripheral slot masks
	constant GPIO0_MASK				: natural := 2 ** PeriphSlotGPIO0;
	constant GPIO1_MASK				: natural := 2 ** PeriphSlotGPIO1;
	constant SPI0_MASK				: natural := 2 ** PeriphSlotSPI0;
	constant SPI1_MASK				: natural := 2 ** PeriphSlotSPI1;
	constant UART0_MASK				: natural := 2 ** PeriphSlotUART0;
	constant UART1_MASK				: natural := 2 ** PeriphSlotUART1;
	constant TIMER0_MASK			: natural := 2 ** PeriphSlotTIMER0;
	constant TIMER1_MASK			: natural := 2 ** PeriphSlotTIMER1;
	constant GPIO2_MASK				: natural := 2 ** PeriphSlotGPIO2;
	constant SYSTEM0_MASK			: natural := 2 ** PeriphSlotSystem0;
	constant PWRCTRL_MASK			: natural := 2 ** PeriphSlotPWRCTRL;
	constant GPIO3_MASK				: natural := 2 ** PeriphSlotGPIO3;
	constant I2C0_MASK				: natural := 2 ** PeriphSlotI2C0;
	constant I2C1_MASK				: natural := 2 ** PeriphSlotI2C1;

	-- GPIO Constants
	constant gpio_dir_out			: std_logic := '1';						-- GPIO output direction
	constant gpio_dir_in			: std_logic := '0';						-- GPIO input direction
	constant gpio_ren_en			: std_logic := '1';						-- GPIO resistor enable
	constant gpio_ren_dis			: std_logic := '0';						-- GPIO resistor disable
	constant gpio_out_high			: std_logic := '1';						-- GPIO output high
	constant gpio_out_low			: std_logic := '0';						-- GPIO output low

	-- SYSTEM register slots (RTL spelling; slot values from hdl/common/MemoryMap.vhd)
	constant RegSlotSYS_CLK_CR		: natural := 00;						-- offset = 0 bytes
	constant RegSlotSYS_CLK_DIV_CR	: natural := 01;						-- offset = 4 bytes
	constant RegSlotSYS_BLOCK_PWR	: natural := 02;						-- offset = 8 bytes
	constant RegSlotSYS_CRC_DATA	: natural := 03;						-- offset = 12 bytes
	constant RegSlotSYS_CRC_STATE	: natural := 04;						-- offset = 16 bytes
	constant RegSlotSYS_WDT_PASS	: natural := 12;						-- offset = 48 bytes
	constant RegSlotSYS_WDT_CR		: natural := 13;						-- offset = 52 bytes
	constant RegSlotSYS_WDT_SR		: natural := 14;						-- offset = 56 bytes
	constant RegSlotSYS_WDT_VAL		: natural := 15;						-- offset = 60 bytes
	constant RegSlotDCO0_BIAS		: natural := 16;						-- offset = 64 bytes
	constant RegSlotDCO1_BIAS		: natural := 17;						-- offset = 68 bytes

	-- Interrupt Bit Assignments (per-vector; names from hdl/common/MemoryMap.vhd)
	constant IVT_BASE_ADDR			: integer := 16#8000#;					-- IVT base address = 0x8000
	constant IRQB_SYS_WDT			: natural := 00;						-- Watchdog Timer Interrupt, IVT address = 0x8000
	constant IRQB_GPIO0_B0			: natural := 01;						-- GPIO0 Bit 0 Interrupt, IVT address = 0x8004
	constant IRQB_GPIO0_B1			: natural := 02;						-- GPIO0 Bit 1 Interrupt, IVT address = 0x8008
	constant IRQB_GPIO0_B2			: natural := 03;						-- GPIO0 Bit 2 Interrupt, IVT address = 0x800C
	constant IRQB_GPIO0_B3			: natural := 04;						-- GPIO0 Bit 3 Interrupt, IVT address = 0x8010
	constant IRQB_GPIO0_B4			: natural := 05;						-- GPIO0 Bit 4 Interrupt, IVT address = 0x8014
	constant IRQB_GPIO0_B5			: natural := 06;						-- GPIO0 Bit 5 Interrupt, IVT address = 0x8018
	constant IRQB_GPIO0_B6			: natural := 07;						-- GPIO0 Bit 6 Interrupt, IVT address = 0x801C
	constant IRQB_GPIO0_B7			: natural := 08;						-- GPIO0 Bit 7 Interrupt, IVT address = 0x8020
	constant IRQB_SPI0_TC			: natural := 09;						-- SPI0 Transmission Complete Interrupt, IVT address = 0x8024
	constant IRQB_SPI0_TE			: natural := 10;						-- SPI0 Transmission Buffer Empty Interrupt, IVT address = 0x8028
	constant IRQB_SPI1_TC			: natural := 11;						-- SPI1 Transmission Complete Interrupt, IVT address = 0x802C
	constant IRQB_SPI1_TE			: natural := 12;						-- SPI1 Transmission Buffer Empty Interrupt, IVT address = 0x8030
	constant IRQB_UART0_RC			: natural := 13;						-- UART0 Receive Complete Interrupt, IVT address = 0x8034
	constant IRQB_UART0_TE			: natural := 14;						-- UART0 Transmission Buffer Empty Interrupt, IVT address = 0x8038
	constant IRQB_UART0_TC			: natural := 15;						-- UART0 Transmission Complete Interrupt, IVT address = 0x803C
	constant IRQB_TIM0_CAP0			: natural := 16;						-- TIMER0 Capture 0 Interrupt, IVT address = 0x8040
	constant IRQB_TIM0_CAP1			: natural := 17;						-- TIMER0 Capture 1 Interrupt, IVT address = 0x8044
	constant IRQB_TIM0_OVF			: natural := 18;						-- TIMER0 Overflow Interrupt, IVT address = 0x8048
	constant IRQB_TIM0_CMP0			: natural := 19;						-- TIMER0 Compare 0 Interrupt, IVT address = 0x804C
	constant IRQB_TIM0_CMP1			: natural := 20;						-- TIMER0 Compare 1 Interrupt, IVT address = 0x8050
	constant IRQB_TIM0_CMP2			: natural := 21;						-- TIMER0 Compare 2 Interrupt, IVT address = 0x8054
	constant IRQB_TIM1_CAP0			: natural := 22;						-- TIMER1 Capture 0 Interrupt, IVT address = 0x8058
	constant IRQB_TIM1_CAP1			: natural := 23;						-- TIMER1 Capture 1 Interrupt, IVT address = 0x805C
	constant IRQB_TIM1_OVF			: natural := 24;						-- TIMER1 Overflow Interrupt, IVT address = 0x8060
	constant IRQB_TIM1_CMP0			: natural := 25;						-- TIMER1 Compare 0 Interrupt, IVT address = 0x8064
	constant IRQB_TIM1_CMP1			: natural := 26;						-- TIMER1 Compare 1 Interrupt, IVT address = 0x8068
	constant IRQB_TIM1_CMP2			: natural := 27;						-- TIMER1 Compare 2 Interrupt, IVT address = 0x806C
	constant IRQB_GPIO1_B0			: natural := 28;						-- GPIO1 Bit 0 Interrupt, IVT address = 0x8070
	constant IRQB_GPIO1_B1			: natural := 29;						-- GPIO1 Bit 1 Interrupt, IVT address = 0x8074
	constant IRQB_GPIO1_B2			: natural := 30;						-- GPIO1 Bit 2 Interrupt, IVT address = 0x8078
	constant IRQB_GPIO1_B3			: natural := 31;						-- GPIO1 Bit 3 Interrupt, IVT address = 0x807C
	constant IRQB_GPIO1_B4			: natural := 32;						-- GPIO1 Bit 4 Interrupt, IVT address = 0x8080
	constant IRQB_GPIO1_B5			: natural := 33;						-- GPIO1 Bit 5 Interrupt, IVT address = 0x8084
	constant IRQB_GPIO1_B6			: natural := 34;						-- GPIO1 Bit 6 Interrupt, IVT address = 0x8088
	constant IRQB_GPIO1_B7			: natural := 35;						-- GPIO1 Bit 7 Interrupt, IVT address = 0x808C
	constant IRQB_GPIO2_B0			: natural := 36;						-- GPIO2 Bit 0 Interrupt, IVT address = 0x8090
	constant IRQB_GPIO2_B1			: natural := 37;						-- GPIO2 Bit 1 Interrupt, IVT address = 0x8094
	constant IRQB_GPIO2_B2			: natural := 38;						-- GPIO2 Bit 2 Interrupt, IVT address = 0x8098
	constant IRQB_GPIO2_B3			: natural := 39;						-- GPIO2 Bit 3 Interrupt, IVT address = 0x809C
	constant IRQB_GPIO2_B4			: natural := 40;						-- GPIO2 Bit 4 Interrupt, IVT address = 0x80A0
	constant IRQB_GPIO2_B5			: natural := 41;						-- GPIO2 Bit 5 Interrupt, IVT address = 0x80A4
	constant IRQB_GPIO2_B6			: natural := 42;						-- GPIO2 Bit 6 Interrupt, IVT address = 0x80A8
	constant IRQB_GPIO2_B7			: natural := 43;						-- GPIO2 Bit 7 Interrupt, IVT address = 0x80AC
	constant IRQB_GPIO3_B0			: natural := 44;						-- GPIO3 Bit 0 Interrupt, IVT address = 0x80B0
	constant IRQB_GPIO3_B1			: natural := 45;						-- GPIO3 Bit 1 Interrupt, IVT address = 0x80B4
	constant IRQB_GPIO3_B2			: natural := 46;						-- GPIO3 Bit 2 Interrupt, IVT address = 0x80B8
	constant IRQB_GPIO3_B3			: natural := 47;						-- GPIO3 Bit 3 Interrupt, IVT address = 0x80BC
	constant IRQB_GPIO3_B4			: natural := 48;						-- GPIO3 Bit 4 Interrupt, IVT address = 0x80C0
	constant IRQB_GPIO3_B5			: natural := 49;						-- GPIO3 Bit 5 Interrupt, IVT address = 0x80C4
	constant IRQB_GPIO3_B6			: natural := 50;						-- GPIO3 Bit 6 Interrupt, IVT address = 0x80C8
	constant IRQB_GPIO3_B7			: natural := 51;						-- GPIO3 Bit 7 Interrupt, IVT address = 0x80CC
	constant IRQB_UART1_RC			: natural := 52;						-- UART1 Receive Complete Interrupt, IVT address = 0x80D0
	constant IRQB_UART1_TE			: natural := 53;						-- UART1 Transmission Buffer Empty Interrupt, IVT address = 0x80D4
	constant IRQB_UART1_TC			: natural := 54;						-- UART1 Transmission Complete Interrupt, IVT address = 0x80D8
	constant IRQB_RSVD55			: natural := 55;						-- Reserved (vector 55; formerly AFE0 Receive Complete), IVT address = 0x80DC
	constant IRQB_RSVD56			: natural := 56;						-- Reserved (vector 56; formerly SARADC0 Conversion Complete), IVT address = 0x80E0
	constant IRQB_I2C0_STR			: natural := 57;						-- I2C0 start received Interrupt, IVT address = 0x80E4
	constant IRQB_I2C0_spr			: natural := 58;						-- I2C0 stop received Interrupt, IVT address = 0x80E8
	constant IRQB_I2C0_msts			: natural := 59;						-- I2C0 master mode start condition sent Interrupt, IVT address = 0x80EC
	constant IRQB_I2C0_msps			: natural := 60;						-- I2C0 master mode stop condition sent Interrupt, IVT address = 0x80F0
	constant IRQB_I2C0_marb			: natural := 61;						-- I2C0 master mode arbitration lost Interrupt, IVT address = 0x80F4
	constant IRQB_I2C0_mtxe			: natural := 62;						-- I2C0 master mode transmit empty Interrupt, IVT address = 0x80F8
	constant IRQB_I2C0_mnr			: natural := 63;						-- I2C0 master mode NACK received Interrupt, IVT address = 0x80FC
	constant IRQB_I2C0_mxc			: natural := 64;						-- I2C0 master mode transfer complete Interrupt, IVT address = 0x8100
	constant IRQB_I2C0_sa			: natural := 65;						-- I2C0 slave address Interrupt, IVT address = 0x8104
	constant IRQB_I2C0_stxe			: natural := 66;						-- I2C0 slave transmit empty Interrupt, IVT address = 0x8108
	constant IRQB_I2C0_sovf			: natural := 67;						-- I2C0 slave overflow Interrupt, IVT address = 0x810C
	constant IRQB_I2C0_snr			: natural := 68;						-- I2C0 slave mode NACK received Interrupt, IVT address = 0x8110
	constant IRQB_I2C0_sxc			: natural := 69;						-- I2C0 slave mode transfer complete Interrupt, IVT address = 0x8114
	constant IRQB_I2C1_STR			: natural := 70;						-- I2C1 start received Interrupt, IVT address = 0x8118
	constant IRQB_I2C1_spr			: natural := 71;						-- I2C1 stop received Interrupt, IVT address = 0x811C
	constant IRQB_I2C1_msts			: natural := 72;						-- I2C1 master mode start condition sent Interrupt, IVT address = 0x8120
	constant IRQB_I2C1_msps			: natural := 73;						-- I2C1 master mode stop condition sent Interrupt, IVT address = 0x8124
	constant IRQB_I2C1_marb			: natural := 74;						-- I2C1 master mode arbitration lost Interrupt, IVT address = 0x8128
	constant IRQB_I2C1_mtxe			: natural := 75;						-- I2C1 master mode transmit empty Interrupt, IVT address = 0x812C
	constant IRQB_I2C1_mnr			: natural := 76;						-- I2C1 master mode NACK received Interrupt, IVT address = 0x8130
	constant IRQB_I2C1_mxc			: natural := 77;						-- I2C1 master mode transfer complete Interrupt, IVT address = 0x8134
	constant IRQB_I2C1_sa			: natural := 78;						-- I2C1 slave address Interrupt, IVT address = 0x8138
	constant IRQB_I2C1_stxe			: natural := 79;						-- I2C1 slave transmit empty Interrupt, IVT address = 0x813C
	constant IRQB_I2C1_sovf			: natural := 80;						-- I2C1 slave overflow Interrupt, IVT address = 0x8140
	constant IRQB_I2C1_snr			: natural := 81;						-- I2C1 slave mode NACK received Interrupt, IVT address = 0x8144
	constant IRQB_I2C1_sxc			: natural := 82;						-- I2C1 slave mode transfer complete Interrupt, IVT address = 0x8148
	constant IRQB_CLINT_MSIP		: natural := 83;						-- CLINT software interrupt (IPI), IVT address = 0x814C
	constant IRQB_CLINT_MTIP		: natural := 84;						-- CLINT timer interrupt, IVT address = 0x8150
	constant IRQB_RSVD85			: natural := 85;						-- Reserved (vector 85; coincides with the meip external-interrupt IVT slot, never a pending source), IVT address = 0x8154
	constant IRQB_RSVD86			: natural := 86;						-- Reserved (vector 86; I3C0 disabled by this configuration), IVT address = 0x8158
	constant IRQB_RSVD87			: natural := 87;						-- Reserved (vector 87; I3C0 disabled by this configuration), IVT address = 0x815C
	constant IRQB_RSVD88			: natural := 88;						-- Reserved (vector 88; I3C0 disabled by this configuration), IVT address = 0x8160
	constant IRQB_RSVD89			: natural := 89;						-- Reserved (vector 89; I3C0 disabled by this configuration), IVT address = 0x8164
	constant IRQB_RSVD90			: natural := 90;						-- Reserved (vector 90; I3C0 disabled by this configuration), IVT address = 0x8168
	constant IRQB_RSVD91			: natural := 91;						-- Reserved (vector 91; I3C0 disabled by this configuration), IVT address = 0x816C
	constant IRQB_RSVD92			: natural := 92;						-- Reserved (vector 92; I3C0 disabled by this configuration), IVT address = 0x8170
	constant IRQB_RSVD93			: natural := 93;						-- Reserved (vector 93; I3C0 disabled by this configuration), IVT address = 0x8174
	constant IRQB_RSVD94			: natural := 94;						-- Reserved (vector 94; NFC0 disabled by this configuration), IVT address = 0x8178
	constant IRQB_RSVD95			: natural := 95;						-- Reserved (vector 95; NFC0 disabled by this configuration), IVT address = 0x817C
	constant IRQB_RSVD96			: natural := 96;						-- Reserved (vector 96; NFC0 disabled by this configuration), IVT address = 0x8180
	constant IRQB_RSVD97			: natural := 97;						-- Reserved (vector 97; NFC0 disabled by this configuration), IVT address = 0x8184
	constant IRQB_GPIO4_B0			: natural := 98;						-- GPIO4 Bit 0 Interrupt, IVT address = 0x8188
	constant IRQB_GPIO4_B1			: natural := 99;						-- GPIO4 Bit 1 Interrupt, IVT address = 0x818C
	constant IRQB_GPIO4_B2			: natural := 100;						-- GPIO4 Bit 2 Interrupt, IVT address = 0x8190
	constant IRQB_GPIO4_B3			: natural := 101;						-- GPIO4 Bit 3 Interrupt, IVT address = 0x8194
	constant IRQB_GPIO4_B4			: natural := 102;						-- GPIO4 Bit 4 Interrupt, IVT address = 0x8198
	constant IRQB_GPIO4_B5			: natural := 103;						-- GPIO4 Bit 5 Interrupt, IVT address = 0x819C
	constant IRQB_GPIO4_B6			: natural := 104;						-- GPIO4 Bit 6 Interrupt, IVT address = 0x81A0
	constant IRQB_GPIO4_B7			: natural := 105;						-- GPIO4 Bit 7 Interrupt, IVT address = 0x81A4
	constant IRQB_GPIO5_B0			: natural := 106;						-- GPIO5 Bit 0 Interrupt, IVT address = 0x81A8
	constant IRQB_GPIO5_B1			: natural := 107;						-- GPIO5 Bit 1 Interrupt, IVT address = 0x81AC
	constant IRQB_GPIO5_B2			: natural := 108;						-- GPIO5 Bit 2 Interrupt, IVT address = 0x81B0
	constant IRQB_GPIO5_B3			: natural := 109;						-- GPIO5 Bit 3 Interrupt, IVT address = 0x81B4
	constant IRQB_GPIO5_B4			: natural := 110;						-- GPIO5 Bit 4 Interrupt, IVT address = 0x81B8
	constant IRQB_GPIO5_B5			: natural := 111;						-- GPIO5 Bit 5 Interrupt, IVT address = 0x81BC
	constant IRQB_GPIO5_B6			: natural := 112;						-- GPIO5 Bit 6 Interrupt, IVT address = 0x81C0
	constant IRQB_GPIO5_B7			: natural := 113;						-- GPIO5 Bit 7 Interrupt, IVT address = 0x81C4
	constant IRQB_EXT_MEIP			: natural := 85;						-- External (peripheral) interrupt via IRQROUTER claim/complete, IVT address = 0x8154
	constant NUM_IRQ_SRCS			: natural := 114;						-- Peripheral IRQ SOURCES (deglitch/irq_router width; CLINT slots delivered per-hart)
	constant NUM_IRQS				: natural := 114;						-- Core IVT slot count = max(sources, meip slot + 1) (M19; digperiphs #2)
	constant NUM_GF_INSTANCES		: natural := (NUM_IRQ_SRCS + 31) / 32;	-- glitch-filter instance count

	-- Core ISA Features (drive the hart_tile/vesta ENABLE_* generics; all four tiles identical)
	constant CORE_ENABLE_MUL		: boolean := true;						-- M: MUL/MULH/MULHU/MULHSU
	constant CORE_ENABLE_DIV		: boolean := true;						-- M: DIV/DIVU/REM/REMU + the iterative divider
	constant CORE_ENABLE_ATOMICS	: boolean := true;						-- A: LR/SC + AMOs (disabling breaks the mutex/lock infrastructure)
	constant CORE_ENABLE_COMPRESSED	: boolean := true;						-- C: 16-bit instructions
	constant CORE_ENABLE_BITMANIP	: boolean := true;						-- Zba/Zbb/Zbs/Zbc
	constant CORE_ENABLE_ZICOND		: boolean := false;						-- X1: Zicond czero.eqz/nez
	constant CORE_ENABLE_ZCB		: boolean := false;						-- X1: Zcb extra compressed insns
	constant CORE_ENABLE_ZIMOP		: boolean := false;						-- X1: Zimop+Zcmop may-be-ops
	constant CORE_ENABLE_ZIHINT		: boolean := false;						-- X1: Zihintpause+Zihintntl
	constant CORE_ENABLE_ZIHPM		: boolean := false;						-- X1: Zihpm hw perf counters
	constant CORE_ENABLE_ZAWRS		: boolean := false;						-- X1: Zawrs wait-on-reservation
	constant CORE_ENABLE_ZABHA		: boolean := false;						-- X2: Zabha byte/half AMOs
	constant CORE_ENABLE_ZACAS		: boolean := false;						-- X2: Zacas amocas.w
	constant CORE_ENABLE_ZICBOZ		: boolean := false;						-- X3: Zicboz cbo.zero block-zero
	constant CORE_ENABLE_ZCMP		: boolean := false;						-- X3: Zcmp push/pop + reg-moves
	constant CORE_ENABLE_ZCMT		: boolean := false;						-- X3: Zcmt table jump + jvt CSR
	constant CORE_ENABLE_ZBKB		: boolean := false;						-- X3: Zbkb crypto bit-manip
	constant CORE_ENABLE_ZBKC		: boolean := false;						-- X3: Zbkc carryless multiply
	constant CORE_ENABLE_ZBKX		: boolean := false;						-- X3: Zbkx crossbar permute
	constant CORE_ENABLE_ZKN		: boolean := false;						-- X3: Zkn AES+SHA (Zknd+Zkne+Zknh)
	constant CORE_ENABLE_ZFINX		: boolean := false;						-- X4: Zfinx single-prec FP in x-regs

	-- GPIO0 Pin Assignments (Serial Flash)
	constant pnum_gpio0_cs_flash	: natural := 00;						-- P1.0
	constant pnum_gpio0_miso		: natural := 01;						-- P1.1
	constant pnum_gpio0_mosi		: natural := 02;						-- P1.2
	constant pnum_gpio0_spi_clk		: natural := 03;						-- P1.3
	constant pnum_gpio0_lfxt		: natural := 04;						-- P1.4
	constant pnum_gpio0_hfxt		: natural := 05;						-- P1.5
	constant pnum_gpio0_trap		: natural := 06;						-- P1.6
	constant pnum_gpio0_boot		: natural := 07;						-- P1.7

	-- GPIO1 Pin Assignments (SPI1, UART0, UART1)
	constant pnum_gpio1_cs1			: natural := 00;						-- P2.0
	constant pnum_gpio1_miso1		: natural := 01;						-- P2.1
	constant pnum_gpio1_mosi1		: natural := 02;						-- P2.2
	constant pnum_gpio1_sck1		: natural := 03;						-- P2.3
	constant pnum_gpio1_tx0			: natural := 04;						-- P2.4
	constant pnum_gpio1_rx0			: natural := 05;						-- P2.5
	constant pnum_gpio1_tx1			: natural := 06;						-- P2.6
	constant pnum_gpio1_rx1			: natural := 07;						-- P2.7

	-- GPIO2 Pin Assignments (TIMER0, TIMER1)
	constant pnum_gpio2_t0_cmp0		: natural := 00;						-- P3.0
	constant pnum_gpio2_t0_cmp1		: natural := 01;						-- P3.1
	constant pnum_gpio2_t0_cap0		: natural := 02;						-- P3.2
	constant pnum_gpio2_t0_cap1		: natural := 03;						-- P3.3
	constant pnum_gpio2_t1_cmp0		: natural := 04;						-- P3.4
	constant pnum_gpio2_t1_cmp1		: natural := 05;						-- P3.5
	constant pnum_gpio2_t1_cap0		: natural := 06;						-- P3.6
	constant pnum_gpio2_t1_cap1		: natural := 07;						-- P3.7

	-- GPIO3 Pin Assignments (DTP)
	constant pnum_gpio3_sda0		: natural := 00;						-- P4.0
	constant pnum_gpio3_scl0		: natural := 01;						-- P4.1
	constant pnum_gpio3_sda1		: natural := 02;						-- P4.2
	constant pnum_gpio3_scl1		: natural := 03;						-- P4.3
	constant pnum_gpio3_dtp0		: natural := 04;						-- P4.4
	constant pnum_gpio3_dtp1		: natural := 05;						-- P4.5
	constant pnum_gpio3_dtp2		: natural := 06;						-- P4.6
	constant pnum_gpio3_dtp3		: natural := 07;						-- P4.7

	-- GPIO1 (P2) AF1: TIMER compare (PWM) relocations + I2C1 relocation (v2) + I2C0 relocation
	constant pnum_gpio1_af1_t0_cmp0	: natural := 00;						-- P2.0
	constant pnum_gpio1_af1_t0_cmp1	: natural := 01;						-- P2.1
	constant pnum_gpio1_af1_t1_cmp0	: natural := 02;						-- P2.2
	constant pnum_gpio1_af1_t1_cmp1	: natural := 03;						-- P2.3
	constant pnum_gpio1_af1_sda1	: natural := 04;						-- P2.4
	constant pnum_gpio1_af1_scl1	: natural := 05;						-- P2.5
	constant pnum_gpio1_af1_sda0	: natural := 06;						-- P2.6
	constant pnum_gpio1_af1_scl0	: natural := 07;						-- P2.7

	-- GPIO2 (P3) AF1: UART0/UART1 + I2C1 relocations + I2C0 relocation (v2)
	constant pnum_gpio2_af1_tx1		: natural := 00;						-- P3.0
	constant pnum_gpio2_af1_rx1		: natural := 01;						-- P3.1
	constant pnum_gpio2_af1_sda1	: natural := 02;						-- P3.2
	constant pnum_gpio2_af1_scl1	: natural := 03;						-- P3.3
	constant pnum_gpio2_af1_tx0		: natural := 04;						-- P3.4
	constant pnum_gpio2_af1_rx0		: natural := 05;						-- P3.5
	constant pnum_gpio2_af1_sda0	: natural := 06;						-- P3.6
	constant pnum_gpio2_af1_scl0	: natural := 07;						-- P3.7

	-- GPIO3 (P4) AF1: TIMER capture + compare relocations
	constant pnum_gpio3_af1_t0_cap0	: natural := 00;						-- P4.0
	constant pnum_gpio3_af1_t0_cap1	: natural := 01;						-- P4.1
	constant pnum_gpio3_af1_t1_cap0	: natural := 02;						-- P4.2
	constant pnum_gpio3_af1_t1_cap1	: natural := 03;						-- P4.3
	constant pnum_gpio3_af1_t0_cmp0	: natural := 04;						-- P4.4
	constant pnum_gpio3_af1_t0_cmp1	: natural := 05;						-- P4.5
	constant pnum_gpio3_af1_t1_cmp0	: natural := 06;						-- P4.6
	constant pnum_gpio3_af1_t1_cmp1	: natural := 07;						-- P4.7

	-- GPIO4 (P5) AF1: P5.0-5 reserved (QSPI0 absent) + P5.6/7 reserved (I3C0 absent)

	-- GPIO5 (P6) AF1: P6.0-5 reserved (NFC0 absent)



end MemoryMap;

package body MemoryMap is
end MemoryMap;
