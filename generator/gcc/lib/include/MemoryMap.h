/**
 **	MemoryMap.h
 **	Memory map definition header file
 **	Defines the microcontroller peripheral and register addresses, as well as the bit field bit masks
 **	Generated on 2026/02/17 at 13:23:05 with the MemoryMap.py memory map generator
 **	WARNING: Do not edit or modify this file!
 **		If you need to change it, use the MemoryMap.py memory map generator tool
 **/

#pragma once	// Ensures this file will be included only once per source file

#ifdef __cplusplus
extern "C" {
#endif	// extern "C"



/** Includes **/
#include <stdint.h>
#include <bits.h>
#include <custom_ops.S>



/** Defines **/
#define ASIC_NAME	"Myshkin"
#define ASIC_DEFINE_Myshkin



/** Memory Mapped Register Macros **/
#define MMR_8_BIT_MACRO(_address)	(*((volatile uint8_t *) (_address)))
#define MMR_08_BIT_MACRO(_address)	MMR_8_BIT_MACRO(_address)
#define MMR_16_BIT_MACRO(_address)	(*((volatile uint16_t *) (_address)))
#define MMR_32_BIT_MACRO(_address)	(*((volatile uint32_t *) (_address)))
#define MMR_8_PTR(_peripheralBaseAddress, _registerOffset)	MMR_8_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))
#define MMR_08_PTR(_peripheralBaseAddress, _registerOffset)	MMR_8_PTR(_peripheralBaseAddress, _registerOffset)
#define MMR_16_PTR(_peripheralBaseAddress, _registerOffset)	MMR_16_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))
#define MMR_32_PTR(_peripheralBaseAddress, _registerOffset)	MMR_32_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))



/** Macros **/

// General Macros
#define STR_EXPAND_MACRO(_tok)	#_tok
#define MACRO_TO_STRING(_tok)	STR_EXPAND_MACRO(_tok)

// Interrupt Macros
#ifdef __cplusplus
#define RVISR(_vect_number, _func_name)	extern "C" { __attribute__((used)) void _func_name(); __attribute__((used)) __attribute__((section(".__interrupt_vector_" MACRO_TO_STRING(_vect_number)))) void (*__IVT_vector_##_vect_number##_##_func_name##__)(void) = _func_name; }
#else	// #ifdef __cplusplus
#define RVISR(_vect_number, _func_name)	__attribute__((used)) void _func_name(); __attribute__((used)) __attribute__((section(".__interrupt_vector_" MACRO_TO_STRING(_vect_number)))) void (*__IVT_vector_##_vect_number##_##_func_name##__)(void) = _func_name;
#endif	// #ifdef __cplusplus
#define cpu_sleep()	asm volatile(MACRO_TO_STRING(smrv32_sleep_insn()) "\n")
#define cpu_wake()	asm volatile(MACRO_TO_STRING(smrv32_wake_insn()) "\n")
#define irq_return()	asm volatile(MACRO_TO_STRING(smrv32_retirq_insn()) "\n")



/** RAM, ROM, and Interrupt Vector Table Locations and Sizes **/
#define ROM_START							(0x0000)
#define ROM_SIZE							(0x4000)
#define RAM_START							(0x8000)
#define RAM_SIZE							(0x8000)
#define INTERRUPT_VECTOR_TABLE_START		(0x8000)
#define INTERRUPT_VECTOR_TABLE_SIZE			(0x0100)
#define RAM_PROGRAM_START_ADDRESS			(0x8100)
#define INTERRUPT_HANDLER_ADDRESS			(0x9000)
#define PERIPHERAL_SPACING					(0x0100)	// The number of bytes between each adjacent peripheral base address
#define STACK_POINTER_INIT					(0x10000)
#define BOOTLOADER_USES_SPI_FLASH_COMMANDS

#define RAM_SLOT_SIZE						(16384)
#define LAST_RAM_SLOT_SIZE					(16384)
#define SRAM03_ADDRESS						(0x0C000)
#define SRAM04_ADDRESS						(0x10000)

#define SPI_FLASH_PROGRAM_ADDRESS			(0x0000)

#define HAS_NATIVE_SPI_FLASH_MEMORY_READ_ACCESS
// Does not have native SPI Flash memory write access
#define SPI_FLASH_MEM_ADDRESS	(0x01000000)
#define SPI_FLASH_MEM			((volatile uint32_t *) (SPI_FLASH_MEM_ADDRESS))



/** Chip Properties **/
#define ENABLE_IRQ_FAST_CONTEXT_SWITCHING



/********** Register Offsets and Bit Fields **********/

/** GPIOx **/
// PxIN
#define PxIN_OFFSET				(0)
#define PxIN_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIN_OFFSET)

// PxOUT
#define PxOUT_OFFSET			(4)
#define PxOUT_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxOUT_OFFSET)

// PxOUTS
#define PxOUTS_OFFSET			(8)
#define PxOUTS_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxOUTS_OFFSET)

// PxOUTC
#define PxOUTC_OFFSET			(12)
#define PxOUTC_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxOUTC_OFFSET)

// PxOUTT
#define PxOUTT_OFFSET			(16)
#define PxOUTT_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxOUTT_OFFSET)

// PxDIR
#define PxDIR_OFFSET			(20)
#define PxDIR_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxDIR_OFFSET)

// PxIFG
#define PxIFG_OFFSET			(24)
#define PxIFG_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIFG_OFFSET)

// PxIES
#define PxIES_OFFSET			(28)
#define PxIES_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIES_OFFSET)

// PxIE
#define PxIE_OFFSET				(32)
#define PxIE_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIE_OFFSET)

// PxSEL
#define PxSEL_OFFSET			(36)
#define PxSEL_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxSEL_OFFSET)

// PxREN
#define PxREN_OFFSET			(40)
#define PxREN_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxREN_OFFSET)



/** SPIx **/
// SPIxCR
#define SPIxCR_OFFSET			(0)
#define SPIxCR_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxCR_OFFSET)

#define SPIFEN		(0x00080000)	// bit 19
#define SPIFEN_LSB	(19)
#define SPISM		(0x00040000)	// bit 18
#define SPISM_LSB	(18)
#define SPITXSB		(0x00020000)	// bit 17
#define SPITXSB_LSB	(17)
#define SPIRXSB		(0x00010000)	// bit 16
#define SPIRXSB_LSB	(16)
#define SPIBR_MASK	(0x0000FF00)	// bits 15 downto 8
#define SPIBR_LSB	(8)
#define SPIEN		(0x00000080)	// bit 7
#define SPIEN_LSB	(7)
#define SPIMSB		(0x00000040)	// bit 6
#define SPIMSB_LSB	(6)
#define SPITCIE		(0x00000020)	// bit 5
#define SPITCIE_LSB	(5)
#define SPITEIE		(0x00000010)	// bit 4
#define SPITEIE_LSB	(4)
#define SPIDL_MASK	(0x0000000C)	// bits 3 downto 2
#define SPIDL_LSB	(2)
#define SPIDL_8		(0x00000000)
#define SPIDL_16	(0x00000004)
#define SPIDL_32	(0x00000008)
#define SPICPOL		(0x00000002)	// bit 1
#define SPICPOL_LSB	(1)
#define SPICPHA		(0x00000001)	// bit 0
#define SPICPHA_LSB	(0)

// SPIxSR
#define SPIxSR_OFFSET			(4)
#define SPIxSR_PTR(_SPIx_BASE)	MMR_08_PTR(_SPIx_BASE, SPIxSR_OFFSET)

#define SPIBUSY		(0x04)	// bit 2
#define SPIBUSY_LSB	(2)
#define SPITCIF		(0x02)	// bit 1
#define SPITCIF_LSB	(1)
#define SPITEIF		(0x01)	// bit 0
#define SPITEIF_LSB	(0)

// SPIxTX
#define SPIxTX_OFFSET			(8)
#define SPIxTX_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxTX_OFFSET)

// SPIxRX
#define SPIxRX_OFFSET			(12)
#define SPIxRX_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxRX_OFFSET)

// SPIxFOS
#define SPIxFOS_OFFSET			(16)
#define SPIxFOS_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxFOS_OFFSET)



/** UARTx **/
// UARTxCR
#define UARTxCR_OFFSET				(0)
#define UARTxCR_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxCR_OFFSET)

#define UEN			(0x20)	// bit 5
#define UEN_LSB		(5)
#define UPEN		(0x10)	// bit 4
#define UPEN_LSB	(4)
#define UPODD		(0x08)	// bit 3
#define UPODD_LSB	(3)
#define URCIE		(0x04)	// bit 2
#define URCIE_LSB	(2)
#define UTEIE		(0x02)	// bit 1
#define UTEIE_LSB	(1)
#define UTCIE		(0x01)	// bit 0
#define UTCIE_LSB	(0)

// UARTxSR
#define UARTxSR_OFFSET				(4)
#define UARTxSR_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxSR_OFFSET)

#define URBF		(0x80)	// bit 7
#define URBF_LSB	(7)
#define UTBF		(0x40)	// bit 6
#define UTBF_LSB	(6)
#define UFEF		(0x20)	// bit 5
#define UFEF_LSB	(5)
#define UPEF		(0x10)	// bit 4
#define UPEF_LSB	(4)
#define UOVF		(0x08)	// bit 3
#define UOVF_LSB	(3)
#define URCIF		(0x04)	// bit 2
#define URCIF_LSB	(2)
#define UTEIF		(0x02)	// bit 1
#define UTEIF_LSB	(1)
#define UTCIF		(0x01)	// bit 0
#define UTCIF_LSB	(0)

// UARTxBR
#define UARTxBR_OFFSET				(8)
#define UARTxBR_PTR(_UARTx_BASE)	MMR_16_PTR(_UARTx_BASE, UARTxBR_OFFSET)

#define UBR_MASK	(0x0FFF)	// bits 11 downto 0
#define UBR_LSB		(0)

// UARTxRX
#define UARTxRX_OFFSET				(12)
#define UARTxRX_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxRX_OFFSET)

// UARTxTX
#define UARTxTX_OFFSET				(16)
#define UARTxTX_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxTX_OFFSET)



/** TIMERx **/
// TIMxCR
#define TIMxCR_OFFSET				(0)
#define TIMxCR_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCR_OFFSET)

#define TIMDIV_MASK		(0x000F0000)	// bits 19 downto 16
#define TIMDIV_LSB		(16)
#define TIMDIV_1		(0x00000000)
#define TIMDIV_2		(0x00010000)
#define TIMDIV_4		(0x00020000)
#define TIMDIV_8		(0x00030000)
#define TIMDIV_16		(0x00040000)
#define TIMDIV_32		(0x00050000)
#define TIMDIV_64		(0x00060000)
#define TIMDIV_128		(0x00070000)
#define TIMDIV_256		(0x00080000)
#define TIMDIV_512		(0x00090000)
#define TIMDIV_1024		(0x000A0000)
#define TIMDIV_2048		(0x000B0000)
#define TIMDIV_4096		(0x000C0000)
#define TIMDIV_8192		(0x000D0000)
#define TIMDIV_16384	(0x000E0000)
#define TIMDIV_32768	(0x000F0000)
#define TIMCMP1IH		(0x00008000)	// bit 15
#define TIMCMP1IH_LSB	(15)
#define TIMCMP0IH		(0x00004000)	// bit 14
#define TIMCMP0IH_LSB	(14)
#define TIMCAP1FE		(0x00002000)	// bit 13
#define TIMCAP1FE_LSB	(13)
#define TIMCAP0FE		(0x00001000)	// bit 12
#define TIMCAP0FE_LSB	(12)
#define TIMCAP1EN		(0x00000800)	// bit 11
#define TIMCAP1EN_LSB	(11)
#define TIMCAP0EN		(0x00000400)	// bit 10
#define TIMCAP0EN_LSB	(10)
#define TIMSSEL_MASK	(0x00000300)	// bits 9 downto 8
#define TIMSSEL_LSB		(8)
#define TIMSSEL_SMCLK	(0x00000000)
#define TIMSSEL_MCLK	(0x00000100)
#define TIMSSEL_LFXT	(0x00000200)
#define TIMSSEL_HFXT	(0x00000300)
#define TIMCMP2RST		(0x00000080)	// bit 7
#define TIMCMP2RST_LSB	(7)
#define TIMEN			(0x00000040)	// bit 6
#define TIMEN_LSB		(6)
#define TIMCAP1IE		(0x00000020)	// bit 5
#define TIMCAP1IE_LSB	(5)
#define TIMCAP0IE		(0x00000010)	// bit 4
#define TIMCAP0IE_LSB	(4)
#define TIMOVIE			(0x00000008)	// bit 3
#define TIMOVIE_LSB		(3)
#define TIMCMP2IE		(0x00000004)	// bit 2
#define TIMCMP2IE_LSB	(2)
#define TIMCMP1IE		(0x00000002)	// bit 1
#define TIMCMP1IE_LSB	(1)
#define TIMCMP0IE		(0x00000001)	// bit 0
#define TIMCMP0IE_LSB	(0)

// TIMxSR
#define TIMxSR_OFFSET				(4)
#define TIMxSR_PTR(_TIMERx_BASE)	MMR_08_PTR(_TIMERx_BASE, TIMxSR_OFFSET)

#define TCMP1			(0x80)	// bit 7
#define TCMP1_LSB		(7)
#define TCMP0			(0x40)	// bit 6
#define TCMP0_LSB		(6)
#define TIMCAP1IF		(0x20)	// bit 5
#define TIMCAP1IF_LSB	(5)
#define TIMCAP0IF		(0x10)	// bit 4
#define TIMCAP0IF_LSB	(4)
#define TIMOVIF			(0x08)	// bit 3
#define TIMOVIF_LSB		(3)
#define TIMCMP2IF		(0x04)	// bit 2
#define TIMCMP2IF_LSB	(2)
#define TIMCMP1IF		(0x02)	// bit 1
#define TIMCMP1IF_LSB	(1)
#define TIMCMP0IF		(0x01)	// bit 0
#define TIMCMP0IF_LSB	(0)

// TIMxVAL
#define TIMxVAL_OFFSET				(8)
#define TIMxVAL_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxVAL_OFFSET)

// TIMxCMP0
#define TIMxCMP0_OFFSET				(12)
#define TIMxCMP0_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP0_OFFSET)

// TIMxCMP1
#define TIMxCMP1_OFFSET				(16)
#define TIMxCMP1_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP1_OFFSET)

// TIMxCMP2
#define TIMxCMP2_OFFSET				(20)
#define TIMxCMP2_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP2_OFFSET)

// TIMxCAP0
#define TIMxCAP0_OFFSET				(24)
#define TIMxCAP0_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCAP0_OFFSET)

// TIMxCAP1
#define TIMxCAP1_OFFSET				(28)
#define TIMxCAP1_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCAP1_OFFSET)



/** SYSTEM **/
// SYSCLKCR
#define SYSCLKCR_OFFSET				(0)
#define SYSCLKCR_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, SYSCLKCR_OFFSET)

#define DCO1OFF			(0x0800)	// bit 11
#define DCO1OFF_LSB		(11)
#define DCO0OFF			(0x0400)	// bit 10
#define DCO0OFF_LSB		(10)
#define HFXTOFF			(0x0200)	// bit 9
#define HFXTOFF_LSB		(9)
#define LFXTOFF			(0x0100)	// bit 8
#define LFXTOFF_LSB		(8)
#define SMCLKOFF		(0x0040)	// bit 6
#define SMCLKOFF_LSB	(6)
#define SMCLKSEL_MASK	(0x0018)	// bits 4 downto 3
#define SMCLKSEL_LSB	(3)
#define SMCLKSEL_HFXT	(0x0000)
#define SMCLKSEL_LFXT	(0x0008)
#define SMCLKSEL_DCO0	(0x0010)
#define SMCLKSEL_DCO1	(0x0018)
#define MCLKSEL_MASK	(0x0003)	// bits 1 downto 0
#define MCLKSEL_LSB		(0)
#define MCLKSEL_HFXT	(0x0000)
#define MCLKSEL_SMCLK	(0x0001)
#define MCLKSEL_DCO0	(0x0002)
#define MCLKSEL_DCO1	(0x0003)

// CLKDIVCR
#define CLKDIVCR_OFFSET				(4)
#define CLKDIVCR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, CLKDIVCR_OFFSET)

#define SMCLKDIV_MASK	(0x38)	// bits 5 downto 3
#define SMCLKDIV_LSB	(3)
#define SMCLKDIV_1		(0x00)
#define SMCLKDIV_2		(0x08)
#define SMCLKDIV_4		(0x10)
#define SMCLKDIV_8		(0x18)
#define SMCLKDIV_16		(0x20)
#define SMCLKDIV_32		(0x28)
#define SMCLKDIV_64		(0x30)
#define SMCLKDIV_128	(0x38)
#define MCLKDIV_MASK	(0x07)	// bits 2 downto 0
#define MCLKDIV_LSB		(0)
#define MCLKDIV_1		(0x00)
#define MCLKDIV_2		(0x01)
#define MCLKDIV_4		(0x02)
#define MCLKDIV_8		(0x03)
#define MCLKDIV_16		(0x04)
#define MCLKDIV_32		(0x05)
#define MCLKDIV_64		(0x06)
#define MCLKDIV_128		(0x07)

// MEMPWRCR
#define MEMPWRCR_OFFSET				(8)
#define MEMPWRCR_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, MEMPWRCR_OFFSET)

#define SRAM15OFF		(0x8000)	// bit 15
#define SRAM15OFF_LSB	(15)
#define SRAM14OFF		(0x4000)	// bit 14
#define SRAM14OFF_LSB	(14)
#define SRAM13OFF		(0x2000)	// bit 13
#define SRAM13OFF_LSB	(13)
#define SRAM12OFF		(0x1000)	// bit 12
#define SRAM12OFF_LSB	(12)
#define SRAM11OFF		(0x0800)	// bit 11
#define SRAM11OFF_LSB	(11)
#define SRAM10OFF		(0x0400)	// bit 10
#define SRAM10OFF_LSB	(10)
#define SRAM09OFF		(0x0200)	// bit 9
#define SRAM09OFF_LSB	(9)
#define SRAM08OFF		(0x0100)	// bit 8
#define SRAM08OFF_LSB	(8)
#define SRAM07OFF		(0x0080)	// bit 7
#define SRAM07OFF_LSB	(7)
#define SRAM06OFF		(0x0040)	// bit 6
#define SRAM06OFF_LSB	(6)
#define SRAM05OFF		(0x0020)	// bit 5
#define SRAM05OFF_LSB	(5)
#define SRAM04OFF		(0x0010)	// bit 4
#define SRAM04OFF_LSB	(4)
#define SRAM03OFF		(0x0008)	// bit 3
#define SRAM03OFF_LSB	(3)
#define SRAM02OFF		(0x0004)	// bit 2
#define SRAM02OFF_LSB	(2)
#define ROMOFF			(0x0001)	// bit 0
#define ROMOFF_LSB		(0)

// CRCDATA
#define CRCDATA_OFFSET				(12)
#define CRCDATA_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, CRCDATA_OFFSET)

// CRCSTATE
#define CRCSTATE_OFFSET				(16)
#define CRCSTATE_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, CRCSTATE_OFFSET)

// IRQEN
#define IRQEN_OFFSET			(20)
#define IRQEN_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQEN_OFFSET)

// IRQPRI
#define IRQPRI_OFFSET				(24)
#define IRQPRI_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQPRI_OFFSET)

// WDTPASS
#define WDTPASS_OFFSET				(28)
#define WDTPASS_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, WDTPASS_OFFSET)

// WDTCR
#define WDTCR_OFFSET			(32)
#define WDTCR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, WDTCR_OFFSET)

#define HWRST				(0x40)	// bit 6
#define HWRST_LSB			(6)
#define WDTCDIV_MASK		(0x3C)	// bits 5 downto 2
#define WDTCDIV_LSB			(2)
#define WDTCDIV_65536		(0x00)
#define WDTCDIV_131072		(0x04)
#define WDTCDIV_262144		(0x08)
#define WDTCDIV_524288		(0x0C)
#define WDTCDIV_1048576		(0x10)
#define WDTCDIV_2097152		(0x14)
#define WDTCDIV_4194304		(0x18)
#define WDTCDIV_8388608		(0x1C)
#define WDTCDIV_16777216	(0x20)
#define WDTCDIV_33554432	(0x24)
#define WDTCDIV_67108864	(0x28)
#define WDTCDIV_134217728	(0x2C)
#define WDTCDIV_268435456	(0x30)
#define WDTCDIV_536870912	(0x34)
#define WDTCDIV_1073741824	(0x38)
#define WDTCDIV_2147483648	(0x3C)
#define WDTIE				(0x02)	// bit 1
#define WDTIE_LSB			(1)
#define WDTREN				(0x01)	// bit 0
#define WDTREN_LSB			(0)

// WDTSR
#define WDTSR_OFFSET			(36)
#define WDTSR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, WDTSR_OFFSET)

#define WDTIF		(0x02)	// bit 1
#define WDTIF_LSB	(1)
#define WDTRF		(0x01)	// bit 0
#define WDTRF_LSB	(0)

// WDTVAL
#define WDTVAL_OFFSET				(40)
#define WDTVAL_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, WDTVAL_OFFSET)

// DCO0FREQ
#define DCO0FREQ_OFFSET				(44)
#define DCO0FREQ_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, DCO0FREQ_OFFSET)

#define DCO0MFREQ_MASK	(0x0FFF)	// bits 11 downto 0
#define DCO0MFREQ_LSB	(0)

// DCO1FREQ
#define DCO1FREQ_OFFSET				(48)
#define DCO1FREQ_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, DCO1FREQ_OFFSET)

#define DCO1MFREQ_MASK	(0x0FFF)	// bits 11 downto 0
#define DCO1MFREQ_LSB	(0)

// TPMR
#define TPMR_OFFSET				(52)
#define TPMR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, TPMR_OFFSET)

// BIASCR
#define BIASCR_OFFSET				(56)
#define BIASCR_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, BIASCR_OFFSET)

#define EnBG			(0x0400)	// bit 10
#define EnBG_LSB		(10)
#define UseExtBias		(0x0200)	// bit 9
#define UseExtBias_LSB	(9)
#define UseBiasDac		(0x0100)	// bit 8
#define UseBiasDac_LSB	(8)
#define EnBiasBuf		(0x0080)	// bit 7
#define EnBiasBuf_LSB	(7)
#define EnBiasGen		(0x0040)	// bit 6
#define EnBiasGen_LSB	(6)
#define BiasAdj_MASK	(0x003F)	// bits 5 downto 0
#define BiasAdj_LSB		(0)

// BIASDBP
#define BIASDBP_OFFSET				(60)
#define BIASDBP_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, BIASDBP_OFFSET)

// BIASDBPC
#define BIASDBPC_OFFSET				(64)
#define BIASDBPC_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, BIASDBPC_OFFSET)

// BIASDBNC
#define BIASDBNC_OFFSET				(68)
#define BIASDBNC_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, BIASDBNC_OFFSET)

// BIASDBN
#define BIASDBN_OFFSET				(72)
#define BIASDBN_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, BIASDBN_OFFSET)



/** NNx **/
// NNxCR
#define NNxCR_OFFSET			(0)
#define NNxCR_PTR(_NNx_BASE)	MMR_32_PTR(_NNx_BASE, NNxCR_OFFSET)

#define NNCIE		(0x00400000)	// bit 22
#define NNCIE_LSB	(22)
#define NNCIF		(0x00200000)	// bit 21
#define NNCIF_LSB	(21)
#define NNLSIS		(0x00100000)	// bit 20
#define NNLSIS_LSB	(20)
#define NNCS		(0x00080000)	// bit 19
#define NNCS_LSB	(19)
#define NNBIAS		(0x00040000)	// bit 18
#define NNBIAS_LSB	(18)
#define NNAFS		(0x00020000)	// bit 17
#define NNAFS_LSB	(17)
#define NNRUN		(0x00010000)	// bit 16
#define NNRUN_LSB	(16)
#define NNO_MASK	(0x0000FF00)	// bits 15 downto 8
#define NNO_LSB		(8)
#define NNI_MASK	(0x000000FF)	// bits 7 downto 0
#define NNI_LSB		(0)

// NNxIVA
#define NNxIVA_OFFSET			(4)
#define NNxIVA_PTR(_NNx_BASE)	MMR_32_PTR(_NNx_BASE, NNxIVA_OFFSET)

#define NNIVA_MASK	(0x00003FFC)	// bits 13 downto 2
#define NNIVA_LSB	(2)

// NNxOVA
#define NNxOVA_OFFSET			(8)
#define NNxOVA_PTR(_NNx_BASE)	MMR_32_PTR(_NNx_BASE, NNxOVA_OFFSET)

#define NNOVA_MASK	(0x00003FFC)	// bits 13 downto 2
#define NNOVA_LSB	(2)

// NNxWMA
#define NNxWMA_OFFSET			(12)
#define NNxWMA_PTR(_NNx_BASE)	MMR_32_PTR(_NNx_BASE, NNxWMA_OFFSET)

#define NNWMA_MASK	(0x00003FFC)	// bits 13 downto 2
#define NNWMA_LSB	(2)

// NNxLSI
#define NNxLSI_OFFSET			(16)
#define NNxLSI_PTR(_NNx_BASE)	MMR_32_PTR(_NNx_BASE, NNxLSI_OFFSET)

// NNxLSO
#define NNxLSO_OFFSET			(20)
#define NNxLSO_PTR(_NNx_BASE)	MMR_16_PTR(_NNx_BASE, NNxLSO_OFFSET)



/** SARADCx **/
// SARADCxCR
#define SARADCxCR_OFFSET				(0)
#define SARADCxCR_PTR(_SARADCx_BASE)	MMR_16_PTR(_SARADCx_BASE, SARADCxCR_OFFSET)

#define SARADCCONTMEAS			(0x0100)	// bit 8
#define SARADCCONTMEAS_LSB		(8)
#define SARADCDATAIE			(0x0080)	// bit 7
#define SARADCDATAIE_LSB		(7)
#define SARADCDEBUG				(0x0040)	// bit 6
#define SARADCDEBUG_LSB			(6)
#define SARADCEN				(0x0020)	// bit 5
#define SARADCEN_LSB			(5)
#define SARADCSAMPLESTEP_MASK	(0x001E)	// bits 4 downto 1
#define SARADCSAMPLESTEP_LSB	(1)
#define SARADCRESET				(0x0001)	// bit 0
#define SARADCRESET_LSB			(0)

// SARADCxCDIV
#define SARADCxCDIV_OFFSET				(4)
#define SARADCxCDIV_PTR(_SARADCx_BASE)	MMR_08_PTR(_SARADCx_BASE, SARADCxCDIV_OFFSET)

#define SARADCCDIV_MASK	(0xFF)	// bits 7 downto 0
#define SARADCCDIV_LSB	(0)

// SARADCxSR
#define SARADCxSR_OFFSET				(8)
#define SARADCxSR_PTR(_SARADCx_BASE)	MMR_08_PTR(_SARADCx_BASE, SARADCxSR_OFFSET)

#define SARADCRDY			(0x08)	// bit 3
#define SARADCRDY_LSB		(3)
#define SARADCOVF			(0x04)	// bit 2
#define SARADCOVF_LSB		(2)
#define SARADCDATAVALID		(0x02)	// bit 1
#define SARADCDATAVALID_LSB	(1)
#define SARADCBUSY			(0x01)	// bit 0
#define SARADCBUSY_LSB		(0)

// SARADCxDATA
#define SARADCxDATA_OFFSET				(12)
#define SARADCxDATA_PTR(_SARADCx_BASE)	MMR_16_PTR(_SARADCx_BASE, SARADCxDATA_OFFSET)

#define SARADCDATA_MASK	(0x03FF)	// bits 9 downto 0
#define SARADCDATA_LSB	(0)

// SARADCxTPR
#define SARADCxTPR_OFFSET				(16)
#define SARADCxTPR_PTR(_SARADCx_BASE)	MMR_08_PTR(_SARADCx_BASE, SARADCxTPR_OFFSET)

#define SARADCDTP1SEL_MASK	(0xF0)	// bits 7 downto 4
#define SARADCDTP1SEL_LSB	(4)
#define SARADCDTP0SEL_MASK	(0x0F)	// bits 3 downto 0
#define SARADCDTP0SEL_LSB	(0)



/** AFEx **/
// AFExCR0
#define AFExCR0_OFFSET			(0)
#define AFExCR0_PTR(_AFEx_BASE)	MMR_32_PTR(_AFEx_BASE, AFExCR0_OFFSET)

#define AdcExtIn			(0x20000000)	// bit 29
#define AdcExtIn_LSB		(29)
#define AdcMidSel			(0x10000000)	// bit 28
#define AdcMidSel_LSB		(28)
#define AdcMuxTest			(0x08000000)	// bit 27
#define AdcMuxTest_LSB		(27)
#define BufCMMid			(0x04000000)	// bit 26
#define BufCMMid_LSB		(26)
#define CsaBiasSel			(0x02000000)	// bit 25
#define CsaBiasSel_LSB		(25)
#define CsaForceRst			(0x01000000)	// bit 24
#define CsaForceRst_LSB		(24)
#define CsaForceUnRst		(0x00800000)	// bit 23
#define CsaForceUnRst_LSB	(23)
#define CsaRstMode			(0x00400000)	// bit 22
#define CsaRstMode_LSB		(22)
#define EnAfe				(0x00200000)	// bit 21
#define EnAfe_LSB			(21)
#define EnCM				(0x00100000)	// bit 20
#define EnCM_LSB			(20)
#define EnCsa				(0x00080000)	// bit 19
#define EnCsa_LSB			(19)
#define EnAdc				(0x00040000)	// bit 18
#define EnAdc_LSB			(18)
#define EnThresh			(0x00020000)	// bit 17
#define EnThresh_LSB		(17)
#define EnDma				(0x00010000)	// bit 16
#define EnDma_LSB			(16)
#define EnPURej				(0x00008000)	// bit 15
#define EnPURej_LSB			(15)
#define EnPsd				(0x00004000)	// bit 14
#define EnPsd_LSB			(14)
#define EnBLLT				(0x00002000)	// bit 13
#define EnBLLT_LSB			(13)
#define ForceThresh			(0x00001000)	// bit 12
#define ForceThresh_LSB		(12)
#define OpenInput			(0x00000800)	// bit 11
#define OpenInput_LSB		(11)
#define PsdOrder			(0x00000400)	// bit 10
#define PsdOrder_LSB		(10)
#define PUPara				(0x00000200)	// bit 9
#define PUPara_LSB			(9)
#define RamOff				(0x00000100)	// bit 8
#define RamOff_LSB			(8)
#define RejectMode			(0x00000080)	// bit 7
#define RejectMode_LSB		(7)
#define SHPwrMode			(0x00000040)	// bit 6
#define SHPwrMode_LSB		(6)
#define ThreshSel_MASK		(0x00000030)	// bits 5 downto 4
#define ThreshSel_LSB		(4)
#define PulseDoneWait		(0x00000008)	// bit 3
#define PulseDoneWait_LSB	(3)
#define PulseDoneIE			(0x00000004)	// bit 2
#define PulseDoneIE_LSB		(2)
#define AdcConvDoneIE		(0x00000002)	// bit 1
#define AdcConvDoneIE_LSB	(1)
#define PsdFullIE			(0x00000001)	// bit 0
#define PsdFullIE_LSB		(0)

// AFExCR1
#define AFExCR1_OFFSET			(4)
#define AFExCR1_PTR(_AFEx_BASE)	MMR_32_PTR(_AFEx_BASE, AFExCR1_OFFSET)

#define AdcClkDivN_MASK	(0xE0000000)	// bits 31 downto 29
#define AdcClkDivN_LSB	(29)
#define AdcClkDivM_MASK	(0x1E000000)	// bits 28 downto 25
#define AdcClkDivM_LSB	(25)
#define AdcCp_MASK		(0x01FC0000)	// bits 24 downto 18
#define AdcCp_LSB		(18)
#define AdcSampT_MASK	(0x00038000)	// bits 17 downto 15
#define AdcSampT_LSB	(15)
#define ClkSel_MASK		(0x00006000)	// bits 14 downto 13
#define ClkSel_LSB		(13)
#define CMSHClkDiv_MASK	(0x00001E00)	// bits 12 downto 9
#define CMSHClkDiv_LSB	(9)
#define CsaCmAdj_MASK	(0x000001C0)	// bits 8 downto 6
#define CsaCmAdj_LSB	(6)
#define ISink_MASK		(0x0000003F)	// bits 5 downto 0
#define ISink_LSB		(0)

// AFExCFB
#define AFExCFB_OFFSET			(8)
#define AFExCFB_PTR(_AFEx_BASE)	MMR_08_PTR(_AFEx_BASE, AFExCFB_OFFSET)

// AFExRFB
#define AFExRFB_OFFSET			(12)
#define AFExRFB_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExRFB_OFFSET)

// AFExTHR
#define AFExTHR_OFFSET			(16)
#define AFExTHR_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExTHR_OFFSET)

// AFExTPR
#define AFExTPR_OFFSET			(20)
#define AFExTPR_PTR(_AFEx_BASE)	MMR_32_PTR(_AFEx_BASE, AFExTPR_OFFSET)

#define AfeAtp1BufEn		(0x20000000)	// bit 29
#define AfeAtp1BufEn_LSB	(29)
#define AfeAtp1Sel_MASK		(0x1E000000)	// bits 28 downto 25
#define AfeAtp1Sel_LSB		(25)
#define AfeAtp0BufEn		(0x01000000)	// bit 24
#define AfeAtp0BufEn_LSB	(24)
#define AfeAtp0Sel_MASK		(0x00F00000)	// bits 23 downto 20
#define AfeAtp0Sel_LSB		(20)
#define AfeDtp3Sel_MASK		(0x000F8000)	// bits 19 downto 15
#define AfeDtp3Sel_LSB		(15)
#define AfeDtp2Sel_MASK		(0x00007C00)	// bits 14 downto 10
#define AfeDtp2Sel_LSB		(10)
#define AfeDtp1Sel_MASK		(0x000003E0)	// bits 9 downto 5
#define AfeDtp1Sel_LSB		(5)
#define AfeDtp0Sel_MASK		(0x0000001F)	// bits 4 downto 0
#define AfeDtp0Sel_LSB		(0)

// AFExSPT
#define AFExSPT_OFFSET			(24)
#define AFExSPT_PTR(_AFEx_BASE)	MMR_08_PTR(_AFEx_BASE, AFExSPT_OFFSET)

// AFExPIT
#define AFExPIT_OFFSET			(28)
#define AFExPIT_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExPIT_OFFSET)

// AFExEIT
#define AFExEIT_OFFSET			(32)
#define AFExEIT_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExEIT_OFFSET)

// AFExLIT
#define AFExLIT_OFFSET			(36)
#define AFExLIT_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExLIT_OFFSET)

// AFExRJT
#define AFExRJT_OFFSET			(40)
#define AFExRJT_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExRJT_OFFSET)

// AFExRST
#define AFExRST_OFFSET			(44)
#define AFExRST_PTR(_AFEx_BASE)	MMR_08_PTR(_AFEx_BASE, AFExRST_OFFSET)

// AFExAOFST
#define AFExAOFST_OFFSET			(48)
#define AFExAOFST_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExAOFST_OFFSET)

// AFExBLLT
#define AFExBLLT_OFFSET				(52)
#define AFExBLLT_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExBLLT_OFFSET)

// AFExCSAREF
#define AFExCSAREF_OFFSET			(56)
#define AFExCSAREF_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExCSAREF_OFFSET)

// AFExCSABP
#define AFExCSABP_OFFSET			(60)
#define AFExCSABP_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExCSABP_OFFSET)

// AFExCSABPC
#define AFExCSABPC_OFFSET			(64)
#define AFExCSABPC_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExCSABPC_OFFSET)

// AFExCSABNC
#define AFExCSABNC_OFFSET			(68)
#define AFExCSABNC_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExCSABNC_OFFSET)

// AFExCSABN
#define AFExCSABN_OFFSET			(72)
#define AFExCSABN_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExCSABN_OFFSET)

// AFExCMSHR
#define AFExCMSHR_OFFSET			(76)
#define AFExCMSHR_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExCMSHR_OFFSET)

// AFExCLPF
#define AFExCLPF_OFFSET				(80)
#define AFExCLPF_PTR(_AFEx_BASE)	MMR_08_PTR(_AFEx_BASE, AFExCLPF_OFFSET)

// AFExSR
#define AFExSR_OFFSET			(84)
#define AFExSR_PTR(_AFEx_BASE)	MMR_08_PTR(_AFEx_BASE, AFExSR_OFFSET)

#define DTP1VAL				(0x80)	// bit 7
#define DTP1VAL_LSB			(7)
#define DTP0VAL				(0x40)	// bit 6
#define DTP0VAL_LSB			(6)
#define AdcActive			(0x20)	// bit 5
#define AdcActive_LSB		(5)
#define AdcDataReady		(0x10)	// bit 4
#define AdcDataReady_LSB	(4)
#define DmaEnabled			(0x08)	// bit 3
#define DmaEnabled_LSB		(3)
#define PulseDone			(0x04)	// bit 2
#define PulseDone_LSB		(2)
#define AdcConvDone			(0x02)	// bit 1
#define AdcConvDone_LSB		(1)
#define PsdFull				(0x01)	// bit 0
#define PsdFull_LSB			(0)

// AFExADCVAL
#define AFExADCVAL_OFFSET			(88)
#define AFExADCVAL_PTR(_AFEx_BASE)	MMR_16_PTR(_AFEx_BASE, AFExADCVAL_OFFSET)

// AFExVPC
#define AFExVPC_OFFSET			(92)
#define AFExVPC_PTR(_AFEx_BASE)	MMR_32_PTR(_AFEx_BASE, AFExVPC_OFFSET)

// AFExTPC
#define AFExTPC_OFFSET			(96)
#define AFExTPC_PTR(_AFEx_BASE)	MMR_32_PTR(_AFEx_BASE, AFExTPC_OFFSET)



/** I2Cx **/
// I2CxCR
#define I2CxCR_OFFSET			(0)
#define I2CxCR_PTR(_I2Cx_BASE)	MMR_32_PTR(_I2Cx_BASE, I2CxCR_OFFSET)

#define I2CMEN			(0x00200000)	// bit 21
#define I2CMEN_LSB		(21)
#define I2CSEN			(0x00100000)	// bit 20
#define I2CSEN_LSB		(20)
#define I2CSN			(0x00080000)	// bit 19
#define I2CSN_LSB		(19)
#define I2CSCS			(0x00040000)	// bit 18
#define I2CSCS_LSB		(18)
#define I2CGCE			(0x00020000)	// bit 17
#define I2CGCE_LSB		(17)
#define I2CMDIV_MASK	(0x0001E000)	// bits 16 downto 13
#define I2CMDIV_LSB		(13)
#define I2CMDIV_1		(0x00000000)
#define I2CMDIV_2		(0x00002000)
#define I2CMDIV_4		(0x00004000)
#define I2CMDIV_8		(0x00006000)
#define I2CMDIV_16		(0x00008000)
#define I2CMDIV_32		(0x0000A000)
#define I2CMDIV_64		(0x0000C000)
#define I2CMDIV_128		(0x0000E000)
#define I2CMDIV_256		(0x00010000)
#define I2CMDIV_512		(0x00012000)
#define I2CMDIV_1024	(0x00014000)
#define I2CMDIV_2048	(0x00016000)
#define I2CMDIV_4096	(0x00018000)
#define I2CMDIV_8192	(0x0001A000)
#define I2CMDIV_16384	(0x0001C000)
#define I2CMDIV_32768	(0x0001E000)
#define I2CSAIE			(0x00001000)	// bit 12
#define I2CSAIE_LSB		(12)
#define I2CSTXEIE		(0x00000800)	// bit 11
#define I2CSTXEIE_LSB	(11)
#define I2CSOVFIE		(0x00000400)	// bit 10
#define I2CSOVFIE_LSB	(10)
#define I2CSNRIE		(0x00000200)	// bit 9
#define I2CSNRIE_LSB	(9)
#define I2CSXCIE		(0x00000100)	// bit 8
#define I2CSXCIE_LSB	(8)
#define I2CMSTSIE		(0x00000080)	// bit 7
#define I2CMSTSIE_LSB	(7)
#define I2CMSPSIE		(0x00000040)	// bit 6
#define I2CMSPSIE_LSB	(6)
#define I2CMARBIE		(0x00000020)	// bit 5
#define I2CMARBIE_LSB	(5)
#define I2CMTXEIE		(0x00000010)	// bit 4
#define I2CMTXEIE_LSB	(4)
#define I2CMNRIE		(0x00000008)	// bit 3
#define I2CMNRIE_LSB	(3)
#define I2CMXCIE		(0x00000004)	// bit 2
#define I2CMXCIE_LSB	(2)
#define I2CSTRIE		(0x00000002)	// bit 1
#define I2CSTRIE_LSB	(1)
#define I2CSPRIE		(0x00000001)	// bit 0
#define I2CSPRIE_LSB	(0)

// I2CxFCR
#define I2CxFCR_OFFSET			(4)
#define I2CxFCR_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxFCR_OFFSET)

#define I2CSC		(0x08)	// bit 3
#define I2CSC_LSB	(3)
#define I2CMST		(0x04)	// bit 2
#define I2CMST_LSB	(2)
#define I2CMSP		(0x02)	// bit 1
#define I2CMSP_LSB	(1)
#define I2CMRB		(0x01)	// bit 0
#define I2CMRB_LSB	(0)

// I2CxSR
#define I2CxSR_OFFSET			(8)
#define I2CxSR_PTR(_I2Cx_BASE)	MMR_16_PTR(_I2Cx_BASE, I2CxSR_OFFSET)

#define I2CBS		(0x8000)	// bit 15
#define I2CBS_LSB	(15)
#define I2CMCB		(0x4000)	// bit 14
#define I2CMCB_LSB	(14)
#define I2CSTM		(0x2000)	// bit 13
#define I2CSTM_LSB	(13)
#define I2CSA		(0x1000)	// bit 12
#define I2CSA_LSB	(12)
#define I2CSTXE		(0x0800)	// bit 11
#define I2CSTXE_LSB	(11)
#define I2CSOVF		(0x0400)	// bit 10
#define I2CSOVF_LSB	(10)
#define I2CSNR		(0x0200)	// bit 9
#define I2CSNR_LSB	(9)
#define I2CSXC		(0x0100)	// bit 8
#define I2CSXC_LSB	(8)
#define I2CMSTS		(0x0080)	// bit 7
#define I2CMSTS_LSB	(7)
#define I2CMSPS		(0x0040)	// bit 6
#define I2CMSPS_LSB	(6)
#define I2CMARB		(0x0020)	// bit 5
#define I2CMARB_LSB	(5)
#define I2CMTXE		(0x0010)	// bit 4
#define I2CMTXE_LSB	(4)
#define I2CMNR		(0x0008)	// bit 3
#define I2CMNR_LSB	(3)
#define I2CMXC		(0x0004)	// bit 2
#define I2CMXC_LSB	(2)
#define I2CSTR		(0x0002)	// bit 1
#define I2CSTR_LSB	(1)
#define I2CSPR		(0x0001)	// bit 0
#define I2CSPR_LSB	(0)

// I2CxMTX
#define I2CxMTX_OFFSET			(12)
#define I2CxMTX_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxMTX_OFFSET)

// I2CxMRX
#define I2CxMRX_OFFSET			(16)
#define I2CxMRX_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxMRX_OFFSET)

// I2CxSTX
#define I2CxSTX_OFFSET			(20)
#define I2CxSTX_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxSTX_OFFSET)

// I2CxSRX
#define I2CxSRX_OFFSET			(24)
#define I2CxSRX_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxSRX_OFFSET)

// I2CxAR
#define I2CxAR_OFFSET			(28)
#define I2CxAR_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxAR_OFFSET)

// I2CxAMR
#define I2CxAMR_OFFSET			(32)
#define I2CxAMR_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxAMR_OFFSET)



/********** Peripheral and Register Memory Map **********/

/** GPIO0 **/
#define GPIO0_BASE			(0x4000)

#define P0IN_ADDRESS		(0x4000)
#define P0IN				MMR_08_BIT_MACRO(P0IN_ADDRESS)
#define P0OUT_ADDRESS		(0x4004)
#define P0OUT				MMR_08_BIT_MACRO(P0OUT_ADDRESS)
#define P0OUTS_ADDRESS		(0x4008)
#define P0OUTS				MMR_08_BIT_MACRO(P0OUTS_ADDRESS)
#define P0OUTC_ADDRESS		(0x400C)
#define P0OUTC				MMR_08_BIT_MACRO(P0OUTC_ADDRESS)
#define P0OUTT_ADDRESS		(0x4010)
#define P0OUTT				MMR_32_BIT_MACRO(P0OUTT_ADDRESS)
#define P0DIR_ADDRESS		(0x4014)
#define P0DIR				MMR_08_BIT_MACRO(P0DIR_ADDRESS)
#define P0IFG_ADDRESS		(0x4018)
#define P0IFG				MMR_08_BIT_MACRO(P0IFG_ADDRESS)
#define P0IES_ADDRESS		(0x401C)
#define P0IES				MMR_08_BIT_MACRO(P0IES_ADDRESS)
#define P0IE_ADDRESS		(0x4020)
#define P0IE				MMR_08_BIT_MACRO(P0IE_ADDRESS)
#define P0SEL_ADDRESS		(0x4024)
#define P0SEL				MMR_08_BIT_MACRO(P0SEL_ADDRESS)
#define P0REN_ADDRESS		(0x4028)
#define P0REN				MMR_08_BIT_MACRO(P0REN_ADDRESS)



/** GPIO1 **/
#define GPIO1_BASE			(0x4100)

#define P1IN_ADDRESS		(0x4100)
#define P1IN				MMR_08_BIT_MACRO(P1IN_ADDRESS)
#define P1OUT_ADDRESS		(0x4104)
#define P1OUT				MMR_08_BIT_MACRO(P1OUT_ADDRESS)
#define P1OUTS_ADDRESS		(0x4108)
#define P1OUTS				MMR_08_BIT_MACRO(P1OUTS_ADDRESS)
#define P1OUTC_ADDRESS		(0x410C)
#define P1OUTC				MMR_08_BIT_MACRO(P1OUTC_ADDRESS)
#define P1OUTT_ADDRESS		(0x4110)
#define P1OUTT				MMR_32_BIT_MACRO(P1OUTT_ADDRESS)
#define P1DIR_ADDRESS		(0x4114)
#define P1DIR				MMR_08_BIT_MACRO(P1DIR_ADDRESS)
#define P1IFG_ADDRESS		(0x4118)
#define P1IFG				MMR_08_BIT_MACRO(P1IFG_ADDRESS)
#define P1IES_ADDRESS		(0x411C)
#define P1IES				MMR_08_BIT_MACRO(P1IES_ADDRESS)
#define P1IE_ADDRESS		(0x4120)
#define P1IE				MMR_08_BIT_MACRO(P1IE_ADDRESS)
#define P1SEL_ADDRESS		(0x4124)
#define P1SEL				MMR_08_BIT_MACRO(P1SEL_ADDRESS)
#define P1REN_ADDRESS		(0x4128)
#define P1REN				MMR_08_BIT_MACRO(P1REN_ADDRESS)



/** SPI0 **/
#define SPI0_BASE			(0x4200)

#define SPI0CR_ADDRESS		(0x4200)
#define SPI0CR				MMR_32_BIT_MACRO(SPI0CR_ADDRESS)
#define SPI0SR_ADDRESS		(0x4204)
#define SPI0SR				MMR_08_BIT_MACRO(SPI0SR_ADDRESS)
#define SPI0TX_ADDRESS		(0x4208)
#define SPI0TX				MMR_32_BIT_MACRO(SPI0TX_ADDRESS)
#define SPI0RX_ADDRESS		(0x420C)
#define SPI0RX				MMR_32_BIT_MACRO(SPI0RX_ADDRESS)
#define SPI0FOS_ADDRESS		(0x4210)
#define SPI0FOS				MMR_32_BIT_MACRO(SPI0FOS_ADDRESS)



/** SPI1 **/
#define SPI1_BASE			(0x4300)

#define SPI1CR_ADDRESS		(0x4300)
#define SPI1CR				MMR_32_BIT_MACRO(SPI1CR_ADDRESS)
#define SPI1SR_ADDRESS		(0x4304)
#define SPI1SR				MMR_08_BIT_MACRO(SPI1SR_ADDRESS)
#define SPI1TX_ADDRESS		(0x4308)
#define SPI1TX				MMR_32_BIT_MACRO(SPI1TX_ADDRESS)
#define SPI1RX_ADDRESS		(0x430C)
#define SPI1RX				MMR_32_BIT_MACRO(SPI1RX_ADDRESS)
#define SPI1FOS_ADDRESS		(0x4310)
#define SPI1FOS				MMR_32_BIT_MACRO(SPI1FOS_ADDRESS)



/** UART0 **/
#define UART0_BASE			(0x4400)

#define UART0CR_ADDRESS		(0x4400)
#define UART0CR				MMR_08_BIT_MACRO(UART0CR_ADDRESS)
#define UART0SR_ADDRESS		(0x4404)
#define UART0SR				MMR_08_BIT_MACRO(UART0SR_ADDRESS)
#define UART0BR_ADDRESS		(0x4408)
#define UART0BR				MMR_16_BIT_MACRO(UART0BR_ADDRESS)
#define UART0RX_ADDRESS		(0x440C)
#define UART0RX				MMR_08_BIT_MACRO(UART0RX_ADDRESS)
#define UART0TX_ADDRESS		(0x4410)
#define UART0TX				MMR_08_BIT_MACRO(UART0TX_ADDRESS)



/** UART1 **/
#define UART1_BASE			(0x4500)

#define UART1CR_ADDRESS		(0x4500)
#define UART1CR				MMR_08_BIT_MACRO(UART1CR_ADDRESS)
#define UART1SR_ADDRESS		(0x4504)
#define UART1SR				MMR_08_BIT_MACRO(UART1SR_ADDRESS)
#define UART1BR_ADDRESS		(0x4508)
#define UART1BR				MMR_16_BIT_MACRO(UART1BR_ADDRESS)
#define UART1RX_ADDRESS		(0x450C)
#define UART1RX				MMR_08_BIT_MACRO(UART1RX_ADDRESS)
#define UART1TX_ADDRESS		(0x4510)
#define UART1TX				MMR_08_BIT_MACRO(UART1TX_ADDRESS)



/** TIMER0 **/
#define TIMER0_BASE			(0x4600)

#define TIM0CR_ADDRESS		(0x4600)
#define TIM0CR				MMR_32_BIT_MACRO(TIM0CR_ADDRESS)
#define TIM0SR_ADDRESS		(0x4604)
#define TIM0SR				MMR_08_BIT_MACRO(TIM0SR_ADDRESS)
#define TIM0VAL_ADDRESS		(0x4608)
#define TIM0VAL				MMR_32_BIT_MACRO(TIM0VAL_ADDRESS)
#define TIM0CMP0_ADDRESS	(0x460C)
#define TIM0CMP0			MMR_32_BIT_MACRO(TIM0CMP0_ADDRESS)
#define TIM0CMP1_ADDRESS	(0x4610)
#define TIM0CMP1			MMR_32_BIT_MACRO(TIM0CMP1_ADDRESS)
#define TIM0CMP2_ADDRESS	(0x4614)
#define TIM0CMP2			MMR_32_BIT_MACRO(TIM0CMP2_ADDRESS)
#define TIM0CAP0_ADDRESS	(0x4618)
#define TIM0CAP0			MMR_32_BIT_MACRO(TIM0CAP0_ADDRESS)
#define TIM0CAP1_ADDRESS	(0x461C)
#define TIM0CAP1			MMR_32_BIT_MACRO(TIM0CAP1_ADDRESS)



/** TIMER1 **/
#define TIMER1_BASE			(0x4700)

#define TIM1CR_ADDRESS		(0x4700)
#define TIM1CR				MMR_32_BIT_MACRO(TIM1CR_ADDRESS)
#define TIM1SR_ADDRESS		(0x4704)
#define TIM1SR				MMR_08_BIT_MACRO(TIM1SR_ADDRESS)
#define TIM1VAL_ADDRESS		(0x4708)
#define TIM1VAL				MMR_32_BIT_MACRO(TIM1VAL_ADDRESS)
#define TIM1CMP0_ADDRESS	(0x470C)
#define TIM1CMP0			MMR_32_BIT_MACRO(TIM1CMP0_ADDRESS)
#define TIM1CMP1_ADDRESS	(0x4710)
#define TIM1CMP1			MMR_32_BIT_MACRO(TIM1CMP1_ADDRESS)
#define TIM1CMP2_ADDRESS	(0x4714)
#define TIM1CMP2			MMR_32_BIT_MACRO(TIM1CMP2_ADDRESS)
#define TIM1CAP0_ADDRESS	(0x4718)
#define TIM1CAP0			MMR_32_BIT_MACRO(TIM1CAP0_ADDRESS)
#define TIM1CAP1_ADDRESS	(0x471C)
#define TIM1CAP1			MMR_32_BIT_MACRO(TIM1CAP1_ADDRESS)



/** GPIO2 **/
#define GPIO2_BASE			(0x4800)

#define P2IN_ADDRESS		(0x4800)
#define P2IN				MMR_08_BIT_MACRO(P2IN_ADDRESS)
#define P2OUT_ADDRESS		(0x4804)
#define P2OUT				MMR_08_BIT_MACRO(P2OUT_ADDRESS)
#define P2OUTS_ADDRESS		(0x4808)
#define P2OUTS				MMR_08_BIT_MACRO(P2OUTS_ADDRESS)
#define P2OUTC_ADDRESS		(0x480C)
#define P2OUTC				MMR_08_BIT_MACRO(P2OUTC_ADDRESS)
#define P2OUTT_ADDRESS		(0x4810)
#define P2OUTT				MMR_32_BIT_MACRO(P2OUTT_ADDRESS)
#define P2DIR_ADDRESS		(0x4814)
#define P2DIR				MMR_08_BIT_MACRO(P2DIR_ADDRESS)
#define P2IFG_ADDRESS		(0x4818)
#define P2IFG				MMR_08_BIT_MACRO(P2IFG_ADDRESS)
#define P2IES_ADDRESS		(0x481C)
#define P2IES				MMR_08_BIT_MACRO(P2IES_ADDRESS)
#define P2IE_ADDRESS		(0x4820)
#define P2IE				MMR_08_BIT_MACRO(P2IE_ADDRESS)
#define P2SEL_ADDRESS		(0x4824)
#define P2SEL				MMR_08_BIT_MACRO(P2SEL_ADDRESS)
#define P2REN_ADDRESS		(0x4828)
#define P2REN				MMR_08_BIT_MACRO(P2REN_ADDRESS)



/** SYSTEM **/
#define SYSTEM_BASE			(0x4900)

#define SYSCLKCR_ADDRESS	(0x4900)
#define SYSCLKCR			MMR_16_BIT_MACRO(SYSCLKCR_ADDRESS)
#define CLKDIVCR_ADDRESS	(0x4904)
#define CLKDIVCR			MMR_08_BIT_MACRO(CLKDIVCR_ADDRESS)
#define MEMPWRCR_ADDRESS	(0x4908)
#define MEMPWRCR			MMR_16_BIT_MACRO(MEMPWRCR_ADDRESS)
#define CRCDATA_ADDRESS		(0x490C)
#define CRCDATA				MMR_08_BIT_MACRO(CRCDATA_ADDRESS)
#define CRCSTATE_ADDRESS	(0x4910)
#define CRCSTATE			MMR_16_BIT_MACRO(CRCSTATE_ADDRESS)
#define IRQEN_ADDRESS		(0x4914)
#define IRQEN				MMR_32_BIT_MACRO(IRQEN_ADDRESS)
#define IRQPRI_ADDRESS		(0x4918)
#define IRQPRI				MMR_32_BIT_MACRO(IRQPRI_ADDRESS)
#define WDTPASS_ADDRESS		(0x491C)
#define WDTPASS				MMR_32_BIT_MACRO(WDTPASS_ADDRESS)
#define WDTCR_ADDRESS		(0x4920)
#define WDTCR				MMR_08_BIT_MACRO(WDTCR_ADDRESS)
#define WDTSR_ADDRESS		(0x4924)
#define WDTSR				MMR_08_BIT_MACRO(WDTSR_ADDRESS)
#define WDTVAL_ADDRESS		(0x4928)
#define WDTVAL				MMR_32_BIT_MACRO(WDTVAL_ADDRESS)
#define DCO0FREQ_ADDRESS	(0x492C)
#define DCO0FREQ			MMR_16_BIT_MACRO(DCO0FREQ_ADDRESS)
#define DCO1FREQ_ADDRESS	(0x4930)
#define DCO1FREQ			MMR_16_BIT_MACRO(DCO1FREQ_ADDRESS)
#define TPMR_ADDRESS		(0x4934)
#define TPMR				MMR_08_BIT_MACRO(TPMR_ADDRESS)
#define BIASCR_ADDRESS		(0x4938)
#define BIASCR				MMR_16_BIT_MACRO(BIASCR_ADDRESS)
#define BIASDBP_ADDRESS		(0x493C)
#define BIASDBP				MMR_16_BIT_MACRO(BIASDBP_ADDRESS)
#define BIASDBPC_ADDRESS	(0x4940)
#define BIASDBPC			MMR_16_BIT_MACRO(BIASDBPC_ADDRESS)
#define BIASDBNC_ADDRESS	(0x4944)
#define BIASDBNC			MMR_16_BIT_MACRO(BIASDBNC_ADDRESS)
#define BIASDBN_ADDRESS		(0x4948)
#define BIASDBN				MMR_16_BIT_MACRO(BIASDBN_ADDRESS)



/** NN0 **/
#define NN0_BASE			(0x4A00)

#define NN0CR_ADDRESS		(0x4A00)
#define NN0CR				MMR_32_BIT_MACRO(NN0CR_ADDRESS)
#define NN0IVA_ADDRESS		(0x4A04)
#define NN0IVA				MMR_32_BIT_MACRO(NN0IVA_ADDRESS)
#define NN0OVA_ADDRESS		(0x4A08)
#define NN0OVA				MMR_32_BIT_MACRO(NN0OVA_ADDRESS)
#define NN0WMA_ADDRESS		(0x4A0C)
#define NN0WMA				MMR_32_BIT_MACRO(NN0WMA_ADDRESS)
#define NN0LSI_ADDRESS		(0x4A10)
#define NN0LSI				MMR_32_BIT_MACRO(NN0LSI_ADDRESS)
#define NN0LSO_ADDRESS		(0x4A14)
#define NN0LSO				MMR_16_BIT_MACRO(NN0LSO_ADDRESS)



/** SARADC0 **/
#define SARADC0_BASE		(0x4B00)

#define SARADC0CR_ADDRESS	(0x4B00)
#define SARADC0CR			MMR_16_BIT_MACRO(SARADC0CR_ADDRESS)
#define SARADC0CDIV_ADDRESS	(0x4B04)
#define SARADC0CDIV			MMR_08_BIT_MACRO(SARADC0CDIV_ADDRESS)
#define SARADC0SR_ADDRESS	(0x4B08)
#define SARADC0SR			MMR_08_BIT_MACRO(SARADC0SR_ADDRESS)
#define SARADC0DATA_ADDRESS	(0x4B0C)
#define SARADC0DATA			MMR_16_BIT_MACRO(SARADC0DATA_ADDRESS)
#define SARADC0TPR_ADDRESS	(0x4B10)
#define SARADC0TPR			MMR_08_BIT_MACRO(SARADC0TPR_ADDRESS)



/** AFE0 **/
#define AFE0_BASE			(0x4C00)

#define AFE0CR0_ADDRESS		(0x4C00)
#define AFE0CR0				MMR_32_BIT_MACRO(AFE0CR0_ADDRESS)
#define AFE0CR1_ADDRESS		(0x4C04)
#define AFE0CR1				MMR_32_BIT_MACRO(AFE0CR1_ADDRESS)
#define AFE0CFB_ADDRESS		(0x4C08)
#define AFE0CFB				MMR_08_BIT_MACRO(AFE0CFB_ADDRESS)
#define AFE0RFB_ADDRESS		(0x4C0C)
#define AFE0RFB				MMR_16_BIT_MACRO(AFE0RFB_ADDRESS)
#define AFE0THR_ADDRESS		(0x4C10)
#define AFE0THR				MMR_16_BIT_MACRO(AFE0THR_ADDRESS)
#define AFE0TPR_ADDRESS		(0x4C14)
#define AFE0TPR				MMR_32_BIT_MACRO(AFE0TPR_ADDRESS)
#define AFE0SPT_ADDRESS		(0x4C18)
#define AFE0SPT				MMR_08_BIT_MACRO(AFE0SPT_ADDRESS)
#define AFE0PIT_ADDRESS		(0x4C1C)
#define AFE0PIT				MMR_16_BIT_MACRO(AFE0PIT_ADDRESS)
#define AFE0EIT_ADDRESS		(0x4C20)
#define AFE0EIT				MMR_16_BIT_MACRO(AFE0EIT_ADDRESS)
#define AFE0LIT_ADDRESS		(0x4C24)
#define AFE0LIT				MMR_16_BIT_MACRO(AFE0LIT_ADDRESS)
#define AFE0RJT_ADDRESS		(0x4C28)
#define AFE0RJT				MMR_16_BIT_MACRO(AFE0RJT_ADDRESS)
#define AFE0RST_ADDRESS		(0x4C2C)
#define AFE0RST				MMR_08_BIT_MACRO(AFE0RST_ADDRESS)
#define AFE0AOFST_ADDRESS	(0x4C30)
#define AFE0AOFST			MMR_16_BIT_MACRO(AFE0AOFST_ADDRESS)
#define AFE0BLLT_ADDRESS	(0x4C34)
#define AFE0BLLT			MMR_16_BIT_MACRO(AFE0BLLT_ADDRESS)
#define AFE0CSAREF_ADDRESS	(0x4C38)
#define AFE0CSAREF			MMR_16_BIT_MACRO(AFE0CSAREF_ADDRESS)
#define AFE0CSABP_ADDRESS	(0x4C3C)
#define AFE0CSABP			MMR_16_BIT_MACRO(AFE0CSABP_ADDRESS)
#define AFE0CSABPC_ADDRESS	(0x4C40)
#define AFE0CSABPC			MMR_16_BIT_MACRO(AFE0CSABPC_ADDRESS)
#define AFE0CSABNC_ADDRESS	(0x4C44)
#define AFE0CSABNC			MMR_16_BIT_MACRO(AFE0CSABNC_ADDRESS)
#define AFE0CSABN_ADDRESS	(0x4C48)
#define AFE0CSABN			MMR_16_BIT_MACRO(AFE0CSABN_ADDRESS)
#define AFE0CMSHR_ADDRESS	(0x4C4C)
#define AFE0CMSHR			MMR_16_BIT_MACRO(AFE0CMSHR_ADDRESS)
#define AFE0CLPF_ADDRESS	(0x4C50)
#define AFE0CLPF			MMR_08_BIT_MACRO(AFE0CLPF_ADDRESS)
#define AFE0SR_ADDRESS		(0x4C54)
#define AFE0SR				MMR_08_BIT_MACRO(AFE0SR_ADDRESS)
#define AFE0ADCVAL_ADDRESS	(0x4C58)
#define AFE0ADCVAL			MMR_16_BIT_MACRO(AFE0ADCVAL_ADDRESS)
#define AFE0VPC_ADDRESS		(0x4C5C)
#define AFE0VPC				MMR_32_BIT_MACRO(AFE0VPC_ADDRESS)
#define AFE0TPC_ADDRESS		(0x4C60)
#define AFE0TPC				MMR_32_BIT_MACRO(AFE0TPC_ADDRESS)



/** GPIO3 **/
#define GPIO3_BASE			(0x4D00)

#define P3IN_ADDRESS		(0x4D00)
#define P3IN				MMR_08_BIT_MACRO(P3IN_ADDRESS)
#define P3OUT_ADDRESS		(0x4D04)
#define P3OUT				MMR_08_BIT_MACRO(P3OUT_ADDRESS)
#define P3OUTS_ADDRESS		(0x4D08)
#define P3OUTS				MMR_08_BIT_MACRO(P3OUTS_ADDRESS)
#define P3OUTC_ADDRESS		(0x4D0C)
#define P3OUTC				MMR_08_BIT_MACRO(P3OUTC_ADDRESS)
#define P3OUTT_ADDRESS		(0x4D10)
#define P3OUTT				MMR_32_BIT_MACRO(P3OUTT_ADDRESS)
#define P3DIR_ADDRESS		(0x4D14)
#define P3DIR				MMR_08_BIT_MACRO(P3DIR_ADDRESS)
#define P3IFG_ADDRESS		(0x4D18)
#define P3IFG				MMR_08_BIT_MACRO(P3IFG_ADDRESS)
#define P3IES_ADDRESS		(0x4D1C)
#define P3IES				MMR_08_BIT_MACRO(P3IES_ADDRESS)
#define P3IE_ADDRESS		(0x4D20)
#define P3IE				MMR_08_BIT_MACRO(P3IE_ADDRESS)
#define P3SEL_ADDRESS		(0x4D24)
#define P3SEL				MMR_08_BIT_MACRO(P3SEL_ADDRESS)
#define P3REN_ADDRESS		(0x4D28)
#define P3REN				MMR_08_BIT_MACRO(P3REN_ADDRESS)



/** I2C0 **/
#define I2C0_BASE			(0x4E00)

#define I2C0CR_ADDRESS		(0x4E00)
#define I2C0CR				MMR_32_BIT_MACRO(I2C0CR_ADDRESS)
#define I2C0FCR_ADDRESS		(0x4E04)
#define I2C0FCR				MMR_08_BIT_MACRO(I2C0FCR_ADDRESS)
#define I2C0SR_ADDRESS		(0x4E08)
#define I2C0SR				MMR_16_BIT_MACRO(I2C0SR_ADDRESS)
#define I2C0MTX_ADDRESS		(0x4E0C)
#define I2C0MTX				MMR_08_BIT_MACRO(I2C0MTX_ADDRESS)
#define I2C0MRX_ADDRESS		(0x4E10)
#define I2C0MRX				MMR_08_BIT_MACRO(I2C0MRX_ADDRESS)
#define I2C0STX_ADDRESS		(0x4E14)
#define I2C0STX				MMR_08_BIT_MACRO(I2C0STX_ADDRESS)
#define I2C0SRX_ADDRESS		(0x4E18)
#define I2C0SRX				MMR_08_BIT_MACRO(I2C0SRX_ADDRESS)
#define I2C0AR_ADDRESS		(0x4E1C)
#define I2C0AR				MMR_08_BIT_MACRO(I2C0AR_ADDRESS)
#define I2C0AMR_ADDRESS		(0x4E20)
#define I2C0AMR				MMR_08_BIT_MACRO(I2C0AMR_ADDRESS)



/** I2C1 **/
#define I2C1_BASE			(0x4F00)

#define I2C1CR_ADDRESS		(0x4F00)
#define I2C1CR				MMR_32_BIT_MACRO(I2C1CR_ADDRESS)
#define I2C1FCR_ADDRESS		(0x4F04)
#define I2C1FCR				MMR_08_BIT_MACRO(I2C1FCR_ADDRESS)
#define I2C1SR_ADDRESS		(0x4F08)
#define I2C1SR				MMR_16_BIT_MACRO(I2C1SR_ADDRESS)
#define I2C1MTX_ADDRESS		(0x4F0C)
#define I2C1MTX				MMR_08_BIT_MACRO(I2C1MTX_ADDRESS)
#define I2C1MRX_ADDRESS		(0x4F10)
#define I2C1MRX				MMR_08_BIT_MACRO(I2C1MRX_ADDRESS)
#define I2C1STX_ADDRESS		(0x4F14)
#define I2C1STX				MMR_08_BIT_MACRO(I2C1STX_ADDRESS)
#define I2C1SRX_ADDRESS		(0x4F18)
#define I2C1SRX				MMR_08_BIT_MACRO(I2C1SRX_ADDRESS)
#define I2C1AR_ADDRESS		(0x4F1C)
#define I2C1AR				MMR_08_BIT_MACRO(I2C1AR_ADDRESS)
#define I2C1AMR_ADDRESS		(0x4F20)
#define I2C1AMR				MMR_08_BIT_MACRO(I2C1AMR_ADDRESS)



/********** Peripheral, Register, and Bit Field Structures **********/

/** Peripheral GPIOx **/
// Bit fields structure for GPIO registers
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t P0	: 1;
		volatile uint8_t P1	: 1;
		volatile uint8_t P2	: 1;
		volatile uint8_t P3	: 1;
		volatile uint8_t P4	: 1;
		volatile uint8_t P5	: 1;
		volatile uint8_t P6	: 1;
		volatile uint8_t P7	: 1;
	};
} GPIO_8bit_Register_t;

typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t P0	: 1;
		volatile uint16_t P1	: 1;
		volatile uint16_t P2	: 1;
		volatile uint16_t P3	: 1;
		volatile uint16_t P4	: 1;
		volatile uint16_t P5	: 1;
		volatile uint16_t P6	: 1;
		volatile uint16_t P7	: 1;
		volatile uint16_t P8	: 1;
		volatile uint16_t P9	: 1;
		volatile uint16_t P10	: 1;
		volatile uint16_t P11	: 1;
		volatile uint16_t P12	: 1;
		volatile uint16_t P13	: 1;
		volatile uint16_t P14	: 1;
		volatile uint16_t P15	: 1;
	};
} GPIO_16bit_Register_t;

typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t P0	: 1;
		volatile uint32_t P1	: 1;
		volatile uint32_t P2	: 1;
		volatile uint32_t P3	: 1;
		volatile uint32_t P4	: 1;
		volatile uint32_t P5	: 1;
		volatile uint32_t P6	: 1;
		volatile uint32_t P7	: 1;
		volatile uint32_t P8	: 1;
		volatile uint32_t P9	: 1;
		volatile uint32_t P10	: 1;
		volatile uint32_t P11	: 1;
		volatile uint32_t P12	: 1;
		volatile uint32_t P13	: 1;
		volatile uint32_t P14	: 1;
		volatile uint32_t P15	: 1;
		volatile uint32_t P16	: 1;
		volatile uint32_t P17	: 1;
		volatile uint32_t P18	: 1;
		volatile uint32_t P19	: 1;
		volatile uint32_t P20	: 1;
		volatile uint32_t P21	: 1;
		volatile uint32_t P22	: 1;
		volatile uint32_t P23	: 1;
		volatile uint32_t P24	: 1;
		volatile uint32_t P25	: 1;
		volatile uint32_t P26	: 1;
		volatile uint32_t P27	: 1;
		volatile uint32_t P28	: 1;
		volatile uint32_t P29	: 1;
		volatile uint32_t P30	: 1;
		volatile uint32_t P31	: 1;
	};
} GPIO_32bit_Register_t;

