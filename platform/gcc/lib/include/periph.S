// periph.S
// Peripheral and register address assembly header
// Defines the microcontroller peipheral and register addresses
// Generated on 2026/03/18 at 17:29:58 with the MemoryMap.py memory map generator
// WARNING: Do not edit or modify this file!
//   If you need to change it, use the MemoryMap.py memory map generator tool

#define RomStartAddress						0x0000
#define RomSize								0x4000
#define PeripheralMemoryStartAddress		0x4000
#define PeripheralMemorySize				0x1000
#define RamStartAddress						0x8000
#define RamSize								0x8000
#define RamProgramStartAddress				0x814C
#define InterruptHandlerAddress				0x9000
#define ProgramCounterInit					0x0000
#define StackPointerInit					0x10000
#define BOOTLOADER_USES_SPI_FLASH_COMMANDS
#define SpiFlashProgramAddress				0x8200

#define CS_FLASH_MASK						0x01
#define P1SEL_BOOT_VAL						0x7E
#define SPI0_P1DIR_MASK						0x0E
#define BOOT_MASK							0x80




/********** Register Offsets and Bit Fields **********/

/** GPIOx **/
// PxIN
#define PxIN_OFFSET	0

// PxOUT
#define PxOUT_OFFSET	4

// PxOUTS
#define PxOUTS_OFFSET	8

// PxOUTC
#define PxOUTC_OFFSET	12

// PxOUTT
#define PxOUTT_OFFSET	16

// PxDIR
#define PxDIR_OFFSET	20

// PxREN
#define PxREN_OFFSET	24

// PxSEL
#define PxSEL_OFFSET	28

// PxIF
#define PxIF_OFFSET	32

// PxIES
#define PxIES_OFFSET	36

// PxIE
#define PxIE_OFFSET	40



/** SPIx **/
// SPIxCR
#define SPIxCR_OFFSET	0

#define SPIFEN		0x00080000	// bit 19
#define SPIFEN_LSB	19
#define SPISM		0x00040000	// bit 18
#define SPISM_LSB	18
#define SPITXSB		0x00020000	// bit 17
#define SPITXSB_LSB	17
#define SPIRXSB		0x00010000	// bit 16
#define SPIRXSB_LSB	16
#define SPIBR_MASK	0x0000FF00	// bits 15 downto 8
#define SPIBR_LSB	8
#define SPIEN		0x00000080	// bit 7
#define SPIEN_LSB	7
#define SPIMSB		0x00000040	// bit 6
#define SPIMSB_LSB	6
#define SPITCIE		0x00000020	// bit 5
#define SPITCIE_LSB	5
#define SPITEIE		0x00000010	// bit 4
#define SPITEIE_LSB	4
#define SPIDL_MASK	0x0000000C	// bits 3 downto 2
#define SPIDL_LSB	2
#define SPIDL_8		0x00000000
#define SPIDL_16	0x00000004
#define SPIDL_32	0x00000008
#define SPIDL_RES	0x0000000C
#define SPICPOL		0x00000002	// bit 1
#define SPICPOL_LSB	1
#define SPICPHA		0x00000001	// bit 0
#define SPICPHA_LSB	0

// SPIxSR
#define SPIxSR_OFFSET	4

#define SPIBUSY		0x04	// bit 2
#define SPIBUSY_LSB	2
#define SPITCIF		0x02	// bit 1
#define SPITCIF_LSB	1
#define SPITEIF		0x01	// bit 0
#define SPITEIF_LSB	0

// SPIxTX
#define SPIxTX_OFFSET	8

#define SPITX_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SPITX_LSB	0

// SPIxRX
#define SPIxRX_OFFSET	12

#define SPIRX_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SPIRX_LSB	0

// SPIxFOS
#define SPIxFOS_OFFSET	16

#define SPIFOS_MASK	0x00FFFFFF	// bits 23 downto 0
#define SPIFOS_LSB	0



/** UARTx **/
// UARTxCR
#define UARTxCR_OFFSET	0

#define UEN			0x20	// bit 5
#define UEN_LSB		5
#define UPEN		0x10	// bit 4
#define UPEN_LSB	4
#define PSEL		0x08	// bit 3
#define PSEL_LSB	3
#define CIE			0x04	// bit 2
#define CIE_LSB		2
#define TEIE		0x02	// bit 1
#define TEIE_LSB	1
#define TCIE		0x01	// bit 0
#define TCIE_LSB	0

