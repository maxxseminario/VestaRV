/**
 **	MemoryMap.h
 **	Memory map definition header file
 **	Defines the microcontroller peripheral and register addresses, as well as the bit field bit masks
 **	Generated on 2022/03/08 at 17:23:08 with the MemoryMap.py memory map generator
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



/** Defines **/
#define ASIC_NAME	"washakie"
#define ASIC_DEFINE_washakie



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



/** RAM, ROM, and Interrupt Vector Table Locations and Sizes **/
#define ROM_START							(0x0000)
#define ROM_SIZE							(0x4000)
#define RAM_START							(0x8000)
#define RAM_SIZE							(0x34800)
#define INTERRUPT_VECTOR_TABLE_START		(0x8000)
#define INTERRUPT_VECTOR_TABLE_SIZE			(0x0080)
#define RAM_PROGRAM_START_ADDRESS			(0x8080)
#define INTERRUPT_HANDLER_ADDRESS			(0x8090)
#define PERIPHERAL_SPACING					(0x0100)	// The number of bytes between each adjacent peripheral base address
#define STACK_POINTER_INIT					(0x2C000)
#define BOOTLOADER_USES_SPI_FLASH_COMMANDS

#define RAM_SLOT_SIZE						(16384)
#define LAST_RAM_SLOT_SIZE					(2048)
#define SRAM02_ADDRESS						(0x08000)
#define SRAM03_ADDRESS						(0x0C000)
#define SRAM04_ADDRESS						(0x10000)
#define SRAM05_ADDRESS						(0x14000)
#define SRAM06_ADDRESS						(0x18000)
#define SRAM07_ADDRESS						(0x1C000)
#define SRAM08_ADDRESS						(0x20000)
#define SRAM09_ADDRESS						(0x24000)
#define SRAM10_ADDRESS						(0x28000)
#define SRAM11_ADDRESS						(0x2C000)
#define SRAM12_ADDRESS						(0x30000)
#define SRAM13_ADDRESS						(0x34000)
#define SRAM14_ADDRESS						(0x38000)
#define SRAM15_ADDRESS						(0x3C000)

#define SPI_FLASH_PROGRAM_ADDRESS			(0x0000)

#define HAS_NATIVE_SPI_FLASH_MEMORY_READ_ACCESS
// Does not have native SPI Flash memory write access
#define SPI_FLASH_MEM_ADDRESS	(0x01000000)
#define SPI_FLASH_MEM			((volatile uint32_t *) (SPI_FLASH_MEM_ADDRESS))



/** Chip Properties **/
#define ENABLE_IRQ_FAST_CONTEXT_SWITCHING



/********** Register Offsets and Bit Fields **********/

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



/** PCT **/
// PCTCR
#define PCTCR_OFFSET			(0)
#define PCTCR_PTR(_PCT_BASE)	MMR_08_PTR(_PCT_BASE, PCTCR_OFFSET)

#define ESPCT3		(0x80)	// bit 7
#define ESPCT3_LSB	(7)
#define ESPCT2		(0x40)	// bit 6
#define ESPCT2_LSB	(6)
#define ESPCT1		(0x20)	// bit 5
#define ESPCT1_LSB	(5)
#define ESPCT0		(0x10)	// bit 4
#define ESPCT0_LSB	(4)
#define ENPCT3		(0x08)	// bit 3
#define ENPCT3_LSB	(3)
#define ENPCT2		(0x04)	// bit 2
#define ENPCT2_LSB	(2)
#define ENPCT1		(0x02)	// bit 1
#define ENPCT1_LSB	(1)
#define ENPCT0		(0x01)	// bit 0
#define ENPCT0_LSB	(0)

// PCTCNT0
#define PCTCNT0_OFFSET			(4)
#define PCTCNT0_PTR(_PCT_BASE)	MMR_32_PTR(_PCT_BASE, PCTCNT0_OFFSET)

// PCTCNT1
#define PCTCNT1_OFFSET			(8)
#define PCTCNT1_PTR(_PCT_BASE)	MMR_32_PTR(_PCT_BASE, PCTCNT1_OFFSET)

// PCTCNT2
#define PCTCNT2_OFFSET			(12)
#define PCTCNT2_PTR(_PCT_BASE)	MMR_32_PTR(_PCT_BASE, PCTCNT2_OFFSET)

// PCTCNT3
#define PCTCNT3_OFFSET			(16)
#define PCTCNT3_PTR(_PCT_BASE)	MMR_32_PTR(_PCT_BASE, PCTCNT3_OFFSET)



/** OPA **/
// OPACR
#define OPACR_OFFSET			(0)
#define OPACR_PTR(_OPA_BASE)	MMR_16_PTR(_OPA_BASE, OPACR_OFFSET)

#define OPA1CMPIES			(0x2000)	// bit 13
#define OPA1CMPIES_LSB		(13)
#define OPA1CMPIE			(0x1000)	// bit 12
#define OPA1CMPIE_LSB		(12)
#define OPA1CMPEN			(0x0800)	// bit 11
#define OPA1CMPEN_LSB		(11)
#define OPA0CMPIES			(0x0400)	// bit 10
#define OPA0CMPIES_LSB		(10)
#define OPA0CMPIE			(0x0200)	// bit 9
#define OPA0CMPIE_LSB		(9)
#define OPA0CMPEN			(0x0100)	// bit 8
#define OPA0CMPEN_LSB		(8)
#define OPA1PDWD			(0x0080)	// bit 7
#define OPA1PDWD_LSB		(7)
#define OPA1BS				(0x0040)	// bit 6
#define OPA1BS_LSB			(6)
#define OPA1MODE_MASK		(0x0030)	// bits 5 downto 4
#define OPA1MODE_LSB		(4)
#define OPA1MODE_DISABLED	(0x0000)
#define OPA1MODE_BUF_ONLY	(0x0010)
#define OPA1MODE_OTA_UNBUF	(0x0020)
#define OPA1MODE_OTA_BUF	(0x0030)
#define OPA0PDWD			(0x0008)	// bit 3
#define OPA0PDWD_LSB		(3)
#define OPA0BS				(0x0004)	// bit 2
#define OPA0BS_LSB			(2)
#define OPA0MODE_MASK		(0x0003)	// bits 1 downto 0
#define OPA0MODE_LSB		(0)
#define OPA0MODE_DISABLED	(0x0000)
#define OPA0MODE_BUF_ONLY	(0x0001)
#define OPA0MODE_OTA_UNBUF	(0x0002)
#define OPA0MODE_OTA_BUF	(0x0003)

// OPASR
#define OPASR_OFFSET			(4)
#define OPASR_PTR(_OPA_BASE)	MMR_08_PTR(_OPA_BASE, OPASR_OFFSET)

#define OPA1CMPIF		(0x08)	// bit 3
#define OPA1CMPIF_LSB	(3)
#define OPA0CMPIF		(0x04)	// bit 2
#define OPA0CMPIF_LSB	(2)
#define OPA1CMPVAL		(0x02)	// bit 1
#define OPA1CMPVAL_LSB	(1)
#define OPA0CMPVAL		(0x01)	// bit 0
#define OPA0CMPVAL_LSB	(0)



/** DAC **/
// DACCR
#define DACCR_OFFSET			(0)
#define DACCR_PTR(_DAC_BASE)	MMR_16_PTR(_DAC_BASE, DACCR_OFFSET)

#define DACCDIV_MASK	(0x0700)	// bits 10 downto 8
#define DACCDIV_LSB		(8)
#define DACCDIV_1		(0x0000)
#define DACCDIV_2		(0x0100)
#define DACCDIV_4		(0x0200)
#define DACCDIV_8		(0x0300)
#define DACCDIV_16		(0x0400)
#define DACCDIV_32		(0x0500)
#define DACCDIV_64		(0x0600)
#define DACCDIV_128		(0x0700)
#define DAC1EN			(0x0080)	// bit 7
#define DAC1EN_LSB		(7)
#define DAC0EN			(0x0040)	// bit 6
#define DAC0EN_LSB		(6)
#define DAC1DEN			(0x0020)	// bit 5
#define DAC1DEN_LSB		(5)
#define DAC0DEN			(0x0010)	// bit 4
#define DAC0DEN_LSB		(4)
#define DACCS_MASK		(0x000C)	// bits 3 downto 2
#define DACCS_LSB		(2)
#define DACCS_MCLK		(0x0000)
#define DACCS_SMCLK		(0x0004)
#define DACCS_HFXT		(0x0008)
#define DACCS_DCO0		(0x000C)
#define DACDAL			(0x0002)	// bit 1
#define DACDAL_LSB		(1)
#define DACBEIE			(0x0001)	// bit 0
#define DACBEIE_LSB		(0)

// DACSR
#define DACSR_OFFSET			(4)
#define DACSR_PTR(_DAC_BASE)	MMR_08_PTR(_DAC_BASE, DACSR_OFFSET)

#define DACBH		(0x02)	// bit 1
#define DACBH_LSB	(1)
#define DACBEIF		(0x01)	// bit 0
#define DACBEIF_LSB	(0)

// DAC0VAL
#define DAC0VAL_OFFSET			(8)
#define DAC0VAL_PTR(_DAC_BASE)	MMR_16_PTR(_DAC_BASE, DAC0VAL_OFFSET)

// DAC1VAL
#define DAC1VAL_OFFSET			(12)
#define DAC1VAL_PTR(_DAC_BASE)	MMR_16_PTR(_DAC_BASE, DAC1VAL_OFFSET)

// DACFS
#define DACFS_OFFSET			(16)
#define DACFS_PTR(_DAC_BASE)	MMR_16_PTR(_DAC_BASE, DACFS_OFFSET)

// DACHBS
#define DACHBS_OFFSET			(20)
#define DACHBS_PTR(_DAC_BASE)	MMR_08_PTR(_DAC_BASE, DACHBS_OFFSET)



/********** Peripheral and Register Memory Map **********/

/** SYSTEM **/
#define SYSTEM_BASE			(0x4000)

#define SYSCLKCR_ADDRESS	(0x4000)
#define SYSCLKCR			MMR_16_BIT_MACRO(SYSCLKCR_ADDRESS)
#define CLKDIVCR_ADDRESS	(0x4004)
#define CLKDIVCR			MMR_08_BIT_MACRO(CLKDIVCR_ADDRESS)
#define MEMPWRCR_ADDRESS	(0x4008)
#define MEMPWRCR			MMR_16_BIT_MACRO(MEMPWRCR_ADDRESS)
#define CRCDATA_ADDRESS		(0x400C)
#define CRCDATA				MMR_08_BIT_MACRO(CRCDATA_ADDRESS)
#define CRCSTATE_ADDRESS	(0x4010)
#define CRCSTATE			MMR_16_BIT_MACRO(CRCSTATE_ADDRESS)
#define IRQEN_ADDRESS		(0x4014)
#define IRQEN				MMR_32_BIT_MACRO(IRQEN_ADDRESS)
#define IRQPRI_ADDRESS		(0x4018)
#define IRQPRI				MMR_32_BIT_MACRO(IRQPRI_ADDRESS)
#define WDTPASS_ADDRESS		(0x401C)
#define WDTPASS				MMR_32_BIT_MACRO(WDTPASS_ADDRESS)
#define WDTCR_ADDRESS		(0x4020)
#define WDTCR				MMR_08_BIT_MACRO(WDTCR_ADDRESS)
#define WDTSR_ADDRESS		(0x4024)
#define WDTSR				MMR_08_BIT_MACRO(WDTSR_ADDRESS)
#define WDTVAL_ADDRESS		(0x4028)
#define WDTVAL				MMR_32_BIT_MACRO(WDTVAL_ADDRESS)
#define DCO0FREQ_ADDRESS	(0x402C)
#define DCO0FREQ			MMR_16_BIT_MACRO(DCO0FREQ_ADDRESS)
#define DCO1FREQ_ADDRESS	(0x4030)
#define DCO1FREQ			MMR_16_BIT_MACRO(DCO1FREQ_ADDRESS)
#define TPMR_ADDRESS		(0x4034)
#define TPMR				MMR_08_BIT_MACRO(TPMR_ADDRESS)
#define BIASCR_ADDRESS		(0x4038)
#define BIASCR				MMR_16_BIT_MACRO(BIASCR_ADDRESS)
#define BIASDBP_ADDRESS		(0x403C)
#define BIASDBP				MMR_16_BIT_MACRO(BIASDBP_ADDRESS)
#define BIASDBPC_ADDRESS	(0x4040)
#define BIASDBPC			MMR_16_BIT_MACRO(BIASDBPC_ADDRESS)
#define BIASDBNC_ADDRESS	(0x4044)
#define BIASDBNC			MMR_16_BIT_MACRO(BIASDBNC_ADDRESS)
#define BIASDBN_ADDRESS		(0x4048)
#define BIASDBN				MMR_16_BIT_MACRO(BIASDBN_ADDRESS)



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