// Registers structure for 8-bit GPIO peripheral
typedef struct
{
	volatile GPIO_8bit_Register_t	IN;
	volatile uint8_t				__unused0;
	volatile uint16_t				__unused1;
	volatile GPIO_8bit_Register_t	OUT;
	volatile uint8_t				__unused2;
	volatile uint16_t				__unused3;
	volatile GPIO_8bit_Register_t	OUTS;
	volatile uint8_t				__unused4;
	volatile uint16_t				__unused5;
	volatile GPIO_8bit_Register_t	OUTC;
	volatile uint8_t				__unused6;
	volatile uint16_t				__unused7;
	volatile GPIO_8bit_Register_t	OUTT;
	volatile uint8_t				__unused8;
	volatile uint16_t				__unused9;
	volatile GPIO_8bit_Register_t	DIR;
	volatile uint8_t				__unused10;
	volatile uint16_t				__unused11;
	volatile GPIO_8bit_Register_t	IFG;
	volatile uint8_t				__unused12;
	volatile uint16_t				__unused13;
	volatile GPIO_8bit_Register_t	IES;
	volatile uint8_t				__unused14;
	volatile uint16_t				__unused15;
	volatile GPIO_8bit_Register_t	IE;
	volatile uint8_t				__unused16;
	volatile uint16_t				__unused17;
	volatile GPIO_8bit_Register_t	SEL;
	volatile uint8_t				__unused18;
	volatile uint16_t				__unused19;
	volatile GPIO_8bit_Register_t	REN;
	volatile uint8_t				__unused20;
	volatile uint16_t				__unused21;
	volatile uint32_t				__unused22[53];
}GPIOx_8bit_t;