// UARTxSR
#define UARTxSR_OFFSET	4

#define RXBF		0x80	// bit 7
#define RXBF_LSB	7
#define TXBF		0x40	// bit 6
#define TXBF_LSB	6
#define FEF			0x20	// bit 5
#define FEF_LSB		5
#define PEF			0x10	// bit 4
#define PEF_LSB		4
#define OVF			0x08	// bit 3
#define OVF_LSB		3
#define RCIF		0x04	// bit 2
#define RCIF_LSB	2
#define TEIF		0x02	// bit 1
#define TEIF_LSB	1
#define TCIF		0x01	// bit 0
#define TCIF_LSB	0

// UARTxBR
#define UARTxBR_OFFSET	8

#define BR_MASK	0x0FFF	// bits 11 downto 0
#define BR_LSB	0

// UARTxRX
#define UARTxRX_OFFSET	12

#define RX_MASK	0xFF	// bits 7 downto 0
#define RX_LSB	0

// UARTxTX
#define UARTxTX_OFFSET	16

#define TX_MASK	0xFF	// bits 7 downto 0
#define TX_LSB	0



/** TIMERx **/
// TIMxCR
#define TIMxCR_OFFSET	0

#define DIV_MASK	0x000F0000	// bits 19 downto 16
#define DIV_LSB		16
#define DIV_1		0x00000000
#define DIV_2		0x00010000
#define DIV_4		0x00020000
#define DIV_8		0x00030000
#define DIV_16		0x00040000
#define DIV_32		0x00050000
#define DIV_64		0x00060000
#define DIV_128		0x00070000
#define DIV_256		0x00080000
#define DIV_512		0x00090000
#define DIV_1024	0x000A0000
#define DIV_2048	0x000B0000
#define DIV_4096	0x000C0000
#define DIV_8192	0x000D0000
#define DIV_16384	0x000E0000
#define DIV_32768	0x000F0000
#define CMP1IH		0x00008000	// bit 15
#define CMP1IH_LSB	15
#define CMP0IH		0x00004000	// bit 14
#define CMP0IH_LSB	14
#define CAP1FE		0x00002000	// bit 13
#define CAP1FE_LSB	13
#define CAP0FE		0x00001000	// bit 12
#define CAP0FE_LSB	12
#define CAP1EN		0x00000800	// bit 11
#define CAP1EN_LSB	11
#define CAP0EN		0x00000400	// bit 10
#define CAP0EN_LSB	10
#define SSEL_MASK	0x00000300	// bits 9 downto 8
#define SSEL_LSB	8
#define SSEL_SMCLK	0x00000000
#define SSEL_MCLK	0x00000100
#define SSEL_LFXT	0x00000200
#define SSEL_HFXT	0x00000300
#define CMP2RST		0x00000080	// bit 7
#define CMP2RST_LSB	7
#define TEN			0x00000040	// bit 6
#define TEN_LSB		6
#define CAP1IE		0x00000020	// bit 5
#define CAP1IE_LSB	5
#define CAP0IE		0x00000010	// bit 4
#define CAP0IE_LSB	4
#define OVIE		0x00000008	// bit 3
#define OVIE_LSB	3
#define CMP2IE		0x00000004	// bit 2
#define CMP2IE_LSB	2
#define CMP1IE		0x00000002	// bit 1
#define CMP1IE_LSB	1
#define CMP0IE		0x00000001	// bit 0
#define CMP0IE_LSB	0

// TIMxSR
#define TIMxSR_OFFSET	4

#define CMP1OUT		0x80	// bit 7
#define CMP1OUT_LSB	7
#define CMP0OUT		0x40	// bit 6
#define CMP0OUT_LSB	6
#define CAP1IF		0x20	// bit 5
#define CAP1IF_LSB	5
#define CAP0IF		0x10	// bit 4
#define CAP0IF_LSB	4
#define OVIF		0x08	// bit 3
#define OVIF_LSB	3
#define CMP2IF		0x04	// bit 2
#define CMP2IF_LSB	2
#define CMP1IF		0x02	// bit 1
#define CMP1IF_LSB	1
#define CMP0IF		0x01	// bit 0
#define CMP0IF_LSB	0

// TIMxVAL
#define TIMxVAL_OFFSET	8

