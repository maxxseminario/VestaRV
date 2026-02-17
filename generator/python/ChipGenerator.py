import pathlib, os, json, datetime
from shutil import ExecError

from Peripheral import PeripheralTemplate, Peripheral
from Register import RegisterTemplate, Register
from BitField import BitField
from Package import PackageData, PackagePin, PowerDomain
from GpioConfigurator import GpioConfigurator
from TabbedTable import TabbedTable
from LatexUserGuide import LatexUserGuide

class ChipGenerator():
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	ChipRootDirectory = None

	AsicName = None
	AsicNameForUserGuide = None
	McuUserGuideLatexTemplateFileName = None

	PeripheralTemplates = None
	SymbolTemplates = None
	
	Peripherals = None
	Symbols = None
	AddressTable = None
	
	RomStartAddress = None
	RomSize = None	# In bytes
	RomEndAddress = None	# The address of the last address in the ROM
	
	PeripheralMemoryStartAddress = None
	PeripheralMemorySize = None	# In bytes
	PeripheralMemorySlotCount = None
	RegisterMemorySlotsPerPeripheralMemorySlot = None
	PeripheralMemorySlotSize = None	# In bytes
	PeripheralMemoryEndAddress = None	# The address of the last address in the peripheral memory
	
	RamStartAddress = None
	RamSize = None	# In bytes
	RamMemorySlotSize = None	# In bytes
	LastRamMemorySlotSize = None	# In bytes
	RamMemorySlotsAvailable = None
	RamMemorySlotsUsed = None
	RamMemorySlotsMuxed = None
	RamEndAddress = None	# The address of the last address in the RAM memory
	SpiFlashProgramAddress = None	# The address that the program is written to / read from the SPI flash. This can be different from the location the program is inserted into RAM when booting to SPI flash mode
	NativeSpiFlashMemoryReadAccess = None
	NativeSpiFlashMemoryWriteAccess = None
	
	VectorsStartAddress = None	# Address of the interrupt vector table
	VectorsSize = None	# The size of the interrupt vector table in bytes
	VectorsCount = None	# The number of entries in the interrupt vector table
	VectorsEndAddress = None	# The end address of the interrupt vector table (inclusive)
	RamProgramStartAddress = None	# The initial execution point of the program stored on RAM
	ProgramCounterInit = None	# The program counter value on reset
	StackPointerInit = None	# The stack pointer initial value (this is not a reset value, it must be done in software)
	BootloaderUsesSpiFlashCommands = None	# Determines what format the bootloader expects the program to be in on the SPI flash
	ExtraMemorySections = None	# [(SECTION_NAME (rwx), ORIGIN = 0x?, LENGTH = 0x?, notes), ...]
	
	NeedToCheckPeripheralTemplates = None
	NeedToCheckPeripherals = None

	PadOUTPosLogic = None
	PadDIRPosLogic = None
	PadRENPosLogic = None
	#PadOCENPosLogic = None

	ENABLE_IRQ_FAST_CONTEXT_SWITCHING = None	# Enables/disables fast IRQ context switching. When enabled, entering interrupt-handling mode will automatically save the CPU registers to a register file. When the retirq instruction is called, the CPU registers will be restored to their saved values
	ENABLE_COUNTERS = None		# Enables/disables support for the RDCYCLE[H], RDTIME[H], and RDINSTRET[H] instructions. If disabled, these instructions will cause a hardware trap like any other unsupported instruction
	ENABLE_COUNTERS64 = None	# Enables/disables support for RDCYCLEH, RDTIMEH, and RDINSTRETH instructions.
	ENABLE_REGS_DUALPORT = None	# Enables/disables dual access to general purpose registers
	LATCHED_MEM_RDATA = None	# If picorv32/mem_rdata is kept stable by the AD after a memory transaction, set this to 1. For chips up to pingora2, this was always False
	TWO_STAGE_SHIFT = None		# Enables/disables a two-stage bit shift operation. When enabled, this is a medium-speed shift. When disabled, it is slow
	BARREL_SHIFTER = None		# Enables/disables the fast barrel bit shift operation. Overrides TWO_STAGE_SHIFT when enabled
	COMPRESSED_ISA = None		# Enables/disables the compressed ISA extension RV32IC
	ENABLE_MUL = None			# Enables/disables the hardware multiplier
	ENABLE_FAST_MUL = None		# Enables/disables the fast hardware multiplier. If both ENABLE_FAST_MUL and ENABLE_MUL are enabled, the ENABLE_MUL is ignored and the fast hardware multiplier is instantiated
	ENABLE_DIV = None			# Enables/disables the hardware divider and remainder calculator
	ENABLE_IRQ_QREGS = None		# Enables/disables the four IRQ registers, which help speed IRQ calls
	ENABLE_IRQ_TIMER = None		# Enables/disables the "timer" custom instruction. For chips up to pingora2, this was always True
	MASKED_IRQ = None			# Any '1' bit corresponds to a permenantely disabled IRQ
	PROGADDR_IRQ = None			# The address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)

	Package = PackageData

	
	
	def __init__(self,
		chipRootDirectory:str,
		asicName:str,
		asicNameForUserGuide:str,
		mcuUserGuideLatexTemplateFileName:str,
		romStartAddress:int,
		romSize:int,
		peripheralMemoryStartAddress:int,
		peripheralMemorySlotCount:int,
		registerMemorySlotsPerPeripheralMemorySlot:int,
		ramStartAddress:int,
		ramMemorySlotSize:int,
		ramMemorySlotsAvailable:int,
		ramMemorySlotsUsed:int,
		ramMemorySlotsMuxed,
		spiFlashProgramAddress:int,
		nativeSpiFlashMemoryReadAccess:bool,
		nativeSpiFlashMemoryWriteAccess:bool,
		stackPointerInit,
		bootloaderUsesSpiFlashCommands:bool,
		vectorsCount:int,
		padOutPosLogic:bool,
		padDIRPosLogic:bool,
		padRENPosLogic:bool,
		ENABLE_COUNTERS:bool,
		ENABLE_COUNTERS64:bool,
		ENABLE_REGS_DUALPORT:bool,
		LATCHED_MEM_RDATA: bool,
		TWO_STAGE_SHIFT:bool,
		BARREL_SHIFTER:bool,
		COMPRESSED_ISA:bool,
		ENABLE_MUL:bool,
		ENABLE_FAST_MUL:bool,
		ENABLE_DIV:bool,
		ENABLE_IRQ_FAST_CONTEXT_SWITCHING:bool,
		ENABLE_IRQ_QREGS:bool,
		ENABLE_IRQ_TIMER:bool,
		MASKED_IRQ:int,
		PROGADDR_IRQ:int,
		lastRamMemorySlotSize:int=None):
		# Initialize lists
		self.PeripheralTemplates = []
		self.Peripherals = []

		# Check root directory
		if not os.path.isdir(chipRootDirectory):
			raise Exception('chipRootDirectory is not a valid directory: ' + str(chipRootDirectory))
		self.ChipRootDirectory = os.path.abspath(chipRootDirectory).replace('\\', '/')
		while '//' in self.ChipRootDirectory:
			self.ChipRootDirectory.replace('//', '/')
		if self.ChipRootDirectory.count('/') > 1 and self.ChipRootDirectory.endswith('/'):
			self.ChipRootDirectory = self.ChipRootDirectory[:-1]

		# Check Name
		if len(asicName) < 1:
			raise Exception('asicName cannot be empty')
		for c in asicName:
			if c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_':
				raise Exception('Illegal character \"' + c + '\" in asicName')
		self.AsicName = asicName
		self.AsicNameForUserGuide = asicNameForUserGuide
		self.McuUserGuideLatexTemplateFileName = mcuUserGuideLatexTemplateFileName
		
		# Check ROM addresses
		if type(romStartAddress) != int:
			raise Exception('romStartAddress must be an int >= 0')
		if romStartAddress < 0:
			raise Exception('romStartAddress must be an int >= 0')
		if romStartAddress > 0 and not self.isPower2(romStartAddress):
			raise Exception('romStartAddress must be a power of 2')
		if type(romSize) != int:
			raise Exception('romSize must be an int > 0')
		if romSize < 1:
			raise Exception('romSize must be an int > 0')
		if not self.isPower2(romSize):
			raise Exception('romSize must be a power of 2')
		
		self.RomStartAddress = romStartAddress
		self.RomSize = romSize
		self.RomEndAddress = romStartAddress + romSize - 1
		
		# Check peripheral addresses
		if type(peripheralMemoryStartAddress) != int:
			raise Exception('peripheralMemoryStartAddress must be an int >= 0')
		if peripheralMemoryStartAddress < 0:
			raise Exception('peripheralMemoryStartAddress must be an int >= 0')
		if peripheralMemoryStartAddress > 0 and not self.isPower2(peripheralMemoryStartAddress):
			raise Exception('peripheralMemoryStartAddress must be a power of 2')
		if type(peripheralMemorySlotCount) != int:
			raise Exception('peripheralMemorySlotCount must be an int > 0')
		if peripheralMemorySlotCount < 1:
			raise Exception('peripheralMemorySlotCount must be an int > 0')
		if not self.isPower2(peripheralMemorySlotCount):
			raise Exception('peripheralMemorySlotCount must be a power of 2')
		if type(registerMemorySlotsPerPeripheralMemorySlot) != int:
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot must be an int > 0')
		if registerMemorySlotsPerPeripheralMemorySlot < 1:
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot must be an int > 0')
		if not self.isPower2(registerMemorySlotsPerPeripheralMemorySlot):
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot must be a power of 2')
		
		self.PeripheralMemoryStartAddress = peripheralMemoryStartAddress
		self.PeripheralMemorySlotCount = peripheralMemorySlotCount
		self.RegisterMemorySlotsPerPeripheralMemorySlot = registerMemorySlotsPerPeripheralMemorySlot
		self.PeripheralMemorySlotSize = registerMemorySlotsPerPeripheralMemorySlot * 4
		self.PeripheralMemorySize = peripheralMemorySlotCount * self.PeripheralMemorySlotSize
		self.PeripheralMemoryEndAddress = peripheralMemoryStartAddress + self.PeripheralMemorySize - 1
		
		# Check RAM addresses
		if type(ramStartAddress) != int:
			raise Exception('ramStartAddress must be an int >= 0')
		if ramStartAddress < 0:
			raise Exception('ramStartAddress must be an int >= 0')
		if ramStartAddress > 0 and not self.isPower2(ramStartAddress):
			raise Exception('ramStartAddress must be a power of 2')
		if type(ramMemorySlotSize) != int:
			raise Exception('ramMemorySlotSize must be an int > 0')
		if ramMemorySlotSize < 4:
			raise Exception('ramMemorySlotSize must be an int > 0')
		if not self.isPower2(ramMemorySlotSize):
			raise Exception('ramMemorySlotSize must be a power of 2')
		if lastRamMemorySlotSize is None:
			lastRamMemorySlotSize = ramMemorySlotSize
		if lastRamMemorySlotSize < 4:
			raise Exception('lastRamMemorySlotSize must be an int > 0')
		if not self.isPower2(lastRamMemorySlotSize):
			raise Exception('lastRamMemorySlotSize must be a power of 2')
		if lastRamMemorySlotSize > ramMemorySlotSize:
			raise Exception('lastRamMemorySlotSize must be <= ramMemorySlotSize')
		
		if type(ramMemorySlotsAvailable) != list:
			raise Exception('ramMemorySlotsAvailable must be a list with unique integers >= 0 indicating the indices of all available RAM memory slots on the MCU address decoder')
		for slot in ramMemorySlotsAvailable:
			if type(slot) != int:
				raise Exception('ramMemorySlotsAvailable must be a list with unique integers >= 0 indicating the indices of all available RAM memory slots on the MCU address decoder')
			if slot < 0:
				raise Exception('ramMemorySlotsAvailable must be a list with unique integers >= 0 indicating the indices of all available RAM memory slots on the MCU address decoder')
			if ramMemorySlotsAvailable.count(slot) != 1:
				raise Exception('Each available RAM memory slot may be declared only once. Slot #' + str(slot) + ' is being declared more than once')
			if 0 in ramMemorySlotsAvailable or 1 in ramMemorySlotsAvailable:
				raise Exception('Neither 0 nor 1 may be in ramMemorySlotsAvailable. This is because the ROM and the peripheral memory technically take slots 0 and 1.')
		if type(ramMemorySlotsUsed) != list:
			raise Exception('ramMemorySlotsUsed must be a list with unique integers >= 0 indicating the indices of all RAM memory slots populated with a RAM cell in the MCU')
		for slot in ramMemorySlotsUsed:
			if type(slot) != int:
				raise Exception('ramMemorySlotsUsed must be a list with unique integers >= 0 indicating the indices of all available RAM memory slots on the MCU address decoder')
			if slot < 0:
				raise Exception('ramMemorySlotsUsed must be a list with unique integers >= 0 indicating the indices of all available RAM memory slots on the MCU address decoder')
			if ramMemorySlotsUsed.count(slot) != 1:
				raise Exception('Each RAM memory slot may be used only once. Slot #' + str(slot) + ' is being used more than once')
			if slot not in ramMemorySlotsAvailable:
				raise Exception('RAM memory slot #' + str(slot) + 'is not available for use')
		if type(ramMemorySlotsMuxed) != list and type(ramMemorySlotsMuxed) != dict:
			raise Exception('ramMemorySlotsMuxed must be a list with unique integers >= 0 indicating the indices of all RAM memory slots that are multiplexed with some hardware peripheral. Optionally, it can also be a dict with the same indices whose keys represent the text description of what the memory slot is MUXed with.')
		for slot in ramMemorySlotsMuxed:
			if type(slot) != int:
				raise Exception('ramMemorySlotsMuxed must be a list with unique integers >= 0 indicating the indices of all RAM memory slots that are multiplexed with some hardware peripheral. Optionally, it can also be a dict with the same indices whose keys represent the text description of what the memory slot is MUXed with.')
			if slot < 0:
				raise Exception('ramMemorySlotsMuxed must be a list with unique integers >= 0 indicating the indices of all RAM memory slots that are multiplexed with some hardware peripheral. Optionally, it can also be a dict with the same indices whose keys represent the text description of what the memory slot is MUXed with.')
			if type(ramMemorySlotsMuxed) != dict and ramMemorySlotsMuxed.count(slot) != 1:
				raise Exception('Each RAM memory slot may be used only once. Slot #' + str(slot) + ' is being used more than once')
			if slot not in ramMemorySlotsAvailable:
				raise Exception('RAM memory slot #' + str(slot) + 'is not available for use')
		if not set(ramMemorySlotsMuxed).issubset(ramMemorySlotsUsed):
			raise Exception('ramMemorySlotsMuxed may only contain slots that are also in ramMemorySlotsUsed')
		ramMemorySlotsMuxedMax = float('inf')
		if len(ramMemorySlotsMuxed) > 0:
			max(ramMemorySlotsMuxed)
		if min(set(ramMemorySlotsUsed).difference(ramMemorySlotsMuxed)) > ramMemorySlotsMuxedMax:
			raise Exception('All MUXed RAM memory slots must come at the end of the RAM memory without any non-muxed RAM memory slots in between.')
		
		if type(spiFlashProgramAddress) != int or spiFlashProgramAddress < 0 or (spiFlashProgramAddress % 256) != 0:
			raise Exception('spiFlashProgramAddress must be an int > 0 and must be divisible by 256')
		self.SpiFlashProgramAddress = spiFlashProgramAddress
		
		self.NativeSpiFlashMemoryReadAccess = nativeSpiFlashMemoryReadAccess
		self.NativeSpiFlashMemoryWriteAccess = nativeSpiFlashMemoryWriteAccess
		
		self.RamStartAddress = ramStartAddress
		self.RamMemorySlotSize = ramMemorySlotSize
		self.LastRamMemorySlotSize = lastRamMemorySlotSize
		self.RamMemorySlotsAvailable = sorted(ramMemorySlotsAvailable)
		for i in range(len(self.RamMemorySlotsAvailable) - 1):
			if self.RamMemorySlotsAvailable[i + 1] - self.RamMemorySlotsAvailable[i] != 1:
				raise Exception('Missing RAM slots are not allowed in between available RAM memory slots')
		self.RamMemorySlotsUsed = sorted(ramMemorySlotsUsed)
		if type(ramMemorySlotsMuxed) == dict:
			self.RamMemorySlotsMuxed = ramMemorySlotsMuxed
		else:
			self.RamMemorySlotsMuxed = sorted(ramMemorySlotsMuxed)
		for i in range(len(self.RamMemorySlotsUsed) - 1):
			if self.RamMemorySlotsUsed[i + 1] - self.RamMemorySlotsUsed[i] != 1:
				raise Exception('Missing RAM slots are not allowed in between used RAM memory slots')
		self.RamSize = ((len(self.RamMemorySlotsUsed) - 1) * self.RamMemorySlotSize) + self.LastRamMemorySlotSize
		self.RamEndAddress = self.RamStartAddress + self.RamSize - 1
		
		# Check for alignment issues
		if self.RomStartAddress % self.RomSize != 0:
			raise Exception('ROM must be aligned on a ' + str(self.RomSize) + '-byte boundary')
		
		if self.PeripheralMemoryStartAddress % self.PeripheralMemorySlotSize != 0:
			raise Exception('All peripheral memory slots must be aligned on a ' + str(self.PeripheralMemorySlotSize) + '-byte boundary')
		
		if self.RamStartAddress % self.RamMemorySlotSize != 0:
			raise Exception('All RAM slots must be aligned on a ' + str(self.RamMemorySlotSize) + '-byte boundary')
		
		# Check for overlaps
		romRange = range(self.RomStartAddress, self.RomEndAddress + 1)
		peripheralRange = range(self.PeripheralMemoryStartAddress, self.PeripheralMemoryEndAddress + 1)
		ramRange = range(self.RamStartAddress, self.RamEndAddress + 1)
		
		overlap1 = list(set(romRange) & set(peripheralRange))
		overlap2 = list(set(peripheralRange) & set(ramRange))
		overlap3 = list(set(ramRange) & set(romRange))
		
		if len(overlap1) != 0:
			raise Exception('The ROM memory overlaps with the peripheral memory between addresses ' + hex(min(overlap1)) + ' and ' + hex(max(overlap1)))
		if len(overlap2) != 0:
			raise Exception('The peripheral memory overlaps with the RAM memory between addresses ' + hex(min(overlap2)) + ' and ' + hex(max(overlap2)))
		if len(overlap3) != 0:
			print(min(overlap3), max(overlap3))
			raise Exception('The RAM memory overlaps with the ROM memory between addresses ' + hex(min(overlap3)) + ' and ' + hex(max(overlap3)))
		
		# Calculate vector positions
		if type(vectorsCount) != int:
			raise Exception('vectorsCount must be an int >= 0')
		if vectorsCount < 0:
			raise Exception('vectorsCount must be an int >= 0')
		if vectorsCount > 0 and not self.isPower2(vectorsCount):
			raise Exception('vectorsCount must be a power of 2')
		
		self.VectorsCount = vectorsCount
		self.VectorsSize = vectorsCount * 4
		if self.VectorsSize > self.RamSize:
			raise Exception('The RAM is not large enough to hold all of the interrupt vectors')
		
		self.VectorsStartAddress = self.RamStartAddress
		self.VectorsEndAddress = self.VectorsStartAddress + self.VectorsSize - 1

		self.RamProgramStartAddress = self.VectorsEndAddress + 1
		
		self.ProgramCounterInit = self.RomStartAddress

		if stackPointerInit is None:
			self.StackPointerInit = self.RamEndAddress + 1
		elif (type(stackPointerInit) == int) and (stackPointerInit % 128 == 0) and (stackPointerInit > self.RamProgramStartAddress) and (stackPointerInit <= self.RamEndAddress + 1):
			self.StackPointerInit = stackPointerInit
		else:
			print(stackPointerInit, self.RamProgramStartAddress, self.RamEndAddress)
			raise Exception('Invalid stack pointer initial value: ' + str(stackPointerInit))
		RamMemorySlotsMuxedMin = max(self.RamMemorySlotsUsed) + 1
		if len(self.RamMemorySlotsMuxed) > 0:
			RamMemorySlotsMuxedMin = min(self.RamMemorySlotsMuxed)
		if self.StackPointerInit != (self.RamMemorySlotSize * RamMemorySlotsMuxedMin):
			print('***')
			print('***')
			print('WARNING: StackPointerInit is not set to the end of the non-MUXed RAM')
			print('***')
			print('***')
		
		self.BootloaderUsesSpiFlashCommands = bootloaderUsesSpiFlashCommands

		# Update the pad logic levels
		self.PadOUTPosLogic = padOutPosLogic
		self.PadDIRPosLogic = padDIRPosLogic
		self.PadRENPosLogic = padRENPosLogic
		#self.PadOCENPosLogic = padOCENPosLogic

		# Set the picorv32 defines
		self.ENABLE_COUNTERS = ENABLE_COUNTERS
		self.ENABLE_COUNTERS64 = ENABLE_COUNTERS64
		self.ENABLE_REGS_DUALPORT = ENABLE_REGS_DUALPORT
		self.LATCHED_MEM_RDATA = LATCHED_MEM_RDATA
		self.TWO_STAGE_SHIFT = TWO_STAGE_SHIFT
		self.BARREL_SHIFTER = BARREL_SHIFTER
		self.COMPRESSED_ISA = COMPRESSED_ISA
		self.ENABLE_MUL = ENABLE_MUL
		self.ENABLE_FAST_MUL = ENABLE_FAST_MUL
		self.ENABLE_DIV = ENABLE_DIV
		self.ENABLE_IRQ_FAST_CONTEXT_SWITCHING = ENABLE_IRQ_FAST_CONTEXT_SWITCHING
		self.ENABLE_IRQ_QREGS = ENABLE_IRQ_QREGS
		self.ENABLE_IRQ_TIMER = ENABLE_IRQ_TIMER
		self.MASKED_IRQ = MASKED_IRQ
		self.PROGADDR_IRQ = PROGADDR_IRQ

		if not (self.RamProgramStartAddress <= self.PROGADDR_IRQ < self.RamEndAddress):
			raise Exception('PROGADDR_IRQ must be located in RAM, not in the interrupt vector table')

		if abs(self.PROGADDR_IRQ - self.RamProgramStartAddress) < 16:
			raise Exception('PROGADDR_IRQ needs to be at least 16 bytes away from RamProgramStartAddress')
		
		if (self.PROGADDR_IRQ % 4) != 0:
			raise Exception('PROGADDR_IRQ must be located on a 4-byte boundary')

		if (self.ENABLE_IRQ_FAST_CONTEXT_SWITCHING and self.ENABLE_IRQ_QREGS):
			raise Exception('Cannot have both ENABLE_IRQ_FAST_CONTEXT_SWITCHING and ENABLE_IRQ_QREGS enabled at the same time')
		
		# Set the update variables
		self.NeedToCheckPeripheralTemplates = True
		self.NeedToCheckPeripherals = True
		self.NeedToCheckPins = True
		
		return
	
	def AddPeripheralTemplate(self, peripheralTemplate):
		if type(peripheralTemplate) != PeripheralTemplate:
			raise Exception('Not a PeripheralTemplate type')
		peripheralTemplate.Parent = self
		self.PeripheralTemplates.append(peripheralTemplate)
		self.NeedToCheckPeripheralTemplates = True
		return
	
	def CreatePackage(self, packageType:str, pinCount:int, units:str, dimensions:list, pinsOnEachSide:dict, pinPitch:float, pinWidth:float, pinDepth:float):
		self.Package = PackageData(packageType=packageType, pinCount=pinCount, units=units, dimensions=dimensions, pinsOnEachSide=pinsOnEachSide, pinPitch=pinPitch, pinWidth=pinWidth, pinDepth=pinDepth)
		return self.Package
	
	def CheckPeripheralTemplates(self):
		# Check each peripheral template for identical NameTemplates
		for p1 in self.PeripheralTemplates:
			for p2 in self.PeripheralTemplates:
				if p1 == p2:
					continue
				
				if p1.NameTemplate == p2.NameTemplate:
					raise Exception('There is more than one PeripheralTemplate named "' + p1.NameTemplate + '"')
		
		# Check the register templates in each peripheral template
		for p in self.PeripheralTemplates:
			p.CheckRegisterTemplates()
		
		# Build the symbol table
		peripheralTemplateNameTemplates = []
		registerTemplateNameTemplates = []
		bitFieldNames = []
		valueDescriptionNames = []
		
		for p in self.PeripheralTemplates:
			peripheralTemplateNameTemplates.append(p.NameTemplate)
			for r in p.RegisterTemplates:
				registerTemplateNameTemplates.append(r.NameTemplate)
				for bf in r.BitFields:
					if bf.Unused is True:
						continue
					if bf.SameNameAsRegister is True:
						continue
					bitFieldNames.append(bf.Name)
					for vd in bf.ValueDescriptions:
						if len(vd) == 3:
							if len(vd[2]) > 0:
								valueDescriptionNames.append(vd[2])
		
		self.SymbolTemplates = peripheralTemplateNameTemplates + registerTemplateNameTemplates + bitFieldNames + valueDescriptionNames
		self.checkSymbolTable(self.SymbolTemplates)
		
		self.NeedToCheckPeripheralTemplates = False
		
		return
	
	def FindPeripheralTemplate(self, nameTemplate):
		if type(nameTemplate) != str:
			raise Exception('nameTemplate must be a str')
		for p in self.PeripheralTemplates:
			if p.NameTemplate == nameTemplate:
				return p
		
		raise Exception('Could not find PeripheralTemplate "' + nameTemplate + '"')
		return
	
	def FindPeripheral(self, name):
		if type(name) != str:
			raise Exception('name must be a str')
		for p in self.Peripherals:
			if p.Name == name:
				return p
		
		raise Exception('Could not find Peripheral "' + name + '"')
		return
	
	def CreatePeripheral(self, nameTemplate, nameIndex, peripheralMemorySlot, interruptPriority):
		pt = self.FindPeripheralTemplate(nameTemplate)
		p = Peripheral(peripheralTemplate=pt, peripheralMemorySlot=peripheralMemorySlot, peripheralMemorySlotCount=self.PeripheralMemorySlotCount, registerMemorySlotsPerPeripheralMemorySlot=self.RegisterMemorySlotsPerPeripheralMemorySlot, peripheralMemoryStartAddress=self.PeripheralMemoryStartAddress, interruptPriority=interruptPriority, nameIndex=nameIndex)
		p.Parent = self
		self.Peripherals.append(p)
		return p
	
	def CheckPeripherals(self):
		# Check each peripheral for identical Names
		for p1 in self.Peripherals:
			for p2 in self.Peripherals:
				if p1 == p2:
					continue
				
				if p1.Name == p2.Name:
					raise Exception('There is more than one Peripheral named "' + p1.Name + '"')
		
		# Ensure that all registers are fully defined, that is, that every bit is attached to a bit field
		for p in self.Peripherals:
			for r in p.Registers:
				r.CheckIfAllBitsDefined()
		
		# Check GPIO pins
		for p in self.Peripherals:
			if p.IsGPIO():
				p.CheckGpios()
		
		# Make sure the CS_FLASH, SCK0, MOSI0, MISO0, and BOOT pins are all in the peripheral GPIO0
		GPIO0 = self.FindPeripheral('GPIO0')
		try:
			PinCS_FLASH = GPIO0.FindGpio(primaryName='CS_FLASH')
		except:
			PinCS_FLASH = GPIO0.FindGpio(funcName='CS_FLASH')
		PinSCK0 = GPIO0.FindGpio(funcName='SCK0')
		PinMISO0 = GPIO0.FindGpio(funcName='MISO0')
		PinMOSI0 = GPIO0.FindGpio(funcName='MOSI0')
		PinBOOT = GPIO0.FindGpio(primaryName='BOOT')
		
		# Build the symbol table and scan it for duplicate symbols
		peripheralNames = []
		registerNames = []
		bitFieldNames = []
		valueDescriptionNames = []
		pinNames = []
		
		usedRegisterTemplates = []
		
		for p in self.Peripherals:
			peripheralNames.append(p.Name)
			for r in p.Registers:
				registerNames.append(r.Name)
				if r.Template not in usedRegisterTemplates:
					usedRegisterTemplates.append(r.Template)
					for bf in r.BitFields:
						if bf.Unused is True:
							continue
						if bf.SameNameAsRegister is True:
							continue
						bitFieldNames.append(bf.Name)
						for vd in bf.ValueDescriptions:
							if len(vd) == 3:
								if len(vd[2]) > 0:
									valueDescriptionNames.append(vd[2])
			
			if p.IsGPIO():
				for pin in p.Pins:
					if pin.NoConnect:
						continue
					if len(pin.PrimaryName) > 0:
						pinNames.append(pin.PrimaryBitName)
						pinNames.append(pin.PrimaryPxOUTName)
						pinNames.append(pin.PrimaryPxDIRName)
						pinNames.append(pin.PrimaryPxIESName)
						pinNames.append(pin.PrimaryPxIEName)
						pinNames.append(pin.PrimaryPxSELName)
						pinNames.append(pin.PrimaryPxRENName)
						#pinNames.append(pin.PrimaryPxOCENName)
					if len(pin.FuncName) > 0:
						pinNames.append(pin.FuncBitName)
						pinNames.append(pin.FuncPxSELName)
		
		self.Symbols = peripheralNames + registerNames + bitFieldNames + valueDescriptionNames + pinNames
		self.checkSymbolTable(self.Symbols)
		
		# Build the address table
		addressTable = []
		
		for p in self.Peripherals:
			for r in p.Registers:
				tup = (r.Name, r.Address)
				addressTable.append(tup)
		
		self.AddressTable = addressTable
		
		# Scan the address table for duplicate addresses
		addresses = [tup[1] for tup in addressTable]
		for address in addresses:
			symbolsAtAddress = []
			for at_tup in addressTable:
				if address == at_tup[1]:
					symbolsAtAddress.append(at_tup[0])
			if len(symbolsAtAddress) != 1:
				sharedRegistersStr = ''
				for s in symbolsAtAddress:
					sharedRegistersStr += '"' + s + '", '
				sharedRegistersStr = sharedRegistersStr[:-2]
				raise Exception('The registers ' + sharedRegistersStr + ' all share the same address of ' + hex(address) + ', which is not allowed')
		
		# Scan the peripherals for duplicate interrupt priorities
		usedInterruptPriorities = []
		for p in self.Peripherals:
			if p.InterruptPriority is not None:
				if p.InterruptPriority in usedInterruptPriorities:
					raise Exception('The interrupt priority/vector number ' + str(p.InterruptPriority) + ' has been used more than once, which is not allowed')
				if p.InterruptPriority < 0:
					raise Exception('Interrupt priority/vector number must be non-negative, but peripheral ' + p.Name + ' has interrupt priority ' + str(p.InterruptPriority))
				usedInterruptPriorities.append(p.InterruptPriority)
		
		# Sort the peripherals by base address in ascending order
		self.Peripherals = sorted(self.Peripherals, key=lambda p: p.BaseAddress)
		
		self.NeedToCheckPeripherals = False
		
		return
	
	def CheckPackagePins(self):
		# Sort the pins by the pin number
		self.Package.Pins.sort(key=lambda x: x.PackagePinNumber)

		# Check for out-of-bounds or repeated pin numbers
		pinNumbers = []
		for pin in self.Package.Pins:
			if not (1 <= pin.PackagePinNumber <= self.Package.PinCount):
				raise Exception('Pin "' + pin.Name + '" has pin number ' + str(pin.PackagePinNumber) + ', which is outside the bounds of 1 to ' + self.Package.PinCount)
			if pin.PackagePinNumber in pinNumbers:
				raise Exception('Pin "' + pin.Name + '" has pin number ' + str(pin.PackagePinNumber) + ', which has already been used')
			pinNumbers.append(pin.PackagePinNumber)
		
		# Check for missing pins
		missingPins = []
		for i in range(1, self.Package.PinCount + 1):
			if i not in pinNumbers:
				missingPins.append(i)
		if len(missingPins) > 0:
			raise Exception('The following pins have not been defined: ' + str(missingPins))
		
		# Make lists for the pins
		names = []
		for pin in self.Package.Pins:
			if pin.NoConnect:
				continue

			names.append(pin.Name)
			if pin.PrimaryName is not None:
				names.append(pin.PrimaryName)
			if pin.FuncName is not None:
				names.append(pin.FuncName)
		
		# Check to make sure no name is used twice
		self.checkSymbolTable(names)

		# Make sure every pin has a power domain
		for pin in self.Package.Pins:
			if pin.NoConnect:
				continue
			if type(pin.PowerDomain) != PowerDomain:
				raise Exception('Pin ' + pin.Name + ' does not have an assigned power domain')

		# Assign a side to each pin
		i = 0
		for j in range(self.Package.PinsOnEachSide['W']):
			self.Package.Pins[i].Side = 'W'
			i += 1
		for j in range(self.Package.PinsOnEachSide['S']):
			self.Package.Pins[i].Side = 'S'
			i += 1
		for j in range(self.Package.PinsOnEachSide['E']):
			self.Package.Pins[i].Side = 'E'
			i += 1
		for j in range(self.Package.PinsOnEachSide['N']):
			self.Package.Pins[i].Side = 'N'
			i += 1

		self.NeedToCheckPins = False

		return

	
	def Generate(self, test=True, force=False, saveHardware=True, saveSoftware=True):
		# Make the paths for each file
		cHeaderPath = self.ChipRootDirectory + '/gcc/lib/include/MemoryMap.h'
		memoryXPath =  self.ChipRootDirectory + '/gcc/lib/linker/memory.x'
		periphXPath =  self.ChipRootDirectory + '/gcc/lib/linker/periph.x'
		periphSPath =  self.ChipRootDirectory + '/gcc/lib/include/periph.S'
		memoryMapVHDPath =  self.ChipRootDirectory + '/hdl/MCU/MemoryMap.vhd'
		latexUserGuidePath =  self.ChipRootDirectory + '/latex/MCU-User-Guide'
		signalRoutingVHDPath =  self.ChipRootDirectory + '/hdl/MCU/MCU.vhd'
		ramRomSizeDir =  self.ChipRootDirectory + '/gcc/lib/linker'
		chipConfigJsonPath =  self.ChipRootDirectory + '/config/MemoryMap.json'
		
		if test is True:
			force = True
			
			cHeaderPath = 'out/MemoryMap.h'
			memoryXPath = 'out/memory.x'
			periphXPath = 'out/periph.x'
			periphSPath = 'out/periph.S'
			memoryMapVHDPath = 'out/MemoryMap.vhd'
			latexUserGuidePath = 'out/MCU-User-Guide'
			signalRoutingVHDPath = 'out/routing_template.vhd'
			ramRomSizeDir = 'out'
			chipConfigJsonPath = 'out/MemoryMap.json'

		
		# Generate each file
		if force is True:
			self.generateLatexUserGuide(latexUserGuidePath)
		
			if saveSoftware is True:
				self.generateCHeader(cHeaderPath)
				self.generateMemoryX(memoryXPath)
				self.generatePeriphX(periphXPath)
				self.generatePeriphS(periphSPath)
			
			if saveHardware is True:
				self.generateMemoryMapVHD(memoryMapVHDPath)
				self.generateSignalRoutingVHD(signalRoutingVHDPath, editFile=(not test))
				self.generateRamRomSizeFiles(ramRomSizeDir)
			
			self.generateMemoryMapJson(chipConfigJsonPath)
		else:
			
			if os.path.exists(latexUserGuidePath):
				s = input('The file ' + latexUserGuidePath + ' already exists. Overwrite? (y/n) ')
				if s.lower() == 'y':
					self.generateLatexUserGuide(latexUserGuidePath)
			
			if saveSoftware is True:
				if os.path.exists(cHeaderPath):
					s = input('The file ' + cHeaderPath + ' already exists. Overwrite? (y/n) ')
					if s.lower() == 'y':
						self.generateCHeader(cHeaderPath)
				if os.path.exists(memoryXPath):
					s = input('The file ' + memoryXPath + ' already exists. Overwrite? (y/n) ')
					if s.lower() == 'y':
						self.generateMemoryX(memoryXPath)
				if os.path.exists(periphXPath):
					s = input('The file ' + periphXPath + ' already exists. Overwrite? (y/n) ')
					if s.lower() == 'y':
						self.generatePeriphX(periphXPath)
				if os.path.exists(periphSPath):
					s = input('The file ' + periphSPath + ' already exists. Overwrite? (y/n) ')
					if s.lower() == 'y':
						self.generatePeriphS(periphSPath)
			
			if saveHardware is True:
				if os.path.exists(memoryMapVHDPath):
					s = input('The file ' + memoryMapVHDPath + ' already exists. Overwrite? (y/n) ')
					if s.lower() == 'y':
						self.generateMemoryMapVHD(memoryMapVHDPath)
				if os.path.exists(signalRoutingVHDPath):
					s = input('The file ' + signalRoutingVHDPath + ' already exists. Overwrite? (y/n) ')
					if s.lower() == 'y':
						self.generateSignalRoutingVHD(signalRoutingVHDPath, editFile=(not test))
				
			if os.path.exists(chipConfigJsonPath):
				s = input('The file ' + chipConfigJsonPath + ' already exists. Overwrite? (y/n) ')
				if s.lower() == 'y':
					self.generateMemoryMapJson(chipConfigJsonPath)

		return
	
	
	
	
	
	
	
	
	
	def generateCHeader(self, outPath):
		self.isTimeToGenerate()
		
		s = ''
		
		# Create the preamble
		s += '/**\n'
		s += ' **\tMemoryMap.h\n'
		s += ' **\tMemory map definition header file\n'
		s += ' **\tDefines the microcontroller peripheral and register addresses, as well as the bit field bit masks\n'
		s += ' **\tGenerated on ' + datetime.datetime.now().strftime('%Y/%m/%d at %H:%M:%S') + ' with the MemoryMap.py memory map generator\n'
		s += ' **\tWARNING: Do not edit or modify this file!\n'
		s += ' **\t\tIf you need to change it, use the MemoryMap.py memory map generator tool\n'
		s += ' **/\n'
		
		s += '\n'
		
		s += '#pragma once\t// Ensures this file will be included only once per source file\n'
		
		s += '\n'
		
		s += '#ifdef __cplusplus\n'
		s += 'extern "C" {\n'
		s += '#endif\t// extern "C"\n'
		
		s += '\n\n\n'
		
		s += '/** Includes **/\n'
		s += '#include <stdint.h>\n'
		s += '#include <bits.h>\n'
		s += '#include <custom_ops.S>\n'
		
		s += '\n\n\n'

		s += '/** Defines **/\n'
		s += '#define ASIC_NAME\t\"' + self.AsicName + '\"\n'
		s += '#define ASIC_DEFINE_' + self.AsicName + '\n'

		s += '\n\n\n'

		s += '/** Memory Mapped Register Macros **/\n'
		s +=	   '#define MMR_8_BIT_MACRO(_address)	(*((volatile uint8_t *) (_address)))\n'
		s +=	   '#define MMR_08_BIT_MACRO(_address)	MMR_8_BIT_MACRO(_address)\n'
		s +=	   '#define MMR_16_BIT_MACRO(_address)	(*((volatile uint16_t *) (_address)))\n'
		s +=	   '#define MMR_32_BIT_MACRO(_address)	(*((volatile uint32_t *) (_address)))\n'
		s +=	   '#define MMR_8_PTR(_peripheralBaseAddress, _registerOffset)	MMR_8_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))\n'
		s +=	   '#define MMR_08_PTR(_peripheralBaseAddress, _registerOffset)	MMR_8_PTR(_peripheralBaseAddress, _registerOffset)\n'
		s +=	   '#define MMR_16_PTR(_peripheralBaseAddress, _registerOffset)	MMR_16_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))\n'
		s +=	   '#define MMR_32_PTR(_peripheralBaseAddress, _registerOffset)	MMR_32_BIT_MACRO(((uint32_t)_peripheralBaseAddress) + ((uint32_t)_registerOffset))\n'

		s += '\n\n\n'

		s += '/** Macros **/\n'
		s += '\n'
		s += '// General Macros\n'
		s += r'#define STR_EXPAND_MACRO(_tok)	#_tok' + '\n'
		s += r'#define MACRO_TO_STRING(_tok)	STR_EXPAND_MACRO(_tok)' + '\n'
		s += '\n'
		s += '// Interrupt Macros\n'
		s += r'#ifdef __cplusplus' + '\n'
		s += r'#define RVISR(_vect_number, _func_name)	extern "C" { __attribute__((used)) void _func_name(); __attribute__((used)) __attribute__((section(".__interrupt_vector_" MACRO_TO_STRING(_vect_number)))) void (*__IVT_vector_##_vect_number##_##_func_name##__)(void) = _func_name; }' + '\n'
		s += r'#else	// #ifdef __cplusplus' + '\n'
		s += r'#define RVISR(_vect_number, _func_name)	__attribute__((used)) void _func_name(); __attribute__((used)) __attribute__((section(".__interrupt_vector_" MACRO_TO_STRING(_vect_number)))) void (*__IVT_vector_##_vect_number##_##_func_name##__)(void) = _func_name;' + '\n'
		s += r'#endif	// #ifdef __cplusplus' + '\n'
		
		if self.AsicName in ['pingora', 'teewinot', 'pingora2', 'washakie']:
			# Using the picorv32 core
			s += r'#define halt_cpu_until_interrupt() asm volatile(MACRO_TO_STRING(picorv32_waitirq_insn()) "\n")' + '\n'
			if self.AsicName != 'teewinot' and self.AsicName != 'pingora':
				s += r'#define cpu_sleep()	asm volatile(MACRO_TO_STRING(picorv32_sleep_insn()) "\n")' + '\n'
				s += r'#define cpu_wake()	asm volatile(MACRO_TO_STRING(picorv32_wake_insn()) "\n")' + '\n'
		else:
			# Using the smrv32 core
			s += r'#define cpu_sleep()	asm volatile(MACRO_TO_STRING(smrv32_sleep_insn()) "\n")' + '\n'
			s += r'#define cpu_wake()	asm volatile(MACRO_TO_STRING(smrv32_wake_insn()) "\n")' + '\n'
			s += r'#define irq_return()	asm volatile(MACRO_TO_STRING(smrv32_retirq_insn()) "\n")' + '\n'
		

		s += '\n\n\n'
		

		# Add the RAM and ROM locations and sizes
		t = TabbedTable()

		t.AddLine('/** RAM, ROM, and Interrupt Vector Table Locations and Sizes **/')
		
		t.AddRow(['#define ROM_START', '(' + self.fmthex(self.RomStartAddress) + ')'])
		t.AddRow(['#define ROM_SIZE',  '(' + self.fmthex(self.RomSize) + ')'])
		t.AddRow(['#define RAM_START', '(' + self.fmthex(self.RamStartAddress) + ')'])
		t.AddRow(['#define RAM_SIZE',  '(' + self.fmthex(self.RamSize) + ')'])
		t.AddRow(['#define INTERRUPT_VECTOR_TABLE_START', '(' + self.fmthex(self.VectorsStartAddress) + ')'])
		t.AddRow(['#define INTERRUPT_VECTOR_TABLE_SIZE',  '(' + self.fmthex(self.VectorsSize) + ')'])
		t.AddRow(['#define RAM_PROGRAM_START_ADDRESS',  '(' + self.fmthex(self.RamProgramStartAddress) + ')'])
		t.AddRow(['#define INTERRUPT_HANDLER_ADDRESS',  '(' + self.fmthex(self.PROGADDR_IRQ) + ')'])
		t.AddRow(['#define PERIPHERAL_SPACING',  '(' + self.fmthex(self.RegisterMemorySlotsPerPeripheralMemorySlot * 4) + ')', '// The number of bytes between each adjacent peripheral base address'])
		t.AddRow(['#define STACK_POINTER_INIT', '(' + self.fmthex(self.StackPointerInit) + ')'])
		if self.BootloaderUsesSpiFlashCommands:
			t.AddRow(['#define BOOTLOADER_USES_SPI_FLASH_COMMANDS'])
		
		t.AddBlankLine()
		
		t.AddRow(['#define RAM_SLOT_SIZE', '(' + str(self.RamMemorySlotSize) + ')'])
		t.AddRow(['#define LAST_RAM_SLOT_SIZE', '(' + str(self.LastRamMemorySlotSize) + ')'])
		# (Slot name (None if unused section), SRAM slot number (None if not SRAM), start address, end address)
		slots = []
		for ramSlot in self.RamMemorySlotsUsed:
			addr = self.RamStartAddress + ((ramSlot - 2) * self.RamMemorySlotSize)
			slots += [('SRAM{:02d}'.format(ramSlot), ramSlot, addr, addr + self.RamMemorySlotSize - 1)]
		for slot in slots:
			t.AddRow(['#define ' + slot[0] + '_ADDRESS', '(' + self.fmthex(slot[2], minDigits=5) + ')'])
		
		t.AddBlankLine()
		t.AddRow(['#define SPI_FLASH_PROGRAM_ADDRESS', '(' + self.fmthex(self.SpiFlashProgramAddress) + ')'])
		t.AddBlankLine()
		s += t.ToString()
		
		if self.NativeSpiFlashMemoryReadAccess:
			s += '#define HAS_NATIVE_SPI_FLASH_MEMORY_READ_ACCESS\n'
		else:
			s += '// Does not have native SPI Flash memory read access\n'
		
		if self.NativeSpiFlashMemoryWriteAccess:
			s += '#define HAS_NATIVE_SPI_FLASH_MEMORY_WRITE_ACCESS\n'
		else:
			s += '// Does not have native SPI Flash memory write access\n'
		
		t = TabbedTable()
		if self.NativeSpiFlashMemoryReadAccess or self.NativeSpiFlashMemoryReadAccess:
			t.AddRow(['#define SPI_FLASH_MEM_ADDRESS', '(0x01000000)'])
			t.AddRow(['#define SPI_FLASH_MEM', '((volatile uint32_t *) (SPI_FLASH_MEM_ADDRESS))'])

		t.AddBlankLines(3)

		s += t.ToString()

		# Chip Properties
		t = TabbedTable()
		t.AddLine('/** Chip Properties **/')
		if self.ENABLE_IRQ_QREGS:
			t.AddRow(['#define ENABLE_IRQ_QREGS'])
		if self.ENABLE_IRQ_FAST_CONTEXT_SWITCHING:
			t.AddRow(['#define ENABLE_IRQ_FAST_CONTEXT_SWITCHING'])
		if self.ENABLE_COUNTERS:
			t.AddRow(['#define ENABLE_COUNTERS'])
		if self.ENABLE_COUNTERS64:
			t.AddRow(['#define ENABLE_COUNTERS64'])
		
		t.AddBlankLines(3)
		
		s += t.ToString()
		
		# Get all used peripheral templates
		usedPTs = []
		for p in self.Peripherals:
			if p.Template not in usedPTs:
				usedPTs.append(p.Template)
		
		# Add the register offsets and the bit fields to the header file
		t = TabbedTable()
		t.AddLine('/********** Register Offsets and Bit Fields **********/')
		t.AddBlankLine()
		s += t.ToString()
		
		for pt in usedPTs:
			t = TabbedTable()
			t.AddLine('/** ' + pt.NameTemplate + ' **/')
			s += t.ToString()
			for rt in pt.RegisterTemplates:
				# Add the register
				t = TabbedTable()
				t.AddLine('// ' + rt.NameTemplate)
				t.AddRow(['#define ' + rt.NameTemplate + '_OFFSET', '(' + str(rt.Offset) + ')'])
				t.AddRow(['#define ' + rt.NameTemplate + '_PTR(_' + rt.Parent.NameTemplate + '_BASE)', 'MMR_{:02}_PTR(_'.format(rt.Size) + rt.Parent.NameTemplate + '_BASE, ' + rt.NameTemplate + '_OFFSET)'])
				t.AddBlankLine()
				s += t.ToString()
				
				t = TabbedTable()
				hexDigits = None
				if rt.Size == 8:
					hexDigits = 2
				elif rt.Size == 16:
					hexDigits = 4
				else:
					hexDigits = 8
				
				# Add the bit fields
				bfDefines = 0
				for bf in rt.BitFields:
					if bf.Unused is True:
						continue
					if bf.Size == 1:
						if bf.SameNameAsRegister:
							continue
						t.AddRow(['#define ' + bf.Name, '(' + self.fmthex(bf.BitMask, minDigits=hexDigits) + ')', '// bit ' + str(bf.MSB)])
						t.AddRow(['#define ' + bf.Name + '_LSB', '(' + self.fmtint(bf.LSB, minDigits=1) + ')'])
						bfDefines += 1
					else:
						if not bf.SameNameAsRegister:
							t.AddRow(['#define ' + bf.Name + '_MASK', '(' + self.fmthex(bf.BitMask, minDigits=hexDigits) + ')', '// bits ' + str(bf.MSB) + ' downto ' + str(bf.LSB)])
							t.AddRow(['#define ' + bf.Name + '_LSB', '(' + self.fmtint(bf.LSB, minDigits=1) + ')'])
							bfDefines += 1
						for vd in bf.ValueDescriptions:
							if len(vd) == 3:
								if len(vd[2]) > 0:
									# This value description has a name, so add it
									t.AddRow(['#define ' + vd[2], '(' + self.fmthex(vd[0] << bf.LSB, minDigits=hexDigits) + ')'])
				
				if bfDefines > 0:
					t.AddBlankLine()
				s += t.ToString()
			t = TabbedTable()
			t.AddBlankLines(2)
			s += t.ToString()
		


		# Add the register address definitions
		t = TabbedTable()
		t.AddLine('/********** Peripheral and Register Memory Map **********/')
		t.AddBlankLine()
		
		for p in self.Peripherals:
			t.AddLine('/** ' + p.Name + ' **/')
			t.AddRow(['#define ' + p.Name + '_BASE', '(' + self.fmthex(p.BaseAddress) + ')'])
			t.AddBlankLine()
			
			for r in p.Registers:
				t.AddRow(['#define ' + r.Name + '_ADDRESS', '(' + self.fmthex(r.Address) + ')'])
				macroStr = None
				if r.Size == 8:
					macroStr = 'MMR_08_BIT_MACRO'
				elif r.Size == 16:
					macroStr = 'MMR_16_BIT_MACRO'
				else:
					macroStr = 'MMR_32_BIT_MACRO'
				t.AddRow(['#define ' + r.Name, macroStr + '(' + r.Name + '_ADDRESS)'])
			t.AddBlankLines(3)
		
		s += t.ToString()



		# Add peripheral and register structures
		s += '/********** Peripheral, Register, and Bit Field Structures **********/\n\n'

		for pt in usedPTs:
			s += '/** Peripheral ' + pt.NameTemplate + ' **/\n'

			if pt.NameTemplate == 'GPIOx':
				s += '// Bit fields structure for GPIO registers\n'
				for bitCount in [8, 16, 32]:
					typeStr = 'volatile uint' + str(bitCount) + '_t'
					s += 'typedef union\n{\n'
					s += '\t' + typeStr + ' value;\n'
					s += '\tstruct\n\t{\n'
					t = TabbedTable()
					for i in range(bitCount):	# Put the LSB first
						t.AddRow([typeStr + ' P' + str(i), ': 1;'], prefixTabs=2)
					s += t.ToString()
					s += '\t};\n'
					s += '} GPIO_' + str(bitCount) + 'bit_Register_t;\n'
					s += '\n'
				
				# Add the peripheral's register structure
				for bitCount in [8, 16, 32]:
					s += '// Registers structure for ' + str(bitCount) + '-bit GPIO peripheral\n'
					s += 'typedef struct\n{\n'
					unusedIndex = 0
					registers = sorted(pt.RegisterTemplates, key=lambda x: x.Offset)
					t = TabbedTable()
					
					if registers[0].Offset != 0:
						numUnused = registers[0].Offset
						if numUnused == 4:
							t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
						else:
							t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + '[' + str(numUnused // 4) + '];'], prefixTabs=1)
						unusedIndex += 1

					for i in range(len(registers)):
						rt = registers[i]
						typeStr = 'volatile GPIO_' + str(bitCount) + 'bit_Register_t'
						name = rt.NameTemplate + '_'
						if type(pt.RegisterPrefix) == str:
							name = rt.NameTemplate[len(pt.RegisterPrefix):]
						t.AddRow([typeStr, name + ';'], prefixTabs=1)
						
						if bitCount == 8:
							t.AddRow(['volatile uint8_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
							unusedIndex += 1
							t.AddRow(['volatile uint16_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
							unusedIndex += 1
						elif bitCount == 16:
							t.AddRow(['volatile uint16_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
							unusedIndex += 1
						
						numUnused = 0
						if i == (len(registers) - 1):
							# This is the last register
							numUnused = (self.RegisterMemorySlotsPerPeripheralMemorySlot * 4) - (rt.Offset + 4)
						else:
							nextRt = registers[i + 1]
							numUnused = nextRt.Offset - (rt.Offset + 4)
						
						if numUnused == 4:
							t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
						elif numUnused > 4:
							t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + '[' + str(numUnused // 4) + '];'], prefixTabs=1)
					
					s += t.ToString()
					s += '}' + pt.NameTemplate + '_' + str(bitCount) + 'bit_t;\n'
					s += '\n'
				continue

			# Add each register's bit field structure
			for rt in pt.RegisterTemplates:
				# Skip any GPIO peripherals
				if pt.NameTemplate == 'GPIOx':
					break

				# Add the register string
				s += '// Bit fields structure for register ' + rt.NameTemplate + '\n'
				
				hexDigits = rt.Size // 4

				# Add the register's bit field structure
				bfs = sorted(rt.BitFields, key=lambda x: x.MSB)	# Sort with LSB first
				usedBfs = [bf for bf in bfs if not bf.Unused]

				if len(usedBfs) > 0:
					unusedIndex = 0
					typeStr = 'volatile uint' + str(rt.Size) + '_t'
					s += 'typedef union\n{\n'
					s += '\t' + typeStr + ' value;\n'
					s += '\tstruct\n\t{\n'
					t = TabbedTable()
					for bf in bfs:
						bitsStr = '// bit ' + str(bf.MSB)
						if bf.Size > 1:
							bitsStr = '// bits ' + str(bf.MSB) + ' downto ' + str(bf.LSB)
						name = None
						if bf.Unused:
							name = '__unused' + str(unusedIndex)
							unusedIndex += 1
						elif bf.SameNameAsRegister:
							if type(pt.RegisterPrefix) == str:
								name = bf.Name[len(pt.RegisterPrefix):]
							else:
								name = bf.Name + '_'
						elif type(pt.BitFieldPrefix) == str and bf.Name.startswith(pt.BitFieldPrefix):
							name = bf.Name[len(pt.BitFieldPrefix):]
						else:
							name = bf.Name + '_'

						t.AddRow([typeStr + ' ' + name, ': ' + str(bf.Size) + ';', bitsStr], prefixTabs=2)
					s += t.ToString()
					s += '\t};\n'
					s += '} ' + rt.NameTemplate + '_Register_t;\n'
					s += '\n'

			s += '\n\n'

			# Add the peripheral's register structure
			s += '// Registers structure for peripheral ' + pt.NameTemplate + '\n'
			s += 'typedef struct\n{\n'
			unusedIndex = 0
			registers = sorted(pt.RegisterTemplates, key=lambda x: x.Offset)
			t = TabbedTable()
			
			if registers[0].Offset != 0:
				numUnused = registers[0].Offset
				if numUnused == 4:
					t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
				else:
					t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + '[' + str(numUnused // 4) + '];'], prefixTabs=1)
				unusedIndex += 1

			for i in range(len(registers)):
				rt = registers[i]
				typeStr = 'volatile ' + rt.NameTemplate + '_Register_t'
				name = rt.NameTemplate + '_'
				if type(pt.RegisterPrefix) == str:
					name = rt.NameTemplate[len(pt.RegisterPrefix):]
				t.AddRow([typeStr, name + ';'], prefixTabs=1)
				
				if rt.Size == 8:
					t.AddRow(['volatile uint8_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
					unusedIndex += 1
					t.AddRow(['volatile uint16_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
					unusedIndex += 1
				elif rt.Size == 16:
					t.AddRow(['volatile uint16_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
					unusedIndex += 1
				
				numUnused = 0
				if i == (len(registers) - 1):
					# This is the last register
					numUnused = (self.RegisterMemorySlotsPerPeripheralMemorySlot * 4) - (rt.Offset + 4)
				else:
					nextRt = registers[i + 1]
					numUnused = nextRt.Offset - (rt.Offset + 4)
				
				if numUnused == 4:
					t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + ';'], prefixTabs=1)
				elif numUnused > 4:
					t.AddRow(['volatile uint32_t', '__unused' + str(unusedIndex) + '[' + str(numUnused // 4) + '];'], prefixTabs=1)
			
			s += t.ToString()
			s += '} ' + pt.NameTemplate + '_t;\n'
			if 'x' in pt.NameTemplate:
				s += '#define ' + pt.NameTemplate + '_PTR(_' + pt.NameTemplate + '_BASE)\t((' + pt.NameTemplate + '_t *) _' + pt.NameTemplate + '_BASE)\n'
			s += '\n'
		
		s += '\n'



		# Add the structure macros for each peripheral
		s += '/********** Peripheral Structure Pointer Macros **********/\n\n'
		t = TabbedTable()
		
		for p in self.Peripherals:
			if p.IsGPIO():
				bitCount = p.Registers[0].Size
				t.AddRow(['#define ' + p.Name, '((' + p.Template.NameTemplate + '_' + str(bitCount) + 'bit_t *) ' + p.Name + '_BASE)'])
			else:
				t.AddRow(['#define ' + p.Name, '((' + p.Template.NameTemplate + '_t *) ' + p.Name + '_BASE)'])
		
		s += t.ToString()
		s += '\n\n\n'

		
		# Add the bit names and numbers for the GPIO ports
		t = TabbedTable()
		t.AddLine('/********** GPIO Pins **********/')
		t.AddBlankLine()
		for p in self.Peripherals:
			if p.IsGPIO():
				if len(p.Pins) < 1:
					continue
				t.AddLine('/** GPIO' + p.GetGPIOPortLabel() + ' Pins **/')
				for pin in p.Pins:
					if pin.NoConnect:
						continue
					if len(pin.PrimaryName) > 0:
						t.AddLine('// P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber) + ' primary function (when P' + p.GetGPIOPortLabel() + 'SEL(' + str(pin.BitNumber) + ') = \'0\'): ' + pin.PrimaryName)
						t.AddRow(['#define ' + pin.PrimaryBitName, '(BIT' + str(pin.BitNumber) + ')'])
						t.AddRow(['#define ' + pin.PrimaryPxINName, '(P' + p.GetGPIOPortLabel() + 'IN)'])
						t.AddRow(['#define ' + pin.PrimaryPxOUTName, '(P' + p.GetGPIOPortLabel() + 'OUT)'])
						t.AddRow(['#define ' + pin.PrimaryPxDIRName, '(P' + p.GetGPIOPortLabel() + 'DIR)'])
						t.AddRow(['#define ' + pin.PrimaryPxIESName, '(P' + p.GetGPIOPortLabel() + 'IES)'])
						t.AddRow(['#define ' + pin.PrimaryPxIFGName, '(P' + p.GetGPIOPortLabel() + 'IFG)'])
						t.AddRow(['#define ' + pin.PrimaryPxIEName, '(P' + p.GetGPIOPortLabel() + 'IE)'])
						t.AddRow(['#define ' + pin.PrimaryPxSELName, '(P' + p.GetGPIOPortLabel() + 'SEL)'])
						t.AddRow(['#define ' + pin.PrimaryPxRENName, '(P' + p.GetGPIOPortLabel() + 'REN)'])
						#t.AddRow(['#define ' + pin.PrimaryPxOCENName, '(P' + p.GetGPIOPortLabel() + 'OCEN)'])
						t.AddBlankLine()
					
					if len(pin.FuncName) > 0:
						t.AddLine('// P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber) + ' secondary function (when P' + p.GetGPIOPortLabel() + 'SEL(' + str(pin.BitNumber) + ') = \'1\'): ' + pin.FuncName)
						t.AddRow(['#define ' + pin.FuncBitName, '(BIT' + str(pin.BitNumber) + ')'])
						t.AddRow(['#define ' + pin.FuncPxINName, '(P' + p.GetGPIOPortLabel() + 'IN)'])
						t.AddRow(['#define ' + pin.FuncPxSELName, '(P' + p.GetGPIOPortLabel() + 'SEL)'])
						t.AddRow(['#define ' + pin.FuncPxDIRName, '(P' + p.GetGPIOPortLabel() + 'DIR)'])
						t.AddRow(['#define ' + pin.FuncPxOUTName, '(P' + p.GetGPIOPortLabel() + 'OUT)'])
						t.AddRow(['#define ' + pin.FuncPxRENName, '(P' + p.GetGPIOPortLabel() + 'REN)'])
						t.AddRow(['#define ' + pin.FuncPxIEName, '(P' + p.GetGPIOPortLabel() + 'IE)'])
						t.AddRow(['#define ' + pin.FuncPxIESName, '(P' + p.GetGPIOPortLabel() + 'IES)'])
						t.AddRow(['#define ' + pin.FuncPxIFGName, '(P' + p.GetGPIOPortLabel() + 'IFG)'])
						t.AddBlankLine()
				t.AddBlankLines(2)
		
		s += t.ToString()
		
		# Add the interrupt vectors
		t = TabbedTable()
		t.AddLine('/********** Interrupt Vectors **********/')
		t.AddBlankLine()

		populatedInterruptVectors = [1, 2]
		if self.ENABLE_COUNTERS or self.ENABLE_COUNTERS64:
			t.AddRow(['#define IRQ_CPU_TIMER_VECTOR', '0', '// ' + self.fmthex(self.VectorsStartAddress + 0 * 4) + ' (called when CPU down-counting timer transitions from 1 to 0)'])
			populatedInterruptVectors = [0] + populatedInterruptVectors
		else:
			for p in self.Peripherals:
				if p.InterruptPriority == 0:
					t.AddRow(['#define IRQ_' + p.Name + '_VECTOR', '0', '// ' + self.fmthex(self.VectorsStartAddress + 0 * 4)])
					populatedInterruptVectors = [0] + populatedInterruptVectors
					break
		t.AddRow(['#define IRQ_EBREAK_VECTOR', '1', '// ' + self.fmthex(self.VectorsStartAddress + 1 * 4) + ' (called when EBREAK, ECALL, or illegal instruction occurrs)'])
		t.AddRow(['#define IRQ_BUS_ERROR_VECTOR', '2', '// ' + self.fmthex(self.VectorsStartAddress + 2 * 4) + ' (called when an unaligned memory access occurs)'])

		for i in range(3, 32):
			# Search for a peripheral with this interrupt priority (there are either 1 or 0 of them for each interrupt priority number)
			for p in self.Peripherals:
				if p.InterruptPriority == i:
					t.AddRow(['#define IRQ_' + p.Name + '_VECTOR', str(i), '// ' + self.fmthex(self.VectorsStartAddress + i * 4)])
					populatedInterruptVectors.append(i)
					break

		t.AddBlankLine()
		t.AddBlankLine()
		t.AddBlankLine()

		for i in range(0, 32):
			t.AddRow(['#define IRQ_' + str(i) + '_VECTOR', str(i), '// ' + self.fmthex(self.VectorsStartAddress + i * 4)])
		
		t.AddBlankLine()

		t.AddRow(['#define LAST_POPULATED_IRQ_VECTOR', str(max(populatedInterruptVectors))])
		
		s += t.ToString()

		if len(set(populatedInterruptVectors)) != len(populatedInterruptVectors):
			print(populatedInterruptVectors)
			raise Exception('Repeated interrupt vector!')
		
		# Add the postamble
		s += '\n\n\n'
		 
		s += '#ifdef __cplusplus\n'
		s += '}\n'
		s += '#endif\t// extern "C"\n'
		
		# Save the file
		f = open(outPath, 'w', newline='\n')
		f.write(s)
		f.close()
		
		print('C Header file saved to ' + outPath)
		
		return
	
	def generateMemoryX(self, outPath):
		self.isTimeToGenerate()
		
		s = ''
		t = TabbedTable()
		
		# Create the preamble
		s += '/**\n'
		s += ' **\tmemory.x\n'
		s += ' **\tMemory map linker file\n'
		s += ' **\tDefines the microcontroller linker memory, including the RAM, ROM, peripheral, and vector spaces\n'
		s += ' **\tGenerated on ' + datetime.datetime.now().strftime('%Y/%m/%d at %H:%M:%S') + ' with the MemoryMap.py memory map generator\n'
		s += ' **\tWARNING: Do not edit or modify this file!\n'
		s += ' **\t\tIf you need to change it, use the MemoryMap.py memory map generator tool\n'
		s += ' **/\n'
		
		s += '\n'
		
		s += 'MEMORY\n'
		s += '{\n'
		
		# Add the ROM
		t.AddRow(['ROM (rx)', ': ORIGIN = ' + self.fmthex(self.RomStartAddress, 5) + ', LENGTH = ' + self.fmthex(self.RomSize, 5), '/* END = ' + self.fmthex(self.RomEndAddress, 5) + ', SIZE = ' + str(self.RomSize // 1024) + ' KiB */'], prefixTabs=1)
		
		# Add the peripheral memory
		t.AddRow(['PERIPHERAL (rw)', ': ORIGIN = ' + self.fmthex(self.PeripheralMemoryStartAddress, 5) + ', LENGTH = ' + self.fmthex(self.PeripheralMemorySize, 5), '/* END = ' + self.fmthex(self.PeripheralMemoryEndAddress, 5) + ', SIZE = ' + str(self.PeripheralMemorySize // 1024) + ' KiB */'], prefixTabs=1)
		
		t.AddBlankLine()

		# Add the vectors
		t.AddRow(['vectors', ': ORIGIN = ' + self.fmthex(self.VectorsStartAddress, 5) + ', LENGTH = ' + self.fmthex(self.VectorsSize, 5), '/* END = ' + self.fmthex(self.VectorsEndAddress, 5) + ', SIZE = ' + str(self.VectorsSize) + ' bytes */'], prefixTabs=1)
		
		t.AddBlankLine()
		
		for i in range(0, 32):
			t.AddRow(['VECT' + str(i), ': ORIGIN = ' + self.fmthex(self.VectorsStartAddress + i * 4, 5) + ', LENGTH = ' + self.fmthex(4, 5)], prefixTabs=1)

		t.AddBlankLine()

		# Add the RAM memory
		t.AddRow(['RAM (rwx)', ': ORIGIN = ' + self.fmthex(self.RamProgramStartAddress, 5) + ', LENGTH = ' + self.fmthex(self.RamSize - self.VectorsSize, 5), '/* END = ' + self.fmthex(self.RamEndAddress, 5) + ', SIZE = ' + str(self.RamSize - self.VectorsSize) + ' bytes */'], prefixTabs=1)
		ramNotMuxedLength = self.RamSize - self.VectorsSize
		if len(self.RamMemorySlotsMuxed) > 0:
			ramNotMuxedLength = self.RamMemorySlotSize * min(self.RamMemorySlotsMuxed) - self.RamProgramStartAddress
		t.AddRow(['RAM_NOT_MUXED (rwx)', ': ORIGIN = ' + self.fmthex(self.RamProgramStartAddress, 5) + ', LENGTH = ' + self.fmthex(ramNotMuxedLength, 5), '/* END = ' + self.fmthex(self.RamProgramStartAddress + ramNotMuxedLength - 1, 5) + ', SIZE = ' + str(ramNotMuxedLength) + ' bytes */'], prefixTabs=1)
		
		t.AddBlankLine()

		# Add each SRAM cell
		firstSlot = min(self.RamMemorySlotsAvailable)
		for i, slot in enumerate(self.RamMemorySlotsUsed):
			# Get start and end addresses
			slotStartAddress = self.RamStartAddress + ((slot - firstSlot) * self.RamMemorySlotSize)
			if i == (len(self.RamMemorySlotsUsed) - 1):
				thisSlotSize = self.LastRamMemorySlotSize
			else:
				thisSlotSize = self.RamMemorySlotSize
			slotEndAddress = slotStartAddress + thisSlotSize - 1

			# Does this SRAM cell contain the interrupt vector table?
			ivtRange = range(self.VectorsStartAddress, self.VectorsStartAddress + self.VectorsSize)
			slotRange = range(slotStartAddress, slotStartAddress + thisSlotSize)
			set1 = set(ivtRange)
			if len(set1.intersection(slotRange)) > 0:
				# This SRAM cell contains the interrupt vector table
				if self.VectorsStartAddress != slotStartAddress:
					raise Exception('The start address of the SRAM cell that contains the interrupt vector table must equal the address of the interrupt vector table')
				t.AddRow(['SRAM' + self.fmtint(slot, minDigits=2) + ' (rwx)', ': ORIGIN = ' + self.fmthex(slotStartAddress + self.VectorsSize, 5) + ', LENGTH = ' + self.fmthex(thisSlotSize - self.VectorsSize, 5), '/* END = ' + self.fmthex(slotEndAddress, 5) + ', SIZE = ' + str(thisSlotSize - self.VectorsSize) + ' bytes */'], prefixTabs=1)
			else:
				# This SRAM cell does not contain the interrupt vector table
				t.AddRow(['SRAM' + self.fmtint(slot, minDigits=2) + ' (rwx)', ': ORIGIN = ' + self.fmthex(slotStartAddress, 5) + ', LENGTH = ' + self.fmthex(thisSlotSize, 5), '/* END = ' + self.fmthex(slotEndAddress, 5) + ', SIZE = ' + str(thisSlotSize // 1024) + ' KiB */'], prefixTabs=1)
			
		# Add the extra memory sections
		if self.ExtraMemorySections is not None:
			t.AddBlankLine()
			for section in self.ExtraMemorySections:
				t.AddRow([element for element in section], prefixTabs=1)
		
		# Add the unused section
		t.AddBlankLine()
		t.AddRow(['UNUSED', ': ORIGIN = 0xFFFF0000, LENGTH = 0x10000', '/* END = 0xFFFFFFFF, SIZE = 64 KiB, used for throwing away unneeded data generated by the compiler */'], prefixTabs=1)
		
		s += t.ToString()
		s += '}\n'
		
		# Save the file
		f = open(outPath, 'w', newline='\n')
		f.write(s)
		f.close()
		
		print('Linker memory map file saved to ' + outPath)
		
		return
	
	def generatePeriphX(self, outPath):
		self.isTimeToGenerate()
		
		s = ''
		t = TabbedTable()
		
		# Create the preamble
		s += '/**\n'
		s += ' **\tperiph.x\n'
		s += ' **\tPeripheral and register address linker file\n'
		s += ' **\tDefines the microcontroller peipheral and register addresses\n'
		s += ' **\tGenerated on ' + datetime.datetime.now().strftime('%Y/%m/%d at %H:%M:%S') + ' with the MemoryMap.py memory map generator\n'
		s += ' **\tWARNING: Do not edit or modify this file!\n'
		s += ' **\t\tIf you need to change it, use the MemoryMap.py memory map generator tool\n'
		s += ' **/\n'
		
		s += '\n'
		
		# Define the RAM and ROM locations and sizes
		t.AddRow(['__RomStartAddress', '= ' + self.fmthex(self.RomStartAddress) + ';'])
		t.AddRow(['__RomSize', '= ' + self.fmthex(self.RomSize) + ';'])
		t.AddRow(['__RamStartAddress', '= ' + self.fmthex(self.RamStartAddress) + ';'])
		t.AddRow(['__RamSize', '= ' + self.fmthex(self.RamSize) + ';'])
		t.AddRow(['__RamProgramStartAddress', '= ' + self.fmthex(self.RamProgramStartAddress) + ';'])
		t.AddRow(['__InterruptHandlerAddress', '= ' + self.fmthex(self.PROGADDR_IRQ) + ';'])
		t.AddRow(['__ProgramCounterInit', '= ' + self.fmthex(self.ProgramCounterInit) + ';'])
		t.AddRow(['__StackPointerInit', '= ' + self.fmthex(self.StackPointerInit) + ';'])
		
		t.AddBlankLine()
		
		# Add the registers
		for tup in self.AddressTable:
			t.AddRow(['__' + tup[0], '= ' + self.fmthex(tup[1]) + ';'])
		
		s += t.ToString()
		
		# Save the file
		f = open(outPath, 'w', newline='\n')
		f.write(s)
		f.close()
		
		print('Linker peripheral addresses file saved to ' + outPath)
		
		return
	
	def generatePeriphS(self, outPath):
		self.isTimeToGenerate()
		
		s = ''
		t = TabbedTable()
		
		# Create the preamble
		s += '// periph.S\n'
		s += '// Peripheral and register address assembly header\n'
		s += '// Defines the microcontroller peipheral and register addresses\n'
		s += '// Generated on ' + datetime.datetime.now().strftime('%Y/%m/%d at %H:%M:%S') + ' with the MemoryMap.py memory map generator\n'
		s += '// WARNING: Do not edit or modify this file!\n'
		s += '//   If you need to change it, use the MemoryMap.py memory map generator tool\n'
		
		s += '\n'
		
		# Define the RAM and ROM locations and sizes
		t.AddRow(['#define RomStartAddress', self.fmthex(self.RomStartAddress)])
		t.AddRow(['#define RomSize', self.fmthex(self.RomSize)])
		t.AddRow(['#define PeripheralMemoryStartAddress', self.fmthex(self.PeripheralMemoryStartAddress)])
		t.AddRow(['#define PeripheralMemorySize', self.fmthex(self.PeripheralMemorySize)])
		t.AddRow(['#define RamStartAddress', self.fmthex(self.RamStartAddress)])
		t.AddRow(['#define RamSize', self.fmthex(self.RamSize)])
		t.AddRow(['#define RamProgramStartAddress', self.fmthex(self.RamProgramStartAddress)])
		t.AddRow(['#define InterruptHandlerAddress', self.fmthex(self.PROGADDR_IRQ)])
		t.AddRow(['#define ProgramCounterInit', self.fmthex(self.ProgramCounterInit)])
		t.AddRow(['#define StackPointerInit', self.fmthex(self.StackPointerInit)])
		if self.BootloaderUsesSpiFlashCommands:
			t.AddRow(['#define BOOTLOADER_USES_SPI_FLASH_COMMANDS'])
		t.AddRow(['#define SpiFlashProgramAddress', self.fmthex(self.SpiFlashProgramAddress)])
		
		t.AddBlankLine()
		
		# Add the CS_FLASH, SCK0, MOSI0, MISO0, and BOOT bit masks
		GPIO0 = self.FindPeripheral('GPIO0')
		try:
			PinCS_FLASH = GPIO0.FindGpio(primaryName='CS_FLASH')
		except:
			PinCS_FLASH = GPIO0.FindGpio(funcName='CS_FLASH')
		PinMISO0 = GPIO0.FindGpio(funcName='MISO0')
		PinMOSI0 = GPIO0.FindGpio(funcName='MOSI0')
		PinSCK0 = GPIO0.FindGpio(funcName='SCK0')
		GPIO1 = self.FindPeripheral('GPIO1')
		PinTX0 = GPIO1.FindGpio(funcName='TX0')
		PinRX0 = GPIO1.FindGpio(funcName='RX0')
		PinTRAP = GPIO0.FindGpio(funcName='TRAP')
		PinBOOT = GPIO0.FindGpio(primaryName='BOOT')
		
		P1SEL_BOOT_VAL = 0
		if PinCS_FLASH.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinCS_FLASH.BitNumber
		if PinMISO0.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinMISO0.BitNumber
		if PinMOSI0.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinMOSI0.BitNumber
		if PinSCK0.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinSCK0.BitNumber
		if PinTX0.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinTX0.BitNumber
		if PinRX0.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinRX0.BitNumber
		if PinTRAP.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinTRAP.BitNumber
		if PinBOOT.RstSEL:
			P1SEL_BOOT_VAL |= 0b1 << PinBOOT.BitNumber
		
		t.AddRow(['#define CS_FLASH_MASK', self.fmthex(0b1 << PinCS_FLASH.BitNumber, minDigits=2)])
		t.AddRow(['#define P1SEL_BOOT_VAL', self.fmthex(P1SEL_BOOT_VAL, minDigits=2)])
		t.AddRow(['#define SPI0_P1DIR_MASK', self.fmthex((0b1 << PinSCK0.BitNumber) | (0b1 << PinMISO0.BitNumber) | (0b1 << PinMOSI0.BitNumber), minDigits=2)])
		t.AddRow(['#define BOOT_MASK', self.fmthex(0b1 << PinBOOT.BitNumber, minDigits=2)])
		
		t.AddBlankLine()

		# Chip Properties
		if self.ENABLE_IRQ_QREGS:
			t.AddRow(['#define ENABLE_IRQ_QREGS'])
		if self.ENABLE_IRQ_FAST_CONTEXT_SWITCHING:
			t.AddRow(['#define ENABLE_IRQ_FAST_CONTEXT_SWITCHING'])
		if self.ENABLE_COUNTERS:
			t.AddRow(['#define ENABLE_COUNTERS'])
		if self.ENABLE_COUNTERS64:
			t.AddRow(['#define ENABLE_COUNTERS64'])
		
		t.AddBlankLines(3)
		s += t.ToString()

		# Get all used peripheral templates
		usedPTs = []
		for p in self.Peripherals:
			if p.Template not in usedPTs:
				usedPTs.append(p.Template)

		# Add the register offsets and bit fields
		t = TabbedTable()
		t.AddLine('/********** Register Offsets and Bit Fields **********/')
		t.AddBlankLine()
		s += t.ToString()
		
		for pt in usedPTs:
			t = TabbedTable()
			t.AddLine('/** ' + pt.NameTemplate + ' **/')
			s += t.ToString()
			for rt in pt.RegisterTemplates:
				# Add the register
				t = TabbedTable()
				t.AddLine('// ' + rt.NameTemplate)
				t.AddRow(['#define ' + rt.NameTemplate + '_OFFSET', str(rt.Offset)])
				t.AddBlankLine()
				s += t.ToString()
				
				t = TabbedTable()
				hexDigits = None
				if rt.Size == 8:
					hexDigits = 2
				elif rt.Size == 16:
					hexDigits = 4
				else:
					hexDigits = 8
				
				# Add the bit fields
				bfDefines = 0
				for bf in rt.BitFields:
					if bf.Unused is True:
						continue
					if bf.Size == 1:
						if bf.SameNameAsRegister:
							continue
						t.AddRow(['#define ' + bf.Name, self.fmthex(bf.BitMask, minDigits=hexDigits), '// bit ' + str(bf.MSB)])
						t.AddRow(['#define ' + bf.Name + '_LSB', self.fmtint(bf.LSB, minDigits=1)])
						bfDefines += 1
					else:
						if not bf.SameNameAsRegister:
							t.AddRow(['#define ' + bf.Name + '_MASK', self.fmthex(bf.BitMask, minDigits=hexDigits), '// bits ' + str(bf.MSB) + ' downto ' + str(bf.LSB)])
							t.AddRow(['#define ' + bf.Name + '_LSB', self.fmtint(bf.LSB, minDigits=1)])
							bfDefines += 1
						for vd in bf.ValueDescriptions:
							if len(vd) == 3:
								if len(vd[2]) > 0:
									# This value description has a name, so add it
									t.AddRow(['#define ' + vd[2], self.fmthex(vd[0] << bf.LSB, minDigits=hexDigits)])
				
				if bfDefines > 0:
					t.AddBlankLine()
				s += t.ToString()
			t = TabbedTable()
			t.AddBlankLines(2)
			s += t.ToString()

		
		# Add the peripheral base addresses and the register offsets
		t = TabbedTable()
		t.AddLine('/********** Peripheral Base Addresses **********/')

		for p in self.Peripherals:
			t.AddRow(['#define ' + p.Name + '_BASE', self.fmthex(p.BaseAddress)])
		
		s += t.ToString()
		
		## Add the register addresses
		#t.AddLine('// All registers')
		#for tup in self.AddressTable:
		#	t.AddRow(['#define ' + tup[0], self.fmthex(tup[1])])
		#
		#s += t.ToString()
		
		# Save the file
		f = open(outPath, 'w', newline='\n')
		f.write(s)
		f.close()
		
		print('Assembly peripheral addresses header file saved to ' + outPath)
		
		return
	
	def generateMemoryMapVHD(self, outPath):
		self.isTimeToGenerate()
		
		s = ''
		
		# Create the preamble
		s += '-- MemoryMap.vhd\n'
		s += '-- Memory map VHDL package\n'
		s += '-- Defines the memory map of the MCU, including which RAM and peripheral slots are activated, as well as which slot each peripheral is allocated to, and the slot each register within each peripheral is allocated to\n'
		s += '-- Generated on ' + datetime.datetime.now().strftime('%Y/%m/%d at %H:%M:%S') + ' with the MemoryMap.py memory map generator\n'
		s += '-- WARNING: Do not edit or modify this file!\n'
		s += '-- \tIf you need to change it, use the MemoryMap.py memory map generator tool\n'
		
		s += '\n'
		
		# Add the libraries
		s += 'library ieee;\n'
		s += 'use ieee.std_logic_1164.all;\n'
		s += 'use ieee.std_logic_arith.all;\n'
		s += 'use ieee.std_logic_unsigned.all;\n'
		s += 'use ieee.numeric_std.all;\n'
		s += 'library work;\n'
		s += 'use work.Constants.all;\n'
		
		s += '\n\n\n'
		
		# Begin the package
		s += 'package MemoryMap is\n'
		s += '\n'

		# Add the pad logic levels
		t = TabbedTable()
		t.AddLine('---------- Pad IP Logic Levels ----------', prefixTabs=1)
		t.AddRow(['constant PadOUTLogicLevel', ': boolean := ' + str(self.PadOUTPosLogic).lower() + ';', '-- Configured such that setting PxOUT to \'1\' will drive the output of the pad HIGH'], prefixTabs=1)
		t.AddRow(['constant PadDIRLogicLevel', ': boolean := ' + str(self.PadDIRPosLogic).lower() + ';', '-- Configured such that setting PxDIR to \'1\' will set the pad to OUTPUT mode'], prefixTabs=1)
		t.AddRow(['constant PadRENLogicLevel', ': boolean := ' + str(self.PadRENPosLogic).lower() + ';', '-- Configured such that setting PxREN to \'1\' will enable the pad pullup/pulldown resistor'], prefixTabs=1)
		#t.AddRow(['constant PadOCENLogicLevel', ': boolean := ' + str(self.PadOCENPosLogic).lower() + ';', '-- Configured such that setting PxOCEN to \'1\' will enable the pad open collector/open drain mode'], prefixTabs=1)
		
		t.AddBlankLines(3)
		
		# Add the pad logic levels
		t.AddLine('---------- Memory Information ----------', prefixTabs=1)
		t.AddRow(['constant RamStartAddress', ': natural := ' + str(self.RamStartAddress) + ';', '-- ' + self.fmthex(self.RamStartAddress)], prefixTabs=1)
		t.AddRow(['constant RamSize', ': natural := ' + str(self.RamSize) + ';', '-- ' + self.fmthex(self.RamSize)], prefixTabs=1)
		
		t.AddBlankLines(3)
		
		# Add the peripheral slot enables
		usePeripheralSlot = [False for i in range(self.PeripheralMemorySlotCount)]
		for p in self.Peripherals:
			usePeripheralSlot[p.PeripheralMemorySlot] = True
		
		t.AddLine('---------- Memory Slot Enables/Disables ----------', prefixTabs=1)
		t.AddLine('-- Peripheral Slot Enables/Disables', prefixTabs=1)
		for i in range(self.PeripheralMemorySlotCount):
			t.AddRow(['constant UsePeriph' + self.fmtint(i, 2), ': boolean := ' + str(usePeripheralSlot[i]).lower() + ';', '-- base address = ' + self.fmthex(self.PeripheralMemoryStartAddress + i * self.PeripheralMemorySlotSize)], prefixTabs=1)
		
		t.AddBlankLine()
		
		# Add the SRAM slot enables
		t.AddLine('-- SRAM Slot Enables/Disables', prefixTabs=1)
		for i in self.RamMemorySlotsAvailable:
			available = 'false'
			if i in self.RamMemorySlotsUsed:
				available = 'true'
			
			t.AddRow(['constant UseSRAM' + self.fmtint(i, 2), ': boolean := ' + available + ';', '-- base address = ' + self.fmthex(i * self.RamMemorySlotSize)], prefixTabs=1)
		
		t.AddBlankLines(3)
		
		# Add the peripheral memory slot assignments
		t.AddLine('---------- Peripheral Memory Slot Assignments ----------', prefixTabs=1)
		for i in range(self.PeripheralMemorySlotCount):
			name = None
			for p in self.Peripherals:
				if i == p.PeripheralMemorySlot:
					name = p.Name
					break
			
			if name is None:
				t.AddRow(['--constant PeriphSlot', ': natural := ' + self.fmtint(i, 2) + ';', '-- base address = ' + self.fmthex(self.PeripheralMemoryStartAddress + i * self.PeripheralMemorySlotSize)], prefixTabs=1)
			else:
				t.AddRow(['constant PeriphSlot' + name, ': natural := ' + self.fmtint(i, 2) + ';', '-- base address = ' + self.fmthex(self.PeripheralMemoryStartAddress + i * self.PeripheralMemorySlotSize)], prefixTabs=1)
		
		t.AddBlankLines(3)
		
		# Get all used peripheral templates
		usedPTs = []
		for p in self.Peripherals:
			if p.Template not in usedPTs:
				usedPTs.append(p.Template)
		
		# Add the peripheral register address offsets
		t.AddLine('---------- Peripheral Register Address Offsets ----------', prefixTabs=1)
		for pt in usedPTs:
			t.AddLine('-- ' + pt.NameTemplate, prefixTabs=1)
			for rt in pt.RegisterTemplates:
				t.AddRow(['constant RegSlot' + rt.NameTemplate, ': natural := ' + self.fmtint(rt.RegisterMemorySlot) + ';', '-- offset = ' + str(rt.RegisterMemorySlot * 4) + ' bytes'], prefixTabs=1)
			t.AddBlankLine()
		t.AddBlankLines(2)
		
		# Add the GPIO pin numbers
		t.AddLine('---------- GPIO Pin Numbers ----------', prefixTabs=1)
		for p in self.Peripherals:
			if p.IsGPIO():
				if len(p.Pins) < 1:
					continue
				
				t.AddLine('-- GPIO' + p.GetGPIOPortLabel(), prefixTabs=1)
				for pin in p.Pins:
					if pin.NoConnect:
						continue
					if len(pin.FuncName) > 0:
						t.AddRow(['constant PinNumGPIO' + p.GetGPIOPortLabel() + pin.FuncName, ': natural := ' + self.fmtint(pin.BitNumber) + ';', '-- P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber)], prefixTabs=1)
				t.AddBlankLine()
		
		t.AddBlankLines(2)
		
		s += t.ToString()
		
		# Add the GPIO register reset values
		t = TabbedTable()
		t.AddLine('---------- GPIO Register Reset Values ----------', prefixTabs=1)
		for p in self.Peripherals:
			if p.IsGPIO():
				t.AddLine('-- GPIO' + p.GetGPIOPortLabel(), prefixTabs=1)
				
				rstValPxOUT = 0
				rstValPxDIR = 0
				rstValPxSEL = 0
				rstValPxREN = 0
				#rstValPxOCEN = 0
				
				for pin in p.Pins:
					if pin.NoConnect:
						continue
					rstValPxOUT |= pin.RstOUT << pin.BitNumber
					rstValPxDIR |= pin.RstDIR << pin.BitNumber
					rstValPxSEL |= pin.RstSEL << pin.BitNumber
					rstValPxREN |= pin.RstREN << pin.BitNumber
					#rstValPxOCEN |= pin.RstOCEN << pin.BitNumber
				
				t.AddRow(['constant RstValP' + p.GetGPIOPortLabel() + 'OUT', ': slv(31 downto 0) := X"' + self.fmthex(rstValPxOUT, 8)[2:] + '";'], prefixTabs=1)
				t.AddRow(['constant RstValP' + p.GetGPIOPortLabel() + 'DIR', ': slv(31 downto 0) := X"' + self.fmthex(rstValPxDIR, 8)[2:] + '";'], prefixTabs=1)
				t.AddRow(['constant RstValP' + p.GetGPIOPortLabel() + 'SEL', ': slv(31 downto 0) := X"' + self.fmthex(rstValPxSEL, 8)[2:] + '";'], prefixTabs=1)
				t.AddRow(['constant RstValP' + p.GetGPIOPortLabel() + 'REN', ': slv(31 downto 0) := X"' + self.fmthex(rstValPxREN, 8)[2:] + '";'], prefixTabs=1)
				#t.AddRow(['constant RstValP' + p.GetGPIOPortLabel() + 'OCEN', ': slv(31 downto 0) := X"' + self.fmthex(rstValPxOCEN, 8)[2:] + '";'], prefixTabs=1)
				
				t.AddBlankLine()
		
		t.AddBlankLines(2)

		s += t.ToString()

		# Add the interrupt vector priority (bit numbers)
		t = TabbedTable()
		t.AddLine('---------- Interrupt Vector Bit Numbers (Priorities) ----------', prefixTabs=1)
		for i in range(0, 32):
			# Search for a peripheral with this interrupt priority (there are either 1 or 0 of them for each interrupt priority number)
			for p in self.Peripherals:
				if p.InterruptPriority == i:
					t.AddRow(['constant IrqBit' + p.Name, ': natural := ' + self.fmtint(i, minDigits=2) + ';', '-- IVT address = ' + self.fmthex(self.VectorsStartAddress + i * 4)], prefixTabs=1)
					break
		
		t.AddBlankLines(3)

		s += t.ToString()

		# Generate the CPU core constants
		t = TabbedTable()
		t.AddLine('---------- picorv32 CPU Configuration ----------', prefixTabs=1)
		t.AddRow(["constant picorv32_ENABLE_COUNTERS", ": sl", ":= '" + str(int(self.ENABLE_COUNTERS)) + "';"], prefixTabs=1)
		t.AddRow(["constant picorv32_ENABLE_COUNTERS64", ": sl", ":= '" + str(int(self.ENABLE_COUNTERS64 and self.ENABLE_COUNTERS)) + "';"], prefixTabs=1)	# Doesn't cost too much, and is the standard
		t.AddRow(["constant picorv32_ENABLE_REGS_16_31", ": sl", ":= '1';"], prefixTabs=1)	# Required for RV32I ISA
		t.AddRow(["constant picorv32_ENABLE_REGS_DUALPORT", ": sl", ":= '" + str(int(self.ENABLE_REGS_DUALPORT)) + "';"], prefixTabs=1)	# Enables/disables dual access to general purpose registers
		t.AddRow(["constant picorv32_LATCHED_MEM_RDATA", ": sl", ":= '" + str(int(self.LATCHED_MEM_RDATA)) + "';"], prefixTabs=1)	# The address decoder only guarantees the correct data to be output on rdata for one cycle, so this needs to be disabled
		t.AddRow(["constant picorv32_TWO_STAGE_SHIFT", ": sl", ":= '" + str(int(self.TWO_STAGE_SHIFT)) + "';"], prefixTabs=1)	# Enables/disables a two-stage bit shift operation. When enabled, this is a medium-speed shift. When disabled, it is slow
		t.AddRow(["constant picorv32_BARREL_SHIFTER", ": sl", ":= '" + str(int(self.BARREL_SHIFTER)) + "';"], prefixTabs=1)	# Enables/disables the fast barrel bit shift operation. Overrides TWO_STAGE_SHIFT when enabled
		t.AddRow(["constant picorv32_TWO_CYCLE_COMPARE", ": sl", ":= '0';"], prefixTabs=1)	# We want compares to be fast, so this needs to be disabled
		t.AddRow(["constant picorv32_TWO_CYCLE_ALU", ": sl", ":= '0';"], prefixTabs=1)	# We want ALU operations to be fast, so this needs to be disabled
		t.AddRow(["constant picorv32_COMPRESSED_ISA", ": sl", ":= '" + str(int(self.COMPRESSED_ISA)) + "';"], prefixTabs=1)	# Enables/disables the compressed ISA extension RV32IC
		t.AddRow(["constant picorv32_CATCH_MISALIGN", ": sl", ":= '1';"], prefixTabs=1)	# Enable catching misaligned memory addresses (disabling this does NOT help bad compressed ISA problems)
		t.AddRow(["constant picorv32_CATCH_ILLINSN", ": sl", ":= '1';"], prefixTabs=1)	# Enable catching illegal instructions (disabling this does NOT help bad compressed ISA problems)
		t.AddRow(["constant picorv32_ENABLE_PCPI", ": sl", ":= '0';"], prefixTabs=1)	# Don't need the pico co-proessor interface, except for the internal multiplier/divider, which this setting does not control
		t.AddRow(["constant picorv32_ENABLE_MUL", ": sl", ":= '" + str(int(self.ENABLE_MUL)) + "';"], prefixTabs=1)	# Enables/disables the hardware multiplier
		t.AddRow(["constant picorv32_ENABLE_FAST_MUL", ": sl", ":= '" + str(int(self.ENABLE_FAST_MUL)) + "';"], prefixTabs=1)	# Enables/disables the fast hardware multiplier. If both ENABLE_FAST_MUL and ENABLE_MUL are enabled, the ENABLE_MUL is ignored and the fast hardware multiplier is instantiated
		t.AddRow(["constant picorv32_ENABLE_DIV", ": sl", ":= '" + str(int(self.ENABLE_DIV)) + "';"], prefixTabs=1)	# Enables/disables the hardware divider and remainder calculator
		t.AddRow(["constant picorv32_ENABLE_IRQ", ": sl", ":= '1';"], prefixTabs=1)	# Enables/disables processor interrupts
		t.AddRow(["constant picorv32_ENABLE_IRQ_FAST_CONTEXT_SWITCHING", ": sl", ":= '" + str(int(self.ENABLE_IRQ_FAST_CONTEXT_SWITCHING)) + "';"], prefixTabs=1)
		t.AddRow(["constant picorv32_ENABLE_IRQ_QREGS", ": sl", ":= '" + str(int(self.ENABLE_IRQ_QREGS)) + "';"], prefixTabs=1)	# Enables/disables the four IRQ registers, which help speed IRQ calls
		t.AddRow(["constant picorv32_ENABLE_IRQ_TIMER", ": sl", ":= '" + str(int(self.ENABLE_IRQ_TIMER)) + "';"], prefixTabs=1)	# Enables the timer instruction
		t.AddRow(["constant picorv32_ENABLE_TRACE", ": sl", ":= '0';"], prefixTabs=1)
		t.AddRow(["constant picorv32_REGS_INIT_ZERO", ": sl", ":= '0';"], prefixTabs=1)	# Don't initialize registers to zero. While this would be convenient for simulation, it could be detrimental for synthesis
		t.AddRow(["constant picorv32_MASKED_IRQ", ": slv(31 downto 0)", ":= X\"{:08x}".format(self.MASKED_IRQ) + "\";"], prefixTabs=1)	# Any '1' bit corresponds to a permenantely disabled IRQ
		#t.AddRow(["constant picorv32_LATCHED_IRQ", "32'hFFFF_FFFF"])	# All interrupts are "edge sensitive". This means the interrupt is initiated on a low to high transition of the corresponding IRQ signal and stays pending until the interrupt handler is called
		t.AddRow(["constant picorv32_LATCHED_IRQ", ": slv(31 downto 0)", ":= X\"00000000\";"], prefixTabs=1)	# All interrupts are "level sensitive". This means the interrupt is initiated whenever the IRQ bit is high, and peripherals are responsible for setting their IRQ bit low again. This was done because using edge sensitive interrupts makes the interrupt handler execute twice in a row, since the CPU does not update the next_irq_pending signal at the appropriate time
		t.AddRow(["constant picorv32_PROGADDR_RESET", ": slv(31 downto 0)", ":= X\"{:08x}\";".format(self.ProgramCounterInit)], prefixTabs=1)	# The reset value of the program counter, which must be the start of the program. This MUST be the beginning of your program, which MUST be set to the start of the ROM
		t.AddRow(["constant picorv32_PROGADDR_IRQ", ": slv(31 downto 0)", ":= X\"{:08x}\";".format(self.PROGADDR_IRQ)], prefixTabs=1)	# The address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)
		t.AddRow(["constant picorv32_PROGADDR_IVT", ": slv(31 downto 0)", ":= X\"{:08x}\";".format(self.VectorsStartAddress)], prefixTabs=1)	# The address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)
		t.AddRow(["constant picorv32_STACKADDR", ": slv(31 downto 0)", ":= X\"FFFFFFFF\";"], prefixTabs=1)	# Do not hardware initialize the stack pointer (we cannot initialize register files to specific values). Allow software to do this instead

		t.AddBlankLines(3)

		s += t.ToString()

		# Add the bit field defines
		t = TabbedTable()
		t.AddLine('---------- Bit Field Defines ----------', prefixTabs=1)
		for pt in usedPTs:
			t.AddLine('------ ' + pt.NameTemplate, prefixTabs=1)
			for rt in pt.RegisterTemplates:
				usedRegister = False
				for bf in rt.BitFields:
					if bf.Unused:
						continue
					if not usedRegister:
						t.AddRow(['-- ' + rt.NameTemplate], prefixTabs=1)
						usedRegister = True
					if bf.Size > 1:
						t.AddRow(['constant ' + bf.Name + '_MSB', ': natural := ' + self.fmtint(bf.MSB) + ';'], prefixTabs=1)
					t.AddRow(['constant ' + bf.Name + '_LSB', ': natural := ' + self.fmtint(bf.LSB) + ';'], prefixTabs=1)
				if usedRegister:
					t.AddBlankLine()
			t.AddBlankLine()
		t.AddBlankLines(1)

		s += t.ToString()
		
		# Create the postamble
		s += 'end MemoryMap;\n'
		s += '\n'
		s += 'package body MemoryMap is\n'
		s += 'end MemoryMap;\n'
		
		# Save the file
		f = open(outPath, 'w', newline='\n')
		f.write(s)
		f.close()
		
		print('VHDL memory map file saved to ' + outPath)
		
		return
	
	def generateLatexUserGuide(self, outDirectoryPath):
		self.isTimeToGenerate()
		l = LatexUserGuide(self, outDirectoryPath)
		l.Generate()
		print('Latex MCU user guide latex project saved to ' + outDirectoryPath)
		return
	
	def generateSignalRoutingVHD(self, outPath, editFile=False):
		self.isTimeToGenerate()

		# Peripheral Pin Signal Declarations
		sigStr = ''
		sigTitle = 'Peripheral Pin Signal Declarations'
		sigHeader = '---------- Begin Automatically Generated ' + sigTitle + ' ----------'
		sigFooter = '---------- End Automatically Generated ' + sigTitle + ' ----------'
		t = TabbedTable()

		t.AddLine(sigHeader, prefixTabs=0)
		t.AddLine('-- WARNING: Do NOT edit or modify this section (' + sigTitle + '). It is automatically maintained by generate.py', prefixTabs=1)
		t.AddBlankLine()
		for p in self.Peripherals:
			if not p.IsGPIO():
				continue
			
			t.AddLine('-- GPIO' + p.GetGPIOPortLabel(), prefixTabs=1)
			numGpioPins = p.Registers[0].Size
			t.AddRow(['signal P' + p.GetGPIOPortLabel() + 'OUT', ': slv(' + str(numGpioPins - 1) + ' downto 0);'], prefixTabs=1)
			t.AddRow(['signal P' + p.GetGPIOPortLabel() + 'DIR', ': slv(' + str(numGpioPins - 1) + ' downto 0);'], prefixTabs=1)
			t.AddRow(['signal P' + p.GetGPIOPortLabel() + 'REN', ': slv(' + str(numGpioPins - 1) + ' downto 0);'], prefixTabs=1)
			t.AddRow(['signal Func' + p.GetGPIOPortLabel() + 'OUT', ': slv(' + str(numGpioPins - 1) + ' downto 0);'], prefixTabs=1)
			t.AddRow(['signal Func' + p.GetGPIOPortLabel() + 'DIR', ': slv(' + str(numGpioPins - 1) + ' downto 0);'], prefixTabs=1)
			t.AddRow(['signal Func' + p.GetGPIOPortLabel() + 'REN', ': slv(' + str(numGpioPins - 1) + ' downto 0);'], prefixTabs=1)
			t.AddBlankLine()
			
			# Add each pin signal
			for pin in p.Pins:
				if pin.NoConnect:
					continue
				if len(pin.FuncName) < 1:
					continue
				ioStr = ''
				if 'I' in pin.FuncIOType and 'O' in pin.FuncIOType:
					ioStr = 'input and output'
				elif 'I' in pin.FuncIOType:
					ioStr = 'input only'
				elif 'O' in pin.FuncIOType:
					ioStr = 'output only'
				t.AddLine('-- P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber) + ': ' + pin.FuncName + ' (' + ioStr + ')', prefixTabs=1)
				if 'I' in pin.FuncIOType:
					t.AddRow(['signal ' + pin.FuncName + '_IN', ': sl;'], prefixTabs=1)
				if 'O' in pin.FuncIOType:
					t.AddRow(['signal ' + pin.FuncName + '_OUT', ': sl;'], prefixTabs=1)
					t.AddRow(['signal ' + pin.FuncName + '_DIR', ': sl;'], prefixTabs=1)
					t.AddRow(['signal ' + pin.FuncName + '_REN', ': sl;'], prefixTabs=1)
				t.AddRow(['signal ' + pin.FuncName + '_REN_loopback', ': sl;'], prefixTabs=1)
				t.AddBlankLine()
			t.AddBlankLines(2)
		
		t.AddLine(sigFooter, prefixTabs=1)
			
		sigStr += t.ToString()[:-1]	# remove trailing newline
		
		# GPIO Signal Routing
		gpioStr = ''
		gpioTitle = 'GPIO Signal Routing'
		gpioHeader = '---------- Begin Automatically Generated ' + gpioTitle + ' ----------'
		gpioFooter = '---------- End Automatically Generated ' + gpioTitle + ' ----------'
		t = TabbedTable()
		
		t.AddLine(gpioHeader, prefixTabs=0)
		t.AddLine('-- WARNING: Do NOT edit or modify this section (' + gpioTitle + '). It is automatically maintained by generate.py', prefixTabs=1)
		for p in self.Peripherals:
			if not p.IsGPIO():
				continue
			
			t.AddLine('-- GPIO' + p.GetGPIOPortLabel(), prefixTabs=1)
			
			# Add each pin input
			for pin in p.Pins:
				if pin.NoConnect:
					continue
				if len(pin.FuncName) < 1:
					continue
				if 'I' not in pin.FuncIOType:
					continue
				t.AddRow([pin.FuncName + '_IN', '<= Prt' + p.GetGPIOPortLabel() + 'IN(PinNumGPIO' + p.GetGPIOPortLabel() + pin.FuncName + ');'], prefixTabs=1)
			
			# Add pin output, direction, and resistor enable enable
			b1 = '<= ('
			b2 = '<= ('
			b3 = '<= ('
			for pin in reversed(p.Pins):
				if pin.NoConnect or (len(pin.FuncName) < 1) or ('O' not in pin.FuncIOType):
					b1 += str(pin.BitNumber) + ' => P' + p.GetGPIOPortLabel() + 'OUT(' + str(pin.BitNumber) + '), '
					b2 += str(pin.BitNumber) + ' => P' + p.GetGPIOPortLabel() + 'DIR(' + str(pin.BitNumber) + '), '
					b3 += str(pin.BitNumber) + ' => P' + p.GetGPIOPortLabel() + 'REN(' + str(pin.BitNumber) + '), '
				else:
					b1 += 'PinNumGPIO' + p.GetGPIOPortLabel() + pin.FuncName + ' => ' + pin.FuncName + '_' + 'OUT' + ', '
					b2 += 'PinNumGPIO' + p.GetGPIOPortLabel() + pin.FuncName + ' => ' + pin.FuncName + '_' + 'DIR' + ', '
					b3 += 'PinNumGPIO' + p.GetGPIOPortLabel() + pin.FuncName + ' => ' + pin.FuncName + '_' + 'REN' + ', '
			b1 = b1[:-2] + ');'
			b2 = b2[:-2] + ');'
			b3 = b3[:-2] + ');'
			t.AddRow(['Func' + p.GetGPIOPortLabel() + 'OUT', b1], prefixTabs=1)
			t.AddRow(['Func' + p.GetGPIOPortLabel() + 'DIR', b2], prefixTabs=1)
			t.AddRow(['Func' + p.GetGPIOPortLabel() + 'REN', b3], prefixTabs=1)

			# Add loopbacks
			for pin in (p.Pins):
				if (not pin.NoConnect) and (len(pin.FuncName) > 0):
					t.AddRow([pin.FuncName + '_REN_loopback', '<= P' + p.GetGPIOPortLabel() + 'REN(PinNumGPIO' + p.GetGPIOPortLabel() + pin.FuncName + ');'], prefixTabs=1)
			t.AddBlankLine()
		t.AddLine(gpioFooter, prefixTabs=1)
			
		gpioStr += t.ToString()[:-1]	# remove trailing newline

		# Interrupt Signal Declarations
		irqDeclareStr = ''
		irqDeclareTitle = 'Peripheral Interrupt Signal Declarations'
		irqDeclareHeader = '---------- Begin Automatically Generated ' + irqDeclareTitle + ' ----------'
		irqDeclareFooter = '---------- End Automatically Generated ' + irqDeclareTitle + ' ----------'
		t = TabbedTable()
		
		t.AddLine(irqDeclareHeader, prefixTabs=0)
		t.AddLine('-- WARNING: Do NOT edit or modify this section (' + irqDeclareTitle + '). It is automatically maintained by generate.py', prefixTabs=1)

		for i in range(0, 32):
			# Search for a peripheral with this interrupt priority (there are either 1 or 0 of them for each interrupt priority number)
			for p in self.Peripherals:
				if p.InterruptPriority == i:
					t.AddRow(['signal Irq' + p.Name, ': sl;', '-- Priority = ' + self.fmtint(i, minDigits=2) + ', IVT address = ' + self.fmthex(self.VectorsStartAddress + i * 4)], prefixTabs=1)
					break
		t.AddLine(irqDeclareFooter, prefixTabs=1)

		irqDeclareStr += t.ToString()[:-1]	# remove trailing newline

		# Interrupt Signal Routing
		irqRouteStr = ''
		irqRouteTitle = 'Interrupt Signal Routing'
		irqRouteHeader = '---------- Begin Automatically Generated ' + irqRouteTitle + ' ----------'
		irqRouteFooter = '---------- End Automatically Generated ' + irqRouteTitle + ' ----------'
		t = TabbedTable()
		
		t.AddLine(irqRouteHeader, prefixTabs=0)
		t.AddLine('-- WARNING: Do NOT edit or modify this section (' + irqRouteTitle + '). It is automatically maintained by generate.py', prefixTabs=1)

		t.AddLine('IrqGlitchy <= (', prefixTabs=1)
		for i in range(32):
			# Search for a peripheral with this interrupt priority (there are either 1 or 0 of them for each interrupt priority number)
			for p in self.Peripherals:
				if p.InterruptPriority is i:
					t.AddRow(['IrqBit' + p.Name, '=> ' + 'Irq' + p.Name + ',', '-- Priority = ' + self.fmtint(i, minDigits=2) + ', IVT address = ' + self.fmthex(self.VectorsStartAddress + i * 4)], prefixTabs=2)
					break
		t.AddRow(['others', '=> IrqGlitchyZero'], prefixTabs=2)
		t.AddLine(');', prefixTabs=1)
		t.AddLine(irqRouteFooter, prefixTabs=1)

		irqRouteStr += t.ToString()[:-1]	# remove trailing newline
		
		if editFile == True:
			if not outPath.endswith('MCU.vhd'):
				raise Exception('The provided file ' + outPath + ' is not the correct MCU.vhd file')
			
			s = None
			with open(outPath, 'r') as f:
				s = f.read()
			
			# Find and replace the Peripheral Pin Signal Declarations section
			startIndex = s.find(sigHeader)
			if startIndex < 0:
				raise Exception('Could not find header "' + sigHeader + '" in file ' + outPath)
			endIndex = s.find(sigFooter)
			if endIndex < 0:
				raise Exception('Could not find footer "' + sigFooter + '" in file ' + outPath)
			endIndex += len(sigFooter)
			s = s[:startIndex] + sigStr + s[endIndex:]

			# Find and replace the GPIO Signal Routing section
			startIndex = s.find(gpioHeader)
			if startIndex < 0:
				raise Exception('Could not find header "' + gpioHeader + '" in file ' + outPath)
			endIndex = s.find(gpioFooter)
			if endIndex < 0:
				raise Exception('Could not find footer "' + gpioFooter + '" in file ' + outPath)
			endIndex += len(gpioFooter)
			s = s[:startIndex] + gpioStr + s[endIndex:]

			# Find and replace the Peripheral Interrupt Signal Declarations
			startIndex = s.find(irqDeclareHeader)
			if startIndex < 0:
				raise Exception('Could not find header "' + irqDeclareHeader + '" in file ' + outPath)
			endIndex = s.find(irqDeclareFooter)
			if endIndex < 0:
				raise Exception('Could not find footer "' + irqDeclareFooter + '" in file ' + outPath)
			endIndex += len(irqDeclareFooter)
			s = s[:startIndex] + irqDeclareStr + s[endIndex:]

			# Find and replace the Interrupt Signal Routing section
			startIndex = s.find(irqRouteHeader)
			if startIndex < 0:
				raise Exception('Could not find header "' + irqRouteHeader + '" in file ' + outPath)
			endIndex = s.find(irqRouteFooter)
			if endIndex < 0:
				raise Exception('Could not find footer "' + irqRouteFooter + '" in file ' + outPath)
			endIndex += len(irqRouteFooter)
			s = s[:startIndex] + irqRouteStr + s[endIndex:]
			
			# Write the changes to the file
			with open(outPath, 'w', newline='\n') as f:
				f.write(s)
			
			print('VHDL GPIO signal routing file saved to ' + outPath)
		else:
			if outPath.endswith('MCU.vhd'):
				raise Exception('As a safety feature, writing to a file called MCU.vhd is prohibited if editFile is False')
				return
			
			# Save the file
			with open(outPath, 'w', newline='\n') as f:
				f.write('\t' + gpioStr + '\n\n\n\t' + irqDeclareStr + '\n\n\n\t' + irqRouteStr)
			
			print('VHDL GPIO signal routing file saved to ' + outPath)
		
		return

	def generateRamRomSizeFiles(self, outDir):
		with open(outDir + '/RAM_START.txt', 'w') as f:
			f.write(self.fmthex(self.RamStartAddress))
		
		with open(outDir + '/RAM_SIZE.txt', 'w') as f:
			f.write(self.fmthex(self.RamSize))
		
		with open(outDir + '/ROM_START.txt', 'w') as f:
			f.write(self.fmthex(self.RomStartAddress))
		
		with open(outDir + '/ROM_SIZE.txt', 'w') as f:
			f.write(self.fmthex(self.RomSize))
		
		print('RAM and ROM size files saved to directory ' + outDir)
	
	def ToDict(self):
		# Create a dictionary of the MemoryMap object
		chip = dict()
		chip['ChipName'] = self.AsicName

		chip['RomStartAddress'] = self.RomStartAddress
		chip['RomSize'] = self.RomSize
		chip['RomEndAddress'] = self.RomEndAddress

		chip['PeripheralMemoryStartAddress'] = self.PeripheralMemoryStartAddress
		chip['PeripheralMemorySize'] = self.PeripheralMemorySize
		chip['PeripheralMemorySlotCount'] = self.PeripheralMemorySlotCount
		chip['RegisterMemorySlotsPerPeripheralMemorySlot'] = self.RegisterMemorySlotsPerPeripheralMemorySlot
		chip['PeripheralMemorySlotSize'] = self.PeripheralMemorySlotSize
		chip['PeripheralMemoryEndAddress'] = self.PeripheralMemoryEndAddress

		chip['RamStartAddress'] = self.RamStartAddress
		chip['RamSize'] = self.RamSize
		chip['RamMemorySlotSize'] = self.RamMemorySlotSize
		chip['LastRamMemorySlotSize'] = self.LastRamMemorySlotSize
		chip['RamMemorySlotsAvailable'] = self.RamMemorySlotsAvailable 
		chip['RamMemorySlotsUsed'] = self.RamMemorySlotsUsed
		chip['RamEndAddress'] = self.RamEndAddress
		chip['SpiFlashProgramAddress'] = self.SpiFlashProgramAddress
		chip['NativeSpiFlashMemoryReadAccess'] = self.NativeSpiFlashMemoryReadAccess
		chip['NativeSpiFlashMemoryWriteAccess'] = self.NativeSpiFlashMemoryWriteAccess

		chip['VectorsStartAddress'] = self.VectorsStartAddress
		chip['VectorsSize'] = self.VectorsSize
		chip['VectorsCount'] = self.VectorsCount
		chip['VectorsEndAddress'] = self.VectorsEndAddress
		chip['RamProgramStartAddress'] = self.RamProgramStartAddress
		chip['ProgramCounterInit'] = self.ProgramCounterInit
		chip['StackPointerInit'] = self.StackPointerInit
		chip['BootloaderUsesSpiFlashCommands'] = self.BootloaderUsesSpiFlashCommands

		chip['PadOUTPosLogic'] = self.PadOUTPosLogic
		chip['PadDIRPosLogic'] = self.PadDIRPosLogic
		chip['PadRENPosLogic'] = self.PadRENPosLogic

		chip['ENABLE_IRQ_FAST_CONTEXT_SWITCHING'] = self.ENABLE_IRQ_FAST_CONTEXT_SWITCHING
		chip['ENABLE_REGS_DUALPORT'] = self.ENABLE_REGS_DUALPORT
		chip['TWO_STAGE_SHIFT'] = self.TWO_STAGE_SHIFT
		chip['BARREL_SHIFTER'] = self.BARREL_SHIFTER
		chip['COMPRESSED_ISA'] = self.COMPRESSED_ISA
		chip['ENABLE_MUL'] = self.ENABLE_MUL
		chip['ENABLE_FAST_MUL'] = self.ENABLE_FAST_MUL
		chip['ENABLE_DIV'] = self.ENABLE_DIV
		chip['ENABLE_IRQ_QREGS'] = self.ENABLE_IRQ_QREGS
		chip['MASKED_IRQ'] = self.MASKED_IRQ
		chip['PROGADDR_IRQ'] = self.PROGADDR_IRQ

		peripherals = []
		for p in self.Peripherals:
			peripherals.append(p.ToDict())
		chip['Peripherals'] = peripherals

		return chip
	
	def generateMemoryMapJson(self, outPath):
		# Create a dictionary 
		memoryMapDict = self.ToDict()

		# Write it as a JSON file
		with open(outPath, 'w', newline='\n') as f:
			json.dump(memoryMapDict, f, indent='\t')
		
		print('JSON memory map file saved to ' + outPath)
		return
	
	
	
	
	
	
	
	
	
		
	def checkSymbolTable(self, symbols):
		for symbol in symbols:
			if len(symbol) < 1:
				raise Exception('Found empty symbol')
			
			num = symbols.count(symbol)
			if num != 1:
				raise Exception('Found ' + str(num) + ' instances of symbol "' + symbol + '" in symbol table. Only one instance is allowed.')
		
		return
	
	def fmthex(self, num, minDigits=4):
		fmtstr = '{:0' + str(minDigits) + 'x}'
		return '0x' + fmtstr.format(num).upper()
	
	def fmtint(self, num, minDigits=2):
		fmtstr = '{:0' + str(minDigits) + '}'
		return fmtstr.format(num)
	
	def isPower2(self, num):
		''' Returns True if num is a power of 2, returns False if not'''
		return num != 0 and ((num & (num - 1)) == 0)
	
	def isTimeToGenerate(self):
		if (self.NeedToCheckPeripheralTemplates == True):
			raise Exception('Cannot generate output files, need to run CheckPeripheralTemplates first')
		if (self.NeedToCheckPeripherals == True):
			raise Exception('Cannot generate output files, need to run CheckPeripherals first')
		if (self.NeedToCheckPins == True):
			raise Exception('Cannot generate output files, need to run CheckPackagePins first')
		
		return