// Registers structure for 16-bit GPIO peripheral
typedef struct
{
	volatile GPIO_16bit_Register_t	IN;
	volatile uint16_t				__unused0;
	volatile GPIO_16bit_Register_t	OUT;
	volatile uint16_t				__unused1;
	volatile GPIO_16bit_Register_t	OUTS;
	volatile uint16_t				__unused2;
	volatile GPIO_16bit_Register_t	OUTC;
	volatile uint16_t				__unused3;
	volatile GPIO_16bit_Register_t	OUTT;
	volatile uint16_t				__unused4;
	volatile GPIO_16bit_Register_t	DIR;
	volatile uint16_t				__unused5;
	volatile GPIO_16bit_Register_t	IFG;
	volatile uint16_t				__unused6;
	volatile GPIO_16bit_Register_t	IES;
	volatile uint16_t				__unused7;
	volatile GPIO_16bit_Register_t	IE;
	volatile uint16_t				__unused8;
	volatile GPIO_16bit_Register_t	SEL;
	volatile uint16_t				__unused9;
	volatile GPIO_16bit_Register_t	REN;
	volatile uint16_t				__unused10;
	volatile uint32_t				__unused11[53];
}GPIOx_16bit_t;

// Registers structure for 32-bit GPIO peripheral
typedef struct
{
	volatile GPIO_32bit_Register_t	IN;
	volatile GPIO_32bit_Register_t	OUT;
	volatile GPIO_32bit_Register_t	OUTS;
	volatile GPIO_32bit_Register_t	OUTC;
	volatile GPIO_32bit_Register_t	OUTT;
	volatile GPIO_32bit_Register_t	DIR;
	volatile GPIO_32bit_Register_t	IFG;
	volatile GPIO_32bit_Register_t	IES;
	volatile GPIO_32bit_Register_t	IE;
	volatile GPIO_32bit_Register_t	SEL;
	volatile GPIO_32bit_Register_t	REN;
	volatile uint32_t				__unused0[53];
}GPIOx_32bit_t;

