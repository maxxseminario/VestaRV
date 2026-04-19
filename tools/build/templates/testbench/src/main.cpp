/** Includes **/
#include <MemoryMap.h>
#include <irq.h>
#include <uart.h>
#include <spi.h>
#include <flash_memory.h>



/** Defines **/
#define DEVBOARD_CLOCK	(24000000UL)
#define BAUDRATE		(115200UL)

#define MEM_ACCESS(_addr)		MMR_32_BIT_MACRO(_addr)

#define SINE_14b_NUM_SAMPS_HALF_BUFFER 256
#define SINE_14b_PING { 8192, 8192, 8282, 8101, 8372, 8011, 8463, 7920, 8553, 7830, 8644, 7739, 8734, 7649, 8824, 7559, 8914, 7469, 9004, 7379, 9094, 7289, 9184, 7199, 9273, 7110, 9363, 7020, 9452, 6931, 9541, 6842, 9630, 6753, 9718, 6665, 9807, 6576, 9895, 6488, 9983, 6400, 10070, 6313, 10158, 6225, 10245, 6138, 10332, 6051, 10418, 5965, 10504, 5879, 10590, 5793, 10675, 5708, 10760, 5623, 10845, 5538, 10929, 5454, 11013, 5370, 11096, 5287, 11179, 5204, 11262, 5121, 11344, 5039, 11425, 4958, 11506, 4877, 11587, 4796, 11667, 4716, 11746, 4637, 11825, 4558, 11904, 4479, 11982, 4401, 12059, 4324, 12136, 4247, 12212, 4171, 12287, 4096, 12362, 4021, 12437, 3946, 12510, 3873, 12583, 3800, 12656, 3727, 12727, 3656, 12798, 3585, 12868, 3515, 12938, 3445, 13007, 3376, 13075, 3308, 13142, 3241, 13209, 3174, 13275, 3108, 13340, 3043, 13405, 2978, 13468, 2915, 13531, 2852, 13593, 2790, 13654, 2729, 13714, 2669, 13774, 2609, 13833, 2550, 13890, 2493, 13947, 2436, 14003, 2380, 14059, 2324, 14113, 2270, 14166, 2217, 14219, 2164, 14271, 2112, 14321, 2062, 14371, 2012, 14420, 1963, 14468, 1915, 14515, 1868, 14561, 1822, 14606, 1777, 14650, 1733, 14693, 1690, 14735, 1648, 14777, 1606, 14817, 1566, 14856, 1527, 14894, 1489, 14931, 1452, 14968, 1415, 15003, 1380, 15037, 1346, 15070, 1313, 15102, 1281, 15133, 1250, 15163, 1220, 15192, 1191, 15220, 1163, 15246, 1137, 15272, 1111, 15297, 1086, 15320, 1063, 15343, 1040, 15364, 1019, 15385, 998, 15404, 979, 15422, 961, 15439, 944, 15455, 928, 15470, 913, 15484, 899, 15497, 886, 15508, 875, 15519, 864, 15528, 855, 15537, 846, 15544, 839, 15550, 833, 15555, 828, 15559, 824, 15562, 821, 15563, 820, 15564, 819, 15563, 820, 15562, 821, 15559, 824, 15555, 828, 15550, 833, 15544, 839, 15537, 846, 15528, 855, 15519, 864, 15508, 875, 15497, 886, 15484, 899, 15470, 913, 15455, 928, 15439, 944, 15422, 961, 15404, 979, 15385, 998, 15364, 1019, 15343, 1040, 15320, 1063, 15297, 1086, 15272, 1111, 15246, 1137, 15220, 1163, 15192, 1191, 15163, 1220, 15133, 1250, 15102, 1281, 15070, 1313, 15037, 1346, 15003, 1380, 14968, 1415, 14931, 1452, 14894, 1489, 14856, 1527, 14817, 1566, 14777, 1606, 14735, 1648, 14693, 1690, 14650, 1733, 14606, 1777, 14561, 1822, 14515, 1868, 14468, 1915, 14420, 1963, 14371, 2012, 14321, 2062, 14271, 2112, 14219, 2164, 14166, 2217, 14113, 2270, 14059, 2324, 14003, 2380, 13947, 2436, 13890, 2493, 13833, 2550, 13774, 2609, 13714, 2669, 13654, 2729, 13593, 2790, 13531, 2852, 13468, 2915, 13405, 2978, 13340, 3043, 13275, 3108, 13209, 3174, 13142, 3241, 13075, 3308, 13007, 3376, 12938, 3445, 12868, 3515, 12798, 3585, 12727, 3656, 12656, 3727, 12583, 3800, 12510, 3873, 12437, 3946, 12362, 4021, 12287, 4096, 12212, 4171, 12136, 4247, 12059, 4324, 11982, 4401, 11904, 4479, 11825, 4558, 11746, 4637, 11667, 4716, 11587, 4796, 11506, 4877, 11425, 4958, 11344, 5039, 11262, 5121, 11179, 5204, 11096, 5287, 11013, 5370, 10929, 5454, 10845, 5538, 10760, 5623, 10675, 5708, 10590, 5793, 10504, 5879, 10418, 5965, 10332, 6051, 10245, 6138, 10158, 6225, 10070, 6313, 9983, 6400, 9895, 6488, 9807, 6576, 9718, 6665, 9630, 6753, 9541, 6842, 9452, 6931, 9363, 7020, 9273, 7110, 9184, 7199, 9094, 7289, 9004, 7379, 8914, 7469, 8824, 7559, 8734, 7649, 8644, 7739, 8553, 7830, 8463, 7920, 8372, 8011, 8282, 8101 }
#define SINE_14b_PONG { 8192, 8192, 8101, 8282, 8011, 8372, 7920, 8463, 7830, 8553, 7739, 8644, 7649, 8734, 7559, 8824, 7469, 8914, 7379, 9004, 7289, 9094, 7199, 9184, 7110, 9273, 7020, 9363, 6931, 9452, 6842, 9541, 6753, 9630, 6665, 9718, 6576, 9807, 6488, 9895, 6400, 9983, 6313, 10070, 6225, 10158, 6138, 10245, 6051, 10332, 5965, 10418, 5879, 10504, 5793, 10590, 5708, 10675, 5623, 10760, 5538, 10845, 5454, 10929, 5370, 11013, 5287, 11096, 5204, 11179, 5121, 11262, 5039, 11344, 4958, 11425, 4877, 11506, 4796, 11587, 4716, 11667, 4637, 11746, 4558, 11825, 4479, 11904, 4401, 11982, 4324, 12059, 4247, 12136, 4171, 12212, 4096, 12287, 4021, 12362, 3946, 12437, 3873, 12510, 3800, 12583, 3727, 12656, 3656, 12727, 3585, 12798, 3515, 12868, 3445, 12938, 3376, 13007, 3308, 13075, 3241, 13142, 3174, 13209, 3108, 13275, 3043, 13340, 2978, 13405, 2915, 13468, 2852, 13531, 2790, 13593, 2729, 13654, 2669, 13714, 2609, 13774, 2550, 13833, 2493, 13890, 2436, 13947, 2380, 14003, 2324, 14059, 2270, 14113, 2217, 14166, 2164, 14219, 2112, 14271, 2062, 14321, 2012, 14371, 1963, 14420, 1915, 14468, 1868, 14515, 1822, 14561, 1777, 14606, 1733, 14650, 1690, 14693, 1648, 14735, 1606, 14777, 1566, 14817, 1527, 14856, 1489, 14894, 1452, 14931, 1415, 14968, 1380, 15003, 1346, 15037, 1313, 15070, 1281, 15102, 1250, 15133, 1220, 15163, 1191, 15192, 1163, 15220, 1137, 15246, 1111, 15272, 1086, 15297, 1063, 15320, 1040, 15343, 1019, 15364, 998, 15385, 979, 15404, 961, 15422, 944, 15439, 928, 15455, 913, 15470, 899, 15484, 886, 15497, 875, 15508, 864, 15519, 855, 15528, 846, 15537, 839, 15544, 833, 15550, 828, 15555, 824, 15559, 821, 15562, 820, 15563, 819, 15564, 820, 15563, 821, 15562, 824, 15559, 828, 15555, 833, 15550, 839, 15544, 846, 15537, 855, 15528, 864, 15519, 875, 15508, 886, 15497, 899, 15484, 913, 15470, 928, 15455, 944, 15439, 961, 15422, 979, 15404, 998, 15385, 1019, 15364, 1040, 15343, 1063, 15320, 1086, 15297, 1111, 15272, 1137, 15246, 1163, 15220, 1191, 15192, 1220, 15163, 1250, 15133, 1281, 15102, 1313, 15070, 1346, 15037, 1380, 15003, 1415, 14968, 1452, 14931, 1489, 14894, 1527, 14856, 1566, 14817, 1606, 14777, 1648, 14735, 1690, 14693, 1733, 14650, 1777, 14606, 1822, 14561, 1868, 14515, 1915, 14468, 1963, 14420, 2012, 14371, 2062, 14321, 2112, 14271, 2164, 14219, 2217, 14166, 2270, 14113, 2324, 14059, 2380, 14003, 2436, 13947, 2493, 13890, 2550, 13833, 2609, 13774, 2669, 13714, 2729, 13654, 2790, 13593, 2852, 13531, 2915, 13468, 2978, 13405, 3043, 13340, 3108, 13275, 3174, 13209, 3241, 13142, 3308, 13075, 3376, 13007, 3445, 12938, 3515, 12868, 3585, 12798, 3656, 12727, 3727, 12656, 3800, 12583, 3873, 12510, 3946, 12437, 4021, 12362, 4096, 12287, 4171, 12212, 4247, 12136, 4324, 12059, 4401, 11982, 4479, 11904, 4558, 11825, 4637, 11746, 4716, 11667, 4796, 11587, 4877, 11506, 4958, 11425, 5039, 11344, 5121, 11262, 5204, 11179, 5287, 11096, 5370, 11013, 5454, 10929, 5538, 10845, 5623, 10760, 5708, 10675, 5793, 10590, 5879, 10504, 5965, 10418, 6051, 10332, 6138, 10245, 6225, 10158, 6313, 10070, 6400, 9983, 6488, 9895, 6576, 9807, 6665, 9718, 6753, 9630, 6842, 9541, 6931, 9452, 7020, 9363, 7110, 9273, 7199, 9184, 7289, 9094, 7379, 9004, 7469, 8914, 7559, 8824, 7649, 8734, 7739, 8644, 7830, 8553, 7920, 8463, 8011, 8372, 8101, 8282 }



