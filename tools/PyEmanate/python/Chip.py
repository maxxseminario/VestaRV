import json, os, pathlib

from HelperFunctions import *

class Chip():
	# Memory Map Hardware Definitions (do not modify after loading)
	Name = None
	
	RomStartAddress = None
	RomSize = None
	RomEndAddress = None

	PeripheralMemoryStartAddress = None
	PeripheralMemorySize = None
	PeripheralMemorySlotCount = None
	RegisterMemorySlotsPerPeripheralMemorySlot = None
	PeripheralMemorySlotSize = None
	PeripheralMemoryEndAddress = None

	RamStartAddress = None
	RamSize = None
	RamMemorySlotSize = None
	RamMemorySlotsAvailable = None
	RamMemorySlotsUsed = None
	RamEndAddress = None
	SpiFlashProgramAddress = None
	NativeSpiFlashMemoryReadAccess = None
	NativeSpiFlashMemoryWriteAccess = None

	VectorsStartAddress = None
	VectorsSize = None
	VectorsCount = None
	VectorsEndAddress = None
	RamProgramStartAddress = None
	ProgramCounterInit = None
	StackPointerInit = None
	
	ENABLE_REGS_DUALPORT = None
	TWO_STAGE_SHIFT = None
	BARREL_SHIFTER = None
	COMPRESSED_ISA = None
	ENABLE_MUL = None
	ENABLE_FAST_MUL = None
	ENABLE_DIV = None
	ENABLE_IRQ_QREGS = None
	MASKED_IRQ = None
	PROGADDR_IRQ = None
	
	# List of peripherals. Each peripheral contains both hardware definitions and current value data.
	Peripherals = None
	
	# List of registers. Each register contains both hardware definitions and current value data. Registers retain links to their parent Peripheral through the Parent field
	Registers = None

	# Chip configuration data
	IDChipPrefix = None
	DieIDSuffix = None
	DieID = None
	ForthInitStringRom = None
	ForthInitStringFlash = None
	BootForthFlashWriteCompressionAllowed = None
	SwapProgramBytes = None
	SpiFlashProgramAddress = None
	BootForthHasMultiPageFlashEraseCommand = None
	BootloaderUsesSpiFlashCommands = None
	
	# List of supported circuit boards. Each contains only hardware definitions.
	Boards = None
	
	# File system data
	RootDirectory = None
	ConfigDirectory = None
	DataDirectory = None

	# Analog Front-Ends
	AFEs = None

	# Notes for the register saves
	NotesForRegisterSave = None

	UserDefinedForthFunctions = None
	
	
	
	
	# Load and setup methods
	@staticmethod
	def CreateFromPath(directoryPath:str):
		# Iteratively search for the config/ChipConfig.json file in each folder in the hierarchy
		while True:
			# Does the current directory have a file called config/ChipConfig.json?
			if os.path.isfile(directoryPath + '/config/ChipConfig.json'):
				return Chip.CreateFromChipRootDirectory(directoryPath)
			
			# Go up a directory
			parentDirectory = str(pathlib.Path(directoryPath).parent)
			if parentDirectory == directoryPath:
				return None
			directoryPath = parentDirectory
		
	@staticmethod
	def CreateFromExecutionDirectory():
		# Get the current working directory
		directoryPath = os.getcwd()

		# Create the chip
		return Chip.CreateFromPath(directoryPath)
		
	@staticmethod
	def CreateFromChipRootDirectory(chipRootDirectoryPath:str):
		if not os.path.isdir(chipRootDirectoryPath):
			return None
		configDirectoryPath = chipRootDirectoryPath + '/config'
		if not os.path.isdir(configDirectoryPath):
			return None
		memoryMapJsonPath = configDirectoryPath + '/MemoryMap.json'
		if not os.path.isfile(memoryMapJsonPath):
			return None
		chipConfigJsonPath = configDirectoryPath + '/ChipConfig.json'
		if not os.path.isfile(chipConfigJsonPath):
			return None
		boardConfigJsonPath = configDirectoryPath + '/BoardConfig.json'
		if not os.path.isfile(boardConfigJsonPath):
			return None
		
		chip = Chip()
		
		# Set up directories
		chip.RootDirectory = os.path.abspath(chipRootDirectoryPath)
		chip.ConfigDirectory = os.path.abspath(configDirectoryPath)
		chip.DataDirectory = chip.RootDirectory + '/data'
		
		# Load configuration files
		if not chip.LoadMemoryMapFromJson(memoryMapJsonPath):
			return None
		if not chip.LoadChipConfigFromJson(chipConfigJsonPath):
			return None
		if not chip.LoadBoardsFromJson(boardConfigJsonPath):
			return None
		
		return chip
	
	@staticmethod
	def GetAvailableChipsFromConfig():
		# Load PyEmanateConfig.json
		thisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
		pyEmanateConfigJsonPath = thisFileDirectory + '/../config/PyEmanateConfig.json'
		if not os.path.isfile(pyEmanateConfigJsonPath):
			print('Could not load PyEmanate configuration file at', pyEmanateConfigJsonPath)
			return None
		
		with open(pyEmanateConfigJsonPath, 'r') as f:
			d = json.load(f)
		if type(d) != dict or 'FileType' not in d or d['FileType'] != 'PyEmanateConfig':
			print('Could not load PyEmanate configuration file at', pyEmanateConfigJsonPath)
			return None
		
		# Create the chips from their root directories
		chips = []
		for chipDir in d['ChipRootDirectories']:
			chipDir = absRootDir = str(pathlib.Path(os.path.expanduser(chipDir)).absolute())
			chip = Chip.CreateFromChipRootDirectory(chipDir)
			if chip is not None:
				chips.append(chip)
		
		return chips
	
	@staticmethod
	def InteractiveChipChooser(tryUsingExecutionDirectory:bool=True):
		# Try using the execution directory, if desired
		if tryUsingExecutionDirectory:
			chip = Chip.CreateFromExecutionDirectory()
			if chip is not None:
				return chip
		
		# Get the available chips
		chips = Chip.GetAvailableChipsFromConfig()
		
		if chips is None or len(chips) == 0:
			print('No chips available')
			return None
		
		if len(chips) == 1:
			return chips[0]
			
		# Enumerate the chips and ask the user which one they are using
		print('Available chips:')
		for i, chip in enumerate(chips):
			print('  ' + str(i + 1) + ': ' + chip.Name)
		
		# Get the user input
		s = input('Desired chip number: ')
		chipNum = strToInt(s)
		if type(chipNum) != int or not (1 <= chipNum <= len(chips)):
			print('Invalid selection')
			return None
		return chips[chipNum - 1]
	
	def LoadChipConfigFromJson(self, jsonPath:str):
		d = None
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		if d is None:
			return False
		if not self.LoadChipConfigFromDict(d):
			return False
		return True

	def LoadChipConfigFromDict(self, d:dict):
		if 'ChipName' not in d:
			return False
		if d['ChipName'] != self.Name and self.Name is not None:
			return False

		self.IDChipPrefix = d['IDChipPrefix']
		self.ForthInitStringRom = d['ForthInitStringRom']
		self.ForthInitStringFlash = d['ForthInitStringFlash']
		self.BootForthFlashWriteCompressionAllowed = d['BootForthFlashWriteCompressionAllowed']
		self.SwapProgramBytes = d['SwapProgramBytes']
		self.BootForthHasMultiPageFlashEraseCommand = d['BootForthHasMultiPageFlashEraseCommand']
		self.BootloaderUsesSpiFlashCommands = d['BootloaderUsesSpiFlashCommands']

		if 'UserDefinedForthFunctions' in d:
			self.UserDefinedForthFunctions = d['UserDefinedForthFunctions']

		if 'AFEs' in d:
			from AFE import AFE
			self.AFEs = [AFE.CreateFromDict(subDict, self) for subDict in d['AFEs']]
		
		return True

	def LoadMemoryMapFromJson(self, jsonPath:str):
		d = None
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		if d is None:
			return False
		if not self.LoadMemoryMapFromDict(d):
			return False
		return True
	
	def LoadMemoryMapFromDict(self, d):
		'''
		Loads the chip memory map from a dictionary. Does not load the register values.
		'''
		if d['ChipName'] != self.Name and self.Name is not None:
			return False
		
		self.Name = d['ChipName']
		
		self.RomStartAddress = d['RomStartAddress']
		self.RomSize = d['RomSize']
		self.RomEndAddress = d['RomEndAddress']
		
		self.PeripheralMemoryStartAddress = d['PeripheralMemoryStartAddress']
		self.PeripheralMemorySize = d['PeripheralMemorySize']
		self.PeripheralMemorySlotCount = d['PeripheralMemorySlotCount']
		self.RegisterMemorySlotsPerPeripheralMemorySlot = d['RegisterMemorySlotsPerPeripheralMemorySlot']
		self.PeripheralMemorySlotSize = d['PeripheralMemorySlotSize']
		self.PeripheralMemoryEndAddress = d['PeripheralMemoryEndAddress']
		
		self.RamStartAddress = d['RamStartAddress']
		self.RamSize = d['RamSize']
		self.RamMemorySlotSize = d['RamMemorySlotSize']
		self.RamMemorySlotsAvailable = d['RamMemorySlotsAvailable']
		self.RamMemorySlotsUsed = d['RamMemorySlotsUsed']
		self.RamEndAddress = d['RamEndAddress']
		self.SpiFlashProgramAddress = d['SpiFlashProgramAddress']
		self.NativeSpiFlashMemoryReadAccess = d['NativeSpiFlashMemoryReadAccess']
		self.NativeSpiFlashMemoryWriteAccess = d['NativeSpiFlashMemoryWriteAccess']
		
		self.VectorsStartAddress = d['VectorsStartAddress']
		self.VectorsSize = d['VectorsSize']
		self.VectorsCount = d['VectorsCount']
		self.VectorsEndAddress = d['VectorsEndAddress']
		self.RamProgramStartAddress = d['RamProgramStartAddress']
		self.ProgramCounterInit = d['ProgramCounterInit']
		self.StackPointerInit = d['StackPointerInit']
		
		self.ENABLE_REGS_DUALPORT = d['ENABLE_REGS_DUALPORT']
		self.TWO_STAGE_SHIFT = d['TWO_STAGE_SHIFT']
		self.BARREL_SHIFTER = d['BARREL_SHIFTER']
		self.COMPRESSED_ISA = d['COMPRESSED_ISA']
		self.ENABLE_MUL = d['ENABLE_MUL']
		self.ENABLE_FAST_MUL = d['ENABLE_FAST_MUL']
		self.ENABLE_DIV = d['ENABLE_DIV']
		self.ENABLE_IRQ_QREGS = d['ENABLE_IRQ_QREGS']
		self.MASKED_IRQ = d['MASKED_IRQ']
		self.PROGADDR_IRQ = d['PROGADDR_IRQ']
		
		self.Peripherals = []
		peripherals = d['Peripherals']
		for pDict in peripherals:
			p = Peripheral.CreateFromMemoryMapDict(pDict)
			p.Parent = self
			self.Peripherals.append(p)
		
		self.Registers = []
		for p in self.Peripherals:
			for r in p.Registers:
				self.Registers.append(r)
		
		return True
	
	def LoadBoardsFromJson(self, jsonPath):
		d = None
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		if d is None:
			return False
		if d['ChipName'] != self.Name:
			return False
		dlist = d['Boards']
		self.LoadBoardsFromDictList(dlist)
		return True
	
	def LoadBoardsFromDictList(self, dlist):
		self.Boards = []
		for d in dlist:
			b = Board.CreateBoardFromDict(d)
			b.Parent = self
			self.Boards.append(b)
		
		return
	



	# Save and load registers methods
	def SaveRegisterValuesToDict(self, onlyMarked=False, timestampStr=None):
		peripherals = []
		for p in self.Peripherals:
			registers = []
			for r in p.Registers:
				if onlyMarked and not r.MarkToBeSaved:
					continue
				registers.append({'Name': r.Name, 'Address': r.Address, 'Value': r.CurrentValue})
			if len(registers) <= 0:
				continue
			peripherals.append({'Name': p.Name, 'BaseAddress': p.BaseAddress, 'Registers': registers})
		if timestampStr is None:
			timestampStr = get_string_timestamp(includeSeconds=True)
		d = {'Type': 'RegisterValues', 'ChipName': self.Name, 'DieID': self.DieID, 'Timestamp': timestampStr, 'NotesForRegisterSave': self.NotesForRegisterSave, 'Peripherals': peripherals}
		return d

	def SaveRegisterValuesToJson(self, outPath, onlyMarked=False):
		parentDir = os.path.dirname(outPath)
		if not os.path.isdir(parentDir):
			return False
		
		d = self.SaveRegisterValuesToDict(onlyMarked=onlyMarked)
		with open(outPath, 'w', newline='\n') as f:
			json.dump(d, f, indent='\t')
		return True
	



	# Public methods
	def GetPeripheral(self, name=None, baseAddress=None):
		if baseAddress is not None:
			p = None
			for candidatePeripheral in self.Peripherals:
				if candidatePeripheral.BaseAddress == baseAddress:
					p = candidatePeripheral
					break
			if p is None:
				return None
			if name is not None:
				if p.Name != name:
					return None
			return p
		elif name is not None:
			for candidatePeripheral in self.Peripherals:
				if candidatePeripheral.Name == name:
					p = candidatePeripheral
					break
			if p is None:
				return None
			return p
		else:
			return None
	
	def GetRegister(self, name=None, address=None):
		if address is not None:
			r = None
			for candidateRegister in self.Registers:
				if candidateRegister.Address == address:
					r = candidateRegister
					break
			if r is None:
				return None
			if name is not None:
				if r.Name != name:
					return None
			return r
		elif name is not None:
			for candidateRegister in self.Registers:
				if candidateRegister.Name == name:
					r = candidateRegister
					break
			if r is None:
				return None
			return r
		else:
			return None
	
	def GetBoard(self, name:str):
		if type(self.Boards) != list:
			return None
		for board in self.Boards:
			if (board.Name == name):
				return board
		return None
	
	def InteractiveBoardChooser(self):
		if type(self.Boards) != list:
			print('No boards are registered with this chip')
			return None
		if len(self.Boards) == 0:
			print('No boards are registered with this chip')
			return None
		elif len(self.Boards) == 1:
			return self.Boards[0]
		else:
			print('Available circuit boards:')
			for i, board in enumerate(self.Boards):
				print('  ' + str(i + 1) + ': ' + board.Name)
			desiredBoardKey = input('Desired circuit board: ')
			desiredBoardNum = None
			try:
				desiredBoardNum = int(desiredBoardKey) - 1
			except:
				print('Invalid circuit board')
				return None
			if (desiredBoardNum < 0) or (desiredBoardNum >= len(self.Boards)):
				print('Invalid circuit board')
				return None
			return self.Boards[desiredBoardNum]
		

