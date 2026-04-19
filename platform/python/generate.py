#!/usr/bin/env python3

import pathlib, sys, os

thisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
chipRootDirectory = thisFileDirectory + '/..'

# No need to append path since we're already in ChipGenerator/python

from ChipGenerator import ChipGenerator
from Peripheral import PeripheralTemplate, Peripheral
from Register import RegisterTemplate, Register
from BitField import BitField
from GpioConfigurator import GpioConfigurator


''' Create Memory Map '''
m = ChipGenerator(
	chipRootDirectory=chipRootDirectory,
	asicName='Myshkin',
	asicNameForUserGuide='Myshkin',
	mcuUserGuideLatexTemplateFileName='TRM.template.tex',
	romStartAddress=0x0000,
	romSize=16384,	# 16 KiB
	peripheralMemoryStartAddress=0x4000,
	peripheralMemorySlotCount=16,
	registerMemorySlotsPerPeripheralMemorySlot=64, #Bytes between each peripheral's register memory slots.
	ramStartAddress=0x8000,
	ramMemorySlotSize=16384,	# 16 KiB
	# Neither 0 nor 1 may be in ramMemorySlotsAvailable. This is because the ROM and the peripheral memory technically take slots 0 and 1.
	ramMemorySlotsAvailable=[3, 4],
	ramMemorySlotsUsed=[3, 4],
	ramMemorySlotsMuxed={},	# TODO: MUXed RAM slots
	spiFlashProgramAddress=0x8200, 
	nativeSpiFlashMemoryReadAccess=True,
	nativeSpiFlashMemoryWriteAccess=False,
	stackPointerInit=0x10000,	# Stack pointer at top of RAM slots 3-4 (32 KiB total)
	bootloaderUsesSpiFlashCommands=True,
	vectorsCount=83,
	padOutPosLogic=True,
	padDIRPosLogic=False,
	padRENPosLogic=False,
	ENABLE_COUNTERS=False,
	ENABLE_COUNTERS64=False,
	ENABLE_REGS_DUALPORT=True,	# TODO: Enable for ASIC synthesis if using a dual port register file, disable for Xilinx Spartan 6 FPGAs
	LATCHED_MEM_RDATA=False,
	TWO_STAGE_SHIFT=False,
	BARREL_SHIFTER=False,
	COMPRESSED_ISA=True,
	ENABLE_MUL=True,
	ENABLE_FAST_MUL=True,
	ENABLE_DIV=True,
	ENABLE_IRQ_FAST_CONTEXT_SWITCHING=False,	# Using fast context switching saves 31.042 us @ 24 MHz (745 cycles) per interrupt, but doubles the size of the CPU register file
	ENABLE_IRQ_QREGS=False,	# Evidently the ARM register file IPs are called "two-port", but one port is read-only and the other is write-only. This means you need to write your own register file definition in HDL (remember that register x0 is always all '0's!)
	ENABLE_IRQ_TIMER=False,
	MASKED_IRQ=0x00000000,	# 32-bit IRQ mask. Any bit that is a '1' is a permanently disabled interrupt vector
	PROGADDR_IRQ=0x9000,	# TODO: Set this as the address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)
	lastRamMemorySlotSize=16384
)



# Extra memory sections (none for this chip)
m.ExtraMemorySections = []



''' System '''
p = PeripheralTemplate(nameTemplate='SYSTEM', description='Controls the entire system, including the clocking and power state. Also has a CRC calculator using the CRC16_CDMA2000 polynomial.', bitFieldPrefix='SYS', latexIntroFileName='SYSTEM-intro-myshkin-2025-11.tex')
m.AddPeripheralTemplate(p)

# SYSCLK
r = RegisterTemplate(nameTemplate='SYSCLKCR', registerMemorySlot=0, description='System clock control register', size=16)
p.AddRegisterTemplate(r)

