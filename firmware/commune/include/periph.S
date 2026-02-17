// periph.S
// Peripheral and register address assembly header
// Defines the microcontroller peipheral and register addresses
// Generated on 2022/03/08 at 17:23:08 with the MemoryMap.py memory map generator
// WARNING: Do not edit or modify this file!
//   If you need to change it, use the MemoryMap.py memory map generator tool

#define RomStartAddress						0x0000
#define RomSize								0x4000
#define PeripheralMemoryStartAddress		0x4000
#define PeripheralMemorySize				0x2000
#define RamStartAddress						0x8000
#define RamSize								0x34800
#define RamProgramStartAddress				0x8080
#define InterruptHandlerAddress				0x8090
#define ProgramCounterInit					0x0000
#define StackPointerInit					0x2C000
#define BOOTLOADER_USES_SPI_FLASH_COMMANDS
#define SpiFlashProgramAddress				0x0000

#define CS_FLASH_MASK						0x01
#define P1SEL_BOOT_VAL						0x7E
#define SPI0_P1DIR_MASK						0x0E
#define BOOT_MASK							0x80

#define ENABLE_IRQ_FAST_CONTEXT_SWITCHING



/********** Register Offsets and Bit Fields **********/

/** SYSTEM **/
// SYSCLKCR
#define SYSCLKCR_OFFSET	0

#define DCO1OFF			0x0800	// bit 11
#define DCO1OFF_LSB		11
#define DCO0OFF			0x0400	// bit 10
#define DCO0OFF_LSB		10
#define HFXTOFF			0x0200	// bit 9
#define HFXTOFF_LSB		9
#define LFXTOFF			0x0100	// bit 8
#define LFXTOFF_LSB		8
#define SMCLKOFF		0x0040	// bit 6
#define SMCLKOFF_LSB	6
#define SMCLKSEL_MASK	0x0018	// bits 4 downto 3
#define SMCLKSEL_LSB	3
#define SMCLKSEL_HFXT	0x0000
#define SMCLKSEL_LFXT	0x0008
#define SMCLKSEL_DCO0	0x0010
#define SMCLKSEL_DCO1	0x0018
#define MCLKSEL_MASK	0x0003	// bits 1 downto 0
#define MCLKSEL_LSB		0
#define MCLKSEL_HFXT	0x0000
#define MCLKSEL_SMCLK	0x0001
#define MCLKSEL_DCO0	0x0002
#define MCLKSEL_DCO1	0x0003

// CLKDIVCR
#define CLKDIVCR_OFFSET	4

#define SMCLKDIV_MASK	0x38	// bits 5 downto 3
#define SMCLKDIV_LSB	3
#define SMCLKDIV_1		0x00
#define SMCLKDIV_2		0x08
#define SMCLKDIV_4		0x10
#define SMCLKDIV_8		0x18
#define SMCLKDIV_16		0x20
#define SMCLKDIV_32		0x28
#define SMCLKDIV_64		0x30
#define SMCLKDIV_128	0x38
#define MCLKDIV_MASK	0x07	// bits 2 downto 0
#define MCLKDIV_LSB		0
#define MCLKDIV_1		0x00
#define MCLKDIV_2		0x01
#define MCLKDIV_4		0x02
#define MCLKDIV_8		0x03
#define MCLKDIV_16		0x04
#define MCLKDIV_32		0x05
#define MCLKDIV_64		0x06
#define MCLKDIV_128		0x07

// MEMPWRCR
#define MEMPWRCR_OFFSET	8