/** Peripheral SPIx **/
// Bit fields structure for register SPIxCR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CPHA		: 1;	// bit 0
		volatile uint32_t CPOL		: 1;	// bit 1
		volatile uint32_t DL		: 2;	// bits 3 downto 2
		volatile uint32_t TEIE		: 1;	// bit 4
		volatile uint32_t TCIE		: 1;	// bit 5
		volatile uint32_t MSB		: 1;	// bit 6
		volatile uint32_t EN		: 1;	// bit 7
		volatile uint32_t BR		: 8;	// bits 15 downto 8
		volatile uint32_t RXSB		: 1;	// bit 16
		volatile uint32_t TXSB		: 1;	// bit 17
		volatile uint32_t SM		: 1;	// bit 18
		volatile uint32_t FEN		: 1;	// bit 19
		volatile uint32_t __unused0	: 12;	// bits 31 downto 20
	};
} SPIxCR_Register_t;

// Bit fields structure for register SPIxSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TEIF		: 1;	// bit 0
		volatile uint8_t TCIF		: 1;	// bit 1
		volatile uint8_t BUSY		: 1;	// bit 2
		volatile uint8_t __unused0	: 5;	// bits 7 downto 3
	};
} SPIxSR_Register_t;

// Bit fields structure for register SPIxTX
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t TX	: 32;	// bits 31 downto 0
	};
} SPIxTX_Register_t;

// Bit fields structure for register SPIxRX
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t RX	: 32;	// bits 31 downto 0
	};
} SPIxRX_Register_t;

// Bit fields structure for register SPIxFOS
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t FOS		: 24;	// bits 23 downto 0
		volatile uint32_t __unused0	: 8;	// bits 31 downto 24
	};
} SPIxFOS_Register_t;



// Registers structure for peripheral SPIx
typedef struct
{
	volatile SPIxCR_Register_t	CR;
	volatile SPIxSR_Register_t	SR;
	volatile uint8_t			__unused0;
	volatile uint16_t			__unused1;
	volatile SPIxTX_Register_t	TX;
	volatile SPIxRX_Register_t	RX;
	volatile SPIxFOS_Register_t	FOS;
	volatile uint32_t			__unused2[59];
} SPIx_t;
#define SPIx_PTR(_SPIx_BASE)	((SPIx_t *) _SPIx_BASE)

/** Peripheral UARTx **/
// Bit fields structure for register UARTxCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TCIE		: 1;	// bit 0
		volatile uint8_t TEIE		: 1;	// bit 1
		volatile uint8_t RCIE		: 1;	// bit 2
		volatile uint8_t PODD		: 1;	// bit 3
		volatile uint8_t PEN		: 1;	// bit 4
		volatile uint8_t EN			: 1;	// bit 5
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} UARTxCR_Register_t;

// Bit fields structure for register UARTxSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TCIF	: 1;	// bit 0
		volatile uint8_t TEIF	: 1;	// bit 1
		volatile uint8_t RCIF	: 1;	// bit 2
		volatile uint8_t OVF	: 1;	// bit 3
		volatile uint8_t PEF	: 1;	// bit 4
		volatile uint8_t FEF	: 1;	// bit 5
		volatile uint8_t TBF	: 1;	// bit 6
		volatile uint8_t RBF	: 1;	// bit 7
	};
} UARTxSR_Register_t;

// Bit fields structure for register UARTxBR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BR		: 12;	// bits 11 downto 0
		volatile uint16_t __unused0	: 4;	// bits 15 downto 12
	};
} UARTxBR_Register_t;

// Bit fields structure for register UARTxRX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t RX	: 8;	// bits 7 downto 0
	};
} UARTxRX_Register_t;

// Bit fields structure for register UARTxTX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TX	: 8;	// bits 7 downto 0
	};
} UARTxTX_Register_t;



// Registers structure for peripheral UARTx
typedef struct
{
	volatile UARTxCR_Register_t	CR;
	volatile uint8_t			__unused0;
	volatile uint16_t			__unused1;
	volatile UARTxSR_Register_t	SR;
	volatile uint8_t			__unused2;
	volatile uint16_t			__unused3;
	volatile UARTxBR_Register_t	BR;
	volatile uint16_t			__unused4;
	volatile UARTxRX_Register_t	RX;
	volatile uint8_t			__unused5;
	volatile uint16_t			__unused6;
	volatile UARTxTX_Register_t	TX;
	volatile uint8_t			__unused7;
	volatile uint16_t			__unused8;
	volatile uint32_t			__unused9[59];
} UARTx_t;
#define UARTx_PTR(_UARTx_BASE)	((UARTx_t *) _UARTx_BASE)

/** Peripheral TIMERx **/
// Bit fields structure for register TIMxCR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP0IE	: 1;	// bit 0
		volatile uint32_t CMP1IE	: 1;	// bit 1
		volatile uint32_t CMP2IE	: 1;	// bit 2
		volatile uint32_t OVIE		: 1;	// bit 3
		volatile uint32_t CAP0IE	: 1;	// bit 4
		volatile uint32_t CAP1IE	: 1;	// bit 5
		volatile uint32_t EN		: 1;	// bit 6
		volatile uint32_t CMP2RST	: 1;	// bit 7
		volatile uint32_t SSEL		: 2;	// bits 9 downto 8
		volatile uint32_t CAP0EN	: 1;	// bit 10
		volatile uint32_t CAP1EN	: 1;	// bit 11
		volatile uint32_t CAP0FE	: 1;	// bit 12
		volatile uint32_t CAP1FE	: 1;	// bit 13
		volatile uint32_t CMP0IH	: 1;	// bit 14
		volatile uint32_t CMP1IH	: 1;	// bit 15
		volatile uint32_t DIV		: 4;	// bits 19 downto 16
		volatile uint32_t __unused0	: 12;	// bits 31 downto 20
	};
} TIMxCR_Register_t;

// Bit fields structure for register TIMxSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CMP0IF	: 1;	// bit 0
		volatile uint8_t CMP1IF	: 1;	// bit 1
		volatile uint8_t CMP2IF	: 1;	// bit 2
		volatile uint8_t OVIF	: 1;	// bit 3
		volatile uint8_t CAP0IF	: 1;	// bit 4
		volatile uint8_t CAP1IF	: 1;	// bit 5
		volatile uint8_t TCMP0_	: 1;	// bit 6
		volatile uint8_t TCMP1_	: 1;	// bit 7
	};
} TIMxSR_Register_t;

// Bit fields structure for register TIMxVAL
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t VAL	: 32;	// bits 31 downto 0
	};
} TIMxVAL_Register_t;