#r.AddBitField(BitField(name='CLKOSSEL', msb=15, lsb=13, description='CLKO pin output clock source select', accessibility='rw', valueDescriptions=[(0b000, 'CPU Clock', '_CPU'), (0b001, 'MCLK', '_MCLK'), (0b010, 'SMCLK', '_SMCLK'), (0b011, 'Low Frequency Crystal Clock', '_LFXT'), (0b100, 'High Frequency Crystal Clock', '_HFXT'), (0b101, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b110, 'Digitally Controlled Oscillator 1', '_DCO1')]))
#r.AddBitField(BitField(unused=True, msb=12))
r.AddBitField(BitField(unused=True, msb=15, lsb=9))
r.AddBitField(BitField(name='DCO1ON', msb=8, description='Digitally controlled oscillator 1 (DCO1) power enable. Set to power on DCO1. DCO1 is automatically kept on if it is currently selected as the source for MCLK or SMCLK, regardless of this bit.', accessibility='rw', valueDescriptions=[(0b0, 'DCO1 powered off'), (0b1, 'DCO1 powered on')]))
r.AddBitField(BitField(name='DCO0ON', msb=7, description='Digitally controlled oscillator 0 (DCO0) power enable. Set to power on DCO0. DCO0 is automatically kept on if it is currently selected as the source for MCLK or SMCLK, regardless of this bit.', accessibility='rw', valueDescriptions=[(0b0, 'DCO0 powered off'), (0b1, 'DCO0 powered on')]))
r.AddBitField(BitField(name='HFXTOFF', msb=6, description='High frequency external crystal clock disable. Cannot be disabled if it is currently selected as the source for MCLK or SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'HFXT enabled'), (0b1, 'HFXT disabled')]))
r.AddBitField(BitField(name='LFXTOFF', msb=5, description='Low frequency external crystal clock disable. Cannot be disabled if it is currently selected as the source for SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'LFXT enabled'), (0b1, 'LFXT disabled')]))
r.AddBitField(BitField(name='SMCLKOFF', msb=4, description='Submain clock disable. Globally and unconditionally disables SMCLK, gating all peripherals clocked from SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'SMCLK enabled'), (0b1, 'SMCLK disabled')]))
r.AddBitField(BitField(name='SMCLKSEL', msb=3, lsb=2, description='Submain clock source select', accessibility='rw', valueDescriptions=[(0b00, 'High Frequency Crystal Clock', '_HFXT'), (0b01, 'Low Frequency Crystal Clock', '_LFXT'), (0b10, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b11, 'Digitally Controlled Oscillator 1', '_DCO1')]))
r.AddBitField(BitField(name='MCLKSEL', msb=1, lsb=0, description='Main clock source select (also CPU clock source select)', accessibility='rw', valueDescriptions=[(0b00, 'High Frequency Crystal Clock', '_HFXT'), (0b01, 'Submain Clock', '_SMCLK'), (0b10, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b11, 'Digitally Controlled Oscillator 1', '_DCO1')]))

# CLKDIVCR
r = RegisterTemplate(nameTemplate='CLKDIVCR', registerMemorySlot=1, description='MCLK and SMCLK clock divider control register. Configures clock division for main and submain clocks using glitch-free multiplexers.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='SYSSMCLKDIV', msb=5, lsb=3, accessibility='rw', description='SMCLK clock division selection. Division is applied after clock source selection through glitch-free divider multiplexer.', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))
r.AddBitField(BitField(name='SYSMCLKDIV', msb=2, lsb=0, accessibility='rw', description='MCLK clock division selection. Division is applied after clock source selection through glitch-free divider multiplexer.', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))

# BLOCKPWR
r = RegisterTemplate(nameTemplate='BLOCKPWR', registerMemorySlot=2, description='Block power control register. Controls power gating for on-chip memory blocks.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=3))
r.AddBitField(BitField(name='SYSRAM1OFF', msb=2, description='RAM block 1 power control. When set, RAM block 1 is powered off. All data becomes undefined and the block no longer responds to memory access. Reduces static power consumption.', accessibility='rw', valueDescriptions=[(0b0, 'RAM block 1 powered on'), (0b1, 'RAM block 1 powered off')]))
r.AddBitField(BitField(name='SYSRAM0OFF', msb=1, description='RAM block 0 power control. When set, RAM block 0 is powered off. All data becomes undefined and the block no longer responds to memory access. Reduces static power consumption.', accessibility='rw', valueDescriptions=[(0b0, 'RAM block 0 powered on'), (0b1, 'RAM block 0 powered off')]))
r.AddBitField(BitField(name='SYSROMOFF', msb=0, description='ROM power control. When set, boot ROM is powered off. ROM no longer responds to read access. Reduces static power consumption.', accessibility='rw', valueDescriptions=[(0b0, 'ROM powered on'), (0b1, 'ROM powered off')]))

# CRCDATA
r = RegisterTemplate(nameTemplate='CRCDATA', registerMemorySlot=3, description='CRC input data register. Write the next byte of data to this register to update the CRC calculation. Uses CRC16-CDMA2000 polynomial 0xC857.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSCRCDATA', msb=7, lsb=0, accessibility='rw', description='CRC data input byte. Writing to this register feeds the byte into the CRC calculation and updates CRCSTATE.'))

# CRCSTATE
r = RegisterTemplate(nameTemplate='CRCSTATE', registerMemorySlot=4, description='CRC state register. Contains the current CRC16 calculation result. Write to this register to initialize or restart the CRC calculation. Read to obtain the computed CRC16 checksum.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSCRCSTATE', msb=15, lsb=0, accessibility='rw', description='CRC state value. Initialize to 0xFFFF before starting CRC calculation. Read after processing all data bytes to get final CRC16 checksum.'))

# IRQENL
r = RegisterTemplate(nameTemplate='IRQENL', registerMemorySlot=5, size=32, description='IRQ enable register (lower 32 bits). Each bit enables the corresponding IRQ when set to 1. Bit position corresponds to IRQ vector number 0-31. IRQ also requires global enable in IRQCR.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSIRQENL', msb=31, lsb=0, accessibility='rw', description='IRQ enable bits for IRQ vectors 0-31. Set bit to 1 to enable corresponding IRQ.'))

# IRQENM
r = RegisterTemplate(nameTemplate='IRQENM', registerMemorySlot=6, size=32, description='IRQ enable register (middle 32 bits). Each bit enables the corresponding IRQ when set to 1. Bit position corresponds to IRQ vector number 32-63.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSIRQENM', msb=31, lsb=0, accessibility='rw', description='IRQ enable bits for IRQ vectors 32-63. Set bit to 1 to enable corresponding IRQ.'))

# IRQENU
r = RegisterTemplate(nameTemplate='IRQENU', registerMemorySlot=7, size=32, description='IRQ enable register (upper bits). Each bit enables the corresponding IRQ when set to 1. Bit position corresponds to IRQ vector number 64 and above.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSIRQENU', msb=31, lsb=0, accessibility='rw', description='IRQ enable bits for IRQ vectors 64 and above. Set bit to 1 to enable corresponding IRQ.'))

# IRQPRIL
r = RegisterTemplate(nameTemplate='IRQPRIL', registerMemorySlot=8, size=32, description='IRQ priority register (lower 32 bits). Each bit sets priority tier for corresponding IRQ. Bit position corresponds to IRQ vector number 0-31. Priority determined first by tier (0=high, 1=low), then by IRQ number (lower number = higher priority within tier).')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSIRQPRIL', msb=31, lsb=0, accessibility='rw', description='IRQ priority bits for IRQ vectors 0-31. Clear bit (0) for high priority tier, set bit (1) for low priority tier.'))

# IRQPRIM
r = RegisterTemplate(nameTemplate='IRQPRIM', registerMemorySlot=9, size=32, description='IRQ priority register (middle 32 bits). Each bit sets priority tier for corresponding IRQ. Bit position corresponds to IRQ vector number 32-63.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSIRQPRIM', msb=31, lsb=0, accessibility='rw', description='IRQ priority bits for IRQ vectors 32-63. Clear bit (0) for high priority tier, set bit (1) for low priority tier.'))

# IRQPRIU
r = RegisterTemplate(nameTemplate='IRQPRIU', registerMemorySlot=10, size=32, description='IRQ priority register (upper bits). Each bit sets priority tier for corresponding IRQ. Bit position corresponds to IRQ vector number 64 and above.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSIRQPRIU', msb=31, lsb=0, accessibility='rw', description='IRQ priority bits for IRQ vectors 64 and above. Clear bit (0) for high priority tier, set bit (1) for low priority tier.'))

# IRQCR
r = RegisterTemplate(nameTemplate='IRQCR', registerMemorySlot=11, size=8, description='IRQ control register. Controls global IRQ enable and interrupt recursion settings.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=2))
r.AddBitField(BitField(name='SYSIRQRECEN', msb=1, accessibility='rw', description='IRQ recursion enable. When set, allows interrupt service routines to be interrupted by higher priority IRQs.', valueDescriptions=[(0b0, 'IRQ recursion disabled'), (0b1, 'IRQ recursion enabled')]))
r.AddBitField(BitField(name='SYSIRQGEN', msb=0, accessibility='rw', description='Global IRQ enable. Master enable for all interrupts. When cleared, all IRQs are disabled regardless of individual enable bits.', valueDescriptions=[(0b0, 'All IRQs globally disabled'), (0b1, 'IRQs enabled per IRQEN registers')]))

# WDTCR
r = RegisterTemplate(nameTemplate='WDTCR', registerMemorySlot=12, size=8, description='Watchdog timer control register. This register is protected and requires password unlock via WDTPASS before writing. Configures watchdog operation mode and timeout period.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTEN', msb=7, accessibility='rw', description='Watchdog timer enable. When set, watchdog counter increments on MCLK. Watchdog generates interrupt and/or reset when counter bit selected by WDTCDIV transitions from 0 to 1. Register is write-protected; unlock with WDTPASS first.', valueDescriptions=[(0b0, 'Watchdog disabled'), (0b1, 'Watchdog enabled')]))
r.AddBitField(BitField(unused=True, msb=6))
r.AddBitField(BitField(name='SYSWDTCDIV', msb=5, lsb=2, accessibility='rw', description='Watchdog timer clock divider select. Selects which bit of the 24-bit counter triggers watchdog event. Event occurs when selected bit transitions from 0 to 1. Timeout period = 2^(WDTCDIV+16) MCLK cycles.', valueDescriptions=[(0b0000, 'Bit 16: 65,536 MCLK cycles', '_65536'), (0b0001, 'Bit 17: 131,072 MCLK cycles', '_131072'), (0b0010, 'Bit 18: 262,144 MCLK cycles', '_262144'), (0b0011, 'Bit 19: 524,288 MCLK cycles', '_524288'), (0b0100, 'Bit 20: 1,048,576 MCLK cycles', '_1048576'), (0b0101, 'Bit 21: 2,097,152 MCLK cycles', '_2097152'), (0b0110, 'Bit 22: 4,194,304 MCLK cycles', '_4194304'), (0b0111, 'Bit 23: 8,388,608 MCLK cycles', '_8388608'), (0b1000, 'Bit 24: 16,777,216 MCLK cycles', '_16777216'), (0b1001, 'Bit 25: 33,554,432 MCLK cycles', '_33554432'), (0b1010, 'Bit 26: 67,108,864 MCLK cycles', '_67108864'), (0b1011, 'Bit 27: 134,217,728 MCLK cycles', '_134217728'), (0b1100, 'Bit 28: 268,435,456 MCLK cycles', '_268435456'), (0b1101, 'Bit 29: 536,870,912 MCLK cycles', '_536870912'), (0b1110, 'Bit 30: 1,073,741,824 MCLK cycles', '_1073741824'), (0b1111, 'Bit 31: 2,147,483,648 MCLK cycles', '_2147483648')]))
r.AddBitField(BitField(name='SYSWDTIE', msb=1, accessibility='rw', description='Watchdog timer interrupt enable. When set, watchdog timeout generates an interrupt before reset. If SYSWDTEN is also set and SYSIRQEN is enabled for watchdog IRQ, system executes watchdog ISR. Upon ISR return, system resets if SYSWDTHWRST is set.', valueDescriptions=[(0b0, 'Watchdog interrupt disabled'), (0b1, 'Watchdog interrupt enabled')]))
r.AddBitField(BitField(name='SYSWDTHWRST', msb=0, accessibility='rw', description='Watchdog hardware reset enable. When set, watchdog timeout causes system reset. If WDTIE is set, reset occurs after interrupt service routine completes. If WDTIE is cleared or IRQ is not enabled, reset occurs immediately on timeout.', valueDescriptions=[(0b0, 'Watchdog reset disabled'), (0b1, 'Watchdog reset enabled')]))

# WDTSR
r = RegisterTemplate(nameTemplate='WDTSR', registerMemorySlot=13, size=8, description='Watchdog timer status register. Contains flags indicating watchdog reset and interrupt events. Flags are cleared by writing 1 to the respective bit.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=2))
r.AddBitField(BitField(name='SYSWDTIF', msb=1, accessibility='rw1', description='Watchdog timer interrupt flag. Set when watchdog timeout occurs and WDTIE is enabled. Cleared by writing 1 to this bit. If not cleared before next timeout, indicates watchdog event occurred.', valueDescriptions=[(0b0, 'No watchdog interrupt pending'), (0b1, 'Watchdog interrupt occurred')]))
r.AddBitField(BitField(name='SYSWDTRF', msb=0, accessibility='rw1', description='Watchdog timer reset flag. Set when system reset was caused by watchdog timer. Persists across resets until cleared by software. Cleared by writing 1 to this bit.', valueDescriptions=[(0b0, 'Reset not caused by watchdog'), (0b1, 'Reset caused by watchdog')]))

# WDTPASS
r = RegisterTemplate(nameTemplate='WDTPASS', registerMemorySlot=14, size=32, description='Watchdog timer password register. Write-only register for two security functions: (1) Write 0x3FB0AD1C to unlock WDTCR for 64 MCLK cycles, enabling writes to watchdog configuration. (2) Write 0xD6F402BC to clear watchdog counter to 0, preventing timeout. Reading always returns 0.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTPASS', msb=31, lsb=0, accessibility='w', description='Watchdog password. Write 0x3FB0AD1C (unlock password) to enable WDTCR writes for 64 MCLK cycles. Write 0xD6F402BC (clear password) to reset watchdog counter to 0.'))

# WDTVAL
r = RegisterTemplate(nameTemplate='WDTVAL', registerMemorySlot=15, size=32, description='Watchdog timer value register. Read-only register containing current watchdog counter value. Counter increments on MCLK when watchdog is enabled. Returns 0 when watchdog is disabled.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTVAL', msb=23, lsb=0, accessibility='r', description='Watchdog counter value. 24-bit up-counter that increments on MCLK cycles. Watchdog event occurs when bit selected by WDTCDIV transitions from 0 to 1.'))
r.AddBitField(BitField(unused=True, msb=31, lsb=24))