#define SRAM15OFF		0x8000	// bit 15
#define SRAM15OFF_LSB	15
#define SRAM14OFF		0x4000	// bit 14
#define SRAM14OFF_LSB	14
#define SRAM13OFF		0x2000	// bit 13
#define SRAM13OFF_LSB	13
#define SRAM12OFF		0x1000	// bit 12
#define SRAM12OFF_LSB	12
#define SRAM11OFF		0x0800	// bit 11
#define SRAM11OFF_LSB	11
#define SRAM10OFF		0x0400	// bit 10
#define SRAM10OFF_LSB	10
#define SRAM09OFF		0x0200	// bit 9
#define SRAM09OFF_LSB	9
#define SRAM08OFF		0x0100	// bit 8
#define SRAM08OFF_LSB	8
#define SRAM07OFF		0x0080	// bit 7
#define SRAM07OFF_LSB	7
#define SRAM06OFF		0x0040	// bit 6
#define SRAM06OFF_LSB	6
#define SRAM05OFF		0x0020	// bit 5
#define SRAM05OFF_LSB	5
#define SRAM04OFF		0x0010	// bit 4
#define SRAM04OFF_LSB	4
#define SRAM03OFF		0x0008	// bit 3
#define SRAM03OFF_LSB	3
#define SRAM02OFF		0x0004	// bit 2
#define SRAM02OFF_LSB	2
#define ROMOFF			0x0001	// bit 0
#define ROMOFF_LSB		0

// CRCDATA
#define CRCDATA_OFFSET	12

// CRCSTATE
#define CRCSTATE_OFFSET	16

// IRQEN
#define IRQEN_OFFSET	20

// IRQPRI
#define IRQPRI_OFFSET	24

// WDTPASS
#define WDTPASS_OFFSET	28

// WDTCR
#define WDTCR_OFFSET	32

#define HWRST				0x40	// bit 6
#define HWRST_LSB			6
#define WDTCDIV_MASK		0x3C	// bits 5 downto 2
#define WDTCDIV_LSB			2
#define WDTCDIV_65536		0x00
#define WDTCDIV_131072		0x04
#define WDTCDIV_262144		0x08
#define WDTCDIV_524288		0x0C
#define WDTCDIV_1048576		0x10
#define WDTCDIV_2097152		0x14
#define WDTCDIV_4194304		0x18
#define WDTCDIV_8388608		0x1C
#define WDTCDIV_16777216	0x20
#define WDTCDIV_33554432	0x24
#define WDTCDIV_67108864	0x28
#define WDTCDIV_134217728	0x2C
#define WDTCDIV_268435456	0x30
#define WDTCDIV_536870912	0x34
#define WDTCDIV_1073741824	0x38
#define WDTCDIV_2147483648	0x3C
#define WDTIE				0x02	// bit 1
#define WDTIE_LSB			1
#define WDTREN				0x01	// bit 0
#define WDTREN_LSB			0

// WDTSR
#define WDTSR_OFFSET	36

#define WDTIF		0x02	// bit 1
#define WDTIF_LSB	1
#define WDTRF		0x01	// bit 0
#define WDTRF_LSB	0

// WDTVAL
#define WDTVAL_OFFSET	40

// DCO0FREQ
#define DCO0FREQ_OFFSET	44

#define DCO0MFREQ_MASK	0x0FFF	// bits 11 downto 0
#define DCO0MFREQ_LSB	0

// DCO1FREQ
#define DCO1FREQ_OFFSET	48

#define DCO1MFREQ_MASK	0x0FFF	// bits 11 downto 0
#define DCO1MFREQ_LSB	0

// TPMR
#define TPMR_OFFSET	52

// BIASCR
#define BIASCR_OFFSET	56

#define EnBG			0x0400	// bit 10
#define EnBG_LSB		10
#define UseExtBias		0x0200	// bit 9
#define UseExtBias_LSB	9
#define UseBiasDac		0x0100	// bit 8
#define UseBiasDac_LSB	8
#define EnBiasBuf		0x0080	// bit 7
#define EnBiasBuf_LSB	7
#define EnBiasGen		0x0040	// bit 6
#define EnBiasGen_LSB	6
#define BiasAdj_MASK	0x003F	// bits 5 downto 0
#define BiasAdj_LSB		0

// BIASDBP
#define BIASDBP_OFFSET	60

// BIASDBPC
#define BIASDBPC_OFFSET	64

// BIASDBNC
#define BIASDBNC_OFFSET	68

// BIASDBN
#define BIASDBN_OFFSET	72



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

// PxIFG
#define PxIFG_OFFSET	24

// PxIES
#define PxIES_OFFSET	28

// PxIE
#define PxIE_OFFSET	32

// PxSEL
#define PxSEL_OFFSET	36

