from Register import RegisterTemplate, Register
from GpioConfigurator import GpioConfigurator

import fnmatch

class PeripheralTemplate():
	NameTemplate = None
	Description = None
	RegisterPrefix = None
	BitFieldPrefix = None
	RegisterTemplates = None
	LatexIntroFileName = None
	
	Parent = None
	
	def __init__(self, nameTemplate, description='', registerPrefix=None, bitFieldPrefix=None, registerTemplates=None, latexIntroFileName=None):
		# Check nameTemplate
		if type(nameTemplate) != str:
			raise Exception('nameTemplate must be a string')
		if len(nameTemplate) < 1:
			raise Exception('nameTemplate cannot be empty')
		validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_x'
		for c in nameTemplate:
			if c not in validChars:
				raise Exception('RPeripheralTemplate\'s nameTemplate "' + nameTemplate + '" contains illegal character "' + c + '"')
		poundSignsInNameTemplate = nameTemplate.count('x')
		if poundSignsInNameTemplate > 1:
			raise Exception('Only one "x" character may be used in a name template')
		
		self.NameTemplate = nameTemplate
		
		# Set description
		self.Description = description
		self.RegisterPrefix = registerPrefix
		self.BitFieldPrefix = bitFieldPrefix
		
		self.isGPIO = None
		
		# Add register templates
		self.RegisterTemplates = []
		if registerTemplates is not None:
			if type(registerTemplates) != list:
				raise Exception('registerTemplates must be a list of RegisterTemplate objects')
			for register in registerTemplates:
				self.AddRegisterTemplate(register)
		
		# Add the latex introduction, if one is given
		if type(latexIntroFileName) == str:
			self.LatexIntroFileName = latexIntroFileName
		
		return
	
	def AddRegisterTemplate(self, registerTemplate):
		if type(registerTemplate) != RegisterTemplate:
			raise Exception('Not a RegisterTemplate type')
		registerTemplate.Parent = self
		self.RegisterTemplates.append(registerTemplate)
		return
	
	def CheckRegisterTemplates(self):
		# Check each register template for identical NameTemplates or RegisterMemorySlot
		for r1 in self.RegisterTemplates:
			for r2 in self.RegisterTemplates:
				if r1 == r2:
					continue
				
				# Check for duplicate names
				if r1.NameTemplate == r2.NameTemplate:
					raise Exception('PeripheralTemplate "' + self.NameTemplate + '" has more than one RegisterTemplate named "' + r1.NameTemplate + '"')
				
				# Check for duplicate memory slots
				if r1.RegisterMemorySlot == r2.RegisterMemorySlot:
					raise Exception('PeripheralTemplate "' + self.NameTemplate + '" has more than one register assigned to slot ' + str(r1.RegisterMemorySlot) + ' (' + r1.NameTemplate + ', ' + r2.NameTemplate + ')')
		
		# Check each register's bit fields
		for r in self.RegisterTemplates:
			r.CheckBitFields()
		
		# Sort register templates by slot number in ascending order
		self.RegisterTemplates = sorted(self.RegisterTemplates, key=lambda r: r.RegisterMemorySlot)
		
		return

