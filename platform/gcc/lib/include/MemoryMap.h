/**
 **	MemoryMap.h
 **	Memory map definition header file
 **	Defines the microcontroller peripheral and register addresses, as well as the bit field bit masks
 **	Generated on 2026/04/20 at 16:30:37 with the MemoryMap.py memory map generator
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
#define INTERRUPT_VECTOR_TABLE_SIZE			(0x014C)
#define RAM_PROGRAM_START_ADDRESS			(0x814C)
#define INTERRUPT_HANDLER_ADDRESS			(0x9000)
#define PERIPHERAL_SPACING					(0x0100)	// The number of bytes between each adjacent peripheral base address
#define STACK_POINTER_INIT					(0x10000)
#define BOOTLOADER_USES_SPI_FLASH_COMMANDS

#define RAM_SLOT_SIZE						(16384)
#define LAST_RAM_SLOT_SIZE					(16384)
#define SRAM03_ADDRESS						(0x0C000)
#define SRAM04_ADDRESS						(0x10000)

#define SPI_FLASH_PROGRAM_ADDRESS			(0x8200)

#define HAS_NATIVE_SPI_FLASH_MEMORY_READ_ACCESS
// Does not have native SPI Flash memory write access
#define SPI_FLASH_MEM_ADDRESS	(0x01000000)
#define SPI_FLASH_MEM			((volatile uint32_t *) (SPI_FLASH_MEM_ADDRESS))



/** Chip Properties **/



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

// PxREN
#define PxREN_OFFSET			(24)
#define PxREN_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxREN_OFFSET)

// PxSEL
#define PxSEL_OFFSET			(28)
#define PxSEL_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxSEL_OFFSET)

// PxIF
#define PxIF_OFFSET				(32)
#define PxIF_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIF_OFFSET)

// PxIES
#define PxIES_OFFSET			(36)
#define PxIES_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIES_OFFSET)

// PxIE
#define PxIE_OFFSET				(40)
#define PxIE_PTR(_GPIOx_BASE)	MMR_32_PTR(_GPIOx_BASE, PxIE_OFFSET)



/** SPIx **/
// SPIxCR
#define SPIxCR_OFFSET			(0)
#define SPIxCR_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxCR_OFFSET)

#define SPIFEN_BIT	(0x00080000)	// bit 19
#define SPIFEN_LSB	(19)
#define SPISM_BIT	(0x00040000)	// bit 18
#define SPISM_LSB	(18)
#define SPITXSB_BIT	(0x00020000)	// bit 17
#define SPITXSB_LSB	(17)
#define SPIRXSB_BIT	(0x00010000)	// bit 16
#define SPIRXSB_LSB	(16)
#define SPIBR_MASK	(0x0000FF00)	// bits 15 downto 8
#define SPIBR_LSB	(8)
#define SPIEN_BIT	(0x00000080)	// bit 7
#define SPIEN_LSB	(7)
#define SPIMSB_BIT	(0x00000040)	// bit 6
#define SPIMSB_LSB	(6)
#define SPITCIE_BIT	(0x00000020)	// bit 5
#define SPITCIE_LSB	(5)
#define SPITEIE_BIT	(0x00000010)	// bit 4
#define SPITEIE_LSB	(4)
#define SPIDL_MASK	(0x0000000C)	// bits 3 downto 2
#define SPIDL_LSB	(2)
#define SPIDL_8		(0x00000000)
#define SPIDL_16	(0x00000004)
#define SPIDL_32	(0x00000008)
#define SPIDL_RES	(0x0000000C)
#define SPICPOL_BIT	(0x00000002)	// bit 1
#define SPICPOL_LSB	(1)
#define SPICPHA_BIT	(0x00000001)	// bit 0
#define SPICPHA_LSB	(0)

// SPIxSR
#define SPIxSR_OFFSET			(4)
#define SPIxSR_PTR(_SPIx_BASE)	MMR_08_PTR(_SPIx_BASE, SPIxSR_OFFSET)

#define SPIBUSY_BIT	(0x04)	// bit 2
#define SPIBUSY_LSB	(2)
#define SPITCIF_BIT	(0x02)	// bit 1
#define SPITCIF_LSB	(1)
#define SPITEIF_BIT	(0x01)	// bit 0
#define SPITEIF_LSB	(0)

// SPIxTX
#define SPIxTX_OFFSET			(8)
#define SPIxTX_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxTX_OFFSET)

#define SPITX_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SPITX_LSB	(0)

// SPIxRX
#define SPIxRX_OFFSET			(12)
#define SPIxRX_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxRX_OFFSET)

#define SPIRX_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SPIRX_LSB	(0)

// SPIxFOS
#define SPIxFOS_OFFSET			(16)
#define SPIxFOS_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxFOS_OFFSET)

#define SPIFOS_MASK	(0x00FFFFFF)	// bits 23 downto 0
#define SPIFOS_LSB	(0)



/** UARTx **/
// UARTxCR
#define UARTxCR_OFFSET				(0)
#define UARTxCR_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxCR_OFFSET)

#define UEN_BIT		(0x20)	// bit 5
#define UEN_LSB		(5)
#define UPEN_BIT	(0x10)	// bit 4
#define UPEN_LSB	(4)
#define PSEL_BIT	(0x08)	// bit 3
#define PSEL_LSB	(3)
#define CIE_BIT		(0x04)	// bit 2
#define CIE_LSB		(2)
#define TEIE_BIT	(0x02)	// bit 1
#define TEIE_LSB	(1)
#define TCIE_BIT	(0x01)	// bit 0
#define TCIE_LSB	(0)

// UARTxSR
#define UARTxSR_OFFSET				(4)
#define UARTxSR_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxSR_OFFSET)

#define RXBF_BIT	(0x80)	// bit 7
#define RXBF_LSB	(7)
#define TXBF_BIT	(0x40)	// bit 6
#define TXBF_LSB	(6)
#define FEF_BIT		(0x20)	// bit 5
#define FEF_LSB		(5)
#define PEF_BIT		(0x10)	// bit 4
#define PEF_LSB		(4)
#define OVF_BIT		(0x08)	// bit 3
#define OVF_LSB		(3)
#define RCIF_BIT	(0x04)	// bit 2
#define RCIF_LSB	(2)
#define TEIF_BIT	(0x02)	// bit 1
#define TEIF_LSB	(1)
#define TCIF_BIT	(0x01)	// bit 0
#define TCIF_LSB	(0)

// UARTxBR
#define UARTxBR_OFFSET				(8)
#define UARTxBR_PTR(_UARTx_BASE)	MMR_16_PTR(_UARTx_BASE, UARTxBR_OFFSET)

#define BR_MASK	(0x0FFF)	// bits 11 downto 0
#define BR_LSB	(0)

// UARTxRX
#define UARTxRX_OFFSET				(12)
#define UARTxRX_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxRX_OFFSET)

#define RX_MASK	(0xFF)	// bits 7 downto 0
#define RX_LSB	(0)

// UARTxTX
#define UARTxTX_OFFSET				(16)
#define UARTxTX_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxTX_OFFSET)

#define TX_MASK	(0xFF)	// bits 7 downto 0
#define TX_LSB	(0)



/** TIMERx **/
// TIMxCR
#define TIMxCR_OFFSET				(0)
#define TIMxCR_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCR_OFFSET)

#define DIV_MASK	(0x000F0000)	// bits 19 downto 16
#define DIV_LSB		(16)
#define DIV_1		(0x00000000)
#define DIV_2		(0x00010000)
#define DIV_4		(0x00020000)
#define DIV_8		(0x00030000)
#define DIV_16		(0x00040000)
#define DIV_32		(0x00050000)
#define DIV_64		(0x00060000)
#define DIV_128		(0x00070000)
#define DIV_256		(0x00080000)
#define DIV_512		(0x00090000)
#define DIV_1024	(0x000A0000)
#define DIV_2048	(0x000B0000)
#define DIV_4096	(0x000C0000)
#define DIV_8192	(0x000D0000)
#define DIV_16384	(0x000E0000)
#define DIV_32768	(0x000F0000)
#define CMP1IH_BIT	(0x00008000)	// bit 15
#define CMP1IH_LSB	(15)
#define CMP0IH_BIT	(0x00004000)	// bit 14
#define CMP0IH_LSB	(14)
#define CAP1FE_BIT	(0x00002000)	// bit 13
#define CAP1FE_LSB	(13)
#define CAP0FE_BIT	(0x00001000)	// bit 12
#define CAP0FE_LSB	(12)
#define CAP1EN_BIT	(0x00000800)	// bit 11
#define CAP1EN_LSB	(11)
#define CAP0EN_BIT	(0x00000400)	// bit 10
#define CAP0EN_LSB	(10)
#define SSEL_MASK	(0x00000300)	// bits 9 downto 8
#define SSEL_LSB	(8)
#define SSEL_SMCLK	(0x00000000)
#define SSEL_MCLK	(0x00000100)
#define SSEL_LFXT	(0x00000200)
#define SSEL_HFXT	(0x00000300)
#define CMP2RST_BIT	(0x00000080)	// bit 7
#define CMP2RST_LSB	(7)
#define TEN_BIT		(0x00000040)	// bit 6
#define TEN_LSB		(6)
#define CAP1IE_BIT	(0x00000020)	// bit 5
#define CAP1IE_LSB	(5)
#define CAP0IE_BIT	(0x00000010)	// bit 4
#define CAP0IE_LSB	(4)
#define OVIE_BIT	(0x00000008)	// bit 3
#define OVIE_LSB	(3)
#define CMP2IE_BIT	(0x00000004)	// bit 2
#define CMP2IE_LSB	(2)
#define CMP1IE_BIT	(0x00000002)	// bit 1
#define CMP1IE_LSB	(1)
#define CMP0IE_BIT	(0x00000001)	// bit 0
#define CMP0IE_LSB	(0)

// TIMxSR
#define TIMxSR_OFFSET				(4)
#define TIMxSR_PTR(_TIMERx_BASE)	MMR_08_PTR(_TIMERx_BASE, TIMxSR_OFFSET)

#define CMP1OUT_BIT	(0x80)	// bit 7
#define CMP1OUT_LSB	(7)
#define CMP0OUT_BIT	(0x40)	// bit 6
#define CMP0OUT_LSB	(6)
#define CAP1IF_BIT	(0x20)	// bit 5
#define CAP1IF_LSB	(5)
#define CAP0IF_BIT	(0x10)	// bit 4
#define CAP0IF_LSB	(4)
#define OVIF_BIT	(0x08)	// bit 3
#define OVIF_LSB	(3)
#define CMP2IF_BIT	(0x04)	// bit 2
#define CMP2IF_LSB	(2)
#define CMP1IF_BIT	(0x02)	// bit 1
#define CMP1IF_LSB	(1)
#define CMP0IF_BIT	(0x01)	// bit 0
#define CMP0IF_LSB	(0)