// PxREN
#define PxREN_OFFSET	40



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

// SPIxRX
#define SPIxRX_OFFSET	12

// SPIxFOS
#define SPIxFOS_OFFSET	16



/** UARTx **/
// UARTxCR
#define UARTxCR_OFFSET	0

#define UEN			0x20	// bit 5
#define UEN_LSB		5
#define UPEN		0x10	// bit 4
#define UPEN_LSB	4
#define UPODD		0x08	// bit 3
#define UPODD_LSB	3
#define URCIE		0x04	// bit 2
#define URCIE_LSB	2
#define UTEIE		0x02	// bit 1
#define UTEIE_LSB	1
#define UTCIE		0x01	// bit 0
#define UTCIE_LSB	0

// UARTxSR
#define UARTxSR_OFFSET	4

#define URBF		0x80	// bit 7
#define URBF_LSB	7
#define UTBF		0x40	// bit 6
#define UTBF_LSB	6
#define UFEF		0x20	// bit 5
#define UFEF_LSB	5
#define UPEF		0x10	// bit 4
#define UPEF_LSB	4
#define UOVF		0x08	// bit 3
#define UOVF_LSB	3
#define URCIF		0x04	// bit 2
#define URCIF_LSB	2
#define UTEIF		0x02	// bit 1
#define UTEIF_LSB	1
#define UTCIF		0x01	// bit 0
#define UTCIF_LSB	0

// UARTxBR
#define UARTxBR_OFFSET	8

#define UBR_MASK	0x0FFF	// bits 11 downto 0
#define UBR_LSB		0

// UARTxRX
#define UARTxRX_OFFSET	12

// UARTxTX
#define UARTxTX_OFFSET	16



/** TIMERx **/
// TIMxCR
#define TIMxCR_OFFSET	0

#define TIMDIV_MASK		0x000F0000	// bits 19 downto 16
#define TIMDIV_LSB		16
#define TIMDIV_1		0x00000000
#define TIMDIV_2		0x00010000
#define TIMDIV_4		0x00020000
#define TIMDIV_8		0x00030000
#define TIMDIV_16		0x00040000
#define TIMDIV_32		0x00050000
#define TIMDIV_64		0x00060000
#define TIMDIV_128		0x00070000
#define TIMDIV_256		0x00080000
#define TIMDIV_512		0x00090000
#define TIMDIV_1024		0x000A0000
#define TIMDIV_2048		0x000B0000
#define TIMDIV_4096		0x000C0000
#define TIMDIV_8192		0x000D0000
#define TIMDIV_16384	0x000E0000
#define TIMDIV_32768	0x000F0000
#define TIMCMP1IH		0x00008000	// bit 15
#define TIMCMP1IH_LSB	15
#define TIMCMP0IH		0x00004000	// bit 14
#define TIMCMP0IH_LSB	14
#define TIMCAP1FE		0x00002000	// bit 13
#define TIMCAP1FE_LSB	13
#define TIMCAP0FE		0x00001000	// bit 12
#define TIMCAP0FE_LSB	12
#define TIMCAP1EN		0x00000800	// bit 11
#define TIMCAP1EN_LSB	11
#define TIMCAP0EN		0x00000400	// bit 10
#define TIMCAP0EN_LSB	10
#define TIMSSEL_MASK	0x00000300	// bits 9 downto 8
#define TIMSSEL_LSB		8
#define TIMSSEL_SMCLK	0x00000000
#define TIMSSEL_MCLK	0x00000100
#define TIMSSEL_LFXT	0x00000200
#define TIMSSEL_HFXT	0x00000300
#define TIMCMP2RST		0x00000080	// bit 7
#define TIMCMP2RST_LSB	7
#define TIMEN			0x00000040	// bit 6
#define TIMEN_LSB		6
#define TIMCAP1IE		0x00000020	// bit 5
#define TIMCAP1IE_LSB	5
#define TIMCAP0IE		0x00000010	// bit 4
#define TIMCAP0IE_LSB	4
#define TIMOVIE			0x00000008	// bit 3
#define TIMOVIE_LSB		3
#define TIMCMP2IE		0x00000004	// bit 2
#define TIMCMP2IE_LSB	2
#define TIMCMP1IE		0x00000002	// bit 1
#define TIMCMP1IE_LSB	1
#define TIMCMP0IE		0x00000001	// bit 0
#define TIMCMP0IE_LSB	0