# DCO0BIAS
r = RegisterTemplate(nameTemplate='DCO0BIAS', registerMemorySlot=16, size=16, description='Digitally controlled oscillator 0 bias register. Controls DCO0 output frequency through bias voltage adjustment. Higher bias values generally produce higher frequencies.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=12))
r.AddBitField(BitField(name='SYSDCO0BIAS', msb=11, lsb=0, accessibility='rw', description='DCO0 bias adjustment value. 12-bit bias control for DCO0 frequency tuning. Default value loaded from constants on reset.'))

# DCO1BIAS
r = RegisterTemplate(nameTemplate='DCO1BIAS', registerMemorySlot=17, size=16, description='Digitally controlled oscillator 1 bias register. Controls DCO1 output frequency through bias voltage adjustment. Higher bias values generally produce higher frequencies.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=12))
r.AddBitField(BitField(name='SYSDCO1BIAS', msb=11, lsb=0, accessibility='rw', description='DCO1 bias adjustment value. 12-bit bias control for DCO1 frequency tuning. Default value loaded from constants on reset.'))

	
	
''' SPIx '''
p = PeripheralTemplate(nameTemplate='SPIx', description='Serial Peripheral Interface. Supports both master and slave modes with configurable data length (8, 16, or 32 bits), clock polarity, clock phase, and byte ordering. SPI0 includes flash extended memory capability for direct memory-mapped access to external SPI flash. SPI1 supports both master and slave modes without flash extended memory.', registerPrefix='SPIx', bitFieldPrefix='SPI', latexIntroFileName='SPI-intro-myshkin-2025-11.tex')
m.AddPeripheralTemplate(p)

# SPIxCR
r = RegisterTemplate(nameTemplate='SPIxCR', registerMemorySlot=0, description='SPI control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='SPIFEN', msb=19, accessibility='rw', description='SPI Flash extended memory enable. When enabled, allows native read-only memory access to the SPI flash memory via the system memory bus. The SPI peripheral automatically handles flash read commands and provides transparent memory-mapped access. Available only on SPI0; reads as 0 on SPI1.', valueDescriptions=[(0b0, 'Flash extended memory disabled'), (0b1, 'Flash extended memory enabled')]))
r.AddBitField(BitField(name='SPISM', msb=18, accessibility='rw', description='SPI slave mode select. Configures the SPI peripheral for master or slave operation. SPI0 is master-only; this bit has no effect on SPI0. SPI1 supports both master and slave modes.', valueDescriptions=[(0b0, 'Master mode'), (0b1, 'Slave mode')]))
r.AddBitField(BitField(name='SPITXSB', msb=17, accessibility='rw', description='SPI TX swap bytes. Swaps the byte order in 16- and 32-bit transmissions. In 32-bit transmissions, bytes 3 and 0 are swapped and bytes 2 and 1 are swapped. In 16-bit transmissions, bytes 1 and 0 are swapped. Does not affect 8-bit transmissions.', valueDescriptions=[(0b0, 'Bytes not swapped'), (0b1, 'Bytes swapped')]))
r.AddBitField(BitField(name='SPIRXSB', msb=16, accessibility='rw', description='SPI RX swap bytes. Swaps the byte order in 16- and 32-bit receptions. In 32-bit receptions, bytes 3 and 0 are swapped and bytes 2 and 1 are swapped. In 16-bit receptions, bytes 1 and 0 are swapped. Does not affect 8-bit receptions.', valueDescriptions=[(0b0, 'Bytes not swapped'), (0b1, 'Bytes swapped')]))
r.AddBitField(BitField(name='SPIBR', msb=15, lsb=8, description='SPI clock (SCK) baud rate control for master mode. Baud rate = SMCLK / (2 * (1 + SPIBR)). For example, with SMCLK at 24 MHz: SPIBR=0 gives 12 MHz, SPIBR=1 gives 8 MHz, SPIBR=2 gives 6 MHz, SPIBR=5 gives 4 MHz, SPIBR=11 gives 2 MHz, SPIBR=23 gives 1 MHz.', accessibility='rw'))
r.AddBitField(BitField(name='SPIEN', msb=7, description='SPI enable. When disabled, all SPI operations cease and the peripheral is held in reset state.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='SPIMSB', msb=6, description='Bit endianness select. Determines whether data is transmitted and received MSB-first or LSB-first.', accessibility='rw', valueDescriptions=[(0b0, 'LSB-first'), (0b1, 'MSB-first')]))
r.AddBitField(BitField(name='SPITCIE', msb=5, description='SPI transmit complete interrupt enable. Interrupt triggers when a full SPI transfer (transmit and receive) completes.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SPITEIE', msb=4, description='SPI transmit register empty interrupt enable. Interrupt triggers when SPIxTX register is empty and ready to accept new data for the next transfer.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SPIDL', msb=3, lsb=2, description='SPI transmission data length select. Determines the number of bits transferred per SPI transaction.', accessibility='rw', valueDescriptions=[(0b00, '8-bit transfers', '_8'), (0b01, '16-bit transfers', '_16'), (0b10, '32-bit transfers', '_32'), (0b11, 'Reserved (do not use)', '_RES')]))
r.AddBitField(BitField(name='SPICPOL', msb=1, description='SPI clock (SCK) polarity. Determines the idle state of the SCK line.', accessibility='rw', valueDescriptions=[(0b0, 'SCK idles low (SPIMODE0 or SPIMODE1)'), (0b1, 'SCK idles high (SPIMODE2 or SPIMODE3)')]))
r.AddBitField(BitField(name='SPICPHA', msb=0, description='SPI clock (SCK) phase. Determines when data is sampled relative to the SCK edge. In slave mode, only SPICPHA=1 is supported.', accessibility='rw', valueDescriptions=[(0b0, 'Data sampled on leading edge, shifted on trailing edge (SPIMODE0 or SPIMODE2)'), (0b1, 'Data shifted on leading edge, sampled on trailing edge (SPIMODE1 or SPIMODE3)')]))

# SPIxSR
r = RegisterTemplate(nameTemplate='SPIxSR', registerMemorySlot=1, description='SPI status register. Provides real-time status of SPI transfer operations and interrupt flags.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=3, unused=True))
r.AddBitField(BitField(name='SPIBUSY', msb=2, description='Indicates whether a SPI transfer is currently in progress. In master mode, set when a transfer starts and cleared when complete. In slave mode, set when chip select is asserted (driven low) and cleared when deasserted.', accessibility='r', valueDescriptions=[(0b0, 'SPI is idle'), (0b1, 'SPI transfer in progress')]))
r.AddBitField(BitField(name='SPITCIF', msb=1, description='SPI transfer complete interrupt flag. Set when a SPI transfer completes. Must be cleared by writing 1 to this bit or by reading SPIxRX register.', accessibility='rw1', valueDescriptions=[(0b0, 'No transfer completed'), (0b1, 'Transfer completed')]))
r.AddBitField(BitField(name='SPITEIF', msb=0, description='SPI transmit register empty interrupt flag. Set when SPIxTX register is empty and ready to accept new data. The data will not be transmitted until any current transfer completes. Must be cleared by writing 1 to this bit.', accessibility='rw1', valueDescriptions=[(0b0, 'SPIxTX not empty'), (0b1, 'SPIxTX empty and ready')]))

# SPIxTX
r = RegisterTemplate(nameTemplate='SPIxTX', registerMemorySlot=2, description='SPI transmit buffer register. In master mode, writing to this register initiates a new SPI transfer. In slave mode, writing to this register queues data to be transmitted during the next master-initiated transfer. Actual number of bits transmitted is determined by SPIDL setting.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SPITX', msb=31, lsb=0, accessibility='rw'))

# SPIxRX
r = RegisterTemplate(nameTemplate='SPIxRX', registerMemorySlot=3, description='SPI receive buffer register. Contains the data received during the most recent SPI transfer. Reading this register also clears the SPITCIF flag. Valid data width depends on SPIDL setting; unused upper bits read as 0.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SPIRX', msb=31, lsb=0, accessibility='r'))

# SPIxFOS
r = RegisterTemplate(nameTemplate='SPIxFOS', registerMemorySlot=4, description='SPI Flash memory address offset. This 24-bit value is added to memory access addresses when flash extended memory mode is enabled (SPIFEN=1). Allows remapping of flash memory to different virtual addresses. The addition wraps around at 0x00FFFFFF. Available only on SPI0; reads as 0 on SPI1.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=24, unused=True))
r.AddBitField(BitField(name='SPIFOS', msb=23, lsb=0, accessibility='rw'))



''' GPIOx '''
p = PeripheralTemplate(nameTemplate='GPIOx', description='General Purpose Input Output', registerPrefix='Px', bitFieldPrefix='Px', latexIntroFileName='GPIO-intro-2025-11.tex')
m.AddPeripheralTemplate(p)

# PxIN
r = RegisterTemplate(nameTemplate='PxIN', registerMemorySlot=0, description='GPIO read pin register. Each bit corresponds to the input logic state of the GPIO pin of the same number. The register is latched on the falling edge of the memory enable signal. Reading a 0 in a bit indicates a logic low pin state; reading a 1 indicates a logic high state. This register always reflects the pin state regardless of pin direction or peripheral select settings.', size=32)
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
r = RegisterTemplate(nameTemplate='PxOUTT', registerMemorySlot=4, description='GPIO output drive toggle register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to toggle the corresponding pin state. Writing a 0 has no effect. Reading this register is equivalent to reading the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTT', msb=31, lsb=0, accessibility='rw1'))

# PxDIR
r = RegisterTemplate(nameTemplate='PxDIR', registerMemorySlot=5, description='GPIO pin direction register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to set the corresponding pin to input mode; write a 1 to set to output mode.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxDIR', msb=31, lsb=0, accessibility='rw'))

# PxREN
r = RegisterTemplate(nameTemplate='PxREN', registerMemorySlot=6, description='GPIO resistor enable register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin pullup/pulldown resistor; write a 1 to enable the pin pullup/pulldown resistor.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxREN', msb=31, lsb=0, accessibility='rw'))

# PxSEL
r = RegisterTemplate(nameTemplate='PxSEL', registerMemorySlot=7, description='GPIO peripheral select register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to set the corresponding pin to GPIO (primary) mode; write a 1 to set the pin to secondary function (peripheral) mode. When a pin is in secondary function (peripheral) mode, the governing peripheral takes control of the pin output, direction, and resistor enable states, and the PxOUT, PxDIR, and PxREN registers have no effect on the pin. Pin interrupts remain available when in secondary function (peripheral) mode in addition to any interrupts the secondary function/peripheral may generate. If a pin has no secondary function defined, setting PxSEL to 1 will configure the pin as a high-impedance input.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxSEL', msb=31, lsb=0, accessibility='rw'))

# PxIF
r = RegisterTemplate(nameTemplate='PxIF', registerMemorySlot=8, description='GPIO interrupt flag register. Each bit corresponds to the GPIO pin of the same number. The register is latched on the falling edge of the memory enable signal. Reading a 0 in a bit indicates there is no pending interrupt for the corresponding pin; reading a 1 indicates there is a new interrupt pending for the corresponding pin. Write a 1 to each bit for which you wish to clear the interrupt flag. Writing 0 has no effect.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIF', msb=31, lsb=0, accessibility='rw1'))