// TIMxVAL
#define TIMxVAL_OFFSET				(8)
#define TIMxVAL_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxVAL_OFFSET)

#define VAL_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define VAL_LSB		(0)

// TIMxCMP0
#define TIMxCMP0_OFFSET				(12)
#define TIMxCMP0_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP0_OFFSET)

#define CMP0_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define CMP0_LSB	(0)

// TIMxCMP1
#define TIMxCMP1_OFFSET				(16)
#define TIMxCMP1_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP1_OFFSET)

#define CMP1_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define CMP1_LSB	(0)

// TIMxCMP2
#define TIMxCMP2_OFFSET				(20)
#define TIMxCMP2_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP2_OFFSET)

#define CMP2_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define CMP2_LSB	(0)

// TIMxCAP0
#define TIMxCAP0_OFFSET				(24)
#define TIMxCAP0_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCAP0_OFFSET)

#define CAP0_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define CAP0_LSB	(0)

// TIMxCAP1
#define TIMxCAP1_OFFSET				(28)
#define TIMxCAP1_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCAP1_OFFSET)

#define CAP1_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define CAP1_LSB	(0)



/** SYSTEM **/
// SYSCLKCR
#define SYSCLKCR_OFFSET				(0)
#define SYSCLKCR_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, SYSCLKCR_OFFSET)

#define DCO1ON_BIT		(0x0100)	// bit 8
#define DCO1ON_LSB		(8)
#define DCO0ON_BIT		(0x0080)	// bit 7
#define DCO0ON_LSB		(7)
#define HFXTOFF_BIT		(0x0040)	// bit 6
#define HFXTOFF_LSB		(6)
#define LFXTOFF_BIT		(0x0020)	// bit 5
#define LFXTOFF_LSB		(5)
#define SMCLKOFF_BIT	(0x0010)	// bit 4
#define SMCLKOFF_LSB	(4)
#define SMCLKSEL_MASK	(0x000C)	// bits 3 downto 2
#define SMCLKSEL_LSB	(2)
#define SMCLKSEL_HFXT	(0x0000)
#define SMCLKSEL_LFXT	(0x0004)
#define SMCLKSEL_DCO0	(0x0008)
#define SMCLKSEL_DCO1	(0x000C)
#define MCLKSEL_MASK	(0x0003)	// bits 1 downto 0
#define MCLKSEL_LSB		(0)
#define MCLKSEL_HFXT	(0x0000)
#define MCLKSEL_SMCLK	(0x0001)
#define MCLKSEL_DCO0	(0x0002)
#define MCLKSEL_DCO1	(0x0003)

// CLKDIVCR
#define CLKDIVCR_OFFSET				(4)
#define CLKDIVCR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, CLKDIVCR_OFFSET)

#define SYSSMCLKDIV_MASK	(0x38)	// bits 5 downto 3
#define SYSSMCLKDIV_LSB		(3)
#define SYSSMCLKDIV_1		(0x00)
#define SYSSMCLKDIV_2		(0x08)
#define SYSSMCLKDIV_4		(0x10)
#define SYSSMCLKDIV_8		(0x18)
#define SYSSMCLKDIV_16		(0x20)
#define SYSSMCLKDIV_32		(0x28)
#define SYSSMCLKDIV_64		(0x30)
#define SYSSMCLKDIV_128		(0x38)
#define SYSMCLKDIV_MASK		(0x07)	// bits 2 downto 0
#define SYSMCLKDIV_LSB		(0)
#define SYSMCLKDIV_1		(0x00)
#define SYSMCLKDIV_2		(0x01)
#define SYSMCLKDIV_4		(0x02)
#define SYSMCLKDIV_8		(0x03)
#define SYSMCLKDIV_16		(0x04)
#define SYSMCLKDIV_32		(0x05)
#define SYSMCLKDIV_64		(0x06)
#define SYSMCLKDIV_128		(0x07)

// BLOCKPWR
#define BLOCKPWR_OFFSET				(8)
#define BLOCKPWR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, BLOCKPWR_OFFSET)

#define SYSRAM1OFF_BIT	(0x04)	// bit 2
#define SYSRAM1OFF_LSB	(2)
#define SYSRAM0OFF_BIT	(0x02)	// bit 1
#define SYSRAM0OFF_LSB	(1)
#define SYSROMOFF_BIT	(0x01)	// bit 0
#define SYSROMOFF_LSB	(0)

// CRCDATA
#define CRCDATA_OFFSET				(12)
#define CRCDATA_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, CRCDATA_OFFSET)

#define SYSCRCDATA_MASK	(0xFF)	// bits 7 downto 0
#define SYSCRCDATA_LSB	(0)

// CRCSTATE
#define CRCSTATE_OFFSET				(16)
#define CRCSTATE_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, CRCSTATE_OFFSET)

#define SYSCRCSTATE_MASK	(0xFFFF)	// bits 15 downto 0
#define SYSCRCSTATE_LSB		(0)

// IRQENL
#define IRQENL_OFFSET				(20)
#define IRQENL_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQENL_OFFSET)

#define SYSIRQENL_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSIRQENL_LSB	(0)

// IRQENM
#define IRQENM_OFFSET				(24)
#define IRQENM_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQENM_OFFSET)

#define SYSIRQENM_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSIRQENM_LSB	(0)

// IRQENU
#define IRQENU_OFFSET				(28)
#define IRQENU_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQENU_OFFSET)

#define SYSIRQENU_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSIRQENU_LSB	(0)

// IRQPRIL
#define IRQPRIL_OFFSET				(32)
#define IRQPRIL_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQPRIL_OFFSET)

#define SYSIRQPRIL_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSIRQPRIL_LSB	(0)

// IRQPRIM
#define IRQPRIM_OFFSET				(36)
#define IRQPRIM_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQPRIM_OFFSET)

#define SYSIRQPRIM_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSIRQPRIM_LSB	(0)

// IRQPRIU
#define IRQPRIU_OFFSET				(40)
#define IRQPRIU_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, IRQPRIU_OFFSET)

#define SYSIRQPRIU_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSIRQPRIU_LSB	(0)

// IRQCR
#define IRQCR_OFFSET			(44)
#define IRQCR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, IRQCR_OFFSET)

#define SYSIRQRECEN_BIT	(0x02)	// bit 1
#define SYSIRQRECEN_LSB	(1)
#define SYSIRQGEN_BIT	(0x01)	// bit 0
#define SYSIRQGEN_LSB	(0)

// WDTCR
#define WDTCR_OFFSET			(48)
#define WDTCR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, WDTCR_OFFSET)

#define SYSWDTEN_BIT			(0x80)	// bit 7
#define SYSWDTEN_LSB			(7)
#define SYSWDTCDIV_MASK			(0x3C)	// bits 5 downto 2
#define SYSWDTCDIV_LSB			(2)
#define SYSWDTCDIV_65536		(0x00)
#define SYSWDTCDIV_131072		(0x04)
#define SYSWDTCDIV_262144		(0x08)
#define SYSWDTCDIV_524288		(0x0C)
#define SYSWDTCDIV_1048576		(0x10)
#define SYSWDTCDIV_2097152		(0x14)
#define SYSWDTCDIV_4194304		(0x18)
#define SYSWDTCDIV_8388608		(0x1C)
#define SYSWDTCDIV_16777216		(0x20)
#define SYSWDTCDIV_33554432		(0x24)
#define SYSWDTCDIV_67108864		(0x28)
#define SYSWDTCDIV_134217728	(0x2C)
#define SYSWDTCDIV_268435456	(0x30)
#define SYSWDTCDIV_536870912	(0x34)
#define SYSWDTCDIV_1073741824	(0x38)
#define SYSWDTCDIV_2147483648	(0x3C)
#define SYSWDTIE_BIT			(0x02)	// bit 1
#define SYSWDTIE_LSB			(1)
#define SYSWDTHWRST_BIT			(0x01)	// bit 0
#define SYSWDTHWRST_LSB			(0)

// WDTSR
#define WDTSR_OFFSET			(52)
#define WDTSR_PTR(_SYSTEM_BASE)	MMR_08_PTR(_SYSTEM_BASE, WDTSR_OFFSET)

#define SYSWDTIF_BIT	(0x02)	// bit 1
#define SYSWDTIF_LSB	(1)
#define SYSWDTRF_BIT	(0x01)	// bit 0
#define SYSWDTRF_LSB	(0)

// WDTPASS
#define WDTPASS_OFFSET				(56)
#define WDTPASS_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, WDTPASS_OFFSET)

#define SYSWDTPASS_MASK	(0xFFFFFFFF)	// bits 31 downto 0
#define SYSWDTPASS_LSB	(0)

// WDTVAL
#define WDTVAL_OFFSET				(60)
#define WDTVAL_PTR(_SYSTEM_BASE)	MMR_32_PTR(_SYSTEM_BASE, WDTVAL_OFFSET)

#define SYSWDTVAL_MASK	(0x00FFFFFF)	// bits 23 downto 0
#define SYSWDTVAL_LSB	(0)

// DCO0BIAS
#define DCO0BIAS_OFFSET				(64)
#define DCO0BIAS_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, DCO0BIAS_OFFSET)

#define SYSDCO0BIAS_MASK	(0x0FFF)	// bits 11 downto 0
#define SYSDCO0BIAS_LSB		(0)

// DCO1BIAS
#define DCO1BIAS_OFFSET				(68)
#define DCO1BIAS_PTR(_SYSTEM_BASE)	MMR_16_PTR(_SYSTEM_BASE, DCO1BIAS_OFFSET)

#define SYSDCO1BIAS_MASK	(0x0FFF)	// bits 11 downto 0
#define SYSDCO1BIAS_LSB		(0)



/** NPU **/
// NPUCR
#define NPUCR_OFFSET			(0)
#define NPUCR_PTR(_NPU_BASE)	MMR_32_PTR(_NPU_BASE, NPUCR_OFFSET)

#define NPUBEN_BIT		(0x00040000)	// bit 18
#define NPUBEN_LSB		(18)
#define NPUAEN_BIT		(0x00020000)	// bit 17
#define NPUAEN_LSB		(17)
#define NPUTHINK_BIT	(0x00010000)	// bit 16
#define NPUTHINK_LSB	(16)
#define NPUNI_MASK		(0x0000FF00)	// bits 15 downto 8
#define NPUNI_LSB		(8)
#define NPUNN_MASK		(0x000000FF)	// bits 7 downto 0
#define NPUNN_LSB		(0)

