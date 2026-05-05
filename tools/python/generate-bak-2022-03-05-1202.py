#!/usr/bin/env python3

import pathlib, sys, os

thisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
chipRootDirectory = thisFileDirectory + '/..'

sys.path.append(os.path.abspath(chipRootDirectory + '/../common/ChipGenerator/python'))

from ChipGenerator import ChipGenerator
from Peripheral import PeripheralTemplate, Peripheral
from Register import RegisterTemplate, Register
from BitField import BitField
from GpioConfigurator import GpioConfigurator



''' Create Memory Map '''
m = ChipGenerator(
	chipRootDirectory=chipRootDirectory,
	asicName='washakie',
	asicNameForUserGuide='Washakie',
	mcuUserGuideLatexTemplateFileName='MCU-User-Guide.template-washakie-2022-03.tex',
	romStartAddress=0x0000,
	romSize=8192,	# 8 KiB
	peripheralMemoryStartAddress=0x4000,
	peripheralMemorySlotCount=32,
	registerMemorySlotsPerPeripheralMemorySlot=64,
	ramStartAddress=0x8000,
	ramMemorySlotSize=16384,	# 16 KiB
	ramMemorySlotsAvailable=[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	ramMemorySlotsUsed=[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	ramMemorySlotsMuxed={11: 'NPU0', 12: 'AFE0 and AFE1', 13: 'AFE2 and AFE3', 14: 'AFE4 and AFE5', 15: 'DAC'},	# The RAM slots that are MUXed with some peripheral that the program may not always use for whatever it wants.
	spiFlashProgramAddress=0x0000,
	nativeSpiFlashMemoryReadAccess=True,
	nativeSpiFlashMemoryWriteAccess=False,
	stackPointerInit=0x2C000,	# TODO: Make sure the initial stack pointer is not in the NPU MUXed RAM block or the AFE MUXed RAM blocks.
	bootloaderUsesSpiFlashCommands=True,
	vectorsCount=32,
	padOutPosLogic=True,
	padDIRPosLogic=False,
	padRENPosLogic=False,
	ENABLE_COUNTERS=False,
	ENABLE_COUNTERS64=False,
	ENABLE_REGS_DUALPORT=True,	# TODO: Enable for ASIC synthesis if using a dual port register file, disable for Xilinx Spartan 6 FPGAs
	TWO_STAGE_SHIFT=True,
	BARREL_SHIFTER=True,
	COMPRESSED_ISA=True,
	ENABLE_MUL=True,
	ENABLE_FAST_MUL=True,
	ENABLE_DIV=True,
	ENABLE_IRQ_FAST_CONTEXT_SWITCHING=True,	# Using fast context switching saves 31.042 us @ 24 MHz (745 cycles) per interrupt, but doubles the size of the CPU register file
	ENABLE_IRQ_QREGS=False,	# Evidently the ARM register file IPs are called "two-port", but one port is read-only and the other is write-only. This means you need to write your own register file definition in HDL (remember that register x0 is always all '0's!)
	MASKED_IRQ=0x00000000,	# 32-bit IRQ mask. Any bit that is a '1' is a permanently disabled interrupt vector
	PROGADDR_IRQ=0x8090,	# TODO: Set this as the address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)
	lastRamMemorySlotSize=2048
)



# Extra memory sections
m.ExtraMemorySections = [
	('NPU0_RAM (rwx)', ': ORIGIN = 0x2C000, LENGTH = 0x4000', '/* END = 0x2FFFF, SIZE = 16 KiB */'),
	('AFE0_RAM (rwx)', ': ORIGIN = 0x30000, LENGTH = 0x2000', '/* END = 0x31FFF, SIZE = 8 KiB */'),
	('AFE1_RAM (rwx)', ': ORIGIN = 0x32000, LENGTH = 0x2000', '/* END = 0x33FFF, SIZE = 8 KiB */'),
	('AFE2_RAM (rwx)', ': ORIGIN = 0x34000, LENGTH = 0x2000', '/* END = 0x35FFF, SIZE = 8 KiB */'),
	('AFE3_RAM (rwx)', ': ORIGIN = 0x36000, LENGTH = 0x2000', '/* END = 0x37FFF, SIZE = 8 KiB */'),
	('AFE4_RAM (rwx)', ': ORIGIN = 0x38000, LENGTH = 0x2000', '/* END = 0x39FFF, SIZE = 8 KiB */'),
	('AFE5_RAM (rwx)', ': ORIGIN = 0x3A000, LENGTH = 0x2000', '/* END = 0x3BFFF, SIZE = 8 KiB */'),
	('DAC_PING_RAM (rwx)', ': ORIGIN = 0x3C000, LENGTH = 0x400', '/* END = 0x3C3FF, SIZE = 1 KiB */'),
	('DAC_PONG_RAM (rwx)', ': ORIGIN = 0x3C400, LENGTH = 0x400', '/* END = 0x3C7FF, SIZE = 1 KiB */'),
]



''' System '''
p = PeripheralTemplate(nameTemplate='SYSTEM', description='Controls the entire system, including the clocking and power state. Also has a CRC calculator using the CRC16_CDMA2000 polynomial.', latexIntroFileName='SYSTEM-intro-pingora2-2021-05.tex')
m.AddPeripheralTemplate(p)

# SYSCLK
r = RegisterTemplate(nameTemplate='SYSCLKCR', registerMemorySlot=0, description='System clock control register', size=16)
p.AddRegisterTemplate(r)

#r.AddBitField(BitField(name='CLKOSSEL', msb=15, lsb=13, description='CLKO pin output clock source select', accessibility='rw', valueDescriptions=[(0b000, 'CPU Clock', '_CPU'), (0b001, 'MCLK', '_MCLK'), (0b010, 'SMCLK', '_SMCLK'), (0b011, 'Low Frequency Crystal Clock', '_LFXT'), (0b100, 'High Frequency Crystal Clock', '_HFXT'), (0b101, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b110, 'Digitally Controlled Oscillator 1', '_DCO1')]))
#r.AddBitField(BitField(unused=True, msb=12))
r.AddBitField(BitField(unused=True, msb=15, lsb=12))
r.AddBitField(BitField(name='DCO1OFF', msb=11, description='Enables/disables the digitally controlled oscillator 1 (DCO1) clock. Cannot be disabled if it is being used as a source to the CPU clock or SMCLK, even if this bit is set to disable mode.', accessibility='rw', valueDescriptions=[(0b0, 'Enabled and Powered On'), (0b1, 'Disabled and Powered Down')]))
r.AddBitField(BitField(name='DCO0OFF', msb=10, description='Enables/disables the digitally controlled oscillator 0 (DCO0) clock. Cannot be disabled if it is being used as a source to the CPU clock or SMCLK, even if this bit is set to disable mode.', accessibility='rw', valueDescriptions=[(0b0, 'Enabled and Powered On'), (0b1, 'Disabled and Powered Down')]))
r.AddBitField(BitField(name='HFXTOFF', msb=9, description='Enables/disables the high frequency crystal clock. Cannot be disabled if it is being used as a source to the CPU clock or SMCLK, even if this bit is set to disable mode.', accessibility='rw', valueDescriptions=[(0b0, 'Enabled'), (0b1, 'Disabled')]))
r.AddBitField(BitField(name='LFXTOFF', msb=8, description='Enables/disables the low frequency crystal clock. Cannot be disabled if it is being used as a source to SMCLK, even if this bit is set to disable mode.', accessibility='rw', valueDescriptions=[(0b0, 'Enabled'), (0b1, 'Disabled')]))
#r.AddBitField(BitField(name='CPUOFF', msb=7, description='Enables/disables the CPU clock. This is the main vehicle for putting the CPU to sleep. The CPU clock (and the clock that the CPU clock is currently sourced from in MCLKSEL) is automatically enabled during interrupts, even if this bit is set to disable mode.', accessibility='rw', valueDescriptions=[(0b0, 'Enabled'), (0b1, 'Disabled')]))
r.AddBitField(BitField(unused=True, msb=7))
r.AddBitField(BitField(name='SMCLKOFF', msb=6, description='Enables/disables the submain clock. This is the main vehicle for putting the peripherals to sleep. The MCU is not aware of which peripherals are currently using SMCLK, and in consequence, setting this bit to disable mode will globally and absolutely shut down SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'Enabled'), (0b1, 'Disabled')]))
r.AddBitField(BitField(unused=True, msb=5))
r.AddBitField(BitField(name='SMCLKSEL', msb=4, lsb=3, description='Submain clock source select', accessibility='rw', valueDescriptions=[(0b00, 'High Frequency Crystal Clock', '_HFXT'), (0b01, 'Low Frequency Crystal Clock', '_LFXT'), (0b10, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b11, 'Digitally Controlled Oscillator 1', '_DCO1')]))
r.AddBitField(BitField(unused=True, msb=2))
r.AddBitField(BitField(name='MCLKSEL', msb=1, lsb=0, description='Main clock source select (also CPU clock source select)', accessibility='rw', valueDescriptions=[(0b00, 'High Frequency Crystal Clock', '_HFXT'), (0b01, 'Submain Clock', '_SMCLK'), (0b10, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b11, 'Digitally Controlled Oscillator 1', '_DCO1')]))

# CLKDIVCR
r = RegisterTemplate(nameTemplate='CLKDIVCR', registerMemorySlot=1, description='MCLK and SMCLK clock divider control register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='SMCLKDIV', msb=5, lsb=3, accessibility='rw', description='SMCLK clock division selection', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))
r.AddBitField(BitField(name='MCLKDIV', msb=2, lsb=0, accessibility='rw', description='MCLK clock division selection', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))

# MEMPWRCR
r = RegisterTemplate(nameTemplate='MEMPWRCR', registerMemorySlot=2, description='Memory power control register', size=16)
p.AddRegisterTemplate(r)

for i in reversed(range(2, 16)):
	sramName = 'SRAM' + '{:02}'.format(i)
	bfName = sramName + 'OFF'
	r.AddBitField(BitField(name=bfName, msb=i, description='Controls the power state of ' + sramName + '. When off, all memory in ' + sramName + ' becomes undefined, it no longer responds to read or write access, and leakage power consumption decreases.', accessibility='rw', valueDescriptions=[(0b0, 'Power on'), (0b1, 'Power off')]))
r.AddBitField(BitField(unused=True, msb=1))
r.AddBitField(BitField(name='ROMOFF', msb=0, description='Controls the power state of the boot ROM. When off, it no longer responds to read access, and leakage power consumption decreases.', accessibility='rw', valueDescriptions=[(0b0, 'Power on'), (0b1, 'Power off')]))

# CRCDATA
r = RegisterTemplate(nameTemplate='CRCDATA', registerMemorySlot=3, description='CRC input data register. Write the next byte of the data array to this register to continue calculating the CRC value of the data array.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CRCDATA', msb=7, lsb=0, accessibility='rw'))

# CRCSTATE
r = RegisterTemplate(nameTemplate='CRCSTATE', registerMemorySlot=4, description='CRC state register. Read this register to get the output of the CRC calculation. Write to this register to set the initial value of the CRC. Note that the value of this register is undefined during the time between when it is written to until when CRCDATA is written to.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CRCSTATE', msb=15, lsb=0, accessibility='rw'))

# IRQEN
r = RegisterTemplate(nameTemplate='IRQEN', registerMemorySlot=5, size=32, description='IRQ enable register. Each bit enables the associated IRQ when 1, and disables it when 0. The bit number corresponds to the IRQ vector number.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='IRQEN', msb=31, lsb=0, accessibility='rw'))

# IRQPRI
r = RegisterTemplate(nameTemplate='IRQPRI', registerMemorySlot=6, size=32, description='IRQ priority register. Each bit sets the associated IRQ to the higer priority tier when 0, and sets it to the lower priority tier when 0. The bit number corresponds to the IRQ vector number. IRQ priority is determined first by the value of IRQPRI and then by the IRQ vector order. An IRQ with an associated IRQPRI bit of 0 will always have higher priority than one with an IRQPRI bit of 1. If two IRQs have the same value of IRQPRI bits, then the one with the smaller IRQ vector number has greater priority.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='IRQPRI', msb=31, lsb=0, accessibility='rw'))

# WDTPASS
r = RegisterTemplate(nameTemplate='WDTPASS', registerMemorySlot=7, size=32, description='Watchdog timer password register. To unlock the WDTCR register for writing, first write 0x3FB0AD1C to WDTPASS. After that, the WDTCR register will be unlocked for 64 MCLK cycles during which it can be written to. Outside this time, any attempts to write to WDTCR will have no effect. To reset the watchdog timer counter, write 0xD6F402BC to WDTPASS. If the watchdog timer is enabled and reaches its maximum value determined by WDTCDIV, it will reset the system. Reading this register always yields 0.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='WDTPASS', msb=31, lsb=0, accessibility='w'))

# WDTCR
r = RegisterTemplate(nameTemplate='WDTCR', registerMemorySlot=8, size=8, description='Watchdog timer control register. This register is normally read-only, and must first be unlocked to write to it. To unlock the register, write 0x3FB0AD1C to the WDTPASS register. After that, the WDTCR register will be unlocked for write access for 64 MCLK cycles, and then return to being read-only.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='WDTREN', msb=0, accessibility='rw', description='Watchdog timer reset enable. The watchdog timer begins counting up from 0 immediately after being enabled, which is achieved by either setting WDTREN or WDTIE. If the watchdog timer is enabled and reaches its maximum value determined by WDTCDIV, it will reset the system. Disabling the watchdog timer also resets its internal counter.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='WDTIE', msb=1, accessibility='rw', description='Watchdog timer interrupt enable. The watchdog timer begins counting up from 0 immediately after being enabled, which is achieved by either setting WDTREN or WDTIE. When the watchdog timer interrupt is enabled, if the watchdog timer reaches its maximum value determined by WDTCDIV, then the SYSTEM interrupt will execute. Upon its return, the MCU will be reset if WDTREN is enabled. The SYSTEM IRQ must also be enabled in IRQEN.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='WDTCDIV', msb=5, lsb=2, accessibility='rw', description='Watchdog timer clock divider. Determines the number of MCLK cycles before the watchdog timer resets the system when enabled as 2^(WDTCDIV + 16)', valueDescriptions=[(0b0000, '/65,536', '_65536'), (0b0001, '/131,072', '_131072'), (0b0010, '/262,144', '_262144'), (0b0011, '/524,288', '_524288'), (0b0100, '/1,048,576', '_1048576'), (0b0101, '/2,097,152', '_2097152'), (0b0110, '/4,194,304', '_4194304'), (0b0111, '/8,388,608', '_8388608'), (0b1000, '/16,777,216', '_16777216'), (0b1001, '/33,554,432', '_33554432'), (0b1010, '/67,108,864', '_67108864'), (0b1011, '/134,217,728', '_134217728'), (0b1100, '/268,435,456', '_268435456'), (0b1101, '/536,870,912', '_536870912'), (0b1110, '/1,073,741,824', '_1073741824'), (0b1111, '/2,147,483,648', '_2147483648')]))
r.AddBitField(BitField(name='HWRST', msb=6, accessibility='w', description='Hardware reset. Write a 1 to this bit to perform a hardware reset of the system.', valueDescriptions=[(0b0, 'Does nothing'), (0b1, 'Systemwide hardware reset')]))
r.AddBitField(BitField(unused=True, msb=7))

# WDTSR
r = RegisterTemplate(nameTemplate='WDTSR', registerMemorySlot=9, size=8, description='Watchdog timer status register.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='WDTRF', msb=0, accessibility='rw1', description='Watchdog timer reset flag. Indicates that the previous systemwide reset was generated by the watchdog timer. To clear the bit, write a 1 to it.', valueDescriptions=[(0b0, 'Previous reset was not generated by the watchdog timer'), (0b1, 'Previous reset was generated by the watchdog timer')]))
r.AddBitField(BitField(name='WDTIF', msb=1, accessibility='rw1', description='Watchdog timer interrupt flag. Indicates that the watchdog timer has reached its maximum value, but the system has not yet been reset. To clear the bit, write a 1 to it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(unused=True, msb=7, lsb=2))

# WDTVAL
r = RegisterTemplate(nameTemplate='WDTVAL', registerMemorySlot=10, size=32, description='Watchdog timer value register. Contains the current value of the watchdog timer counter value. Reads as 0 if the watchdog timer is disabled.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='WDTVAL', msb=31, lsb=0, accessibility='r'))

# DCOx
for i in range(0, 2):
	prefix = 'DCO' + str(i)
	
	# DCOxFREQ
	r = RegisterTemplate(nameTemplate=prefix + 'FREQ', registerMemorySlot=(11 + 0 + (i * 1)), size=16, description=(prefix + ' non-stabilized frequency register (manual frequency adjustment)'))
	p.AddRegisterTemplate(r)

	r.AddBitField(BitField(unused=True, msb=15, lsb=12))
	r.AddBitField(BitField(name=(prefix + 'MFREQ'), msb=11, lsb=0, accessibility='rw', description='12-bit manual frequency adjustment'))

# TPMR
r = RegisterTemplate(nameTemplate='TPMR', registerMemorySlot=13, description='Analog and digital test port multiplexer register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=4))
r.AddBitField(BitField(name='TPMR', msb=3, lsb=0, description='Selects which analog front-end (AFE) to output on the ATP and DTP pins', accessibility='rw'))

# BIASCR
r = RegisterTemplate(nameTemplate='BIASCR', registerMemorySlot=14, size=16, description='Global bias and bandgap generator control register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=11))
r.AddBitField(BitField(name='EnBG', msb=10, accessibility='rw', description='Enables/disables the internal bandgap generator at 1.196 V', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='UseExtBias', msb=9, accessibility='rw', description='Enables/disables external bias voltages. Note that this bit does not enable or disable the internal bias generator or DACs. Those must be toggled separately.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='UseBiasDac', msb=8, accessibility='rw', description='Switches between using the bias generator voltages or bias DACs for the global bias voltages.', valueDescriptions=[(0b0, 'Uses bias generator'), (0b1, 'Uses DACs')]))
r.AddBitField(BitField(name='EnBiasBuf', msb=7, accessibility='rw', description='Enables/disables buffers on the internal global bias voltages.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='EnBiasGen', msb=6, accessibility='rw', description='Enables/disables the internal bias generator.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='BiasAdj', msb=5, lsb=0, accessibility='rw', description='Internal bias generator adjustment vector. Higher vector codes produce smaller currents. The nominal vector from simulation is decimal 37.'))

# BIASDBP
r = RegisterTemplate(nameTemplate='BIASDBP', registerMemorySlot=15, size=16, description='Global bias P DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=14))
r.AddBitField(BitField(name='BIASDBP', msb=13, lsb=0, accessibility='rw', description='DAC value'))

# BIASDBPC
r = RegisterTemplate(nameTemplate='BIASDBPC', registerMemorySlot=16, size=16, description='Global bias P cascode DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=14))
r.AddBitField(BitField(name='BIASDBPC', msb=13, lsb=0, accessibility='rw', description='DAC value'))

# BIASDBNC
r = RegisterTemplate(nameTemplate='BIASDBNC', registerMemorySlot=17, size=16, description='Global bias N cascode DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=14))
r.AddBitField(BitField(name='BIASDBNC', msb=13, lsb=0, accessibility='rw', description='DAC value'))

# BIASDBN
r = RegisterTemplate(nameTemplate='BIASDBN', registerMemorySlot=18, size=16, description='Global bias N DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=14))
r.AddBitField(BitField(name='BIASDBN', msb=13, lsb=0, accessibility='rw', description='DAC value'))

	
	
''' SPIx '''
p = PeripheralTemplate(nameTemplate='SPIx', description='Serial Peripheral Interface. Supports both master and slave modes. Note that SPI0 only supports master mode.', registerPrefix='SPIx', bitFieldPrefix='SPI', latexIntroFileName='SPI-intro-pingora2-2021-05.tex')
m.AddPeripheralTemplate(p)

# SPIxCR
r = RegisterTemplate(nameTemplate='SPIxCR', registerMemorySlot=0, description='SPI control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='SPIFEN', msb=19, accessibility='rw', description='SPI Flash enable. Allows native read-only memory access to the SPI flash memory attached to SPI0. (Only available on SPI0)', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='SPISM', msb=18, accessibility='rw', description='SPI slave mode (Note that SPI0 is master-only, and this bit is unavailable)', valueDescriptions=[(0b0, 'Master mode'), (0b1, 'Slave mode')]))
r.AddBitField(BitField(name='SPITXSB', msb=17, accessibility='rw', description='SPI TX swap bytes. Swaps the byte order in 16- and 32-bit transmissions. In 32-bit transmissions, bytes 3 and 0 are swapped and bytes 2 and 1 are swapped. In 16-bit transmissoins, bytes 1 and 0 are swapped. Does not affect 8-bit transmissions.', valueDescriptions=[(0b0, 'Bytes not reversed'), (0b1, 'Bytes reversed')]))
r.AddBitField(BitField(name='SPIRXSB', msb=16, accessibility='rw', description='SPI RX swap bytes. Swaps the byte order in 16- and 32-bit receptions. In 32-bit receptions, bytes 3 and 0 are swapped and bytes 2 and 1 are swapped. In 16-bit receptions, bytes 1 and 0 are swapped. Does not affect 8-bit receptions.', valueDescriptions=[(0b0, 'Bytes not reversed'), (0b1, 'Bytes reversed')]))
r.AddBitField(BitField(name='SPIBR', msb=15, lsb=8, description='SPI clock (SCK) baud control for master mode. Baud rate = SMCLK / (2 * (1 + SPIBR))', accessibility='rw'))
r.AddBitField(BitField(name='SPIEN', msb=7, description='SPI enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='SPIMSB', msb=6, description='Endianness select', accessibility='rw', valueDescriptions=[(0b0, 'LSB-first'), (0b1, 'MSB-first')]))
r.AddBitField(BitField(name='SPITCIE', msb=5, description='SPI transmit complete interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SPITEIE', msb=4, description='SPI transmit register empty interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SPIDL', msb=3, lsb=2, description='SPI transmission data length select', accessibility='rw', valueDescriptions=[(0b00, '8-bit transfers', '_8'), (0b01, '16-bit transfers', '_16'), (0b10, '32-bit transfers', '_32')]))
r.AddBitField(BitField(name='SPICPOL', msb=1, description='SPI clock (SCK) polarity', accessibility='rw', valueDescriptions=[(0b0, 'SCK idles low, leading edge is a rising edge (for SPIMODE0 or SPIMODE1)'), (0b1, 'SCK idles high, leading edge is a falling edge (for SPIMODE2 or SPIMODE3)')]))
r.AddBitField(BitField(name='SPICPHA', msb=0, description='SPI clock (SCK) phase. Note that in slave mode, only SPICPHA = 1 is supported, and this bit becomes a don\'t care.', accessibility='rw', valueDescriptions=[(0b0, 'Data is sampled on leading edge of SCK, data is updated on trailing edge of SCK (for SPIMODE0 or SPIMODE2)'), (0b1, 'Data is updated on leading edge of SCK, data is sampled on trailing edge of SCK (for SPIMODE1 or SPIMODE3)')]))

# SPIxSR
r = RegisterTemplate(nameTemplate='SPIxSR', registerMemorySlot=1, description='SPI status register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=3, unused=True))
r.AddBitField(BitField(name='SPIBUSY', msb=2, description='Indicates if a SPI transfer is occurring or not. When in slave mode, this bit is set whenever the chip select pin is asserted (driven low).', accessibility='r', valueDescriptions=[(0b0, 'A SPI transfer is not presently occurring'), (0b1, 'A SPI transfer is presently occurring')]))
r.AddBitField(BitField(name='SPITCIF', msb=1, description='SPI transfer complete interrupt flag. This bit is set when a SPI transfer has completed, and must be cleared in software before it can be set again. To clear the bit, write a 1 to it or read the SPIxRX register.', accessibility='rw1', valueDescriptions=[(0b0, 'A SPI transfer has not been completed'), (0b1, 'A SPI transfer has been completed (must be cleared before it can be set again)')]))
r.AddBitField(BitField(name='SPITEIF', msb=0, description='SPI transmit register empty interrupt flag. This bit is set when the SPI transmit register SPIxTX is empty, and indicates SPIxTX is ready to accept new data for the next transfer (though the new data will not be transmitted until a current transfer is complete). Must be cleared in software before it can be set again. To clear the bit, write a 1 to it.', accessibility='rw1', valueDescriptions=[(0b0, 'SPIxTX is not empty'), (0b1, 'SPIxTX is empty and ready for new data (must be cleared before it can be set again)')]))

# SPIxTX
r = RegisterTemplate(nameTemplate='SPIxTX', registerMemorySlot=2, description='SPI transmit buffer register. In master mode, write to this register to begin a SPI transfer. In slave mode, write to this register to queue the data to transmit during the next transfer, which will be initiated by the master.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SPIxTX', msb=31, lsb=0, accessibility='rw'))

# SPIxRX
r = RegisterTemplate(nameTemplate='SPIxRX', registerMemorySlot=3, description='SPI receive buffer register. The received SPI data will appear in this register after each SPI transfer is complete.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SPIxRX', msb=31, lsb=0, accessibility='r'))

# SPIxFOS
r = RegisterTemplate(nameTemplate='SPIxFOS', registerMemorySlot=4, description='SPI Flash memory address offset. This value is added to the 24-bit SPI Flash address, wrapping around back to 0 after 0x00FFFFFF. This can be used to create a virtual address for a file in the SPI Flash to make it appear at that address. (Only available in SPI0).', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=24, unused=True))
r.AddBitField(BitField(name='SPIxFOS', msb=23, lsb=0, accessibility='r'))



''' GPIOx '''
p = PeripheralTemplate(nameTemplate='GPIOx', description='General Purpose Input Output', registerPrefix='Px', bitFieldPrefix='Px', latexIntroFileName='GPIO-intro-2020-05.tex')
m.AddPeripheralTemplate(p)

# PxIN
r = RegisterTemplate(nameTemplate='PxIN', registerMemorySlot=0, description='GPIO read pin register. Each bit corresponds to the input logic state of the GPIO pin of the same number at the time of the memory access reading this register (not synchronized to any clock). Reading a 0 in a bit indicates a logic low pin state; reading a 1 indicates a logic high state.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIN', msb=31, lsb=0, accessibility='r'))

# PxOUT
r = RegisterTemplate(nameTemplate='PxOUT', registerMemorySlot=1, description='GPIO output drive register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is set to GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to make the corresponding pin output a logic low value; write a 1 to output a logic high value.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUT', msb=31, lsb=0, accessibility='rw'))

# PxOUTS
r = RegisterTemplate(nameTemplate='PxOUTS', registerMemorySlot=2, description='GPIO output drive set register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to set the corresponding pin (make the pin output a logic high value). Writing a 0 has no effect. Reading this register is equivalent to reading the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTS', msb=31, lsb=0, accessibility='rw1'))

# PxOUTC
r = RegisterTemplate(nameTemplate='PxOUTC', registerMemorySlot=3, description='GPIO output drive clear register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to clear the corresponding pin (make the pin output a logic low value). Writing a 0 has no effect. Reading this register yields the inversion of the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTC', msb=31, lsb=0, accessibility='rw1'))

# PxOUTT
r = RegisterTemplate(nameTemplate='PxOUTT', registerMemorySlot=4, description='GPIO output drive toggle register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to toggle the corresponding pin (make the pin output a logic low value). Writing a 0 has no effect. Reading this register is equivalent to reading the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTT', msb=31, lsb=0, accessibility='rw1'))

# PxDIR
r = RegisterTemplate(nameTemplate='PxDIR', registerMemorySlot=5, description='GPIO pin direction register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to set the corresponding pin to input mode; write a 1 to set to output mode.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxDIR', msb=31, lsb=0, accessibility='rw'))

# PxIFG
r = RegisterTemplate(nameTemplate='PxIFG', registerMemorySlot=6, description='GPIO interrupt flag register. Each bit corresponds to the GPIO pin of the same number. Reading a 0 in a bit indicates there is no pending interrupt for the corresponding pin; reading a 1 indicates there is a new interrupt pending for the corresponding pin. Write a 1 to each bit for which you wish to clear the interrupt flag.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIFG', msb=31, lsb=0, accessibility='rw1'))

# PxIES
r = RegisterTemplate(nameTemplate='PxIES', registerMemorySlot=7, description='GPIO interrupt edge select register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to set the corresponding pin interrupt rising edge triggering; write a 1 to set to falling edge triggering.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIES', msb=31, lsb=0, accessibility='rw'))

# PxIE
r = RegisterTemplate(nameTemplate='PxIE', registerMemorySlot=8, description='GPIO interrupt enable register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin interrupt; write a 1 to enable the pin interrupt.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIE', msb=31, lsb=0, accessibility='rw'))

# PxSEL
r = RegisterTemplate(nameTemplate='PxSEL', registerMemorySlot=9, description='GPIO peripheral select register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to set the corresponding pin to GPIO (primary) mode; write a 1 to set the pin to secondary function (peripheral) mode. When a pin is in secondary function (peripheral) mode, the governing peripheral takes control of the pin ouput, direction, resistor enable, and open-collector enable states, and the PxOUT, PxDIR, and PxREN have no effect on the pin. Note that pin interrupts are still available when in secondary function (peripheral) mode in addition to any interrupts the secondary function/peripheral may generate. Also note that not all pins necessarily have a secondary function; in this case, if the corresponding bit in PxSEL is set to 1, the pin will be configured as an input with the pullup resistor disabled and the open-collector mode disabled.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxSEL', msb=31, lsb=0, accessibility='rw'))

# PxREN
r = RegisterTemplate(nameTemplate='PxREN', registerMemorySlot=10, description='GPIO resistor enable register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin pullup resistor; write a 1 to enable the pin pullup resistor.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxREN', msb=31, lsb=0, accessibility='rw'))

## PxOCEN
#r = RegisterTemplate(nameTemplate='PxOCEN', registerMemorySlot=10, description='GPIO open collector register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin open-collector mode; write a 1 to enable the pin open-collector mode.', size=32)
#p.AddRegisterTemplate(r)



''' UARTx '''
p = PeripheralTemplate(nameTemplate='UARTx', description='Full-duplex Universal Asynchronous Receiver/Transmitter serial port', registerPrefix='UARTx', bitFieldPrefix='U', latexIntroFileName='UART-intro-2020-05.tex')
m.AddPeripheralTemplate(p)

# UARTxCR
r = RegisterTemplate(nameTemplate='UARTxCR', registerMemorySlot=0, description='UART control register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='UEN', msb=5, description='UART enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='UPEN', msb=4, description='UART parity enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='UPODD', msb=3, description='UART parity select', accessibility='rw', valueDescriptions=[(0b0, 'Even parity'), (0b1, 'Odd parity')]))
r.AddBitField(BitField(name='URCIE', msb=2, description='UART receive complete interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='UTEIE', msb=1, description='UART transmit register empty interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='UTCIE', msb=0, description='UART transmit complete interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))

# UARTxSR
r = RegisterTemplate(nameTemplate='UARTxSR', registerMemorySlot=1, description='UART status register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='URBF', msb=7, description='UART receiver busy flag', accessibility='r', valueDescriptions=[(0b0, 'Receiver idle and ready for new reception'), (0b1, 'Receiver busy with ongoing reception')]))
r.AddBitField(BitField(name='UTBF', msb=6, description='UART transmitter busy flag', accessibility='r', valueDescriptions=[(0b0, 'Transmitter idle and ready for new transmission'), (0b1, 'Transmitter busy with ongoing transmission')]))
r.AddBitField(BitField(name='UFEF', msb=5, description='UART framing error flag. Read UARTxRX to clear.', accessibility='r', valueDescriptions=[(0b0, 'No framing error'), (0b1, 'Framing error on last reception')]))
r.AddBitField(BitField(name='UPEF', msb=4, description='UART parity error flag. Read UARTxRX to clear.', accessibility='r', valueDescriptions=[(0b0, 'No parity error'), (0b1, 'Parity error on last reception')]))
r.AddBitField(BitField(name='UOVF', msb=3, description='UART receive data overflow flag. Read UARTxRX to clear.', accessibility='r', valueDescriptions=[(0b0, 'No receive data overrun'), (0b1, 'Receive data overflow on last reception')]))
r.AddBitField(BitField(name='URCIF', msb=2, description='UART receive complete interrupt flag. Read UARTxRX to clear.', accessibility='r', valueDescriptions=[(0b0, 'No new receive complete interrupt pending'), (0b1, 'New receive complete interrupt pending')]))
r.AddBitField(BitField(name='UTEIF', msb=1, description='UART transmit register empty interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No new transmit register empty interrupt pending'), (0b1, 'New transmit register empty interrupt pending')]))
r.AddBitField(BitField(name='UTCIF', msb=0, description='UART transmit complete interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No new transmit complete interrupt pending'), (0b1, 'New transmit complete interrupt pending')]))

# UARTxBR
r = RegisterTemplate(nameTemplate='UARTxBR', registerMemorySlot=2, description='UART baud rate register', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=12, unused=True))
r.AddBitField(BitField(name='UBR', msb=11, lsb=0, description='UART baud rate = SMCLK / (16 * (UBR + 1))', accessibility='rw'))

# UARTxRX
r = RegisterTemplate(nameTemplate='UARTxRX', registerMemorySlot=3, description='UART receive buffer register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='UARTxRX', msb=7, lsb=0, accessibility='r'))

# UARTxTX
r = RegisterTemplate(nameTemplate='UARTxTX', registerMemorySlot=4, description='UART transmit buffer register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='UARTxTX', msb=7, lsb=0, accessibility='rw'))



''' TIMERx '''
p = PeripheralTemplate(nameTemplate='TIMERx', description='32-bit Timer/Counter with input capture, compare, and pulse-width modulation functionality', registerPrefix='TIMx', bitFieldPrefix='TIM', latexIntroFileName='TIMER-intro-2020-05.tex')
m.AddPeripheralTemplate(p)

# TIMxCR
r = RegisterTemplate(nameTemplate='TIMxCR', registerMemorySlot=0, description='Timer/Counter control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='TIMDIV', msb=19, lsb=16, description='Timer/Counter clock divider. Divides the clock source selected by TIMSSEL to produce each increment to TIMxVAL', accessibility='rw', valueDescriptions=[(0, '/1 (no division)', '_1'), (1, '/2', '_2'), (2, '/4', '_4'), (3, '/8', '_8'), (4, '/16', '_16'), (5, '/32', '_32'), (6, '/64', '_64'), (7, '/128', '_128'), (8, '/256', '_256'), (9, '/512', '_512'), (10, '/1,024', '_1024'), (11, '/2,048', '_2048'), (12, '/4,096', '_4096'), (13, '/8,192', '_8192'), (14, '/16,384', '_16384'), (15, '/32,768', '_32768')]))
r.AddBitField(BitField(name='TIMCMP1IH', msb=15, description='Compare 1 TxCMP1 initial PWM logic state', accessibility='rw', valueDescriptions=[(0b0, 'Initial PWM logic state LOW'), (0b1, 'Initial PWM logic state HIGH')]))
r.AddBitField(BitField(name='TIMCMP0IH', msb=14, description='Compare 0 TxCMP0 initial PWM logic state', accessibility='rw', valueDescriptions=[(0b0, 'Initial PWM logic state LOW'), (0b1, 'Initial PWM logic state HIGH')]))
r.AddBitField(BitField(name='TIMCAP1FE', msb=13, description='Capture 1 edge select', accessibility='rw', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='TIMCAP0FE', msb=12, description='Capture 0 edge select', accessibility='rw', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='TIMCAP1EN', msb=11, description='Capture 1 enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMCAP0EN', msb=10, description='Capture 0 enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMSSEL', msb=9, lsb=8, description='Timer/Counter clock source select', accessibility='rw', valueDescriptions=[(0b00, 'SMCLK', '_SMCLK'), (0b01, 'MCLK', '_MCLK'), (0b10, 'Low frequency crystal clock', '_LFXT'), (0b11, 'High frequency crystal clock', '_HFXT')]))
r.AddBitField(BitField(name='TIMCMP2RST', msb=7, description='Enable Timer/Counter reset on Compare 2 event', accessibility='rw', valueDescriptions=[(0b0, 'Does not reset Timer/Counter on Compare 2 event'), (0b1, 'Resets Timer/Counter on Compare 2 event')]))
r.AddBitField(BitField(name='TIMEN', msb=6, description='Timer/Counter enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMCAP1IE', msb=5, description='Capture 1 interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMCAP0IE', msb=4, description='Capture 0 interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMOVIE', msb=3, description='Timer/Counter overflow interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMCMP2IE', msb=2, description='Compare 2 interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMCMP1IE', msb=1, description='Compare 1 interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='TIMCMP0IE', msb=0, description='Compare 0 interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))

# TIMxSR
r = RegisterTemplate(nameTemplate='TIMxSR', registerMemorySlot=1, description='Timer/Counter status register.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TCMP1', msb=7, description='Current value of the Compare 1 pin TxCMP1', accessibility='r', valueDescriptions=[(0b0, 'LOW'), (0b1, 'HIGH')]))
r.AddBitField(BitField(name='TCMP0', msb=6, description='Current value of the Compare 0 pin TxCMP0', accessibility='r', valueDescriptions=[(0b0, 'LOW'), (0b1, 'HIGH')]))
r.AddBitField(BitField(name='TIMCAP1IF', msb=5, description='Capture 1 interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='TIMCAP0IF', msb=4, description='Capture 0 interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='TIMOVIF', msb=3, description='Timer/Counter overflow interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='TIMCMP2IF', msb=2, description='Compare 2 interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='TIMCMP1IF', msb=1, description='Compare 1 interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='TIMCMP0IF', msb=0, description='Compare 0 interrupt flag. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))

# TIMxVAL
r = RegisterTemplate(nameTemplate='TIMxVAL', registerMemorySlot=2, description='Timer/Counter value register. Read to get the number of cycles of the divided down source clock since the timer was reset or enabled. Write to set an arbitrary starting point for the Timer/Counter.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TIMxVAL', msb=31, lsb=0, accessibility='rw'))

# TIMxCMP0
r = RegisterTemplate(nameTemplate='TIMxCMP0', registerMemorySlot=3, description='Timer/Counter Compare 0 comparison register. When Compare 0 is enabled, a Compare 0 event will be triggered when TIMxVAL equals TIMxCMP0.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TIMxCMP0', msb=31, lsb=0, accessibility='rw'))

# TIMxCMP1
r = RegisterTemplate(nameTemplate='TIMxCMP1', registerMemorySlot=4, description='Timer/Counter Compare 1 comparison register. When Compare 1 is enabled, a Compare 1 event will be triggered when TIMxVAL equals TIMxCMP1.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TIMxCMP1', msb=31, lsb=0, accessibility='rw'))

# TIMxCMP2
r = RegisterTemplate(nameTemplate='TIMxCMP2', registerMemorySlot=5, description='Timer/Counter Compare 2 comparison register. When Compare 2 is enabled, a Compare 2 event will be triggered when TIMxVAL equals TIMxCMP2.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TIMxCMP2', msb=31, lsb=0, accessibility='rw'))

# TIMxCAP0
r = RegisterTemplate(nameTemplate='TIMxCAP0', registerMemorySlot=6, description='Timer/Counter Capture 0 value register. When Capture 0 is enabled and a Capture 0 event occurs, this register will latch the value of TIMxVAL.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TIMxCAP0', msb=31, lsb=0, accessibility='rw'))

# TIMxCAP1
r = RegisterTemplate(nameTemplate='TIMxCAP1', registerMemorySlot=7, description='Timer/Counter Capture 1 value register. When Capture 1 is enabled and a Capture 1 event occurs, this register will latch the value of TIMxVAL.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TIMxCAP1', msb=31, lsb=0, accessibility='rw'))



''' I2Cx '''
i2cDescription = 'I2C serial port interface. The master and slave I2C interfaces are split between two sets of registers.\n\n'
i2cDescription += 'To use master transmitter mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (0 for write/master transmitter) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, send the slave a byte of data by writing the desired data to I2CxMTX. When the I2C peripheral is ready for another byte of data to be queued for transmission, the I2CMTXE flag will be set. Again, wait for I2CMXC or I2CMARB, then check I2CMARB and I2CMNR, and finally clear the status register. Once finished sending all of the desired bytes, either send a stop condition to release control of the bus by setting I2CMSP, or send a repeated start condition to retain control of the bus with a new transmission (and possibly a new slave and read/write mode) by setting I2CMST. Once a stop condition is sent, wait for I2CMSTS to be set, indicating that a stop condition has been sent. Clear the status register.\n\n'
i2cDescription += 'To use master receiver mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (1 for read/master receiver) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, begin to receive a byte of data from the slave by setting I2CMRB. Wait for I2CMXC to be set. Clear the status register. Read I2CxMRX to get the byte of data received from the slave. To send the slave an ACK and begin to read another byte from the slave, set I2CMRB. Or, to send the slave a NACK and send a stop condition, set I2CMSP. Or, to send the slave a NACK and send a repeated start condition, set I2CMST. Wait for the appropriate flag, then clear the status register.\n\n'
i2cDescription += 'To use slave receiver mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Note that if I2CGCE is set, the I2C peripheral will be addressed if either its address is received or if the general call is received. Wait for the I2C peripheral to be addressed when I2CSA is set. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (0 indicates slave receiver). Clear the status register. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for the slave to receive a data byte from the master when I2CSXC is set. If I2CSOVF is set, then the MCU has failed to read one of the bytes sent by the master in the past. Clear the status register, and then read I2CSRX to get the data byte sent from the master. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for I2CSXC, I2CSPR, or I2CSTR to be set, indicating the I2C peripheral has received a new byte of data, a stop condition, or a repeated start condition. If a stop or start condition has been received, clear the status register.\n\n'
i2cDescription += 'To use slave transmitter mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (1 indicates slave transmitter). Clear the status register. Queue the byte of data to transmit to the master by writing the byte to I2CSTX. If clock stretching is enabled, set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Wait for I2CSTXE to be set, indicating that the I2C peripheral is ready to queue the next byte to send to the master. Clear the status register, and write the next byte to send to the master to I2CxSTX. If clock stretching is enabled, wait for I2CSXC to be set, clear the status register, and set I2CSC. Wait for I2CSTXE, I2CSPR, or I2CSTR to be set, then clear the status register.'
p = PeripheralTemplate(nameTemplate='I2Cx', description=i2cDescription, registerPrefix='I2Cx', bitFieldPrefix='I2C')
m.AddPeripheralTemplate(p)

# I2CxCR
r = RegisterTemplate(nameTemplate='I2CxCR', registerMemorySlot=0, description='I2C control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CSPRIE', msb=0, accessibility='rw', description='I2C stop received interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSTRIE', msb=1, accessibility='rw', description='I2C start received interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMXCIE', msb=2, accessibility='rw', description='I2C master transfer complete interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMNRIE', msb=3, accessibility='rw', description='I2C master mode NACK received interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMTXEIE', msb=4, accessibility='rw', description='I2C master transmit register empty interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMARBIE', msb=5, accessibility='rw', description='I2C master mode arbitration error interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMSPSIE', msb=6, accessibility='rw', description='I2C master mode stop condition sent interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMSTSIE', msb=7, accessibility='rw', description='I2C master mode start condition sent interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSXCIE', msb=8, accessibility='rw', description='I2C slave mode transfer complete interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSNRIE', msb=9, accessibility='rw', description='I2C slave mode NACK received from master interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSOVFIE', msb=10, accessibility='rw', description='I2C slave receive register overflow interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSTXEIE', msb=11, accessibility='rw', description='I2C slave transmit register empty interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSAIE', msb=12, accessibility='rw', description='I2C slave mode addressed interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMDIV', msb=16, lsb=13, accessibility='rw', description='I2C master mode clock divider. The master mode finite state machine clock source is SMCLK, which is divided by a factor of 4 * 2**I2CMDIV.', valueDescriptions=[(0, '/1 (no division)', '_1'), (1, '/2', '_2'), (2, '/4', '_4'), (3, '/8', '_8'), (4, '/16', '_16'), (5, '/32', '_32'), (6, '/64', '_64'), (7, '/128', '_128'), (8, '/256', '_256'), (9, '/512', '_512'), (10, '/1,024', '_1024'), (11, '/2,048', '_2048'), (12, '/4,096', '_4096'), (13, '/8,192', '_8192'), (14, '/16,384', '_16384'), (15, '/32,768', '_32768')]))
r.AddBitField(BitField(name='I2CGCE', msb=17, accessibility='rw', description='I2C slave general call enable. When enabled, this slave will be addressed if a global call is issued on the bus.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='I2CSCS', msb=18, accessibility='rw', description='I2C slave clock stretching enable. When enabled, this slave will hold the SCL line low during the ACK phase of the transmission to allow this slave more time. Note that the master will be left waiting for the ACK/NACK as long as this bit is set to 1.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='I2CSN', msb=19, accessibility='rw', description='I2C slave NACK next byte received. When enabled, this slave will reply with a NACK whenever it receives its address or whenever it receives a byte from a master. When disabled, it will send an ACK in those situations. If clock stretching is enabled, this bit can be changed in accordance with the desired ACK/NACK reply before allowing a rising edge of SCL.', valueDescriptions=[(0b0, 'ACK'), (0b1, 'NACK')]))
r.AddBitField(BitField(name='I2CSEN', msb=20, accessibility='rw', description='I2C slave enable. When enabled, this device behaves as an I2C slave and begins listening for its address. If master mode is also enabled on this device, then this device will act as a slave until commanded to send a start condition with I2CMST, whereupon it will begin acting as a master. Once the master transfer is complete, it will resume acting as a slave.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='I2CMEN', msb=21, accessibility='rw', description='I2C master enable. When enabled, this device awaits a command to send a start condition with I2CMST, and then begins acting as a master until commanded to send a stop condition with I2CMSP. If master mode is also enabled on this device, then this device will act as a slave until commanded to send a start condition with I2CMST, whereupon it will begin acting as a master. Once the master transfer is complete, it will resume acting as a slave.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(msb=31, lsb=22, unused=True))

# I2CxFCR
r = RegisterTemplate(nameTemplate='I2CxFCR', registerMemorySlot=1, description='I2C flow control register. Writing a 1 to a bit in this register initiates or queues the associated command. Writing a 0 to a bit does nothing. Reading this register always returns the value 0.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CMRB', msb=0, accessibility='w1', description='I2C master read byte command. Set this bit to 1 while in master receiver mode to read one byte from the slave. This master is required to have already sent the slave address and received an ACK from the slave before initiating this command.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Read next byte')]))
r.AddBitField(BitField(name='I2CMSP', msb=1, accessibility='w1', description='I2C master send stop condition command. Set this bit to 1 while this master is in control of the bus to send a stop condition. This master is required to have already sent a start condition and at least one address frame before initiating this command. If this master is busy with a transaction when this bit is set, then it will send the stop condition immediately after it finishes the transaction.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Send a stop condition')]))
r.AddBitField(BitField(name='I2CMST', msb=2, accessibility='w1', description='I2C master send start condition command. Set this bit to 1 to send a start condition or a repeated start condition. Once this bit is set, this master is required to send at least one address frame before initiating this command again. If another master has control of the bus when this bit is set, this master will wait until the bus is idle before seizing control of it and sending the start condition. If this master is busy with a transaction when this bit is set, then it will send a restart condition immediately after it finishes the transaction.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Send a start condition')]))
r.AddBitField(BitField(name='I2CSC', msb=3, accessibility='w1', description='I2C slave continue command. When clock stretching is enabled in slave mode, set this bit to tell the slave to continue with the ACK/NACK phase of the current byte by releasing SCL. This may only be set if clock stretching is enabled, slave mode is enabled, and the slave transfer complete flag has just been set.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Send a start condition')]))
r.AddBitField(BitField(msb=7, lsb=4, unused=True))