# PxIES
r = RegisterTemplate(nameTemplate='PxIES', registerMemorySlot=9, description='GPIO interrupt edge select register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to set the corresponding pin interrupt to trigger on low-to-high (rising) edge; write a 1 to set to high-to-low (falling) edge triggering.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIES', msb=31, lsb=0, accessibility='rw'))

# PxIE
r = RegisterTemplate(nameTemplate='PxIE', registerMemorySlot=10, description='GPIO interrupt enable register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to disable the pin interrupt; write a 1 to enable the pin interrupt. Each pin has an individual interrupt output that connects to the system interrupt vector table. Interrupts function in both GPIO (primary) and secondary function (peripheral) modes.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIE', msb=31, lsb=0, accessibility='rw'))

## PxOCEN
#r = RegisterTemplate(nameTemplate='PxOCEN', registerMemorySlot=10, description='GPIO open collector register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin open-collector mode; write a 1 to enable the pin open-collector mode.', size=32)
#p.AddRegisterTemplate(r)



''' UARTx '''
p = PeripheralTemplate(nameTemplate='UARTx', description='Full-duplex Universal Asynchronous Receiver/Transmitter with hardware parity support', registerPrefix='UARTx', bitFieldPrefix='U', latexIntroFileName='UART-intro-2020-05.tex')
m.AddPeripheralTemplate(p)

# UARTxCR
r = RegisterTemplate(nameTemplate='UARTxCR', registerMemorySlot=0, description='UART control register. Controls UART enable, parity configuration, and interrupt enable bits. When UCR.EN is disabled, the UART peripheral is held in reset state.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='UEN', msb=5, description='UART enable. When disabled, the UART peripheral is in reset state and the transmitter is idle.', accessibility='rw', valueDescriptions=[(0b0, 'UART disabled'), (0b1, 'UART enabled')]))
r.AddBitField(BitField(name='UPEN', msb=4, description='Parity enable. Enables parity generation on transmit and parity checking on receive.', accessibility='rw', valueDescriptions=[(0b0, 'Parity disabled'), (0b1, 'Parity enabled')]))
r.AddBitField(BitField(name='PSEL', msb=3, description='Parity select. Selects even or odd parity when parity is enabled.', accessibility='rw', valueDescriptions=[(0b0, 'Even parity'), (0b1, 'Odd parity')]))
r.AddBitField(BitField(name='CIE', msb=2, description='Receive complete interrupt enable. Enables interrupt generation when a byte is successfully received.', accessibility='rw', valueDescriptions=[(0b0, 'RX complete interrupt disabled'), (0b1, 'RX complete interrupt enabled')]))
r.AddBitField(BitField(name='TEIE', msb=1, description='Transmit empty interrupt enable. Enables interrupt generation when the transmit buffer becomes empty and ready for new data.', accessibility='rw', valueDescriptions=[(0b0, 'TX empty interrupt disabled'), (0b1, 'TX empty interrupt enabled')]))
r.AddBitField(BitField(name='TCIE', msb=0, description='Transmit complete interrupt enable. Enables interrupt generation when transmission is complete and the transmitter is idle.', accessibility='rw', valueDescriptions=[(0b0, 'TX complete interrupt disabled'), (0b1, 'TX complete interrupt enabled')]))

# UARTxSR
r = RegisterTemplate(nameTemplate='UARTxSR', registerMemorySlot=1, description='UART status register. Contains receiver and transmitter status flags and interrupt flags. Error flags (FEF, PEF, OVF, RCIF) are cleared by reading UARTxRX. Interrupt flags (RCIF, TEIF, TCIF) can also be cleared by writing a 1 to the respective bit.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='RXBF', msb=7, description='Receiver busy flag. Set while the UART receiver is actively receiving a byte.', accessibility='r', valueDescriptions=[(0b0, 'Receiver idle'), (0b1, 'Reception in progress')]))
r.AddBitField(BitField(name='TXBF', msb=6, description='Transmitter busy flag. Set while the UART transmitter is actively transmitting a byte or has a pending transmission.', accessibility='r', valueDescriptions=[(0b0, 'Transmitter idle'), (0b1, 'Transmission in progress')]))
r.AddBitField(BitField(name='FEF', msb=5, description='Framing error flag. Set when the stop bit is not detected (RX line not high at expected stop bit time). Cleared by reading UARTxRX.', accessibility='r', valueDescriptions=[(0b0, 'No framing error'), (0b1, 'Framing error detected on last reception')]))
r.AddBitField(BitField(name='PEF', msb=4, description='Parity error flag. Set when received parity does not match expected parity (when parity is enabled). Cleared by reading UARTxRX.', accessibility='r', valueDescriptions=[(0b0, 'No parity error'), (0b1, 'Parity error detected on last reception')]))
r.AddBitField(BitField(name='OVF', msb=3, description='Receive overflow flag. Set when a new byte is received before the previous byte in UARTxRX was read by the processor. Cleared by reading UARTxRX.', accessibility='r', valueDescriptions=[(0b0, 'No receive data overrun'), (0b1, 'Receive data overflow detected')]))
r.AddBitField(BitField(name='RCIF', msb=2, description='Receive complete interrupt flag. Set when a byte is successfully received and placed in UARTxRX. Cleared by reading UARTxRX or writing a 1 to this bit.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending RX complete interrupt'), (0b1, 'RX complete interrupt pending')]))
r.AddBitField(BitField(name='TEIF', msb=1, description='Transmit empty interrupt flag. Set when the transmit buffer is empty and ready to accept new data. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending TX empty interrupt'), (0b1, 'TX empty interrupt pending')]))
r.AddBitField(BitField(name='TCIF', msb=0, description='Transmit complete interrupt flag. Set when transmission is complete (all bits sent) and the transmitter is idle. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending TX complete interrupt'), (0b1, 'TX complete interrupt pending')]))

