//  Memory Map Constants Header File
//  Generated from memorymap.vhd

//  ---------- Peripheral Base Addresses ----------
#define PERIPH_GPIO0_BASE       0x4000    //  SPI Flash
#define PERIPH_GPIO1_BASE       0x4100
#define PERIPH_SPI0_BASE        0x4200
#define PERIPH_SPI1_BASE        0x4300
#define PERIPH_UART0_BASE       0x4400
#define PERIPH_UART1_BASE       0x4500
#define PERIPH_TIMER0_BASE      0x4600
#define PERIPH_TIMER1_BASE      0x4700
#define PERIPH_GPIO2_BASE       0x4800    //  Timers
#define PERIPH_SYSTEM0_BASE     0x4900
#define PERIPH_NPU0_BASE        0x4A00
#define PERIPH_SARADC0_BASE     0x4B00
#define PERIPH_AFE0_BASE        0x4C00
#define PERIPH_GPIO3_BASE       0x4D00

//  ---------- GPIO Register Offsets ----------
GPIO_PxIN               0x00      //  offset = 0 bytes
GPIO_PxOUT              0x04      //  offset = 4 bytes
GPIO_PxOUTS             0x08      //  offset = 8 bytes
GPIO_PxOUTC             0x0C      //  offset = 12 bytes
GPIO_PxOUTT             0x10      //  offset = 16 bytes
GPIO_PxDIR              0x14      //  offset = 20 bytes
GPIO_PxIFG              0x18      //  offset = 24 bytes
GPIO_PxIES              0x1C      //  offset = 28 bytes
GPIO_PxIE               0x20      //  offset = 32 bytes
GPIO_PxSEL              0x24      //  offset = 36 bytes
GPIO_PxREN              0x28      //  offset = 40 bytes

//  ---------- SPI Register Offsets ----------
SPI_CR                  0x00      //  offset = 0 bytes
SPI_SR                  0x04      //  offset = 4 bytes
SPI_TX                  0x08      //  offset = 8 bytes
SPI_RX                  0x0C      //  offset = 12 bytes
SPI_FOS                 0x10      //  offset = 16 bytes

//  ---------- TIMER Register Offsets ----------
TIM_CR                  0x00      //  offset = 0 bytes
TIM_SR                  0x04      //  offset = 4 bytes
TIM_VAL                 0x08      //  offset = 8 bytes
TIM_CMP0                0x0C      //  offset = 12 bytes
TIM_CMP1                0x10      //  offset = 16 bytes
TIM_CMP2                0x14      //  offset = 20 bytes
TIM_CAP0                0x18      //  offset = 24 bytes
TIM_CAP1                0x1C      //  offset = 28 bytes

//  ---------- UART Register Offsets ----------
UART_CR                 0x00      //  offset = 0 bytes
UART_SR                 0x04      //  offset = 4 bytes
UART_BR                 0x08      //  offset = 8 bytes
UART_RX                 0x0C      //  offset = 12 bytes
UART_TX                 0x10      //  offset = 16 bytes

//  ---------- SYSTEM Register Offsets ----------
SYS_CLK_CR              0x00      //  offset = 0 bytes
SYS_CLK_DIV_CR          0x04      //  offset = 4 bytes
SYS_BLOCK_PWR           0x08      //  offset = 8 bytes
SYS_CRC_DATA            0x0C      //  offset = 12 bytes
SYS_CRC_STATE           0x10      //  offset = 16 bytes
SYS_IRQ_EN              0x14      //  offset = 20 bytes
SYS_IRQ_PRI             0x18      //  offset = 24 bytes
SYS_WDT_PASS            0x1C      //  offset = 28 bytes
SYS_WDT_CR              0x20      //  offset = 32 bytes
SYS_WDT_SR              0x24      //  offset = 36 bytes
SYS_WDT_VAL             0x28      //  offset = 40 bytes
SYS_IRQ                 0x2C      //  offset = 44 bytes

//  ---------- NPU Register Offsets ----------
NPU_CR                  0x00      //  offset = 0 bytes
NPU_IVSAR               0x04      //  offset = 4 bytes
NPU_WVSAR               0x08      //  offset = 8 bytes
NPU_OVSAR               0x0C      //  offset = 12 bytes

//  ---------- AFE Register Offsets ----------
AFE_CR                  0x00      //  offset = 0 bytes
AFE_TPR                 0x04      //  offset = 4 bytes
AFE_SR                  0x08      //  offset = 8 bytes
AFE_ADC_VAL             0x0C      //  offset = 12 bytes
BIAS_CR                 0x10      //  offset = 16 bytes
BIAS_ADJ                0x30      //  offset = 48 bytes
BIAS_DBP                0x14      //  offset = 20 bytes
BIAS_DBPC               0x18      //  offset = 24 bytes
BIAS_DBNC               0x1C      //  offset = 28 bytes
BIAS_DBN                0x20      //  offset = 32 bytes
BIAS_TC_POT             0x24      //  offset = 36 bytes
BIAS_LC_POT             0x28      //  offset = 40 bytes
BIAS_TIA_G_POT          0x2C      //  offset = 44 bytes
BIAS_DSADC_VCM          0x30      //  offset = 48 bytes
BIAS_REV_POT            0x34      //  offset = 52 bytes
BIAS_TC_DSADC           0x38      //  offset = 56 bytes
BIAS_LC_DSADC           0x3C      //  offset = 60 bytes
BIAS_RIN_DSADC          0x40      //  offset = 64 bytes
BIAS_RFB_DSADC          0x44      //  offset = 68 bytes

//  ---------- SARADC Register Offsets ----------
SARADC_CR               0x00      //  offset = 0 bytes
SARADC_CDIV             0x04      //  offset = 4 bytes
SARADC_SR               0x08      //  offset = 8 bytes
SARADC_DATA             0x0C      //  offset = 12 bytes