// NPUIVSAR
#define NPUIVSAR_OFFSET			(4)
#define NPUIVSAR_PTR(_NPU_BASE)	MMR_32_PTR(_NPU_BASE, NPUIVSAR_OFFSET)

// NPUWVSAR
#define NPUWVSAR_OFFSET			(8)
#define NPUWVSAR_PTR(_NPU_BASE)	MMR_32_PTR(_NPU_BASE, NPUWVSAR_OFFSET)

// NPUOVSAR
#define NPUOVSAR_OFFSET			(12)
#define NPUOVSAR_PTR(_NPU_BASE)	MMR_32_PTR(_NPU_BASE, NPUOVSAR_OFFSET)



/** SARADC **/
// SARADC_CR
#define SARADC_CR_OFFSET			(0)
#define SARADC_CR_PTR(_SARADC_BASE)	MMR_16_PTR(_SARADC_BASE, SARADC_CR_OFFSET)

#define SARADCCONTMEAS_BIT		(0x0100)	// bit 8
#define SARADCCONTMEAS_LSB		(8)
#define SARADCDATAIE_BIT		(0x0080)	// bit 7
#define SARADCDATAIE_LSB		(7)
#define SARADCDEBUG_BIT			(0x0040)	// bit 6
#define SARADCDEBUG_LSB			(6)
#define SARADCEN_BIT			(0x0020)	// bit 5
#define SARADCEN_LSB			(5)
#define SARADCSAMPLESTEP_MASK	(0x001E)	// bits 4 downto 1
#define SARADCSAMPLESTEP_LSB	(1)
#define SARADCRESET_BIT			(0x0001)	// bit 0
#define SARADCRESET_LSB			(0)

// SARADC_CDIV
#define SARADC_CDIV_OFFSET				(4)
#define SARADC_CDIV_PTR(_SARADC_BASE)	MMR_08_PTR(_SARADC_BASE, SARADC_CDIV_OFFSET)

#define SARADCCDIV_MASK	(0xFF)	// bits 7 downto 0
#define SARADCCDIV_LSB	(0)

// SARADC_SR
#define SARADC_SR_OFFSET			(8)
#define SARADC_SR_PTR(_SARADC_BASE)	MMR_08_PTR(_SARADC_BASE, SARADC_SR_OFFSET)

#define SARADCRDY_BIT		(0x08)	// bit 3
#define SARADCRDY_LSB		(3)
#define SARADCOVF_BIT		(0x04)	// bit 2
#define SARADCOVF_LSB		(2)
#define SARADCDATAVALID_BIT	(0x02)	// bit 1
#define SARADCDATAVALID_LSB	(1)
#define SARADCBUSY_BIT		(0x01)	// bit 0
#define SARADCBUSY_LSB		(0)

// SARADC_DATA
#define SARADC_DATA_OFFSET				(12)
#define SARADC_DATA_PTR(_SARADC_BASE)	MMR_16_PTR(_SARADC_BASE, SARADC_DATA_OFFSET)

#define SARADCDATA_MASK	(0x03FF)	// bits 9 downto 0
#define SARADCDATA_LSB	(0)

// SARADC_TPR
#define SARADC_TPR_OFFSET				(16)
#define SARADC_TPR_PTR(_SARADC_BASE)	MMR_08_PTR(_SARADC_BASE, SARADC_TPR_OFFSET)

#define SARADCDTP1SEL_MASK	(0xF0)	// bits 7 downto 4
#define SARADCDTP1SEL_LSB	(4)
#define SARADCDTP0SEL_MASK	(0x0F)	// bits 3 downto 0
#define SARADCDTP0SEL_LSB	(0)



/** AFE **/
// AFE_CR
#define AFE_CR_OFFSET			(0)
#define AFE_CR_PTR(_AFE_BASE)	MMR_32_PTR(_AFE_BASE, AFE_CR_OFFSET)

#define AFE_RAMPNUM_MASK	(0x00FFF000)	// bits 23 downto 12
#define AFE_RAMPNUM_LSB		(12)
#define AFE_ADCSEL_BIT		(0x00000800)	// bit 11
#define AFE_ADCSEL_LSB		(11)
#define AFE_ATPSEL_BIT		(0x00000400)	// bit 10
#define AFE_ATPSEL_LSB		(10)
#define AFE_ATPEN_BIT		(0x00000200)	// bit 9
#define AFE_ATPEN_LSB		(9)
#define AFE_ADCEXTIN_BIT	(0x00000100)	// bit 8
#define AFE_ADCEXTIN_LSB	(8)
#define AFE_CONTMEAS_BIT	(0x00000010)	// bit 4
#define AFE_CONTMEAS_LSB	(4)
#define AFE_DACEN_BIT		(0x00000008)	// bit 3
#define AFE_DACEN_LSB		(3)
#define AFE_DATARDYIE_BIT	(0x00000004)	// bit 2
#define AFE_DATARDYIE_LSB	(2)
#define AFE_EN_BIT			(0x00000002)	// bit 1
#define AFE_EN_LSB			(1)
#define AFE_ADCEN_BIT		(0x00000001)	// bit 0
#define AFE_ADCEN_LSB		(0)

// AFE_TPR
#define AFE_TPR_OFFSET			(4)
#define AFE_TPR_PTR(_AFE_BASE)	MMR_32_PTR(_AFE_BASE, AFE_TPR_OFFSET)

#define AFE_DTP3SEL_MASK	(0x000F8000)	// bits 19 downto 15
#define AFE_DTP3SEL_LSB		(15)
#define AFE_DTP2SEL_MASK	(0x00007C00)	// bits 14 downto 10
#define AFE_DTP2SEL_LSB		(10)
#define AFE_DTP1SEL_MASK	(0x000003E0)	// bits 9 downto 5
#define AFE_DTP1SEL_LSB		(5)
#define AFE_DTP0SEL_MASK	(0x0000001F)	// bits 4 downto 0
#define AFE_DTP0SEL_LSB		(0)

// AFE_SR
#define AFE_SR_OFFSET			(8)
#define AFE_SR_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, AFE_SR_OFFSET)

#define AFE_OVFIF_BIT		(0x04)	// bit 2
#define AFE_OVFIF_LSB		(2)
#define AFE_DATARDYIF_BIT	(0x02)	// bit 1
#define AFE_DATARDYIF_LSB	(1)
#define AFE_ADCACTIVE_BIT	(0x01)	// bit 0
#define AFE_ADCACTIVE_LSB	(0)

// AFE_ADC_VAL
#define AFE_ADC_VAL_OFFSET			(12)
#define AFE_ADC_VAL_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, AFE_ADC_VAL_OFFSET)

#define AFE_ADCVAL_MASK	(0x0FFF)	// bits 11 downto 0
#define AFE_ADCVAL_LSB	(0)

// BIAS_CR
#define BIAS_CR_OFFSET			(16)
#define BIAS_CR_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_CR_OFFSET)

#define USEDAC_BIT	(0x10)	// bit 4
#define USEDAC_LSB	(4)
#define BUFEN_BIT	(0x08)	// bit 3
#define BUFEN_LSB	(3)
#define EN_BIT		(0x04)	// bit 2
#define EN_LSB		(2)

// BIAS_ADJ
#define BIAS_ADJ_OFFSET			(20)
#define BIAS_ADJ_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_ADJ_OFFSET)

#define ADJ_MASK	(0x3F)	// bits 5 downto 0
#define ADJ_LSB		(0)

// BIAS_DBP
#define BIAS_DBP_OFFSET			(24)
#define BIAS_DBP_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, BIAS_DBP_OFFSET)

#define DBP_MASK	(0x3FFF)	// bits 13 downto 0
#define DBP_LSB		(0)

// BIAS_DBPC
#define BIAS_DBPC_OFFSET			(28)
#define BIAS_DBPC_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, BIAS_DBPC_OFFSET)

#define DBPC_MASK	(0x3FFF)	// bits 13 downto 0
#define DBPC_LSB	(0)

// BIAS_DBNC
#define BIAS_DBNC_OFFSET			(32)
#define BIAS_DBNC_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, BIAS_DBNC_OFFSET)

#define DBNC_MASK	(0x3FFF)	// bits 13 downto 0
#define DBNC_LSB	(0)

// BIAS_DBN
#define BIAS_DBN_OFFSET			(36)
#define BIAS_DBN_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, BIAS_DBN_OFFSET)

#define DBN_MASK	(0x3FFF)	// bits 13 downto 0
#define DBN_LSB		(0)

// BIAS_TC_POT
#define BIAS_TC_POT_OFFSET			(40)
#define BIAS_TC_POT_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_TC_POT_OFFSET)

#define TC_POT_MASK	(0x3F)	// bits 5 downto 0
#define TC_POT_LSB	(0)

// BIAS_LC_POT
#define BIAS_LC_POT_OFFSET			(44)
#define BIAS_LC_POT_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_LC_POT_OFFSET)

#define LC_POT_MASK	(0x3F)	// bits 5 downto 0
#define LC_POT_LSB	(0)

// BIAS_TIA_G_POT
#define BIAS_TIA_G_POT_OFFSET			(48)
#define BIAS_TIA_G_POT_PTR(_AFE_BASE)	MMR_32_PTR(_AFE_BASE, BIAS_TIA_G_POT_OFFSET)

#define TIA_G_POT_MASK	(0x0001FFFF)	// bits 16 downto 0
#define TIA_G_POT_LSB	(0)

// BIAS_DSADC_VCM
#define BIAS_DSADC_VCM_OFFSET			(52)
#define BIAS_DSADC_VCM_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, BIAS_DSADC_VCM_OFFSET)

#define DSADC_VCM_MASK	(0x3FFF)	// bits 13 downto 0
#define DSADC_VCM_LSB	(0)

// BIAS_REV_POT
#define BIAS_REV_POT_OFFSET			(56)
#define BIAS_REV_POT_PTR(_AFE_BASE)	MMR_16_PTR(_AFE_BASE, BIAS_REV_POT_OFFSET)

#define REV_POT_MASK	(0x3FFF)	// bits 13 downto 0
#define REV_POT_LSB		(0)

// BIAS_TC_DSADC
#define BIAS_TC_DSADC_OFFSET			(60)
#define BIAS_TC_DSADC_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_TC_DSADC_OFFSET)

#define TC_DSADC_MASK	(0x3F)	// bits 5 downto 0
#define TC_DSADC_LSB	(0)

// BIAS_LC_DSADC
#define BIAS_LC_DSADC_OFFSET			(64)
#define BIAS_LC_DSADC_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_LC_DSADC_OFFSET)

#define LC_DSADC_MASK	(0x3F)	// bits 5 downto 0
#define LC_DSADC_LSB	(0)

// BIAS_RIN_DSADC
#define BIAS_RIN_DSADC_OFFSET			(68)
#define BIAS_RIN_DSADC_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_RIN_DSADC_OFFSET)