# UARTxBR
r = RegisterTemplate(nameTemplate='UARTxBR', registerMemorySlot=2, description='UART baud rate register. Configures the baud rate divisor for the UART. The UART uses 16× oversampling.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=12, unused=True))
r.AddBitField(BitField(name='BR', msb=11, lsb=0, description='Baud rate divisor. UART baud rate = SMCLK ÷ (16 × (BR + 1)). For example, with SMCLK = 48 MHz: BR = 25 gives 115,200 baud; BR = 51 gives 57,600 baud; BR = 103 gives 28,800 baud.', accessibility='rw'))

# UARTxRX
r = RegisterTemplate(nameTemplate='UARTxRX', registerMemorySlot=3, description='UART receive buffer register. Contains the last received byte. Reading this register clears the FEF, PEF, OVF, and RCIF flags in UARTxSR. The value is latched on the falling edge of the memory enable signal.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='RX', msb=7, lsb=0, description='Received data byte', accessibility='r'))

# UARTxTX
r = RegisterTemplate(nameTemplate='UARTxTX', registerMemorySlot=4, description='UART transmit buffer register. Writing to this register loads the byte to transmit and initiates transmission. Do not write to this register while TXBF is set in UARTxSR.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TX', msb=7, lsb=0, description='Transmit data byte', accessibility='rw'))



''' TIMERx '''
p = PeripheralTemplate(nameTemplate='TIMERx', description='32-bit Timer/Counter with input capture, output compare, and pulse-width modulation functionality. Features glitch-free clock source switching and configurable clock division.', registerPrefix='TIMx', bitFieldPrefix='T', latexIntroFileName='TIMER-intro-2020-05.tex')
m.AddPeripheralTemplate(p)

# TIMxCR
r = RegisterTemplate(nameTemplate='TIMxCR', registerMemorySlot=0, description='Timer/Counter control register. Configures clock source, clock divider, capture/compare settings, and interrupt enables.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='DIV', msb=19, lsb=16, description='Timer/Counter clock divider. Divides the clock source selected by SSEL to generate the timer clock for TIMxVAL increments.', accessibility='rw', valueDescriptions=[(0, '/1 (no division)', '_1'), (1, '/2', '_2'), (2, '/4', '_4'), (3, '/8', '_8'), (4, '/16', '_16'), (5, '/32', '_32'), (6, '/64', '_64'), (7, '/128', '_128'), (8, '/256', '_256'), (9, '/512', '_512'), (10, '/1,024', '_1024'), (11, '/2,048', '_2048'), (12, '/4,096', '_4096'), (13, '/8,192', '_8192'), (14, '/16,384', '_16384'), (15, '/32,768', '_32768')]))
r.AddBitField(BitField(name='CMP1IH', msb=15, description='Compare 1 initial PWM output level. Sets the TxCMP1 pin level when TIMxVAL < TIMxCMP1.', accessibility='rw', valueDescriptions=[(0b0, 'PWM output starts LOW'), (0b1, 'PWM output starts HIGH')]))
r.AddBitField(BitField(name='CMP0IH', msb=14, description='Compare 0 initial PWM output level. Sets the TxCMP0 pin level when TIMxVAL < TIMxCMP0.', accessibility='rw', valueDescriptions=[(0b0, 'PWM output starts LOW'), (0b1, 'PWM output starts HIGH')]))
r.AddBitField(BitField(name='CAP1FE', msb=13, description='Capture 1 edge select. Selects which edge on TxCAP1 pin triggers a capture event.', accessibility='rw', valueDescriptions=[(0b0, 'Capture on rising edge'), (0b1, 'Capture on falling edge')]))
r.AddBitField(BitField(name='CAP0FE', msb=12, description='Capture 0 edge select. Selects which edge on TxCAP0 pin triggers a capture event.', accessibility='rw', valueDescriptions=[(0b0, 'Capture on rising edge'), (0b1, 'Capture on falling edge')]))
r.AddBitField(BitField(name='CAP1EN', msb=11, description='Capture 1 enable. Enables input capture on TxCAP1 pin.', accessibility='rw', valueDescriptions=[(0b0, 'Capture 1 disabled'), (0b1, 'Capture 1 enabled')]))
r.AddBitField(BitField(name='CAP0EN', msb=10, description='Capture 0 enable. Enables input capture on TxCAP0 pin.', accessibility='rw', valueDescriptions=[(0b0, 'Capture 0 disabled'), (0b1, 'Capture 0 enabled')]))
r.AddBitField(BitField(name='SSEL', msb=9, lsb=8, description='Timer/Counter clock source select. Glitch-free multiplexer prevents spurious transitions when switching sources.', accessibility='rw', valueDescriptions=[(0b00, 'SMCLK', '_SMCLK'), (0b01, 'MCLK', '_MCLK'), (0b10, 'LFXT (low frequency crystal)', '_LFXT'), (0b11, 'HFXT (high frequency crystal)', '_HFXT')]))
r.AddBitField(BitField(name='CMP2RST', msb=7, description='Timer/Counter reset on Compare 2 enable. Resets TIMxVAL to 0 when TIMxVAL equals TIMxCMP2.', accessibility='rw', valueDescriptions=[(0b0, 'Free-running mode (resets at 2³²-1)'), (0b1, 'Resets on TIMxVAL = TIMxCMP2')]))
r.AddBitField(BitField(name='TEN', msb=6, description='Timer/Counter enable. When disabled, timer clock is gated off and TIMxVAL holds its value.', accessibility='rw', valueDescriptions=[(0b0, 'Timer disabled'), (0b1, 'Timer enabled')]))
r.AddBitField(BitField(name='CAP1IE', msb=5, description='Capture 1 interrupt enable. Enables interrupt when CAP1IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CAP0IE', msb=4, description='Capture 0 interrupt enable. Enables interrupt when CAP0IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='OVIE', msb=3, description='Timer/Counter overflow interrupt enable. Enables interrupt when OVIF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CMP2IE', msb=2, description='Compare 2 interrupt enable. Enables interrupt when CMP2IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CMP1IE', msb=1, description='Compare 1 interrupt enable. Enables interrupt when CMP1IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CMP0IE', msb=0, description='Compare 0 interrupt enable. Enables interrupt when CMP0IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
# TIMxSR
r = RegisterTemplate(nameTemplate='TIMxSR', registerMemorySlot=1, description='Timer/Counter status register. Contains current compare output levels and interrupt flags. The register is latched on the falling edge of the memory enable signal for stable reads.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP1OUT', msb=7, description='Current value of the Compare 1 output pin TxCMP1. Reflects the actual PWM output level.', accessibility='r', valueDescriptions=[(0b0, 'TxCMP1 output LOW'), (0b1, 'TxCMP1 output HIGH')]))
r.AddBitField(BitField(name='CMP0OUT', msb=6, description='Current value of the Compare 0 output pin TxCMP0. Reflects the actual PWM output level.', accessibility='r', valueDescriptions=[(0b0, 'TxCMP0 output LOW'), (0b1, 'TxCMP0 output HIGH')]))
r.AddBitField(BitField(name='CAP1IF', msb=5, description='Capture 1 interrupt flag. Set when TxCAP1 pin triggers a capture event. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending capture 1 interrupt'), (0b1, 'Capture 1 interrupt pending')]))
r.AddBitField(BitField(name='CAP0IF', msb=4, description='Capture 0 interrupt flag. Set when TxCAP0 pin triggers a capture event. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending capture 0 interrupt'), (0b1, 'Capture 0 interrupt pending')]))
r.AddBitField(BitField(name='OVIF', msb=3, description='Timer/Counter overflow interrupt flag. Set when timer overflows from 2³²-1 to 0. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending overflow interrupt'), (0b1, 'Overflow interrupt pending')]))
r.AddBitField(BitField(name='CMP2IF', msb=2, description='Compare 2 interrupt flag. Set when TIMxVAL equals TIMxCMP2. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending compare 2 interrupt'), (0b1, 'Compare 2 interrupt pending')]))
r.AddBitField(BitField(name='CMP1IF', msb=1, description='Compare 1 interrupt flag. Set when TIMxVAL equals TIMxCMP1. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending compare 1 interrupt'), (0b1, 'Compare 1 interrupt pending')]))
r.AddBitField(BitField(name='CMP0IF', msb=0, description='Compare 0 interrupt flag. Set when TIMxVAL equals TIMxCMP0. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending compare 0 interrupt'), (0b1, 'Compare 0 interrupt pending')]))

# TIMxVAL
r = RegisterTemplate(nameTemplate='TIMxVAL', registerMemorySlot=2, description='Timer/Counter value register. Reads the current timer count. Writes immediately update the timer value regardless of enable state. The value is latched on the falling edge of the memory enable signal for stable reads.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='VAL', msb=31, lsb=0, description='Current timer count value', accessibility='rw'))

# TIMxCMP0
r = RegisterTemplate(nameTemplate='TIMxCMP0', registerMemorySlot=3, description='Timer/Counter Compare 0 threshold register. When TIMxVAL equals this value, CMP0IF is set and the TxCMP0 PWM output toggles.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP0', msb=31, lsb=0, description='Compare 0 threshold value', accessibility='rw'))

# TIMxCMP1
r = RegisterTemplate(nameTemplate='TIMxCMP1', registerMemorySlot=4, description='Timer/Counter Compare 1 threshold register. When TIMxVAL equals this value, CMP1IF is set and the TxCMP1 PWM output toggles.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP1', msb=31, lsb=0, description='Compare 1 threshold value', accessibility='rw'))

# TIMxCMP2
r = RegisterTemplate(nameTemplate='TIMxCMP2', registerMemorySlot=5, description='Timer/Counter Compare 2 threshold register. When TIMxVAL equals this value, CMP2IF is set. If CMP2RST is enabled, timer resets to 0 (PWM period control).', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP2', msb=31, lsb=0, description='Compare 2 threshold value (PWM period)', accessibility='rw'))

# TIMxCAP0
r = RegisterTemplate(nameTemplate='TIMxCAP0', registerMemorySlot=6, description='Timer/Counter Capture 0 value register. Automatically latches TIMxVAL when TxCAP0 pin edge triggers a capture event. The captured value is latched on the falling edge of the memory enable signal for stable reads.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CAP0', msb=31, lsb=0, description='Captured timer value from TxCAP0 event', accessibility='r'))

# TIMxCAP1
r = RegisterTemplate(nameTemplate='TIMxCAP1', registerMemorySlot=7, description='Timer/Counter Capture 1 value register. Automatically latches TIMxVAL when TxCAP1 pin edge triggers a capture event. The captured value is latched on the falling edge of the memory enable signal for stable reads.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CAP1', msb=31, lsb=0, description='Captured timer value from TxCAP1 event', accessibility='r'))



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

''' NPU '''
p = PeripheralTemplate(nameTemplate='NPU', description='Fixed-point multilayer perceptron (MLP) neural network processing unit. Computes a single fully-connected layer of a neural network: given an input vector and a synaptic weight matrix, it produces an output vector. Multiple layers can be computed sequentially by the CPU. Inputs and outputs are signed Q0.15 (signed int16) numbers. Synaptic weights are signed Q8.15 (signed int24) numbers. An optional bias weight and a logistic sigmoid approximation activation function are available. The input vector, output vector, and weight matrix must all reside in the same 16 KiB multiplexed SRAM.', registerPrefix='NPU', bitFieldPrefix='NPU', latexIntroFileName='NPU-intro-myshkin-2025-11.tex')
m.AddPeripheralTemplate(p)