// TIMxSR
#define TIMxSR_OFFSET	4

#define TCMP1			0x80	// bit 7
#define TCMP1_LSB		7
#define TCMP0			0x40	// bit 6
#define TCMP0_LSB		6
#define TIMCAP1IF		0x20	// bit 5
#define TIMCAP1IF_LSB	5
#define TIMCAP0IF		0x10	// bit 4
#define TIMCAP0IF_LSB	4
#define TIMOVIF			0x08	// bit 3
#define TIMOVIF_LSB		3
#define TIMCMP2IF		0x04	// bit 2
#define TIMCMP2IF_LSB	2
#define TIMCMP1IF		0x02	// bit 1
#define TIMCMP1IF_LSB	1
#define TIMCMP0IF		0x01	// bit 0
#define TIMCMP0IF_LSB	0

// TIMxVAL
#define TIMxVAL_OFFSET	8

// TIMxCMP0
#define TIMxCMP0_OFFSET	12

// TIMxCMP1
#define TIMxCMP1_OFFSET	16

// TIMxCMP2
#define TIMxCMP2_OFFSET	20

// TIMxCAP0
#define TIMxCAP0_OFFSET	24

// TIMxCAP1
#define TIMxCAP1_OFFSET	28



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



/** NNx **/
// NNxCR
#define NNxCR_OFFSET	0

#define NNCIE		0x00400000	// bit 22
#define NNCIE_LSB	22
#define NNCIF		0x00200000	// bit 21
#define NNCIF_LSB	21
#define NNLSIS		0x00100000	// bit 20
#define NNLSIS_LSB	20
#define NNCS		0x00080000	// bit 19
#define NNCS_LSB	19
#define NNBIAS		0x00040000	// bit 18
#define NNBIAS_LSB	18
#define NNAFS		0x00020000	// bit 17
#define NNAFS_LSB	17
#define NNRUN		0x00010000	// bit 16
#define NNRUN_LSB	16
#define NNO_MASK	0x0000FF00	// bits 15 downto 8
#define NNO_LSB		8
#define NNI_MASK	0x000000FF	// bits 7 downto 0
#define NNI_LSB		0

// NNxIVA
#define NNxIVA_OFFSET	4

#define NNIVA_MASK	0x00003FFC	// bits 13 downto 2
#define NNIVA_LSB	2

// NNxOVA
#define NNxOVA_OFFSET	8

#define NNOVA_MASK	0x00003FFC	// bits 13 downto 2
#define NNOVA_LSB	2

// NNxWMA
#define NNxWMA_OFFSET	12

#define NNWMA_MASK	0x00003FFC	// bits 13 downto 2
#define NNWMA_LSB	2

// NNxLSI
#define NNxLSI_OFFSET	16

// NNxLSO
#define NNxLSO_OFFSET	20



/** AFEx **/
// AFExCR0
#define AFExCR0_OFFSET	0