class Peripheral():
	Template = None
	PeripheralMemorySlot = None
	NameIndex = None

	Parent = None
	
	BaseAddress = None
	Name = None
	Registers = None
	
	Description = None
	
	Pins = None
	isGPIO = None

	InterruptPriority = None
	LegacySlot = None	# The 0x4000-page slot NUMBER this peripheral owns (or owned, for shared-window
						# devices moved out of the page): the RTL still indexes periph_dout by these
						# numbers (e.g. to zero a moved peripheral's dead legacy window)

	def __init__(self, peripheralTemplate:PeripheralTemplate, peripheralMemorySlot:int, peripheralMemorySlotCount:int, registerMemorySlotsPerPeripheralMemorySlot:int, peripheralMemoryStartAddress:int, interruptPriority, nameIndex='', absoluteBaseAddress=None, legacySlot=None):
		'''
		@peripheralTemplate - The PeripheralTemplate type to bind this Peripheral to
		@peripheralMemorySlot - The peripheral memory slot number that this peripheral will use
		@peripheralMemorySlotCount - The total number of peripheral memory slots in the peripheral memory address space
		@registerMemorySlotsPerPeripheralMemorySlot - The number of register memory slots contained in one peripheral memory slot. A register memory slot is 4 bytes long (32 bits)
		@peripheralMemoryStartAddress - The address of the beginning of the peripheral memory address space
		@interruptPriority - The value of the interrupt priority (range: [0, ∞), smaller is higher priority). Also the element number in the interrupt vector table. Set to None if there is no interrupt in this peripheral
		@nameIndex - The index to replace the "x" character in the PeripheralTemplate and the RegisterTemplates
		@legacySlot - The 0x4000-page slot number this peripheral owns or (for shared-window devices) used to own. Defaults to peripheralMemorySlot. Set explicitly for moved peripherals whose slot number still matters to the RTL; None for devices that never had one (e.g. CLINT)
		'''
		# Check peripheralTemplate
		if type(peripheralTemplate) != PeripheralTemplate:
			raise Exception('Not a PeripheralTemplate type')
		
		self.Template = peripheralTemplate
		
		# Check the memory slot
		if type(peripheralMemorySlotCount) != int:
			raise Exception('peripheralMemorySlotCount must be an int > 0')
		if peripheralMemorySlotCount < 1:
			raise Exception('peripheralMemorySlotCount must be an int > 0')
		
		if absoluteBaseAddress is None:
			if type(peripheralMemorySlot) != int:
				raise Exception('peripheralMemorySlot must be an int on the range of [0, ' + str(peripheralMemorySlotCount) + '), but its value is ' + str(peripheralMemorySlot))
			if (peripheralMemorySlot < 0) or (peripheralMemorySlot >= peripheralMemorySlotCount):
				raise Exception('peripheralMemorySlot must be an int on the range of [0, ' + str(peripheralMemorySlotCount) + '), but its value is ' + str(peripheralMemorySlot))
			self.PeripheralMemorySlot = peripheralMemorySlot
		else:
			# Peripheral outside the standard peripheral slot space (e.g. a shared-window
			# device behind the multi-core arbiter). No slot; the base address is given directly.
			if type(absoluteBaseAddress) != int or absoluteBaseAddress < 0:
				raise Exception('absoluteBaseAddress must be an int >= 0, but its value is ' + str(absoluteBaseAddress))
			if peripheralMemorySlot is not None:
				raise Exception('peripheralMemorySlot must be None when absoluteBaseAddress is given')
			self.PeripheralMemorySlot = None
		
		if type(registerMemorySlotsPerPeripheralMemorySlot) != int:
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot must be an int > 0')
		if registerMemorySlotsPerPeripheralMemorySlot < 1:
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot must be an int > 0')
		
		# Check the peripheral memory offset
		if type(peripheralMemoryStartAddress) != int:
			raise Exception('peripheralMemoryStartAddress must be an int >= 0x0000')
		if peripheralMemoryStartAddress < 0:
			raise Exception('peripheralMemoryStartAddress must be an int >= 0x0000')
		
		# Calculate the base address
		if absoluteBaseAddress is None:
			self.BaseAddress = peripheralMemoryStartAddress + (peripheralMemorySlot * registerMemorySlotsPerPeripheralMemorySlot * 4)
		else:
			self.BaseAddress = absoluteBaseAddress
		
		# Check the name index
		validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
		nameIndexNeeded = 'x' in self.Template.NameTemplate
		if len(self.Template.RegisterTemplates) > 0:
			for r in self.Template.RegisterTemplates:
				nameIndexNeeded = nameIndexNeeded or 'x' in r.NameTemplate
		if type(nameIndex) is int:
			if nameIndex < 0:
				raise Exception('If nameIndex is an int, it must be >= 0. Name index given: ' + str(nameIndex))
			nameIndex = str(nameIndex)
		if len(nameIndex) < 1 and nameIndexNeeded:
			raise Exception('A nameIndex is needed, but an empty nameIndex was given')
		if len(nameIndex) > 0 and not nameIndexNeeded:
			raise Exception('A nameIndex is not needed, but a non-empty nameIndex was given')
		
		for c in nameIndex:
			if c not in validChars:
				raise Exception('Peripheral\'s nameIndex "' + nameIndex + '" contains illegal character "' + c + '"')
		
		# Set the name
		self.NameIndex = nameIndex
		self.Name = self.Template.NameTemplate.replace('x', nameIndex)
		
		# Copy data from PeripheralTemplate for ease-of-use
		self.Description = self.Template.Description

		# Set the interrupt priority (if there is an interrupt in this peripheral at all)
		if interruptPriority is None:
			self.InterruptPriority = None
		else:
			if type(interruptPriority) != int:
				raise Exception('interruptPriority must be None or a non-negative integer, but its value is ' + str(interruptPriority))
			if interruptPriority < 0:
				raise Exception('interruptPriority must be None or a non-negative integer, but its value is ' + str(interruptPriority))
			self.InterruptPriority = interruptPriority

		# Set the legacy 0x4000-page slot number
		if legacySlot is None:
			self.LegacySlot = self.PeripheralMemorySlot
		else:
			if type(legacySlot) != int:
				raise Exception('legacySlot must be None or a non-negative integer, but its value is ' + str(legacySlot))
			if (legacySlot < 0) or (legacySlot >= peripheralMemorySlotCount):
				raise Exception('legacySlot must be on the range of [0, ' + str(peripheralMemorySlotCount) + '), but its value is ' + str(legacySlot))
			if (self.PeripheralMemorySlot is not None) and (legacySlot != self.PeripheralMemorySlot):
				raise Exception('legacySlot (' + str(legacySlot) + ') contradicts peripheralMemorySlot (' + str(self.PeripheralMemorySlot) + ')')
			self.LegacySlot = legacySlot

		# Create blank pins list
		self.Pins = []
		
		# Generate the registers
		self.Registers = []
		for rt in self.Template.RegisterTemplates:
			r = Register(registerTemplate=rt, peripheralBaseAddress=self.BaseAddress, registerMemorySlotsPerPeripheralMemorySlot=registerMemorySlotsPerPeripheralMemorySlot, nameIndex=nameIndex)
			r.Parent = self
			self.Registers.append(r)
		
		return
	
	def IsGPIO(self):
		if self.isGPIO is not None:
			return self.isGPIO
		
		if not self.Name.startswith('GPIO'):
			self.isGPIO = False
			return self.isGPIO
		
		# Check the registers
		registerNames = []
		registerSizes = []
		for r in self.Registers:
			registerNames.append(r.Name)
			if len(fnmatch.filter([r.Name], 'P?EN')) == 0:
				registerSizes.append(r.Size)
		
		neededRegisters = ['P?IN', 'P?OUT', 'P?DIR', 'P?SEL', 'P?REN']	# 'P?OCEN'
		for neededRegister in neededRegisters:
			if len(fnmatch.filter(registerNames, neededRegister)) < 1:
				self.isGPIO = False
				return self.isGPIO
		
		#optionalRegistersSet1 = ['P?RIE', 'P?FIE', 'P?RIF', 'P?FIF']
		
		# Check if all the registers have the same size
		if registerSizes.count(registerSizes[0]) != len(registerSizes):
			raise Exception('The GPIO registers in peripheral "' + self.Name + '" must all have the same Size (except for PxEN)')
		
		if registerSizes[0] not in [8, 16, 32]:
			raise Exception('The GPIO registers in "' + self.Name + '" must have sizes of 8, 16, or 32 bits.')
		
		self.isGPIO = True
		return self.isGPIO
	
	def GetGPIOPortLabel(self):
		if not self.IsGPIO():
			raise Exception('Peripheral "' + self.Name + '" is not a valid GPIO peripheral')
		
		return self.NameIndex
	
	def GetGPIOPortSize(self):
		if not self.IsGPIO():
			raise Exception('Peripheral "' + self.Name + '" is not a valid GPIO peripheral')
		
		for r in self.Registers:
			if len(fnmatch.filter([r.Name], 'P?OUT')) > 0:
				return r.Size
		
		raise Exception('Could not find register "PxOUT" in supposed GPIO peripheral "' + self.Name + '"')
	
	def ChangeGPIOPortSize(self, size):
		if not self.IsGPIO():
			raise Exception('Peripheral "' + self.Name + '" is not a valid GPIO peripheral')
		
		if size not in [8, 16, 32]:
			raise Exception('size must be 8, 16, or 32')
		
		registersToChange = ['P?IN', 'P?OUT', 'P?OUTS', 'P?OUTC', 'P?DIR', 'P?IFG', 'P?IES', 'P?IE', 'P?SEL', 'P?REN', 'P?RIE', 'P?FIE', 'P?RIF', 'P?FIF']	# 'P?OCEN'
		
		for r in self.Registers:
			for wildcardRegisterName in registersToChange:
				if len(fnmatch.filter([r.Name], wildcardRegisterName)) > 0:
					r.Size = size
					if len(r.BitFields) != 1:
						raise Exception('There must be exactly one bit field the the GPIO register "' + r.Name + '"')
					r.BitFields[0].MSB = r.Size - 1
					r.BitFields[0].LSB = 0
					r.BitFields[0].Size = r.Size
					r.BitFields[0].BitMask = 0
					for i in range(r.Size):
						r.BitFields[0].BitMask |= (0b1 << i)
					break
		return
	
	def AddGpio(self, gpio, packagePinNumber=None, powerDomain=None):
		if type(gpio) != GpioConfigurator:
			raise Exception('GPIO pin must be of type GpioConfigurator')
		
		# Is this a GPIO peripheral?
		if not self.Name.startswith('GPIO'):
			raise Exception('Cannot add a GPIO pin to a peripheral that does not have a Name that starts with "GPIO"')
		
		# What is the size of the GPIO port?
		numAvailablePins = None
		for r in self.Registers:
			if r.Name.startswith('P') and r.Name.endswith('OUT'):
				numAvailablePins = r.Size
				break
		if numAvailablePins is None:
			raise Exception('Peripheral "' + self.Name + '" is not a valid GPIO peripheral because it does not contain a register named "PxOUT"')
		
		if gpio.BitNumber >= self.GetGPIOPortSize():
			raise Exception('Pin number ' + str(gpio.BitNumber) + ' is out-of-bounds for peripheral "' + self.Name + '" port of size ' + str(self.GetGPIOPortSize))
		
		gpio.ParentPeripheral = self
		
		self.Pins.append(gpio)

		# Add the package pin?
		if packagePinNumber is not None:
			p = self.Parent.Package.AddGpioPin(packagePinNumber=packagePinNumber, gpio=gpio)

			if powerDomain is not None:
				p.PowerDomain = powerDomain
			elif self.Parent.Package.GpioPowerDomain is not None:
				p.PowerDomain = self.Parent.Package.GpioPowerDomain
		
		return
	
	
	def FindGpio(self, primaryName='', funcName=''):
		if len(primaryName) < 1 and len(funcName) < 1:
			raise Exception('Must give either primaryName or funcName to find a Pin, but not both')
		if len(primaryName) > 0 and len(funcName) > 0:
			raise Exception('Must give either primaryName or funcName to find a Pin, but not both')
		
		if len(primaryName) > 0:
			for pin in self.Pins:
				if pin.PrimaryName == primaryName:
					return pin
			raise Exception('Could not find the desired Pin "' + primaryName + '"')
		
		if len(funcName) > 0:
			for pin in self.Pins:
				if pin.FuncName == funcName:
					return pin
			raise Exception('Could not find the desired Pin "' + funcName + '"')
		
		raise Exception('Could not find the desired Pin')
	
	def CheckGpios(self):
		if not self.IsGPIO():
			raise Exception('Peripheral "' + self.Name + '" is not a valid GPIO peripheral')
		
		# Check pins for identical PrimaryNames or FuncNames
		allPinNames = []
		for pin in self.Pins:
			if pin.NoConnect:
				continue
			if len(pin.PrimaryName) > 0:
				allPinNames.append(pin.PrimaryName)
			if len(pin.FuncName) > 0:
				allPinNames.append(pin.FuncName)
		for name in allPinNames:
			c = allPinNames.count(name)
			if c > 1:
				raise Exception('There are ' + str(c) + ' instances of the pin name "' + name + '" on GPIO peripheral "' + self.Name + '"')
		
		# Check pins for pin numbers, and if it is out of bounds of the GPIO port size
		bitNumbers = []
		for p1 in self.Pins:
			bitNumbers.append(p1.BitNumber)
			for p2 in self.Pins:
				if p1 == p2:
					continue
				
				if p1.BitNumber == p2.BitNumber:
					raise Exception('GPIO Peripheral "' + self.Name + '" has more than one Pin at pin number ' + str(p1.BitNumber))
			if p1.BitNumber >= self.GetGPIOPortSize():
				raise Exception('Pin number ' + str(p1.BitNumber) + ' is out-of-bounds for peripheral "' + self.Name + '" port of size ' + str(self.GetGPIOPortSize()))
		
		for i in range(self.GetGPIOPortSize()):
			if i not in bitNumbers:
				raise Exception('GPIO Peripheral "' + self.Name + '" should have ' + str(self.GetGPIOPortSize()) + ' bits, but is missing bit ' + str(i) + '. (Did you forget to add a noConnect=True to unused bits?)')
		
		# Sort register templates by slot number in ascending order
		self.Pins = sorted(self.Pins, key=lambda p: p.BitNumber)
		
		return

	def ToDict(self):
		# Create a dictionary of the Peripheral object
		p = dict()

		p['PeripheralName'] = self.Name
		p['PeripheralTemplateName'] = self.Template.NameTemplate
		p['BaseAddress'] = self.BaseAddress
		p['PeripheralMemorySlot'] = self.PeripheralMemorySlot
		p['isGPIO'] = self.isGPIO
		p['InterruptPriority'] = self.InterruptPriority
		p['Description'] = self.Description
		
		registers = []
		for r in self.Registers:
			registers.append(r.ToDict())
		p['Registers'] = registers

		return p