# NPUCR
r = RegisterTemplate(nameTemplate='NPUCR', registerMemorySlot=0, description='NPU control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=19, unused=True))
r.AddBitField(BitField(name='NPUBEN', msb=18, description='Bias enable. When set, the last weight fetched for each output neuron is used as a bias term added to the accumulator before the activation function.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='NPUAEN', msb=17, description='Activation function enable. When set, the logistic sigmoid approximation activation function is applied to the accumulator output. When cleared, the raw accumulator output is used (linear/identity).', accessibility='rw', valueDescriptions=[(0b0, 'Disabled (linear output)'), (0b1, 'Enabled (logistic sigmoid approximation)')]))
r.AddBitField(BitField(name='NPUTHINK', msb=16, description='NPU computation start and status bit. Write 1 to start the NPU. Self-clears when the computation is complete. Poll this bit to determine when results are ready.', accessibility='rw1', valueDescriptions=[(0b0, 'Idle (computation complete or not started)'), (0b1, 'Running (write 1 to start)')]))
r.AddBitField(BitField(name='NPUNI', msb=15, lsb=8, description='Number of inputs in the input vector minus 1. The actual number of inputs is NPUNI + 1.', accessibility='rw'))
r.AddBitField(BitField(name='NPUNN', msb=7, lsb=0, description='Number of output neurons minus 1. The actual number of outputs is NPUNN + 1.', accessibility='rw'))

# NPUIVSAR
r = RegisterTemplate(nameTemplate='NPUIVSAR', registerMemorySlot=1, description='Input vector start address (word address, i.e. byte address divided by 4). Each input is a signed Q0.15 (signed int16) value stored in bits 15:0 of its 32-bit SRAM word; bits 31:16 are ignored. The input at index 0 is at word address NPUIVSAR. The input at index 1 is at word address NPUIVSAR + 1. The rest of the inputs follow in consecutive word addresses. Bits 1:0 are unused because the start address must be aligned to a 32-bit word boundary.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=14, unused=True))
r.AddBitField(BitField(name='NPUIVSAR', msb=13, lsb=2, description='Input vector start address (divided by 4)', accessibility='rw'))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))

# NPUWVSAR
r = RegisterTemplate(nameTemplate='NPUWVSAR', registerMemorySlot=2, description='Synaptic weight matrix start address (word address, i.e. byte address divided by 4). Each weight is a signed Q3.15 (signed 19-bit) value stored in bits 18:0 of its 32-bit SRAM word; bits 31:19 are ignored. Bit 18 is the sign bit. Weights are stored row-major, one per 32-bit word, in the following order: for each output neuron (0 through NPUNN), if bias is enabled (NPUBEN = 1), the first word in the row is the bias weight (multiplied by an implicit input of 1.0), followed by NPUNI + 1 synaptic weights for inputs 0 through NPUNI. If bias is disabled, each row contains NPUNI + 1 synaptic weights only. Bits 1:0 are unused because the start address must be aligned to a 32-bit word boundary.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=14, unused=True))
r.AddBitField(BitField(name='NPUWVSAR', msb=13, lsb=2, description='Synaptic weight matrix start address (divided by 4)', accessibility='rw'))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))

# NPUOVSAR
r = RegisterTemplate(nameTemplate='NPUOVSAR', registerMemorySlot=3, description='Output vector start address (word address, i.e. byte address divided by 4). Each output is a signed Q3.15 (signed 19-bit) value stored in bits 18:0 of its 32-bit SRAM word; bits 31:19 are unused. Bit 18 is the sign bit. The output at index 0 is written to word address NPUOVSAR. The output at index 1 is at word address NPUOVSAR + 1, and so on. Bits 1:0 are unused because the start address must be aligned to a 32-bit word boundary.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=14, unused=True))
r.AddBitField(BitField(name='NPUOVSAR', msb=13, lsb=2, description='Output vector start address (divided by 4)', accessibility='rw'))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))



''' SARADC '''
p = PeripheralTemplate(nameTemplate='SARADC', description='10-bit capacitive-DAC (CAPDAC) successive-approximation register analog-to-digital converter', registerPrefix='SARADC', bitFieldPrefix='SARADC', latexIntroFileName='SARADC-intro-myshkin-2025-11.tex')
m.AddPeripheralTemplate(p)

# SARADC_CR
r = RegisterTemplate(nameTemplate='SARADC_CR', registerMemorySlot=0, description='SAR ADC control register', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=9, unused=True))
r.AddBitField(BitField(name='SARADCCONTMEAS', msb=8, description='Continuous measurement mode enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='SARADCDATAIE', msb=7, description='Data valid interrupt enable', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SARADCDEBUG', msb=6, description='Debug mode', accessibility='rw', valueDescriptions=[(0b0, 'Normal operation'), (0b1, 'Debug mode')]))
r.AddBitField(BitField(name='SARADCEN', msb=5, description='ADC enable', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='SARADCSAMPLESTEP', msb=4, lsb=1, description='Initial value of the 4-bit sample-phase countdown counter. 0 gives the minimum sample time; larger values extend the sample phase by the corresponding number of clock cycles.', accessibility='rw'))
r.AddBitField(BitField(name='SARADCRESET', msb=0, description='ADC reset', accessibility='rw', valueDescriptions=[(0b0, 'Normal operation'), (0b1, 'Reset')]))

# SARADC_CDIV
r = RegisterTemplate(nameTemplate='SARADC_CDIV', registerMemorySlot=1, description='Reserved. This register slot is allocated in the memory map but is not implemented in hardware. Writes are ignored and reads return 0.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SARADCCDIV', msb=7, lsb=0, description='Reserved. Not implemented; reads as 0.', accessibility='rw'))