#define RIN_DSADC_MASK	(0x3F)	// bits 5 downto 0
#define RIN_DSADC_LSB	(0)

// BIAS_RFB_DSADC
#define BIAS_RFB_DSADC_OFFSET			(72)
#define BIAS_RFB_DSADC_PTR(_AFE_BASE)	MMR_08_PTR(_AFE_BASE, BIAS_RFB_DSADC_OFFSET)

#define RFB_DSADC_MASK	(0x3F)	// bits 5 downto 0
#define RFB_DSADC_LSB	(0)



/** I2Cx **/
// I2CxCR
#define I2CxCR_OFFSET			(0)
#define I2CxCR_PTR(_I2Cx_BASE)	MMR_32_PTR(_I2Cx_BASE, I2CxCR_OFFSET)

#define I2CMEN_BIT		(0x00200000)	// bit 21
#define I2CMEN_LSB		(21)
#define I2CSEN_BIT		(0x00100000)	// bit 20
#define I2CSEN_LSB		(20)
#define I2CSN_BIT		(0x00080000)	// bit 19
#define I2CSN_LSB		(19)
#define I2CSCS_BIT		(0x00040000)	// bit 18
#define I2CSCS_LSB		(18)
#define I2CGCE_BIT		(0x00020000)	// bit 17
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
#define I2CSAIE_BIT		(0x00001000)	// bit 12
#define I2CSAIE_LSB		(12)
#define I2CSTXEIE_BIT	(0x00000800)	// bit 11
#define I2CSTXEIE_LSB	(11)
#define I2CSOVFIE_BIT	(0x00000400)	// bit 10
#define I2CSOVFIE_LSB	(10)
#define I2CSNRIE_BIT	(0x00000200)	// bit 9
#define I2CSNRIE_LSB	(9)
#define I2CSXCIE_BIT	(0x00000100)	// bit 8
#define I2CSXCIE_LSB	(8)
#define I2CMSTSIE_BIT	(0x00000080)	// bit 7
#define I2CMSTSIE_LSB	(7)
#define I2CMSPSIE_BIT	(0x00000040)	// bit 6
#define I2CMSPSIE_LSB	(6)
#define I2CMARBIE_BIT	(0x00000020)	// bit 5
#define I2CMARBIE_LSB	(5)
#define I2CMTXEIE_BIT	(0x00000010)	// bit 4
#define I2CMTXEIE_LSB	(4)
#define I2CMNRIE_BIT	(0x00000008)	// bit 3
#define I2CMNRIE_LSB	(3)
#define I2CMXCIE_BIT	(0x00000004)	// bit 2
#define I2CMXCIE_LSB	(2)
#define I2CSTRIE_BIT	(0x00000002)	// bit 1
#define I2CSTRIE_LSB	(1)
#define I2CSPRIE_BIT	(0x00000001)	// bit 0
#define I2CSPRIE_LSB	(0)

// I2CxFCR
#define I2CxFCR_OFFSET			(4)
#define I2CxFCR_PTR(_I2Cx_BASE)	MMR_08_PTR(_I2Cx_BASE, I2CxFCR_OFFSET)

#define I2CSC_BIT	(0x08)	// bit 3
#define I2CSC_LSB	(3)
#define I2CMST_BIT	(0x04)	// bit 2
#define I2CMST_LSB	(2)
#define I2CMSP_BIT	(0x02)	// bit 1
#define I2CMSP_LSB	(1)
#define I2CMRB_BIT	(0x01)	// bit 0
#define I2CMRB_LSB	(0)

// I2CxSR
#define I2CxSR_OFFSET			(8)
#define I2CxSR_PTR(_I2Cx_BASE)	MMR_16_PTR(_I2Cx_BASE, I2CxSR_OFFSET)

#define I2CBS_BIT	(0x8000)	// bit 15
#define I2CBS_LSB	(15)
#define I2CMCB_BIT	(0x4000)	// bit 14
#define I2CMCB_LSB	(14)
#define I2CSTM_BIT	(0x2000)	// bit 13
#define I2CSTM_LSB	(13)
#define I2CSA_BIT	(0x1000)	// bit 12
#define I2CSA_LSB	(12)
#define I2CSTXE_BIT	(0x0800)	// bit 11
#define I2CSTXE_LSB	(11)
#define I2CSOVF_BIT	(0x0400)	// bit 10
#define I2CSOVF_LSB	(10)
#define I2CSNR_BIT	(0x0200)	// bit 9
#define I2CSNR_LSB	(9)
#define I2CSXC_BIT	(0x0100)	// bit 8
#define I2CSXC_LSB	(8)
#define I2CMSTS_BIT	(0x0080)	// bit 7
#define I2CMSTS_LSB	(7)
#define I2CMSPS_BIT	(0x0040)	// bit 6
#define I2CMSPS_LSB	(6)
#define I2CMARB_BIT	(0x0020)	// bit 5
#define I2CMARB_LSB	(5)
#define I2CMTXE_BIT	(0x0010)	// bit 4
#define I2CMTXE_LSB	(4)
#define I2CMNR_BIT	(0x0008)	// bit 3
#define I2CMNR_LSB	(3)
#define I2CMXC_BIT	(0x0004)	// bit 2
#define I2CMXC_LSB	(2)
#define I2CSTR_BIT	(0x0002)	// bit 1
#define I2CSTR_LSB	(1)
#define I2CSPR_BIT	(0x0001)	// bit 0
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
#define GPIO0_BASE				(0x4000)

#define P0IN_ADDRESS			(0x4000)
#define P0OUT_ADDRESS			(0x4004)
#define P0OUTS_ADDRESS			(0x4008)
#define P0OUTC_ADDRESS			(0x400C)
#define P0OUTT_ADDRESS			(0x4010)
#define P0DIR_ADDRESS			(0x4014)
#define P0REN_ADDRESS			(0x4018)
#define P0SEL_ADDRESS			(0x401C)
#define P0IF_ADDRESS			(0x4020)
#define P0IES_ADDRESS			(0x4024)
#define P0IE_ADDRESS			(0x4028)



/** GPIO1 **/
#define GPIO1_BASE				(0x4100)

#define P1IN_ADDRESS			(0x4100)
#define P1OUT_ADDRESS			(0x4104)
#define P1OUTS_ADDRESS			(0x4108)
#define P1OUTC_ADDRESS			(0x410C)
#define P1OUTT_ADDRESS			(0x4110)
#define P1DIR_ADDRESS			(0x4114)
#define P1REN_ADDRESS			(0x4118)
#define P1SEL_ADDRESS			(0x411C)
#define P1IF_ADDRESS			(0x4120)
#define P1IES_ADDRESS			(0x4124)
#define P1IE_ADDRESS			(0x4128)



/** SPI0 **/
#define SPI0_BASE				(0x4200)

#define SPI0CR_ADDRESS			(0x4200)
#define SPI0SR_ADDRESS			(0x4204)
#define SPI0TX_ADDRESS			(0x4208)
#define SPI0RX_ADDRESS			(0x420C)
#define SPI0FOS_ADDRESS			(0x4210)



/** SPI1 **/
#define SPI1_BASE				(0x4300)

#define SPI1CR_ADDRESS			(0x4300)
#define SPI1SR_ADDRESS			(0x4304)
#define SPI1TX_ADDRESS			(0x4308)
#define SPI1RX_ADDRESS			(0x430C)
#define SPI1FOS_ADDRESS			(0x4310)



/** UART0 **/
#define UART0_BASE				(0x4400)

#define UART0CR_ADDRESS			(0x4400)
#define UART0SR_ADDRESS			(0x4404)
#define UART0BR_ADDRESS			(0x4408)
#define UART0RX_ADDRESS			(0x440C)
#define UART0TX_ADDRESS			(0x4410)



/** UART1 **/
#define UART1_BASE				(0x4500)

#define UART1CR_ADDRESS			(0x4500)
#define UART1SR_ADDRESS			(0x4504)
#define UART1BR_ADDRESS			(0x4508)
#define UART1RX_ADDRESS			(0x450C)
#define UART1TX_ADDRESS			(0x4510)



/** TIMER0 **/
#define TIMER0_BASE				(0x4600)

#define TIM0CR_ADDRESS			(0x4600)
#define TIM0SR_ADDRESS			(0x4604)
#define TIM0VAL_ADDRESS			(0x4608)
#define TIM0CMP0_ADDRESS		(0x460C)
#define TIM0CMP1_ADDRESS		(0x4610)
#define TIM0CMP2_ADDRESS		(0x4614)
#define TIM0CAP0_ADDRESS		(0x4618)
#define TIM0CAP1_ADDRESS		(0x461C)



/** TIMER1 **/
#define TIMER1_BASE				(0x4700)

#define TIM1CR_ADDRESS			(0x4700)
#define TIM1SR_ADDRESS			(0x4704)
#define TIM1VAL_ADDRESS			(0x4708)
#define TIM1CMP0_ADDRESS		(0x470C)
#define TIM1CMP1_ADDRESS		(0x4710)
#define TIM1CMP2_ADDRESS		(0x4714)
#define TIM1CAP0_ADDRESS		(0x4718)
#define TIM1CAP1_ADDRESS		(0x471C)



/** GPIO2 **/
#define GPIO2_BASE				(0x4800)

#define P2IN_ADDRESS			(0x4800)
#define P2OUT_ADDRESS			(0x4804)
#define P2OUTS_ADDRESS			(0x4808)
#define P2OUTC_ADDRESS			(0x480C)
#define P2OUTT_ADDRESS			(0x4810)
#define P2DIR_ADDRESS			(0x4814)
#define P2REN_ADDRESS			(0x4818)
#define P2SEL_ADDRESS			(0x481C)
#define P2IF_ADDRESS			(0x4820)
#define P2IES_ADDRESS			(0x4824)
#define P2IE_ADDRESS			(0x4828)



/** SYSTEM **/
#define SYSTEM_BASE				(0x4900)

#define SYSCLKCR_ADDRESS		(0x4900)
#define CLKDIVCR_ADDRESS		(0x4904)
#define BLOCKPWR_ADDRESS		(0x4908)
#define CRCDATA_ADDRESS			(0x490C)
#define CRCSTATE_ADDRESS		(0x4910)
#define IRQENL_ADDRESS			(0x4914)
#define IRQENM_ADDRESS			(0x4918)
#define IRQENU_ADDRESS			(0x491C)
#define IRQPRIL_ADDRESS			(0x4920)
#define IRQPRIM_ADDRESS			(0x4924)
#define IRQPRIU_ADDRESS			(0x4928)
#define IRQCR_ADDRESS			(0x492C)
#define WDTCR_ADDRESS			(0x4930)
#define WDTSR_ADDRESS			(0x4934)
#define WDTPASS_ADDRESS			(0x4938)
#define WDTVAL_ADDRESS			(0x493C)
#define DCO0BIAS_ADDRESS		(0x4940)
#define DCO1BIAS_ADDRESS		(0x4944)