# I2CxSR
r = RegisterTemplate(nameTemplate='I2CxSR', registerMemorySlot=2, description='I2C status register', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CSPR', msb=0, accessibility='rw1', description='I2C stop condition received interrupt flag. This flag is set whenever a stop condition condition is detected on the bus, regardless of which device sent it. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSTR', msb=1, accessibility='rw1', description='I2C start condition received interrupt flag. This flag is set whenever a start condition or repeated start condition is detected on the bus, regardless of if this master or another sent it. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMXC', msb=2, accessibility='rw1', description='I2C master transfer complete interrupt flag. In master transmitter mode, this flag is set after this master has sent the data byte and the slave has sent an ACK/NACK. In master receiver mode, this flag is set after the slave has sent the data byte and before this master sends an ACK/NACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMNR', msb=3, accessibility='rw1', description='I2C master mode NACK received interrupt flag. This flag is set in master transmitter mode after ACK/NACK bit is sent if the slave sends a NACK. It is not set if the slave sends an ACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMTXE', msb=4, accessibility='rw1', description='I2C master transmit register empty interrupt flag. This bit is set when this master latches the data stored in the master transmit register to indicate that the master transmit register is ready to accept another byte and queue it for transmission. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMARB', msb=5, accessibility='rw1', description='I2C master mode arbitration loss interrupt flag. This bit is set when this master detects that the value it tried to write to SDA is being overridden by another master. After it detects the arbitration loss, this master releases control of the bus. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMSPS', msb=6, accessibility='rw1', description='I2C master mode stop condition sent interrupt flag. This flag is set after this master sends a stop condition. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMSTS', msb=7, accessibility='rw1', description='I2C master mode start condition sent interrupt flag. This flag is set after this master sends a start condition or repeated start condition. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSXC', msb=8, accessibility='rw1', description='I2C slave mode transfer complete interrupt flag. This bit is set after this slave receives a byte of data from a master, but before this slave sends an ACK/NACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSNR', msb=9, accessibility='rw1', description='I2C slave mode NACK received from master interrupt flag. This bit is set in slave transmitter mode if the master responds with a NACK after this slave sends it a byte of data. This bit is not set if the master responds with an ACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSOVF', msb=10, accessibility='rw1', description='I2C slave receive register overflow interrupt flag. Indicates that this slave has failed to read one or more bytes from the I2CxSRX register before they were overwritten by another transmission. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSTXE', msb=11, accessibility='rw1', description='I2C slave transmit register empty interrupt flag. This bit is set when this slave latches the data stored in the masslaveter transmit register to indicate that the slave transmit register is ready to accept another byte and queue it for transmission. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSA', msb=12, accessibility='rw1', description='I2C slave mode addressed interrupt flag. Indicates that this slave has been addressed by another master. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSTM', msb=13, accessibility='r', description='I2C slave transmitter mode indicator. Indicates for which mode this slave has been addressed. Only valid if I2CSA is 1. This bit cannot be cleared by writing to the status register.', valueDescriptions=[(0b0, 'Slave receiver mode'), (0b1, 'Slave transmitter mode')]))
r.AddBitField(BitField(name='I2CMCB', msb=14, accessibility='r', description='I2C master controls bus indicator. This bit cannot be cleared by writing to the status register.', valueDescriptions=[(0b0, 'This master does not control the bus'), (0b1, 'This master controls the bus')]))
r.AddBitField(BitField(name='I2CBS', msb=15, accessibility='r', description='I2C bus state indicator. This bit cannot be cleared by writing to the status register.', valueDescriptions=[(0b0, 'The I2C bus is idle'), (0b1, 'The I2C bus is active')]))

# I2CxMTX
r = RegisterTemplate(nameTemplate='I2CxMTX', registerMemorySlot=3, description='I2C master transmit register. Write the desired slave address and read/write bit to this register after sending a start condition to begin a transmission with a slave. Note that the desired slave address must occupy the upper seven bits and the read/write bit must occupy the least significant bit. If the read bit is 0, the master enters master transmitter mode. If the read bit is 1, the master enters master receiver mode. Write a byte of data to this register after sending the address frame or a data frame to send that byte of data to the slave. If this master is busy with a transmission when this register is written, it will send the byte after it finishes the transmission.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxMTX', msb=7, lsb=0, accessibility='rw'))