# SARADC_SR
r = RegisterTemplate(nameTemplate='SARADC_SR', registerMemorySlot=2, description='SAR ADC status register', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=4, unused=True))
r.AddBitField(BitField(name='SARADCRDY', msb=3, description='ADC ready', accessibility='r', valueDescriptions=[(0b0, 'ADC not ready'), (0b1, 'ADC ready')]))
r.AddBitField(BitField(name='SARADCOVF', msb=2, description='ADC overflow interrupt flag', accessibility='rw1', valueDescriptions=[(0b0, 'No overflow'), (0b1, 'Overflow occurred')]))
r.AddBitField(BitField(name='SARADCDATAVALID', msb=1, description='Data valid flag. Set by hardware when a conversion result is available. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'Data not valid'), (0b1, 'Data valid')]))
r.AddBitField(BitField(name='SARADCBUSY', msb=0, description='Conversion busy', accessibility='r', valueDescriptions=[(0b0, 'Idle'), (0b1, 'Busy')]))

# SARADC_DATA
r = RegisterTemplate(nameTemplate='SARADC_DATA', registerMemorySlot=3, description='SAR ADC data register. Holds the most recent 10-bit conversion result. Bits 15:10 read as zero.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=10, unused=True))
r.AddBitField(BitField(name='SARADCDATA', msb=9, lsb=0, description='ADC conversion result (10-bit)', accessibility='r'))

# SARADC_TPR
r = RegisterTemplate(nameTemplate='SARADC_TPR', registerMemorySlot=4, description='SAR ADC test port register. Selects which internal debug signal is routed to each digital test port when debug mode (DEBUG) is enabled. DTP0SEL (bits 3:0) controls DTP0; DTP1SEL (bits 7:4) controls DTP1. Both outputs are driven to 0 when DEBUG = 0. See the Digital Test Ports section for the full signal index table.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SARADCDTP1SEL', msb=7, lsb=4, description='Digital test port 1 select', accessibility='rw'))
r.AddBitField(BitField(name='SARADCDTP0SEL', msb=3, lsb=0, description='Digital test port 0 select', accessibility='rw'))



''' Opamp (NOT INCLUDED IN VESTARV - REMOVED) '''
# Removed DAC, Opamp, PCT peripherals - not present in vestarv chip
# AFE peripheral IS included in vestarv



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



''' AFE '''
p = PeripheralTemplate(nameTemplate='AFE', description='Dual-slope integrating ADC (DSADC) and potentiostat analog front end with programmable bias generation.', registerPrefix='AFE', bitFieldPrefix='AFE_', latexIntroFileName='AFE-intro-myshkin-2025-11.tex')
m.AddPeripheralTemplate(p)

# AFE_CR
r = RegisterTemplate(nameTemplate='AFE_CR', registerMemorySlot=0, size=32, description='AFE control register. Controls the DSADC, potentiostat, and analog test port. Bits 7:5 are not routed to any internal signal and should be written 0.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=24, unused=True))
r.AddBitField(BitField(name='AFE_RAMPNUM', msb=23, lsb=12, description='Number of DSADC ramp cycles per conversion (12-bit). Larger values give longer integration time and increased sensitivity at the cost of conversion speed.', accessibility='rw'))
r.AddBitField(BitField(name='AFE_ADCSEL', msb=11, description='ADC output multiplexer select.', accessibility='rw', valueDescriptions=[(0b0, 'DSADC result'), (0b1, 'SARADC result')]))
r.AddBitField(BitField(name='AFE_ATPSEL', msb=10, description='Analog test port signal select.', accessibility='rw', valueDescriptions=[(0b0, 'Potentiostat output'), (0b1, 'DSADC output')]))
r.AddBitField(BitField(name='AFE_ATPEN', msb=9, description='Analog test port enable.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='AFE_ADCEXTIN', msb=8, description='DSADC input source select.', accessibility='rw', valueDescriptions=[(0b0, 'External pin'), (0b1, 'Potentiostat output pad')]))
r.AddBitField(BitField(msb=7, lsb=5, unused=True))
r.AddBitField(BitField(name='AFE_CONTMEAS', msb=4, description='Continuous measurement mode. When set, the DSADC restarts automatically after each conversion without a software trigger.', accessibility='rw', valueDescriptions=[(0b0, 'Single conversion (triggered by writing AFE_ADC_VAL)'), (0b1, 'Continuous')]))
r.AddBitField(BitField(name='AFE_DACEN', msb=3, description='Enable the bias DACs for DSADC common-mode voltage (BIAS_DSADC_VCM) and potentiostat reference electrode voltage (BIAS_REV_POT). Must be set before starting a conversion.', accessibility='rw', valueDescriptions=[(0b0, 'DACs disabled'), (0b1, 'DACs enabled')]))
r.AddBitField(BitField(name='AFE_DATARDYIE', msb=2, description='Data-ready interrupt enable. When 1, an IRQ is generated when DATARDYIF is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='AFE_EN', msb=1, description='AFE enable. Gates the AFE peripheral clock. Must be 1 for any AFE operation.', accessibility='rw', valueDescriptions=[(0b0, 'AFE clock disabled'), (0b1, 'AFE clock enabled')]))
r.AddBitField(BitField(name='AFE_ADCEN', msb=0, description='DSADC enable. Must be 1 before triggering a conversion.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))

# AFE_TPR
r = RegisterTemplate(nameTemplate='AFE_TPR', registerMemorySlot=1, size=32, description='AFE test port register. Four 5-bit fields select which internal debug signal is driven onto each of the four digital test ports DTP0-DTP3. See the Digital Test Ports section for the full signal index table.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='AFE_DTP3SEL', msb=19, lsb=15, description='Digital test port 3 signal select (5-bit index into the debug vector)', accessibility='rw'))
r.AddBitField(BitField(name='AFE_DTP2SEL', msb=14, lsb=10, description='Digital test port 2 signal select', accessibility='rw'))
r.AddBitField(BitField(name='AFE_DTP1SEL', msb=9, lsb=5, description='Digital test port 1 signal select', accessibility='rw'))
r.AddBitField(BitField(name='AFE_DTP0SEL', msb=4, lsb=0, description='Digital test port 0 signal select', accessibility='rw'))

# AFE_SR
r = RegisterTemplate(nameTemplate='AFE_SR', registerMemorySlot=2, size=8, description='AFE status register.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=3, unused=True))
r.AddBitField(BitField(name='AFE_OVFIF', msb=2, description='Overflow interrupt flag. Set when a conversion completes while DATARDYIF is still set. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No overflow'), (0b1, 'Overflow: previous result was not read before new conversion completed')]))
r.AddBitField(BitField(name='AFE_DATARDYIF', msb=1, description='Data-ready interrupt flag. Set by hardware when a DSADC conversion completes. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No data ready'), (0b1, 'Conversion result available in AFE_ADC_VAL')]))
r.AddBitField(BitField(name='AFE_ADCACTIVE', msb=0, description='ADC active flag. High while the DSADC FSM is running a conversion.', accessibility='r', valueDescriptions=[(0b0, 'Idle'), (0b1, 'Conversion in progress')]))

# AFE_ADC_VAL
r = RegisterTemplate(nameTemplate='AFE_ADC_VAL', registerMemorySlot=3, size=16, description='DSADC result register. Reading returns the 12-bit result of the most recent conversion in bits 11:0; bits 15:12 read as zero. Writing any value to this register (when ADCEN = 1 and CONTMEAS = 0) triggers a new single-shot conversion.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=12, unused=True))
r.AddBitField(BitField(name='AFE_ADCVAL', msb=11, lsb=0, description='12-bit DSADC conversion result. Represents the number of ramp clock cycles counted before the comparator fired.', accessibility='r'))

# BIAS_CR
r = RegisterTemplate(nameTemplate='BIAS_CR', registerMemorySlot=4, size=8, description='Bias control register. Selects the bias source (internal generator or DACs) and enables the generator and its output buffers.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=5, unused=True))
r.AddBitField(BitField(name='USEDAC', msb=4, description='Bias source select.', accessibility='rw', valueDescriptions=[(0b0, 'Internal bias generator (use BIAS_ADJ to trim)'), (0b1, 'Bias DACs (BIAS_DBP/DBPC/DBN/DBNC)')]))
r.AddBitField(BitField(name='BUFEN', msb=3, description='Bias voltage buffer enable. Enables the output buffers on the internal global bias voltages.', accessibility='rw', valueDescriptions=[(0b0, 'Buffers disabled'), (0b1, 'Buffers enabled')]))
r.AddBitField(BitField(name='EN', msb=2, description='Internal bias generator enable.', accessibility='rw', valueDescriptions=[(0b0, 'Generator disabled'), (0b1, 'Generator enabled')]))
r.AddBitField(BitField(msb=1, lsb=0, unused=True))

# BIAS_ADJ
r = RegisterTemplate(nameTemplate='BIAS_ADJ', registerMemorySlot=5, size=8, description='Wide-swing cascode bias generator adjustment register. Higher codes produce smaller bias currents (smaller voltage across the bias resistor). Used when BIAS_USEDAC = 0. The nominal trim code depends on process corner; see characterization data.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='ADJ', msb=5, lsb=0, description='6-bit bias generator trim code (nominal = 37).', accessibility='rw'))

# BIAS_DBP
r = RegisterTemplate(nameTemplate='BIAS_DBP', registerMemorySlot=6, size=16, description='P-branch bias DAC register. Sets the global V_bp voltage for PMOS current sources when BIAS_USEDAC = 1.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='DBP', msb=13, lsb=0, description='14-bit P bias DAC code.', accessibility='rw'))

# BIAS_DBPC
r = RegisterTemplate(nameTemplate='BIAS_DBPC', registerMemorySlot=7, size=16, description='P-cascode bias DAC register. Sets the global V_bpc voltage for PMOS cascode transistors when BIAS_USEDAC = 1.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='DBPC', msb=13, lsb=0, description='14-bit P cascode bias DAC code.', accessibility='rw'))

# BIAS_DBNC
r = RegisterTemplate(nameTemplate='BIAS_DBNC', registerMemorySlot=8, size=16, description='N-cascode bias DAC register. Sets the global V_bnc voltage for NMOS cascode transistors when BIAS_USEDAC = 1.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='DBNC', msb=13, lsb=0, description='14-bit N cascode bias DAC code.', accessibility='rw'))

# BIAS_DBN
r = RegisterTemplate(nameTemplate='BIAS_DBN', registerMemorySlot=9, size=16, description='N-branch bias DAC register. Sets the global V_bn voltage for NMOS current sources when BIAS_USEDAC = 1.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='DBN', msb=13, lsb=0, description='14-bit N bias DAC code.', accessibility='rw'))

# BIAS_TC_POT
r = RegisterTemplate(nameTemplate='BIAS_TC_POT', registerMemorySlot=10, size=8, description='Potentiostat TIA tail-current bias trim register. Sets the quiescent current in the two-stage op-amp (A2) used as the transimpedance amplifier. Larger codes produce smaller currents.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='TC_POT', msb=5, lsb=0, description='6-bit tail-current trim code for the potentiostat TIA amplifier (A2).', accessibility='rw'))

# BIAS_LC_POT
r = RegisterTemplate(nameTemplate='BIAS_LC_POT', registerMemorySlot=11, size=8, description='Potentiostat TIA Miller lead-compensation resistor trim register. The two-stage op-amp (A2) uses a Miller capacitor with a series resistor Rc to improve phase margin. This register trims Rc to cancel right-half-plane zeros introduced by process variation.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='LC_POT', msb=5, lsb=0, description='6-bit Miller lead-compensation resistor Rc trim code for the potentiostat TIA (A2).', accessibility='rw'))

# BIAS_TIA_G_POT
r = RegisterTemplate(nameTemplate='BIAS_TIA_G_POT', registerMemorySlot=12, size=32, description='Potentiostat TIA feedback resistor Rf register. Encoded as a 17-bit thermometer code controlling 16 series 60 kohm resistors plus one 1 Mohm resistor; each bit closes a parallel analog switch that shorts the corresponding resistor. Asserting more bits reduces Rf and therefore lowers TIA gain, increasing the measurable current range. Maximum gain (Rf = ~2 Mohm, sensitivity = ~56 pA) requires all bits clear (0x00000); minimum gain requires all bits set (0x1FFFF, reset value).')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=17, unused=True))
r.AddBitField(BitField(name='TIA_G_POT', msb=16, lsb=0, description='17-bit TIA gain resistance DAC code.', accessibility='rw'))

# BIAS_DSADC_VCM
r = RegisterTemplate(nameTemplate='BIAS_DSADC_VCM', registerMemorySlot=13, size=16, description='Analog common-mode voltage (v_cm) DAC register. The generated voltage is applied to the non-inverting inputs of both the control amplifier (A1) and the TIA (A2), centring the output swing at V_DD/2 for single-supply operation. Midscale code 8192 produces V_DD/2. Must be enabled via DACEN (AFE_CR bit 3) before starting a conversion.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='DSADC_VCM', msb=13, lsb=0, description='14-bit v_cm R-2R DAC code. Midscale = 8192 gives V_DD/2.', accessibility='rw'))

# BIAS_REV_POT
r = RegisterTemplate(nameTemplate='BIAS_REV_POT', registerMemorySlot=14, size=16, description='Potentiostat excitation voltage (v_pattern) DAC register. The generated voltage is applied to the non-inverting input of the folded-cascode control amplifier (A1), which drives the counter electrode such that V_RE = v_pattern. Programming this register sets the working-to-reference electrode potential. For cyclic voltammetry, firmware increments or decrements this register over time; for chronoamperometry, it is stepped once to the desired overpotential. Must be enabled via DACEN (AFE_CR bit 3).')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=14, unused=True))
r.AddBitField(BitField(name='REV_POT', msb=13, lsb=0, description='14-bit v_pattern R-2R DAC code. Sets the WE-RE electrode potential.', accessibility='rw'))

# BIAS_TC_DSADC
r = RegisterTemplate(nameTemplate='BIAS_TC_DSADC', registerMemorySlot=15, size=8, description='DSADC bias current source (BTS) trim register.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='TC_DSADC', msb=5, lsb=0, description='6-bit tail-current trim code for the DSADC integrating amplifier.', accessibility='rw'))

# BIAS_LC_DSADC
r = RegisterTemplate(nameTemplate='BIAS_LC_DSADC', registerMemorySlot=16, size=8, description='DSADC integrating amplifier Miller lead-compensation resistor trim register. Adjusts the Rc zero-placement for proper phase margin in the two-stage integrator op-amp.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='LC_DSADC', msb=5, lsb=0, description='6-bit Miller lead-compensation resistor Rc trim code for the DSADC integrating amplifier.', accessibility='rw'))

# BIAS_RIN_DSADC
r = RegisterTemplate(nameTemplate='BIAS_RIN_DSADC', registerMemorySlot=17, size=8, description='DSADC integration resistor R1 trim register. R1 and the integration capacitor C1 define the ramp slope during the integration phase. On-chip resistors can vary up to +/-20% from nominal; this 6-bit trim code corrects the R1 value to maintain the desired R1*C1 time constant.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='RIN_DSADC', msb=5, lsb=0, description='6-bit R1 trim code for the DSADC integration resistor.', accessibility='rw'))

# BIAS_RFB_DSADC
r = RegisterTemplate(nameTemplate='BIAS_RFB_DSADC', registerMemorySlot=18, size=8, description='DSADC lead-compensation resistor R2 trim register. R2 is placed in series with the integration capacitor C1 to mitigate integrator output overshoot at the transition from integration to deintegration phase. On-chip resistors can vary up to +/-20% from nominal; this 6-bit trim code corrects R2 accordingly.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='RFB_DSADC', msb=5, lsb=0, description='6-bit R2 lead-compensation resistor trim code for the DSADC.', accessibility='rw'))






''' Check the peripheral templates for errors '''
m.CheckPeripheralTemplates()



''' Create Peripherals from PeripheralTemplates and add them to the memory map '''
# Based on MemoryMap.vhd peripheral slot assignments
GPIO0 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=0, peripheralMemorySlot=0, interruptPriority=1)	# GPIO0 at 0x4000
GPIO1 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=1, peripheralMemorySlot=1, interruptPriority=28)	# GPIO1 at 0x4100
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=0, peripheralMemorySlot=2, interruptPriority=9)	# SPI0 at 0x4200
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=1, peripheralMemorySlot=3, interruptPriority=11)	# SPI1 at 0x4300
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=0, peripheralMemorySlot=4, interruptPriority=13)	# UART0 at 0x4400
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=1, peripheralMemorySlot=5, interruptPriority=52)	# UART1 at 0x4500
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=0, peripheralMemorySlot=6, interruptPriority=16)	# TIMER0 at 0x4600
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=1, peripheralMemorySlot=7, interruptPriority=22)	# TIMER1 at 0x4700
GPIO2 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=2, peripheralMemorySlot=8, interruptPriority=36)	# GPIO2 at 0x4800
m.CreatePeripheral(nameTemplate='SYSTEM', nameIndex='', peripheralMemorySlot=9, interruptPriority=0)	# SYSTEM at 0x4900
m.CreatePeripheral(nameTemplate='NPU', nameIndex='', peripheralMemorySlot=10, interruptPriority=None)	# NPU at 0x4A00
m.CreatePeripheral(nameTemplate='SARADC', nameIndex='', peripheralMemorySlot=11, interruptPriority=56)	# SARADC at 0x4B00
m.CreatePeripheral(nameTemplate='AFE', nameIndex='', peripheralMemorySlot=12, interruptPriority=55)	# AFE at 0x4C00
GPIO3 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=3, peripheralMemorySlot=13, interruptPriority=44)	# GPIO3 at 0x4D00
m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=0, peripheralMemorySlot=14, interruptPriority=57)	# I2C0 at 0x4E00
m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=1, peripheralMemorySlot=15, interruptPriority=70)	# I2C1 at 0x4F00



# TODO!!
''' Create the package and power domains '''
# List of necessary pins for a hypothetical /home/mseminario/vestarv/sw/ChipGenerator/latex/MCU-User-Guide44 package: West = {3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23}, South = {28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48} East = {53, 55, 57, 59, 61, 63, 65, 67, 69, 71, 73} North = {78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98}
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
	pinCount=44,
	units='mm',
	dimensions=[7, 7],
	pinsOnEachSide={'W': 11, 'S': 11, 'E': 11, 'N': 11},
	pinPitch=0.5,
	pinWidth=0.25,
	pinDepth=0.4
)

digitalIOPowerDomain = package.AddPowerDomain(
	powerDomainName='Digital I/O',
	positiveVoltage=3.3,
	negativeVoltage=0.0,
	positiveRailPinNumber=12,
	positiveRailPinName='VDDPST',
	negativeRailPinNumber=21,
	negativeRailPinName='VSSPST',
	isGpioPowerDomain=True
)

digitalCorePowerDomain = package.AddPowerDomain(
	powerDomainName='Digital Core',
	positiveVoltage=1.0,
	negativeVoltage=0.0,
	positiveRailPinNumber=10,
	positiveRailPinName='VDD',
	negativeRailPinNumber=22,
	negativeRailPinName='VSS'
)

analogPowerDomain = package.AddPowerDomain(
	powerDomainName='Analog',
	positiveVoltage=3.3,
	negativeVoltage=0.0,
	positiveRailPinNumber=37,
	positiveRailPinName='AVDD',
	negativeRailPinNumber=32,
	negativeRailPinName='AVSS'
)

# Special pins
package.AddPin(packagePinNumber=11, name='RESETN', ioType='i', powerDomain=digitalIOPowerDomain)
package.AddPin(packagePinNumber=23, name='NC', ioType='', noConnect=True)
package.AddPin(packagePinNumber=36, name='ATP-OUT', ioType='o', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=35, name='ATP-IN', ioType='i', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=34, name='CE', ioType='io', powerDomain=analogPowerDomain)
package.AddPin(packagePinNumber=33, name='RE', ioType='io', powerDomain=analogPowerDomain)





''' Add pins to the GPIO ports (and optionally change the GPIO port sizes) '''
''' WARNING: Look at the documentation for GpioConfigurator.__init__() for important instructions on how to use the function, especially concerning the funcIOType argument '''
# GPIO0 (P1.0-P1.7)
GPIO0.ChangeGPIOPortSize(8)

GPIO0.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO0', funcName='CS_FLASH', funcIOType='o',	rstOUT=1, rstDIR=1, rstSEL=0, rstREN=0, description='Chip select pin for SPI flash memory'), packagePinNumber=31) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO1', funcName='MISO0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 Master In Slave Out (connected to SPI flash memory)'), packagePinNumber=30) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO2', funcName='MOSI0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 Master Out Slave In (connected to SPI flash memory)'), packagePinNumber=29) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO3', funcName='SCK0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 serial clock (connected to SPI flash memory)'), packagePinNumber=28) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO4', funcName='LFXT', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='Low frequency external clock'), packagePinNumber=27) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO5', funcName='HFXT', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='High frequency external clock'), packagePinNumber=26) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO6', funcName='TRAP', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='CPU trap state'), packagePinNumber=25) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=7, primaryName='BOOT', funcName='', funcIOType='',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=1, description='Boot select pin (Boots to forth interpreter when LOW, boots from SPI flash when HIGH)'), packagePinNumber=24) # necessary