/** TIMER0 **/
#define TIMER0_BASE			(0x4500)

#define TIM0CR_ADDRESS		(0x4500)
#define TIM0CR				MMR_32_BIT_MACRO(TIM0CR_ADDRESS)
#define TIM0SR_ADDRESS		(0x4504)
#define TIM0SR				MMR_08_BIT_MACRO(TIM0SR_ADDRESS)
#define TIM0VAL_ADDRESS		(0x4508)
#define TIM0VAL				MMR_32_BIT_MACRO(TIM0VAL_ADDRESS)
#define TIM0CMP0_ADDRESS	(0x450C)
#define TIM0CMP0			MMR_32_BIT_MACRO(TIM0CMP0_ADDRESS)
#define TIM0CMP1_ADDRESS	(0x4510)
#define TIM0CMP1			MMR_32_BIT_MACRO(TIM0CMP1_ADDRESS)
#define TIM0CMP2_ADDRESS	(0x4514)
#define TIM0CMP2			MMR_32_BIT_MACRO(TIM0CMP2_ADDRESS)
#define TIM0CAP0_ADDRESS	(0x4518)
#define TIM0CAP0			MMR_32_BIT_MACRO(TIM0CAP0_ADDRESS)
#define TIM0CAP1_ADDRESS	(0x451C)
#define TIM0CAP1			MMR_32_BIT_MACRO(TIM0CAP1_ADDRESS)



/** TIMER1 **/
#define TIMER1_BASE			(0x4600)

#define TIM1CR_ADDRESS		(0x4600)
#define TIM1CR				MMR_32_BIT_MACRO(TIM1CR_ADDRESS)
#define TIM1SR_ADDRESS		(0x4604)
#define TIM1SR				MMR_08_BIT_MACRO(TIM1SR_ADDRESS)
#define TIM1VAL_ADDRESS		(0x4608)
#define TIM1VAL				MMR_32_BIT_MACRO(TIM1VAL_ADDRESS)
#define TIM1CMP0_ADDRESS	(0x460C)
#define TIM1CMP0			MMR_32_BIT_MACRO(TIM1CMP0_ADDRESS)
#define TIM1CMP1_ADDRESS	(0x4610)
#define TIM1CMP1			MMR_32_BIT_MACRO(TIM1CMP1_ADDRESS)
#define TIM1CMP2_ADDRESS	(0x4614)
#define TIM1CMP2			MMR_32_BIT_MACRO(TIM1CMP2_ADDRESS)
#define TIM1CAP0_ADDRESS	(0x4618)
#define TIM1CAP0			MMR_32_BIT_MACRO(TIM1CAP0_ADDRESS)
#define TIM1CAP1_ADDRESS	(0x461C)
#define TIM1CAP1			MMR_32_BIT_MACRO(TIM1CAP1_ADDRESS)



/** GPIO2 **/
#define GPIO2_BASE			(0x4700)

#define P2IN_ADDRESS		(0x4700)
#define P2IN				MMR_08_BIT_MACRO(P2IN_ADDRESS)
#define P2OUT_ADDRESS		(0x4704)
#define P2OUT				MMR_08_BIT_MACRO(P2OUT_ADDRESS)
#define P2OUTS_ADDRESS		(0x4708)
#define P2OUTS				MMR_08_BIT_MACRO(P2OUTS_ADDRESS)
#define P2OUTC_ADDRESS		(0x470C)
#define P2OUTC				MMR_08_BIT_MACRO(P2OUTC_ADDRESS)
#define P2OUTT_ADDRESS		(0x4710)
#define P2OUTT				MMR_32_BIT_MACRO(P2OUTT_ADDRESS)
#define P2DIR_ADDRESS		(0x4714)
#define P2DIR				MMR_08_BIT_MACRO(P2DIR_ADDRESS)
#define P2IFG_ADDRESS		(0x4718)
#define P2IFG				MMR_08_BIT_MACRO(P2IFG_ADDRESS)
#define P2IES_ADDRESS		(0x471C)
#define P2IES				MMR_08_BIT_MACRO(P2IES_ADDRESS)
#define P2IE_ADDRESS		(0x4720)
#define P2IE				MMR_08_BIT_MACRO(P2IE_ADDRESS)
#define P2SEL_ADDRESS		(0x4724)
#define P2SEL				MMR_08_BIT_MACRO(P2SEL_ADDRESS)
#define P2REN_ADDRESS		(0x4728)
#define P2REN				MMR_08_BIT_MACRO(P2REN_ADDRESS)



/** GPIO3 **/
#define GPIO3_BASE			(0x4800)

#define P3IN_ADDRESS		(0x4800)
#define P3IN				MMR_08_BIT_MACRO(P3IN_ADDRESS)
#define P3OUT_ADDRESS		(0x4804)
#define P3OUT				MMR_08_BIT_MACRO(P3OUT_ADDRESS)
#define P3OUTS_ADDRESS		(0x4808)
#define P3OUTS				MMR_08_BIT_MACRO(P3OUTS_ADDRESS)
#define P3OUTC_ADDRESS		(0x480C)
#define P3OUTC				MMR_08_BIT_MACRO(P3OUTC_ADDRESS)
#define P3OUTT_ADDRESS		(0x4810)
#define P3OUTT				MMR_32_BIT_MACRO(P3OUTT_ADDRESS)
#define P3DIR_ADDRESS		(0x4814)
#define P3DIR				MMR_08_BIT_MACRO(P3DIR_ADDRESS)
#define P3IFG_ADDRESS		(0x4818)
#define P3IFG				MMR_08_BIT_MACRO(P3IFG_ADDRESS)
#define P3IES_ADDRESS		(0x481C)
#define P3IES				MMR_08_BIT_MACRO(P3IES_ADDRESS)
#define P3IE_ADDRESS		(0x4820)
#define P3IE				MMR_08_BIT_MACRO(P3IE_ADDRESS)
#define P3SEL_ADDRESS		(0x4824)
#define P3SEL				MMR_08_BIT_MACRO(P3SEL_ADDRESS)
#define P3REN_ADDRESS		(0x4828)
#define P3REN				MMR_08_BIT_MACRO(P3REN_ADDRESS)



/** GPIO4 **/
#define GPIO4_BASE			(0x4900)

#define P4IN_ADDRESS		(0x4900)
#define P4IN				MMR_08_BIT_MACRO(P4IN_ADDRESS)
#define P4OUT_ADDRESS		(0x4904)
#define P4OUT				MMR_08_BIT_MACRO(P4OUT_ADDRESS)
#define P4OUTS_ADDRESS		(0x4908)
#define P4OUTS				MMR_08_BIT_MACRO(P4OUTS_ADDRESS)
#define P4OUTC_ADDRESS		(0x490C)
#define P4OUTC				MMR_08_BIT_MACRO(P4OUTC_ADDRESS)
#define P4OUTT_ADDRESS		(0x4910)
#define P4OUTT				MMR_32_BIT_MACRO(P4OUTT_ADDRESS)
#define P4DIR_ADDRESS		(0x4914)
#define P4DIR				MMR_08_BIT_MACRO(P4DIR_ADDRESS)
#define P4IFG_ADDRESS		(0x4918)
#define P4IFG				MMR_08_BIT_MACRO(P4IFG_ADDRESS)
#define P4IES_ADDRESS		(0x491C)
#define P4IES				MMR_08_BIT_MACRO(P4IES_ADDRESS)
#define P4IE_ADDRESS		(0x4920)
#define P4IE				MMR_08_BIT_MACRO(P4IE_ADDRESS)
#define P4SEL_ADDRESS		(0x4924)
#define P4SEL				MMR_08_BIT_MACRO(P4SEL_ADDRESS)
#define P4REN_ADDRESS		(0x4928)
#define P4REN				MMR_08_BIT_MACRO(P4REN_ADDRESS)



/** GPIO5 **/
#define GPIO5_BASE			(0x4A00)

#define P5IN_ADDRESS		(0x4A00)
#define P5IN				MMR_08_BIT_MACRO(P5IN_ADDRESS)
#define P5OUT_ADDRESS		(0x4A04)
#define P5OUT				MMR_08_BIT_MACRO(P5OUT_ADDRESS)
#define P5OUTS_ADDRESS		(0x4A08)
#define P5OUTS				MMR_08_BIT_MACRO(P5OUTS_ADDRESS)
#define P5OUTC_ADDRESS		(0x4A0C)
#define P5OUTC				MMR_08_BIT_MACRO(P5OUTC_ADDRESS)
#define P5OUTT_ADDRESS		(0x4A10)
#define P5OUTT				MMR_32_BIT_MACRO(P5OUTT_ADDRESS)
#define P5DIR_ADDRESS		(0x4A14)
#define P5DIR				MMR_08_BIT_MACRO(P5DIR_ADDRESS)
#define P5IFG_ADDRESS		(0x4A18)
#define P5IFG				MMR_08_BIT_MACRO(P5IFG_ADDRESS)
#define P5IES_ADDRESS		(0x4A1C)
#define P5IES				MMR_08_BIT_MACRO(P5IES_ADDRESS)
#define P5IE_ADDRESS		(0x4A20)
#define P5IE				MMR_08_BIT_MACRO(P5IE_ADDRESS)
#define P5SEL_ADDRESS		(0x4A24)
#define P5SEL				MMR_08_BIT_MACRO(P5SEL_ADDRESS)
#define P5REN_ADDRESS		(0x4A28)
#define P5REN				MMR_08_BIT_MACRO(P5REN_ADDRESS)



/** I2C0 **/
#define I2C0_BASE			(0x4B00)

#define I2C0CR_ADDRESS		(0x4B00)
#define I2C0CR				MMR_32_BIT_MACRO(I2C0CR_ADDRESS)
#define I2C0FCR_ADDRESS		(0x4B04)
#define I2C0FCR				MMR_08_BIT_MACRO(I2C0FCR_ADDRESS)
#define I2C0SR_ADDRESS		(0x4B08)
#define I2C0SR				MMR_16_BIT_MACRO(I2C0SR_ADDRESS)
#define I2C0MTX_ADDRESS		(0x4B0C)
#define I2C0MTX				MMR_08_BIT_MACRO(I2C0MTX_ADDRESS)
#define I2C0MRX_ADDRESS		(0x4B10)
#define I2C0MRX				MMR_08_BIT_MACRO(I2C0MRX_ADDRESS)
#define I2C0STX_ADDRESS		(0x4B14)
#define I2C0STX				MMR_08_BIT_MACRO(I2C0STX_ADDRESS)
#define I2C0SRX_ADDRESS		(0x4B18)
#define I2C0SRX				MMR_08_BIT_MACRO(I2C0SRX_ADDRESS)
#define I2C0AR_ADDRESS		(0x4B1C)
#define I2C0AR				MMR_08_BIT_MACRO(I2C0AR_ADDRESS)
#define I2C0AMR_ADDRESS		(0x4B20)
#define I2C0AMR				MMR_08_BIT_MACRO(I2C0AMR_ADDRESS)



/** SPI2 **/
#define SPI2_BASE			(0x4C00)

#define SPI2CR_ADDRESS		(0x4C00)
#define SPI2CR				MMR_32_BIT_MACRO(SPI2CR_ADDRESS)
#define SPI2SR_ADDRESS		(0x4C04)
#define SPI2SR				MMR_08_BIT_MACRO(SPI2SR_ADDRESS)
#define SPI2TX_ADDRESS		(0x4C08)
#define SPI2TX				MMR_32_BIT_MACRO(SPI2TX_ADDRESS)
#define SPI2RX_ADDRESS		(0x4C0C)
#define SPI2RX				MMR_32_BIT_MACRO(SPI2RX_ADDRESS)
#define SPI2FOS_ADDRESS		(0x4C10)
#define SPI2FOS				MMR_32_BIT_MACRO(SPI2FOS_ADDRESS)



/** UART1 **/
#define UART1_BASE			(0x4D00)

#define UART1CR_ADDRESS		(0x4D00)
#define UART1CR				MMR_08_BIT_MACRO(UART1CR_ADDRESS)
#define UART1SR_ADDRESS		(0x4D04)
#define UART1SR				MMR_08_BIT_MACRO(UART1SR_ADDRESS)
#define UART1BR_ADDRESS		(0x4D08)
#define UART1BR				MMR_16_BIT_MACRO(UART1BR_ADDRESS)
#define UART1RX_ADDRESS		(0x4D0C)
#define UART1RX				MMR_08_BIT_MACRO(UART1RX_ADDRESS)
#define UART1TX_ADDRESS		(0x4D10)
#define UART1TX				MMR_08_BIT_MACRO(UART1TX_ADDRESS)



/** TIMER2 **/
#define TIMER2_BASE			(0x4E00)