#define AdcExtIn			0x20000000	// bit 29
#define AdcExtIn_LSB		29
#define AdcMidSel			0x10000000	// bit 28
#define AdcMidSel_LSB		28
#define AdcMuxTest			0x08000000	// bit 27
#define AdcMuxTest_LSB		27
#define BufCMMid			0x04000000	// bit 26
#define BufCMMid_LSB		26
#define CsaBiasSel			0x02000000	// bit 25
#define CsaBiasSel_LSB		25
#define CsaForceRst			0x01000000	// bit 24
#define CsaForceRst_LSB		24
#define CsaForceUnRst		0x00800000	// bit 23
#define CsaForceUnRst_LSB	23
#define CsaRstMode			0x00400000	// bit 22
#define CsaRstMode_LSB		22
#define EnAfe				0x00200000	// bit 21
#define EnAfe_LSB			21
#define EnCM				0x00100000	// bit 20
#define EnCM_LSB			20
#define EnCsa				0x00080000	// bit 19
#define EnCsa_LSB			19
#define EnAdc				0x00040000	// bit 18
#define EnAdc_LSB			18
#define EnThresh			0x00020000	// bit 17
#define EnThresh_LSB		17
#define EnDma				0x00010000	// bit 16
#define EnDma_LSB			16
#define EnPURej				0x00008000	// bit 15
#define EnPURej_LSB			15
#define EnPsd				0x00004000	// bit 14
#define EnPsd_LSB			14
#define EnBLLT				0x00002000	// bit 13
#define EnBLLT_LSB			13
#define ForceThresh			0x00001000	// bit 12
#define ForceThresh_LSB		12
#define OpenInput			0x00000800	// bit 11
#define OpenInput_LSB		11
#define PsdOrder			0x00000400	// bit 10
#define PsdOrder_LSB		10
#define PUPara				0x00000200	// bit 9
#define PUPara_LSB			9
#define RamOff				0x00000100	// bit 8
#define RamOff_LSB			8
#define RejectMode			0x00000080	// bit 7
#define RejectMode_LSB		7
#define SHPwrMode			0x00000040	// bit 6
#define SHPwrMode_LSB		6
#define ThreshSel_MASK		0x00000030	// bits 5 downto 4
#define ThreshSel_LSB		4
#define PulseDoneWait		0x00000008	// bit 3
#define PulseDoneWait_LSB	3
#define PulseDoneIE			0x00000004	// bit 2
#define PulseDoneIE_LSB		2
#define AdcConvDoneIE		0x00000002	// bit 1
#define AdcConvDoneIE_LSB	1
#define PsdFullIE			0x00000001	// bit 0
#define PsdFullIE_LSB		0

// AFExCR1
#define AFExCR1_OFFSET	4

#define AdcClkDivN_MASK	0xE0000000	// bits 31 downto 29
#define AdcClkDivN_LSB	29
#define AdcClkDivM_MASK	0x1E000000	// bits 28 downto 25
#define AdcClkDivM_LSB	25
#define AdcCp_MASK		0x01FC0000	// bits 24 downto 18
#define AdcCp_LSB		18
#define AdcSampT_MASK	0x00038000	// bits 17 downto 15
#define AdcSampT_LSB	15
#define ClkSel_MASK		0x00006000	// bits 14 downto 13
#define ClkSel_LSB		13
#define CMSHClkDiv_MASK	0x00001E00	// bits 12 downto 9
#define CMSHClkDiv_LSB	9
#define CsaCmAdj_MASK	0x000001C0	// bits 8 downto 6
#define CsaCmAdj_LSB	6
#define ISink_MASK		0x0000003F	// bits 5 downto 0
#define ISink_LSB		0

// AFExCFB
#define AFExCFB_OFFSET	8

// AFExRFB
#define AFExRFB_OFFSET	12

// AFExTHR
#define AFExTHR_OFFSET	16

// AFExTPR
#define AFExTPR_OFFSET	20

#define AfeAtp1BufEn		0x20000000	// bit 29
#define AfeAtp1BufEn_LSB	29
#define AfeAtp1Sel_MASK		0x1E000000	// bits 28 downto 25
#define AfeAtp1Sel_LSB		25
#define AfeAtp0BufEn		0x01000000	// bit 24
#define AfeAtp0BufEn_LSB	24
#define AfeAtp0Sel_MASK		0x00F00000	// bits 23 downto 20
#define AfeAtp0Sel_LSB		20
#define AfeDtp3Sel_MASK		0x000F8000	// bits 19 downto 15
#define AfeDtp3Sel_LSB		15
#define AfeDtp2Sel_MASK		0x00007C00	// bits 14 downto 10
#define AfeDtp2Sel_LSB		10
#define AfeDtp1Sel_MASK		0x000003E0	// bits 9 downto 5
#define AfeDtp1Sel_LSB		5
#define AfeDtp0Sel_MASK		0x0000001F	// bits 4 downto 0
#define AfeDtp0Sel_LSB		0

// AFExSPT
#define AFExSPT_OFFSET	24

