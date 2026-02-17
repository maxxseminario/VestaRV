//  Memory Map Constants Header File for Myshkin MCU
//  Maxx Seminario 

#pragma once	// Ensures this file will be included only once per source file

// If using C++, ensure functions have C linkage
#ifdef __cplusplus
extern "C" {
#endif	// extern "C"

/** Includes **/
// #include <stdint.h> 
// #include <bits.h> //custom bit declarations - can put here if troubled. 


/** Defines **/
#define ASIC_NAME	"myshkin"
#define ASIC_DEFINE_myshkin




// /** Memory Mapped Register Macros **/
// #define MMR_8_BIT_MACRO(_address)	(*((volatile uint8_t *) (_address)))
// #define MMR_08_BIT_MACRO(_address)	MMR_8_BIT_MACRO(_address)
// #define MMR_16_BIT_MACRO(_address)	(*((volatile uint16_t *) (_address)))
// #define MMR_32_BIT_MACRO(_address)	(*((volatile uint32_t *) (_address)))
// #define MMR_8_PTR(_peripheralBaseAddress, _registerOffset)	MMR_8_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))
// #define MMR_08_PTR(_peripheralBaseAddress, _registerOffset)	MMR_8_PTR(_peripheralBaseAddress, _registerOffset)
// #define MMR_16_PTR(_peripheralBaseAddress, _registerOffset)	MMR_16_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))
// #define MMR_32_PTR(_peripheralBaseAddress, _registerOffset)	MMR_32_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))


//  ---------- Peripheral Base Addresses ----------
#define PERIPH_GPIO0_BASE       0x4000    
#define PERIPH_GPIO1_BASE       0x4100
#define PERIPH_SPI0_BASE        0x4200
#define PERIPH_SPI1_BASE        0x4300
#define PERIPH_UART0_BASE       0x4400
#define PERIPH_UART1_BASE       0x4500
#define PERIPH_TIMER0_BASE      0x4600
#define PERIPH_TIMER1_BASE      0x4700
#define PERIPH_GPIO2_BASE       0x4800   
#define PERIPH_SYSTEM0_BASE     0x4900
#define PERIPH_NPU0_BASE        0x4A00
#define PERIPH_SARADC0_BASE     0x4B00
#define PERIPH_AFE0_BASE        0x4C00
#define PERIPH_GPIO3_BASE       0x4D00

#define ROM_BASE_ADDR           0x00000
#define IVT_BASE_ADDR           0x08000
#define RAM0_BASE_ADDR          0x08000
#define PROG_BASE_ADDR          0x08200
#define RAM1_BASE_ADDR          0x0C000
#define RAM_END_ADDR            0x0FFFF
#define RAM_SIZE                0x08000  
#define SP_INIT_VAL             0x0FFFC  // Initial Stack Pointer Value (top of RAM)

//  ---------- GPIO Register Offsets ----------
#define GPIO_PxIN               0x00      //  offset = 0 bytes
#define GPIO_PxOUT              0x04      //  offset = 4 bytes
#define GPIO_PxOUTS             0x08      //  offset = 8 bytes
#define GPIO_PxOUTC             0x0C      //  offset = 12 bytes
#define GPIO_PxOUTT             0x10      //  offset = 16 bytes
#define GPIO_PxDIR              0x14      //  offset = 20 bytes
#define GPIO_PxIFG              0x18      //  offset = 24 bytes
#define GPIO_PxIES              0x1C      //  offset = 28 bytes
#define GPIO_PxIE               0x20      //  offset = 32 bytes
#define GPIO_PxSEL              0x24      //  offset = 36 bytes
#define GPIO_PxREN              0x28      //  offset = 40 bytes

//  ---------- SPI Register Offsets ----------
#define SPI_CR                  0x00      //  offset = 0 bytes
#define SPI_SR                  0x04      //  offset = 4 bytes
#define SPI_TX                  0x08      //  offset = 8 bytes
#define SPI_RX                  0x0C      //  offset = 12 bytes
#define SPI_FOS                 0x10      //  offset = 16 bytes TODO: Implement

//  ---------- TIMER Register Offsets ----------
#define TIMER_CR                  0x00      //  offset = 0 bytes
#define TIMER_SR                  0x04      //  offset = 4 bytes
#define TIMER_VAL                 0x08      //  offset = 8 bytes
#define TIMER_CMP0                0x0C      //  offset = 12 bytes
#define TIMER_CMP1                0x10      //  offset = 16 bytes
#define TIMER_CMP2                0x14      //  offset = 20 bytes
#define TIMER_CAP0                0x18      //  offset = 24 bytes
#define TIMER_CAP1                0x1C      //  offset = 28 bytes


//  ---------- UART Register Offsets ----------
#define UART_CR                 0x00      //  offset = 0 bytes
#define UART_SR                 0x04      //  offset = 4 bytes
#define UART_BR                 0x08      //  offset = 8 bytes
#define UART_RX                 0x0C      //  offset = 12 bytes
#define UART_TX                 0x10      //  offset = 16 bytes

//  ---------- SYSTEM Register Offsets ----------
#define SYS_CLK_CR              0x00      //  offset = 0 bytes
#define SYS_CLK_DIV_CR          0x04      //  offset = 4 bytes
#define SYS_BLOCK_PWR           0x08      //  offset = 8 bytes
#define SYS_CRC_DATA            0x0C      //  offset = 12 bytes
#define SYS_CRC_STATE           0x10      //  offset = 16 bytes
#define SYS_IRQ_ENL             0x14      //  offset = 20 bytes
#define SYS_IRQ_ENM             0x18      //  offset = 20 bytes
#define SYS_IRQ_ENH             0x1C      //  offset = 24 bytes
#define SYS_IRQ_PRIL            0x20      //  offset = 28 bytes
#define SYS_IRQ_PRIM            0x24      //  offset = 32 bytes
#define SYS_IRQ_PRIH            0x28      //  offset = 32 bytes
#define SYS_IRQ_CR              0x2C      //  offset = 36 bytes
#define SYS_WDT_PASS            0x30      //  offset = 40 bytes
#define SYS_WDT_CR              0x34      //  offset = 44 bytes
#define SYS_WDT_SR              0x38      //  offset = 48 bytes
#define SYS_WDT_VAL             0x3C      //  offset = 52 bytes
#define SYS_DCO0_BIAS           0x40      //  offset = 64 bytes
#define SYS_DCO1_BIAS           0x44      //  offset = 68 bytes



//  ---------- NPU Register Offsets ----------
#define NPU_CR                  0x00      //  offset = 0 bytes
#define NPU_IVSAR               0x04      //  offset = 4 bytes
#define NPU_WVSAR               0x08      //  offset = 8 bytes
#define NPU_OVSAR               0x0C      //  offset = 12 bytes

//  ---------- AFE Register Offsets ----------
#define AFE_CR                  0x00      //  offset = 0 bytes
#define AFE_TPR                 0x04      //  offset = 4 bytes
#define AFE_SR                  0x08      //  offset = 8 bytes
#define AFE_ADC_VAL             0x0C      //  offset = 12 bytes
#define BIAS_CR                 0x10      //  offset = 16 bytes
#define BIAS_ADJ                0x14      //  offset = 20 bytes
#define BIAS_DBP                0x18      //  offset = 24 bytes
#define BIAS_DBPC               0x1C      //  offset = 28 bytes
#define BIAS_DBNC               0x20      //  offset = 32 bytes
#define BIAS_DBN                0x24      //  offset = 36 bytes
#define BIAS_TC_POT             0x28      //  offset = 40 bytes
#define BIAS_LC_POT             0x2C      //  offset = 44 bytes
#define BIAS_TIA_G_POT          0x30      //  offset = 48 bytes
#define BIAS_DSADC_VCM          0x34      //  offset = 52 bytes
#define BIAS_REV_POT            0x38      //  offset = 56 bytes
#define BIAS_TC_DSADC           0x3C      //  offset = 60 bytes
#define BIAS_LC_DSADC           0x40      //  offset = 64 bytes
#define BIAS_RIN_DSADC          0x44      //  offset = 68 bytes
#define BIAS_RFB_DSADC          0x48      //  offset = 72 bytes

//  ---------- SARADC Register Offsets ----------
#define SARADC_CR               0x00      //  offset = 0 bytes
#define SARADC_CDIV             0x04      //  offset = 4 bytes
#define SARADC_SR               0x08      //  offset = 8 bytes
#define SARADC_DATA             0x0C      //  offset = 12 bytes
#define SARADC_TPR              0x10      //  offset = 16 bytes

//  ---------- UART Register Bit Masks  ----------
// UART Control Register bit masks
#define UCR_EN_MASK          0x20      // Bit 5: UART Enable
#define UCR_PEN_MASK         0x10      // Bit 4: Parity Enable
#define UCR_PSEL_MASK        0x08      // Bit 3: Parity Select
#define UCR_CIE_MASK         0x04      // Bit 2: RX Complete Interrupt Enable
#define UCR_TEIE_MASK        0x02      // Bit 1: TX Empty Interrupt Enable
#define UCR_TCIE_MASK        0x01      // Bit 0: TX Complete Interrupt Enable

// UART Status Register bit masks
#define USR_RX_BUSY_MASK     0x80      // Bit 7: RX Busy Flag
#define USR_TX_BUSY_MASK     0x40      // Bit 6: TX Busy Flag
#define USR_FEF_MASK         0x20      // Bit 5: Framing Error Flag
#define USR_PEF_MASK         0x10      // Bit 4: Parity Error Flag
#define USR_OVF_MASK         0x08      // Bit 3: RX Overflow Flag
#define USR_RCIF_MASK        0x04      // Bit 2: RX Complete Interrupt Flag
#define USR_UTEIF_MASK       0x02      // Bit 1: TX Empty Interrupt Flag
#define USR_UTCIF_MASK       0x01      // Bit 0: TX Complete Interrupt Flag


// ---------- SPI Register Bit Masks  ----------
// SPI Control Register bit masks
#define SPI_FEN_MASK           0x80000  // Bit 19: Flash Enable
#define SPI_MODE_MASK          0x40000  // Bit 18: SPI Mode
#define SPI_TX_SB_MASK         0x20000  // Bit 17: TX Stop Bit
#define SPI_RX_SB_MASK         0x10000  // Bit 16: RX Stop Bit
#define SPI_BR_MASK            0xFF00   // Bits 15-8: Baud Rate
#define SPI_EN_MASK            0x80     // Bit 7: SPI Enable
#define SPI_MSB_MASK           0x40     // Bit 6: MSB First
#define SPI_TCIE_MASK          0x20     // Bit 5: TX Complete Interrupt Enable
#define SPI_TEIE_MASK          0x10     // Bit 4: TX Empty Interrupt Enable
#define SPI_DL_MASK            0x0C     // Bits 3-2: Data Length
#define SPI_CPOL_MASK          0x02     // Bit 1: Clock Polarity
#define SPI_CPHA_MASK          0x01     // Bit 0: Clock Phase



// SPI Status Register bit masks
#define SPI_BUSY_MASK          0x04     // Bit 2: SPI Busy
#define SPI_TCIF_MASK          0x02     // Bit 1: Transmit Complete Interrupt Flag
#define SPI_TXEIF_MASK         0x01     // Bit 0: Transmit Buffer Empty Interrupt Flag

//SPI Control Register (SPIxCR) Bit Masks and Field Definitions
//Register layout (20 bits total):
//Bit 19: SPIFEN - SPI Flash Extended Memory Enable
//Bit 18: SPISM - SPI Slave Mode (not used in this implementation)
//Bit 17: SPITXSB - SPI TX Swap Bytes
//Bit 16: SPIRXSB - SPI RX Swap Bytes
//Bits 15-8: SPIBR - SPI Baud Rate (8 bits)
//Bit 7: SPIEN - SPI Enable
//Bit 6: SPIMSB - SPI MSB First (0=LSB first, 1=MSB first)
//Bit 5: SPITCIE - SPI Transmit Complete Interrupt Enable
//Bit 4: SPITEIE - SPI Transmit Empty Interrupt Enable
//Bits 3-2: SPIDL - SPI Data Length (00=8bit, 01=16bit, 10=32bit, 11=reserved)
//Bit 1: SPICPOL - SPI Clock Polarity
//Bit 0: SPICPHA - SPI Clock Phase

//Individual bit masks
#define SPI_FEN_MASK        0x80000     //Bit 19: Flash Extended Memory Enable
#define SPI_SM_MASK         0x40000     //Bit 18: Slave Mode
#define SPI_TXSB_MASK       0x20000     //Bit 17: TX Swap Bytes
#define SPI_RXSB_MASK       0x10000     //Bit 16: RX Swap Bytes
#define SPI_EN_MASK         0x80        //Bit 7: SPI Enable
#define SPI_MSB_MASK        0x40        //Bit 6: MSB First
#define SPI_TCIE_MASK       0x20        //Bit 5: TX Complete Interrupt Enable
#define SPI_TEIE_MASK       0x10        //Bit 4: TX Empty Interrupt Enable
#define SPI_CPOL_MASK       0x02        //Bit 1: Clock Polarity
#define SPI_CPHA_MASK       0x01        //Bit 0: Clock Phase

//Baud rate field masks (Bits 15-8)
#define SPI_BR_SHIFT        8           //Shift amount for baud rate field
#define SPI_BR_MASK         0xFF00      //Mask for baud rate field
#define SPI_BR(x)           ((x & 0xFF) << SPI_BR_SHIFT)

//Data length field values (Bits 3-2)
#define SPI_DL_SHIFT        2           //Shift amount for data length field
#define SPI_DL_MASK         0x0C        //Mask for data length field
#define SPI_DL_8BIT         0x00        //00 = 8-bit transfers
#define SPI_DL_16BIT        0x04        //01 = 16-bit transfers
#define SPI_DL_32BIT        0x08        //10 = 32-bit transfers
#define SPI_DL_RESERVED     0x0C        //11 = Reserved

//SPI Status Register (SPIxSR) Bit Masks
#define SPI_BUSY_MASK       0x04        //Bit 2: SPI Busy
#define SPI_TCIF_MASK       0x02        //Bit 1: TX Complete Interrupt Flag
#define SPI_TEIF_MASK       0x01        //Bit 0: TX Empty Interrupt Flag

//Common baud rate values
#define SPI_BR_DIV2         0x00        //SMCLK / 2
#define SPI_BR_DIV4         0x01        //SMCLK / 4
#define SPI_BR_DIV8         0x03        //SMCLK / 8
#define SPI_BR_DIV10        0x04        //SMCLK / 10
#define SPI_BR_DIV16        0x07        //SMCLK / 16
#define SPI_BR_DIV32        0x0F        //SMCLK / 32

//Pre-configured SPI modes (CPOL and CPHA combinations)
#define SPI_MODE0           0x00        //CPOL=0, CPHA=0
#define SPI_MODE1           0x01        //CPOL=0, CPHA=1
#define SPI_MODE2           0x02        //CPOL=1, CPHA=0
#define SPI_MODE3           0x03        //CPOL=1, CPHA=1



// ---------- NPU Register Bit Masks  ----------
// NPU Control Register (NPUCR) bit masks
#define NPUBEN_MASK            0x40000  // Bit 18: NPU Bias Enable
#define NPUAEN_MASK            0x20000  // Bit 17: NPU Activation Enable
#define NPUTHINK_MASK          0x10000  // Bit 16: NPU Think (if needed)
#define NPUNI_MASK             0xFF00   // Bits 15-8: Number of Inputs
#define NPUNN_MASK             0x00FF   // Bits 7-0: Number of Neurons

// ---------- TIMER Register Bit Masks  ----------
// Timer Control Register (TIMxCR) bit masks
#define TIMER_CLK_DIV_MASK      0xF0000  // Bits 19-16: Timer Clock Divider
#define TIMER_CMP1_INIT_MASK    0x8000   // Bit 15: Timer Compare 1 Initialize
#define TIMER_CMP0_INIT_MASK    0x4000   // Bit 14: Timer Compare 0 Initialize
#define TIMER_CAP1_EDGE_MASK    0x2000   // Bit 13: Timer Capture 1 Edge
#define TIMER_CAP0_EDGE_MASK    0x1000   // Bit 12: Timer Capture 0 Edge
#define TIMER_CAP1_EN_MASK      0x800    // Bit 11: Timer Capture 1 Enable
#define TIMER_CAP0_EN_MASK      0x400    // Bit 10: Timer Capture 0 Enable
#define TIMER_CLK_SRC_MASK      0x300    // Bits 9-8: Timer Clock Source Select
#define TIMER_CMP2_RESET_MASK   0x80     // Bit 7: Timer Compare 2 Reset
#define TIMER_EN_MASK           0x40     // Bit 6: Timer Enable
#define TIMER_CAP1_IE_MASK      0x20     // Bit 5: Timer Capture 1 Interrupt Enable
#define TIMER_CAP0_IE_MASK      0x10     // Bit 4: Timer Capture 0 Interrupt Enable
#define TIMER_OVF_IE_MASK       0x08     // Bit 3: Timer Overflow Interrupt Enable
#define TIMER_CMP2_IE_MASK      0x04     // Bit 2: Timer Compare 2 Interrupt Enable
#define TIMER_CMP1_IE_MASK      0x02     // Bit 1: Timer Compare 1 Interrupt Enable
#define TIMER_CMP0_IE_MASK      0x01     // Bit 0: Timer Compare 0 Interrupt Enable

// Timer Status Register (TIMxSR) bit masks
#define TIMER_CMP1_OUT_MASK     0x80     // Bit 7: Timer Compare 1 Output
#define TIMER_CMP0_OUT_MASK     0x40     // Bit 6: Timer Compare 0 Output
#define TIMER_CAP1_IF_MASK      0x20     // Bit 5: Timer Capture 1 Interrupt Flag
#define TIMER_CAP0_IF_MASK      0x10     // Bit 4: Timer Capture 0 Interrupt Flag
#define TIMER_OVF_IF_MASK       0x08     // Bit 3: Timer Overflow Interrupt Flag
#define TIMER_CMP2_IF_MASK      0x04     // Bit 2: Timer Compare 2 Interrupt Flag
#define TIMER_CMP1_IF_MASK      0x02     // Bit 1: Timer Compare 1 Interrupt Flag
#define TIMER_CMP0_IF_MASK      0x01     // Bit 0: Timer Compare 0 Interrupt Flag


// -- -------- SYSTEM Register Bit Masks  ----------
// SYSTEM Clock Control Register (SYS_CLK_CR) bit masks
#define SYS_CLK_CR_MASK         (0X1FF)  // 9 bits total
#define SYS_DCO0_ON_MASK       (0x100) // Bit 8: DCO0 Off
#define SYS_DCO1_ON_MASK       (0x80)  // Bit 7: DCO1 Off
#define SYS_CLK_HFXT_OFF_MASK   (0x40)  // Bit 6: High-Frequency Crystal Oscillator Off
#define SYS_CLK_LFXT_OFF_MASK   (0x20)  // Bit 5: Low-Frequency Crystal Oscillator Off
#define SYS_SMCLK_OFF_MASK      (0x10)  // Bit 4: SMCLK Off
#define SYS_SMCLK_SEL_MASK      (0x0C)  // Bit 3-2: SMCLK Source Select
#define SYS_MCLK_SEL_MASK       (0x03)  // Bit 1-0: MCLK Source Select


#define SYS_SMCLKSEL_HFXT       (0x00)  // SMCLK Source Select: HFXT
#define SYS_SMCLKSEL_LFXT       (0x04)  // SMCLK Source Select: LFXT
#define SYS_SMCLKSEL_DCO0       (0x08)  // SMCLK Source Select: DCO0
#define SYS_SMCLKSEL_DCO1       (0x0C)  // SMCLK Source Select: DCO1
#define SYS_MCLKSEL_HFXT        (0x00)  // MCLK Source Select: HFXT
#define SYS_MCLKSEL_SMCLK       (0x01)  // MCLK Source Select: SMCLK
#define SYS_MCLKSEL_DCO0        (0x02)  // MCLK Source Select: DCO0
#define SYS_MCLKSEL_DCO1        (0x03)  // MCLK Source Select: DCO1

// SYSTEM Clock Divider Control Register (SYS_CLK_DIV_CR) bit masks
#define SYS_CLK_DIV_CR_MASK     (0x3F)  // 6 bits total
#define SYS_SMCLK_DIV_MASK      (0x38)  // Bits 5-3: SMCLK Divider
#define SYS_MCLK_DIV_MASK       (0x07)  // Bits 2-0: MCLK Divider

// SYSTEM Block Power Register (SYS_BLOCK_PWR) bit masks
#define SYS_BLOCK_PWR_MASK      (0x07)  // 3 bits total
#define SYS_RAM_OFF_MASK        (0x06)  // Bits 2-1: RAM Power Off
#define SYS_RAM1_OFF_MASK       (0x04)  // Bit 2: RAM1 Power Off
#define SYS_RAM0_OFF_MASK       (0x02)  // Bit 1: RAM0 Power Off
#define SYS_ROM_OFF_MASK        (0x01)  // Bit 0: ROM Power Off

// SYSTEM Watchdog Control Register (SYS_WDT_CR) bit masks
#define SYS_WDT_CR_MASK         (0xFF)  // 8 bits total
#define SYS_WDT_EN_MASK         (0x80)  // Bit 7: Watchdog Enable
#define SYS_WDT_CDIV_MASK       (0x7C)  // Bits 6-2: Watchdog Clock Divider
#define SYS_WDT_IE_MASK         (0x02)  // Bit 1: Watchdog Interrupt Enable
#define SYS_WDT_HWRST_MASK      (0x01)  // Bit 0: Watchdog Hardware Reset

// SYSTEM Watchdog Status Register (SYS_WDT_SR) bit masks
#define SYS_WDT_SR_MASK         (0x03)  // 2 bits total
#define SYS_WDT_RF_MASK         (0x01)  // Bit 0: Watchdog Reset Flag
#define SYS_WDT_IF_MASK         (0x02)  // Bit 1: Watchdog Interrupt Flag

// SYSTEM IRQ Control Register (SYS_IRQ_CR) bit masks
#define SYS_IRQ_RCEN_MASK       (0x02)  // Bit 1: IRQ Recursion Enable
#define SYS_IRQ_GEN_MASK        (0x01)  // Bit 0: Global Enable IRQ

// DCO BIAS Registers
#define DCO_BIAS_MASK           (0xFFF)  // 12 bits

#define DCO0_BIAS_DEFAULT    (0x0600)  // Default DCO0 Bias
#define DCO1_BIAS_DEFAULT    (0x0600)  // Default DCO1 Bias


// SYSTEM Peripheral Passwords
#define WDT_UNLCK_PASSWD  (0x5f3759df)
#define WDT_CLR_PASSWD    (0xA0C8A620)



//=============================================================================
// SARADC Bits
//=============================================================================
//# Bit masks for register fields
#define SARADC_CR_MASK          0x000001FF  // 9 bits
#define SARADC_SR_MASK          0x0000000F  // 4 bits
#define SARADC_DATA_MASK        0x000003FF  // 10 bits
#define SARADC_TPR_MASK         0x000000FF  // 8 bits

// SARADC_CR bit positions
#define ADC_RESET_BIT           0x00000001  // Bit 0
#define ADC_SAMPLE_STEP_MASK    0x0000001E  // Bits 4:1
#define ADC_EN_BIT              0x00000020  // Bit 5
#define DEBUG_MODE_BIT          0x00000040  // Bit 6
#define ADC_DATA_VALID_IE_BIT   0x00000080  // Bit 7
#define ADC_CONT_MEAS_BIT       0x00000100  // Bit 8

// SARADC_SR bit positions
#define CONV_BUSY_BIT           0x00000001  // Bit 0
#define DATA_VALID_BIT          0x00000002  // Bit 1
#define ADC_OVF_IF_BIT          0x00000004  // Bit 2
#define ADC_READY_BIT           0x00000008  // Bit 3







//=============================================================================
// GPIO0 Pin Assignments
//=============================================================================
#define GPIO0_CS_PIN           0x00     // P1.0 - SPI Flash Chip Select
#define GPIO0_MISO_PIN         0x01     // P1.1 - SPI Master In Slave Out
#define GPIO0_MOSI_PIN         0x02     // P1.2 - SPI Master Out Slave In
#define GPIO0_SCK_PIN          0x03     // P1.3 - SPI Serial Clock
#define GPIO0_LFXT_PIN         0x04     // P1.4 - Low Frequency Crystal
#define GPIO0_HFXT_PIN         0x05     // P1.5 - High Frequency Crystal
#define GPIO0_TRAP_PIN         0x06     // P1.6 - TRAP Pin (Active Low)
#define GPIO0_BOOT_PIN         0x07     // P1.7 - BOOT Mode Pin (Active Low)

// GPIO0 Pin Masks
#define GPIO0_CS_MASK          0x01     // P1.0 - SPI Flash Chip Select
#define GPIO0_MISO_MASK        0x02     // P1.1 - SPI Master In Slave Out
#define GPIO0_MOSI_MASK        0x04     // P1.2 - SPI Master Out Slave In
#define GPIO0_SCK_MASK         0x08     // P1.3 - SPI Serial Clock
#define GPIO0_LFXT_MASK        0x10     // P1.4 - Low Frequency Crystal
#define GPIO0_HFXT_MASK        0x20     // P1.5 - High Frequency Crystal
#define GPIO0_TRAP_MASK        0x40     // P1.6 - TRAP Pin (Active Low)
#define GPIO0_BOOT_MASK        0x80     // P1.7 - BOOT Mode Pin (Active Low)

//=============================================================================
// GPIO1 Pin Assignments
//=============================================================================
#define GPIO1_CS1_PIN          0x00     // P2.0 - SPI1 Chip Select
#define GPIO1_MISO1_PIN        0x01     // P2.1 - SPI1 Master In Slave Out
#define GPIO1_MOSI1_PIN        0x02     // P2.2 - SPI1 Master Out Slave In
#define GPIO1_SCK1_PIN         0x03     // P2.3 - SPI1 Serial Clock
#define GPIO1_UART0_TX_PIN     0x04     // P2.4 - UART0 Transmit
#define GPIO1_UART0_RX_PIN     0x05     // P2.5 - UART0 Receive
#define GPIO1_UART1_TX_PIN     0x06     // P2.6 - UART1 Transmit
#define GPIO1_UART1_RX_PIN     0x07     // P2.7 - UART1 Receive

// GPIO1 Pin Masks
#define GPIO1_CS1_MASK         0x01     // P2.0 - SPI1 Chip Select
#define GPIO1_MISO1_MASK       0x02     // P2.1 - SPI1 Master In Slave Out
#define GPIO1_MOSI1_MASK       0x04     // P2.2 - SPI1 Master Out Slave In
#define GPIO1_SCK1_MASK        0x08     // P2.3 - SPI1 Serial Clock
#define GPIO1_UART0_TX_MASK    0x10     // P2.4 - UART0 Transmit
#define GPIO1_UART0_RX_MASK    0x20     // P2.5 - UART0 Receive
#define GPIO1_UART1_TX_MASK    0x40     // P2.6 - UART1 Transmit
#define GPIO1_UART1_RX_MASK    0x80     // P2.7 - UART1 Receive

//=============================================================================
// GPIO2 Pin Assignments (TIMER0, TIMER1)
//=============================================================================
#define GPIO2_T0_CMP0_PIN      0x00     // P3.0 - Timer 0 Compare 0
#define GPIO2_T0_CMP1_PIN      0x01     // P3.1 - Timer 0 Compare 1
#define GPIO2_T0_CAP0_PIN      0x02     // P3.2 - Timer 0 Capture 0
#define GPIO2_T0_CAP1_PIN      0x03     // P3.3 - Timer 0 Capture 1
#define GPIO2_T1_CMP0_PIN      0x04     // P3.4 - Timer 1 Compare 0
#define GPIO2_T1_CMP1_PIN      0x05     // P3.5 - Timer 1 Compare 1
#define GPIO2_T1_CAP0_PIN      0x06     // P3.6 - Timer 1 Capture 0
#define GPIO2_T1_CAP1_PIN      0x07     // P3.7 - Timer 1 Capture 1

// GPIO2 Pin Masks
#define GPIO2_T0_CMP0_MASK     0x01     // P3.0 - Timer 0 Compare 0
#define GPIO2_T0_CMP1_MASK     0x02     // P3.1 - Timer 0 Compare 1
#define GPIO2_T0_CAP0_MASK     0x04     // P3.2 - Timer 0 Capture 0
#define GPIO2_T0_CAP1_MASK     0x08     // P3.3 - Timer 0 Capture 1
#define GPIO2_T1_CMP0_MASK     0x10     // P3.4 - Timer 1 Compare 0
#define GPIO2_T1_CMP1_MASK     0x20     // P3.5 - Timer 1 Compare 1
#define GPIO2_T1_CAP0_MASK     0x40     // P3.6 - Timer 1 Capture 0
#define GPIO2_T1_CAP1_MASK     0x80     // P3.7 - Timer 1 Capture 1


// Word 0 (Bits 0-31)
#define IRQB_SYS_WDT      0x00000001  // 0:  Watchdog Timer Interrupt IVT address = 0xA000
#define IRQB_GPIO0_B0     0x00000002  // 1:  GPIO0 Bit 0 Interrupt IVT address = 0xA004
#define IRQB_GPIO0_B1     0x00000004  // 2:  GPIO0 Bit 1 Interrupt IVT address = 0xA008
#define IRQB_GPIO0_B2     0x00000008  // 3:  GPIO0 Bit 2 Interrupt IVT address = 0xA00C
#define IRQB_GPIO0_B3     0x00000010  // 4:  GPIO0 Bit 3 Interrupt IVT address = 0xA010
#define IRQB_GPIO0_B4     0x00000020  // 5:  GPIO0 Bit 4 Interrupt IVT address = 0xA014
#define IRQB_GPIO0_B5     0x00000040  // 6:  GPIO0 Bit 5 Interrupt IVT address = 0xA018
#define IRQB_GPIO0_B6     0x00000080  // 7:  GPIO0 Bit 6 Interrupt IVT address = 0xA01C
#define IRQB_GPIO0_B7     0x00000100  // 8:  GPIO0 Bit 7 Interrupt IVT address = 0xA020
#define IRQB_SPI0_TC      0x00000200  // 9:  SPI0 Transmission Complete Interrupt IVT address = 0xA024
#define IRQB_SPI0_TE      0x00000400  // 10: SPI0 Transmission Buffer Empty Interrupt IVT address = 0xA028
#define IRQB_SPI1_TC      0x00000800  // 11: SPI1 Transmission Complete Interrupt IVT address = 0xA02C
#define IRQB_SPI1_TE      0x00001000  // 12: SPI1 Transmission Buffer Empty Interrupt IVT address = 0xA030
#define IRQB_UART0_RC     0x00002000  // 13: UART0 Receive Complete Interrupt IVT address = 0xA034
#define IRQB_UART0_TE     0x00004000  // 14: UART0 Transmission Buffer Empty Interrupt IVT address = 0xA038
#define IRQB_UART0_TC     0x00008000  // 15: UART0 Transmission Complete Interrupt IVT address = 0xA03C
#define IRQB_TIM0_CAP0    0x00010000  // 16: TIMER0 Capture 0 Interrupt IVT address = 0xA040
#define IRQB_TIM0_CAP1    0x00020000  // 17: TIMER0 Capture 1 Interrupt IVT address = 0xA044
#define IRQB_TIM0_OVF     0x00040000  // 18: TIMER0 Overflow Interrupt IVT address = 0xA048
#define IRQB_TIM0_CMP0    0x00080000  // 19: TIMER0 Compare 0 Interrupt IVT address = 0xA04C
#define IRQB_TIM0_CMP1    0x00100000  // 20: TIMER0 Compare 1 Interrupt IVT address = 0xA050
#define IRQB_TIM0_CMP2    0x00200000  // 21: TIMER0 Compare 2 Interrupt IVT address = 0xA054
#define IRQB_TIM1_CAP0    0x00400000  // 22: TIMER1 Capture 0 Interrupt IVT address = 0xA058
#define IRQB_TIM1_CAP1    0x00800000  // 23: TIMER1 Capture 1 Interrupt IVT address = 0xA05C
#define IRQB_TIM1_OVF     0x01000000  // 24: TIMER1 Overflow Interrupt IVT address = 0xA060
#define IRQB_TIM1_CMP0    0x02000000  // 25: TIMER1 Compare 0 Interrupt IVT address = 0xA064
#define IRQB_TIM1_CMP1    0x04000000  // 26: TIMER1 Compare 1 Interrupt IVT address = 0xA068
#define IRQB_TIM1_CMP2    0x08000000  // 27: TIMER1 Compare 2 Interrupt IVT address = 0xA06C
#define IRQB_GPIO1_B0     0x10000000  // 28: GPIO1 Bit 0 Interrupt IVT address = 0xA070
#define IRQB_GPIO1_B1     0x20000000  // 29: GPIO1 Bit 1 Interrupt IVT address = 0xA074
#define IRQB_GPIO1_B2     0x40000000  // 30: GPIO1 Bit 2 Interrupt IVT address = 0xA078
#define IRQB_GPIO1_B3     0x80000000  // 31: GPIO1 Bit 3 Interrupt IVT address = 0xA07C

// Word 1 (Bits 32-63)
#define IRQB_GPIO1_B4     0x00000001  // 32: GPIO1 Bit 4 Interrupt IVT address = 0xA080
#define IRQB_GPIO1_B5     0x00000002  // 33: GPIO1 Bit 5 Interrupt IVT address = 0xA084
#define IRQB_GPIO1_B6     0x00000004  // 34: GPIO1 Bit 6 Interrupt IVT address = 0xA088
#define IRQB_GPIO1_B7     0x00000008  // 35: GPIO1 Bit 7 Interrupt IVT address = 0xA08C
#define IRQB_GPIO2_B0     0x00000010  // 36: GPIO2 Bit 0 Interrupt IVT address = 0xA090
#define IRQB_GPIO2_B1     0x00000020  // 37: GPIO2 Bit 1 Interrupt IVT address = 0xA094
#define IRQB_GPIO2_B2     0x00000040  // 38: GPIO2 Bit 2 Interrupt IVT address = 0xA098
#define IRQB_GPIO2_B3     0x00000080  // 39: GPIO2 Bit 3 Interrupt IVT address = 0xA09C
#define IRQB_GPIO2_B4     0x00000100  // 40: GPIO2 Bit 4 Interrupt IVT address = 0xA0A0
#define IRQB_GPIO2_B5     0x00000200  // 41: GPIO2 Bit 5 Interrupt IVT address = 0xA0A4
#define IRQB_GPIO2_B6     0x00000400  // 42: GPIO2 Bit 6 Interrupt IVT address = 0xA0A8
#define IRQB_GPIO2_B7     0x00000800  // 43: GPIO2 Bit 7 Interrupt IVT address = 0xA0AC
#define IRQB_GPIO3_B0     0x00001000  // 44: GPIO3 Bit 0 Interrupt IVT address = 0xA0B0
#define IRQB_GPIO3_B1     0x00002000  // 45: GPIO3 Bit 1 Interrupt IVT address = 0xA0B4
#define IRQB_GPIO3_B2     0x00004000  // 46: GPIO3 Bit 2 Interrupt IVT address = 0xA0B8
#define IRQB_GPIO3_B3     0x00008000  // 47: GPIO3 Bit 3 Interrupt IVT address = 0xA0BC
#define IRQB_GPIO3_B4     0x00010000  // 48: GPIO3 Bit 4 Interrupt IVT address = 0xA0C0
#define IRQB_GPIO3_B5     0x00020000  // 49: GPIO3 Bit 5 Interrupt IVT address = 0xA0C4
#define IRQB_GPIO3_B6     0x00040000  // 50: GPIO3 Bit 6 Interrupt IVT address = 0xA0C8
#define IRQB_GPIO3_B7     0x00080000  // 51: GPIO3 Bit 7 Interrupt IVT address = 0xA0CC
#define IRQB_UART1_RC     0x00100000  // 52: UART1 Receive Complete Interrupt IVT address = 0xA0D0
#define IRQB_UART1_TE     0x00200000  // 53: UART1 Transmission Buffer Empty Interrupt IVT address = 0xA0D4
#define IRQB_UART1_TC     0x00400000  // 54: UART1 Transmission Complete Interrupt IVT address = 0xA0D8
#define IRQB_AFE0_RC      0x00800000  // 55: AFE0 Receive Complete Interrupt IVT address = 0xA0DC
#define IRQB_SAR0_RC      0x01000000  // 56: SARADC0 Conversion Complete Interrupt IVT address = 0xA0E0
#define IRQB_I2C0_STR     0x02000000  // 57: I2C0 start received IVT address = 0xA0E4
#define IRQB_I2C0_SPR     0x04000000  // 58: I2C0 Stop Received Interrupt IVT address = 0xA0E8
#define IRQB_I2C0_MSTS    0x08000000  // 59: I2C0 master mode start condition sent Interrupt IVT address = 0xA0EC
#define IRQB_I2C0_MSPS    0x10000000  // 60: I2C0 master mode stop condition sent Interrupt IVT address = 0xA0F0
#define IRQB_I2C0_MARB    0x20000000  // 61: I2C0 Master Arbitration Lost Interrupt IVT address = 0xA0F4
#define IRQB_I2C0_MTXE    0x40000000  // 62: I2C0 Master Transmit Empty Interrupt IVT address = 0xA0F8
#define IRQB_I2C0_MNR     0x80000000  // 63: I2C0 master mode NACK received Interrupt IVT address = 0xA0FC

// Word 2 (Bits 64-82)
#define IRQB_I2C0_MXC     0x00000001  // 64: I2C0 Master Transfer Complete Interrupt IVT address = 0xA100
#define IRQB_I2C0_SA      0x00000002  // 65: I2C0 Slave Address Interrupt IVT address = 0xA104
#define IRQB_I2C0_STXE    0x00000004  // 66: I2C0 Slave Transmit Empty Interrupt IVT address = 0xA108
#define IRQB_I2C0_SOVF    0x00000008  // 67: I2C0 Slave Overflow Interrupt IVT address = 0xA10C
#define IRQB_I2C0_SNR     0x00000010  // 68: I2C0 slave mode NACK received Interrupt IVT address = 0xA110
#define IRQB_I2C0_SXC     0x00000020  // 69: I2C0 Slave Transfer Complete Interrupt IVT address = 0xA114
#define IRQB_I2C1_STR     0x00000040  // 70: I2C1 start received IVT address = 0xA118
#define IRQB_I2C1_SPR     0x00000080  // 71: I2C1 Stop Received Interrupt IVT address = 0xA11C
#define IRQB_I2C1_MSTS    0x00000100  // 72: I2C1 master mode start condition sent Interrupt IVT address = 0xA120
#define IRQB_I2C1_MSPS    0x00000200  // 73: I2C1 master mode stop condition sent Interrupt IVT address = 0xA124
#define IRQB_I2C1_MARB    0x00000400  // 74: I2C1 master mode arbitration lost Interrupt IVT address = 0xA128
#define IRQB_I2C1_MTXE    0x00000800  // 75: I2C1 master mode transmit empty Interrupt IVT address = 0xA12C
#define IRQB_I2C1_MNR     0x00001000  // 76: I2C1 master mode NACK received Interrupt IVT address = 0xA130
#define IRQB_I2C1_MXC     0x00002000  // 77: I2C1 master mode transfer complete Interrupt IVT address = 0xA134
#define IRQB_I2C1_SA      0x00004000  // 78: I2C1 Slave Address Interrupt IVT address = 0xA138
#define IRQB_I2C1_STXE    0x00008000  // 79: I2C1 Slave Transmit Empty Interrupt IVT address = 0xA13C
#define IRQB_I2C1_SOVF    0x00010000  // 80: I2C1 Slave Overflow Interrupt IVT address = 0xA140
#define IRQB_I2C1_SNR     0x00020000  // 81: I2C1 slave mode NACK received Interrupt IVT address = 0xA144
#define IRQB_I2C1_SXC     0x00040000  // 82: I2C1 Slave Transfer Complete Interrupt IVT address = 0xA148




#define IRQBS_SPI0_MASK    (IRQB_SPI0_TC | IRQB_SPI0_TE)
#define IRQBS_SPI1_MASK    (IRQB_SPI1_TC | IRQB_SPI1_TE)
#define IRQBS_GPIO0_MASK   (IRQB_GPIO0_B0 | IRQB_GPIO0_B1 | IRQB_GPIO0_B2 | IRQB_GPIO0_B3 | IRQB_GPIO0_B4 | IRQB_GPIO0_B5 | IRQB_GPIO0_B6 | IRQB_GPIO0_B7)
#define IRQBS_SPI0_MASK    (IRQB_SPI0_TC | IRQB_SPI0_TE)
#define IRQBS_SPI1_MASK    (IRQB_SPI1_TC | IRQB_SPI1_TE)
#define IRQBS_UART0_MASK   (IRQB_UART0_RC | IRQB_UART0_TE | IRQB_UART0_TC)
#define IRQBS_TIM0_MASK    (IRQB_TIM0_CAP0 | IRQB_TIM0_CAP1 | IRQB_TIM0_OVF | IRQB_TIM0_CMP0 | IRQB_TIM0_CMP1 | IRQB_TIM0_CMP2)
#define IRQBS_TIM1_MASK    (IRQB_TIM1_CAP0 | IRQB_TIM1_CAP1 | IRQB_TIM1_OVF | IRQB_TIM1_CMP0 | IRQB_TIM1_CMP1 | IRQB_TIM1_CMP2)
#define IRQBS_GPIO1_MASK   (IRQB_GPIO1_B0 | IRQB_GPIO1_B1 | IRQB_GPIO1_B2 | IRQB_GPIO1_B3 | IRQB_GPIO1_B4 | IRQB_GPIO1_B5 | IRQB_GPIO1_B6 | IRQB_GPIO1_B7)
#define IRQBS_GPIO2_MASK   (IRQB_GPIO2_B0 | IRQB_GPIO2_B1 | IRQB_GPIO2_B2 | IRQB_GPIO2_B3 | IRQB_GPIO2_B4 | IRQB_GPIO2_B5 | IRQB_GPIO2_B6 | IRQB_GPIO2_B7)
#define IRQBS_GPIO3_MASK   (IRQB_GPIO3_B0 | IRQB_GPIO3_B1 | IRQB_GPIO3_B2 | IRQB_GPIO3_B3 | IRQB_GPIO3_B4 | IRQB_GPIO3_B5 | IRQB_GPIO3_B6 | IRQB_GPIO3_B7)
#define IRQBS_UART1_MASK   (IRQB_UART1_RC | IRQB_UART1_TE | IRQB_UART1_TC)
#define IRQBS_AFE0_MASK    (IRQB_AFE0_RC | IRQB_AFE0_OVF | IRQB_AFE0_ERR)
#define IRQBS_SAR0_MASK    (IRQB_SAR0_RC | IRQB_SAR0_OVF)


// Boot Mode Definitions
// #define SP_INIT        (RAM0_BASE_ADDR + RAM_SIZE - 4) // Initial Stack Pointer to top of RAM

// Forth Interpreter Transition Macros ------------------------------------

// These are to translate from myshkin nomenclature to washakie nomenclature for drag and drop compatibility with forth interpreter files


// // rv4th.c level --------------------------------------------------------------

// #define MEMPWRCR_ADDRESS	(PERIPH_SYSTEM0_BASE + SYS_BLOCK_PWR)
// #define MEMPWRCR			MMR_16_BIT_MACRO(MEMPWRCR_ADDRESS)
// #define TIM0CR_ADDRESS		(PERIPH_TIMER0_BASE + TIMER_CR)
// #define TIM0CR				MMR_32_BIT_MACRO(TIM0CR_ADDRESS)
// #define TIM1CR_ADDRESS		(PERIPH_TIMER1_BASE + TIMER_CR)
// #define TIM1CR				MMR_32_BIT_MACRO(TIM1CR_ADDRESS)
// #define CRCSTATE_ADDRESS	(PERIPH_SYSTEM0_BASE + SYS_CRC_STATE)
// #define CRCSTATE			MMR_16_BIT_MACRO(CRCSTATE_ADDRESS)
// #define CRCDATA_ADDRESS		(PERIPH_SYSTEM0_BASE + SYS_CRC_DATA)
// #define CRCDATA				MMR_08_BIT_MACRO(CRCDATA_ADDRESS)

// // uart.h level -------------------------------------------------------------


// /** UARTx **/
// // UARTxCR
// #define UARTxCR_OFFSET				(0)
// #define UARTxCR_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxCR_OFFSET)

// #define UEN		    UCR_EN_MASK	// bit 5
// #define UEN_LSB		(5)
// #define UPEN		UCR_PEN_MASK	// bit 4
// #define UPEN_LSB	(4)
// #define UPODD		UCR_PSEL_MASK	// bit 3
// #define UPODD_LSB	(3)
// #define URCIE		UCR_CIE_MASK	// bit 2
// #define URCIE_LSB	(2)
// #define UTEIE		UCR_TEIE_MASK	// bit 1
// #define UTEIE_LSB	(1)
// #define UTCIE		UCR_TCIE_MASK	// bit 0
// #define UTCIE_LSB	(0)

// // UARTxSR
// #define UARTxSR_OFFSET				(4)
// #define UARTxSR_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxSR_OFFSET)

// #define URBF		USR_RX_BUSY_MASK	// bit 7
// #define URBF_LSB	(7)
// #define UTBF		USR_TX_BUSY_MASK	// bit 6
// #define UTBF_LSB	(6)
// #define UFEF		USR_FEF_MASK	// bit 5
// #define UFEF_LSB	(5)
// #define UPEF		USR_PEF_MASK	// bit 4
// #define UPEF_LSB	(4)
// #define UOVF		USR_OVF_MASK	// bit 3
// #define UOVF_LSB	(3)
// #define URCIF		USR_RCIF_MASK	// bit 2
// #define URCIF_LSB	(2)
// #define UTEIF		USR_UTEIF_MASK	// bit 1
// #define UTEIF_LSB	(1)
// #define UTCIF		USR_UTCIF_MASK	// bit 0
// #define UTCIF_LSB	(0)

// // UARTxBR
// #define UARTxBR_OFFSET				(8)
// #define UARTxBR_PTR(_UARTx_BASE)	MMR_16_PTR(_UARTx_BASE, UARTxBR_OFFSET)

// #define UBR_MASK	(0x0FFF)	// bits 11 downto 0
// #define UBR_LSB		(0)

// // UARTxRX
// #define UARTxRX_OFFSET				(12)
// #define UARTxRX_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxRX_OFFSET)

// // UARTxTX
// #define UARTxTX_OFFSET				(16)
// #define UARTxTX_PTR(_UARTx_BASE)	MMR_08_PTR(_UARTx_BASE, UARTxTX_OFFSET)




// /** Peripheral UARTx **/
// // Bit fields structure for register UARTxCR
// // With washakie nomenclature (defining UARTx_t structure)
// typedef union
// {
// 	volatile uint8_t value;
// 	struct
// 	{
// 		volatile uint8_t TCIE		: 1;	// bit 0
// 		volatile uint8_t TEIE		: 1;	// bit 1
// 		volatile uint8_t RCIE		: 1;	// bit 2
// 		volatile uint8_t PODD		: 1;	// bit 3
// 		volatile uint8_t PEN		: 1;	// bit 4
// 		volatile uint8_t EN			: 1;	// bit 5
// 		volatile uint8_t __unused0	: 2;	// bits 7 downto 6
// 	};
// } UARTxCR_Register_t;

// // Bit fields structure for register UARTxSR
// typedef union
// {
// 	volatile uint8_t value;
// 	struct
// 	{
// 		volatile uint8_t TCIF	: 1;	// bit 0
// 		volatile uint8_t TEIF	: 1;	// bit 1
// 		volatile uint8_t RCIF	: 1;	// bit 2
// 		volatile uint8_t OVF	: 1;	// bit 3
// 		volatile uint8_t PEF	: 1;	// bit 4
// 		volatile uint8_t FEF	: 1;	// bit 5
// 		volatile uint8_t TBF	: 1;	// bit 6
// 		volatile uint8_t RBF	: 1;	// bit 7
// 	};
// } UARTxSR_Register_t;

// // Bit fields structure for register UARTxBR
// typedef union
// {
// 	volatile uint16_t value;
// 	struct
// 	{
// 		volatile uint16_t BR		: 12;	// bits 11 downto 0
// 		volatile uint16_t __unused0	: 4;	// bits 15 downto 12
// 	};
// } UARTxBR_Register_t;

// // Bit fields structure for register UARTxRX
// typedef union
// {
// 	volatile uint8_t value;
// 	struct
// 	{
// 		volatile uint8_t RX	: 8;	// bits 7 downto 0
// 	};
// } UARTxRX_Register_t;

// // Bit fields structure for register UARTxTX
// typedef union
// {
// 	volatile uint8_t value;
// 	struct
// 	{
// 		volatile uint8_t TX	: 8;	// bits 7 downto 0
// 	};
// } UARTxTX_Register_t;



// // Registers structure for peripheral UARTx
// typedef struct
// {
// 	volatile UARTxCR_Register_t	CR;
// 	volatile uint8_t			__unused0;
// 	volatile uint16_t			__unused1;
// 	volatile UARTxSR_Register_t	SR;
// 	volatile uint8_t			__unused2;
// 	volatile uint16_t			__unused3;
// 	volatile UARTxBR_Register_t	BR;
// 	volatile uint16_t			__unused4;
// 	volatile UARTxRX_Register_t	RX;
// 	volatile uint8_t			__unused5;
// 	volatile uint16_t			__unused6;
// 	volatile UARTxTX_Register_t	TX;
// 	volatile uint8_t			__unused7;
// 	volatile uint16_t			__unused8;
// 	volatile uint32_t			__unused9[59];
// } UARTx_t;
// #define UARTx_PTR(_UARTx_BASE)	((UARTx_t *) _UARTx_BASE)


// // -- spi.h level and spi.c level-------------------------------------------------------------

// // Translation between myshkin and washakie nomenclature for drag and drop compatibility with forth interpreter files

// // SPIxCR
// #define SPIFEN		(0x00080000)	// bit 19
// #define SPIFEN_LSB	(19)
// #define SPISM		SPI_MODE_MASK	// bit 18
// #define SPISM_LSB	(18)
// #define SPITXSB		SPI_TX_SB_MASK	// bit 17
// #define SPITXSB_LSB	(17)
// #define SPIRXSB		SPI_RX_SB_MASK	// bit 16
// #define SPIRXSB_LSB	(16)
// #define SPIBR_MASK	SPI_BR_MASK	// bits 15 downto 8
// #define SPIBR_LSB	(8)
// #define SPIEN		SPI_EN_MASK	// bit 7
// #define SPIEN_LSB	(7)
// #define SPIMSB		SPI_MSB_MASK	// bit 6
// #define SPIMSB_LSB	(6)
// #define SPITCIE		SPI_TCIE_MASK	// bit 5
// #define SPITCIE_LSB	(5)
// #define SPITEIE		SPI_TEIE_MASK	// bit 4
// #define SPITEIE_LSB	(4)
// #define SPIDL_MASK	SPI_DL_MASK	// bits 3 downto 2
// #define SPIDL_LSB	(2)
// #define SPIDL_8		(0x00000000)
// #define SPIDL_16	(0x00000004)
// #define SPIDL_32	(0x00000008)
// #define SPICPOL		SPI_CPOL_MASK	// bit 1
// #define SPICPOL_LSB	(1)
// #define SPICPHA		SPI_CPHA_MASK	// bit 0
// #define SPICPHA_LSB	(0)

// // SPIxSR
// #define SPIxSR_OFFSET			(4) 
// #define SPIxSR_PTR(_SPIx_BASE)	MMR_08_PTR(_SPIx_BASE, SPIxSR_OFFSET)

// #define SPIBUSY		SPI_BUSY_MASK	// bit 2
// #define SPIBUSY_LSB	(2)
// #define SPITCIF		SPI_TCIF_MASK	// bit 1
// #define SPITCIF_LSB	(1)
// #define SPITEIF		SPI_TEIF_MASK	// bit 0
// #define SPITEIF_LSB	(0)

// // SPIxTX
// #define SPIxTX_OFFSET			(8)
// #define SPIxTX_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxTX_OFFSET)

// // SPIxRX
// #define SPIxRX_OFFSET			(12)
// #define SPIxRX_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxRX_OFFSET)

// // SPIxFOS
// #define SPIxFOS_OFFSET			(16)
// #define SPIxFOS_PTR(_SPIx_BASE)	MMR_32_PTR(_SPIx_BASE, SPIxFOS_OFFSET)



// /** Peripheral SPIx **/
// // Defining type SPIx_t structure
// // Bit fields structure for register SPIxCR 
// typedef union
// {
// 	volatile uint32_t value;
// 	struct
// 	{
// 		volatile uint32_t CPHA		: 1;	// bit 0
// 		volatile uint32_t CPOL		: 1;	// bit 1
// 		volatile uint32_t DL		: 2;	// bits 3 downto 2
// 		volatile uint32_t TEIE		: 1;	// bit 4
// 		volatile uint32_t TCIE		: 1;	// bit 5
// 		volatile uint32_t MSB		: 1;	// bit 6
// 		volatile uint32_t EN		: 1;	// bit 7
// 		volatile uint32_t BR		: 8;	// bits 15 downto 8
// 		volatile uint32_t RXSB		: 1;	// bit 16
// 		volatile uint32_t TXSB		: 1;	// bit 17
// 		volatile uint32_t SM		: 1;	// bit 18
// 		volatile uint32_t FEN		: 1;	// bit 19 TODO: Implement 
// 		volatile uint32_t __unused0	: 12;	// bits 31 downto 20
// 	};
// } SPIxCR_Register_t;

// // Bit fields structure for register SPIxSR
// typedef union
// {
// 	volatile uint8_t value;
// 	struct
// 	{
// 		volatile uint8_t TEIF		: 1;	// bit 0
// 		volatile uint8_t TCIF		: 1;	// bit 1
// 		volatile uint8_t BUSY		: 1;	// bit 2
// 		volatile uint8_t __unused0	: 5;	// bits 7 downto 3
// 	};
// } SPIxSR_Register_t;

// // Bit fields structure for register SPIxTX
// typedef union
// {
// 	volatile uint32_t value;
// 	struct
// 	{
// 		volatile uint32_t TX	: 32;	// bits 31 downto 0
// 	};
// } SPIxTX_Register_t;

// // Bit fields structure for register SPIxRX
// typedef union
// {
// 	volatile uint32_t value;
// 	struct
// 	{
// 		volatile uint32_t RX	: 32;	// bits 31 downto 0
// 	};
// } SPIxRX_Register_t;

// // Flash memory address offset register - add when implemented
// // Bit fields structure for register SPIxFOS
// typedef union
// {
// 	volatile uint32_t value;
// 	struct
// 	{
// 		volatile uint32_t FOS		: 24;	// bits 23 downto 0
// 		volatile uint32_t __unused0	: 8;	// bits 31 downto 24
// 	};
// } SPIxFOS_Register_t;



// // Registers structure for peripheral SPIx
// typedef struct
// {
// 	volatile SPIxCR_Register_t	CR;
// 	volatile SPIxSR_Register_t	SR;
// 	volatile uint8_t			__unused0;
// 	volatile uint16_t			__unused1;
// 	volatile SPIxTX_Register_t	TX;
// 	volatile SPIxRX_Register_t	RX;
// 	volatile SPIxFOS_Register_t	FOS;
// 	volatile uint32_t			__unused2[59];
// } SPIx_t;
// #define SPIx_PTR(_SPIx_BASE)	((SPIx_t *) _SPIx_BASE)



// // -- rv4th.c level - TIM PERIPHERAL LEVEL --------------------------------------------------------------



// /** TIMER0 **/
// #define TIMER0_BASE			(PERIPH_TIMER0_BASE)
// #define TIM0CR_ADDRESS		(PERIPH_TIMER0_BASE + TIMER_CR)
// #define TIM0CR				MMR_32_BIT_MACRO(TIM0CR_ADDRESS)
// #define TIM0SR_ADDRESS		(PERIPH_TIMER0_BASE + TIMER_SR)
// #define TIM0SR				MMR_08_BIT_MACRO(TIM0SR_ADDRESS)
// #define TIM0VAL_ADDRESS		(PERIPH_TIMER0_BASE + TIMER_VAL)
// #define TIM0VAL				MMR_32_BIT_MACRO(TIM0VAL_ADDRESS)
// #define TIM0CMP0_ADDRESS	(PERIPH_TIMER0_BASE + TIMER_CMP0)
// #define TIM0CMP0			MMR_32_BIT_MACRO(TIM0CMP0_ADDRESS)
// #define TIM0CMP1_ADDRESS	(PERIPH_TIMER0_BASE + TIMER_CMP1)
// #define TIM0CMP1			MMR_32_BIT_MACRO(TIM0CMP1_ADDRESS)
// #define TIM0CMP2_ADDRESS	(PERIPH_TIMER0_BASE + TIMER_CMP2)
// #define TIM0CMP2			MMR_32_BIT_MACRO(TIM0CMP2_ADDRESS)
// #define TIM0CAP0_ADDRESS	(PERIPH_TIMER0_BASE + TIMER_CAP0)
// #define TIM0CAP0			MMR_32_BIT_MACRO(TIM0CAP0_ADDRESS)
// #define TIM0CAP1_ADDRESS	(PERIPH_TIMER0_BASE + TIMER_CAP1)
// #define TIM0CAP1			MMR_32_BIT_MACRO(TIM0CAP1_ADDRESS)


// /** TIMER1 **/
// #define TIMER1_BASE			(PERIPH_TIMER1_BASE)
// #define TIM1CR_ADDRESS		(PERIPH_TIMER1_BASE + TIMER_CR)
// #define TIM1CR				MMR_32_BIT_MACRO(TIM1CR_ADDRESS)
// #define TIM1SR_ADDRESS		(PERIPH_TIMER1_BASE + TIMER_SR)
// #define TIM1SR				MMR_08_BIT_MACRO(TIM1SR_ADDRESS)
// #define TIM1VAL_ADDRESS		(PERIPH_TIMER1_BASE + TIMER_VAL)
// #define TIM1VAL				MMR_32_BIT_MACRO(TIM1VAL_ADDRESS)
// #define TIM1CMP0_ADDRESS	(PERIPH_TIMER1_BASE + TIMER_CMP0)
// #define TIM1CMP0			MMR_32_BIT_MACRO(TIM1CMP0_ADDRESS)
// #define TIM1CMP1_ADDRESS	(PERIPH_TIMER1_BASE + TIMER_CMP1)
// #define TIM1CMP1			MMR_32_BIT_MACRO(TIM1CMP1_ADDRESS)
// #define TIM1CMP2_ADDRESS	(PERIPH_TIMER1_BASE + TIMER_CMP2)
// #define TIM1CMP2			MMR_32_BIT_MACRO(TIM1CMP2_ADDRESS)
// #define TIM1CAP0_ADDRESS	(PERIPH_TIMER1_BASE + TIMER_CAP0)
// #define TIM1CAP0			MMR_32_BIT_MACRO(TIM1CAP0_ADDRESS)
// #define TIM1CAP1_ADDRESS	(PERIPH_TIMER1_BASE + TIMER_CAP1)
// #define TIM1CAP1			MMR_32_BIT_MACRO(TIM1CAP1_ADDRESS)



// /** TIMERx **/
// // TIMxCR
// #define TIMxCR_OFFSET				(0)
// #define TIMxCR_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCR_OFFSET)

// #define TIMDIV_MASK		TIMER_CLK_DIV_MASK	// bits 19 downto 16
// #define TIMDIV_LSB		(16)
// #define TIMDIV_1		(0x00000000)
// #define TIMDIV_2		(0x00010000)
// #define TIMDIV_4		(0x00020000)
// #define TIMDIV_8		(0x00030000)
// #define TIMDIV_16		(0x00040000)
// #define TIMDIV_32		(0x00050000)
// #define TIMDIV_64		(0x00060000)
// #define TIMDIV_128		(0x00070000)
// #define TIMDIV_256		(0x00080000)
// #define TIMDIV_512		(0x00090000)
// #define TIMDIV_1024		(0x000A0000)
// #define TIMDIV_2048		(0x000B0000)
// #define TIMDIV_4096		(0x000C0000)
// #define TIMDIV_8192		(0x000D0000)
// #define TIMDIV_16384	(0x000E0000)
// #define TIMDIV_32768	(0x000F0000)
// #define TIMCMP1IH		TIMER_CMP1_INIT_MASK	// bit 15
// #define TIMCMP1IH_LSB	(15)
// #define TIMCMP0IH		TIMER_CMP0_INIT_MASK	// bit 14
// #define TIMCMP0IH_LSB	(14)
// #define TIMCAP1FE		TIMER_CAP1_EDGE_MASK	// bit 13
// #define TIMCAP1FE_LSB	(13)
// #define TIMCAP0FE		TIMER_CAP0_EDGE_MASK	// bit 12
// #define TIMCAP0FE_LSB	(12)
// #define TIMCAP1EN		TIMER_CAP1_EN_MASK	// bit 11
// #define TIMCAP1EN_LSB	(11)
// #define TIMCAP0EN		TIMER_CAP0_EN_MASK	// bit 10
// #define TIMCAP0EN_LSB	(10)
// #define TIMSSEL_MASK	TIMER_CLK_SRC_MASK	// bits 9 downto 8
// #define TIMSSEL_LSB		(8)
// #define TIMSSEL_SMCLK	(0x00000000) 
// #define TIMSSEL_MCLK	(0x00000100)
// #define TIMSSEL_LFXT	(0x00000200)
// #define TIMSSEL_HFXT	(0x00000300)
// #define TIMCMP2RST		TIMER_CMP2_RESET_MASK	// bit 7
// #define TIMCMP2RST_LSB	(7)
// #define TIMEN			TIMER_EN_MASK	// bit 6
// #define TIMEN_LSB		(6)
// #define TIMCAP1IE		TIMER_CAP1_IE_MASK	// bit 5
// #define TIMCAP1IE_LSB	(5)
// #define TIMCAP0IE		TIMER_CAP0_IE_MASK	// bit 4
// #define TIMCAP0IE_LSB	(4)
// #define TIMOVIE			TIMER_OVF_IE_MASK	// bit 3
// #define TIMOVIE_LSB		(3)
// #define TIMCMP2IE		TIMER_CMP2_IE_MASK	// bit 2
// #define TIMCMP2IE_LSB	(2)
// #define TIMCMP1IE		TIMER_CMP1_IE_MASK	// bit 1
// #define TIMCMP1IE_LSB	(1)
// #define TIMCMP0IE		TIMER_CMP0_IE_MASK	// bit 0
// #define TIMCMP0IE_LSB	(0)

// // TIMxSR
// #define TIMxSR_OFFSET				(4)
// #define TIMxSR_PTR(_TIMERx_BASE)	MMR_08_PTR(_TIMERx_BASE, TIMxSR_OFFSET)

// #define TCMP1			TIMER_CMP1_OUT_MASK	// bit 7
// #define TCMP1_LSB		(7)
// #define TCMP0			TIMER_CMP0_OUT_MASK	// bit 6
// #define TCMP0_LSB		(6)
// #define TIMCAP1IF		TIMER_CAP1_IF_MASK	// bit 5
// #define TIMCAP1IF_LSB	(5)
// #define TIMCAP0IF		TIMER_CAP0_IF_MASK	// bit 4
// #define TIMCAP0IF_LSB	(4)
// #define TIMOVIF		    TIMER_OVF_IF_MASK	// bit 3
// #define TIMOVIF_LSB		(3)
// #define TIMCMP2IF		TIMER_CMP2_IF_MASK	// bit 2
// #define TIMCMP2IF_LSB	(2)
// #define TIMCMP1IF		TIMER_CMP1_IF_MASK	// bit 1
// #define TIMCMP1IF_LSB	(1)
// #define TIMCMP0IF		TIMER_CMP0_IF_MASK	// bit 0
// #define TIMCMP0IF_LSB	(0)

// // TIMxVAL
// #define TIMxVAL_OFFSET				(8)
// #define TIMxVAL_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxVAL_OFFSET)

// // TIMxCMP0
// #define TIMxCMP0_OFFSET				(12)
// #define TIMxCMP0_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP0_OFFSET)

// // TIMxCMP1
// #define TIMxCMP1_OFFSET				(16)
// #define TIMxCMP1_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP1_OFFSET)

// // TIMxCMP2
// #define TIMxCMP2_OFFSET				(20)
// #define TIMxCMP2_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCMP2_OFFSET)

// // TIMxCAP0
// #define TIMxCAP0_OFFSET				(24)
// #define TIMxCAP0_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCAP0_OFFSET)

// // TIMxCAP1
// #define TIMxCAP1_OFFSET				(28)
// #define TIMxCAP1_PTR(_TIMERx_BASE)	MMR_32_PTR(_TIMERx_BASE, TIMxCAP1_OFFSET)




// // -- Flash memory level -------------------------------------------------------------


// /** GPIO0 Pins **/
// // P1.0 secondary function (when P1SEL(0) = '1'): CS_FLASH
// #define CS_FLASH_BIT		(GPIO1_CS1_PIN)
// #define CS_FLASH_PxIN		(P1IN)
// #define CS_FLASH_PxSEL		(P1SEL)
// #define CS_FLASH_PxDIR		(P1DIR)
// #define CS_FLASH_PxOUT		(P1OUT)
// #define CS_FLASH_PxREN		(P1REN)
// #define CS_FLASH_PxIE		(P1IE)
// #define CS_FLASH_PxIES		(P1IES)
// #define CS_FLASH_PxIFG		(P1IFG)

// #define P1IN_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxIN)
// #define P1IN				MMR_08_BIT_MACRO(P1IN_ADDRESS)
// #define P1OUT_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxOUT)
// #define P1OUT				MMR_08_BIT_MACRO(P1OUT_ADDRESS)
// #define P1OUTS_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxOUTS)
// #define P1OUTS				MMR_08_BIT_MACRO(P1OUTS_ADDRESS)
// #define P1OUTC_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxOUTC)
// #define P1OUTC				MMR_08_BIT_MACRO(P1OUTC_ADDRESS)
// #define P1OUTT_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxOUTT)
// #define P1OUTT				MMR_32_BIT_MACRO(P1OUTT_ADDRESS)
// #define P1DIR_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxDIR)
// #define P1DIR				MMR_08_BIT_MACRO(P1DIR_ADDRESS)
// #define P1IFG_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxIFG)
// #define P1IFG				MMR_08_BIT_MACRO(P1IFG_ADDRESS)
// #define P1IES_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxIES)
// #define P1IES				MMR_08_BIT_MACRO(P1IES_ADDRESS)
// #define P1IE_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxIE)
// #define P1IE				MMR_08_BIT_MACRO(P1IE_ADDRESS)
// #define P1SEL_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxSEL)
// #define P1SEL				MMR_08_BIT_MACRO(P1SEL_ADDRESS)
// #define P1REN_ADDRESS		(PERIPH_GPIO0_BASE + GPIO_PxREN)
// #define P1REN				MMR_08_BIT_MACRO(P1REN_ADDRESS)




// ISR Macros ------------------------------------------------------

// SP already decremented by 4 by hardware (PC saved)
#define SAVE_CONTEXT() \
    addi sp, sp, -120; \
    sw x1, 0(sp);     \
    sw x3, 4(sp);      \
    sw x4, 8(sp);     \
    sw x5, 12(sp);     \
    sw x6, 16(sp);     \
    sw x7, 20(sp);     \
    sw x8, 24(sp);     \
    sw x9, 28(sp);     \
    sw x10, 32(sp);    \
    sw x11, 36(sp);    \
    sw x12, 40(sp);    \
    sw x13, 44(sp);    \
    sw x14, 48(sp);    \
    sw x15, 52(sp);    \
    sw x16, 56(sp);    \
    sw x17, 60(sp);    \
    sw x18, 64(sp);    \
    sw x19, 68(sp);    \
    sw x20, 72(sp);    \
    sw x21, 76(sp);    \
    sw x22, 80(sp);    \
    sw x23, 84(sp);    \
    sw x24, 88(sp);    \
    sw x25, 92(sp);    \
    sw x26, 96(sp);    \
    sw x27, 100(sp);   \
    sw x28, 104(sp);   \
    sw x29, 108(sp);   \
    sw x30, 112(sp);   \
    sw x31, 116(sp);

#define RESTORE_CONTEXT() \
    lw x1, 0(sp);      \
    lw x3, 4(sp);     \
    lw x4, 8(sp);    \
    lw x5, 12(sp);  \
    lw x6, 16(sp);  \
    lw x8, 24(sp);  \
    lw x9, 28(sp);  \
    lw x10, 32(sp); \
    lw x11, 36(sp); \
    lw x12, 40(sp); \
    lw x13, 44(sp); \
    lw x14, 48(sp); \
    lw x15, 52(sp); \
    lw x16, 56(sp); \
    lw x17, 60(sp); \
    lw x18, 64(sp); \
    lw x19, 68(sp); \
    lw x20, 72(sp); \
    lw x21, 76(sp); \
    lw x22, 80(sp); \
    lw x23, 84(sp); \
    lw x24, 88(sp); \
    lw x25, 92(sp); \
    lw x26, 96(sp); \
    lw x27, 100(sp); \
    lw x28, 104(sp); \
    lw x29, 108(sp); \
    lw x30, 112(sp); \
    lw x31, 116(sp); \
    addi sp, sp, 120; \
    iret; 



    // Bit Definitions (was bits.h)

    /** Defines **/
    #define BIT0	(0x00000001)
    #define BIT1	(0x00000002)
    #define BIT2	(0x00000004)
    #define BIT3	(0x00000008)
    #define BIT4	(0x00000010)
    #define BIT5	(0x00000020)
    #define BIT6	(0x00000040)
    #define BIT7	(0x00000080)
    #define BIT8	(0x00000100)
    #define BIT9	(0x00000200)
    #define BIT10	(0x00000400)
    #define BIT11	(0x00000800)
    #define BIT12	(0x00001000)
    #define BIT13	(0x00002000)
    #define BIT14	(0x00004000)
    #define BIT15	(0x00008000)
    #define BIT16	(0x00010000)
    #define BIT17	(0x00020000)
    #define BIT18	(0x00040000)
    #define BIT19	(0x00080000)
    #define BIT20	(0x00100000)
    #define BIT21	(0x00200000)
    #define BIT22	(0x00400000)
    #define BIT23	(0x00800000)
    #define BIT24	(0x01000000)
    #define BIT25	(0x02000000)
    #define BIT26	(0x04000000)
    #define BIT27	(0x08000000)
    #define BIT28	(0x10000000)
    #define BIT29	(0x20000000)
    #define BIT30	(0x40000000)
    #define BIT31	(0x80000000)

    #define BIT00	(BIT0)
    #define BIT01	(BIT1)
    #define BIT02	(BIT2)
    #define BIT03	(BIT3)
    #define BIT04	(BIT4)
    #define BIT05	(BIT5)
    #define BIT06	(BIT6)
    #define BIT07	(BIT7)
    #define BIT08	(BIT8)
    #define BIT09	(BIT9)

    #define BITA	(BIT10)
    #define BITB	(BIT11)
    #define BITC	(BIT12)
    #define BITD	(BIT13)
    #define BITE	(BIT14)
    #define BITF	(BIT15)




// If using C++, ensure functions have C linkage
#ifdef __cplusplus
}
#endif	




// // Custom Instruction Definitions
// #ifdef __ASSEMBLER__  // Only include if being processed by assembler

// // IRET - Interrupt Return
// // Signals end of ISR to hardware, triggers PC restore from stack
// // Encoding: opcode=0x0b, funct3=0, funct7=0, rd=0, rs1=0, rs2=0
// .macro iret
//     .insn r 0x0b, 0, 0, x0, x0, x0
// .endm

// #endif // __ASSEMBLER__