#define TIM2CR_ADDRESS		(0x4E00)
#define TIM2CR				MMR_32_BIT_MACRO(TIM2CR_ADDRESS)
#define TIM2SR_ADDRESS		(0x4E04)
#define TIM2SR				MMR_08_BIT_MACRO(TIM2SR_ADDRESS)
#define TIM2VAL_ADDRESS		(0x4E08)
#define TIM2VAL				MMR_32_BIT_MACRO(TIM2VAL_ADDRESS)
#define TIM2CMP0_ADDRESS	(0x4E0C)
#define TIM2CMP0			MMR_32_BIT_MACRO(TIM2CMP0_ADDRESS)
#define TIM2CMP1_ADDRESS	(0x4E10)
#define TIM2CMP1			MMR_32_BIT_MACRO(TIM2CMP1_ADDRESS)
#define TIM2CMP2_ADDRESS	(0x4E14)
#define TIM2CMP2			MMR_32_BIT_MACRO(TIM2CMP2_ADDRESS)
#define TIM2CAP0_ADDRESS	(0x4E18)
#define TIM2CAP0			MMR_32_BIT_MACRO(TIM2CAP0_ADDRESS)
#define TIM2CAP1_ADDRESS	(0x4E1C)
#define TIM2CAP1			MMR_32_BIT_MACRO(TIM2CAP1_ADDRESS)



/** TIMER3 **/
#define TIMER3_BASE			(0x4F00)

#define TIM3CR_ADDRESS		(0x4F00)
#define TIM3CR				MMR_32_BIT_MACRO(TIM3CR_ADDRESS)
#define TIM3SR_ADDRESS		(0x4F04)
#define TIM3SR				MMR_08_BIT_MACRO(TIM3SR_ADDRESS)
#define TIM3VAL_ADDRESS		(0x4F08)
#define TIM3VAL				MMR_32_BIT_MACRO(TIM3VAL_ADDRESS)
#define TIM3CMP0_ADDRESS	(0x4F0C)
#define TIM3CMP0			MMR_32_BIT_MACRO(TIM3CMP0_ADDRESS)
#define TIM3CMP1_ADDRESS	(0x4F10)
#define TIM3CMP1			MMR_32_BIT_MACRO(TIM3CMP1_ADDRESS)
#define TIM3CMP2_ADDRESS	(0x4F14)
#define TIM3CMP2			MMR_32_BIT_MACRO(TIM3CMP2_ADDRESS)
#define TIM3CAP0_ADDRESS	(0x4F18)
#define TIM3CAP0			MMR_32_BIT_MACRO(TIM3CAP0_ADDRESS)
#define TIM3CAP1_ADDRESS	(0x4F1C)
#define TIM3CAP1			MMR_32_BIT_MACRO(TIM3CAP1_ADDRESS)



/** NN0 **/
#define NN0_BASE			(0x5000)

#define NN0CR_ADDRESS		(0x5000)
#define NN0CR				MMR_32_BIT_MACRO(NN0CR_ADDRESS)
#define NN0IVA_ADDRESS		(0x5004)
#define NN0IVA				MMR_32_BIT_MACRO(NN0IVA_ADDRESS)
#define NN0OVA_ADDRESS		(0x5008)
#define NN0OVA				MMR_32_BIT_MACRO(NN0OVA_ADDRESS)
#define NN0WMA_ADDRESS		(0x500C)
#define NN0WMA				MMR_32_BIT_MACRO(NN0WMA_ADDRESS)
#define NN0LSI_ADDRESS		(0x5010)
#define NN0LSI				MMR_32_BIT_MACRO(NN0LSI_ADDRESS)
#define NN0LSO_ADDRESS		(0x5014)
#define NN0LSO				MMR_16_BIT_MACRO(NN0LSO_ADDRESS)



/** AFE0 **/
#define AFE0_BASE			(0x5100)

#define AFE0CR0_ADDRESS		(0x5100)
#define AFE0CR0				MMR_32_BIT_MACRO(AFE0CR0_ADDRESS)
#define AFE0CR1_ADDRESS		(0x5104)
#define AFE0CR1				MMR_32_BIT_MACRO(AFE0CR1_ADDRESS)
#define AFE0CFB_ADDRESS		(0x5108)
#define AFE0CFB				MMR_08_BIT_MACRO(AFE0CFB_ADDRESS)
#define AFE0RFB_ADDRESS		(0x510C)
#define AFE0RFB				MMR_16_BIT_MACRO(AFE0RFB_ADDRESS)
#define AFE0THR_ADDRESS		(0x5110)
#define AFE0THR				MMR_16_BIT_MACRO(AFE0THR_ADDRESS)
#define AFE0TPR_ADDRESS		(0x5114)
#define AFE0TPR				MMR_32_BIT_MACRO(AFE0TPR_ADDRESS)
#define AFE0SPT_ADDRESS		(0x5118)
#define AFE0SPT				MMR_08_BIT_MACRO(AFE0SPT_ADDRESS)
#define AFE0PIT_ADDRESS		(0x511C)
#define AFE0PIT				MMR_16_BIT_MACRO(AFE0PIT_ADDRESS)
#define AFE0EIT_ADDRESS		(0x5120)
#define AFE0EIT				MMR_16_BIT_MACRO(AFE0EIT_ADDRESS)
#define AFE0LIT_ADDRESS		(0x5124)
#define AFE0LIT				MMR_16_BIT_MACRO(AFE0LIT_ADDRESS)
#define AFE0RJT_ADDRESS		(0x5128)
#define AFE0RJT				MMR_16_BIT_MACRO(AFE0RJT_ADDRESS)
#define AFE0RST_ADDRESS		(0x512C)
#define AFE0RST				MMR_08_BIT_MACRO(AFE0RST_ADDRESS)
#define AFE0AOFST_ADDRESS	(0x5130)
#define AFE0AOFST			MMR_16_BIT_MACRO(AFE0AOFST_ADDRESS)
#define AFE0BLLT_ADDRESS	(0x5134)
#define AFE0BLLT			MMR_16_BIT_MACRO(AFE0BLLT_ADDRESS)
#define AFE0CSAREF_ADDRESS	(0x5138)
#define AFE0CSAREF			MMR_16_BIT_MACRO(AFE0CSAREF_ADDRESS)
#define AFE0CSABP_ADDRESS	(0x513C)
#define AFE0CSABP			MMR_16_BIT_MACRO(AFE0CSABP_ADDRESS)
#define AFE0CSABPC_ADDRESS	(0x5140)
#define AFE0CSABPC			MMR_16_BIT_MACRO(AFE0CSABPC_ADDRESS)
#define AFE0CSABNC_ADDRESS	(0x5144)
#define AFE0CSABNC			MMR_16_BIT_MACRO(AFE0CSABNC_ADDRESS)
#define AFE0CSABN_ADDRESS	(0x5148)
#define AFE0CSABN			MMR_16_BIT_MACRO(AFE0CSABN_ADDRESS)
#define AFE0CMSHR_ADDRESS	(0x514C)
#define AFE0CMSHR			MMR_16_BIT_MACRO(AFE0CMSHR_ADDRESS)
#define AFE0CLPF_ADDRESS	(0x5150)
#define AFE0CLPF			MMR_08_BIT_MACRO(AFE0CLPF_ADDRESS)
#define AFE0SR_ADDRESS		(0x5154)
#define AFE0SR				MMR_08_BIT_MACRO(AFE0SR_ADDRESS)
#define AFE0ADCVAL_ADDRESS	(0x5158)
#define AFE0ADCVAL			MMR_16_BIT_MACRO(AFE0ADCVAL_ADDRESS)
#define AFE0VPC_ADDRESS		(0x515C)
#define AFE0VPC				MMR_32_BIT_MACRO(AFE0VPC_ADDRESS)
#define AFE0TPC_ADDRESS		(0x5160)
#define AFE0TPC				MMR_32_BIT_MACRO(AFE0TPC_ADDRESS)



/** AFE1 **/
#define AFE1_BASE			(0x5200)

#define AFE1CR0_ADDRESS		(0x5200)
#define AFE1CR0				MMR_32_BIT_MACRO(AFE1CR0_ADDRESS)
#define AFE1CR1_ADDRESS		(0x5204)
#define AFE1CR1				MMR_32_BIT_MACRO(AFE1CR1_ADDRESS)
#define AFE1CFB_ADDRESS		(0x5208)
#define AFE1CFB				MMR_08_BIT_MACRO(AFE1CFB_ADDRESS)
#define AFE1RFB_ADDRESS		(0x520C)
#define AFE1RFB				MMR_16_BIT_MACRO(AFE1RFB_ADDRESS)
#define AFE1THR_ADDRESS		(0x5210)
#define AFE1THR				MMR_16_BIT_MACRO(AFE1THR_ADDRESS)
#define AFE1TPR_ADDRESS		(0x5214)
#define AFE1TPR				MMR_32_BIT_MACRO(AFE1TPR_ADDRESS)
#define AFE1SPT_ADDRESS		(0x5218)
#define AFE1SPT				MMR_08_BIT_MACRO(AFE1SPT_ADDRESS)
#define AFE1PIT_ADDRESS		(0x521C)
#define AFE1PIT				MMR_16_BIT_MACRO(AFE1PIT_ADDRESS)
#define AFE1EIT_ADDRESS		(0x5220)
#define AFE1EIT				MMR_16_BIT_MACRO(AFE1EIT_ADDRESS)
#define AFE1LIT_ADDRESS		(0x5224)
#define AFE1LIT				MMR_16_BIT_MACRO(AFE1LIT_ADDRESS)
#define AFE1RJT_ADDRESS		(0x5228)
#define AFE1RJT				MMR_16_BIT_MACRO(AFE1RJT_ADDRESS)
#define AFE1RST_ADDRESS		(0x522C)
#define AFE1RST				MMR_08_BIT_MACRO(AFE1RST_ADDRESS)
#define AFE1AOFST_ADDRESS	(0x5230)
#define AFE1AOFST			MMR_16_BIT_MACRO(AFE1AOFST_ADDRESS)
#define AFE1BLLT_ADDRESS	(0x5234)
#define AFE1BLLT			MMR_16_BIT_MACRO(AFE1BLLT_ADDRESS)
#define AFE1CSAREF_ADDRESS	(0x5238)
#define AFE1CSAREF			MMR_16_BIT_MACRO(AFE1CSAREF_ADDRESS)
#define AFE1CSABP_ADDRESS	(0x523C)
#define AFE1CSABP			MMR_16_BIT_MACRO(AFE1CSABP_ADDRESS)
#define AFE1CSABPC_ADDRESS	(0x5240)
#define AFE1CSABPC			MMR_16_BIT_MACRO(AFE1CSABPC_ADDRESS)
#define AFE1CSABNC_ADDRESS	(0x5244)
#define AFE1CSABNC			MMR_16_BIT_MACRO(AFE1CSABNC_ADDRESS)
#define AFE1CSABN_ADDRESS	(0x5248)
#define AFE1CSABN			MMR_16_BIT_MACRO(AFE1CSABN_ADDRESS)
#define AFE1CMSHR_ADDRESS	(0x524C)
#define AFE1CMSHR			MMR_16_BIT_MACRO(AFE1CMSHR_ADDRESS)
#define AFE1CLPF_ADDRESS	(0x5250)
#define AFE1CLPF			MMR_08_BIT_MACRO(AFE1CLPF_ADDRESS)
#define AFE1SR_ADDRESS		(0x5254)
#define AFE1SR				MMR_08_BIT_MACRO(AFE1SR_ADDRESS)
#define AFE1ADCVAL_ADDRESS	(0x5258)
#define AFE1ADCVAL			MMR_16_BIT_MACRO(AFE1ADCVAL_ADDRESS)
#define AFE1VPC_ADDRESS		(0x525C)
#define AFE1VPC				MMR_32_BIT_MACRO(AFE1VPC_ADDRESS)
#define AFE1TPC_ADDRESS		(0x5260)
#define AFE1TPC				MMR_32_BIT_MACRO(AFE1TPC_ADDRESS)



/** AFE2 **/
#define AFE2_BASE			(0x5300)