// Bit fields structure for register TIMxCMP0
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP0	: 32;	// bits 31 downto 0
	};
} TIMxCMP0_Register_t;

// Bit fields structure for register TIMxCMP1
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP1	: 32;	// bits 31 downto 0
	};
} TIMxCMP1_Register_t;

// Bit fields structure for register TIMxCMP2
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP2	: 32;	// bits 31 downto 0
	};
} TIMxCMP2_Register_t;

// Bit fields structure for register TIMxCAP0
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CAP0	: 32;	// bits 31 downto 0
	};
} TIMxCAP0_Register_t;

// Bit fields structure for register TIMxCAP1
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CAP1	: 32;	// bits 31 downto 0
	};
} TIMxCAP1_Register_t;



// Registers structure for peripheral TIMERx
typedef struct
{
	volatile TIMxCR_Register_t		CR;
	volatile TIMxSR_Register_t		SR;
	volatile uint8_t				__unused0;
	volatile uint16_t				__unused1;
	volatile TIMxVAL_Register_t		VAL;
	volatile TIMxCMP0_Register_t	CMP0;
	volatile TIMxCMP1_Register_t	CMP1;
	volatile TIMxCMP2_Register_t	CMP2;
	volatile TIMxCAP0_Register_t	CAP0;
	volatile TIMxCAP1_Register_t	CAP1;
	volatile uint32_t				__unused2[56];
} TIMERx_t;
#define TIMERx_PTR(_TIMERx_BASE)	((TIMERx_t *) _TIMERx_BASE)

/** Peripheral SYSTEM **/
// Bit fields structure for register SYSCLKCR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t MCLKSEL_	: 2;	// bits 1 downto 0
		volatile uint16_t __unused0	: 1;	// bit 2
		volatile uint16_t SMCLKSEL_	: 2;	// bits 4 downto 3
		volatile uint16_t __unused1	: 1;	// bit 5
		volatile uint16_t SMCLKOFF_	: 1;	// bit 6
		volatile uint16_t __unused2	: 1;	// bit 7
		volatile uint16_t LFXTOFF_	: 1;	// bit 8
		volatile uint16_t HFXTOFF_	: 1;	// bit 9
		volatile uint16_t DCO0OFF_	: 1;	// bit 10
		volatile uint16_t DCO1OFF_	: 1;	// bit 11
		volatile uint16_t __unused3	: 4;	// bits 15 downto 12
	};
} SYSCLKCR_Register_t;

// Bit fields structure for register CLKDIVCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t MCLKDIV_	: 3;	// bits 2 downto 0
		volatile uint8_t SMCLKDIV_	: 3;	// bits 5 downto 3
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} CLKDIVCR_Register_t;

// Bit fields structure for register MEMPWRCR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t ROMOFF_		: 1;	// bit 0
		volatile uint16_t __unused0		: 1;	// bit 1
		volatile uint16_t SRAM02OFF_	: 1;	// bit 2
		volatile uint16_t SRAM03OFF_	: 1;	// bit 3
		volatile uint16_t SRAM04OFF_	: 1;	// bit 4
		volatile uint16_t SRAM05OFF_	: 1;	// bit 5
		volatile uint16_t SRAM06OFF_	: 1;	// bit 6
		volatile uint16_t SRAM07OFF_	: 1;	// bit 7
		volatile uint16_t SRAM08OFF_	: 1;	// bit 8
		volatile uint16_t SRAM09OFF_	: 1;	// bit 9
		volatile uint16_t SRAM10OFF_	: 1;	// bit 10
		volatile uint16_t SRAM11OFF_	: 1;	// bit 11
		volatile uint16_t SRAM12OFF_	: 1;	// bit 12
		volatile uint16_t SRAM13OFF_	: 1;	// bit 13
		volatile uint16_t SRAM14OFF_	: 1;	// bit 14
		volatile uint16_t SRAM15OFF_	: 1;	// bit 15
	};
} MEMPWRCR_Register_t;

// Bit fields structure for register CRCDATA
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CRCDATA_	: 8;	// bits 7 downto 0
	};
} CRCDATA_Register_t;

// Bit fields structure for register CRCSTATE
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CRCSTATE_	: 16;	// bits 15 downto 0
	};
} CRCSTATE_Register_t;

// Bit fields structure for register IRQEN
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQEN_	: 32;	// bits 31 downto 0
	};
} IRQEN_Register_t;

// Bit fields structure for register IRQPRI
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQPRI_	: 32;	// bits 31 downto 0
	};
} IRQPRI_Register_t;

// Bit fields structure for register WDTPASS
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t WDTPASS_	: 32;	// bits 31 downto 0
	};
} WDTPASS_Register_t;

// Bit fields structure for register WDTCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t WDTREN_	: 1;	// bit 0
		volatile uint8_t WDTIE_		: 1;	// bit 1
		volatile uint8_t WDTCDIV_	: 4;	// bits 5 downto 2
		volatile uint8_t HWRST_		: 1;	// bit 6
		volatile uint8_t __unused0	: 1;	// bit 7
	};
} WDTCR_Register_t;

// Bit fields structure for register WDTSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t WDTRF_		: 1;	// bit 0
		volatile uint8_t WDTIF_		: 1;	// bit 1
		volatile uint8_t __unused0	: 6;	// bits 7 downto 2
	};
} WDTSR_Register_t;

// Bit fields structure for register WDTVAL
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t WDTVAL_	: 32;	// bits 31 downto 0
	};
} WDTVAL_Register_t;

// Bit fields structure for register DCO0FREQ
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DCO0MFREQ_	: 12;	// bits 11 downto 0
		volatile uint16_t __unused0		: 4;	// bits 15 downto 12
	};
} DCO0FREQ_Register_t;

// Bit fields structure for register DCO1FREQ
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DCO1MFREQ_	: 12;	// bits 11 downto 0
		volatile uint16_t __unused0		: 4;	// bits 15 downto 12
	};
} DCO1FREQ_Register_t;

// Bit fields structure for register TPMR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TPMR_		: 4;	// bits 3 downto 0
		volatile uint8_t __unused0	: 4;	// bits 7 downto 4
	};
} TPMR_Register_t;

// Bit fields structure for register BIASCR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BiasAdj_		: 6;	// bits 5 downto 0
		volatile uint16_t EnBiasGen_	: 1;	// bit 6
		volatile uint16_t EnBiasBuf_	: 1;	// bit 7
		volatile uint16_t UseBiasDac_	: 1;	// bit 8
		volatile uint16_t UseExtBias_	: 1;	// bit 9
		volatile uint16_t EnBG_			: 1;	// bit 10
		volatile uint16_t __unused0		: 5;	// bits 15 downto 11
	};
} BIASCR_Register_t;

// Bit fields structure for register BIASDBP
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BIASDBP_	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIASDBP_Register_t;

// Bit fields structure for register BIASDBPC
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BIASDBPC_	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIASDBPC_Register_t;

// Bit fields structure for register BIASDBNC
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BIASDBNC_	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIASDBNC_Register_t;

// Bit fields structure for register BIASDBN
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BIASDBN_	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIASDBN_Register_t;



// Registers structure for peripheral SYSTEM
typedef struct
{
	volatile SYSCLKCR_Register_t	SYSCLKCR_;
	volatile uint16_t				__unused0;
	volatile CLKDIVCR_Register_t	CLKDIVCR_;
	volatile uint8_t				__unused1;
	volatile uint16_t				__unused2;
	volatile MEMPWRCR_Register_t	MEMPWRCR_;
	volatile uint16_t				__unused3;
	volatile CRCDATA_Register_t		CRCDATA_;
	volatile uint8_t				__unused4;
	volatile uint16_t				__unused5;
	volatile CRCSTATE_Register_t	CRCSTATE_;
	volatile uint16_t				__unused6;
	volatile IRQEN_Register_t		IRQEN_;
	volatile IRQPRI_Register_t		IRQPRI_;
	volatile WDTPASS_Register_t		WDTPASS_;
	volatile WDTCR_Register_t		WDTCR_;
	volatile uint8_t				__unused7;
	volatile uint16_t				__unused8;
	volatile WDTSR_Register_t		WDTSR_;
	volatile uint8_t				__unused9;
	volatile uint16_t				__unused10;
	volatile WDTVAL_Register_t		WDTVAL_;
	volatile DCO0FREQ_Register_t	DCO0FREQ_;
	volatile uint16_t				__unused11;
	volatile DCO1FREQ_Register_t	DCO1FREQ_;
	volatile uint16_t				__unused12;
	volatile TPMR_Register_t		TPMR_;
	volatile uint8_t				__unused13;
	volatile uint16_t				__unused14;
	volatile BIASCR_Register_t		BIASCR_;
	volatile uint16_t				__unused15;
	volatile BIASDBP_Register_t		BIASDBP_;
	volatile uint16_t				__unused16;
	volatile BIASDBPC_Register_t	BIASDBPC_;
	volatile uint16_t				__unused17;
	volatile BIASDBNC_Register_t	BIASDBNC_;
	volatile uint16_t				__unused18;
	volatile BIASDBN_Register_t		BIASDBN_;
	volatile uint16_t				__unused19;
	volatile uint32_t				__unused20[45];
} SYSTEM_t;

/** Peripheral NNx **/
// Bit fields structure for register NNxCR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t I			: 8;	// bits 7 downto 0
		volatile uint32_t O			: 8;	// bits 15 downto 8
		volatile uint32_t RUN		: 1;	// bit 16
		volatile uint32_t AFS		: 1;	// bit 17
		volatile uint32_t BIAS		: 1;	// bit 18
		volatile uint32_t CS		: 1;	// bit 19
		volatile uint32_t LSIS		: 1;	// bit 20
		volatile uint32_t CIF		: 1;	// bit 21
		volatile uint32_t CIE		: 1;	// bit 22
		volatile uint32_t __unused0	: 9;	// bits 31 downto 23
	};
} NNxCR_Register_t;

// Bit fields structure for register NNxIVA
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t __unused0	: 2;	// bits 1 downto 0
		volatile uint32_t IVA		: 12;	// bits 13 downto 2
		volatile uint32_t __unused1	: 18;	// bits 31 downto 14
	};
} NNxIVA_Register_t;

// Bit fields structure for register NNxOVA
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t __unused0	: 2;	// bits 1 downto 0
		volatile uint32_t OVA		: 12;	// bits 13 downto 2
		volatile uint32_t __unused1	: 18;	// bits 31 downto 14
	};
} NNxOVA_Register_t;

// Bit fields structure for register NNxWMA
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t __unused0	: 2;	// bits 1 downto 0
		volatile uint32_t WMA		: 12;	// bits 13 downto 2
		volatile uint32_t __unused1	: 18;	// bits 31 downto 14
	};
} NNxWMA_Register_t;

// Bit fields structure for register NNxLSI
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t LSI	: 32;	// bits 31 downto 0
	};
} NNxLSI_Register_t;

// Bit fields structure for register NNxLSO
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t LSO	: 16;	// bits 15 downto 0
	};
} NNxLSO_Register_t;



// Registers structure for peripheral NNx
typedef struct
{
	volatile NNxCR_Register_t	CR;
	volatile NNxIVA_Register_t	IVA;
	volatile NNxOVA_Register_t	OVA;
	volatile NNxWMA_Register_t	WMA;
	volatile NNxLSI_Register_t	LSI;
	volatile NNxLSO_Register_t	LSO;
	volatile uint16_t			__unused0;
	volatile uint32_t			__unused1[58];
} NNx_t;
#define NNx_PTR(_NNx_BASE)	((NNx_t *) _NNx_BASE)

/** Peripheral SARADCx **/
// Bit fields structure for register SARADCxCR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t RESET			: 1;	// bit 0
		volatile uint16_t SAMPLESTEP	: 4;	// bits 4 downto 1
		volatile uint16_t EN			: 1;	// bit 5
		volatile uint16_t DEBUG			: 1;	// bit 6
		volatile uint16_t DATAIE		: 1;	// bit 7
		volatile uint16_t CONTMEAS		: 1;	// bit 8
		volatile uint16_t __unused0		: 7;	// bits 15 downto 9
	};
} SARADCxCR_Register_t;

// Bit fields structure for register SARADCxCDIV
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CDIV	: 8;	// bits 7 downto 0
	};
} SARADCxCDIV_Register_t;

// Bit fields structure for register SARADCxSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t BUSY		: 1;	// bit 0
		volatile uint8_t DATAVALID	: 1;	// bit 1
		volatile uint8_t OVF		: 1;	// bit 2
		volatile uint8_t RDY		: 1;	// bit 3
		volatile uint8_t __unused0	: 4;	// bits 7 downto 4
	};
} SARADCxSR_Register_t;

// Bit fields structure for register SARADCxDATA
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DATA		: 10;	// bits 9 downto 0
		volatile uint16_t __unused0	: 6;	// bits 15 downto 10
	};
} SARADCxDATA_Register_t;

// Bit fields structure for register SARADCxTPR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t DTP0SEL	: 4;	// bits 3 downto 0
		volatile uint8_t DTP1SEL	: 4;	// bits 7 downto 4
	};
} SARADCxTPR_Register_t;



// Registers structure for peripheral SARADCx
typedef struct
{
	volatile SARADCxCR_Register_t	xCR;
	volatile uint16_t				__unused0;
	volatile SARADCxCDIV_Register_t	xCDIV;
	volatile uint8_t				__unused1;
	volatile uint16_t				__unused2;
	volatile SARADCxSR_Register_t	xSR;
	volatile uint8_t				__unused3;
	volatile uint16_t				__unused4;
	volatile SARADCxDATA_Register_t	xDATA;
	volatile uint16_t				__unused5;
	volatile SARADCxTPR_Register_t	xTPR;
	volatile uint8_t				__unused6;
	volatile uint16_t				__unused7;
	volatile uint32_t				__unused8[59];
} SARADCx_t;
#define SARADCx_PTR(_SARADCx_BASE)	((SARADCx_t *) _SARADCx_BASE)

/** Peripheral AFEx **/
// Bit fields structure for register AFExCR0
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t PsdFullIE_		: 1;	// bit 0
		volatile uint32_t AdcConvDoneIE_	: 1;	// bit 1
		volatile uint32_t PulseDoneIE_		: 1;	// bit 2
		volatile uint32_t PulseDoneWait_	: 1;	// bit 3
		volatile uint32_t ThreshSel_		: 2;	// bits 5 downto 4
		volatile uint32_t SHPwrMode_		: 1;	// bit 6
		volatile uint32_t RejectMode_		: 1;	// bit 7
		volatile uint32_t RamOff_			: 1;	// bit 8
		volatile uint32_t PUPara_			: 1;	// bit 9
		volatile uint32_t PsdOrder_			: 1;	// bit 10
		volatile uint32_t OpenInput_		: 1;	// bit 11
		volatile uint32_t ForceThresh_		: 1;	// bit 12
		volatile uint32_t EnBLLT_			: 1;	// bit 13
		volatile uint32_t EnPsd_			: 1;	// bit 14
		volatile uint32_t EnPURej_			: 1;	// bit 15
		volatile uint32_t EnDma_			: 1;	// bit 16
		volatile uint32_t EnThresh_			: 1;	// bit 17
		volatile uint32_t EnAdc_			: 1;	// bit 18
		volatile uint32_t EnCsa_			: 1;	// bit 19
		volatile uint32_t EnCM_				: 1;	// bit 20
		volatile uint32_t EnAfe_			: 1;	// bit 21
		volatile uint32_t CsaRstMode_		: 1;	// bit 22
		volatile uint32_t CsaForceUnRst_	: 1;	// bit 23
		volatile uint32_t CsaForceRst_		: 1;	// bit 24
		volatile uint32_t CsaBiasSel_		: 1;	// bit 25
		volatile uint32_t BufCMMid_			: 1;	// bit 26
		volatile uint32_t AdcMuxTest_		: 1;	// bit 27
		volatile uint32_t AdcMidSel_		: 1;	// bit 28
		volatile uint32_t AdcExtIn_			: 1;	// bit 29
		volatile uint32_t __unused0			: 2;	// bits 31 downto 30
	};
} AFExCR0_Register_t;