// AFExPIT
#define AFExPIT_OFFSET	28

// AFExEIT
#define AFExEIT_OFFSET	32

// AFExLIT
#define AFExLIT_OFFSET	36

// AFExRJT
#define AFExRJT_OFFSET	40

// AFExRST
#define AFExRST_OFFSET	44

// AFExAOFST
#define AFExAOFST_OFFSET	48

// AFExBLLT
#define AFExBLLT_OFFSET	52

// AFExCSAREF
#define AFExCSAREF_OFFSET	56

// AFExCSABP
#define AFExCSABP_OFFSET	60

// AFExCSABPC
#define AFExCSABPC_OFFSET	64

// AFExCSABNC
#define AFExCSABNC_OFFSET	68

// AFExCSABN
#define AFExCSABN_OFFSET	72

// AFExCMSHR
#define AFExCMSHR_OFFSET	76

// AFExCLPF
#define AFExCLPF_OFFSET	80

// AFExSR
#define AFExSR_OFFSET	84

#define DTP1VAL				0x80	// bit 7
#define DTP1VAL_LSB			7
#define DTP0VAL				0x40	// bit 6
#define DTP0VAL_LSB			6
#define AdcActive			0x20	// bit 5
#define AdcActive_LSB		5
#define AdcDataReady		0x10	// bit 4
#define AdcDataReady_LSB	4
#define DmaEnabled			0x08	// bit 3
#define DmaEnabled_LSB		3
#define PulseDone			0x04	// bit 2
#define PulseDone_LSB		2
#define AdcConvDone			0x02	// bit 1
#define AdcConvDone_LSB		1
#define PsdFull				0x01	// bit 0
#define PsdFull_LSB			0

// AFExADCVAL
#define AFExADCVAL_OFFSET	88

// AFExVPC
#define AFExVPC_OFFSET	92

// AFExTPC
#define AFExTPC_OFFSET	96



/** PCT **/
// PCTCR
#define PCTCR_OFFSET	0

#define ESPCT3		0x80	// bit 7
#define ESPCT3_LSB	7
#define ESPCT2		0x40	// bit 6
#define ESPCT2_LSB	6
#define ESPCT1		0x20	// bit 5
#define ESPCT1_LSB	5
#define ESPCT0		0x10	// bit 4
#define ESPCT0_LSB	4
#define ENPCT3		0x08	// bit 3
#define ENPCT3_LSB	3
#define ENPCT2		0x04	// bit 2
#define ENPCT2_LSB	2
#define ENPCT1		0x02	// bit 1
#define ENPCT1_LSB	1
#define ENPCT0		0x01	// bit 0
#define ENPCT0_LSB	0

// PCTCNT0
#define PCTCNT0_OFFSET	4

// PCTCNT1
#define PCTCNT1_OFFSET	8

// PCTCNT2
#define PCTCNT2_OFFSET	12

// PCTCNT3
#define PCTCNT3_OFFSET	16



/** OPA **/
// OPACR
#define OPACR_OFFSET	0

#define OPA1CMPIES			0x2000	// bit 13
#define OPA1CMPIES_LSB		13
#define OPA1CMPIE			0x1000	// bit 12
#define OPA1CMPIE_LSB		12
#define OPA1CMPEN			0x0800	// bit 11
#define OPA1CMPEN_LSB		11
#define OPA0CMPIES			0x0400	// bit 10
#define OPA0CMPIES_LSB		10
#define OPA0CMPIE			0x0200	// bit 9
#define OPA0CMPIE_LSB		9
#define OPA0CMPEN			0x0100	// bit 8
#define OPA0CMPEN_LSB		8
#define OPA1PDWD			0x0080	// bit 7
#define OPA1PDWD_LSB		7
#define OPA1BS				0x0040	// bit 6
#define OPA1BS_LSB			6
#define OPA1MODE_MASK		0x0030	// bits 5 downto 4
#define OPA1MODE_LSB		4
#define OPA1MODE_DISABLED	0x0000
#define OPA1MODE_BUF_ONLY	0x0010
#define OPA1MODE_OTA_UNBUF	0x0020
#define OPA1MODE_OTA_BUF	0x0030
#define OPA0PDWD			0x0008	// bit 3
#define OPA0PDWD_LSB		3
#define OPA0BS				0x0004	// bit 2
#define OPA0BS_LSB			2
#define OPA0MODE_MASK		0x0003	// bits 1 downto 0
#define OPA0MODE_LSB		0
#define OPA0MODE_DISABLED	0x0000
#define OPA0MODE_BUF_ONLY	0x0001
#define OPA0MODE_OTA_UNBUF	0x0002
#define OPA0MODE_OTA_BUF	0x0003