#define AFE2CR0_ADDRESS		(0x5300)
#define AFE2CR0				MMR_32_BIT_MACRO(AFE2CR0_ADDRESS)
#define AFE2CR1_ADDRESS		(0x5304)
#define AFE2CR1				MMR_32_BIT_MACRO(AFE2CR1_ADDRESS)
#define AFE2CFB_ADDRESS		(0x5308)
#define AFE2CFB				MMR_08_BIT_MACRO(AFE2CFB_ADDRESS)
#define AFE2RFB_ADDRESS		(0x530C)
#define AFE2RFB				MMR_16_BIT_MACRO(AFE2RFB_ADDRESS)
#define AFE2THR_ADDRESS		(0x5310)
#define AFE2THR				MMR_16_BIT_MACRO(AFE2THR_ADDRESS)
#define AFE2TPR_ADDRESS		(0x5314)
#define AFE2TPR				MMR_32_BIT_MACRO(AFE2TPR_ADDRESS)
#define AFE2SPT_ADDRESS		(0x5318)
#define AFE2SPT				MMR_08_BIT_MACRO(AFE2SPT_ADDRESS)
#define AFE2PIT_ADDRESS		(0x531C)
#define AFE2PIT				MMR_16_BIT_MACRO(AFE2PIT_ADDRESS)
#define AFE2EIT_ADDRESS		(0x5320)
#define AFE2EIT				MMR_16_BIT_MACRO(AFE2EIT_ADDRESS)
#define AFE2LIT_ADDRESS		(0x5324)
#define AFE2LIT				MMR_16_BIT_MACRO(AFE2LIT_ADDRESS)
#define AFE2RJT_ADDRESS		(0x5328)
#define AFE2RJT				MMR_16_BIT_MACRO(AFE2RJT_ADDRESS)
#define AFE2RST_ADDRESS		(0x532C)
#define AFE2RST				MMR_08_BIT_MACRO(AFE2RST_ADDRESS)
#define AFE2AOFST_ADDRESS	(0x5330)
#define AFE2AOFST			MMR_16_BIT_MACRO(AFE2AOFST_ADDRESS)
#define AFE2BLLT_ADDRESS	(0x5334)
#define AFE2BLLT			MMR_16_BIT_MACRO(AFE2BLLT_ADDRESS)
#define AFE2CSAREF_ADDRESS	(0x5338)
#define AFE2CSAREF			MMR_16_BIT_MACRO(AFE2CSAREF_ADDRESS)
#define AFE2CSABP_ADDRESS	(0x533C)
#define AFE2CSABP			MMR_16_BIT_MACRO(AFE2CSABP_ADDRESS)
#define AFE2CSABPC_ADDRESS	(0x5340)
#define AFE2CSABPC			MMR_16_BIT_MACRO(AFE2CSABPC_ADDRESS)
#define AFE2CSABNC_ADDRESS	(0x5344)
#define AFE2CSABNC			MMR_16_BIT_MACRO(AFE2CSABNC_ADDRESS)
#define AFE2CSABN_ADDRESS	(0x5348)
#define AFE2CSABN			MMR_16_BIT_MACRO(AFE2CSABN_ADDRESS)
#define AFE2CMSHR_ADDRESS	(0x534C)
#define AFE2CMSHR			MMR_16_BIT_MACRO(AFE2CMSHR_ADDRESS)
#define AFE2CLPF_ADDRESS	(0x5350)
#define AFE2CLPF			MMR_08_BIT_MACRO(AFE2CLPF_ADDRESS)
#define AFE2SR_ADDRESS		(0x5354)
#define AFE2SR				MMR_08_BIT_MACRO(AFE2SR_ADDRESS)
#define AFE2ADCVAL_ADDRESS	(0x5358)
#define AFE2ADCVAL			MMR_16_BIT_MACRO(AFE2ADCVAL_ADDRESS)
#define AFE2VPC_ADDRESS		(0x535C)
#define AFE2VPC				MMR_32_BIT_MACRO(AFE2VPC_ADDRESS)
#define AFE2TPC_ADDRESS		(0x5360)
#define AFE2TPC				MMR_32_BIT_MACRO(AFE2TPC_ADDRESS)



/** AFE3 **/
#define AFE3_BASE			(0x5400)

#define AFE3CR0_ADDRESS		(0x5400)
#define AFE3CR0				MMR_32_BIT_MACRO(AFE3CR0_ADDRESS)
#define AFE3CR1_ADDRESS		(0x5404)
#define AFE3CR1				MMR_32_BIT_MACRO(AFE3CR1_ADDRESS)
#define AFE3CFB_ADDRESS		(0x5408)
#define AFE3CFB				MMR_08_BIT_MACRO(AFE3CFB_ADDRESS)
#define AFE3RFB_ADDRESS		(0x540C)
#define AFE3RFB				MMR_16_BIT_MACRO(AFE3RFB_ADDRESS)
#define AFE3THR_ADDRESS		(0x5410)
#define AFE3THR				MMR_16_BIT_MACRO(AFE3THR_ADDRESS)
#define AFE3TPR_ADDRESS		(0x5414)
#define AFE3TPR				MMR_32_BIT_MACRO(AFE3TPR_ADDRESS)
#define AFE3SPT_ADDRESS		(0x5418)
#define AFE3SPT				MMR_08_BIT_MACRO(AFE3SPT_ADDRESS)
#define AFE3PIT_ADDRESS		(0x541C)
#define AFE3PIT				MMR_16_BIT_MACRO(AFE3PIT_ADDRESS)
#define AFE3EIT_ADDRESS		(0x5420)
#define AFE3EIT				MMR_16_BIT_MACRO(AFE3EIT_ADDRESS)
#define AFE3LIT_ADDRESS		(0x5424)
#define AFE3LIT				MMR_16_BIT_MACRO(AFE3LIT_ADDRESS)
#define AFE3RJT_ADDRESS		(0x5428)
#define AFE3RJT				MMR_16_BIT_MACRO(AFE3RJT_ADDRESS)
#define AFE3RST_ADDRESS		(0x542C)
#define AFE3RST				MMR_08_BIT_MACRO(AFE3RST_ADDRESS)
#define AFE3AOFST_ADDRESS	(0x5430)
#define AFE3AOFST			MMR_16_BIT_MACRO(AFE3AOFST_ADDRESS)
#define AFE3BLLT_ADDRESS	(0x5434)
#define AFE3BLLT			MMR_16_BIT_MACRO(AFE3BLLT_ADDRESS)
#define AFE3CSAREF_ADDRESS	(0x5438)
#define AFE3CSAREF			MMR_16_BIT_MACRO(AFE3CSAREF_ADDRESS)
#define AFE3CSABP_ADDRESS	(0x543C)
#define AFE3CSABP			MMR_16_BIT_MACRO(AFE3CSABP_ADDRESS)
#define AFE3CSABPC_ADDRESS	(0x5440)
#define AFE3CSABPC			MMR_16_BIT_MACRO(AFE3CSABPC_ADDRESS)
#define AFE3CSABNC_ADDRESS	(0x5444)
#define AFE3CSABNC			MMR_16_BIT_MACRO(AFE3CSABNC_ADDRESS)
#define AFE3CSABN_ADDRESS	(0x5448)
#define AFE3CSABN			MMR_16_BIT_MACRO(AFE3CSABN_ADDRESS)
#define AFE3CMSHR_ADDRESS	(0x544C)
#define AFE3CMSHR			MMR_16_BIT_MACRO(AFE3CMSHR_ADDRESS)
#define AFE3CLPF_ADDRESS	(0x5450)
#define AFE3CLPF			MMR_08_BIT_MACRO(AFE3CLPF_ADDRESS)
#define AFE3SR_ADDRESS		(0x5454)
#define AFE3SR				MMR_08_BIT_MACRO(AFE3SR_ADDRESS)
#define AFE3ADCVAL_ADDRESS	(0x5458)
#define AFE3ADCVAL			MMR_16_BIT_MACRO(AFE3ADCVAL_ADDRESS)
#define AFE3VPC_ADDRESS		(0x545C)
#define AFE3VPC				MMR_32_BIT_MACRO(AFE3VPC_ADDRESS)
#define AFE3TPC_ADDRESS		(0x5460)
#define AFE3TPC				MMR_32_BIT_MACRO(AFE3TPC_ADDRESS)



/** AFE4 **/
#define AFE4_BASE			(0x5500)

#define AFE4CR0_ADDRESS		(0x5500)
#define AFE4CR0				MMR_32_BIT_MACRO(AFE4CR0_ADDRESS)
#define AFE4CR1_ADDRESS		(0x5504)
#define AFE4CR1				MMR_32_BIT_MACRO(AFE4CR1_ADDRESS)
#define AFE4CFB_ADDRESS		(0x5508)
#define AFE4CFB				MMR_08_BIT_MACRO(AFE4CFB_ADDRESS)
#define AFE4RFB_ADDRESS		(0x550C)
#define AFE4RFB				MMR_16_BIT_MACRO(AFE4RFB_ADDRESS)
#define AFE4THR_ADDRESS		(0x5510)
#define AFE4THR				MMR_16_BIT_MACRO(AFE4THR_ADDRESS)
#define AFE4TPR_ADDRESS		(0x5514)
#define AFE4TPR				MMR_32_BIT_MACRO(AFE4TPR_ADDRESS)
#define AFE4SPT_ADDRESS		(0x5518)
#define AFE4SPT				MMR_08_BIT_MACRO(AFE4SPT_ADDRESS)
#define AFE4PIT_ADDRESS		(0x551C)
#define AFE4PIT				MMR_16_BIT_MACRO(AFE4PIT_ADDRESS)
#define AFE4EIT_ADDRESS		(0x5520)
#define AFE4EIT				MMR_16_BIT_MACRO(AFE4EIT_ADDRESS)
#define AFE4LIT_ADDRESS		(0x5524)
#define AFE4LIT				MMR_16_BIT_MACRO(AFE4LIT_ADDRESS)
#define AFE4RJT_ADDRESS		(0x5528)
#define AFE4RJT				MMR_16_BIT_MACRO(AFE4RJT_ADDRESS)
#define AFE4RST_ADDRESS		(0x552C)
#define AFE4RST				MMR_08_BIT_MACRO(AFE4RST_ADDRESS)
#define AFE4AOFST_ADDRESS	(0x5530)
#define AFE4AOFST			MMR_16_BIT_MACRO(AFE4AOFST_ADDRESS)
#define AFE4BLLT_ADDRESS	(0x5534)
#define AFE4BLLT			MMR_16_BIT_MACRO(AFE4BLLT_ADDRESS)
#define AFE4CSAREF_ADDRESS	(0x5538)
#define AFE4CSAREF			MMR_16_BIT_MACRO(AFE4CSAREF_ADDRESS)
#define AFE4CSABP_ADDRESS	(0x553C)
#define AFE4CSABP			MMR_16_BIT_MACRO(AFE4CSABP_ADDRESS)
#define AFE4CSABPC_ADDRESS	(0x5540)
#define AFE4CSABPC			MMR_16_BIT_MACRO(AFE4CSABPC_ADDRESS)
#define AFE4CSABNC_ADDRESS	(0x5544)
#define AFE4CSABNC			MMR_16_BIT_MACRO(AFE4CSABNC_ADDRESS)
#define AFE4CSABN_ADDRESS	(0x5548)
#define AFE4CSABN			MMR_16_BIT_MACRO(AFE4CSABN_ADDRESS)
#define AFE4CMSHR_ADDRESS	(0x554C)
#define AFE4CMSHR			MMR_16_BIT_MACRO(AFE4CMSHR_ADDRESS)
#define AFE4CLPF_ADDRESS	(0x5550)
#define AFE4CLPF			MMR_08_BIT_MACRO(AFE4CLPF_ADDRESS)
#define AFE4SR_ADDRESS		(0x5554)
#define AFE4SR				MMR_08_BIT_MACRO(AFE4SR_ADDRESS)
#define AFE4ADCVAL_ADDRESS	(0x5558)
#define AFE4ADCVAL			MMR_16_BIT_MACRO(AFE4ADCVAL_ADDRESS)
#define AFE4VPC_ADDRESS		(0x555C)
#define AFE4VPC				MMR_32_BIT_MACRO(AFE4VPC_ADDRESS)
#define AFE4TPC_ADDRESS		(0x5560)
#define AFE4TPC				MMR_32_BIT_MACRO(AFE4TPC_ADDRESS)



/** AFE5 **/
#define AFE5_BASE			(0x5600)