#define VAL_MASK	0xFFFFFFFF	// bits 31 downto 0
#define VAL_LSB		0

// TIMxCMP0
#define TIMxCMP0_OFFSET	12

#define CMP0_MASK	0xFFFFFFFF	// bits 31 downto 0
#define CMP0_LSB	0

// TIMxCMP1
#define TIMxCMP1_OFFSET	16

#define CMP1_MASK	0xFFFFFFFF	// bits 31 downto 0
#define CMP1_LSB	0

// TIMxCMP2
#define TIMxCMP2_OFFSET	20

#define CMP2_MASK	0xFFFFFFFF	// bits 31 downto 0
#define CMP2_LSB	0

// TIMxCAP0
#define TIMxCAP0_OFFSET	24

#define CAP0_MASK	0xFFFFFFFF	// bits 31 downto 0
#define CAP0_LSB	0

// TIMxCAP1
#define TIMxCAP1_OFFSET	28

#define CAP1_MASK	0xFFFFFFFF	// bits 31 downto 0
#define CAP1_LSB	0



/** SYSTEM **/
// SYSCLKCR
#define SYSCLKCR_OFFSET	0

#define DCO1ON			0x0100	// bit 8
#define DCO1ON_LSB		8
#define DCO0ON			0x0080	// bit 7
#define DCO0ON_LSB		7
#define HFXTOFF			0x0040	// bit 6
#define HFXTOFF_LSB		6
#define LFXTOFF			0x0020	// bit 5
#define LFXTOFF_LSB		5
#define SMCLKOFF		0x0010	// bit 4
#define SMCLKOFF_LSB	4
#define SMCLKSEL_MASK	0x000C	// bits 3 downto 2
#define SMCLKSEL_LSB	2
#define SMCLKSEL_HFXT	0x0000
#define SMCLKSEL_LFXT	0x0004
#define SMCLKSEL_DCO0	0x0008
#define SMCLKSEL_DCO1	0x000C
#define MCLKSEL_MASK	0x0003	// bits 1 downto 0
#define MCLKSEL_LSB		0
#define MCLKSEL_HFXT	0x0000
#define MCLKSEL_SMCLK	0x0001
#define MCLKSEL_DCO0	0x0002
#define MCLKSEL_DCO1	0x0003

// CLKDIVCR
#define CLKDIVCR_OFFSET	4

#define SYSSMCLKDIV_MASK	0x38	// bits 5 downto 3
#define SYSSMCLKDIV_LSB		3
#define SYSSMCLKDIV_1		0x00
#define SYSSMCLKDIV_2		0x08
#define SYSSMCLKDIV_4		0x10
#define SYSSMCLKDIV_8		0x18
#define SYSSMCLKDIV_16		0x20
#define SYSSMCLKDIV_32		0x28
#define SYSSMCLKDIV_64		0x30
#define SYSSMCLKDIV_128		0x38
#define SYSMCLKDIV_MASK		0x07	// bits 2 downto 0
#define SYSMCLKDIV_LSB		0
#define SYSMCLKDIV_1		0x00
#define SYSMCLKDIV_2		0x01
#define SYSMCLKDIV_4		0x02
#define SYSMCLKDIV_8		0x03
#define SYSMCLKDIV_16		0x04
#define SYSMCLKDIV_32		0x05
#define SYSMCLKDIV_64		0x06
#define SYSMCLKDIV_128		0x07

// BLOCKPWR
#define BLOCKPWR_OFFSET	8

#define SYSRAM1OFF		0x04	// bit 2
#define SYSRAM1OFF_LSB	2
#define SYSRAM0OFF		0x02	// bit 1
#define SYSRAM0OFF_LSB	1
#define SYSROMOFF		0x01	// bit 0
#define SYSROMOFF_LSB	0

// CRCDATA
#define CRCDATA_OFFSET	12

#define SYSCRCDATA_MASK	0xFF	// bits 7 downto 0
#define SYSCRCDATA_LSB	0

// CRCSTATE
#define CRCSTATE_OFFSET	16

#define SYSCRCSTATE_MASK	0xFFFF	// bits 15 downto 0
#define SYSCRCSTATE_LSB		0

// IRQENL
#define IRQENL_OFFSET	20

#define SYSIRQENL_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSIRQENL_LSB	0