/** NPU **/
#define NPU_BASE				(0x4A00)

#define NPUCR_ADDRESS			(0x4A00)
#define NPUIVSAR_ADDRESS		(0x4A04)
#define NPUWVSAR_ADDRESS		(0x4A08)
#define NPUOVSAR_ADDRESS		(0x4A0C)



/** SARADC **/
#define SARADC_BASE				(0x4B00)

#define SARADC_CR_ADDRESS		(0x4B00)
#define SARADC_CDIV_ADDRESS		(0x4B04)
#define SARADC_SR_ADDRESS		(0x4B08)
#define SARADC_DATA_ADDRESS		(0x4B0C)
#define SARADC_TPR_ADDRESS		(0x4B10)



/** AFE **/
#define AFE_BASE				(0x4C00)

#define AFE_CR_ADDRESS			(0x4C00)
#define AFE_TPR_ADDRESS			(0x4C04)
#define AFE_SR_ADDRESS			(0x4C08)
#define AFE_ADC_VAL_ADDRESS		(0x4C0C)
#define BIAS_CR_ADDRESS			(0x4C10)
#define BIAS_ADJ_ADDRESS		(0x4C14)
#define BIAS_DBP_ADDRESS		(0x4C18)
#define BIAS_DBPC_ADDRESS		(0x4C1C)
#define BIAS_DBNC_ADDRESS		(0x4C20)
#define BIAS_DBN_ADDRESS		(0x4C24)
#define BIAS_TC_POT_ADDRESS		(0x4C28)
#define BIAS_LC_POT_ADDRESS		(0x4C2C)
#define BIAS_TIA_G_POT_ADDRESS	(0x4C30)
#define BIAS_DSADC_VCM_ADDRESS	(0x4C34)
#define BIAS_REV_POT_ADDRESS	(0x4C38)
#define BIAS_TC_DSADC_ADDRESS	(0x4C3C)
#define BIAS_LC_DSADC_ADDRESS	(0x4C40)
#define BIAS_RIN_DSADC_ADDRESS	(0x4C44)
#define BIAS_RFB_DSADC_ADDRESS	(0x4C48)



/** GPIO3 **/
#define GPIO3_BASE				(0x4D00)

#define P3IN_ADDRESS			(0x4D00)
#define P3OUT_ADDRESS			(0x4D04)
#define P3OUTS_ADDRESS			(0x4D08)
#define P3OUTC_ADDRESS			(0x4D0C)
#define P3OUTT_ADDRESS			(0x4D10)
#define P3DIR_ADDRESS			(0x4D14)
#define P3REN_ADDRESS			(0x4D18)
#define P3SEL_ADDRESS			(0x4D1C)
#define P3IF_ADDRESS			(0x4D20)
#define P3IES_ADDRESS			(0x4D24)
#define P3IE_ADDRESS			(0x4D28)



/** I2C0 **/
#define I2C0_BASE				(0x4E00)

#define I2C0CR_ADDRESS			(0x4E00)
#define I2C0FCR_ADDRESS			(0x4E04)
#define I2C0SR_ADDRESS			(0x4E08)
#define I2C0MTX_ADDRESS			(0x4E0C)
#define I2C0MRX_ADDRESS			(0x4E10)
#define I2C0STX_ADDRESS			(0x4E14)
#define I2C0SRX_ADDRESS			(0x4E18)
#define I2C0AR_ADDRESS			(0x4E1C)
#define I2C0AMR_ADDRESS			(0x4E20)



/** I2C1 **/
#define I2C1_BASE				(0x4F00)

#define I2C1CR_ADDRESS			(0x4F00)
#define I2C1FCR_ADDRESS			(0x4F04)
#define I2C1SR_ADDRESS			(0x4F08)
#define I2C1MTX_ADDRESS			(0x4F0C)
#define I2C1MRX_ADDRESS			(0x4F10)
#define I2C1STX_ADDRESS			(0x4F14)
#define I2C1SRX_ADDRESS			(0x4F18)
#define I2C1AR_ADDRESS			(0x4F1C)
#define I2C1AMR_ADDRESS			(0x4F20)



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
	volatile GPIO_8bit_Register_t	REN;
	volatile uint8_t				__unused12;
	volatile uint16_t				__unused13;
	volatile GPIO_8bit_Register_t	SEL;
	volatile uint8_t				__unused14;
	volatile uint16_t				__unused15;
	volatile GPIO_8bit_Register_t	IF;
	volatile uint8_t				__unused16;
	volatile uint16_t				__unused17;
	volatile GPIO_8bit_Register_t	IES;
	volatile uint8_t				__unused18;
	volatile uint16_t				__unused19;
	volatile GPIO_8bit_Register_t	IE;
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
	volatile GPIO_16bit_Register_t	REN;
	volatile uint16_t				__unused6;
	volatile GPIO_16bit_Register_t	SEL;
	volatile uint16_t				__unused7;
	volatile GPIO_16bit_Register_t	IF;
	volatile uint16_t				__unused8;
	volatile GPIO_16bit_Register_t	IES;
	volatile uint16_t				__unused9;
	volatile GPIO_16bit_Register_t	IE;
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
	volatile GPIO_32bit_Register_t	REN;
	volatile GPIO_32bit_Register_t	SEL;
	volatile GPIO_32bit_Register_t	IF;
	volatile GPIO_32bit_Register_t	IES;
	volatile GPIO_32bit_Register_t	IE;
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
		volatile uint8_t TCIE_		: 1;	// bit 0
		volatile uint8_t TEIE_		: 1;	// bit 1
		volatile uint8_t CIE_		: 1;	// bit 2
		volatile uint8_t PSEL_		: 1;	// bit 3
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
		volatile uint8_t TCIF_	: 1;	// bit 0
		volatile uint8_t TEIF_	: 1;	// bit 1
		volatile uint8_t RCIF_	: 1;	// bit 2
		volatile uint8_t OVF_	: 1;	// bit 3
		volatile uint8_t PEF_	: 1;	// bit 4
		volatile uint8_t FEF_	: 1;	// bit 5
		volatile uint8_t TXBF_	: 1;	// bit 6
		volatile uint8_t RXBF_	: 1;	// bit 7
	};
} UARTxSR_Register_t;

// Bit fields structure for register UARTxBR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t BR_		: 12;	// bits 11 downto 0
		volatile uint16_t __unused0	: 4;	// bits 15 downto 12
	};
} UARTxBR_Register_t;

// Bit fields structure for register UARTxRX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t RX_	: 8;	// bits 7 downto 0
	};
} UARTxRX_Register_t;

// Bit fields structure for register UARTxTX
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TX_	: 8;	// bits 7 downto 0
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
		volatile uint32_t CMP0IE_	: 1;	// bit 0
		volatile uint32_t CMP1IE_	: 1;	// bit 1
		volatile uint32_t CMP2IE_	: 1;	// bit 2
		volatile uint32_t OVIE_		: 1;	// bit 3
		volatile uint32_t CAP0IE_	: 1;	// bit 4
		volatile uint32_t CAP1IE_	: 1;	// bit 5
		volatile uint32_t EN		: 1;	// bit 6
		volatile uint32_t CMP2RST_	: 1;	// bit 7
		volatile uint32_t SSEL_		: 2;	// bits 9 downto 8
		volatile uint32_t CAP0EN_	: 1;	// bit 10
		volatile uint32_t CAP1EN_	: 1;	// bit 11
		volatile uint32_t CAP0FE_	: 1;	// bit 12
		volatile uint32_t CAP1FE_	: 1;	// bit 13
		volatile uint32_t CMP0IH_	: 1;	// bit 14
		volatile uint32_t CMP1IH_	: 1;	// bit 15
		volatile uint32_t DIV_		: 4;	// bits 19 downto 16
		volatile uint32_t __unused0	: 12;	// bits 31 downto 20
	};
} TIMxCR_Register_t;

// Bit fields structure for register TIMxSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CMP0IF_	: 1;	// bit 0
		volatile uint8_t CMP1IF_	: 1;	// bit 1
		volatile uint8_t CMP2IF_	: 1;	// bit 2
		volatile uint8_t OVIF_		: 1;	// bit 3
		volatile uint8_t CAP0IF_	: 1;	// bit 4
		volatile uint8_t CAP1IF_	: 1;	// bit 5
		volatile uint8_t CMP0OUT_	: 1;	// bit 6
		volatile uint8_t CMP1OUT_	: 1;	// bit 7
	};
} TIMxSR_Register_t;

// Bit fields structure for register TIMxVAL
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t VAL_	: 32;	// bits 31 downto 0
	};
} TIMxVAL_Register_t;

// Bit fields structure for register TIMxCMP0
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP0_	: 32;	// bits 31 downto 0
	};
} TIMxCMP0_Register_t;

// Bit fields structure for register TIMxCMP1
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP1_	: 32;	// bits 31 downto 0
	};
} TIMxCMP1_Register_t;

// Bit fields structure for register TIMxCMP2
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CMP2_	: 32;	// bits 31 downto 0
	};
} TIMxCMP2_Register_t;

// Bit fields structure for register TIMxCAP0
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CAP0_	: 32;	// bits 31 downto 0
	};
} TIMxCAP0_Register_t;

// Bit fields structure for register TIMxCAP1
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CAP1_	: 32;	// bits 31 downto 0
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
		volatile uint16_t SMCLKSEL_	: 2;	// bits 3 downto 2
		volatile uint16_t SMCLKOFF_	: 1;	// bit 4
		volatile uint16_t LFXTOFF_	: 1;	// bit 5
		volatile uint16_t HFXTOFF_	: 1;	// bit 6
		volatile uint16_t DCO0ON_	: 1;	// bit 7
		volatile uint16_t DCO1ON_	: 1;	// bit 8
		volatile uint16_t __unused0	: 7;	// bits 15 downto 9
	};
} SYSCLKCR_Register_t;

// Bit fields structure for register CLKDIVCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t MCLKDIV	: 3;	// bits 2 downto 0
		volatile uint8_t SMCLKDIV	: 3;	// bits 5 downto 3
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} CLKDIVCR_Register_t;

// Bit fields structure for register BLOCKPWR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t ROMOFF		: 1;	// bit 0
		volatile uint8_t RAM0OFF	: 1;	// bit 1
		volatile uint8_t RAM1OFF	: 1;	// bit 2
		volatile uint8_t __unused0	: 5;	// bits 7 downto 3
	};
} BLOCKPWR_Register_t;