# GPIO1 (P2.0-P2.7)
GPIO1.ChangeGPIOPortSize(8)

GPIO1.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO8', funcName='CS1', funcIOType='i',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 chip select'), packagePinNumber=20) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO9', funcName='MISO1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 Master In Slave Out'), packagePinNumber=19) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO10', funcName='MOSI1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 Master Out Slave In'), packagePinNumber=18) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO11', funcName='SCK1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='SPI1 serial clock'), packagePinNumber=17) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO12', funcName='TX0', funcIOType='o',		rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='UART0 transmitter'), packagePinNumber=16) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO13', funcName='RX0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='UART0 receiver'), packagePinNumber=15) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO14', funcName='TX1', funcIOType='o',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='UART1 transmitter'), packagePinNumber=14) # necessary
GPIO1.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO15', funcName='RX1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='UART1 receiver'), packagePinNumber=13) # necessary

# GPIO2 (P3.0-P3.7)
GPIO2.ChangeGPIOPortSize(8)

GPIO2.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO16', funcName='T0CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 0'), packagePinNumber=9) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO17', funcName='T0CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 1'), packagePinNumber=8) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO18', funcName='T0CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Capture 0'), packagePinNumber=7) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO19', funcName='T0CAP1', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Capture 1'), packagePinNumber=6) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO20', funcName='T1CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 Compare 0'), packagePinNumber=5) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO21', funcName='T1CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 Compare 1'), packagePinNumber=4) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO22', funcName='T1CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 Capture 0'), packagePinNumber=3) # necessary
GPIO2.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO23', funcName='T1CAP1', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER1 Capture 1'), packagePinNumber=2) # necessary

# GPIO3 (P4.0-P4.7)
GPIO3.ChangeGPIOPortSize(8)

GPIO3.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO24', funcName='SDA0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial data'), packagePinNumber=1) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO25', funcName='SCL0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial clock'), packagePinNumber=44) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO26', funcName='SDA1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C1 serial data'), packagePinNumber=43) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO27', funcName='SCL1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C1 serial clock'), packagePinNumber=42) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO28', funcName='DTP0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 0'), packagePinNumber=41) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO29', funcName='DTP1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 1'), packagePinNumber=40) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO30', funcName='DTP2', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 2'), packagePinNumber=39) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO31', funcName='DTP3', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 3'), packagePinNumber=38) # necessary


''' Check for errors '''
m.CheckPeripherals()
m.CheckPackagePins()


''' Generate all output files '''
# TODO: Enable saveHardware=True once MCU.vhd has the required "Begin Automatically Generated" headers
# For now, only generating software files and documentation
m.Generate(test=False, force=True, saveHardware=True, saveSoftware=True)