# I2CxMRX
r = RegisterTemplate(nameTemplate='I2CxMRX', registerMemorySlot=4, description='I2C master receive register. When in master receiver mode, read this register after the master transfer complete interrupt flag (I2CMXC) is set to get the received data byte.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxMRX', msb=7, lsb=0, accessibility='r'))

# I2CxSTX
r = RegisterTemplate(nameTemplate='I2CxSTX', registerMemorySlot=5, description='I2C slave transmit register. When in slave transmitter mode, write to this register after the slave addressed flag (I2CSA) or the slave transaction complete flag (I2CSXC) has been set to queue the next byte to send to the master.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxSTX', msb=7, lsb=0, accessibility='rw'))

# I2CxSRX
r = RegisterTemplate(nameTemplate='I2CxSRX', registerMemorySlot=6, description='I2C slave receive register. When in slave receiver mode, read this register after the slave transaction complete flag (I2CSXC) has been set to get the data byte sent from the master. Note that if this slave fails to clear the status register before another byte is received, the slave receive overflow flag (I2CSOVF) will be set.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxSRX', msb=7, lsb=0, accessibility='r'))

# I2CxAR
r = RegisterTemplate(nameTemplate='I2CxAR', registerMemorySlot=7, description='I2C this slave address register. When in slave mode, any master that sends an address frame containing this address will activate this slave.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxAR', msb=6, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=7, unused=True))