// Bit fields structure for register AFExCR1
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t ISink_		: 6;	// bits 5 downto 0
		volatile uint32_t CsaCmAdj_		: 3;	// bits 8 downto 6
		volatile uint32_t CMSHClkDiv_	: 4;	// bits 12 downto 9
		volatile uint32_t ClkSel_		: 2;	// bits 14 downto 13
		volatile uint32_t AdcSampT_		: 3;	// bits 17 downto 15
		volatile uint32_t AdcCp_		: 7;	// bits 24 downto 18
		volatile uint32_t AdcClkDivM_	: 4;	// bits 28 downto 25
		volatile uint32_t AdcClkDivN_	: 3;	// bits 31 downto 29
	};
} AFExCR1_Register_t;

// Bit fields structure for register AFExCFB
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CFB	: 8;	// bits 7 downto 0
	};
} AFExCFB_Register_t;

// Bit fields structure for register AFExRFB
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t RFB		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExRFB_Register_t;

// Bit fields structure for register AFExTHR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t THR		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExTHR_Register_t;

// Bit fields structure for register AFExTPR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t Dtp0Sel	: 5;	// bits 4 downto 0
		volatile uint32_t Dtp1Sel	: 5;	// bits 9 downto 5
		volatile uint32_t Dtp2Sel	: 5;	// bits 14 downto 10
		volatile uint32_t Dtp3Sel	: 5;	// bits 19 downto 15
		volatile uint32_t Atp0Sel	: 4;	// bits 23 downto 20
		volatile uint32_t Atp0BufEn	: 1;	// bit 24
		volatile uint32_t Atp1Sel	: 4;	// bits 28 downto 25
		volatile uint32_t Atp1BufEn	: 1;	// bit 29
		volatile uint32_t __unused0	: 2;	// bits 31 downto 30
	};
} AFExTPR_Register_t;

// Bit fields structure for register AFExSPT
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t SPT	: 8;	// bits 7 downto 0
	};
} AFExSPT_Register_t;

// Bit fields structure for register AFExPIT
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t PIT	: 16;	// bits 15 downto 0
	};
} AFExPIT_Register_t;

// Bit fields structure for register AFExEIT
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t EIT	: 16;	// bits 15 downto 0
	};
} AFExEIT_Register_t;

// Bit fields structure for register AFExLIT
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t LIT	: 16;	// bits 15 downto 0
	};
} AFExLIT_Register_t;

// Bit fields structure for register AFExRJT
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t RJT	: 16;	// bits 15 downto 0
	};
} AFExRJT_Register_t;

// Bit fields structure for register AFExRST
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t RST	: 8;	// bits 7 downto 0
	};
} AFExRST_Register_t;

// Bit fields structure for register AFExAOFST
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t AOFST		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExAOFST_Register_t;

// Bit fields structure for register AFExBLLT
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BLLT		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExBLLT_Register_t;

// Bit fields structure for register AFExCSAREF
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CSAREF	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExCSAREF_Register_t;

// Bit fields structure for register AFExCSABP
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CSABP		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExCSABP_Register_t;

// Bit fields structure for register AFExCSABPC
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CSABPC	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExCSABPC_Register_t;

// Bit fields structure for register AFExCSABNC
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CSABNC	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExCSABNC_Register_t;

// Bit fields structure for register AFExCSABN
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CSABN		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExCSABN_Register_t;

// Bit fields structure for register AFExCMSHR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CMSHR		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} AFExCMSHR_Register_t;

// Bit fields structure for register AFExCLPF
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CLPF		: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} AFExCLPF_Register_t;

// Bit fields structure for register AFExSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t PsdFull_		: 1;	// bit 0
		volatile uint8_t AdcConvDone_	: 1;	// bit 1
		volatile uint8_t PulseDone_		: 1;	// bit 2
		volatile uint8_t DmaEnabled_	: 1;	// bit 3
		volatile uint8_t AdcDataReady_	: 1;	// bit 4
		volatile uint8_t AdcActive_		: 1;	// bit 5
		volatile uint8_t DTP0VAL_		: 1;	// bit 6
		volatile uint8_t DTP1VAL_		: 1;	// bit 7
	};
} AFExSR_Register_t;

// Bit fields structure for register AFExADCVAL
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t ADCVAL	: 10;	// bits 9 downto 0
		volatile uint16_t __unused0	: 6;	// bits 15 downto 10
	};
} AFExADCVAL_Register_t;

// Bit fields structure for register AFExVPC
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t VPC	: 32;	// bits 31 downto 0
	};
} AFExVPC_Register_t;

// Bit fields structure for register AFExTPC
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t TPC	: 32;	// bits 31 downto 0
	};
} AFExTPC_Register_t;



// Registers structure for peripheral AFEx
typedef struct
{
	volatile AFExCR0_Register_t		CR0;
	volatile AFExCR1_Register_t		CR1;
	volatile AFExCFB_Register_t		CFB;
	volatile uint8_t				__unused0;
	volatile uint16_t				__unused1;
	volatile AFExRFB_Register_t		RFB;
	volatile uint16_t				__unused2;
	volatile AFExTHR_Register_t		THR;
	volatile uint16_t				__unused3;
	volatile AFExTPR_Register_t		TPR;
	volatile AFExSPT_Register_t		SPT;
	volatile uint8_t				__unused4;
	volatile uint16_t				__unused5;
	volatile AFExPIT_Register_t		PIT;
	volatile uint16_t				__unused6;
	volatile AFExEIT_Register_t		EIT;
	volatile uint16_t				__unused7;
	volatile AFExLIT_Register_t		LIT;
	volatile uint16_t				__unused8;
	volatile AFExRJT_Register_t		RJT;
	volatile uint16_t				__unused9;
	volatile AFExRST_Register_t		RST;
	volatile uint8_t				__unused10;
	volatile uint16_t				__unused11;
	volatile AFExAOFST_Register_t	AOFST;
	volatile uint16_t				__unused12;
	volatile AFExBLLT_Register_t	BLLT;
	volatile uint16_t				__unused13;
	volatile AFExCSAREF_Register_t	CSAREF;
	volatile uint16_t				__unused14;
	volatile AFExCSABP_Register_t	CSABP;
	volatile uint16_t				__unused15;
	volatile AFExCSABPC_Register_t	CSABPC;
	volatile uint16_t				__unused16;
	volatile AFExCSABNC_Register_t	CSABNC;
	volatile uint16_t				__unused17;
	volatile AFExCSABN_Register_t	CSABN;
	volatile uint16_t				__unused18;
	volatile AFExCMSHR_Register_t	CMSHR;
	volatile uint16_t				__unused19;
	volatile AFExCLPF_Register_t	CLPF;
	volatile uint8_t				__unused20;
	volatile uint16_t				__unused21;
	volatile AFExSR_Register_t		SR;
	volatile uint8_t				__unused22;
	volatile uint16_t				__unused23;
	volatile AFExADCVAL_Register_t	ADCVAL;
	volatile uint16_t				__unused24;
	volatile AFExVPC_Register_t		VPC;
	volatile AFExTPC_Register_t		TPC;
	volatile uint32_t				__unused25[39];
} AFEx_t;
#define AFEx_PTR(_AFEx_BASE)	((AFEx_t *) _AFEx_BASE)

/** Peripheral I2Cx **/
// Bit fields structure for register I2CxCR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t SPRIE		: 1;	// bit 0
		volatile uint32_t STRIE		: 1;	// bit 1
		volatile uint32_t MXCIE		: 1;	// bit 2
		volatile uint32_t MNRIE		: 1;	// bit 3
		volatile uint32_t MTXEIE	: 1;	// bit 4
		volatile uint32_t MARBIE	: 1;	// bit 5
		volatile uint32_t MSPSIE	: 1;	// bit 6
		volatile uint32_t MSTSIE	: 1;	// bit 7
		volatile uint32_t SXCIE		: 1;	// bit 8
		volatile uint32_t SNRIE		: 1;	// bit 9
		volatile uint32_t SOVFIE	: 1;	// bit 10
		volatile uint32_t STXEIE	: 1;	// bit 11
		volatile uint32_t SAIE		: 1;	// bit 12
		volatile uint32_t MDIV		: 4;	// bits 16 downto 13
		volatile uint32_t GCE		: 1;	// bit 17
		volatile uint32_t SCS		: 1;	// bit 18
		volatile uint32_t SN		: 1;	// bit 19
		volatile uint32_t SEN		: 1;	// bit 20
		volatile uint32_t MEN		: 1;	// bit 21
		volatile uint32_t __unused0	: 10;	// bits 31 downto 22
	};
} I2CxCR_Register_t;

// Bit fields structure for register I2CxFCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t MRB		: 1;	// bit 0
		volatile uint8_t MSP		: 1;	// bit 1
		volatile uint8_t MST		: 1;	// bit 2
		volatile uint8_t SC			: 1;	// bit 3
		volatile uint8_t __unused0	: 4;	// bits 7 downto 4
	};
} I2CxFCR_Register_t;

// Bit fields structure for register I2CxSR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t SPR	: 1;	// bit 0
		volatile uint16_t STR	: 1;	// bit 1
		volatile uint16_t MXC	: 1;	// bit 2
		volatile uint16_t MNR	: 1;	// bit 3
		volatile uint16_t MTXE	: 1;	// bit 4
		volatile uint16_t MARB	: 1;	// bit 5
		volatile uint16_t MSPS	: 1;	// bit 6
		volatile uint16_t MSTS	: 1;	// bit 7
		volatile uint16_t SXC	: 1;	// bit 8
		volatile uint16_t SNR	: 1;	// bit 9
		volatile uint16_t SOVF	: 1;	// bit 10
		volatile uint16_t STXE	: 1;	// bit 11
		volatile uint16_t SA	: 1;	// bit 12
		volatile uint16_t STM	: 1;	// bit 13
		volatile uint16_t MCB	: 1;	// bit 14
		volatile uint16_t BS	: 1;	// bit 15
	};
} I2CxSR_Register_t;

// Bit fields structure for register I2CxMTX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t MTX	: 8;	// bits 7 downto 0
	};
} I2CxMTX_Register_t;

// Bit fields structure for register I2CxMRX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t MRX	: 8;	// bits 7 downto 0
	};
} I2CxMRX_Register_t;

// Bit fields structure for register I2CxSTX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t STX	: 8;	// bits 7 downto 0
	};
} I2CxSTX_Register_t;

// Bit fields structure for register I2CxSRX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t SRX	: 8;	// bits 7 downto 0
	};
} I2CxSRX_Register_t;

// Bit fields structure for register I2CxAR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t AR			: 7;	// bits 6 downto 0
		volatile uint8_t __unused0	: 1;	// bit 7
	};
} I2CxAR_Register_t;

// Bit fields structure for register I2CxAMR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t AMR		: 7;	// bits 6 downto 0
		volatile uint8_t __unused0	: 1;	// bit 7
	};
} I2CxAMR_Register_t;



// Registers structure for peripheral I2Cx
typedef struct
{
	volatile I2CxCR_Register_t	CR;
	volatile I2CxFCR_Register_t	FCR;
	volatile uint8_t			__unused0;
	volatile uint16_t			__unused1;
	volatile I2CxSR_Register_t	SR;
	volatile uint16_t			__unused2;
	volatile I2CxMTX_Register_t	MTX;
	volatile uint8_t			__unused3;
	volatile uint16_t			__unused4;
	volatile I2CxMRX_Register_t	MRX;
	volatile uint8_t			__unused5;
	volatile uint16_t			__unused6;
	volatile I2CxSTX_Register_t	STX;
	volatile uint8_t			__unused7;
	volatile uint16_t			__unused8;
	volatile I2CxSRX_Register_t	SRX;
	volatile uint8_t			__unused9;
	volatile uint16_t			__unused10;
	volatile I2CxAR_Register_t	AR;
	volatile uint8_t			__unused11;
	volatile uint16_t			__unused12;
	volatile I2CxAMR_Register_t	AMR;
	volatile uint8_t			__unused13;
	volatile uint16_t			__unused14;
	volatile uint32_t			__unused15[55];
} I2Cx_t;
#define I2Cx_PTR(_I2Cx_BASE)	((I2Cx_t *) _I2Cx_BASE)


/********** Peripheral Structure Pointer Macros **********/

#define GPIO0	((GPIOx_8bit_t *) GPIO0_BASE)
#define GPIO1	((GPIOx_8bit_t *) GPIO1_BASE)
#define SPI0	((SPIx_t *) SPI0_BASE)
#define SPI1	((SPIx_t *) SPI1_BASE)
#define UART0	((UARTx_t *) UART0_BASE)
#define UART1	((UARTx_t *) UART1_BASE)
#define TIMER0	((TIMERx_t *) TIMER0_BASE)
#define TIMER1	((TIMERx_t *) TIMER1_BASE)
#define GPIO2	((GPIOx_8bit_t *) GPIO2_BASE)
#define SYSTEM	((SYSTEM_t *) SYSTEM_BASE)
#define NN0		((NNx_t *) NN0_BASE)
#define SARADC0	((SARADCx_t *) SARADC0_BASE)
#define AFE0	((AFEx_t *) AFE0_BASE)
#define GPIO3	((GPIOx_8bit_t *) GPIO3_BASE)
#define I2C0	((I2Cx_t *) I2C0_BASE)
#define I2C1	((I2Cx_t *) I2C1_BASE)



/********** GPIO Pins **********/

/** GPIO0 Pins **/
// P0.0 secondary function (when P0SEL(0) = '1'): CS_FLASH
#define CS_FLASH_BIT	(BIT0)
#define CS_FLASH_PxIN	(P0IN)
#define CS_FLASH_PxSEL	(P0SEL)
#define CS_FLASH_PxDIR	(P0DIR)
#define CS_FLASH_PxOUT	(P0OUT)
#define CS_FLASH_PxREN	(P0REN)
#define CS_FLASH_PxIE	(P0IE)
#define CS_FLASH_PxIES	(P0IES)
#define CS_FLASH_PxIFG	(P0IFG)

// P0.1 secondary function (when P0SEL(1) = '1'): MISO0
#define MISO0_BIT		(BIT1)
#define MISO0_PxIN		(P0IN)
#define MISO0_PxSEL		(P0SEL)
#define MISO0_PxDIR		(P0DIR)
#define MISO0_PxOUT		(P0OUT)
#define MISO0_PxREN		(P0REN)
#define MISO0_PxIE		(P0IE)
#define MISO0_PxIES		(P0IES)
#define MISO0_PxIFG		(P0IFG)

// P0.2 secondary function (when P0SEL(2) = '1'): MOSI0
#define MOSI0_BIT		(BIT2)
#define MOSI0_PxIN		(P0IN)
#define MOSI0_PxSEL		(P0SEL)
#define MOSI0_PxDIR		(P0DIR)
#define MOSI0_PxOUT		(P0OUT)
#define MOSI0_PxREN		(P0REN)
#define MOSI0_PxIE		(P0IE)
#define MOSI0_PxIES		(P0IES)
#define MOSI0_PxIFG		(P0IFG)

// P0.3 secondary function (when P0SEL(3) = '1'): SCK0
#define SCK0_BIT		(BIT3)
#define SCK0_PxIN		(P0IN)
#define SCK0_PxSEL		(P0SEL)
#define SCK0_PxDIR		(P0DIR)
#define SCK0_PxOUT		(P0OUT)
#define SCK0_PxREN		(P0REN)
#define SCK0_PxIE		(P0IE)
#define SCK0_PxIES		(P0IES)
#define SCK0_PxIFG		(P0IFG)

// P0.4 secondary function (when P0SEL(4) = '1'): LFXT
#define LFXT_BIT		(BIT4)
#define LFXT_PxIN		(P0IN)
#define LFXT_PxSEL		(P0SEL)
#define LFXT_PxDIR		(P0DIR)
#define LFXT_PxOUT		(P0OUT)
#define LFXT_PxREN		(P0REN)
#define LFXT_PxIE		(P0IE)
#define LFXT_PxIES		(P0IES)
#define LFXT_PxIFG		(P0IFG)

// P0.5 secondary function (when P0SEL(5) = '1'): HFXT
#define HFXT_BIT		(BIT5)
#define HFXT_PxIN		(P0IN)
#define HFXT_PxSEL		(P0SEL)
#define HFXT_PxDIR		(P0DIR)
#define HFXT_PxOUT		(P0OUT)
#define HFXT_PxREN		(P0REN)
#define HFXT_PxIE		(P0IE)
#define HFXT_PxIES		(P0IES)
#define HFXT_PxIFG		(P0IFG)