#define AFE5CR0_ADDRESS		(0x5600)
#define AFE5CR0				MMR_32_BIT_MACRO(AFE5CR0_ADDRESS)
#define AFE5CR1_ADDRESS		(0x5604)
#define AFE5CR1				MMR_32_BIT_MACRO(AFE5CR1_ADDRESS)
#define AFE5CFB_ADDRESS		(0x5608)
#define AFE5CFB				MMR_08_BIT_MACRO(AFE5CFB_ADDRESS)
#define AFE5RFB_ADDRESS		(0x560C)
#define AFE5RFB				MMR_16_BIT_MACRO(AFE5RFB_ADDRESS)
#define AFE5THR_ADDRESS		(0x5610)
#define AFE5THR				MMR_16_BIT_MACRO(AFE5THR_ADDRESS)
#define AFE5TPR_ADDRESS		(0x5614)
#define AFE5TPR				MMR_32_BIT_MACRO(AFE5TPR_ADDRESS)
#define AFE5SPT_ADDRESS		(0x5618)
#define AFE5SPT				MMR_08_BIT_MACRO(AFE5SPT_ADDRESS)
#define AFE5PIT_ADDRESS		(0x561C)
#define AFE5PIT				MMR_16_BIT_MACRO(AFE5PIT_ADDRESS)
#define AFE5EIT_ADDRESS		(0x5620)
#define AFE5EIT				MMR_16_BIT_MACRO(AFE5EIT_ADDRESS)
#define AFE5LIT_ADDRESS		(0x5624)
#define AFE5LIT				MMR_16_BIT_MACRO(AFE5LIT_ADDRESS)
#define AFE5RJT_ADDRESS		(0x5628)
#define AFE5RJT				MMR_16_BIT_MACRO(AFE5RJT_ADDRESS)
#define AFE5RST_ADDRESS		(0x562C)
#define AFE5RST				MMR_08_BIT_MACRO(AFE5RST_ADDRESS)
#define AFE5AOFST_ADDRESS	(0x5630)
#define AFE5AOFST			MMR_16_BIT_MACRO(AFE5AOFST_ADDRESS)
#define AFE5BLLT_ADDRESS	(0x5634)
#define AFE5BLLT			MMR_16_BIT_MACRO(AFE5BLLT_ADDRESS)
#define AFE5CSAREF_ADDRESS	(0x5638)
#define AFE5CSAREF			MMR_16_BIT_MACRO(AFE5CSAREF_ADDRESS)
#define AFE5CSABP_ADDRESS	(0x563C)
#define AFE5CSABP			MMR_16_BIT_MACRO(AFE5CSABP_ADDRESS)
#define AFE5CSABPC_ADDRESS	(0x5640)
#define AFE5CSABPC			MMR_16_BIT_MACRO(AFE5CSABPC_ADDRESS)
#define AFE5CSABNC_ADDRESS	(0x5644)
#define AFE5CSABNC			MMR_16_BIT_MACRO(AFE5CSABNC_ADDRESS)
#define AFE5CSABN_ADDRESS	(0x5648)
#define AFE5CSABN			MMR_16_BIT_MACRO(AFE5CSABN_ADDRESS)
#define AFE5CMSHR_ADDRESS	(0x564C)
#define AFE5CMSHR			MMR_16_BIT_MACRO(AFE5CMSHR_ADDRESS)
#define AFE5CLPF_ADDRESS	(0x5650)
#define AFE5CLPF			MMR_08_BIT_MACRO(AFE5CLPF_ADDRESS)
#define AFE5SR_ADDRESS		(0x5654)
#define AFE5SR				MMR_08_BIT_MACRO(AFE5SR_ADDRESS)
#define AFE5ADCVAL_ADDRESS	(0x5658)
#define AFE5ADCVAL			MMR_16_BIT_MACRO(AFE5ADCVAL_ADDRESS)
#define AFE5VPC_ADDRESS		(0x565C)
#define AFE5VPC				MMR_32_BIT_MACRO(AFE5VPC_ADDRESS)
#define AFE5TPC_ADDRESS		(0x5660)
#define AFE5TPC				MMR_32_BIT_MACRO(AFE5TPC_ADDRESS)



/** PCT **/
#define PCT_BASE			(0x5700)

#define PCTCR_ADDRESS		(0x5700)
#define PCTCR				MMR_08_BIT_MACRO(PCTCR_ADDRESS)
#define PCTCNT0_ADDRESS		(0x5704)
#define PCTCNT0				MMR_32_BIT_MACRO(PCTCNT0_ADDRESS)
#define PCTCNT1_ADDRESS		(0x5708)
#define PCTCNT1				MMR_32_BIT_MACRO(PCTCNT1_ADDRESS)
#define PCTCNT2_ADDRESS		(0x570C)
#define PCTCNT2				MMR_32_BIT_MACRO(PCTCNT2_ADDRESS)
#define PCTCNT3_ADDRESS		(0x5710)
#define PCTCNT3				MMR_32_BIT_MACRO(PCTCNT3_ADDRESS)



/** GPIO6 **/
#define GPIO6_BASE			(0x5800)

#define P6IN_ADDRESS		(0x5800)
#define P6IN				MMR_08_BIT_MACRO(P6IN_ADDRESS)
#define P6OUT_ADDRESS		(0x5804)
#define P6OUT				MMR_08_BIT_MACRO(P6OUT_ADDRESS)
#define P6OUTS_ADDRESS		(0x5808)
#define P6OUTS				MMR_08_BIT_MACRO(P6OUTS_ADDRESS)
#define P6OUTC_ADDRESS		(0x580C)
#define P6OUTC				MMR_08_BIT_MACRO(P6OUTC_ADDRESS)
#define P6OUTT_ADDRESS		(0x5810)
#define P6OUTT				MMR_32_BIT_MACRO(P6OUTT_ADDRESS)
#define P6DIR_ADDRESS		(0x5814)
#define P6DIR				MMR_08_BIT_MACRO(P6DIR_ADDRESS)
#define P6IFG_ADDRESS		(0x5818)
#define P6IFG				MMR_08_BIT_MACRO(P6IFG_ADDRESS)
#define P6IES_ADDRESS		(0x581C)
#define P6IES				MMR_08_BIT_MACRO(P6IES_ADDRESS)
#define P6IE_ADDRESS		(0x5820)
#define P6IE				MMR_08_BIT_MACRO(P6IE_ADDRESS)
#define P6SEL_ADDRESS		(0x5824)
#define P6SEL				MMR_08_BIT_MACRO(P6SEL_ADDRESS)
#define P6REN_ADDRESS		(0x5828)
#define P6REN				MMR_08_BIT_MACRO(P6REN_ADDRESS)



/** GPIO7 **/
#define GPIO7_BASE			(0x5900)

#define P7IN_ADDRESS		(0x5900)
#define P7IN				MMR_08_BIT_MACRO(P7IN_ADDRESS)
#define P7OUT_ADDRESS		(0x5904)
#define P7OUT				MMR_08_BIT_MACRO(P7OUT_ADDRESS)
#define P7OUTS_ADDRESS		(0x5908)
#define P7OUTS				MMR_08_BIT_MACRO(P7OUTS_ADDRESS)
#define P7OUTC_ADDRESS		(0x590C)
#define P7OUTC				MMR_08_BIT_MACRO(P7OUTC_ADDRESS)
#define P7OUTT_ADDRESS		(0x5910)
#define P7OUTT				MMR_32_BIT_MACRO(P7OUTT_ADDRESS)
#define P7DIR_ADDRESS		(0x5914)
#define P7DIR				MMR_08_BIT_MACRO(P7DIR_ADDRESS)
#define P7IFG_ADDRESS		(0x5918)
#define P7IFG				MMR_08_BIT_MACRO(P7IFG_ADDRESS)
#define P7IES_ADDRESS		(0x591C)
#define P7IES				MMR_08_BIT_MACRO(P7IES_ADDRESS)
#define P7IE_ADDRESS		(0x5920)
#define P7IE				MMR_08_BIT_MACRO(P7IE_ADDRESS)
#define P7SEL_ADDRESS		(0x5924)
#define P7SEL				MMR_08_BIT_MACRO(P7SEL_ADDRESS)
#define P7REN_ADDRESS		(0x5928)
#define P7REN				MMR_08_BIT_MACRO(P7REN_ADDRESS)



/** GPIO8 **/
#define GPIO8_BASE			(0x5A00)

#define P8IN_ADDRESS		(0x5A00)
#define P8IN				MMR_08_BIT_MACRO(P8IN_ADDRESS)
#define P8OUT_ADDRESS		(0x5A04)
#define P8OUT				MMR_08_BIT_MACRO(P8OUT_ADDRESS)
#define P8OUTS_ADDRESS		(0x5A08)
#define P8OUTS				MMR_08_BIT_MACRO(P8OUTS_ADDRESS)
#define P8OUTC_ADDRESS		(0x5A0C)
#define P8OUTC				MMR_08_BIT_MACRO(P8OUTC_ADDRESS)
#define P8OUTT_ADDRESS		(0x5A10)
#define P8OUTT				MMR_32_BIT_MACRO(P8OUTT_ADDRESS)
#define P8DIR_ADDRESS		(0x5A14)
#define P8DIR				MMR_08_BIT_MACRO(P8DIR_ADDRESS)
#define P8IFG_ADDRESS		(0x5A18)
#define P8IFG				MMR_08_BIT_MACRO(P8IFG_ADDRESS)
#define P8IES_ADDRESS		(0x5A1C)
#define P8IES				MMR_08_BIT_MACRO(P8IES_ADDRESS)
#define P8IE_ADDRESS		(0x5A20)
#define P8IE				MMR_08_BIT_MACRO(P8IE_ADDRESS)
#define P8SEL_ADDRESS		(0x5A24)
#define P8SEL				MMR_08_BIT_MACRO(P8SEL_ADDRESS)
#define P8REN_ADDRESS		(0x5A28)
#define P8REN				MMR_08_BIT_MACRO(P8REN_ADDRESS)



/** OPA **/
#define OPA_BASE			(0x5B00)

#define OPACR_ADDRESS		(0x5B00)
#define OPACR				MMR_16_BIT_MACRO(OPACR_ADDRESS)
#define OPASR_ADDRESS		(0x5B04)
#define OPASR				MMR_08_BIT_MACRO(OPASR_ADDRESS)



/** DAC **/
#define DAC_BASE			(0x5C00)

#define DACCR_ADDRESS		(0x5C00)
#define DACCR				MMR_16_BIT_MACRO(DACCR_ADDRESS)
#define DACSR_ADDRESS		(0x5C04)
#define DACSR				MMR_08_BIT_MACRO(DACSR_ADDRESS)
#define DAC0VAL_ADDRESS		(0x5C08)
#define DAC0VAL				MMR_16_BIT_MACRO(DAC0VAL_ADDRESS)
#define DAC1VAL_ADDRESS		(0x5C0C)
#define DAC1VAL				MMR_16_BIT_MACRO(DAC1VAL_ADDRESS)
#define DACFS_ADDRESS		(0x5C10)
#define DACFS				MMR_16_BIT_MACRO(DACFS_ADDRESS)
#define DACHBS_ADDRESS		(0x5C14)
#define DACHBS				MMR_08_BIT_MACRO(DACHBS_ADDRESS)



/** I2C1 **/
#define I2C1_BASE			(0x5D00)

#define I2C1CR_ADDRESS		(0x5D00)
#define I2C1CR				MMR_32_BIT_MACRO(I2C1CR_ADDRESS)
#define I2C1FCR_ADDRESS		(0x5D04)
#define I2C1FCR				MMR_08_BIT_MACRO(I2C1FCR_ADDRESS)
#define I2C1SR_ADDRESS		(0x5D08)
#define I2C1SR				MMR_16_BIT_MACRO(I2C1SR_ADDRESS)
#define I2C1MTX_ADDRESS		(0x5D0C)
#define I2C1MTX				MMR_08_BIT_MACRO(I2C1MTX_ADDRESS)
#define I2C1MRX_ADDRESS		(0x5D10)
#define I2C1MRX				MMR_08_BIT_MACRO(I2C1MRX_ADDRESS)
#define I2C1STX_ADDRESS		(0x5D14)
#define I2C1STX				MMR_08_BIT_MACRO(I2C1STX_ADDRESS)
#define I2C1SRX_ADDRESS		(0x5D18)
#define I2C1SRX				MMR_08_BIT_MACRO(I2C1SRX_ADDRESS)
#define I2C1AR_ADDRESS		(0x5D1C)
#define I2C1AR				MMR_08_BIT_MACRO(I2C1AR_ADDRESS)
#define I2C1AMR_ADDRESS		(0x5D20)
#define I2C1AMR				MMR_08_BIT_MACRO(I2C1AMR_ADDRESS)



/** UART2 **/
#define UART2_BASE			(0x5E00)

#define UART2CR_ADDRESS		(0x5E00)
#define UART2CR				MMR_08_BIT_MACRO(UART2CR_ADDRESS)
#define UART2SR_ADDRESS		(0x5E04)
#define UART2SR				MMR_08_BIT_MACRO(UART2SR_ADDRESS)
#define UART2BR_ADDRESS		(0x5E08)
#define UART2BR				MMR_16_BIT_MACRO(UART2BR_ADDRESS)
#define UART2RX_ADDRESS		(0x5E0C)
#define UART2RX				MMR_08_BIT_MACRO(UART2RX_ADDRESS)
#define UART2TX_ADDRESS		(0x5E10)
#define UART2TX				MMR_08_BIT_MACRO(UART2TX_ADDRESS)



/********** Peripheral, Register, and Bit Field Structures **********/

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