# I2CxAMR
r = RegisterTemplate(nameTemplate='I2CxAMR', registerMemorySlot=8, description='I2C this slave address mask register. Any bit set to 1 in this register indicates that the corresponding bit in the slave address register is a wildcard. Only the slave address register bits that correspond to 0s in this register will be compared to the received slave address.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxAMR', msb=6, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=7, unused=True))

''' NNx '''
p = PeripheralTemplate(nameTemplate='NNx', description='Fixed point artificial neural network hardware accelerator. The peripheral calculates a single layer of a multilayer perceptron neural network. The input is a vector of signed Q0.15 integers (signed int16), and the output is a vector of signed Q0.15 integers (signed int16), and the weights are 24-bit signed Q8.15 numbers (signed int24). It can be configured to use a linear activation function or a logistic sigmoid approximation activation function. The input vector, output vector, and weights must all fit inside a single 16 KiB multiplexed SRAM.', registerPrefix='NNx', bitFieldPrefix='NN')
m.AddPeripheralTemplate(p)

# NNxCR
r = RegisterTemplate(nameTemplate='NNxCR', registerMemorySlot=0, description='Neural network control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=23, unused=True))
r.AddBitField(BitField(name='NNCIE', msb=22, description='Neural network layer complete interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='NNCIF', msb=21, description='Neural network layer complete interrupt flag. Write a 0 to clear the flag.', accessibility='rw0', valueDescriptions=[(0b0, 'No interrupt pending'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='NNLSIS', msb=20, description='Logistic sigmoid input select. Used for testing the hardware logistic sigmoid approximation activation function.', accessibility='rw', valueDescriptions=[(0b0, 'Internal input (required for neural network usage)'), (0b1, 'Input is NNxLSI (used for testing)')]))
r.AddBitField(BitField(name='NNCS', msb=19, description='Neural network clock select', accessibility='rw', valueDescriptions=[(0b0, 'SMCLK'), (0b1, 'MCLK')]))
r.AddBitField(BitField(name='NNBIAS', msb=18, description='Neural network layer bias enable, used to insert a bias from the synaptic weights into the input of the activation function', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='NNAFS', msb=17, description='Activation function select', accessibility='rw', valueDescriptions=[(0b0, 'Logistic sigmoid approximation'), (0b1, 'Linear')]))
r.AddBitField(BitField(name='NNRUN', msb=16, description='Neural network run. Set to start the neural network accelerator process. Read to determine if the neural network accelerator is running or not.', accessibility='rw1', valueDescriptions=[(0b0, 'Not running'), (0b1, 'Running (write 1 to start)')]))
r.AddBitField(BitField(name='NNO', msb=15, lsb=8, description='Number of neural network outputs in output vector minus 1. The actual number of outputs is NNO + 1', accessibility='rw'))
r.AddBitField(BitField(name='NNI', msb=7, lsb=0, description='Number of neural network inputs in input vector minus 1. The actual number of inputs is NNI + 1.', accessibility='rw'))

# NNxIVA
r = RegisterTemplate(nameTemplate='NNxIVA', registerMemorySlot=1, description='Input vector start address. Must be contained within the appropriate multiplexed SRAM, and must be on a 4-byte boundary. Each input in the input vector is a signed int16 (signed Q0.15) number. Inputs in the input vector must be stored as follows. The input at index 0 must be stored with its LSbyte at NNxIVA + 0 (in bytes) and its MSbyte at NNxIVA + 1 (in bytes). The input at index 1 must be stored with its LSbyte at NNxIVA + 2 (in bytes) and its MSbyte at NNxIVA + 3 (in bytes). The rest of the inputs follow the same sequence.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=14, unused=True))
r.AddBitField(BitField(name='NNIVA', msb=13, lsb=2, description='Input vector start address (divided by 4)', accessibility='rw'))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))

# NNxOVA
r = RegisterTemplate(nameTemplate='NNxOVA', registerMemorySlot=2, description='Output vector start address. Must be contained within the appropriate multiplexed SRAM, and must be on a 4-byte boundary. Each output in the output vector is a signed int16 (signed Q0.15) number. Outputs in the output vector are stored as follows. The output at index 0 is stored with its LSbyte at NNxOVA + 0 (in bytes) and its MSbyte at NNxOVA + 1 (in bytes). The output at index 1 is stored with its LSbyte at NNxOVA + 2 (in bytes) and its MSbyte at NNxOVA + 3 (in bytes). The rest of the outputs follow the same sequence.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=14, unused=True))
r.AddBitField(BitField(name='NNOVA', msb=13, lsb=2, description='Output vector start address (divided by 4)', accessibility='rw'))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))

# NNxWMA
r = RegisterTemplate(nameTemplate='NNxWMA', registerMemorySlot=3, description='Synaptic weights matrix start address. Must be contained within the appropriate multiplexed SRAM, and must be on a 4-byte boundary. Each synaptic weight in the synaptic weights matrix is a signed int24 (signed Q8.15) number. Note that bit 23 of each weight is the sign bit. Weights in the weights matrix are stored as follows. The weight at index 0 is stored with its LSbyte at NNxWMA + 0 (in bytes), its center byte at NNxWMA + 1 (in bytes), and its MSbyte at NNxWMA + 2 (in bytes). The weight at index 1 is stored with its LSbyte at NNxWMA + 3 (in bytes), its center byte at NNxWMA + 4 (in bytes), and its MSbyte at NNxWMA + 5 (in bytes). The weight at index 2 is stored with its LSbyte at NNxWMA + 6 (in bytes), its center byte at NNxWMA + 7 (in bytes), and its MSbyte at NNxWMA + 8 (in bytes). The weight at index 3 is stored with its LSbyte at NNxWMA + 9 (in bytes), its center byte at NNxWMA + 10 (in bytes), and its MSbyte at NNxWMA + 11 (in bytes). The rest of the weights follow the same sequence.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=14, unused=True))
r.AddBitField(BitField(name='NNWMA', msb=13, lsb=2, description='Synaptic weights matrix start address (divided by 4)', accessibility='rw'))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))