// IRQENM
#define IRQENM_OFFSET	24

#define SYSIRQENM_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSIRQENM_LSB	0

// IRQENU
#define IRQENU_OFFSET	28

#define SYSIRQENU_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSIRQENU_LSB	0

// IRQPRIL
#define IRQPRIL_OFFSET	32

#define SYSIRQPRIL_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSIRQPRIL_LSB	0

// IRQPRIM
#define IRQPRIM_OFFSET	36

#define SYSIRQPRIM_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSIRQPRIM_LSB	0

// IRQPRIU
#define IRQPRIU_OFFSET	40

#define SYSIRQPRIU_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSIRQPRIU_LSB	0

// IRQCR
#define IRQCR_OFFSET	44

#define SYSIRQRECEN		0x02	// bit 1
#define SYSIRQRECEN_LSB	1
#define SYSIRQGEN		0x01	// bit 0
#define SYSIRQGEN_LSB	0

// WDTCR
#define WDTCR_OFFSET	48

#define SYSWDTEN				0x80	// bit 7
#define SYSWDTEN_LSB			7
#define SYSWDTCDIV_MASK			0x3C	// bits 5 downto 2
#define SYSWDTCDIV_LSB			2
#define SYSWDTCDIV_65536		0x00
#define SYSWDTCDIV_131072		0x04
#define SYSWDTCDIV_262144		0x08
#define SYSWDTCDIV_524288		0x0C
#define SYSWDTCDIV_1048576		0x10
#define SYSWDTCDIV_2097152		0x14
#define SYSWDTCDIV_4194304		0x18
#define SYSWDTCDIV_8388608		0x1C
#define SYSWDTCDIV_16777216		0x20
#define SYSWDTCDIV_33554432		0x24
#define SYSWDTCDIV_67108864		0x28
#define SYSWDTCDIV_134217728	0x2C
#define SYSWDTCDIV_268435456	0x30
#define SYSWDTCDIV_536870912	0x34
#define SYSWDTCDIV_1073741824	0x38
#define SYSWDTCDIV_2147483648	0x3C
#define SYSWDTIE				0x02	// bit 1
#define SYSWDTIE_LSB			1
#define SYSWDTHWRST				0x01	// bit 0
#define SYSWDTHWRST_LSB			0

// WDTSR
#define WDTSR_OFFSET	52

#define SYSWDTIF		0x02	// bit 1
#define SYSWDTIF_LSB	1
#define SYSWDTRF		0x01	// bit 0
#define SYSWDTRF_LSB	0

// WDTPASS
#define WDTPASS_OFFSET	56

#define SYSWDTPASS_MASK	0xFFFFFFFF	// bits 31 downto 0
#define SYSWDTPASS_LSB	0

// WDTVAL
#define WDTVAL_OFFSET	60

#define SYSWDTVAL_MASK	0x00FFFFFF	// bits 23 downto 0
#define SYSWDTVAL_LSB	0

// DCO0BIAS
#define DCO0BIAS_OFFSET	64

#define SYSDCO0BIAS_MASK	0x0FFF	// bits 11 downto 0
#define SYSDCO0BIAS_LSB		0

// DCO1BIAS
#define DCO1BIAS_OFFSET	68

#define SYSDCO1BIAS_MASK	0x0FFF	// bits 11 downto 0
#define SYSDCO1BIAS_LSB		0



/** NPU **/
// NPUCR
#define NPUCR_OFFSET	0

#define NPUBEN			0x00040000	// bit 18
#define NPUBEN_LSB		18
#define NPUAEN			0x00020000	// bit 17
#define NPUAEN_LSB		17
#define NPUTHINK		0x00010000	// bit 16
#define NPUTHINK_LSB	16
#define NPUNI_MASK		0x0000FF00	// bits 15 downto 8
#define NPUNI_LSB		8
#define NPUNN_MASK		0x000000FF	// bits 7 downto 0
#define NPUNN_LSB		0

// NPUIVSAR
#define NPUIVSAR_OFFSET	4

// NPUWVSAR
#define NPUWVSAR_OFFSET	8

// NPUOVSAR
#define NPUOVSAR_OFFSET	12



/** SARADC **/
// SARADC_CR
#define SARADC_CR_OFFSET	0