/** Peripheral PCT **/
// Bit fields structure for register PCTCR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t ENPCT0_	: 1;	// bit 0
		volatile uint8_t ENPCT1_	: 1;	// bit 1
		volatile uint8_t ENPCT2_	: 1;	// bit 2
		volatile uint8_t ENPCT3_	: 1;	// bit 3
		volatile uint8_t ESPCT0_	: 1;	// bit 4
		volatile uint8_t ESPCT1_	: 1;	// bit 5
		volatile uint8_t ESPCT2_	: 1;	// bit 6
		volatile uint8_t ESPCT3_	: 1;	// bit 7
	};
} PCTCR_Register_t;

// Bit fields structure for register PCTCNT0
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CNT0	: 32;	// bits 31 downto 0
	};
} PCTCNT0_Register_t;

// Bit fields structure for register PCTCNT1
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CNT1	: 32;	// bits 31 downto 0
	};
} PCTCNT1_Register_t;

// Bit fields structure for register PCTCNT2
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CNT2	: 32;	// bits 31 downto 0
	};
} PCTCNT2_Register_t;

// Bit fields structure for register PCTCNT3
typedef union
{
	volatile uint32_t value;
	struct
	{
		volatile uint32_t CNT3	: 32;	// bits 31 downto 0
	};
} PCTCNT3_Register_t;



// Registers structure for peripheral PCT
typedef struct
{
	volatile PCTCR_Register_t	CR;
	volatile uint8_t			__unused0;
	volatile uint16_t			__unused1;
	volatile PCTCNT0_Register_t	CNT0;
	volatile PCTCNT1_Register_t	CNT1;
	volatile PCTCNT2_Register_t	CNT2;
	volatile PCTCNT3_Register_t	CNT3;
	volatile uint32_t			__unused2[59];
} PCT_t;

/** Peripheral OPA **/
// Bit fields structure for register OPACR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t OPA0MODE_		: 2;	// bits 1 downto 0
		volatile uint16_t OPA0BS_		: 1;	// bit 2
		volatile uint16_t OPA0PDWD_		: 1;	// bit 3
		volatile uint16_t OPA1MODE_		: 2;	// bits 5 downto 4
		volatile uint16_t OPA1BS_		: 1;	// bit 6
		volatile uint16_t OPA1PDWD_		: 1;	// bit 7
		volatile uint16_t OPA0CMPEN_	: 1;	// bit 8
		volatile uint16_t OPA0CMPIE_	: 1;	// bit 9
		volatile uint16_t OPA0CMPIES_	: 1;	// bit 10
		volatile uint16_t OPA1CMPEN_	: 1;	// bit 11
		volatile uint16_t OPA1CMPIE_	: 1;	// bit 12
		volatile uint16_t OPA1CMPIES_	: 1;	// bit 13
		volatile uint16_t __unused0		: 2;	// bits 15 downto 14
	};
} OPACR_Register_t;

// Bit fields structure for register OPASR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t OPA0CMPVAL_	: 1;	// bit 0
		volatile uint8_t OPA1CMPVAL_	: 1;	// bit 1
		volatile uint8_t OPA0CMPIF_		: 1;	// bit 2
		volatile uint8_t OPA1CMPIF_		: 1;	// bit 3
		volatile uint8_t __unused0		: 4;	// bits 7 downto 4
	};
} OPASR_Register_t;



// Registers structure for peripheral OPA
typedef struct
{
	volatile OPACR_Register_t	CR;
	volatile uint16_t			__unused0;
	volatile OPASR_Register_t	SR;
	volatile uint8_t			__unused1;
	volatile uint16_t			__unused2;
	volatile uint32_t			__unused3[62];
} OPA_t;

/** Peripheral DAC **/
// Bit fields structure for register DACCR
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DACBEIE_	: 1;	// bit 0
		volatile uint16_t DACDAL_	: 1;	// bit 1
		volatile uint16_t DACCS_	: 2;	// bits 3 downto 2
		volatile uint16_t DAC0DEN_	: 1;	// bit 4
		volatile uint16_t DAC1DEN_	: 1;	// bit 5
		volatile uint16_t DAC0EN_	: 1;	// bit 6
		volatile uint16_t DAC1EN_	: 1;	// bit 7
		volatile uint16_t DACCDIV_	: 3;	// bits 10 downto 8
		volatile uint16_t __unused0	: 5;	// bits 15 downto 11
	};
} DACCR_Register_t;

// Bit fields structure for register DACSR
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t DACBEIF_	: 1;	// bit 0
		volatile uint8_t DACBH_		: 1;	// bit 1
		volatile uint8_t __unused0	: 6;	// bits 7 downto 2
	};
} DACSR_Register_t;

// Bit fields structure for register DAC0VAL
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DAC0VAL_	: 16;	// bits 15 downto 0
	};
} DAC0VAL_Register_t;

// Bit fields structure for register DAC1VAL
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DAC1VAL_	: 16;	// bits 15 downto 0
	};
} DAC1VAL_Register_t;

// Bit fields structure for register DACFS
typedef union
{
	volatile uint16_t value;
	struct
	{
		volatile uint16_t DACFS_	: 16;	// bits 15 downto 0
	};
} DACFS_Register_t;

// Bit fields structure for register DACHBS
typedef union
{
	volatile uint8_t value;
	struct
	{
		volatile uint8_t DACHBS_	: 8;	// bits 7 downto 0
	};
} DACHBS_Register_t;



// Registers structure for peripheral DAC
typedef struct
{
	volatile DACCR_Register_t	DACCR_;
	volatile uint16_t			__unused0;
	volatile DACSR_Register_t	DACSR_;
	volatile uint8_t			__unused1;
	volatile uint16_t			__unused2;
	volatile DAC0VAL_Register_t	DAC0VAL_;
	volatile uint16_t			__unused3;
	volatile DAC1VAL_Register_t	DAC1VAL_;
	volatile uint16_t			__unused4;
	volatile DACFS_Register_t	DACFS_;
	volatile uint16_t			__unused5;
	volatile DACHBS_Register_t	DACHBS_;
	volatile uint8_t			__unused6;
	volatile uint16_t			__unused7;
	volatile uint32_t			__unused8[58];
} DAC_t;


/********** Peripheral Structure Pointer Macros **********/

#define SYSTEM	((SYSTEM_t *) SYSTEM_BASE)
#define GPIO1	((GPIOx_8bit_t *) GPIO1_BASE)
#define SPI0	((SPIx_t *) SPI0_BASE)
#define SPI1	((SPIx_t *) SPI1_BASE)
#define UART0	((UARTx_t *) UART0_BASE)
#define TIMER0	((TIMERx_t *) TIMER0_BASE)
#define TIMER1	((TIMERx_t *) TIMER1_BASE)
#define GPIO2	((GPIOx_8bit_t *) GPIO2_BASE)
#define GPIO3	((GPIOx_8bit_t *) GPIO3_BASE)
#define GPIO4	((GPIOx_8bit_t *) GPIO4_BASE)
#define GPIO5	((GPIOx_8bit_t *) GPIO5_BASE)
#define I2C0	((I2Cx_t *) I2C0_BASE)
#define SPI2	((SPIx_t *) SPI2_BASE)
#define UART1	((UARTx_t *) UART1_BASE)
#define TIMER2	((TIMERx_t *) TIMER2_BASE)
#define TIMER3	((TIMERx_t *) TIMER3_BASE)
#define NN0		((NNx_t *) NN0_BASE)
#define AFE0	((AFEx_t *) AFE0_BASE)
#define AFE1	((AFEx_t *) AFE1_BASE)
#define AFE2	((AFEx_t *) AFE2_BASE)
#define AFE3	((AFEx_t *) AFE3_BASE)
#define AFE4	((AFEx_t *) AFE4_BASE)
#define AFE5	((AFEx_t *) AFE5_BASE)
#define PCT		((PCT_t *) PCT_BASE)
#define GPIO6	((GPIOx_8bit_t *) GPIO6_BASE)
#define GPIO7	((GPIOx_8bit_t *) GPIO7_BASE)
#define GPIO8	((GPIOx_8bit_t *) GPIO8_BASE)
#define OPA		((OPA_t *) OPA_BASE)
#define DAC		((DAC_t *) DAC_BASE)
#define I2C1	((I2Cx_t *) I2C1_BASE)
#define UART2	((UARTx_t *) UART2_BASE)



/********** GPIO Pins **********/

/** GPIO1 Pins **/
// P1.0 secondary function (when P1SEL(0) = '1'): CS_FLASH
#define CS_FLASH_BIT		(BIT0)
#define CS_FLASH_PxIN		(P1IN)
#define CS_FLASH_PxSEL		(P1SEL)
#define CS_FLASH_PxDIR		(P1DIR)
#define CS_FLASH_PxOUT		(P1OUT)
#define CS_FLASH_PxREN		(P1REN)
#define CS_FLASH_PxIE		(P1IE)
#define CS_FLASH_PxIES		(P1IES)
#define CS_FLASH_PxIFG		(P1IFG)

// P1.1 secondary function (when P1SEL(1) = '1'): MISO0
#define MISO0_BIT			(BIT1)
#define MISO0_PxIN			(P1IN)
#define MISO0_PxSEL			(P1SEL)
#define MISO0_PxDIR			(P1DIR)
#define MISO0_PxOUT			(P1OUT)
#define MISO0_PxREN			(P1REN)
#define MISO0_PxIE			(P1IE)
#define MISO0_PxIES			(P1IES)
#define MISO0_PxIFG			(P1IFG)

// P1.2 secondary function (when P1SEL(2) = '1'): MOSI0
#define MOSI0_BIT			(BIT2)
#define MOSI0_PxIN			(P1IN)
#define MOSI0_PxSEL			(P1SEL)
#define MOSI0_PxDIR			(P1DIR)
#define MOSI0_PxOUT			(P1OUT)
#define MOSI0_PxREN			(P1REN)
#define MOSI0_PxIE			(P1IE)
#define MOSI0_PxIES			(P1IES)
#define MOSI0_PxIFG			(P1IFG)

// P1.3 secondary function (when P1SEL(3) = '1'): SCK0
#define SCK0_BIT			(BIT3)
#define SCK0_PxIN			(P1IN)
#define SCK0_PxSEL			(P1SEL)
#define SCK0_PxDIR			(P1DIR)
#define SCK0_PxOUT			(P1OUT)
#define SCK0_PxREN			(P1REN)
#define SCK0_PxIE			(P1IE)
#define SCK0_PxIES			(P1IES)
#define SCK0_PxIFG			(P1IFG)

// P1.4 secondary function (when P1SEL(4) = '1'): TX0
#define TX0_BIT				(BIT4)
#define TX0_PxIN			(P1IN)
#define TX0_PxSEL			(P1SEL)
#define TX0_PxDIR			(P1DIR)
#define TX0_PxOUT			(P1OUT)
#define TX0_PxREN			(P1REN)
#define TX0_PxIE			(P1IE)
#define TX0_PxIES			(P1IES)
#define TX0_PxIFG			(P1IFG)

// P1.5 secondary function (when P1SEL(5) = '1'): RX0
#define RX0_BIT				(BIT5)
#define RX0_PxIN			(P1IN)
#define RX0_PxSEL			(P1SEL)
#define RX0_PxDIR			(P1DIR)
#define RX0_PxOUT			(P1OUT)
#define RX0_PxREN			(P1REN)
#define RX0_PxIE			(P1IE)
#define RX0_PxIES			(P1IES)
#define RX0_PxIFG			(P1IFG)

// P1.6 secondary function (when P1SEL(6) = '1'): TRAP
#define TRAP_BIT			(BIT6)
#define TRAP_PxIN			(P1IN)
#define TRAP_PxSEL			(P1SEL)
#define TRAP_PxDIR			(P1DIR)
#define TRAP_PxOUT			(P1OUT)
#define TRAP_PxREN			(P1REN)
#define TRAP_PxIE			(P1IE)
#define TRAP_PxIES			(P1IES)
#define TRAP_PxIFG			(P1IFG)

// P1.7 primary function (when P1SEL(7) = '0'): BOOT
#define BOOT_BIT			(BIT7)
#define BOOT_PxIN			(P1IN)
#define BOOT_PxOUT			(P1OUT)
#define BOOT_PxDIR			(P1DIR)
#define BOOT_PxIES			(P1IES)
#define BOOT_PxIFG			(P1IFG)
#define BOOT_PxIE			(P1IE)
#define BOOT_PxSEL			(P1SEL)
#define BOOT_PxREN			(P1REN)



/** GPIO2 Pins **/
// P2.0 secondary function (when P2SEL(0) = '1'): CS1
#define CS1_BIT				(BIT0)
#define CS1_PxIN			(P2IN)
#define CS1_PxSEL			(P2SEL)
#define CS1_PxDIR			(P2DIR)
#define CS1_PxOUT			(P2OUT)
#define CS1_PxREN			(P2REN)
#define CS1_PxIE			(P2IE)
#define CS1_PxIES			(P2IES)
#define CS1_PxIFG			(P2IFG)