# NNxLSI
r = RegisterTemplate(nameTemplate='NNxLSI', registerMemorySlot=4, description='Logistic sigmoid input, which is a signed int32 (signed Q8.15) number. Used for testing the hardware logistic sigmoid approximation activation function. When NNLSIS is set, NNxLSO will contain the output of the hardware logistic sigmoid approximation with NNxLSI as its input.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='NNxLSI', msb=31, lsb=0, accessibility='rw'))

# NNxLSO
r = RegisterTemplate(nameTemplate='NNxLSO', registerMemorySlot=5, description='Logistic sigmoid output, which is a signed int16 (signed Q0.15) number. Used for testing the hardware logistic sigmoid approximation activation function. When NNLSIS is set, NNxLSO will contain the output of the hardware logistic sigmoid approximation with NNxLSI as its input.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='NNxLSO', msb=15, lsb=0, accessibility='rw'))



''' DAC '''
p = PeripheralTemplate(nameTemplate='DAC', description='Two 14-bit DACs with timer-based DMA. The DMA reads each new value for the two DACs directly from RAM and sets the DAC output code accordingly. The buffer is split into two halves. The first half begins at index 0 of the buffer, and the second half begins at index 256, or halfway through the whole buffer.', registerPrefix=None, bitFieldPrefix=None, latexIntroFileName='DAC-intro-pingora2-2021-05.tex')
m.AddPeripheralTemplate(p)

# DACCR
r = RegisterTemplate(nameTemplate='DACCR', registerMemorySlot=0, description='DAC control register', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=11, unused=True))
r.AddBitField(BitField(name='DACCDIV', msb=10, lsb=8, accessibility='rw', description='DAC clock divider', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2 ', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))
r.AddBitField(BitField(name='DAC1EN', msb=7, description='DAC1 enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='DAC0EN', msb=6, description='DAC0 enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='DAC1DEN', msb=5, description='DAC1 DMA enable. Immediately begins reading new data to push to the DACS when either DAC is enabled.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='DAC0DEN', msb=4, description='DAC0 DMA enable. Immediately begins reading new data to push to the DACS when either DAC is enabled.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='DACCS', msb=3, lsb=2, description='DAC clock souce select', accessibility='rw', valueDescriptions=[(0b00, 'MCLK', '_MCLK'), (0b01, 'SMCLK', '_SMCLK'), (0b10, 'HFXT', '_HFXT'), (0b11, 'DCO0', '_DCO0')]))
r.AddBitField(BitField(name='DACDAL', msb=1, description='DAC data alignment', accessibility='rw', valueDescriptions=[(0b0, 'Right adjusted (reads bits 13-0)', '_R'), (0b1, 'Left adjusted (reads bits 15-2)', '_L')]))
r.AddBitField(BitField(name='DACBEIE', msb=0, description='DAC buffer half empty interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))

# DACSR
r = RegisterTemplate(nameTemplate='DACSR', registerMemorySlot=1, description='DAC status register.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=2, unused=True))
r.AddBitField(BitField(name='DACBH', msb=1, description='DAC buffer half indicator. Indicates which half of the DAC buffer is currently being read by the DAC DMA.', accessibility='r', valueDescriptions=[(0b0, 'First half is being read, second half is safe to write to', '_FIRST'), (0b1, 'Second half is being read, first half is safe to write to', '_SECOND')]))
r.AddBitField(BitField(name='DACBEIF', msb=0, description='DAC buffer half empty interrupt flag. Write a 1 to this bit to clear it.', accessibility='r', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))

# DAC0VAL
r = RegisterTemplate(nameTemplate='DAC0VAL', registerMemorySlot=2, description='DAC0 value register. Write to this register to immediately update the output code of the DAC. Data alignment depends on the DACDAL bit.', size=16)
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='DAC0VAL', msb=15, lsb=0, accessibility='rw'))

# DAC1VAL
r = RegisterTemplate(nameTemplate='DAC1VAL', registerMemorySlot=3, description='DAC1 value register. Write to this register to immediately update the output code of the DAC. Data alignment depends on the DACDAL bit.', size=16)
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='DAC1VAL', msb=15, lsb=0, accessibility='rw'))

# DACFS
r = RegisterTemplate(nameTemplate='DACFS', registerMemorySlot=4, description='DAC DMA sampling frequency register. When in DMA mode, the DAC sampling frequency is Fs = DAC clock source frequency / (16 * DACFS * 2^DACCS)', size=16)
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='DACFS', msb=15, lsb=0, accessibility='rw'))