// Bit fields structure for register CRCDATA
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CRCDATA	: 8;	// bits 7 downto 0
	};
} CRCDATA_Register_t;

// Bit fields structure for register CRCSTATE
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t CRCSTATE	: 16;	// bits 15 downto 0
	};
} CRCSTATE_Register_t;

// Bit fields structure for register IRQENL
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQENL	: 32;	// bits 31 downto 0
	};
} IRQENL_Register_t;

// Bit fields structure for register IRQENM
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQENM	: 32;	// bits 31 downto 0
	};
} IRQENM_Register_t;

// Bit fields structure for register IRQENU
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQENU	: 32;	// bits 31 downto 0
	};
} IRQENU_Register_t;

// Bit fields structure for register IRQPRIL
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQPRIL	: 32;	// bits 31 downto 0
	};
} IRQPRIL_Register_t;

// Bit fields structure for register IRQPRIM
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQPRIM	: 32;	// bits 31 downto 0
	};
} IRQPRIM_Register_t;

// Bit fields structure for register IRQPRIU
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t IRQPRIU	: 32;	// bits 31 downto 0
	};
} IRQPRIU_Register_t;

// Bit fields structure for register IRQCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t IRQGEN		: 1;	// bit 0
		volatile uint8_t IRQRECEN	: 1;	// bit 1
		volatile uint8_t __unused0	: 6;	// bits 7 downto 2
	};
} IRQCR_Register_t;

// Bit fields structure for register WDTCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t WDTHWRST	: 1;	// bit 0
		volatile uint8_t WDTIE		: 1;	// bit 1
		volatile uint8_t WDTCDIV	: 4;	// bits 5 downto 2
		volatile uint8_t __unused0	: 1;	// bit 6
		volatile uint8_t WDTEN		: 1;	// bit 7
	};
} WDTCR_Register_t;

// Bit fields structure for register WDTSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t WDTRF		: 1;	// bit 0
		volatile uint8_t WDTIF		: 1;	// bit 1
		volatile uint8_t __unused0	: 6;	// bits 7 downto 2
	};
} WDTSR_Register_t;

// Bit fields structure for register WDTPASS
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t WDTPASS	: 32;	// bits 31 downto 0
	};
} WDTPASS_Register_t;

// Bit fields structure for register WDTVAL
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t WDTVAL	: 24;	// bits 23 downto 0
		volatile uint32_t __unused0	: 8;	// bits 31 downto 24
	};
} WDTVAL_Register_t;

// Bit fields structure for register DCO0BIAS
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DCO0BIAS	: 12;	// bits 11 downto 0
		volatile uint16_t __unused0	: 4;	// bits 15 downto 12
	};
} DCO0BIAS_Register_t;

// Bit fields structure for register DCO1BIAS
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DCO1BIAS	: 12;	// bits 11 downto 0
		volatile uint16_t __unused0	: 4;	// bits 15 downto 12
	};
} DCO1BIAS_Register_t;



// Registers structure for peripheral SYSTEM
typedef struct
{
	volatile SYSCLKCR_Register_t	SYSCLKCR_;
	volatile uint16_t				__unused0;
	volatile CLKDIVCR_Register_t	CLKDIVCR_;
	volatile uint8_t				__unused1;
	volatile uint16_t				__unused2;
	volatile BLOCKPWR_Register_t	BLOCKPWR_;
	volatile uint8_t				__unused3;
	volatile uint16_t				__unused4;
	volatile CRCDATA_Register_t		CRCDATA_;
	volatile uint8_t				__unused5;
	volatile uint16_t				__unused6;
	volatile CRCSTATE_Register_t	CRCSTATE_;
	volatile uint16_t				__unused7;
	volatile IRQENL_Register_t		IRQENL_;
	volatile IRQENM_Register_t		IRQENM_;
	volatile IRQENU_Register_t		IRQENU_;
	volatile IRQPRIL_Register_t		IRQPRIL_;
	volatile IRQPRIM_Register_t		IRQPRIM_;
	volatile IRQPRIU_Register_t		IRQPRIU_;
	volatile IRQCR_Register_t		IRQCR_;
	volatile uint8_t				__unused8;
	volatile uint16_t				__unused9;
	volatile WDTCR_Register_t		WDTCR_;
	volatile uint8_t				__unused10;
	volatile uint16_t				__unused11;
	volatile WDTSR_Register_t		WDTSR_;
	volatile uint8_t				__unused12;
	volatile uint16_t				__unused13;
	volatile WDTPASS_Register_t		WDTPASS_;
	volatile WDTVAL_Register_t		WDTVAL_;
	volatile DCO0BIAS_Register_t	DCO0BIAS_;
	volatile uint16_t				__unused14;
	volatile DCO1BIAS_Register_t	DCO1BIAS_;
	volatile uint16_t				__unused15;
	volatile uint32_t				__unused16[46];
} SYSTEM_t;

/** Peripheral NPU **/
// Bit fields structure for register NPUCR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t NN		: 8;	// bits 7 downto 0
		volatile uint32_t NI		: 8;	// bits 15 downto 8
		volatile uint32_t THINK		: 1;	// bit 16
		volatile uint32_t AEN		: 1;	// bit 17
		volatile uint32_t BEN		: 1;	// bit 18
		volatile uint32_t __unused0	: 13;	// bits 31 downto 19
	};
} NPUCR_Register_t;

// Bit fields structure for register NPUIVSAR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t __unused0	: 2;	// bits 1 downto 0
		volatile uint32_t IVSAR		: 12;	// bits 13 downto 2
		volatile uint32_t __unused1	: 18;	// bits 31 downto 14
	};
} NPUIVSAR_Register_t;

// Bit fields structure for register NPUWVSAR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t __unused0	: 2;	// bits 1 downto 0
		volatile uint32_t WVSAR		: 12;	// bits 13 downto 2
		volatile uint32_t __unused1	: 18;	// bits 31 downto 14
	};
} NPUWVSAR_Register_t;

// Bit fields structure for register NPUOVSAR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t __unused0	: 2;	// bits 1 downto 0
		volatile uint32_t OVSAR		: 12;	// bits 13 downto 2
		volatile uint32_t __unused1	: 18;	// bits 31 downto 14
	};
} NPUOVSAR_Register_t;



// Registers structure for peripheral NPU
typedef struct
{
	volatile NPUCR_Register_t		CR;
	volatile NPUIVSAR_Register_t	IVSAR;
	volatile NPUWVSAR_Register_t	WVSAR;
	volatile NPUOVSAR_Register_t	OVSAR;
	volatile uint32_t				__unused0[60];
} NPU_t;

/** Peripheral SARADC **/
// Bit fields structure for register SARADC_CR
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
} SARADC_CR_Register_t;

// Bit fields structure for register SARADC_CDIV
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t CDIV	: 8;	// bits 7 downto 0
	};
} SARADC_CDIV_Register_t;

// Bit fields structure for register SARADC_SR
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
} SARADC_SR_Register_t;

// Bit fields structure for register SARADC_DATA
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DATA		: 10;	// bits 9 downto 0
		volatile uint16_t __unused0	: 6;	// bits 15 downto 10
	};
} SARADC_DATA_Register_t;

// Bit fields structure for register SARADC_TPR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t DTP0SEL	: 4;	// bits 3 downto 0
		volatile uint8_t DTP1SEL	: 4;	// bits 7 downto 4
	};
} SARADC_TPR_Register_t;



// Registers structure for peripheral SARADC
typedef struct
{
	volatile SARADC_CR_Register_t	_CR;
	volatile uint16_t				__unused0;
	volatile SARADC_CDIV_Register_t	_CDIV;
	volatile uint8_t				__unused1;
	volatile uint16_t				__unused2;
	volatile SARADC_SR_Register_t	_SR;
	volatile uint8_t				__unused3;
	volatile uint16_t				__unused4;
	volatile SARADC_DATA_Register_t	_DATA;
	volatile uint16_t				__unused5;
	volatile SARADC_TPR_Register_t	_TPR;
	volatile uint8_t				__unused6;
	volatile uint16_t				__unused7;
	volatile uint32_t				__unused8[59];
} SARADC_t;

/** Peripheral AFE **/
// Bit fields structure for register AFE_CR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t ADCEN		: 1;	// bit 0
		volatile uint32_t EN		: 1;	// bit 1
		volatile uint32_t DATARDYIE	: 1;	// bit 2
		volatile uint32_t DACEN		: 1;	// bit 3
		volatile uint32_t CONTMEAS	: 1;	// bit 4
		volatile uint32_t __unused0	: 3;	// bits 7 downto 5
		volatile uint32_t ADCEXTIN	: 1;	// bit 8
		volatile uint32_t ATPEN		: 1;	// bit 9
		volatile uint32_t ATPSEL	: 1;	// bit 10
		volatile uint32_t ADCSEL	: 1;	// bit 11
		volatile uint32_t RAMPNUM	: 12;	// bits 23 downto 12
		volatile uint32_t __unused1	: 8;	// bits 31 downto 24
	};
} AFE_CR_Register_t;

// Bit fields structure for register AFE_TPR
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t DTP0SEL	: 5;	// bits 4 downto 0
		volatile uint32_t DTP1SEL	: 5;	// bits 9 downto 5
		volatile uint32_t DTP2SEL	: 5;	// bits 14 downto 10
		volatile uint32_t DTP3SEL	: 5;	// bits 19 downto 15
		volatile uint32_t __unused0	: 12;	// bits 31 downto 20
	};
} AFE_TPR_Register_t;

// Bit fields structure for register AFE_SR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t ADCACTIVE	: 1;	// bit 0
		volatile uint8_t DATARDYIF	: 1;	// bit 1
		volatile uint8_t OVFIF		: 1;	// bit 2
		volatile uint8_t __unused0	: 5;	// bits 7 downto 3
	};
} AFE_SR_Register_t;

// Bit fields structure for register AFE_ADC_VAL
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t ADCVAL	: 12;	// bits 11 downto 0
		volatile uint16_t __unused0	: 4;	// bits 15 downto 12
	};
} AFE_ADC_VAL_Register_t;

// Bit fields structure for register BIAS_CR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t __unused0	: 2;	// bits 1 downto 0
		volatile uint8_t EN_		: 1;	// bit 2
		volatile uint8_t BUFEN_		: 1;	// bit 3
		volatile uint8_t USEDAC_	: 1;	// bit 4
		volatile uint8_t __unused1	: 3;	// bits 7 downto 5
	};
} BIAS_CR_Register_t;

// Bit fields structure for register BIAS_ADJ
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t ADJ_		: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_ADJ_Register_t;

// Bit fields structure for register BIAS_DBP
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DBP_		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIAS_DBP_Register_t;

// Bit fields structure for register BIAS_DBPC
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DBPC_		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIAS_DBPC_Register_t;