#define SARADCCONTMEAS			0x0100	// bit 8
#define SARADCCONTMEAS_LSB		8
#define SARADCDATAIE			0x0080	// bit 7
#define SARADCDATAIE_LSB		7
#define SARADCDEBUG				0x0040	// bit 6
#define SARADCDEBUG_LSB			6
#define SARADCEN				0x0020	// bit 5
#define SARADCEN_LSB			5
#define SARADCSAMPLESTEP_MASK	0x001E	// bits 4 downto 1
#define SARADCSAMPLESTEP_LSB	1
#define SARADCRESET				0x0001	// bit 0
#define SARADCRESET_LSB			0

// SARADC_CDIV
#define SARADC_CDIV_OFFSET	4

#define SARADCCDIV_MASK	0xFF	// bits 7 downto 0
#define SARADCCDIV_LSB	0

// SARADC_SR
#define SARADC_SR_OFFSET	8

#define SARADCRDY			0x08	// bit 3
#define SARADCRDY_LSB		3
#define SARADCOVF			0x04	// bit 2
#define SARADCOVF_LSB		2
#define SARADCDATAVALID		0x02	// bit 1
#define SARADCDATAVALID_LSB	1
#define SARADCBUSY			0x01	// bit 0
#define SARADCBUSY_LSB		0

// SARADC_DATA
#define SARADC_DATA_OFFSET	12

#define SARADCDATA_MASK	0x03FF	// bits 9 downto 0
#define SARADCDATA_LSB	0

// SARADC_TPR
#define SARADC_TPR_OFFSET	16

#define SARADCDTP1SEL_MASK	0xF0	// bits 7 downto 4
#define SARADCDTP1SEL_LSB	4
#define SARADCDTP0SEL_MASK	0x0F	// bits 3 downto 0
#define SARADCDTP0SEL_LSB	0



/** AFE **/
// AFE_CR
#define AFE_CR_OFFSET	0

#define AFE_RAMPNUM_MASK	0x00FFF000	// bits 23 downto 12
#define AFE_RAMPNUM_LSB		12
#define AFE_ADCSEL			0x00000800	// bit 11
#define AFE_ADCSEL_LSB		11
#define AFE_ATPSEL			0x00000400	// bit 10
#define AFE_ATPSEL_LSB		10
#define AFE_ATPEN			0x00000200	// bit 9
#define AFE_ATPEN_LSB		9
#define AFE_ADCEXTIN		0x00000100	// bit 8
#define AFE_ADCEXTIN_LSB	8
#define AFE_CONTMEAS		0x00000010	// bit 4
#define AFE_CONTMEAS_LSB	4
#define AFE_DACEN			0x00000008	// bit 3
#define AFE_DACEN_LSB		3
#define AFE_DATARDYIE		0x00000004	// bit 2
#define AFE_DATARDYIE_LSB	2
#define AFE_EN				0x00000002	// bit 1
#define AFE_EN_LSB			1
#define AFE_ADCEN			0x00000001	// bit 0
#define AFE_ADCEN_LSB		0

// AFE_TPR
#define AFE_TPR_OFFSET	4

#define AFE_DTP3SEL_MASK	0x000F8000	// bits 19 downto 15
#define AFE_DTP3SEL_LSB		15
#define AFE_DTP2SEL_MASK	0x00007C00	// bits 14 downto 10
#define AFE_DTP2SEL_LSB		10
#define AFE_DTP1SEL_MASK	0x000003E0	// bits 9 downto 5
#define AFE_DTP1SEL_LSB		5
#define AFE_DTP0SEL_MASK	0x0000001F	// bits 4 downto 0
#define AFE_DTP0SEL_LSB		0

// AFE_SR
#define AFE_SR_OFFSET	8

#define AFE_OVFIF			0x04	// bit 2
#define AFE_OVFIF_LSB		2
#define AFE_DATARDYIF		0x02	// bit 1
#define AFE_DATARDYIF_LSB	1
#define AFE_ADCACTIVE		0x01	// bit 0
#define AFE_ADCACTIVE_LSB	0

// AFE_ADC_VAL
#define AFE_ADC_VAL_OFFSET	12

#define AFE_ADCVAL_MASK	0x0FFF	// bits 11 downto 0
#define AFE_ADCVAL_LSB	0

// BIAS_CR
#define BIAS_CR_OFFSET	16