# DACHBS
r = RegisterTemplate(nameTemplate='DACHBS', registerMemorySlot=5, description='DAC half buffer size register. Determines the size of half of the DAC buffer, which is stored in the multiplexed RAM. The number of DAC samples in half of the DAC buffer is: Ns = (DACHBS + 1). The number of bytes in half of the ADC buffer is: Nb = 4 * Ns', size=8)
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='DACHBS', msb=7, lsb=0, accessibility='rw'))



''' Opamp '''
p = PeripheralTemplate(nameTemplate='OPA', description='Opamp peripheral with optional comparator outputs. Controls two opamps. Each can be configured as an OTA amplifier or a buffer, or both. ', registerPrefix='OPA', bitFieldPrefix=None, latexIntroFileName='OPAMP-intro-pingora2-2021-05.tex')
m.AddPeripheralTemplate(p)

# OPACR
r = RegisterTemplate(nameTemplate='OPACR', registerMemorySlot=0, description='Opamp control register', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='OPA0MODE', msb=1, lsb=0, description='Opamp 0 mode', accessibility='rw', valueDescriptions=[(0b00, 'Disabled', '_DISABLED'), (0b01, 'Buffer only', '_BUF_ONLY'), (0b10, 'OTA unbuffered', '_OTA_UNBUF'), (0b11, 'OTA buffered', '_OTA_BUF')]))
r.AddBitField(BitField(name='OPA0BS', msb=2, description='Opamp 0 bias select', accessibility='rw', valueDescriptions=[(0b0, 'Bias provided by global bias generator', '_BIAS_GEN'), (0b1, 'Bias provided by DAC0', '_DAC0')]))
r.AddBitField(BitField(name='OPA0PDWD', msb=3, description='Opamp 0 pull down when disabled', accessibility='rw', valueDescriptions=[(0b0, 'Opamp output is high impedance (Hi-Z) when disabled', '_HIZ'), (0b1, 'Opamp output is pulled to analog ground when disabled', '_PD')]))

r.AddBitField(BitField(name='OPA1MODE', msb=5, lsb=4, description='Opamp 1 mode', accessibility='rw', valueDescriptions=[(0b00, 'Disabled', '_DISABLED'), (0b01, 'Buffer only', '_BUF_ONLY'), (0b10, 'OTA unbuffered', '_OTA_UNBUF'), (0b11, 'OTA buffered', '_OTA_BUF')]))
r.AddBitField(BitField(name='OPA1BS', msb=6, description='Opamp 1 bias select', accessibility='rw', valueDescriptions=[(0b0, 'Bias provided by global bias generator', '_BIAS_GEN'), (0b1, 'Bias provided by DAC0', '_DAC1')]))
r.AddBitField(BitField(name='OPA1PDWD', msb=7, description='Opamp 1 pull down when disabled', accessibility='rw', valueDescriptions=[(0b0, 'Opamp output is high impedance (Hi-Z) when disabled', '_HIZ'), (0b1, 'Opamp output is pulled to analog ground when disabled', '_PD')]))

r.AddBitField(BitField(name='OPA0CMPEN', msb=8, description='Opamp 0 comparator enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='OPA0CMPIE', msb=9, description='Opamp 0 comparator interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='OPA0CMPIES', msb=10, description='Opamp 0 comparator interrupt edge select', accessibility='rw', valueDescriptions=[(0b0, 'Rising edge', '_RISING'), (0b1, 'Falling edge', '_FALLING')]))

r.AddBitField(BitField(name='OPA1CMPEN', msb=11, description='Opamp 1 comparator enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='OPA1CMPIE', msb=12, description='Opamp 1 comparator interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='OPA1CMPIES', msb=13, description='Opamp 1 comparator interrupt edge select', accessibility='rw', valueDescriptions=[(0b0, 'Rising edge', '_RISING'), (0b1, 'Falling edge', '_FALLING')]))

# OPASR
r = RegisterTemplate(nameTemplate='OPASR', registerMemorySlot=1, description='Opamp status register. Write anything to this register to clear the interrupt flags OPA0CMPIF and OPA1MPIF', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=4, unused=True))
r.AddBitField(BitField(name='OPA0CMPVAL', msb=0, description='Opamp 0 comparator current value.', accessibility='r', valueDescriptions=[(0b0, 'Negative opamp input greater than positive input'), (0b1, 'Positive opamp input greater than negative input')]))
r.AddBitField(BitField(name='OPA1CMPVAL', msb=1, description='Opamp 1 comparator current value.', accessibility='r', valueDescriptions=[(0b0, 'Negative opamp input greater than positive input'), (0b1, 'Positive opamp input greater than negative input')]))
r.AddBitField(BitField(name='OPA0CMPIF', msb=2, description='Opamp 0 comparator interrupt flag. Write a 1 to this bit to clear it.', accessibility='r', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))
r.AddBitField(BitField(name='OPA1CMPIF', msb=3, description='Opamp 1 comparator interrupt flag. Write a 1 to this bit to clear it.', accessibility='r', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Interrupt pending')]))



''' Pulse Counter '''
p = PeripheralTemplate(nameTemplate='PCT', description='Pulse counter. Counts the number of digital pulses generated by a sensor, such as a Domino Neutron detector or a Geiger-Muller tube.', registerPrefix='PCT', bitFieldPrefix='PCT')
m.AddPeripheralTemplate(p)

# PCCR
r = RegisterTemplate(nameTemplate='PCTCR', registerMemorySlot=0, size=8, description='Pulse counter control register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='ENPCT0', msb=0, accessibility='rw', description='Enables pulse counter 0', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ENPCT1', msb=1, accessibility='rw', description='Enables pulse counter 1', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ENPCT2', msb=2, accessibility='rw', description='Enables pulse counter 2', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ENPCT3', msb=3, accessibility='rw', description='Enables pulse counter 3', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ESPCT0', msb=4, accessibility='rw', description='Edge select for pulse counter 0', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='ESPCT1', msb=5, accessibility='rw', description='Edge select for pulse counter 1', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='ESPCT2', msb=6, accessibility='rw', description='Edge select for pulse counter 2', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='ESPCT3', msb=7, accessibility='rw', description='Edge select for pulse counter 3', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))


# PCCNT0
r = RegisterTemplate(nameTemplate='PCTCNT0', registerMemorySlot=1, size=32, description='Pulse counter 0 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT0', msb=31, lsb=0, accessibility='r'))

# PCCNT1
r = RegisterTemplate(nameTemplate='PCTCNT1', registerMemorySlot=2, size=32, description='Pulse counter 1 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT1', msb=31, lsb=0, accessibility='r'))

# PCCNT2
r = RegisterTemplate(nameTemplate='PCTCNT2', registerMemorySlot=3, size=32, description='Pulse counter 2 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT2', msb=31, lsb=0, accessibility='r'))

# PCCNT3
r = RegisterTemplate(nameTemplate='PCTCNT3', registerMemorySlot=4, size=32, description='Pulse counter 3 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT3', msb=31, lsb=0, accessibility='r'))



''' AFEx '''
p = PeripheralTemplate(nameTemplate='AFEx', description='Analog front-end interface. Capable of pulse height analysis (PHA) and pulse shape discrimination (PSD). Features a DMA to place PHA and PSD data directly into RAM without CPU intervention.', registerPrefix='AFEx', bitFieldPrefix='Afe')
m.AddPeripheralTemplate(p)

# AFExCR0
r = RegisterTemplate(nameTemplate='AFExCR0', registerMemorySlot=0, size=32, description='AFE control register 0')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PsdFullIE', msb=0, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcConvDoneIE', msb=1, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='PulseDoneIE', msb=2, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='PulseDoneWait', msb=3, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='ThreshSel', msb=5, lsb=4, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='SHPwrMode', msb=6, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='RejectMode', msb=7, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='RamOff', msb=8, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='PUPara', msb=9, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='PsdOrder', msb=10, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='OpenInput', msb=11, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='ForceThresh', msb=12, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnBLLT', msb=13, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnPsd', msb=14, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnPURej', msb=15, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnDma', msb=16, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnThresh', msb=17, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnAdc', msb=18, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnCsa', msb=19, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnCM', msb=20, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='EnAfe', msb=21, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='CsaRstMode', msb=22, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='CsaForceUnRst', msb=23, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='CsaForceRst', msb=24, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='CsaBiasSel', msb=25, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='BufCMMid', msb=26, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcMuxTest', msb=27, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcMidSel', msb=28, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcExtIn', msb=29, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(msb=31, lsb=30, unused=True))