class Peripheral():
	# Hardware Definitions (do not modify after loading)
	Name = None
	NameTemplate = None
	BaseAddress = None
	PeripheralMemorySlot = None
	isGPIO = None
	InterruptPriority = None
	Description = None
	
	Parent = None	# Chip parent object
	
	# List of registers. Each register contains both hardware definitions and current value data.
	Registers = None
	
	
	
	
	# Static load methods
	@staticmethod
	def CreateFromMemoryMapDict(d):
		peripheral = Peripheral()
		
		peripheral.Name = d['PeripheralName']
		peripheral.NameTemplate = d['PeripheralTemplateName']
		peripheral.BaseAddress = d['BaseAddress']
		peripheral.PeripheralMemorySlot = d['PeripheralMemorySlot']
		peripheral.isGPIO = d['isGPIO']
		peripheral.InterruptPriority = d['InterruptPriority']
		peripheral.Description = d['Description']
		
		peripheral.Registers = []
		registers = d['Registers']
		for rDict in registers:
			r = Register.CreateFromMemoryMapDict(rDict)
			r.Parent = peripheral
			peripheral.Registers.append(r)
		
		return peripheral
	
	def __str__(self):
		if type(self.Name) == str:
			return self.Name
		else:
			return ''
	
	def GetRegister(self, name=None, address=None):
		if address is not None:
			r = None
			for candidateRegister in self.Registers:
				if candidateRegister.Address == address:
					r = candidateRegister
					break
			if r is None:
				return None
			if name is not None:
				if r.Name != name:
					return None
			return r
		elif name is not None:
			for candidateRegister in self.Registers:
				if candidateRegister.Name == name:
					r = candidateRegister
					break
			if r is None:
				return None
			return r
		else:
			return None