// P2.1 secondary function (when P2SEL(1) = '1'): MISO1
#define MISO1_BIT			(BIT1)
#define MISO1_PxIN			(P2IN)
#define MISO1_PxSEL			(P2SEL)
#define MISO1_PxDIR			(P2DIR)
#define MISO1_PxOUT			(P2OUT)
#define MISO1_PxREN			(P2REN)
#define MISO1_PxIE			(P2IE)
#define MISO1_PxIES			(P2IES)
#define MISO1_PxIFG			(P2IFG)

// P2.2 secondary function (when P2SEL(2) = '1'): MOSI1
#define MOSI1_BIT			(BIT2)
#define MOSI1_PxIN			(P2IN)
#define MOSI1_PxSEL			(P2SEL)
#define MOSI1_PxDIR			(P2DIR)
#define MOSI1_PxOUT			(P2OUT)
#define MOSI1_PxREN			(P2REN)
#define MOSI1_PxIE			(P2IE)
#define MOSI1_PxIES			(P2IES)
#define MOSI1_PxIFG			(P2IFG)

// P2.3 secondary function (when P2SEL(3) = '1'): SCK1
#define SCK1_BIT			(BIT3)
#define SCK1_PxIN			(P2IN)
#define SCK1_PxSEL			(P2SEL)
#define SCK1_PxDIR			(P2DIR)
#define SCK1_PxOUT			(P2OUT)
#define SCK1_PxREN			(P2REN)
#define SCK1_PxIE			(P2IE)
#define SCK1_PxIES			(P2IES)
#define SCK1_PxIFG			(P2IFG)

// P2.4 secondary function (when P2SEL(4) = '1'): TX1
#define TX1_BIT				(BIT4)
#define TX1_PxIN			(P2IN)
#define TX1_PxSEL			(P2SEL)
#define TX1_PxDIR			(P2DIR)
#define TX1_PxOUT			(P2OUT)
#define TX1_PxREN			(P2REN)
#define TX1_PxIE			(P2IE)
#define TX1_PxIES			(P2IES)
#define TX1_PxIFG			(P2IFG)

// P2.5 secondary function (when P2SEL(5) = '1'): RX1
#define RX1_BIT				(BIT5)
#define RX1_PxIN			(P2IN)
#define RX1_PxSEL			(P2SEL)
#define RX1_PxDIR			(P2DIR)
#define RX1_PxOUT			(P2OUT)
#define RX1_PxREN			(P2REN)
#define RX1_PxIE			(P2IE)
#define RX1_PxIES			(P2IES)
#define RX1_PxIFG			(P2IFG)

// P2.6 secondary function (when P2SEL(6) = '1'): SDA0
#define SDA0_BIT			(BIT6)
#define SDA0_PxIN			(P2IN)
#define SDA0_PxSEL			(P2SEL)
#define SDA0_PxDIR			(P2DIR)
#define SDA0_PxOUT			(P2OUT)
#define SDA0_PxREN			(P2REN)
#define SDA0_PxIE			(P2IE)
#define SDA0_PxIES			(P2IES)
#define SDA0_PxIFG			(P2IFG)

// P2.7 secondary function (when P2SEL(7) = '1'): SCL0
#define SCL0_BIT			(BIT7)
#define SCL0_PxIN			(P2IN)
#define SCL0_PxSEL			(P2SEL)
#define SCL0_PxDIR			(P2DIR)
#define SCL0_PxOUT			(P2OUT)
#define SCL0_PxREN			(P2REN)
#define SCL0_PxIE			(P2IE)
#define SCL0_PxIES			(P2IES)
#define SCL0_PxIFG			(P2IFG)



/** GPIO3 Pins **/
// P3.0 secondary function (when P3SEL(0) = '1'): CS2
#define CS2_BIT				(BIT0)
#define CS2_PxIN			(P3IN)
#define CS2_PxSEL			(P3SEL)
#define CS2_PxDIR			(P3DIR)
#define CS2_PxOUT			(P3OUT)
#define CS2_PxREN			(P3REN)
#define CS2_PxIE			(P3IE)
#define CS2_PxIES			(P3IES)
#define CS2_PxIFG			(P3IFG)

// P3.1 secondary function (when P3SEL(1) = '1'): MISO2
#define MISO2_BIT			(BIT1)
#define MISO2_PxIN			(P3IN)
#define MISO2_PxSEL			(P3SEL)
#define MISO2_PxDIR			(P3DIR)
#define MISO2_PxOUT			(P3OUT)
#define MISO2_PxREN			(P3REN)
#define MISO2_PxIE			(P3IE)
#define MISO2_PxIES			(P3IES)
#define MISO2_PxIFG			(P3IFG)

// P3.2 secondary function (when P3SEL(2) = '1'): MOSI2
#define MOSI2_BIT			(BIT2)
#define MOSI2_PxIN			(P3IN)
#define MOSI2_PxSEL			(P3SEL)
#define MOSI2_PxDIR			(P3DIR)
#define MOSI2_PxOUT			(P3OUT)
#define MOSI2_PxREN			(P3REN)
#define MOSI2_PxIE			(P3IE)
#define MOSI2_PxIES			(P3IES)
#define MOSI2_PxIFG			(P3IFG)

// P3.3 secondary function (when P3SEL(3) = '1'): SCK2
#define SCK2_BIT			(BIT3)
#define SCK2_PxIN			(P3IN)
#define SCK2_PxSEL			(P3SEL)
#define SCK2_PxDIR			(P3DIR)
#define SCK2_PxOUT			(P3OUT)
#define SCK2_PxREN			(P3REN)
#define SCK2_PxIE			(P3IE)
#define SCK2_PxIES			(P3IES)
#define SCK2_PxIFG			(P3IFG)

// P3.4 secondary function (when P3SEL(4) = '1'): LFXT
#define LFXT_BIT			(BIT4)
#define LFXT_PxIN			(P3IN)
#define LFXT_PxSEL			(P3SEL)
#define LFXT_PxDIR			(P3DIR)
#define LFXT_PxOUT			(P3OUT)
#define LFXT_PxREN			(P3REN)
#define LFXT_PxIE			(P3IE)
#define LFXT_PxIES			(P3IES)
#define LFXT_PxIFG			(P3IFG)

// P3.5 secondary function (when P3SEL(5) = '1'): HFXT
#define HFXT_BIT			(BIT5)
#define HFXT_PxIN			(P3IN)
#define HFXT_PxSEL			(P3SEL)
#define HFXT_PxDIR			(P3DIR)
#define HFXT_PxOUT			(P3OUT)
#define HFXT_PxREN			(P3REN)
#define HFXT_PxIE			(P3IE)
#define HFXT_PxIES			(P3IES)
#define HFXT_PxIFG			(P3IFG)

// P3.6 primary function (when P3SEL(6) = '0'): SH0
#define SH0_BIT				(BIT6)
#define SH0_PxIN			(P3IN)
#define SH0_PxOUT			(P3OUT)
#define SH0_PxDIR			(P3DIR)
#define SH0_PxIES			(P3IES)
#define SH0_PxIFG			(P3IFG)
#define SH0_PxIE			(P3IE)
#define SH0_PxSEL			(P3SEL)
#define SH0_PxREN			(P3REN)

// P3.7 primary function (when P3SEL(7) = '0'): SH1
#define SH1_BIT				(BIT7)
#define SH1_PxIN			(P3IN)
#define SH1_PxOUT			(P3OUT)
#define SH1_PxDIR			(P3DIR)
#define SH1_PxIES			(P3IES)
#define SH1_PxIFG			(P3IFG)
#define SH1_PxIE			(P3IE)
#define SH1_PxSEL			(P3SEL)
#define SH1_PxREN			(P3REN)



/** GPIO4 Pins **/
// P4.0 secondary function (when P4SEL(0) = '1'): T0CMP0
#define T0CMP0_BIT			(BIT0)
#define T0CMP0_PxIN			(P4IN)
#define T0CMP0_PxSEL		(P4SEL)
#define T0CMP0_PxDIR		(P4DIR)
#define T0CMP0_PxOUT		(P4OUT)
#define T0CMP0_PxREN		(P4REN)
#define T0CMP0_PxIE			(P4IE)
#define T0CMP0_PxIES		(P4IES)
#define T0CMP0_PxIFG		(P4IFG)

// P4.1 secondary function (when P4SEL(1) = '1'): T0CMP1
#define T0CMP1_BIT			(BIT1)
#define T0CMP1_PxIN			(P4IN)
#define T0CMP1_PxSEL		(P4SEL)
#define T0CMP1_PxDIR		(P4DIR)
#define T0CMP1_PxOUT		(P4OUT)
#define T0CMP1_PxREN		(P4REN)
#define T0CMP1_PxIE			(P4IE)
#define T0CMP1_PxIES		(P4IES)
#define T0CMP1_PxIFG		(P4IFG)

// P4.2 secondary function (when P4SEL(2) = '1'): T0CAP0
#define T0CAP0_BIT			(BIT2)
#define T0CAP0_PxIN			(P4IN)
#define T0CAP0_PxSEL		(P4SEL)
#define T0CAP0_PxDIR		(P4DIR)
#define T0CAP0_PxOUT		(P4OUT)
#define T0CAP0_PxREN		(P4REN)
#define T0CAP0_PxIE			(P4IE)
#define T0CAP0_PxIES		(P4IES)
#define T0CAP0_PxIFG		(P4IFG)

// P4.3 secondary function (when P4SEL(3) = '1'): DTP0_T0CAP1
#define DTP0_T0CAP1_BIT		(BIT3)
#define DTP0_T0CAP1_PxIN	(P4IN)
#define DTP0_T0CAP1_PxSEL	(P4SEL)
#define DTP0_T0CAP1_PxDIR	(P4DIR)
#define DTP0_T0CAP1_PxOUT	(P4OUT)
#define DTP0_T0CAP1_PxREN	(P4REN)
#define DTP0_T0CAP1_PxIE	(P4IE)
#define DTP0_T0CAP1_PxIES	(P4IES)
#define DTP0_T0CAP1_PxIFG	(P4IFG)

// P4.4 secondary function (when P4SEL(4) = '1'): T1CMP0
#define T1CMP0_BIT			(BIT4)
#define T1CMP0_PxIN			(P4IN)
#define T1CMP0_PxSEL		(P4SEL)
#define T1CMP0_PxDIR		(P4DIR)
#define T1CMP0_PxOUT		(P4OUT)
#define T1CMP0_PxREN		(P4REN)
#define T1CMP0_PxIE			(P4IE)
#define T1CMP0_PxIES		(P4IES)
#define T1CMP0_PxIFG		(P4IFG)

// P4.5 secondary function (when P4SEL(5) = '1'): T1CMP1
#define T1CMP1_BIT			(BIT5)
#define T1CMP1_PxIN			(P4IN)
#define T1CMP1_PxSEL		(P4SEL)
#define T1CMP1_PxDIR		(P4DIR)
#define T1CMP1_PxOUT		(P4OUT)
#define T1CMP1_PxREN		(P4REN)
#define T1CMP1_PxIE			(P4IE)
#define T1CMP1_PxIES		(P4IES)
#define T1CMP1_PxIFG		(P4IFG)

// P4.6 secondary function (when P4SEL(6) = '1'): T1CAP0
#define T1CAP0_BIT			(BIT6)
#define T1CAP0_PxIN			(P4IN)
#define T1CAP0_PxSEL		(P4SEL)
#define T1CAP0_PxDIR		(P4DIR)
#define T1CAP0_PxOUT		(P4OUT)
#define T1CAP0_PxREN		(P4REN)
#define T1CAP0_PxIE			(P4IE)
#define T1CAP0_PxIES		(P4IES)
#define T1CAP0_PxIFG		(P4IFG)

// P4.7 secondary function (when P4SEL(7) = '1'): DTP1_T1CAP1
#define DTP1_T1CAP1_BIT		(BIT7)
#define DTP1_T1CAP1_PxIN	(P4IN)
#define DTP1_T1CAP1_PxSEL	(P4SEL)
#define DTP1_T1CAP1_PxDIR	(P4DIR)
#define DTP1_T1CAP1_PxOUT	(P4OUT)
#define DTP1_T1CAP1_PxREN	(P4REN)
#define DTP1_T1CAP1_PxIE	(P4IE)
#define DTP1_T1CAP1_PxIES	(P4IES)
#define DTP1_T1CAP1_PxIFG	(P4IFG)