# AFExCR1
r = RegisterTemplate(nameTemplate='AFExCR1', registerMemorySlot=1, size=32, description='AFE control register 1')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='ISink', msb=5, lsb=0, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='CsaCmAdj', msb=8, lsb=6, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='CMSHClkDiv', msb=12, lsb=9, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='ClkSel', msb=14, lsb=13, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcSampT', msb=17, lsb=15, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcCp', msb=24, lsb=18, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcClkDivM', msb=28, lsb=25, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AdcClkDivN', msb=31, lsb=29, accessibility='rw', description='', valueDescriptions=None))

# AFExCFB
r = RegisterTemplate(nameTemplate='AFExCFB', registerMemorySlot=2, size=8, description='CSA feedback capacitance register. Increment is 250 fF. A value of 0 gives 0 fF (Cfb disconnected).')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCFB', msb=7, lsb=0, accessibility='rw', resetValue=0xFF))

# AFExRFB
r = RegisterTemplate(nameTemplate='AFExRFB', registerMemorySlot=3, size=16, description='CSA feedback resistance DAC register. Increasing values yield smaller resistances.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExRFB', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExTHR
r = RegisterTemplate(nameTemplate='AFExTHR', registerMemorySlot=4, size=16, description='Threshold DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExTHR', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExTPR
r = RegisterTemplate(nameTemplate='AFExTPR', registerMemorySlot=5, size=32, description='AFE test port register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AfeDtp0Sel', msb=4, lsb=0, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeDtp1Sel', msb=9, lsb=5, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeDtp2Sel', msb=14, lsb=10, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeDtp3Sel', msb=19, lsb=15, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeAtp0Sel', msb=23, lsb=20, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeAtp0BufEn', msb=24, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeAtp1Sel', msb=28, lsb=25, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(name='AfeAtp1BufEn', msb=29, accessibility='rw', description='', valueDescriptions=None))
r.AddBitField(BitField(msb=31, lsb=30, unused=True))

# AFExSPT
r = RegisterTemplate(nameTemplate='AFExSPT', registerMemorySlot=6, size=8, description='Smallest pulse time register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExSPT', msb=7, lsb=0, accessibility='rw'))

# AFExPIT
r = RegisterTemplate(nameTemplate='AFExPIT', registerMemorySlot=7, size=16, description='PHA integration time register. When this timer elapses, the PHA peak sample and hold latches the output of the CSA and allows the ADC to begin converting it. If AfeEnPsd is 0, the timer starts immediately after a valid new pulse is detected. If AfeEnPsd is 1 and AfePsdOrder is 0, the timer starts after the early PSD integration timer elapses. If AfeEnPsd is 1 and AfePsdOrder is 1, it starts after the late PSD integration timer elapses.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExPIT', msb=15, lsb=0, accessibility='rw'))

# AFExEIT
r = RegisterTemplate(nameTemplate='AFExEIT', registerMemorySlot=8, size=16, description='PSD early integration time register. When this timer elapses, the early PSD peak sample and hold latches the output of the CSA and allows the ADC to begin converting it. If AfeEnPsd is 0, the timer is disabled. If 1, the timer starts immediately after a valid new pulse is detected.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExEIT', msb=15, lsb=0, accessibility='rw'))

# AFExLIT
r = RegisterTemplate(nameTemplate='AFExLIT', registerMemorySlot=9, size=16, description='PSD late integration time register. When this timer elapses, the late PSD peak sample and hold latches the output of the CSA and allows the ADC to begin converting it. If AfeEnPsd is 0, the timer is disabled. If AfeEnPsd is 1 and AfePsdOrder is 1, the timer starts after the early PSD integration timer elapses. If AfeEnPsd is 1 and AfePsdOrder is 0, it starts after the PHA integration timer elapses.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExLIT', msb=15, lsb=0, accessibility='rw'))

# AFExRJT
r = RegisterTemplate(nameTemplate='AFExRJT', registerMemorySlot=10, size=16, description='Reject time register.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExRJT', msb=15, lsb=0, accessibility='rw'))

# AFExRST
r = RegisterTemplate(nameTemplate='AFExRST', registerMemorySlot=11, size=8, description='CSA reset time register. Determines the amount of time the CSA is held in reset after the reject timer has elapsed.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExRST', msb=7, lsb=0, accessibility='rw'))

# AFExAOFST
r = RegisterTemplate(nameTemplate='AFExAOFST', registerMemorySlot=12, size=16, description='ADC offset DAC register. Centers the CSA swing on the common mode voltage of the ADC by setting the ADC reference voltage Vref. The ADC buffer converts the differential inputs VInP and VInM to a single-ended signal referenced to VSS with the equation Vbuf = (VInP - VInM) + Vofst')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExAOFST', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExBLLT
r = RegisterTemplate(nameTemplate='AFExBLLT', registerMemorySlot=13, size=16, description='Baseline lower threshold DAC register. The baseline lower threshold is used to reset the CSA if its output dips below the threshold, acting as a form of baseline restoration.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExBLLT', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCSAREF
r = RegisterTemplate(nameTemplate='AFExCSAREF', registerMemorySlot=14, size=16, description='CSA reference DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCSAREF', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCSABP
r = RegisterTemplate(nameTemplate='AFExCSABP', registerMemorySlot=15, size=16, description='CSA bias P DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCSABP', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCSABPC
r = RegisterTemplate(nameTemplate='AFExCSABPC', registerMemorySlot=16, size=16, description='CSA bias P cascode DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCSABPC', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCSABNC
r = RegisterTemplate(nameTemplate='AFExCSABNC', registerMemorySlot=17, size=16, description='CSA bias N cascode DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCSABNC', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCSABN
r = RegisterTemplate(nameTemplate='AFExCSABN', registerMemorySlot=18, size=16, description='CSA bias N DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCSABN', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCMSHR
r = RegisterTemplate(nameTemplate='AFExCMSHR', registerMemorySlot=19, size=16, description='Current mirror sample and hold reference DAC register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCMSHR', msb=13, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=15, lsb=14, unused=True))

# AFExCLPF
r = RegisterTemplate(nameTemplate='AFExCLPF', registerMemorySlot=20, size=8, description='Current mirror low pass filter capacitance adjust register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExCLPF', msb=5, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=7, lsb=6, unused=True))

# AFExSR
r = RegisterTemplate(nameTemplate='AFExSR', registerMemorySlot=21, size=8, description='AFE status register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='DTP1VAL', msb=7, accessibility='r', description='The current value of digital test port 1'))
r.AddBitField(BitField(name='DTP0VAL', msb=6, accessibility='r', description='The current value of digital test port 0'))
r.AddBitField(BitField(name='AdcActive', msb=5, accessibility='r', description='Indicates that the ADC is currently active either sampling or converting', valueDescriptions=[(0b0, 'ADC inactive'), (0b1, 'ADC active')]))
r.AddBitField(BitField(name='AdcDataReady', msb=4, accessibility='r', description='', valueDescriptions=None))
r.AddBitField(BitField(name='DmaEnabled', msb=3, accessibility='r', description='', valueDescriptions=None))
r.AddBitField(BitField(name='PulseDone', msb=2, accessibility='rw1', description=''))
r.AddBitField(BitField(name='AdcConvDone', msb=1, accessibility='rw1', description=''))
r.AddBitField(BitField(name='PsdFull', msb=0, accessibility='rw1', description='PSD memory full interrupt flag. Write a 1 to this bit to clear the flag and allow the AFE finite state machine to overwrite the memory with new PSD data.'))

# AFExADCVAL
r = RegisterTemplate(nameTemplate='AFExADCVAL', registerMemorySlot=22, size=16, description='ADC value register. Shows the value of the most recent ADC conversion.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExADCVAL', msb=9, lsb=0, accessibility='r'))
r.AddBitField(BitField(msb=15, lsb=10, unused=True))

# AFExVPC
r = RegisterTemplate(nameTemplate='AFExVPC', registerMemorySlot=23, size=32, description='Valid pulse count register. Write anything to this register to clear both AFExVPC and AFExTPC.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExVPC', msb=31, lsb=0, accessibility='r'))

# AFExTPC
r = RegisterTemplate(nameTemplate='AFExTPC', registerMemorySlot=24, size=32, description='Total pulse count register. Write anything to this register to clear both AFExVPC and AFExTPC.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='AFExTPC', msb=31, lsb=0, accessibility='r'))









''' Check the peripheral templates for errors '''
m.CheckPeripheralTemplates()



''' Create Peripherals from PeripheralTemplates and add them to the memory map '''
m.CreatePeripheral(nameTemplate='SYSTEM', nameIndex='', peripheralMemorySlot=0, interruptPriority=0)	# SYSTEM
GPIO1 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=1, peripheralMemorySlot=1, interruptPriority=3)	# GPIO1
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=0, peripheralMemorySlot=2, interruptPriority=4)	# SPI0
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=1, peripheralMemorySlot=3, interruptPriority=5)	# SPI1
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=0, peripheralMemorySlot=4, interruptPriority=6)	# UART0
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=0, peripheralMemorySlot=5, interruptPriority=7)	# TIMER0
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=1, peripheralMemorySlot=6, interruptPriority=8)	# TIMER1

GPIO2 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=2, peripheralMemorySlot=7, interruptPriority=9)	# GPIO2
GPIO3 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=3, peripheralMemorySlot=8, interruptPriority=10)	# GPIO3
GPIO4 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=4, peripheralMemorySlot=9, interruptPriority=11)	# GPIO4
GPIO5 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=5, peripheralMemorySlot=10, interruptPriority=12)	# GPIO5

m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=0, peripheralMemorySlot=11, interruptPriority=13)	# I2C0
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=2, peripheralMemorySlot=12, interruptPriority=14)	# SPI2
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=1, peripheralMemorySlot=13, interruptPriority=15)	# UART1
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=2, peripheralMemorySlot=14, interruptPriority=16)	# TIMER2
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=3, peripheralMemorySlot=15, interruptPriority=17)	# TIMER3
m.CreatePeripheral(nameTemplate='NNx', nameIndex=0, peripheralMemorySlot=16, interruptPriority=18)	# NN0

m.CreatePeripheral(nameTemplate='AFEx', nameIndex=0, peripheralMemorySlot=17, interruptPriority=19)	# AFE0
m.CreatePeripheral(nameTemplate='AFEx', nameIndex=1, peripheralMemorySlot=18, interruptPriority=20)	# AFE1
m.CreatePeripheral(nameTemplate='AFEx', nameIndex=2, peripheralMemorySlot=19, interruptPriority=21)	# AFE2
m.CreatePeripheral(nameTemplate='AFEx', nameIndex=3, peripheralMemorySlot=20, interruptPriority=22)	# AFE3
m.CreatePeripheral(nameTemplate='AFEx', nameIndex=4, peripheralMemorySlot=21, interruptPriority=23)	# AFE4
m.CreatePeripheral(nameTemplate='AFEx', nameIndex=5, peripheralMemorySlot=22, interruptPriority=24)	# AFE5

m.CreatePeripheral(nameTemplate='PCT', nameIndex='', peripheralMemorySlot=23, interruptPriority=None)	# PCT
GPIO6 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=6, peripheralMemorySlot=24, interruptPriority=25)	# GPIO6
GPIO7 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=7, peripheralMemorySlot=25, interruptPriority=26)	# GPIO7
GPIO8 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=8, peripheralMemorySlot=26, interruptPriority=27)	# GPIO8

m.CreatePeripheral(nameTemplate='OPA', nameIndex='', peripheralMemorySlot=27, interruptPriority=28)	# Opamp
m.CreatePeripheral(nameTemplate='DAC', nameIndex='', peripheralMemorySlot=28, interruptPriority=29)	# DAC

m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=1, peripheralMemorySlot=29, interruptPriority=30)	# I2C0
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=2, peripheralMemorySlot=30, interruptPriority=31)	# UART2