// P0.6 secondary function (when P0SEL(6) = '1'): TRAP
#define TRAP_BIT		(BIT6)
#define TRAP_PxIN		(P0IN)
#define TRAP_PxSEL		(P0SEL)
#define TRAP_PxDIR		(P0DIR)
#define TRAP_PxOUT		(P0OUT)
#define TRAP_PxREN		(P0REN)
#define TRAP_PxIE		(P0IE)
#define TRAP_PxIES		(P0IES)
#define TRAP_PxIFG		(P0IFG)

// P0.7 primary function (when P0SEL(7) = '0'): BOOT
#define BOOT_BIT		(BIT7)
#define BOOT_PxIN		(P0IN)
#define BOOT_PxOUT		(P0OUT)
#define BOOT_PxDIR		(P0DIR)
#define BOOT_PxIES		(P0IES)
#define BOOT_PxIFG		(P0IFG)
#define BOOT_PxIE		(P0IE)
#define BOOT_PxSEL		(P0SEL)
#define BOOT_PxREN		(P0REN)



/** GPIO1 Pins **/
// P1.0 secondary function (when P1SEL(0) = '1'): CS1
#define CS1_BIT			(BIT0)
#define CS1_PxIN		(P1IN)
#define CS1_PxSEL		(P1SEL)
#define CS1_PxDIR		(P1DIR)
#define CS1_PxOUT		(P1OUT)
#define CS1_PxREN		(P1REN)
#define CS1_PxIE		(P1IE)
#define CS1_PxIES		(P1IES)
#define CS1_PxIFG		(P1IFG)

// P1.1 secondary function (when P1SEL(1) = '1'): MISO1
#define MISO1_BIT		(BIT1)
#define MISO1_PxIN		(P1IN)
#define MISO1_PxSEL		(P1SEL)
#define MISO1_PxDIR		(P1DIR)
#define MISO1_PxOUT		(P1OUT)
#define MISO1_PxREN		(P1REN)
#define MISO1_PxIE		(P1IE)
#define MISO1_PxIES		(P1IES)
#define MISO1_PxIFG		(P1IFG)

// P1.2 secondary function (when P1SEL(2) = '1'): MOSI1
#define MOSI1_BIT		(BIT2)
#define MOSI1_PxIN		(P1IN)
#define MOSI1_PxSEL		(P1SEL)
#define MOSI1_PxDIR		(P1DIR)
#define MOSI1_PxOUT		(P1OUT)
#define MOSI1_PxREN		(P1REN)
#define MOSI1_PxIE		(P1IE)
#define MOSI1_PxIES		(P1IES)
#define MOSI1_PxIFG		(P1IFG)

// P1.3 secondary function (when P1SEL(3) = '1'): SCK1
#define SCK1_BIT		(BIT3)
#define SCK1_PxIN		(P1IN)
#define SCK1_PxSEL		(P1SEL)
#define SCK1_PxDIR		(P1DIR)
#define SCK1_PxOUT		(P1OUT)
#define SCK1_PxREN		(P1REN)
#define SCK1_PxIE		(P1IE)
#define SCK1_PxIES		(P1IES)
#define SCK1_PxIFG		(P1IFG)

// P1.4 secondary function (when P1SEL(4) = '1'): TX0
#define TX0_BIT			(BIT4)
#define TX0_PxIN		(P1IN)
#define TX0_PxSEL		(P1SEL)
#define TX0_PxDIR		(P1DIR)
#define TX0_PxOUT		(P1OUT)
#define TX0_PxREN		(P1REN)
#define TX0_PxIE		(P1IE)
#define TX0_PxIES		(P1IES)
#define TX0_PxIFG		(P1IFG)

// P1.5 secondary function (when P1SEL(5) = '1'): RX0
#define RX0_BIT			(BIT5)
#define RX0_PxIN		(P1IN)
#define RX0_PxSEL		(P1SEL)
#define RX0_PxDIR		(P1DIR)
#define RX0_PxOUT		(P1OUT)
#define RX0_PxREN		(P1REN)
#define RX0_PxIE		(P1IE)
#define RX0_PxIES		(P1IES)
#define RX0_PxIFG		(P1IFG)

// P1.6 secondary function (when P1SEL(6) = '1'): TX1
#define TX1_BIT			(BIT6)
#define TX1_PxIN		(P1IN)
#define TX1_PxSEL		(P1SEL)
#define TX1_PxDIR		(P1DIR)
#define TX1_PxOUT		(P1OUT)
#define TX1_PxREN		(P1REN)
#define TX1_PxIE		(P1IE)
#define TX1_PxIES		(P1IES)
#define TX1_PxIFG		(P1IFG)

// P1.7 secondary function (when P1SEL(7) = '1'): RX1
#define RX1_BIT			(BIT7)
#define RX1_PxIN		(P1IN)
#define RX1_PxSEL		(P1SEL)
#define RX1_PxDIR		(P1DIR)
#define RX1_PxOUT		(P1OUT)
#define RX1_PxREN		(P1REN)
#define RX1_PxIE		(P1IE)
#define RX1_PxIES		(P1IES)
#define RX1_PxIFG		(P1IFG)



/** GPIO2 Pins **/
// P2.0 secondary function (when P2SEL(0) = '1'): T0CMP0
#define T0CMP0_BIT		(BIT0)
#define T0CMP0_PxIN		(P2IN)
#define T0CMP0_PxSEL	(P2SEL)
#define T0CMP0_PxDIR	(P2DIR)
#define T0CMP0_PxOUT	(P2OUT)
#define T0CMP0_PxREN	(P2REN)
#define T0CMP0_PxIE		(P2IE)
#define T0CMP0_PxIES	(P2IES)
#define T0CMP0_PxIFG	(P2IFG)

// P2.1 secondary function (when P2SEL(1) = '1'): T0CMP1
#define T0CMP1_BIT		(BIT1)
#define T0CMP1_PxIN		(P2IN)
#define T0CMP1_PxSEL	(P2SEL)
#define T0CMP1_PxDIR	(P2DIR)
#define T0CMP1_PxOUT	(P2OUT)
#define T0CMP1_PxREN	(P2REN)
#define T0CMP1_PxIE		(P2IE)
#define T0CMP1_PxIES	(P2IES)
#define T0CMP1_PxIFG	(P2IFG)

// P2.2 secondary function (when P2SEL(2) = '1'): T0CAP0
#define T0CAP0_BIT		(BIT2)
#define T0CAP0_PxIN		(P2IN)
#define T0CAP0_PxSEL	(P2SEL)
#define T0CAP0_PxDIR	(P2DIR)
#define T0CAP0_PxOUT	(P2OUT)
#define T0CAP0_PxREN	(P2REN)
#define T0CAP0_PxIE		(P2IE)
#define T0CAP0_PxIES	(P2IES)
#define T0CAP0_PxIFG	(P2IFG)

// P2.3 secondary function (when P2SEL(3) = '1'): T0CAP1
#define T0CAP1_BIT		(BIT3)
#define T0CAP1_PxIN		(P2IN)
#define T0CAP1_PxSEL	(P2SEL)
#define T0CAP1_PxDIR	(P2DIR)
#define T0CAP1_PxOUT	(P2OUT)
#define T0CAP1_PxREN	(P2REN)
#define T0CAP1_PxIE		(P2IE)
#define T0CAP1_PxIES	(P2IES)
#define T0CAP1_PxIFG	(P2IFG)

// P2.4 secondary function (when P2SEL(4) = '1'): T1CMP0
#define T1CMP0_BIT		(BIT4)
#define T1CMP0_PxIN		(P2IN)
#define T1CMP0_PxSEL	(P2SEL)
#define T1CMP0_PxDIR	(P2DIR)
#define T1CMP0_PxOUT	(P2OUT)
#define T1CMP0_PxREN	(P2REN)
#define T1CMP0_PxIE		(P2IE)
#define T1CMP0_PxIES	(P2IES)
#define T1CMP0_PxIFG	(P2IFG)

// P2.5 secondary function (when P2SEL(5) = '1'): T1CMP1
#define T1CMP1_BIT		(BIT5)
#define T1CMP1_PxIN		(P2IN)
#define T1CMP1_PxSEL	(P2SEL)
#define T1CMP1_PxDIR	(P2DIR)
#define T1CMP1_PxOUT	(P2OUT)
#define T1CMP1_PxREN	(P2REN)
#define T1CMP1_PxIE		(P2IE)
#define T1CMP1_PxIES	(P2IES)
#define T1CMP1_PxIFG	(P2IFG)

// P2.6 secondary function (when P2SEL(6) = '1'): T1CAP0
#define T1CAP0_BIT		(BIT6)
#define T1CAP0_PxIN		(P2IN)
#define T1CAP0_PxSEL	(P2SEL)
#define T1CAP0_PxDIR	(P2DIR)
#define T1CAP0_PxOUT	(P2OUT)
#define T1CAP0_PxREN	(P2REN)
#define T1CAP0_PxIE		(P2IE)
#define T1CAP0_PxIES	(P2IES)
#define T1CAP0_PxIFG	(P2IFG)

// P2.7 secondary function (when P2SEL(7) = '1'): T1CAP1
#define T1CAP1_BIT		(BIT7)
#define T1CAP1_PxIN		(P2IN)
#define T1CAP1_PxSEL	(P2SEL)
#define T1CAP1_PxDIR	(P2DIR)
#define T1CAP1_PxOUT	(P2OUT)
#define T1CAP1_PxREN	(P2REN)
#define T1CAP1_PxIE		(P2IE)
#define T1CAP1_PxIES	(P2IES)
#define T1CAP1_PxIFG	(P2IFG)



/** GPIO3 Pins **/
// P3.0 secondary function (when P3SEL(0) = '1'): SDA0
#define SDA0_BIT		(BIT0)
#define SDA0_PxIN		(P3IN)
#define SDA0_PxSEL		(P3SEL)
#define SDA0_PxDIR		(P3DIR)
#define SDA0_PxOUT		(P3OUT)
#define SDA0_PxREN		(P3REN)
#define SDA0_PxIE		(P3IE)
#define SDA0_PxIES		(P3IES)
#define SDA0_PxIFG		(P3IFG)

// P3.1 secondary function (when P3SEL(1) = '1'): SCL0
#define SCL0_BIT		(BIT1)
#define SCL0_PxIN		(P3IN)
#define SCL0_PxSEL		(P3SEL)
#define SCL0_PxDIR		(P3DIR)
#define SCL0_PxOUT		(P3OUT)
#define SCL0_PxREN		(P3REN)
#define SCL0_PxIE		(P3IE)
#define SCL0_PxIES		(P3IES)
#define SCL0_PxIFG		(P3IFG)

// P3.2 secondary function (when P3SEL(2) = '1'): SDA1
#define SDA1_BIT		(BIT2)
#define SDA1_PxIN		(P3IN)
#define SDA1_PxSEL		(P3SEL)
#define SDA1_PxDIR		(P3DIR)
#define SDA1_PxOUT		(P3OUT)
#define SDA1_PxREN		(P3REN)
#define SDA1_PxIE		(P3IE)
#define SDA1_PxIES		(P3IES)
#define SDA1_PxIFG		(P3IFG)

// P3.3 secondary function (when P3SEL(3) = '1'): SCL1
#define SCL1_BIT		(BIT3)
#define SCL1_PxIN		(P3IN)
#define SCL1_PxSEL		(P3SEL)
#define SCL1_PxDIR		(P3DIR)
#define SCL1_PxOUT		(P3OUT)
#define SCL1_PxREN		(P3REN)
#define SCL1_PxIE		(P3IE)
#define SCL1_PxIES		(P3IES)
#define SCL1_PxIFG		(P3IFG)

// P3.4 secondary function (when P3SEL(4) = '1'): DTP0
#define DTP0_BIT		(BIT4)
#define DTP0_PxIN		(P3IN)
#define DTP0_PxSEL		(P3SEL)
#define DTP0_PxDIR		(P3DIR)
#define DTP0_PxOUT		(P3OUT)
#define DTP0_PxREN		(P3REN)
#define DTP0_PxIE		(P3IE)
#define DTP0_PxIES		(P3IES)
#define DTP0_PxIFG		(P3IFG)

// P3.5 secondary function (when P3SEL(5) = '1'): DTP1
#define DTP1_BIT		(BIT5)
#define DTP1_PxIN		(P3IN)
#define DTP1_PxSEL		(P3SEL)
#define DTP1_PxDIR		(P3DIR)
#define DTP1_PxOUT		(P3OUT)
#define DTP1_PxREN		(P3REN)
#define DTP1_PxIE		(P3IE)
#define DTP1_PxIES		(P3IES)
#define DTP1_PxIFG		(P3IFG)

// P3.6 secondary function (when P3SEL(6) = '1'): DTP2
#define DTP2_BIT		(BIT6)
#define DTP2_PxIN		(P3IN)
#define DTP2_PxSEL		(P3SEL)
#define DTP2_PxDIR		(P3DIR)
#define DTP2_PxOUT		(P3OUT)
#define DTP2_PxREN		(P3REN)
#define DTP2_PxIE		(P3IE)
#define DTP2_PxIES		(P3IES)
#define DTP2_PxIFG		(P3IFG)

// P3.7 secondary function (when P3SEL(7) = '1'): DTP3
#define DTP3_BIT		(BIT7)
#define DTP3_PxIN		(P3IN)
#define DTP3_PxSEL		(P3SEL)
#define DTP3_PxDIR		(P3DIR)
#define DTP3_PxOUT		(P3OUT)
#define DTP3_PxREN		(P3REN)
#define DTP3_PxIE		(P3IE)
#define DTP3_PxIES		(P3IES)
#define DTP3_PxIFG		(P3IFG)



/********** Interrupt Vectors **********/

#define IRQ_SYSTEM_VECTOR			0	// 0x8000
#define IRQ_EBREAK_VECTOR			1	// 0x8004 (called when EBREAK, ECALL, or illegal instruction occurrs)
#define IRQ_BUS_ERROR_VECTOR		2	// 0x8008 (called when an unaligned memory access occurs)
#define IRQ_SPI0_VECTOR				9	// 0x8024
#define IRQ_SPI1_VECTOR				11	// 0x802C
#define IRQ_UART0_VECTOR			13	// 0x8034
#define IRQ_TIMER0_VECTOR			16	// 0x8040
#define IRQ_TIMER1_VECTOR			22	// 0x8058
#define IRQ_GPIO1_VECTOR			28	// 0x8070



#define IRQ_0_VECTOR				0	// 0x8000
#define IRQ_1_VECTOR				1	// 0x8004
#define IRQ_2_VECTOR				2	// 0x8008
#define IRQ_3_VECTOR				3	// 0x800C
#define IRQ_4_VECTOR				4	// 0x8010
#define IRQ_5_VECTOR				5	// 0x8014
#define IRQ_6_VECTOR				6	// 0x8018
#define IRQ_7_VECTOR				7	// 0x801C
#define IRQ_8_VECTOR				8	// 0x8020
#define IRQ_9_VECTOR				9	// 0x8024
#define IRQ_10_VECTOR				10	// 0x8028
#define IRQ_11_VECTOR				11	// 0x802C
#define IRQ_12_VECTOR				12	// 0x8030
#define IRQ_13_VECTOR				13	// 0x8034
#define IRQ_14_VECTOR				14	// 0x8038
#define IRQ_15_VECTOR				15	// 0x803C
#define IRQ_16_VECTOR				16	// 0x8040
#define IRQ_17_VECTOR				17	// 0x8044
#define IRQ_18_VECTOR				18	// 0x8048
#define IRQ_19_VECTOR				19	// 0x804C
#define IRQ_20_VECTOR				20	// 0x8050
#define IRQ_21_VECTOR				21	// 0x8054
#define IRQ_22_VECTOR				22	// 0x8058
#define IRQ_23_VECTOR				23	// 0x805C
#define IRQ_24_VECTOR				24	// 0x8060
#define IRQ_25_VECTOR				25	// 0x8064
#define IRQ_26_VECTOR				26	// 0x8068
#define IRQ_27_VECTOR				27	// 0x806C
#define IRQ_28_VECTOR				28	// 0x8070
#define IRQ_29_VECTOR				29	// 0x8074
#define IRQ_30_VECTOR				30	// 0x8078
#define IRQ_31_VECTOR				31	// 0x807C

#define LAST_POPULATED_IRQ_VECTOR	28



#ifdef __cplusplus
}
#endif	// extern "C"