// Bit fields structure for register BIAS_DBNC
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DBNC_		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIAS_DBNC_Register_t;

// Bit fields structure for register BIAS_DBN
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DBN_		: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIAS_DBN_Register_t;

// Bit fields structure for register BIAS_TC_POT
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TC_POT_	: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_TC_POT_Register_t;

// Bit fields structure for register BIAS_LC_POT
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t LC_POT_	: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_LC_POT_Register_t;

// Bit fields structure for register BIAS_TIA_G_POT
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t TIA_G_POT_	: 17;	// bits 16 downto 0
		volatile uint32_t __unused0		: 15;	// bits 31 downto 17
	};
} BIAS_TIA_G_POT_Register_t;

// Bit fields structure for register BIAS_DSADC_VCM
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DSADC_VCM_	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0		: 2;	// bits 15 downto 14
	};
} BIAS_DSADC_VCM_Register_t;

// Bit fields structure for register BIAS_REV_POT
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t REV_POT_	: 14;	// bits 13 downto 0
		volatile uint16_t __unused0	: 2;	// bits 15 downto 14
	};
} BIAS_REV_POT_Register_t;

// Bit fields structure for register BIAS_TC_DSADC
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t TC_DSADC_	: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_TC_DSADC_Register_t;

// Bit fields structure for register BIAS_LC_DSADC
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t LC_DSADC_	: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_LC_DSADC_Register_t;

// Bit fields structure for register BIAS_RIN_DSADC
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t RIN_DSADC_	: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_RIN_DSADC_Register_t;

// Bit fields structure for register BIAS_RFB_DSADC
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t RFB_DSADC_	: 6;	// bits 5 downto 0
		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
	};
} BIAS_RFB_DSADC_Register_t;



// Registers structure for peripheral AFE
typedef struct
{
	volatile AFE_CR_Register_t			_CR;
	volatile AFE_TPR_Register_t			_TPR;
	volatile AFE_SR_Register_t			_SR;
	volatile uint8_t					__unused0;
	volatile uint16_t					__unused1;
	volatile AFE_ADC_VAL_Register_t		_ADC_VAL;
	volatile uint16_t					__unused2;
	volatile BIAS_CR_Register_t			S_CR;
	volatile uint8_t					__unused3;
	volatile uint16_t					__unused4;
	volatile BIAS_ADJ_Register_t		S_ADJ;
	volatile uint8_t					__unused5;
	volatile uint16_t					__unused6;
	volatile BIAS_DBP_Register_t		S_DBP;
	volatile uint16_t					__unused7;
	volatile BIAS_DBPC_Register_t		S_DBPC;
	volatile uint16_t					__unused8;
	volatile BIAS_DBNC_Register_t		S_DBNC;
	volatile uint16_t					__unused9;
	volatile BIAS_DBN_Register_t		S_DBN;
	volatile uint16_t					__unused10;
	volatile BIAS_TC_POT_Register_t		S_TC_POT;
	volatile uint8_t					__unused11;
	volatile uint16_t					__unused12;
	volatile BIAS_LC_POT_Register_t		S_LC_POT;
	volatile uint8_t					__unused13;
	volatile uint16_t					__unused14;
	volatile BIAS_TIA_G_POT_Register_t	S_TIA_G_POT;
	volatile BIAS_DSADC_VCM_Register_t	S_DSADC_VCM;
	volatile uint16_t					__unused15;
	volatile BIAS_REV_POT_Register_t	S_REV_POT;
	volatile uint16_t					__unused16;
	volatile BIAS_TC_DSADC_Register_t	S_TC_DSADC;
	volatile uint8_t					__unused17;
	volatile uint16_t					__unused18;
	volatile BIAS_LC_DSADC_Register_t	S_LC_DSADC;
	volatile uint8_t					__unused19;
	volatile uint16_t					__unused20;
	volatile BIAS_RIN_DSADC_Register_t	S_RIN_DSADC;
	volatile uint8_t					__unused21;
	volatile uint16_t					__unused22;
	volatile BIAS_RFB_DSADC_Register_t	S_RFB_DSADC;
	volatile uint8_t					__unused23;
	volatile uint16_t					__unused24;
	volatile uint32_t					__unused25[45];
} AFE_t;

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
#define NPU		((NPU_t *) NPU_BASE)
#define SARADC	((SARADC_t *) SARADC_BASE)
#define AFE		((AFE_t *) AFE_BASE)
#define GPIO3	((GPIOx_8bit_t *) GPIO3_BASE)
#define I2C0	((I2Cx_t *) I2C0_BASE)
#define I2C1	((I2Cx_t *) I2C1_BASE)



/********** GPIO Pins **********/

/** GPIO0 Pins **/
// P0.0 primary function (when P0SEL(0) = '0'): GPIO0
#define GPIO0_BIT		(BIT0)
#define GPIO0_PxIN		(P0IN)
#define GPIO0_PxOUT		(P0OUT)
#define GPIO0_PxDIR		(P0DIR)
#define GPIO0_PxIES		(P0IES)
#define GPIO0_PxIFG		(P0IFG)
#define GPIO0_PxIE		(P0IE)
#define GPIO0_PxSEL		(P0SEL)
#define GPIO0_PxREN		(P0REN)

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

// P0.1 primary function (when P0SEL(1) = '0'): GPIO1
#define GPIO1_BIT		(BIT1)
#define GPIO1_PxIN		(P0IN)
#define GPIO1_PxOUT		(P0OUT)
#define GPIO1_PxDIR		(P0DIR)
#define GPIO1_PxIES		(P0IES)
#define GPIO1_PxIFG		(P0IFG)
#define GPIO1_PxIE		(P0IE)
#define GPIO1_PxSEL		(P0SEL)
#define GPIO1_PxREN		(P0REN)

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

// P0.2 primary function (when P0SEL(2) = '0'): GPIO2
#define GPIO2_BIT		(BIT2)
#define GPIO2_PxIN		(P0IN)
#define GPIO2_PxOUT		(P0OUT)
#define GPIO2_PxDIR		(P0DIR)
#define GPIO2_PxIES		(P0IES)
#define GPIO2_PxIFG		(P0IFG)
#define GPIO2_PxIE		(P0IE)
#define GPIO2_PxSEL		(P0SEL)
#define GPIO2_PxREN		(P0REN)

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

// P0.3 primary function (when P0SEL(3) = '0'): GPIO3
#define GPIO3_BIT		(BIT3)
#define GPIO3_PxIN		(P0IN)
#define GPIO3_PxOUT		(P0OUT)
#define GPIO3_PxDIR		(P0DIR)
#define GPIO3_PxIES		(P0IES)
#define GPIO3_PxIFG		(P0IFG)
#define GPIO3_PxIE		(P0IE)
#define GPIO3_PxSEL		(P0SEL)
#define GPIO3_PxREN		(P0REN)

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

// P0.4 primary function (when P0SEL(4) = '0'): GPIO4
#define GPIO4_BIT		(BIT4)
#define GPIO4_PxIN		(P0IN)
#define GPIO4_PxOUT		(P0OUT)
#define GPIO4_PxDIR		(P0DIR)
#define GPIO4_PxIES		(P0IES)
#define GPIO4_PxIFG		(P0IFG)
#define GPIO4_PxIE		(P0IE)
#define GPIO4_PxSEL		(P0SEL)
#define GPIO4_PxREN		(P0REN)

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

// P0.5 primary function (when P0SEL(5) = '0'): GPIO5
#define GPIO5_BIT		(BIT5)
#define GPIO5_PxIN		(P0IN)
#define GPIO5_PxOUT		(P0OUT)
#define GPIO5_PxDIR		(P0DIR)
#define GPIO5_PxIES		(P0IES)
#define GPIO5_PxIFG		(P0IFG)
#define GPIO5_PxIE		(P0IE)
#define GPIO5_PxSEL		(P0SEL)
#define GPIO5_PxREN		(P0REN)

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

// P0.6 primary function (when P0SEL(6) = '0'): GPIO6
#define GPIO6_BIT		(BIT6)
#define GPIO6_PxIN		(P0IN)
#define GPIO6_PxOUT		(P0OUT)
#define GPIO6_PxDIR		(P0DIR)
#define GPIO6_PxIES		(P0IES)
#define GPIO6_PxIFG		(P0IFG)
#define GPIO6_PxIE		(P0IE)
#define GPIO6_PxSEL		(P0SEL)
#define GPIO6_PxREN		(P0REN)

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
// P1.0 primary function (when P1SEL(0) = '0'): GPIO8
#define GPIO8_BIT		(BIT0)
#define GPIO8_PxIN		(P1IN)
#define GPIO8_PxOUT		(P1OUT)
#define GPIO8_PxDIR		(P1DIR)
#define GPIO8_PxIES		(P1IES)
#define GPIO8_PxIFG		(P1IFG)
#define GPIO8_PxIE		(P1IE)
#define GPIO8_PxSEL		(P1SEL)
#define GPIO8_PxREN		(P1REN)

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

// P1.1 primary function (when P1SEL(1) = '0'): GPIO9
#define GPIO9_BIT		(BIT1)
#define GPIO9_PxIN		(P1IN)
#define GPIO9_PxOUT		(P1OUT)
#define GPIO9_PxDIR		(P1DIR)
#define GPIO9_PxIES		(P1IES)
#define GPIO9_PxIFG		(P1IFG)
#define GPIO9_PxIE		(P1IE)
#define GPIO9_PxSEL		(P1SEL)
#define GPIO9_PxREN		(P1REN)

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

// P1.2 primary function (when P1SEL(2) = '0'): GPIO10
#define GPIO10_BIT		(BIT2)
#define GPIO10_PxIN		(P1IN)
#define GPIO10_PxOUT	(P1OUT)
#define GPIO10_PxDIR	(P1DIR)
#define GPIO10_PxIES	(P1IES)
#define GPIO10_PxIFG	(P1IFG)
#define GPIO10_PxIE		(P1IE)
#define GPIO10_PxSEL	(P1SEL)
#define GPIO10_PxREN	(P1REN)

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

// P1.3 primary function (when P1SEL(3) = '0'): GPIO11
#define GPIO11_BIT		(BIT3)
#define GPIO11_PxIN		(P1IN)
#define GPIO11_PxOUT	(P1OUT)
#define GPIO11_PxDIR	(P1DIR)
#define GPIO11_PxIES	(P1IES)
#define GPIO11_PxIFG	(P1IFG)
#define GPIO11_PxIE		(P1IE)
#define GPIO11_PxSEL	(P1SEL)
#define GPIO11_PxREN	(P1REN)

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