// OPASR
#define OPASR_OFFSET	4

#define OPA1CMPIF		0x08	// bit 3
#define OPA1CMPIF_LSB	3
#define OPA0CMPIF		0x04	// bit 2
#define OPA0CMPIF_LSB	2
#define OPA1CMPVAL		0x02	// bit 1
#define OPA1CMPVAL_LSB	1
#define OPA0CMPVAL		0x01	// bit 0
#define OPA0CMPVAL_LSB	0



/** DAC **/
// DACCR
#define DACCR_OFFSET	0

#define DACCDIV_MASK	0x0700	// bits 10 downto 8
#define DACCDIV_LSB		8
#define DACCDIV_1		0x0000
#define DACCDIV_2		0x0100
#define DACCDIV_4		0x0200
#define DACCDIV_8		0x0300
#define DACCDIV_16		0x0400
#define DACCDIV_32		0x0500
#define DACCDIV_64		0x0600
#define DACCDIV_128		0x0700
#define DAC1EN			0x0080	// bit 7
#define DAC1EN_LSB		7
#define DAC0EN			0x0040	// bit 6
#define DAC0EN_LSB		6
#define DAC1DEN			0x0020	// bit 5
#define DAC1DEN_LSB		5
#define DAC0DEN			0x0010	// bit 4
#define DAC0DEN_LSB		4
#define DACCS_MASK		0x000C	// bits 3 downto 2
#define DACCS_LSB		2
#define DACCS_MCLK		0x0000
#define DACCS_SMCLK		0x0004
#define DACCS_HFXT		0x0008
#define DACCS_DCO0		0x000C
#define DACDAL			0x0002	// bit 1
#define DACDAL_LSB		1
#define DACBEIE			0x0001	// bit 0
#define DACBEIE_LSB		0

// DACSR
#define DACSR_OFFSET	4

#define DACBH		0x02	// bit 1
#define DACBH_LSB	1
#define DACBEIF		0x01	// bit 0
#define DACBEIF_LSB	0

// DAC0VAL
#define DAC0VAL_OFFSET	8

// DAC1VAL
#define DAC1VAL_OFFSET	12

// DACFS
#define DACFS_OFFSET	16

// DACHBS
#define DACHBS_OFFSET	20



/********** Peripheral Base Addresses **********/
#define SYSTEM_BASE	0x4000
#define GPIO1_BASE	0x4100
#define SPI0_BASE	0x4200
#define SPI1_BASE	0x4300
#define UART0_BASE	0x4400
#define TIMER0_BASE	0x4500
#define TIMER1_BASE	0x4600
#define GPIO2_BASE	0x4700
#define GPIO3_BASE	0x4800
#define GPIO4_BASE	0x4900
#define GPIO5_BASE	0x4A00
#define I2C0_BASE	0x4B00
#define SPI2_BASE	0x4C00
#define UART1_BASE	0x4D00
#define TIMER2_BASE	0x4E00
#define TIMER3_BASE	0x4F00
#define NN0_BASE	0x5000
#define AFE0_BASE	0x5100
#define AFE1_BASE	0x5200
#define AFE2_BASE	0x5300
#define AFE3_BASE	0x5400
#define AFE4_BASE	0x5500
#define AFE5_BASE	0x5600
#define PCT_BASE	0x5700
#define GPIO6_BASE	0x5800
#define GPIO7_BASE	0x5900
#define GPIO8_BASE	0x5A00
#define OPA_BASE	0x5B00
#define DAC_BASE	0x5C00
#define I2C1_BASE	0x5D00
#define UART2_BASE	0x5E00