#define USEDAC		0x10	// bit 4
#define USEDAC_LSB	4
#define BUFEN		0x08	// bit 3
#define BUFEN_LSB	3
#define EN			0x04	// bit 2
#define EN_LSB		2

// BIAS_ADJ
#define BIAS_ADJ_OFFSET	20

#define ADJ_MASK	0x3F	// bits 5 downto 0
#define ADJ_LSB		0

// BIAS_DBP
#define BIAS_DBP_OFFSET	24

#define DBP_MASK	0x3FFF	// bits 13 downto 0
#define DBP_LSB		0

// BIAS_DBPC
#define BIAS_DBPC_OFFSET	28

#define DBPC_MASK	0x3FFF	// bits 13 downto 0
#define DBPC_LSB	0

// BIAS_DBNC
#define BIAS_DBNC_OFFSET	32

#define DBNC_MASK	0x3FFF	// bits 13 downto 0
#define DBNC_LSB	0

// BIAS_DBN
#define BIAS_DBN_OFFSET	36

#define DBN_MASK	0x3FFF	// bits 13 downto 0
#define DBN_LSB		0

// BIAS_TC_POT
#define BIAS_TC_POT_OFFSET	40

#define TC_POT_MASK	0x3F	// bits 5 downto 0
#define TC_POT_LSB	0

// BIAS_LC_POT
#define BIAS_LC_POT_OFFSET	44

#define LC_POT_MASK	0x3F	// bits 5 downto 0
#define LC_POT_LSB	0

// BIAS_TIA_G_POT
#define BIAS_TIA_G_POT_OFFSET	48

#define TIA_G_POT_MASK	0x0001FFFF	// bits 16 downto 0
#define TIA_G_POT_LSB	0

// BIAS_DSADC_VCM
#define BIAS_DSADC_VCM_OFFSET	52

#define DSADC_VCM_MASK	0x3FFF	// bits 13 downto 0
#define DSADC_VCM_LSB	0

// BIAS_REV_POT
#define BIAS_REV_POT_OFFSET	56

#define REV_POT_MASK	0x3FFF	// bits 13 downto 0
#define REV_POT_LSB		0

// BIAS_TC_DSADC
#define BIAS_TC_DSADC_OFFSET	60

#define TC_DSADC_MASK	0x3F	// bits 5 downto 0
#define TC_DSADC_LSB	0

// BIAS_LC_DSADC
#define BIAS_LC_DSADC_OFFSET	64

#define LC_DSADC_MASK	0x3F	// bits 5 downto 0
#define LC_DSADC_LSB	0

// BIAS_RIN_DSADC
#define BIAS_RIN_DSADC_OFFSET	68

#define RIN_DSADC_MASK	0x3F	// bits 5 downto 0
#define RIN_DSADC_LSB	0

// BIAS_RFB_DSADC
#define BIAS_RFB_DSADC_OFFSET	72

#define RFB_DSADC_MASK	0x3F	// bits 5 downto 0
#define RFB_DSADC_LSB	0



/** I2Cx **/
// I2CxCR
#define I2CxCR_OFFSET	0

#define I2CMEN			0x00200000	// bit 21
#define I2CMEN_LSB		21
#define I2CSEN			0x00100000	// bit 20
#define I2CSEN_LSB		20
#define I2CSN			0x00080000	// bit 19
#define I2CSN_LSB		19
#define I2CSCS			0x00040000	// bit 18
#define I2CSCS_LSB		18
#define I2CGCE			0x00020000	// bit 17
#define I2CGCE_LSB		17
#define I2CMDIV_MASK	0x0001E000	// bits 16 downto 13
#define I2CMDIV_LSB		13
#define I2CMDIV_1		0x00000000
#define I2CMDIV_2		0x00002000
#define I2CMDIV_4		0x00004000
#define I2CMDIV_8		0x00006000
#define I2CMDIV_16		0x00008000
#define I2CMDIV_32		0x0000A000
#define I2CMDIV_64		0x0000C000
#define I2CMDIV_128		0x0000E000
#define I2CMDIV_256		0x00010000
#define I2CMDIV_512		0x00012000
#define I2CMDIV_1024	0x00014000
#define I2CMDIV_2048	0x00016000
#define I2CMDIV_4096	0x00018000
#define I2CMDIV_8192	0x0001A000
#define I2CMDIV_16384	0x0001C000
#define I2CMDIV_32768	0x0001E000
#define I2CSAIE			0x00001000	// bit 12
#define I2CSAIE_LSB		12
#define I2CSTXEIE		0x00000800	// bit 11
#define I2CSTXEIE_LSB	11
#define I2CSOVFIE		0x00000400	// bit 10
#define I2CSOVFIE_LSB	10
#define I2CSNRIE		0x00000200	// bit 9
#define I2CSNRIE_LSB	9
#define I2CSXCIE		0x00000100	// bit 8
#define I2CSXCIE_LSB	8
#define I2CMSTSIE		0x00000080	// bit 7
#define I2CMSTSIE_LSB	7
#define I2CMSPSIE		0x00000040	// bit 6
#define I2CMSPSIE_LSB	6
#define I2CMARBIE		0x00000020	// bit 5
#define I2CMARBIE_LSB	5
#define I2CMTXEIE		0x00000010	// bit 4
#define I2CMTXEIE_LSB	4
#define I2CMNRIE		0x00000008	// bit 3
#define I2CMNRIE_LSB	3
#define I2CMXCIE		0x00000004	// bit 2
#define I2CMXCIE_LSB	2
#define I2CSTRIE		0x00000002	// bit 1
#define I2CSTRIE_LSB	1
#define I2CSPRIE		0x00000001	// bit 0
#define I2CSPRIE_LSB	0