// P1.4 primary function (when P1SEL(4) = '0'): GPIO12
#define GPIO12_BIT		(BIT4)
#define GPIO12_PxIN		(P1IN)
#define GPIO12_PxOUT	(P1OUT)
#define GPIO12_PxDIR	(P1DIR)
#define GPIO12_PxIES	(P1IES)
#define GPIO12_PxIFG	(P1IFG)
#define GPIO12_PxIE		(P1IE)
#define GPIO12_PxSEL	(P1SEL)
#define GPIO12_PxREN	(P1REN)

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

// P1.5 primary function (when P1SEL(5) = '0'): GPIO13
#define GPIO13_BIT		(BIT5)
#define GPIO13_PxIN		(P1IN)
#define GPIO13_PxOUT	(P1OUT)
#define GPIO13_PxDIR	(P1DIR)
#define GPIO13_PxIES	(P1IES)
#define GPIO13_PxIFG	(P1IFG)
#define GPIO13_PxIE		(P1IE)
#define GPIO13_PxSEL	(P1SEL)
#define GPIO13_PxREN	(P1REN)

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

// P1.6 primary function (when P1SEL(6) = '0'): GPIO14
#define GPIO14_BIT		(BIT6)
#define GPIO14_PxIN		(P1IN)
#define GPIO14_PxOUT	(P1OUT)
#define GPIO14_PxDIR	(P1DIR)
#define GPIO14_PxIES	(P1IES)
#define GPIO14_PxIFG	(P1IFG)
#define GPIO14_PxIE		(P1IE)
#define GPIO14_PxSEL	(P1SEL)
#define GPIO14_PxREN	(P1REN)

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

// P1.7 primary function (when P1SEL(7) = '0'): GPIO15
#define GPIO15_BIT		(BIT7)
#define GPIO15_PxIN		(P1IN)
#define GPIO15_PxOUT	(P1OUT)
#define GPIO15_PxDIR	(P1DIR)
#define GPIO15_PxIES	(P1IES)
#define GPIO15_PxIFG	(P1IFG)
#define GPIO15_PxIE		(P1IE)
#define GPIO15_PxSEL	(P1SEL)
#define GPIO15_PxREN	(P1REN)

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
// P2.0 primary function (when P2SEL(0) = '0'): GPIO16
#define GPIO16_BIT		(BIT0)
#define GPIO16_PxIN		(P2IN)
#define GPIO16_PxOUT	(P2OUT)
#define GPIO16_PxDIR	(P2DIR)
#define GPIO16_PxIES	(P2IES)
#define GPIO16_PxIFG	(P2IFG)
#define GPIO16_PxIE		(P2IE)
#define GPIO16_PxSEL	(P2SEL)
#define GPIO16_PxREN	(P2REN)

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

// P2.1 primary function (when P2SEL(1) = '0'): GPIO17
#define GPIO17_BIT		(BIT1)
#define GPIO17_PxIN		(P2IN)
#define GPIO17_PxOUT	(P2OUT)
#define GPIO17_PxDIR	(P2DIR)
#define GPIO17_PxIES	(P2IES)
#define GPIO17_PxIFG	(P2IFG)
#define GPIO17_PxIE		(P2IE)
#define GPIO17_PxSEL	(P2SEL)
#define GPIO17_PxREN	(P2REN)

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

// P2.2 primary function (when P2SEL(2) = '0'): GPIO18
#define GPIO18_BIT		(BIT2)
#define GPIO18_PxIN		(P2IN)
#define GPIO18_PxOUT	(P2OUT)
#define GPIO18_PxDIR	(P2DIR)
#define GPIO18_PxIES	(P2IES)
#define GPIO18_PxIFG	(P2IFG)
#define GPIO18_PxIE		(P2IE)
#define GPIO18_PxSEL	(P2SEL)
#define GPIO18_PxREN	(P2REN)

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

// P2.3 primary function (when P2SEL(3) = '0'): GPIO19
#define GPIO19_BIT		(BIT3)
#define GPIO19_PxIN		(P2IN)
#define GPIO19_PxOUT	(P2OUT)
#define GPIO19_PxDIR	(P2DIR)
#define GPIO19_PxIES	(P2IES)
#define GPIO19_PxIFG	(P2IFG)
#define GPIO19_PxIE		(P2IE)
#define GPIO19_PxSEL	(P2SEL)
#define GPIO19_PxREN	(P2REN)

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

// P2.4 primary function (when P2SEL(4) = '0'): GPIO20
#define GPIO20_BIT		(BIT4)
#define GPIO20_PxIN		(P2IN)
#define GPIO20_PxOUT	(P2OUT)
#define GPIO20_PxDIR	(P2DIR)
#define GPIO20_PxIES	(P2IES)
#define GPIO20_PxIFG	(P2IFG)
#define GPIO20_PxIE		(P2IE)
#define GPIO20_PxSEL	(P2SEL)
#define GPIO20_PxREN	(P2REN)

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

// P2.5 primary function (when P2SEL(5) = '0'): GPIO21
#define GPIO21_BIT		(BIT5)
#define GPIO21_PxIN		(P2IN)
#define GPIO21_PxOUT	(P2OUT)
#define GPIO21_PxDIR	(P2DIR)
#define GPIO21_PxIES	(P2IES)
#define GPIO21_PxIFG	(P2IFG)
#define GPIO21_PxIE		(P2IE)
#define GPIO21_PxSEL	(P2SEL)
#define GPIO21_PxREN	(P2REN)

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

// P2.6 primary function (when P2SEL(6) = '0'): GPIO22
#define GPIO22_BIT		(BIT6)
#define GPIO22_PxIN		(P2IN)
#define GPIO22_PxOUT	(P2OUT)
#define GPIO22_PxDIR	(P2DIR)
#define GPIO22_PxIES	(P2IES)
#define GPIO22_PxIFG	(P2IFG)
#define GPIO22_PxIE		(P2IE)
#define GPIO22_PxSEL	(P2SEL)
#define GPIO22_PxREN	(P2REN)

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

// P2.7 primary function (when P2SEL(7) = '0'): GPIO23
#define GPIO23_BIT		(BIT7)
#define GPIO23_PxIN		(P2IN)
#define GPIO23_PxOUT	(P2OUT)
#define GPIO23_PxDIR	(P2DIR)
#define GPIO23_PxIES	(P2IES)
#define GPIO23_PxIFG	(P2IFG)
#define GPIO23_PxIE		(P2IE)
#define GPIO23_PxSEL	(P2SEL)
#define GPIO23_PxREN	(P2REN)

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
// P3.0 primary function (when P3SEL(0) = '0'): GPIO24
#define GPIO24_BIT		(BIT0)
#define GPIO24_PxIN		(P3IN)
#define GPIO24_PxOUT	(P3OUT)
#define GPIO24_PxDIR	(P3DIR)
#define GPIO24_PxIES	(P3IES)
#define GPIO24_PxIFG	(P3IFG)
#define GPIO24_PxIE		(P3IE)
#define GPIO24_PxSEL	(P3SEL)
#define GPIO24_PxREN	(P3REN)

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

// P3.1 primary function (when P3SEL(1) = '0'): GPIO25
#define GPIO25_BIT		(BIT1)
#define GPIO25_PxIN		(P3IN)
#define GPIO25_PxOUT	(P3OUT)
#define GPIO25_PxDIR	(P3DIR)
#define GPIO25_PxIES	(P3IES)
#define GPIO25_PxIFG	(P3IFG)
#define GPIO25_PxIE		(P3IE)
#define GPIO25_PxSEL	(P3SEL)
#define GPIO25_PxREN	(P3REN)

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

// P3.2 primary function (when P3SEL(2) = '0'): GPIO26
#define GPIO26_BIT		(BIT2)
#define GPIO26_PxIN		(P3IN)
#define GPIO26_PxOUT	(P3OUT)
#define GPIO26_PxDIR	(P3DIR)
#define GPIO26_PxIES	(P3IES)
#define GPIO26_PxIFG	(P3IFG)
#define GPIO26_PxIE		(P3IE)
#define GPIO26_PxSEL	(P3SEL)
#define GPIO26_PxREN	(P3REN)

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

// P3.3 primary function (when P3SEL(3) = '0'): GPIO27
#define GPIO27_BIT		(BIT3)
#define GPIO27_PxIN		(P3IN)
#define GPIO27_PxOUT	(P3OUT)
#define GPIO27_PxDIR	(P3DIR)
#define GPIO27_PxIES	(P3IES)
#define GPIO27_PxIFG	(P3IFG)
#define GPIO27_PxIE		(P3IE)
#define GPIO27_PxSEL	(P3SEL)
#define GPIO27_PxREN	(P3REN)

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

// P3.4 primary function (when P3SEL(4) = '0'): GPIO28
#define GPIO28_BIT		(BIT4)
#define GPIO28_PxIN		(P3IN)
#define GPIO28_PxOUT	(P3OUT)
#define GPIO28_PxDIR	(P3DIR)
#define GPIO28_PxIES	(P3IES)
#define GPIO28_PxIFG	(P3IFG)
#define GPIO28_PxIE		(P3IE)
#define GPIO28_PxSEL	(P3SEL)
#define GPIO28_PxREN	(P3REN)

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

// P3.5 primary function (when P3SEL(5) = '0'): GPIO29
#define GPIO29_BIT		(BIT5)
#define GPIO29_PxIN		(P3IN)
#define GPIO29_PxOUT	(P3OUT)
#define GPIO29_PxDIR	(P3DIR)
#define GPIO29_PxIES	(P3IES)
#define GPIO29_PxIFG	(P3IFG)
#define GPIO29_PxIE		(P3IE)
#define GPIO29_PxSEL	(P3SEL)
#define GPIO29_PxREN	(P3REN)

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

// P3.6 primary function (when P3SEL(6) = '0'): GPIO30
#define GPIO30_BIT		(BIT6)
#define GPIO30_PxIN		(P3IN)
#define GPIO30_PxOUT	(P3OUT)
#define GPIO30_PxDIR	(P3DIR)
#define GPIO30_PxIES	(P3IES)
#define GPIO30_PxIFG	(P3IFG)
#define GPIO30_PxIE		(P3IE)
#define GPIO30_PxSEL	(P3SEL)
#define GPIO30_PxREN	(P3REN)

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

// P3.7 primary function (when P3SEL(7) = '0'): GPIO31
#define GPIO31_BIT		(BIT7)
#define GPIO31_PxIN		(P3IN)
#define GPIO31_PxOUT	(P3OUT)
#define GPIO31_PxDIR	(P3DIR)
#define GPIO31_PxIES	(P3IES)
#define GPIO31_PxIFG	(P3IFG)
#define GPIO31_PxIE		(P3IE)
#define GPIO31_PxSEL	(P3SEL)
#define GPIO31_PxREN	(P3REN)

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