class Register():
	# Hardware Definitions (do not modify after loading)
	Name = None
	Address = None
	AddressHex = None
	Offset = None
	RegisterMemorySlot = None
	Size = None
	ResetValue = None
	ResetValueHex = None
	Description = None
	
	WriteCheckMask = None	# A bit mask for the bits that, when written to, need to be read back the same value
	
	Parent = None	# Peripheral parent object
	
	# List of registers. Each bit filed contains both hardware definitions and current value data.
	BitFields = None
	
	# Current Value Data
	CurrentValue = None

	MarkToBeSaved = False

	# Previous Value Data
	ValueHistory = []
	ValueHistoryIndex = -1
	ValueHistoryMaxSize = 1000
	
	
	
	
	# Static load methods
	@staticmethod
	def CreateFromMemoryMapDict(d):
		register = Register()
		
		register.Name = d['RegisterName']
		register.Address = d['Address']
		register.Offset = d['Offset']
		register.RegisterMemorySlot = d['RegisterMemorySlot']
		register.Size = d['Size']
		register.ResetValue = d['ResetValue']
		register.Description = d['Description']
		
		register.AddressHex = fmthex(register.Address)
		register.ResetValueHex = fmthex(register.ResetValue, minDigits=(register.Size // 4))
		
		register.BitFields = []
		bitFields = d['BitFields']
		for bfDict in bitFields:
			bf = BitField.CreateFromMemoryMapDict(bfDict)
			bf.Parent = register
			register.BitFields.append(bf)
		
		# Create the write check mask
		register.WriteCheckMask = 0
		for i in range(register.Size):
			bf = register.GetBitFieldAt(i)
			if bf is None:
				continue
			if bf.Unused:
				continue
			if bf.Accessibility != 'rw':
				continue
			register.WriteCheckMask |= (0b1 << i)
		
		return register
	
	
	
	# Properties
	@property
	def CurrentValueHex(self):
		if self.CurrentValue is None:
			return None
		return fmthex(self.CurrentValue, minDigits=(self.Size // 4))
	
	@property
	def CurrentValueBin(self):
		if self.CurrentValue is None:
			return None
		return fmtbin(self.CurrentValue, minDigits=self.Size)

	@property
	def CurrentValueBinSeparated(self):
		if type(self.CurrentValue) != int:
			return None
		return fmtbin(self.CurrentValue, minDigits=self.Size, separatedBits=4)
	
	
	
	
	# Public methods
	def GetBitFieldAt(self, bitNum:int):
		for bf in self.BitFields:
			if bf.LSB <= bitNum <= bf.MSB:
				return bf
		return None
	
	def GetBitField(self, bitFieldName:str):
		if (len(bitFieldName) <= 0) or (bitFieldName.lower() == 'unused'):
			return None
		for bf in self.BitFields:
			if bf.Name == bitFieldName:
				return bf
		return None
	
	def GetBitResetValue(self, bitNum):
		return int(((0b1 << bitNum) & self.ResetValue) > 0)
	
	def ClearValueHistory(self):
		self.ValueHistory = []
		self.ValueHistoryIndex = -1
		return
	
	def __str__(self):
		if type(self.Name) == str:
			return self.Name
		else:
			return ''

class BitField():
	# Hardware Definitions (do not modify after loading)
	Name = None
	MSB = None
	LSB = None
	Accessibility = None
	ResetValue = None
	Unused = None
	Description = None
	Size = None
	RegisterBitMask = None
	BitFieldBitMask = None
	
	Parent = None	# Register parent object
	
	ValueDescriptions = None
	
	@staticmethod
	def CreateFromMemoryMapDict(d):
		bitField = BitField()
		
		bitField.Name = d['BitFieldName']
		bitField.MSB = d['MSB']
		bitField.LSB = d['LSB']
		bitField.Accessibility = d['Accessibility']
		bitField.ResetValue = d['ResetValue']
		bitField.Unused = d['Unused']
		bitField.Description = d['Description']
		vds = d['ValueDescriptions']
		bitField.ValueDescriptions = []
		for vd in vds:
			newVd = dict()
			newVd['Value'] = vd[0]
			newVd['Description'] = vd[1]
			if len(vd) == 3:
				newVd['Name'] = vd[2]
			else:
				newVd['Name'] = ''
			bitField.ValueDescriptions.append(newVd)
		
		# Set up calculated variables
		bitField.Size = 1 + bitField.MSB - bitField.LSB
		
		bitField.RegisterBitMask = 0
		for i in range(bitField.LSB, bitField.MSB + 1):
			bitField.RegisterBitMask |= 0b1 << i
		bitField.BitFieldBitMask = 0
		for i in range(1 + bitField.MSB - bitField.LSB):
			bitField.BitFieldBitMask |= 0b1 << i
		
		return bitField
	
	@property
	def CurrentValue(self):
		if type(self.Parent) != Register:
			return None
		if type(self.Parent.CurrentValue) != int:
			return None
		return (self.Parent.CurrentValue & self.RegisterBitMask) >> self.LSB
	
	@property
	def CurrentValueHex(self):
		if type(self.CurrentValue) != int:
			return None
		return fmthex(self.CurrentValue, minDigits=((self.Size + 3) // 4))
	
	@property
	def CurrentValueBin(self):
		if type(self.CurrentValue) != int:
			return None
		return fmtbin(self.CurrentValue, minDigits=self.Size)

	@property
	def CurrentValueBinSeparated(self):
		if type(self.CurrentValue) != int:
			return None
		return fmtbin(self.CurrentValue, minDigits=self.Size, separatedBits=4)
	
	def RegisterValueForBitFieldValue(self, hypotheticalBitFieldValue:int):
		if hypotheticalBitFieldValue & self.BitFieldBitMask:
			return None
		if type(self.Parent) != Register:
			return None
		if type(self.Parent.CurrentValue) != int:
			return None
		invmask = 0xFFFFFFFF ^ self.RegisterBitMask
		return (self.Parent.CurrentValue & invmask) | (hypotheticalBitFieldValue << self.LSB)
	
	def GetValueDescription(self, name=None, value=None):
		if name is not None:
			for vd in self.ValueDescriptions:
				if len(vd['Name']) <= 0:
					continue
				if vd['Name'] == name:
					if value is not None:
						if vd['Value'] == value:
							return vd
						else:
							return None
					else:
						return vd
			return None
		if value is not None:
			for vd in self.ValueDescriptions:
				if vd['Value'] == value:
					return vd
		return None
	
	def GetCurrentValueDescription(self):
		return self.GetValueDescription(value=self.CurrentValue)
	
	def __str__(self):
		if type(self.Name) == str:
			return self.Name
		else:
			return ''

class Board():
	# Hardware Definitions (do not modify after loading)
	Name = None
	
	Parent = None
	
	RomBootBaudrate = None
	SpiFlashBootBaudrate = None
	NormalBaudrate = None
	ProgrammingBaudrate = None
	
	# FTDI-controlled output signals. Each one is a dict with keys {'FtdiPin': str, 'Polarity': int}
	FtdiAssertReset = None
	FtdiDeassertReset = None
	FtdiBootRom = None
	FtdiBootSpiFlash = None
	
	# FTDI-controlled input signals. Each one is a dict with keys {'FtdiPin': str, 0: object (value if zero), 1: object (value if 1)}
	FtdiSenseBootState = None
	
	# FTDI-controlled sequencing for DTR and RTS governing boot and reset behavior
	FtdiUseRtsDtrSequencing = None
	InvertRts = None
	InvertDtr = None
	
	
	@staticmethod
	def CreateBoardFromDict(d):
		board = Board()
		board.__dict__ = d
		board.Name = board.BoardName
		return board

if __name__ == "__main__":
	print('Testing...')
	chip = Chip.CreateFromMemoryMapJson('../../picorv32-fpga/config/MemoryMap.json')
	print(chip.Name)
	print(chip.GetRegister('P1OUT').Name)
	chip.LoadBoardsFromJson('../../picorv32-fpga/config/BoardConfig.json')
	print(chip.Boards[0].Name)
	print(chip.Boards[0].FtdiAssertReset)
	print(chip.Boards[0].FtdiSenseBootState)