// I2CxFCR
#define I2CxFCR_OFFSET	4

#define I2CSC		0x08	// bit 3
#define I2CSC_LSB	3
#define I2CMST		0x04	// bit 2
#define I2CMST_LSB	2
#define I2CMSP		0x02	// bit 1
#define I2CMSP_LSB	1
#define I2CMRB		0x01	// bit 0
#define I2CMRB_LSB	0

// I2CxSR
#define I2CxSR_OFFSET	8

#define I2CBS		0x8000	// bit 15
#define I2CBS_LSB	15
#define I2CMCB		0x4000	// bit 14
#define I2CMCB_LSB	14
#define I2CSTM		0x2000	// bit 13
#define I2CSTM_LSB	13
#define I2CSA		0x1000	// bit 12
#define I2CSA_LSB	12
#define I2CSTXE		0x0800	// bit 11
#define I2CSTXE_LSB	11
#define I2CSOVF		0x0400	// bit 10
#define I2CSOVF_LSB	10
#define I2CSNR		0x0200	// bit 9
#define I2CSNR_LSB	9
#define I2CSXC		0x0100	// bit 8
#define I2CSXC_LSB	8
#define I2CMSTS		0x0080	// bit 7
#define I2CMSTS_LSB	7
#define I2CMSPS		0x0040	// bit 6
#define I2CMSPS_LSB	6
#define I2CMARB		0x0020	// bit 5
#define I2CMARB_LSB	5
#define I2CMTXE		0x0010	// bit 4
#define I2CMTXE_LSB	4
#define I2CMNR		0x0008	// bit 3
#define I2CMNR_LSB	3
#define I2CMXC		0x0004	// bit 2
#define I2CMXC_LSB	2
#define I2CSTR		0x0002	// bit 1
#define I2CSTR_LSB	1
#define I2CSPR		0x0001	// bit 0
#define I2CSPR_LSB	0

// I2CxMTX
#define I2CxMTX_OFFSET	12

// I2CxMRX
#define I2CxMRX_OFFSET	16

// I2CxSTX
#define I2CxSTX_OFFSET	20

// I2CxSRX
#define I2CxSRX_OFFSET	24

// I2CxAR
#define I2CxAR_OFFSET	28

// I2CxAMR
#define I2CxAMR_OFFSET	32



/********** Peripheral Base Addresses **********/
#define GPIO0_BASE	0x4000
#define GPIO1_BASE	0x4100
#define SPI0_BASE	0x4200
#define SPI1_BASE	0x4300
#define UART0_BASE	0x4400
#define UART1_BASE	0x4500
#define TIMER0_BASE	0x4600
#define TIMER1_BASE	0x4700
#define GPIO2_BASE	0x4800
#define SYSTEM_BASE	0x4900
#define NPU_BASE	0x4A00
#define SARADC_BASE	0x4B00
#define AFE_BASE	0x4C00
#define GPIO3_BASE	0x4D00
#define I2C0_BASE	0x4E00
#define I2C1_BASE	0x4F00