/** GPIO5 Pins **/
// P5.0 secondary function (when P5SEL(0) = '1'): PC0
#define PC0_BIT				(BIT0)
#define PC0_PxIN			(P5IN)
#define PC0_PxSEL			(P5SEL)
#define PC0_PxDIR			(P5DIR)
#define PC0_PxOUT			(P5OUT)
#define PC0_PxREN			(P5REN)
#define PC0_PxIE			(P5IE)
#define PC0_PxIES			(P5IES)
#define PC0_PxIFG			(P5IFG)

// P5.1 secondary function (when P5SEL(1) = '1'): PC1
#define PC1_BIT				(BIT1)
#define PC1_PxIN			(P5IN)
#define PC1_PxSEL			(P5SEL)
#define PC1_PxDIR			(P5DIR)
#define PC1_PxOUT			(P5OUT)
#define PC1_PxREN			(P5REN)
#define PC1_PxIE			(P5IE)
#define PC1_PxIES			(P5IES)
#define PC1_PxIFG			(P5IFG)

// P5.2 secondary function (when P5SEL(2) = '1'): PC2
#define PC2_BIT				(BIT2)
#define PC2_PxIN			(P5IN)
#define PC2_PxSEL			(P5SEL)
#define PC2_PxDIR			(P5DIR)
#define PC2_PxOUT			(P5OUT)
#define PC2_PxREN			(P5REN)
#define PC2_PxIE			(P5IE)
#define PC2_PxIES			(P5IES)
#define PC2_PxIFG			(P5IFG)

// P5.3 secondary function (when P5SEL(3) = '1'): PC3
#define PC3_BIT				(BIT3)
#define PC3_PxIN			(P5IN)
#define PC3_PxSEL			(P5SEL)
#define PC3_PxDIR			(P5DIR)
#define PC3_PxOUT			(P5OUT)
#define PC3_PxREN			(P5REN)
#define PC3_PxIE			(P5IE)
#define PC3_PxIES			(P5IES)
#define PC3_PxIFG			(P5IFG)

// P5.6 secondary function (when P5SEL(6) = '1'): DTP2
#define DTP2_BIT			(BIT6)
#define DTP2_PxIN			(P5IN)
#define DTP2_PxSEL			(P5SEL)
#define DTP2_PxDIR			(P5DIR)
#define DTP2_PxOUT			(P5OUT)
#define DTP2_PxREN			(P5REN)
#define DTP2_PxIE			(P5IE)
#define DTP2_PxIES			(P5IES)
#define DTP2_PxIFG			(P5IFG)

// P5.7 secondary function (when P5SEL(7) = '1'): DTP3
#define DTP3_BIT			(BIT7)
#define DTP3_PxIN			(P5IN)
#define DTP3_PxSEL			(P5SEL)
#define DTP3_PxDIR			(P5DIR)
#define DTP3_PxOUT			(P5OUT)
#define DTP3_PxREN			(P5REN)
#define DTP3_PxIE			(P5IE)
#define DTP3_PxIES			(P5IES)
#define DTP3_PxIFG			(P5IFG)



/** GPIO6 Pins **/
// P6.0 secondary function (when P6SEL(0) = '1'): T2CMP0
#define T2CMP0_BIT			(BIT0)
#define T2CMP0_PxIN			(P6IN)
#define T2CMP0_PxSEL		(P6SEL)
#define T2CMP0_PxDIR		(P6DIR)
#define T2CMP0_PxOUT		(P6OUT)
#define T2CMP0_PxREN		(P6REN)
#define T2CMP0_PxIE			(P6IE)
#define T2CMP0_PxIES		(P6IES)
#define T2CMP0_PxIFG		(P6IFG)

// P6.1 secondary function (when P6SEL(1) = '1'): T2CMP1
#define T2CMP1_BIT			(BIT1)
#define T2CMP1_PxIN			(P6IN)
#define T2CMP1_PxSEL		(P6SEL)
#define T2CMP1_PxDIR		(P6DIR)
#define T2CMP1_PxOUT		(P6OUT)
#define T2CMP1_PxREN		(P6REN)
#define T2CMP1_PxIE			(P6IE)
#define T2CMP1_PxIES		(P6IES)
#define T2CMP1_PxIFG		(P6IFG)

// P6.2 secondary function (when P6SEL(2) = '1'): T2CAP0
#define T2CAP0_BIT			(BIT2)
#define T2CAP0_PxIN			(P6IN)
#define T2CAP0_PxSEL		(P6SEL)
#define T2CAP0_PxDIR		(P6DIR)
#define T2CAP0_PxOUT		(P6OUT)
#define T2CAP0_PxREN		(P6REN)
#define T2CAP0_PxIE			(P6IE)
#define T2CAP0_PxIES		(P6IES)
#define T2CAP0_PxIFG		(P6IFG)

// P6.3 secondary function (when P6SEL(3) = '1'): T2CAP1
#define T2CAP1_BIT			(BIT3)
#define T2CAP1_PxIN			(P6IN)
#define T2CAP1_PxSEL		(P6SEL)
#define T2CAP1_PxDIR		(P6DIR)
#define T2CAP1_PxOUT		(P6OUT)
#define T2CAP1_PxREN		(P6REN)
#define T2CAP1_PxIE			(P6IE)
#define T2CAP1_PxIES		(P6IES)
#define T2CAP1_PxIFG		(P6IFG)

// P6.4 secondary function (when P6SEL(4) = '1'): T3CMP0
#define T3CMP0_BIT			(BIT4)
#define T3CMP0_PxIN			(P6IN)
#define T3CMP0_PxSEL		(P6SEL)
#define T3CMP0_PxDIR		(P6DIR)
#define T3CMP0_PxOUT		(P6OUT)
#define T3CMP0_PxREN		(P6REN)
#define T3CMP0_PxIE			(P6IE)
#define T3CMP0_PxIES		(P6IES)
#define T3CMP0_PxIFG		(P6IFG)

// P6.5 secondary function (when P6SEL(5) = '1'): T3CMP1
#define T3CMP1_BIT			(BIT5)
#define T3CMP1_PxIN			(P6IN)
#define T3CMP1_PxSEL		(P6SEL)
#define T3CMP1_PxDIR		(P6DIR)
#define T3CMP1_PxOUT		(P6OUT)
#define T3CMP1_PxREN		(P6REN)
#define T3CMP1_PxIE			(P6IE)
#define T3CMP1_PxIES		(P6IES)
#define T3CMP1_PxIFG		(P6IFG)

// P6.6 secondary function (when P6SEL(6) = '1'): T3CAP0
#define T3CAP0_BIT			(BIT6)
#define T3CAP0_PxIN			(P6IN)
#define T3CAP0_PxSEL		(P6SEL)
#define T3CAP0_PxDIR		(P6DIR)
#define T3CAP0_PxOUT		(P6OUT)
#define T3CAP0_PxREN		(P6REN)
#define T3CAP0_PxIE			(P6IE)
#define T3CAP0_PxIES		(P6IES)
#define T3CAP0_PxIFG		(P6IFG)

// P6.7 secondary function (when P6SEL(7) = '1'): T3CAP1
#define T3CAP1_BIT			(BIT7)
#define T3CAP1_PxIN			(P6IN)
#define T3CAP1_PxSEL		(P6SEL)
#define T3CAP1_PxDIR		(P6DIR)
#define T3CAP1_PxOUT		(P6OUT)
#define T3CAP1_PxREN		(P6REN)
#define T3CAP1_PxIE			(P6IE)
#define T3CAP1_PxIES		(P6IES)
#define T3CAP1_PxIFG		(P6IFG)



/** GPIO7 Pins **/
// P7.0 primary function (when P7SEL(0) = '0'): SL0
#define SL0_BIT				(BIT0)
#define SL0_PxIN			(P7IN)
#define SL0_PxOUT			(P7OUT)
#define SL0_PxDIR			(P7DIR)
#define SL0_PxIES			(P7IES)
#define SL0_PxIFG			(P7IFG)
#define SL0_PxIE			(P7IE)
#define SL0_PxSEL			(P7SEL)
#define SL0_PxREN			(P7REN)

// P7.1 primary function (when P7SEL(1) = '0'): SL1
#define SL1_BIT				(BIT1)
#define SL1_PxIN			(P7IN)
#define SL1_PxOUT			(P7OUT)
#define SL1_PxDIR			(P7DIR)
#define SL1_PxIES			(P7IES)
#define SL1_PxIFG			(P7IFG)
#define SL1_PxIE			(P7IE)
#define SL1_PxSEL			(P7SEL)
#define SL1_PxREN			(P7REN)

// P7.2 secondary function (when P7SEL(2) = '1'): SDA1
#define SDA1_BIT			(BIT2)
#define SDA1_PxIN			(P7IN)
#define SDA1_PxSEL			(P7SEL)
#define SDA1_PxDIR			(P7DIR)
#define SDA1_PxOUT			(P7OUT)
#define SDA1_PxREN			(P7REN)
#define SDA1_PxIE			(P7IE)
#define SDA1_PxIES			(P7IES)
#define SDA1_PxIFG			(P7IFG)

// P7.3 secondary function (when P7SEL(3) = '1'): SCL1
#define SCL1_BIT			(BIT3)
#define SCL1_PxIN			(P7IN)
#define SCL1_PxSEL			(P7SEL)
#define SCL1_PxDIR			(P7DIR)
#define SCL1_PxOUT			(P7OUT)
#define SCL1_PxREN			(P7REN)
#define SCL1_PxIE			(P7IE)
#define SCL1_PxIES			(P7IES)
#define SCL1_PxIFG			(P7IFG)

// P7.4 secondary function (when P7SEL(4) = '1'): TX2
#define TX2_BIT				(BIT4)
#define TX2_PxIN			(P7IN)
#define TX2_PxSEL			(P7SEL)
#define TX2_PxDIR			(P7DIR)
#define TX2_PxOUT			(P7OUT)
#define TX2_PxREN			(P7REN)
#define TX2_PxIE			(P7IE)
#define TX2_PxIES			(P7IES)
#define TX2_PxIFG			(P7IFG)

// P7.5 secondary function (when P7SEL(5) = '1'): RX2
#define RX2_BIT				(BIT5)
#define RX2_PxIN			(P7IN)
#define RX2_PxSEL			(P7SEL)
#define RX2_PxDIR			(P7DIR)
#define RX2_PxOUT			(P7OUT)
#define RX2_PxREN			(P7REN)
#define RX2_PxIE			(P7IE)
#define RX2_PxIES			(P7IES)
#define RX2_PxIFG			(P7IFG)



/** GPIO8 Pins **/


/********** Interrupt Vectors **********/

#define IRQ_SYSTEM_VECTOR			0	// 0x8000
#define IRQ_EBREAK_VECTOR			1	// 0x8004 (called when EBREAK, ECALL, or illegal instruction occurrs)
#define IRQ_BUS_ERROR_VECTOR		2	// 0x8008 (called when an unaligned memory access occurs)
#define IRQ_GPIO1_VECTOR			3	// 0x800C
#define IRQ_SPI0_VECTOR				4	// 0x8010
#define IRQ_SPI1_VECTOR				5	// 0x8014
#define IRQ_UART0_VECTOR			6	// 0x8018
#define IRQ_TIMER0_VECTOR			7	// 0x801C
#define IRQ_TIMER1_VECTOR			8	// 0x8020
#define IRQ_GPIO2_VECTOR			9	// 0x8024
#define IRQ_GPIO3_VECTOR			10	// 0x8028
#define IRQ_GPIO4_VECTOR			11	// 0x802C
#define IRQ_GPIO5_VECTOR			12	// 0x8030
#define IRQ_I2C0_VECTOR				13	// 0x8034
#define IRQ_SPI2_VECTOR				14	// 0x8038
#define IRQ_UART1_VECTOR			15	// 0x803C
#define IRQ_TIMER2_VECTOR			16	// 0x8040
#define IRQ_TIMER3_VECTOR			17	// 0x8044
#define IRQ_NN0_VECTOR				18	// 0x8048
#define IRQ_AFE0_VECTOR				19	// 0x804C
#define IRQ_AFE1_VECTOR				20	// 0x8050
#define IRQ_AFE2_VECTOR				21	// 0x8054
#define IRQ_AFE3_VECTOR				22	// 0x8058
#define IRQ_AFE4_VECTOR				23	// 0x805C
#define IRQ_AFE5_VECTOR				24	// 0x8060
#define IRQ_GPIO6_VECTOR			25	// 0x8064
#define IRQ_GPIO7_VECTOR			26	// 0x8068
#define IRQ_GPIO8_VECTOR			27	// 0x806C
#define IRQ_OPA_VECTOR				28	// 0x8070
#define IRQ_DAC_VECTOR				29	// 0x8074
#define IRQ_I2C1_VECTOR				30	// 0x8078
#define IRQ_UART2_VECTOR			31	// 0x807C



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

#define LAST_POPULATED_IRQ_VECTOR	31



#ifdef __cplusplus
}
#endif	// extern "C"