/** Interrupt Handler Function Declarations **/
RVISR(IRQ_GPIO2_VECTOR, ISR_GPIO2)
RVISR(IRQ_GPIO4_VECTOR, ISR_GPIO4)
RVISR(IRQ_SPI1_VECTOR, ISR_SPI1)
RVISR(IRQ_SYSTEM_VECTOR, ISR_SYSTEM)



/** Global Variables **/
volatile uint8_t pinInterruptCount;
volatile uint8_t isr_gpio4_count;
volatile uint8_t g_spi_slave_done;
__attribute__((section(".AFE0_HISTOGRAM_RAM"))) __attribute__((aligned (4))) volatile uint32_t AFE0_HISTOGRAM[1024] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

// DAC samples
__attribute__((section(".DAC_PING_RAM"))) __attribute__((aligned (2))) volatile uint16_t DAC_PING_BUFFER[] = SINE_14b_PING;
__attribute__((section(".DAC_PONG_RAM"))) __attribute__((aligned (2))) volatile uint16_t DAC_PONG_BUFFER[] = SINE_14b_PONG;



/** Main Function **/
extern "C" int main()
{
	// Power down the ROM
	MEMPWRCR |= ROMOFF;

	// Setup UART
	uart_init_8N1(DEVBOARD_CLOCK, BAUDRATE);
	
	// P2.0 is a pin interrupt
	P2SEL &= ~BIT0;
	P2DIR &= ~BIT0;
	P2IE = BIT0;

	// P2.1 is an input pin
	P2SEL &= ~BIT1;
	P2DIR &= ~BIT1;

	// P2.2 is an output LED
	P2SEL &= ~BIT2;
	P2DIR |= BIT2;
	P2OUTS = BIT2;

	// P2.3 is an output LED
	P2SEL &= ~BIT3;
	P2DIR |= BIT3;
	P2OUTC = BIT3;

	// P2.4 is an output LED
	P2SEL &= ~BIT4;
	P2DIR |= BIT4;
	P2OUTC = BIT4;

	// P2.5 is an output LED
	P2SEL &= ~BIT5;
	P2DIR |= BIT5;
	P2OUTC = BIT5;

	// P2.6 is an output that mirrors the selected clock
	P2SEL |= BIT6;

	// P2.6 (SDA0) and 2.7 (SCL0)
	SDA0_PxSEL |= SDA0_BIT;
	SDA0_PxREN |= SDA0_BIT;
	SCL0_PxSEL |= SCL0_BIT;
	SCL0_PxREN |= SCL0_BIT;

	// P3.0 is an input pin
	P3SEL &= ~BIT0;
	P3DIR &= ~BIT0;

	// P3.1 is an output pin
	P1SEL &= ~BIT1;
	P1DIR |= BIT1;
	P1OUTC = BIT1;
	P1OUTS = BIT1;
	P1OUTC = BIT1;


	// P4.0 is T0CMP0
	P4SEL |= BIT0;

	// P4.1 is a synchronization pin
	P4SEL &= ~BIT1;
	P4OUT &= ~BIT1;
	P4DIR |= BIT1;

	// P4.2 is a second pin interrupt
	P4SEL &= ~BIT2;
	P4DIR &= ~BIT2;
	P4IE = BIT2;



	// Watchdog timer
	if (WDTSR & WDTRF)
	{
		// The watchdog timer has reset the system
		uart_puts("WDTSR=");
		uart_puth4(WDTSR);
		uart_putln();
		WDTSR |= WDTRF;

		WDTPASS = 0x3FB0AD1C;
		WDTCR = WDTREN | WDTCDIV_65536;

		while (1) {}
	}


	// Set up DAC0
	DACCR = 0
		| DACCDIV_1
		| DAC1EN
		| DAC0EN
		| DACCS_HFXT
	;
	DACFS = 0;
	DACHBS = SINE_14b_NUM_SAMPS_HALF_BUFFER - 1;	// # samples in half buffer = DACHBS + 1
	DACCR |= DAC0DEN | DAC1DEN;



	// Test 2.1: Test the CRC16 module using CRC16_CDMA2000
	CRCSTATE = 0xFFFF;	// Set the initial CRC value to 0xFFFF
	P2OUTC = BIT2;
	CRCDATA = uart_getchar();	// VHDL testbench defines this as 0x5A, which is a 'Z' char
	printHex16(CRCSTATE);	// Should be equal to 0x38EA
	CRCSTATE = 0xFFFF;	// Set the initial CRC value to 0xFFFF
	CRCDATA = 0x5A;
	CRCDATA = 0x67;
	CRCDATA = 0x8F;
	CRCDATA = 0x20;
	printHex16(CRCSTATE);	// Should be equal to 0xF1A3
	uart_wait_for_transmission();



	// Test 2.2: Go to sleep and wait for several pin interrupts to occur
	// Clear P2.2
	P2OUTC = BIT2;
	P2IFG = 0xFF;
	P4IFG = 0xFF;

	// Set P2.3 to the value of P2.1 (the testbench expects it to go HIGH after it sets P2.1 HIGH)
	if (P2IN & BIT1)
		P2OUTS = BIT3;	// sync1
	else
		P2OUTC = BIT3;
	P2OUTC = BIT3;	// sync2
	
	pinInterruptCount = 0;
	P2IFG = 0xFF;	// Clear all pin interrupt flags on port 2
	enable_all_interrupts();	// Enable all interrupts
	//SYSCLKCR |= CPUOFF;	// Go to sleep
	cpu_sleep();	// Go to sleep

	// Once here, the two pin interrupts SHOULD have occurred
	P2OUTS = BIT3;	// sync3
	P2OUTC = BIT3;	// sync4

	// Two interrupts at once
	pinInterruptCount = 0;
	isr_gpio4_count = 0;
	P2IE = BIT0;
	P4IE = BIT2;

	// Wait for P2.1 to go high
	while (!(P2IN & BIT1)) {}

	// Toggle P2.4
	P2OUTS = BIT4;	// sync5
	P2OUTC = BIT4;	// sync6

	// Wait for the interrupts to trigger
	while ((pinInterruptCount < 3) || (isr_gpio4_count < 5)) {}
	uart_putui(pinInterruptCount);
	uart_putln();
	uart_putui(isr_gpio4_count);
	uart_putln();
	uart_wait_for_transmission();

	// De-prioritize GPIO2 priority
	IRQPRI |= 1 << IRQ_GPIO2_VECTOR;
	pinInterruptCount = 0;
	isr_gpio4_count = 0;
	P2IE = BIT0;
	P4IE = BIT2;

	// Wait for P2.1 to go high
	while (!(P2IN & BIT1)) {}

	// Toggle P2.4
	P2OUTS = BIT4;
	P2OUTC = BIT4;

	// Wait for the interrupts to trigger
	while ((pinInterruptCount < 5) || (isr_gpio4_count < 3)) {}
	uart_putui(pinInterruptCount);
	uart_putln();
	uart_putui(isr_gpio4_count);
	uart_putln();
	uart_wait_for_transmission();



	// Test 2.3: Test TIMER0
	TIM0CR = 0;
	TIM0VAL = 0;	// Reset the timer
	TIM0CMP2 = 140;	// The timer will reset after 120 cycles
	TIM0CMP0 = 100;	// A compare event is triggered after 100 cycles
	TIM0SR = 0xFF;	// Clear the status register
	TIM0CR = 0
		| TIMDIV_1	// No division
		| TIMCMP0IH	// Set T0CMP0's initial state to HIGH
		| TIMSSEL_MCLK	// Use MCLK as a source
		| TIMCMP2RST	// Reset the timer (and compare PWMs) when TIM0CMP2 occurs
		;
	TIM0CR |= TIMEN;	// You MUST enable the timer AFTER setting it up! Otherwise, not all the data will be latched in properly
	
	while (!(TIM0SR & TIMCMP0IF)) {}	// Wait until compare happens
	uint32_t tval1 = TIM0VAL;
	while (!(TIM0SR & TIMCMP2IF)) {}	// Wait until timer reset happens
	uint32_t tval2 = TIM0VAL;
	TIM0SR = 0xFF;
	while (!(TIM0SR & TIMCMP2IF)) {}	// Wait until timer reset happens
	TIM0CR = 0;	// Stop the timer

	printString("t1=");
	printNumberUInt32(tval1);
	printString("t2=");
	printNumberUInt32(tval2);
	printString("\n");
	uart_wait_for_transmission();


	/*
	// Test 2.4: Clock system
	// Set the DCO0 to another frequency
	DCO0FREQ = 500;

	// Switch mclk to DCO0
	SYSCLKCR = (SYSCLKCR & MCLKSEL_MASK) | (MCLKSEL_DCO0);

	// Divide mclk by two (should now be 50 MHz)
	CLKDIVCR = (CLKDIVCR & MCLKDIV_MASK) | (MCLKDIV_4);

	// Set P2.4 high
	P2OUTS |= BIT4;

	// Wait for P2.0 to go high while the testbench measures the frequency of the CLKO pin (P2.6)
	while (P2IN & BIT0) {}

	// Set P2.4 low
	P2OUTC |= BIT4;
	*/



	// Test 2.5: SPI1 in slave mode
	CS1_PxSEL	&= ~CS1_BIT;
	CS1_PxDIR	&= ~CS1_BIT;
	MOSI1_PxSEL	|= MOSI1_BIT;
	MISO1_PxSEL	|= MISO1_BIT;
	SCK1_PxSEL	|= SCK1_BIT;

	SPI1SR = 0xFF;	// clear the status register
	SPI1CR = 0
		| SPISM
		| (0 << SPIBR_LSB)
		| SPIEN
		| SPIMSB
		| SPITCIE
		| SPIDL_8
		//| SPICPOL	// When 0, SCK idles low and the leading edge is the rising edge
		| SPICPHA	// When 1, data is updated on the leading edge (rising edge) and sampled on the trailing edge (falling edge)
	;	// SPIMODE1
	SPI1SR = 0xFF;	// clear the status register
	SPI1TX = 0xB5;	// queue up the byte to send back to the master
	g_spi_slave_done = 0;
	P4OUTS = BIT1;	// Tell the testbench to send the SPI transfer
	P4OUTC = BIT1;
	
	while (g_spi_slave_done == 0) {}	// wait for the transfer to complete
	g_spi_slave_done = 0;
	SPI1TX = SPI1RX;
	printHex8(SPI1RX);	// Print the first result
	printNewline();

	while (g_spi_slave_done == 0) {}	// wait for the transfer to complete
	g_spi_slave_done = 0;
	SPI1TX = SPI1RX;
	printHex8(SPI1RX);	// Print the second result
	printNewline();

	while (g_spi_slave_done == 0) {}	// wait for the transfer to complete
	g_spi_slave_done = 0;
	printHex8(SPI1RX);	// Print the second result
	printNewline();
	
	uart_wait_for_transmission();
	SPI1CR = 0;



	// Test 2.6: I2C master mode
	// Set up I2C in master mode
	I2C0CR = 0
		| I2CMEN
		| I2CMDIV_1
	;
	I2C0SR = 0xFFFF;

	// Send start condition, wait for it to be sent
	I2C0FCR = I2CMST;
	while ((I2C0SR & I2CMSTS) == 0) {}
	I2C0SR = 0xFFFF;

	// Send the slave address and read/write mode, in master transmitter mode
	const uint8_t slave_addr = 0b01101010;
	uint8_t rw_bit = 0b0;
	I2C0MTX = (slave_addr << 1) | rw_bit;
	while ((I2C0SR & I2CMXC) == 0) {}	// Wait for transfer to complete
	if (I2C0SR & (I2CMARB | I2CMNR))
	{
		asm volatile ("ebreak");
	}
	I2C0SR = 0xFFFF;

	// Send a byte of data to the slave
	I2C0MTX = 0xB5;
	while ((I2C0SR & I2CMXC) == 0) {}	// Wait for transfer to complete
	I2C0SR = 0xFFFF;

	// Send a stop condition, wait for it to be sent
	I2C0FCR = I2CMSP;
	while ((I2C0SR & I2CMSPS) == 0) {}
	I2C0SR = 0xFFFF;

	I2C0CR = 0;

	


	// Test 2.7: I2C master receiver
	// Set up I2C in master mode
	I2C0CR = 0
		| I2CMEN
		| I2CMDIV_1
	;
	I2C0SR = 0xFFFF;

	// Send start condition, wait for it to be sent
	I2C0FCR = I2CMST;
	while ((I2C0SR & I2CMSTS) == 0) {}
	I2C0SR = 0xFFFF;

	// Send the slave address and read/write mode, in master transmitter mode
	rw_bit = 0b1;
	I2C0MTX = (slave_addr << 1) | rw_bit;
	while ((I2C0SR & I2CMXC) == 0) {}	// Wait for transfer to complete
	if (I2C0SR & (I2CMARB | I2CMNR))
	{
		printStringln("E!");
		return 0;
	}
	I2C0SR = 0xFFFF;

	// Receive a byte of data
	I2C0FCR = I2CMRB;
	while ((I2C0SR & I2CMXC) == 0) {}	// Wait for transfer to complete
	if (I2C0SR & (I2CMARB))
	{
		printStringln("E!");
		return 0;
	}
	I2C0SR = 0xFFFF;
	printHex8(I2C0MRX);
	printNewline();
	uart_wait_for_transmission();

	// Send a NACK and a stop condition, wait for it to be sent
	I2C0FCR = I2CMSP;
	while ((I2C0SR & I2CMSPS) == 0) {}
	I2C0SR = 0xFFFF;
	
	I2C0CR = 0;

	


	// Test 2.8: Native read-only SPI flash memory
	// Wake the SPI flash up
	// Set up SPI0
	spi_init(SPIMODE3, SPIDL_8);

	// Set up CS_FLASH pin
	CS_FLASH_PxSEL &= ~CS_FLASH_BIT;
	CS_FLASH_PxDIR |= CS_FLASH_BIT;
	deassert_CS_FLASH();

	// Wake the SPI flash from deep sleep
	assert_CS_FLASH();
	spi_transfer(0xAB);
	deassert_CS_FLASH();

	// Wait for about 8 ms for the SPI flash to awake. Note: you cannot read the SPI flash status register to know when the device has awoken from deep power down, since the MISO line will be in a high-impedance state
	//volatile uint32_t i;
	//for (i = 40000; i > 0; i--) {}
	while (flash_memory_busy()) {}

	// Perform the global unprotect operation for all the memory on the SPI flash. This allows any page to be written to and/or erased (YE BE WARNED)
	spi_setDataLength(SPIDL_32);

	assert_CS_FLASH();
	spi_transfer(0x3D2A80A6);
	deassert_CS_FLASH();

	// Wait for about 1 ms for the SPI flash to unprotect all its memory
	//for (i = 5000; i > 0; i--) {}
	while (flash_memory_busy()) {}

	// Configure the SPI flash to use 256-byte pages
	assert_CS_FLASH();
	spi_transfer(0x3D2A7F9A);
	deassert_CS_FLASH();	

	// Get the first 5 32-bit words in the SPI flash
	flash_memory_beginRead(0x0090);
	spi_setDataLength(SPIDL_32);
	uint32_t i;
	uint32_t spi_data[5];
	for (i = 0; i < 5; i++)
	{
		spi_data[i] = spi_transfer(0);
	}
	deassert_CS_FLASH();

	

	// Reconfigure SPI0 to be in SPI Flash mode
	CS_FLASH_PxSEL |= CS_FLASH_BIT;
	SPI0CR = (SPI0CR & ~SPIDL_MASK) | SPIDL_32;	// This is REQUIRED to make the RX swap-byte circuit work
	SPI0CR |= SPIFEN;
	SPI0FOS = 0x90;

	// Check the first word
	if (spi_data[0] != SPI_FLASH_MEM[0])
	{
		printStringln("F");
		return 0;
	}

	// Check the second word
	if (spi_data[1] != SPI_FLASH_MEM[1])
	{
		printStringln("F");
		return 0;
	}
	// Check the third word
	if (spi_data[2] != SPI_FLASH_MEM[2])
	{
		printStringln("F");
		return 0;
	}

	// Check the fifth word
	if (spi_data[4] != SPI_FLASH_MEM[4])
	{
		printStringln("F");
		return 0;
	}

	// Check the fifth word again
	if (spi_data[4] != SPI_FLASH_MEM[4])
	{
		printStringln("F");
		return 0;
	}

	P2SEL &= ~BIT3;
	printStringln("P");
	uart_wait_for_transmission();





	// Test 3.1
	AFE0SPT = 1;
	AFE0PIT = 10;
	AFE0EIT = 2;
	AFE0LIT = 5;
	AFE0RJT = 30;
	AFE0RST = 1;

	AFE0CR1 = 0
		| (1 << AdcClkDivN_LSB)
		| (1 << AdcClkDivM_LSB)
		| (1 << AdcSampT_LSB)
		| (0 << CMSHClkDiv_LSB)
	;

	AFE0CR0 = 0
		//| CsaRstMode
		//| EnAfe
		//| EnCM
		| EnCsa
		| EnAdc
		| EnThresh
		| EnDma
		| EnPURej
		//| EnPsd
		//|EnBLLT
		//|PsdOrder
		| PUPara
		//|RejectMode
	;

	AFE0CR0 |= EnAfe;

	// Wait for P3.0 to go high
	while (!(P3IN & BIT0)) {}

	AFE0CR0 &= ~EnDma;
	for (i = 0; i < 7; i++)
	{
		uart_putui(AFE0_HISTOGRAM[i]);
		uart_putc(' ');
	}
	uart_putln();

	// Keep going!
	AFE0CR0 |= EnDma;

	// Wait for P3.0 to go high
	while (!(P3IN & BIT0)) {}

	AFE0CR0 &= ~EnDma;
	for (i = 0; i < 9; i++)
	{
		uart_putui(AFE0_HISTOGRAM[i]);
		uart_putc(' ');
	}
	uart_putln();
	uart_wait_for_transmission();






	// Test 4.1: WDT
	WDTCR |= HWRST;
	P2OUTS = BIT2;
	P2OUTC = BIT2;
	WDTPASS = 0x3FB0AD1C;
	WDTCR = WDTREN | WDTIE | WDTCDIV_65536;


	

	while (1) {}
	return 0;
}



/** Interrupt Service Routines **/
void ISR_GPIO2()
{
	// Clear interrupt flag
	P2IFG = BIT0;
	
	// Toggle P2.2
	P2OUTS = BIT2;
	P2OUTC = BIT2;

	// Is it time to turn the CPU back on?
	pinInterruptCount++;
	if (pinInterruptCount >= 10)
	{
		// Turn the CPU back on
		//SYSCLKCR &= ~CPUOFF;
		cpu_wake();
	}
}

void ISR_GPIO4()
{
	// Clear interrupt flag
	P4IFG = BIT2;
	
	// Toggle P2.5
	P2OUTT = BIT5;
	P2OUTT = BIT5;

	isr_gpio4_count++;
}

void ISR_SPI1()
{
	SPI1SR = 0xFF;
	g_spi_slave_done = 1;
}

void ISR_SYSTEM()
{
	uart_puts("WDTSR=");
	uart_puth4(WDTSR);
	uart_putln();
	WDTSR = WDTIF;
	uart_wait_for_transmission();
}