''' Create the package and power domains '''
# List of necessary pins for a hypothetical QFN44 package: West = {3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23}, South = {28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48} East = {53, 55, 57, 59, 61, 63, 65, 67, 69, 71, 73} North = {78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98}
# Necessary pin population:
# 3: VDDPST
# 5: VSSPST
# 7: VSS
# 9: VDD
# 11: resetn
# 13: P1.0/CS_FLASH
# 15: P1.1/MISO0
# 17: P1.2/MOSI0
# 19: P1.3/SCK0
# 21: P1.4/TX0
# 23: P1.5/RX0
# 28: P1.6/TRAP
# 30: P1.7/BOOT
# 32: P2.0/CS1
# 34: P2.1/MISO1
# 36: P2.2/MOSI1
# 38: P2.3/SCK1
# 40: P2.4/TX1
# 42: P2.5/RX1
# 44: P2.6/SDA0
# 46: P2.7/SCL0
# 48: P3.0/CS2
# 53: P3.1/MISO2
# 55: P3.2/MOSI2
# 57: P3.3/SCK2
# 59: P3.4/LFXT
# 61: P3.5/HFXT
# 63: P3.6/SH0
# 65: P4.1/T0CMP1
# 67: P4.3/DTP0/T0CAP1
# 69: P4.7/DTP1/T1CAP1
# 71: P5.0/PC0
# 73: P5.2/PC2
# 78: DAC0
# 80: CH3
# 82: Op0Out
# 84: Op0InM
# 86: Op0InP
# 88: ATP0
# 90: CH2
# 92: CH1
# 94: CH0
# 96: AVSS
# 98: AVDD

package = m.CreatePackage(
	packageType='QFN',
	pinCount=100,
	units='mm',
	dimensions=[12, 12],
	pinsOnEachSide={'W': 25, 'S': 25, 'E': 25, 'N': 25},
	pinPitch=0.4,
	pinWidth=0.2,
	pinDepth=0.4
)

digitalIOPowerDomain = package.AddPowerDomain(
	powerDomainName='Digital I/O',
	positiveVoltage=3.3,
	negativeVoltage=0.0,
	positiveRailPinNumber=3,
	positiveRailPinName='VDDPST',
	negativeRailPinNumber=5,
	negativeRailPinName='VSSPST',
	isGpioPowerDomain=True
)

digitalCorePowerDomain = package.AddPowerDomain(
	powerDomainName='Digital Core',
	positiveVoltage=1.0,
	negativeVoltage=0.0,
	positiveRailPinNumber=9,
	positiveRailPinName='VDD',
	negativeRailPinNumber=7,
	negativeRailPinName='VSS'
)

analogPowerDomain = package.AddPowerDomain(
	powerDomainName='Analog',
	positiveVoltage=2.5,
	negativeVoltage=0.0,
	positiveRailPinNumber=98,
	positiveRailPinName='AVDD',
	negativeRailPinNumber=96,
	negativeRailPinName='AVSS'
)

# resetn pin
package.AddPin(packagePinNumber=11, name='resetn', ioType='i', powerDomain=digitalIOPowerDomain)

# Analog pins
package.AddPin(packagePinNumber=77, name='CH5', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=78, name='DAC0', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=79, name='CH4', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=80, name='CH3', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=81, name='DAC1', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=82, name='OP0OUT', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=83, name='EXTBN', ioType='io', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=84, name='OP0INM', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=85, name='EXTBNC', ioType='io', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=86, name='OP0INP', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=87, name='ATP1', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=88, name='ATP0', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=89, name='EXTBPC', ioType='io', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=90, name='CH2', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=91, name='EXTBP', ioType='io', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=92, name='CH1', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=93, name='OP1INM', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=94, name='CH0', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=95, name='OP1INP', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=97, name='OP1OUT', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=99, name='ADCEXTINM', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=100, name='ADCEXTINP', ioType='i', powerDomain=analogPowerDomain)

# Each pad adjacent to a corner is a no connect (except north-north-west)
package.AddPin(packagePinNumber=1, name='', ioType='', noConnect=True)
package.AddPin(packagePinNumber=25, name='', ioType='', noConnect=True)
package.AddPin(packagePinNumber=26, name='', ioType='', noConnect=True)
package.AddPin(packagePinNumber=50, name='', ioType='', noConnect=True)
package.AddPin(packagePinNumber=51, name='', ioType='', noConnect=True)
package.AddPin(packagePinNumber=75, name='', ioType='', noConnect=True)
package.AddPin(packagePinNumber=76, name='', ioType='', noConnect=True)





''' Add pins to the GPIO ports (and optionally change the GPIO port sizes) '''
''' WARNING: Look at the documentation for GpioConfigurator.__init__() for important instructions on how to use the function, especially concerning the funcIOType argument '''
# GPIO1
GPIO1.ChangeGPIOPortSize(8)

GPIO1.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='CS_FLASH', funcIOType='o',	rstOUT=1, rstDIR=1, rstSEL=0, rstREN=0, description='Chip select pin for SPI flash memory'), packagePinNumber=13) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='MISO0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 Master In Slave Out (connected to SPI flash memory)'), packagePinNumber=15) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='MOSI0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 Master Out Slave In (connected to SPI flash memory)'), packagePinNumber=17) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='SCK0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 serial clock (connected to SPI flash memory)'), packagePinNumber=19) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='TX0', funcIOType='o',		rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='UART0 transmitter (default forth interpreter interface)'), packagePinNumber=21) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='RX0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='UART0 receiver (default forth interpreter interface)'), packagePinNumber=23) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='TRAP', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='CPU trap state'), packagePinNumber=28) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=7, primaryName='BOOT', funcName='', funcIOType='',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=1, description='Boot select pin (Boots to forth interpreter when LOW, boots from SPI flash when HIGH)'), packagePinNumber=30) # necessary

# GPIO2
GPIO2.ChangeGPIOPortSize(8)

GPIO2.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='CS1', funcIOType='i',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 this slave chip select'), packagePinNumber=32) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='MISO1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 Master In Slave Out'), packagePinNumber=34) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='MOSI1', funcIOType='io',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 Master Out Slave In'), packagePinNumber=36) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='SCK1', funcIOType='io',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 serial clock'), packagePinNumber=38) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='TX1', funcIOType='o',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='UART1 transmitter'), packagePinNumber=40) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='RX1', funcIOType='io',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='UART1 receiver'), packagePinNumber=42) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='SDA0',   funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial data'), packagePinNumber=44) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=7, primaryName='', funcName='SCL0',   funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial clock'), packagePinNumber=46) # necessary

# GPIO3
GPIO3.ChangeGPIOPortSize(8)

GPIO3.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='CS2', funcIOType='i',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI2 this slave chip select'), packagePinNumber=48) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='MISO2', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI2 Master In Slave Out'), packagePinNumber=53) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='MOSI2', funcIOType='io',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI2 Master Out Slave In'), packagePinNumber=55) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='SCK2', funcIOType='io',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI2 serial clock'), packagePinNumber=57) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='LFXT', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='Low frequency external clock'), packagePinNumber=59)	# necessary. Though this is not technically and "io" pin, make it "io" so the proper signals are generated in MCU.vhd
GPIO3.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='HFXT', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='High frequency external clock'), packagePinNumber=61)	# necessary. Though this is not technically and "io" pin, make it "io" so the proper signals are generated in MCU.vhd
GPIO3.AddGpio(GpioConfigurator(bitNumber=6, primaryName='SH0', funcName='', funcIOType='',	rstOUT=1, rstDIR=1, rstSEL=0, rstREN=0, description='Start high 0'), packagePinNumber=63) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=7, primaryName='SH1', funcName='', funcIOType='',	rstOUT=1, rstDIR=1, rstSEL=0, rstREN=0, description='Start high 1'), packagePinNumber=2) # optional

# GPIO4
GPIO4.ChangeGPIOPortSize(8)

GPIO4.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='T0CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 0 pin (for PWM generation)'), packagePinNumber=4) # optional
GPIO4.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='T0CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 1 pin (for PWM generation)'), packagePinNumber=65) # necessary
GPIO4.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='T0CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 input capture 0 pin'), packagePinNumber=6) # optional
GPIO4.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='DTP0_T0CAP1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 0 (output) and TIMER0 input capture 1 (input) pin'), packagePinNumber=67) # necessary
GPIO4.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='T1CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 Compare 0 pin (for PWM generation)'), packagePinNumber=8) # optional
GPIO4.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='T1CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 Compare 1 pin (for PWM generation)'), packagePinNumber=10) # optional
GPIO4.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='T1CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 input capture 0 pin'), packagePinNumber=12) # optional
GPIO4.AddGpio(GpioConfigurator(bitNumber=7, primaryName='', funcName='DTP1_T1CAP1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 1 (output) and TIMER1 input capture 1 (input) pin'), packagePinNumber=69) # necessary

# GPIO5
GPIO5.ChangeGPIOPortSize(8)

GPIO5.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='PC0', funcIOType='i', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=71) # necessary
GPIO5.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='PC1', funcIOType='i', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=14) # optional
GPIO5.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='PC2', funcIOType='i', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=73) # necessary
GPIO5.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='PC3', funcIOType='i', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=16) # optional
GPIO5.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='', funcIOType='', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=18) # optional
GPIO5.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='', funcIOType='', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=20) # optional
GPIO5.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='DTP2', funcIOType='o', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=22) # optional
GPIO5.AddGpio(GpioConfigurator(bitNumber=7, primaryName='', funcName='DTP3', funcIOType='o', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=24) # optional

# GPIO6
GPIO6.ChangeGPIOPortSize(8)

GPIO6.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='T2CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER2 Compare 0 pin (for PWM generation)'), packagePinNumber=27) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='T2CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER2 Compare 1 pin (for PWM generation)'), packagePinNumber=29) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='T2CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER2 input capture 0 pin'), packagePinNumber=31) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='T2CAP1', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER2 input capture 1 pin'), packagePinNumber=33) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='T3CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER3 Compare 0 pin (for PWM generation)'), packagePinNumber=35) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='T3CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER3 Compare 1 pin (for PWM generation)'), packagePinNumber=37) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='T3CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER3 input capture 0 pin'), packagePinNumber=39) # optional
GPIO6.AddGpio(GpioConfigurator(bitNumber=7, primaryName='', funcName='T3CAP1', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER3 input capture 1 pin'), packagePinNumber=41) # optional

# GPIO7
GPIO7.ChangeGPIOPortSize(8)

GPIO7.AddGpio(GpioConfigurator(bitNumber=0, primaryName='SL0', funcName='', funcIOType='', rstOUT=0, rstDIR=1, rstSEL=0, rstREN=0, description='Start low 0'), packagePinNumber=43) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=1, primaryName='SL1', funcName='', funcIOType='', rstOUT=0, rstDIR=1, rstSEL=0, rstREN=0, description='Start low 1'), packagePinNumber=45) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='SDA1', funcIOType='io', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C1 serial data'), packagePinNumber=47) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='SCL1',   funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C1 serial clock'), packagePinNumber=49) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='TX2', funcIOType='o', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='UART2 transmitter'), packagePinNumber=52) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='RX2', funcIOType='io', rstOUT=0, rstDIR=1, rstSEL=0, rstREN=0, description='UART2 receiver'), packagePinNumber=54) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='', funcIOType='', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=56) # optional
GPIO7.AddGpio(GpioConfigurator(bitNumber=7, primaryName='', funcName='', funcIOType='', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=58) # optional

# GPIO8
GPIO8.ChangeGPIOPortSize(8)

GPIO8.AddGpio(GpioConfigurator(bitNumber=0, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=60) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=1, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=62) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=2, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=64) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=3, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=66) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=4, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=1, rstSEL=0, rstREN=0, description=''), packagePinNumber=68) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=5, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=1, rstSEL=0, rstREN=0, description=''), packagePinNumber=70) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=6, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=72) # optional
GPIO8.AddGpio(GpioConfigurator(bitNumber=7, primaryName='', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=''), packagePinNumber=74) # optional



''' Check for errors '''
m.CheckPeripherals()
m.CheckPackagePins()



''' Generate output files'''
m.Generate(test=False, force=True, saveHardware=True, saveSoftware=True)
