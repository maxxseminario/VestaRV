from copy import deepcopy
from time import sleep

from UART import UART
from Chip import *
from HelperFunctions import *
from LZW import LZW

class ForthInterface():
	
	uart = None
	ActiveChip = None
	ActiveBoard = None
	ActiveBootMode = None

	ForthFunctions = None

	# Properties
	@property
	def IsOpen(self):
		if self.uart is None:
			return False
		return self.uart.IsOpen
		
	@property
	def Connected(self):
		return self.IsOpen
	


	# Methods
	def InteractiveConnect(self, desiredBootMode=None):
		'''
		Uses the current working directory to automatically select the chip. Uses the interactive board chooser to select the board. Uses the interactive port chooser to select the port. Then, runs the Connect method
		'''
		activeChip = Chip.InteractiveChipChooser()
		if type(activeChip) != Chip:
			return False
		activeBoard = activeChip.InteractiveBoardChooser()
		if type(activeBoard) != Board:
			return False
		fakeUart = UART()
		port = fakeUart.InteractivePortChooser()
		if port is None:
			return False
		fakeUart = None
		return self.Connect(activeChip=activeChip, activeBoard=activeBoard, port=port, desiredBootMode=desiredBootMode)
		
	def Connect(self, activeChip:Chip, activeBoard:Board, port:str, desiredBootMode=None, addUserDefinedFunctions=False):
		'''
		Attempts to connect to the chip at the desired port using a Forth interpreter. Detects the boot mode of the forth interpreter (ROM or SpiFlash) and the name of the chip. If the name of the chip is not the same as activeChip.Name, does not connect. Uses the baudrate information from activeBoard. If desiredBootMode is provided, forces the chip into the desired boot mode, resetting it if necessary.
		
		@activeChip: Chip (an object representing the desired chip to connect to)
		@activeBoard: Board (an object representing the desired board to connect to)
		@port: str (represents the serial port to use to connect to the chip)
		@desiredBootMode: If None, attempts to connect to the board without resetting it or changing the boot mode. Otherwise, it must be either 'ROM' or 'SpiFlash', whereupon it will force the board to be in the correct boot mode, resetting it if necessary.
		
		Returns: bool (success)
		'''
		# Error checking
		if desiredBootMode not in [None, 'ROM', 'SpiFlash']:
			print('Invalid boot mode: ' + str(desiredBootMode))
			return False
		
		self.ActiveChip = activeChip
		self.ActiveBoard = activeBoard

		if self.HasBootSelectPin() and self.HasResetPin():
			# Get the initial RTS and DTR states
			initialRTS = None
			initialDTR = None
			if type(activeBoard.FtdiDeassertReset) == dict:
				if ('FtdiPin' in activeBoard.FtdiDeassertReset) and ('Polarity' in activeBoard.FtdiDeassertReset):
					polarity = strToInt(activeBoard.FtdiDeassertReset['Polarity'])
					if polarity in [0, 1]:
						if activeBoard.FtdiDeassertReset['FtdiPin'].lower() == 'dtr':
							initialDTR = polarity
						elif activeBoard.FtdiDeassertReset['FtdiPin'].lower() == 'rts':
							initialRTS = polarity
			if type(activeBoard.FtdiBootSpiFlash) == dict:
				if ('FtdiPin' in activeBoard.FtdiBootSpiFlash) and ('Polarity' in activeBoard.FtdiBootSpiFlash):
					polarity = strToInt(activeBoard.FtdiBootSpiFlash['Polarity'])
					if polarity in [0, 1]:
						if activeBoard.FtdiBootSpiFlash['FtdiPin'].lower() == 'dtr':
							initialDTR = polarity
						elif activeBoard.FtdiBootSpiFlash['FtdiPin'].lower() == 'rts':
							initialRTS = polarity
			
			# Create a UART interface (at the boot baudrate, just for starters) to check the status of the reset and boot pins
			baudrate = None
			if desiredBootMode == 'ROM':
				baudrate = activeBoard.RomBootBaudrate
			else:
				baudrate = activeBoard.SpiFlashBootBaudrate
			
			self.uart = UART()
			if self.uart.Open(port, baudrate, initialRTS=initialRTS, initialDTR=initialDTR) != True:
				self.Disconnect()
				print('Unable to open serial port: ' + port)
				return False
			
			# Should we reset the chip before attempting to communicate?
			if desiredBootMode is not None:
				# Reset the chip, either to SPI flash or Forth mode
				self.ResetChip(bootToForth=(desiredBootMode == 'ROM'))
			
			#if self.SetBootToSpiFlash() != True:
			#	self.Disconnect()
			#	print('Unable to control boot pin')
			#	return False
			#if self.DeassertReset() != True:
			#	self.Disconnect()
			#	print('Unable to control reset pin')
			#	return False
			#sleep(10e-3)
			#if self.ActiveBoard.FtdiSenseBootState is not None and 'FtdiPin' in self.ActiveBoard.FtdiSenseBootState and self.ActiveBoard.FtdiSenseBootState['FtdiPin'] is not None:
			#	currentBootPinMode = self.GetBootPinMode()
			#	if currentBootPinMode not in ['ROM', 'SpiFlash']:
			#		self.Disconnect()
			#		print('Unable to detect initial boot pin status')
			#		return False
			#
			## It seems that there is no way to guarantee the chip won't have a blip on the reset line while a connection is being established. Therefore, reset the chip into the desired mode now
			## Set the boot pin to the desired value
			#if desiredBootMode == 'ROM':
			#	self.SetBootToRom()
			#elif desiredBootMode == 'SpiFlash':
			#	self.SetBootToSpiFlash()
			#sleep(25e-3)
			#if self.ActiveBoard.FtdiSenseBootState is not None and 'FtdiPin' in self.ActiveBoard.FtdiSenseBootState and self.ActiveBoard.FtdiSenseBootState['FtdiPin'] is not None:
			#	currentBootPinMode = self.GetBootPinMode()
			#	if (desiredBootMode is not None) and (currentBootPinMode != desiredBootMode):
			#		self.Disconnect()
			#		print('Unable to set boot mode')
			#		return False
			#
			## Reset the chip
			#self.AssertReset()
			#self.uart.FlushBuffers()
			#sleep(25e-3)
			#self.DeassertReset()
			#sleep(250e-3)
			
			
			
			# Determine the current baudrate is correct by trial and error
			ret = self.testForthConnection()
			if ret is None:
				self.Disconnect()
				print('Unable to detect baudrate (1)')
				return False
			if ret != True:
				# This was not the correct baudrate. Try another one
				baudrate = activeBoard.NormalBaudrate
				self.uart.Baudrate = baudrate
				ret = self.testForthConnection()
				if ret is None:
					self.Disconnect()
					print('Unable to detect baudrate (2)')
					return False
				if ret != True:
					# This was not the correct baudrate
					if desiredBootMode is None:
						# The desired boot mode was never defined, so try the ROM boot baudrate (since it hasn't been tried yet)
						baudrate = activeBoard.RomBootBaudrate
						self.uart.Baudrate = baudrate
						ret = self.testForthConnection()
						if ret != True:
							self.Disconnect()
							print('Unable to detect baudrate (3)')
							return False
					else:
						self.Disconnect()
						print('Unable to detect baudrate (4)')
						return False
			sleep(50e-3)
		else:
			# This board does not have both reset and boot select FTDI pins
			# Create a UART interface (at the boot baudrate, just for starters) to check the status of the reset and boot pins
			baudrate = None
			if desiredBootMode == 'ROM':
				baudrate = activeBoard.RomBootBaudrate
				forthInitString = activeChip.ForthInitStringRom
				print('Please set the boot mode to ROM and reset the board')
			else:
				baudrate = activeBoard.SpiFlashBootBaudrate
				forthInitString = activeChip.ForthInitStringFlash
				print('Please set the boot mode to SPI flash and reset the board')
			
			self.uart = UART()
			if self.uart.Open(port, baudrate) != True:
				self.Disconnect()
				print('Unable to open serial port: ' + port)
				return False
			
			# Flush any garbage from the UART buffer immediately after opening
			self.uart.FlushBuffers()
			
			oldTimeout = self.uart.Timeout
			self.uart.Timeout = 10
			
			# Only wait for init string if one is specified
			if forthInitString and len(forthInitString) > 0:
				if self.uart.ReadUntil(forthInitString) is None:
					print('Timeout: Unable to connect to board')
					return False
			else:
				# No init string expected, give the chip time to boot and stabilize
				sleep(1.0)
				# Flush again in case chip sent data during boot
				self.uart.FlushBuffers()
			
			self.uart.Timeout = oldTimeout
			
		# Get the chip name (and disable echo) and determine if you're actually in the ROM or SpiFlash Forth interpreter
		ret = self.detectChipNameAndBootMode()
		if ret is None:
			self.Disconnect()
			print('Unable to determine the chip name')
			return False
		actualChipName, actualBootMode = ret
		if actualChipName != activeChip.Name:
			self.Disconnect()
			print('Desired chip name is ' + activeChip.Name + ' but the chip at port ' + port + ' is ' + actualChipName)
			return False
		
		# Load user defined functions to the chip
		if addUserDefinedFunctions:
			self.AddUserDefinedFunctions()
		
		# Everything checks out!
		self.ActiveChip = activeChip
		self.ActiveBoard = activeBoard
		self.ActiveBootMode = actualBootMode
		return True
	
	def Disconnect(self):
		'''
		Disconnects from the currently connected chip
		'''
		if type(self.uart) == UART:
			self.uart.Close()
		self.uart = None
		self.ActiveChip = None
		self.ActiveBoard = None
		self.ActiveBootMode = None
		return
	
	def UpdateAvailableFunctionsList(self):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		s = 'list 1 . 1 . 1 .'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('1 1 1 ')
		if self.detectImproperReply(r):
			return None
		if len(r) == 0:
			return None
		
		# Parse the list of functions
		r = r.replace('\r', '').replace('\n', '')
		funcs = list(set([s for s in r.split(' ') if not s.isspace()]))
		if len(funcs) == 0:
			return None

		self.ForthFunctions = funcs
		return self.ForthFunctions
	
	@staticmethod
	def ParseForthFunctionDefinitionString(func:str):
		# Check for problems
		if type(func) != str:
			return None
		if '\n' in func or '\r' in func or '\t' in func:
			return None
		func = func.strip()
		words = [s for s in func.split(' ') if not s.isspace()]
		if len(words) < 3:
			return None
		if not words[0] == ':':
			return None
		if not words[-1] == ';':
			return None
		name = words[1]

		# Check dependencies
		dependencies = []
		for word in words[2:-1]:
			# Is this a number?
			if word.isdigit():
				continue
			
			# Is this a hex number?
			if word.startswith('0x'):
				h = word[2:].upper()
				if len(h) > 8 or len(h) == 0:
					# Invalid hex number, too long or too short
					return None
				for c in h:
					if c not in '0123456789ABCDEF':
						return None
				continue
		
			# Add to dependencies list
			if word not in dependencies:
				dependencies.append(word)
		
		definition = ''
		for word in words:
			definition += word + ' '
		definition = definition[:-1]

		d = {
			'Name': name,
			'Definition': definition,
			'Dependencies': dependencies 
		}
		return d

	def AddForthFunction(self, func:str):
		'''
		Returns False if function is invalid
		Returns None if function cannot yet be defined for lack of dependencies, or because connection to the chip could not be established
		Returns True if function was successfully defined or if it is already defined
		'''
		if self.uart.IsOpen != True:
			return None
		
		d = ForthInterface.ParseForthFunctionDefinitionString(func)
		if d is None:
			return False
		if d['Name'] in self.ForthFunctions:
			return True	# Don't redefine a function

		# Check dependencies
		for word in d['Dependencies']:
			# Is this dependency available in the list of forth functions?
			if word not in self.ForthFunctions:
				return None
		
		# Add function
		self.uart.FlushReadBuffer()
		s = d['Definition'] + ' ' + str(ord('!')) + ' emit ' + str(ord('#')) + ' emit'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('!#')
		if self.detectImproperReply(r):
			return None
		
		self.ForthFunctions.append(d['Name'])
		
		return True
	
	def AddForthFunctions(self, funcs:list):
		if type(funcs) != list:
			return False
		
		self.UpdateAvailableFunctionsList()

		funcs = list(reversed([func for func in funcs]))

		while True:
			if len(funcs) == 0:
				break
			definedAtLeastOne = False
			for i in reversed(range(len(funcs))):
				func = funcs[i]
				ret = self.AddForthFunction(func)
				if ret is not True:
					print(func)
				if ret is False:
					return False
				if ret is True:
					funcs.pop(i)
					definedAtLeastOne = True
			
			if not definedAtLeastOne:
				print('Could not define some forth functions:')
				#for func in funcs:
				#	print(func)
				return False
		
		self.UpdateAvailableFunctionsList()
		return True
	
	def AddUserDefinedFunctions(self):
		if self.ActiveChip.UserDefinedForthFunctions is None:
			return True
		if self.AddForthFunctions([func['Definition'] for func in self.ActiveChip.UserDefinedForthFunctions]) != True:
			print('Warning: Some forth functions could not be added to the chip')
			return False
		return True
	
	def ReadRegister(self, reg=None, regName=None, regAddress=None):
		'''
		Reads the value of the desired register.
		
		@reg: if None, does nothing. Otherwise, it must be a Register type corresponding to the desired register
		@regName: if None, does nothing. Otherwise, it must be a str of the name of the desired register.
		@regAddress: if None, does nothing. Otherwise, it must be an int corresponding to the address of the desired register
		
		Returns: int (register value) or None (if unable to connect or unable to find register)
		'''
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		s = str(reg.Address) + ' @ h.'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil(' ', stripTerminator=True)
		if self.detectImproperReply(r):
			return None
		if len(r) != 8:
			return None
		currentValue = hexToUint(r)
		if currentValue is None:
			return None
		reg.CurrentValue = currentValue

		if len(reg.ValueHistory) == 0:
			reg.ValueHistory.append(currentValue)
			reg.ValueHistoryIndex = 0
		return currentValue
	
	def SetRegisterOnly(self, reg=None, regName=None, regAddress=None, value=None, addToHistory=True):
		'''
		Sets the desired register value without reading the register back
		
		@reg: if None, does nothing. Otherwise, it must be a Register type corresponding to the desired register
		@regName: if None, does nothing. Otherwise, it must be a str of the name of the desired register.
		@regAddress: if None, does nothing. Otherwise, it must be an int corresponding to the address of the desired register
		@value: int (the value to set the register to)
		
		Returns: bool (success) or None (if unable to connect)
		'''
		if self.uart.IsOpen != True:
			return None
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if type(value) != int:
			return None
		if (value < 0) or (value >= 4294967296):
			return None
		s = str(value) + ' ' + str(reg.Address) + ' !'
		if self.uart.WriteLine(s) is None:
			return None
		if addToHistory:
			if reg.ValueHistoryIndex < 0:
				reg.ValueHistory.append(value)
				reg.ValueHistoryIndex = 0
			elif (reg.ValueHistory[reg.ValueHistoryIndex] & reg.WriteCheckMask) != (value & reg.WriteCheckMask):
				reg.ValueHistoryIndex += 1
				reg.ValueHistory = reg.ValueHistory[:reg.ValueHistoryIndex] + [value]
				if reg.ValueHistoryIndex > (reg.ValueHistoryMaxSize - 1):
					reg.ValueHistory = reg.ValueHistory[-reg.ValueHistoryMaxSize:]
					reg.ValueHistoryIndex = reg.ValueHistoryMaxSize - 1
		return True
	
	def WriteRegister(self, reg=None, regName=None, regAddress=None, value=None, addToHistory=True):
		'''
		Sets the desired register value, reads the new value of the register back, and verifies that the rw bits have been updated correctly.
		
		@reg: if None, does nothing. Otherwise, it must be a Register type corresponding to the desired register
		@regName: if None, does nothing. Otherwise, it must be a str of the name of the desired register.
		@regAddress: if None, does nothing. Otherwise, it must be an int corresponding to the address of the desired register
		@value: int (the value to set the register to)
		
		Returns: int bool (success) or None (if unable to connect)
		'''
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushBuffers()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if type(value) != int:
			return None
		if (value < 0) or (value >= 4294967296):
			return None
		s = str(value) + ' ' + str(reg.Address) + ' ! ' + str(reg.Address) + ' @ h.'
		if self.uart.WriteLine(s) is None:
			return None
		# Read the hex string (8 bytes) + 1 space char
		r = self.uart.Read(9)
		if self.detectImproperReply(r):
			return None
		if r[-1] != ' ':
			return None
		currentValue = int(r[0:8], 16)
		reg.CurrentValue = currentValue
		if (reg.WriteCheckMask & (value ^ currentValue)) != 0:
				return False
		if addToHistory:
			if reg.ValueHistoryIndex < 0:
				reg.ValueHistory.append(value)
				reg.ValueHistoryIndex = 0
			elif (reg.ValueHistory[reg.ValueHistoryIndex] & reg.WriteCheckMask) != (value & reg.WriteCheckMask):
				reg.ValueHistoryIndex += 1
				reg.ValueHistory = reg.ValueHistory[:reg.ValueHistoryIndex] + [value]
				if reg.ValueHistoryIndex > (reg.ValueHistoryMaxSize - 1):
					reg.ValueHistory = reg.ValueHistory[-reg.ValueHistoryMaxSize:]
					reg.ValueHistoryIndex = reg.ValueHistoryMaxSize - 1
		r = self.uart.Read()
		return True
	
	def SetRegisterBit(self, reg=None, regName=None, regAddress=None, bitNum=None):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if type(bitNum) != int:
			return None
		if (bitNum < 0) or (bitNum >= reg.Size):
			return None
		
		# Preserve the values of write-to-clear registers
		clearMask = 0
		setMask = 0
		for bf in reg.BitFields:
			if 'w0' in bf.Accessibility and not (bf.LSB <= bitNum <= bf.MSB):
				for i in range(bf.LSB, bf.MSB + 1):
					setMask |= (1 << i)
			if 'w1' in bf.Accessibility and not (bf.LSB <= bitNum <= bf.MSB):
				for i in range(bf.LSB, bf.MSB + 1):
					clearMask |= (1 << i)
		clearMask ^= 0xFFFFFFFF
		
		# Modify the bit
		oldValue = self.ReadRegister(reg=reg)
		if type(oldValue) != int:
			return oldValue
		newValue = (oldValue | (0b1 << bitNum) | setMask) & clearMask
		
		return self.WriteRegister(reg=reg, value=newValue)
	
	def ClearRegisterBit(self, reg=None, regName=None, regAddress=None, bitNum=None):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if type(bitNum) != int:
			return None
		if (bitNum < 0) or (bitNum >= reg.Size):
			return None
		
		# Preserve the values of write-to-clear registers
		clearMask = 0
		setMask = 0
		for bf in reg.BitFields:
			if 'w0' in bf.Accessibility and not (bf.LSB <= bitNum <= bf.MSB):
				for i in range(bf.LSB, bf.MSB + 1):
					setMask |= (1 << i)
			if 'w1' in bf.Accessibility and not (bf.LSB <= bitNum <= bf.MSB):
				for i in range(bf.LSB, bf.MSB + 1):
					clearMask |= (1 << i)
		clearMask ^= 0xFFFFFFFF
		
		oldValue = self.ReadRegister(reg=reg)
		if type(oldValue) != int:
			return oldValue
		newValue = ((oldValue & (0xFFFFFFFF ^ (0b1 << bitNum))) | setMask) & clearMask
		
		return self.WriteRegister(reg=reg, value=newValue)
	
	def SetRegisterMask(self, reg=None, regName=None, regAddress=None, value=None, mask=None):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if type(value) != int:
			return None
		if (value < 0) or (value >= 4294967296):
			return None
		if type(mask) != int:
			return None
		if (mask < 0) or (mask >= 4294967296):
			return None
		
		oldValue = self.ReadRegister(reg=reg)
		if type(oldValue) != int:
			return oldValue
		newValue = (oldValue & (0xFFFFFFFF ^ mask)) | (value & mask)
		
		return self.WriteRegister(reg=reg, value=newValue)
	
	def UndoWriteRegister(self, reg=None, regName=None, regAddress=None):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if reg.ValueHistoryIndex <= 0:
			return True
		reg.ValueHistoryIndex -= 1
		return self.WriteRegister(reg=reg, value=reg.ValueHistory[reg.ValueHistoryIndex], addToHistory=False)
		
	def RedoWriteRegister(self, reg=None, regName=None, regAddress=None):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		if reg is None:
			reg = self.ActiveChip.GetRegister(name=regName, address=regAddress)
		if type(reg) != Register:
			return None
		if reg.ValueHistoryIndex + 1 >= len(reg.ValueHistory):
			return True
		reg.ValueHistoryIndex += 1
		return self.WriteRegister(reg=reg, value=reg.ValueHistory[reg.ValueHistoryIndex], addToHistory=False)
	
	def MeasureClockFrequency(self, desiredClock:str):
		if self.uart.IsOpen != True:
			return None
		self.uart.FlushReadBuffer()
		desiredClock = desiredClock.lower()
		if desiredClock == 'smclk':
			desiredClock = 0
		elif desiredClock == 'mclk':
			desiredClock = 1
		elif desiredClock == 'lfxt':
			desiredClock = 2
		elif desiredClock == 'hfxt':
			desiredClock = 3
		else:
			return None
		s = '0 ' + str(desiredClock) + ' clk .'
		if self.uart.WriteLine(s) is None:
			return None
		sleep(1000e-3 - 50e-3)
		r = self.uart.ReadUntil(' ', stripTerminator=True)
		if self.detectImproperReply(r):
			return None
		frequency = strToInt(r)
		if frequency is None:
			return None
		return frequency
	
	def ChangeBaudrateUsingHFXT(self, desiredBaudrate:int):
		if self.uart.IsOpen != True:
			return None
		
		if abs((self.uart.Baudrate - desiredBaudrate) / desiredBaudrate) < 0.025:
			return True
		
		# Get the current value of SMCLKSEL in SYSCLKCR
		SYSCLKCR = self.ActiveChip.GetRegister(name='SYSCLKCR')
		if SYSCLKCR is None:
			return None
		if type(self.ReadRegister(reg=SYSCLKCR)) != int:
			return None
		SMCLKSEL = SYSCLKCR.GetBitField('SMCLKSEL')
		if SMCLKSEL is None:
			return None
		SMCLKSEL_HFXT = SMCLKSEL.GetValueDescription('SMCLKSEL_HFXT')
		if SMCLKSEL_HFXT is None:
			return None
		
		# Get the baudrate control register
		UART0BR = self.ActiveChip.GetRegister(name='UART0BR')
		if UART0BR is None:
			return None
		
		# Get the desired value of SYSCLKCR
		newValueSYSCLKCR = SMCLKSEL.RegisterValueForBitFieldValue(SMCLKSEL_HFXT['Value'])
		
		# Get the frequency of HFXT
		frequency = self.MeasureClockFrequency('HFXT')
		if type(frequency) != int:
			return None
		
		if self.ActiveBootMode == 'ROM':
			if 6000000 <= frequency <= 6010000:
				frequency = 6000000
			elif 12000000 <= frequency <= 12020000:
				frequency = 12000000
			elif 24000000 <= frequency <= 24040000:
				frequency = 24000000
			elif 48000000 <= frequency <= 48080000:
				frequency = 48000000
		
		# Calculate new BCR and baudrate
		bcr = self.calcBcrRegister(frequency, desiredBaudrate)
		if not (0 <= bcr < 2**12):
			return None
		
		# Is the actual baudrate within 5% of the desired baudrate?
		actualBaudrate = self.calcBaudrate(frequency, bcr)
		if abs((actualBaudrate - desiredBaudrate) / desiredBaudrate) >= 0.05:
			return False
		
		# Send the command to the chip
		s = str(newValueSYSCLKCR) + ' ' + str(SYSCLKCR.Address) + ' ! ' + str(bcr) + ' ' + str(UART0BR.Address) + ' !'
		if self.uart.WriteLine(s) is None:
			return None
		sleep(150e-3)
		self.uart.Baudrate = desiredBaudrate
		#self.uart.Baudrate = actualBaudrate
		sleep(50e-3)
		self.uart.FlushBuffers()
		
		# Test the new baudrate
		if self.uart.WriteLine('0xBEEF . 36 emit') is None:
			return None
		if self.uart.ReadUntil('48879 $') is None:
			return False
		return True
	
	def EraseFlashPage(self, pageAddress:int):
		if self.uart.IsOpen != True:
			return None
		if pageAddress < 0:
			return None
		if pageAddress % 256 != 0:
			return None
		
		# Send the forth command
		s = '123 ' + str(pageAddress) + ' fe drop 0xBEEF .'	# Must include the "drop" command because fe pushes its success value to the TOS, which will overflow if not popped
		if self.uart.WriteLine(s) is None:
			return None
		
		if self.uart.ReadUntil('48879 ') is None:
			return False
		return True
	
	def EraseFlashMultiPage(self, pageAddress:int, numPages:int):
		if self.uart.IsOpen != True:
			return None
		if pageAddress < 0:
			return None
		if pageAddress % 256 != 0:
			return None
		if numPages < 1:
			return None
		if not self.ActiveChip.BootForthHasMultiPageFlashEraseCommand:
			return None
		#if 'fem' not in self.ForthFunctions:
		#	return None
		
		# Send the forth command
		s = '123 ' + str(numPages * 256) + ' ' + str(pageAddress) + ' fem drop 0xBEEF .'	# Must include the "drop" command because fe pushes its success value to the TOS, which will overflow if not popped
		if self.uart.WriteLine(s) is None:
			return None
		
		oldTimeout = self.uart.Timeout
		newTimeout = 30e3 * numPages
		self.uart.Timeout = newTimeout
		if self.uart.ReadUntil('48879 ') is None:
			self.uart.Timeout = oldTimeout
			return False
		self.uart.Timeout = oldTimeout
		return True
	
	def WriteFlashPage(self, pageAddress:int, binData:bytes):
		if self.uart.IsOpen != True:
			return None
		if pageAddress < 0:
			return None
		if pageAddress % 256 != 0:
			return None
		if len(binData) != 256:
			return None
		
		self.uart.FlushBuffers()
		
		# Compute the CRC of the payload using CRC16_CDMA2000
		calcCrc = compute_CRC16_CDMA2000(binData)
		
		# Send the forth command (use a binary payload)
		bin_payload = 1
		s = str(bin_payload) + ' ' + str(pageAddress) + ' fw' #+ ' 0xBEEF .'
		if self.uart.WriteLine(s) is None:
			return None
		if self.uart.ReadUntil('$') is None:	# Receive handshaking char
			return None
		
		# Send the payload
		self.uart.WriteBytes(binData)
		
		# Receive the CRC string
		crcStr = self.uart.Read(4)
		if crcStr is None:
			self.uart.Write('n')
			return None
		receivedCrc = hexToUint(crcStr)
		if receivedCrc is None:
			self.uart.Write('n')
			return None
		
		# Compare the CRC data
		if calcCrc != receivedCrc:
			# The CRC strings do not match
			self.uart.Write('n')
			return False
		
		# The CRC strings match
		self.uart.Write('Y')
		#if self.uart.ReadUntil('48879 ') is None:
		#	return False
		return True
	
	def WriteFlashCompressed(self, pageAddress:int, binData:bytes, maxCompressionRatio=0.95):
		if self.uart.IsOpen != True:
			return None
		if pageAddress < 0:
			return None
		if pageAddress % 256 != 0:
			return None
		if (len(binData) % 256) != 0:
			return None
		
		self.uart.FlushBuffers()
		
		# Compute the CRC of the payload using CRC16_CDMA2000
		calcCrc = compute_CRC16_CDMA2000(binData)

		# Compress the data
		l = LZW()
		compressedBinData = l.Compress(binData, maxbits=11)
		
		# If the compression ratio is not good enough, don't use it
		compressed_bytes = len(compressedBinData)
		uncompressed_bytes = len(binData)
		compressionRatio = compressed_bytes / uncompressed_bytes
		print('Compression ratio: {:.2f}%,'.format(compressionRatio * 100), 'Total compressed bytes =', compressed_bytes)
		print('CRC =', hex(calcCrc))
		if compressionRatio > maxCompressionRatio:
			return False

		# Send the forth command
		s = str(uncompressed_bytes) + ' ' + str(compressed_bytes) + ' ' + str(pageAddress) + ' fwc' #+ ' 0xBEEF .'
		if self.uart.WriteLine(s) is None:
			return None

		# Send each compressed packet when the forth interpreter asks for it (when a '$' is received)
		self.uart.Timeout = 60
		for i in range(0, compressed_bytes, 256):
			# Receive handshaking char, indicating the forth interpreter is ready to receive the next compressed packet
			ret = self.uart.Read(1)
			if ret is None:
				return None
			if ret != '$':
				print('Got a', ret)
				others = self.uart.ReadLine()
				print('Actually got', ret + others)
				return False
			print('Sending compressed packet i =', i)
			# Send the next compressed packet
			end_index = i + 256
			if i + 256 > compressed_bytes:
				end_index = compressed_bytes - i
			compressedBinPacket = compressedBinData[i:end_index]
			self.uart.WriteBytes(compressedBinPacket)
		
		# Receive the CRC string
		c = self.uart.Read(1)
		if c is None or c == '$':
			print('c =', c)
			return None
		crcStr = c + self.uart.Read(3)
		if crcStr is None:
			return None
		receivedCrc = hexToUint(crcStr)
		if receivedCrc is None:
			return None
		
		# Compare the CRC data
		if calcCrc != receivedCrc:
			# The CRC strings do not match
			print('Received CRC: 0x' + crcStr)
			return False
		
		# The CRC strings match
		#if self.uart.ReadUntil('48879 ') is None:
		#	return False
		return True
	
	def ReadFlash(self, startAddress:int, length:int):
		if self.uart.IsOpen != True:
			return None
		if startAddress < 0:
			return None
		if length <= 0:
			return b''
		
		self.uart.FlushBuffers()
		
		# Send the forth command (use a binary payload)
		s = '1 ' + str(length) + ' ' + str(startAddress) + ' fr 0xBEEF .'
		if self.uart.WriteLine(s) is None:
			return None
		
		# Receive the payload
		oldTimeout = self.uart.Timeout
		#self.uart.Timeout = 1.2 * (length + 8) * 10 / self.uart.Baudrate
		self.uart.Timeout = 4
		r = self.uart.ReadBytes(length)
		self.uart.Timeout = oldTimeout
		if r is None:
			print('here')
			return None
		
		if self.uart.ReadUntil('48879 ') is None:
			return False
		return r
	
	def ReadMemoryBlock(self, startAddress:int, length:int, compress=False, swapBytes=False, createIfNotDefined:bool=True):
		if self.uart.IsOpen != True:
			return None
		if startAddress < 0:
			return None
		if length <= 0:
			return b''
		if length >= 65536:
			return None
		if swapBytes and ((length % 4) != 0):
			return None
		
		self.uart.FlushBuffers()

		# Does this forth interpreter have the mr (memory read) command?
		if 'mr' not in self.ForthFunctions:
			# This forth interpreter does NOT have a memory erase command
			if not createIfNotDefined:
				return False
			
			# Remove the previous arguments from the stack
			if self.uart.WriteLine('3 drop 0x7C .') is None:
				return None
			r = self.uart.ReadUntil('124')
			if r is None:
				return None
			
			# So send it a little forth program to do so
			# ut ( bin_byte -- ) // transmits a byte over the UART (in the LSbyte)
			#ut_cmd = ' begin UART0SR @ 0x40 & not until UART0TX ! '.replace('UART0SR', str(self.ActiveChip.GetRegister(name='UART0SR').Address)).replace('UART0TX', str(self.ActiveChip.GetRegister(name='UART0TX').Address))
			# crcs ( -- )	// Sets up the CRC calculator
			crcs_cmd = ' 0xFFFF CRCSTATE ! '.replace('CRCSTATE', str(self.ActiveChip.GetRegister(name='CRCSTATE').Address))
			# crca ( bin_byte -- ) // Adds a byte to the CRC calculator
			crca_cmd = ' CRCDATA ! '.replace('CRCDATA', str(self.ActiveChip.GetRegister(name='CRCDATA').Address))
			# crcr ( -- crc_state) // Pushes the CRC state to the TOS
			crcr_cmd = ' CRCSTATE @ dup emit 8 srl emit '.replace('CRCSTATE', str(self.ActiveChip.GetRegister(name='CRCSTATE').Address))
			# mr ( mode length start_address -- )
			mr_cmd = ': mr 2 roll 1 == if crcs tuck + swap do i @ i 3 & 8 * swap drop srl dup crca emit loop crcr else drop drop 0 0 emit emit then ;'.replace(' crcs ', crcs_cmd).replace(' crca ', crca_cmd).replace(' crcr ', crcr_cmd)

			oldTimeout = self.uart.Timeout
			#self.uart.Timeout = 1.2 * (len(mr_cmd) + 8) * 10 / self.uart.Baudrate
			self.uart.Timeout = 1

			if self.uart.WriteLine(mr_cmd + ' 0x7B .') is None:
				return None
			r = self.uart.ReadUntil('123')
			if r is None:
				return None
			if '?' in r:
				return None
			self.uart.Timeout = oldTimeout

			self.UpdateAvailableFunctionsList()

		self.uart.FlushBuffers()
		#oldTimeout = self.uart.Timeout
		#self.uart.Timeout = 1.5 * length * 10 / self.uart.Baudrate
		
		# Send the forth command
		mode = '1'	# Binary payload (not compressed)
		if compress:
			mode = '2'	# Binary compressed payload
		s = mode + ' ' + str(length) + ' ' + str(startAddress) + ' mr'
		if self.uart.WriteLine(s) is None:
			return None
		
		# Get the length of the payload
		receiveLength = length
		if compress:
			r = self.uart.ReadBytes(2)
			if r is None:
				return None
			compressedLength = r[0] + (r[1] << 8)
			if compressedLength == 0:
				return None
			receiveLength = compressedLength
		
		# Receive the payload
		payload = self.uart.ReadBytes(receiveLength)
		if payload is None:
			print(self.uart.ReadBytes())
			return None
		
		# Receive the CRC
		receivedCrc = self.uart.ReadBytes(2)
		if receivedCrc is None:
			return None
		receivedCrc = receivedCrc[0] + (receivedCrc[1] << 8)
		
		# Decompress the payload
		if compress:
			l = LZW()
			payload = l.Decompress(payload)
		
		if len(payload) != length:
			return False
		
		# Compare the CRCs
		calcCrc = compute_CRC16_CDMA2000(payload)
		if receivedCrc != calcCrc:
			print('Bad CRC. Expected', hex(calcCrc), 'but got', hex(receivedCrc))
			return False
		
		# Optionally swap the bytes around
		if swapBytes:
			payload = swapWordBytesInArray(payload)
		
		#self.Timeout = oldTimeout
		return payload
	
	def EraseMemoryBlock(self, startAddress:int, length:int, createIfNotDefined:bool=True):
		if self.uart.IsOpen != True:
			return None
		if startAddress < 0:
			return None
		if startAddress % 4 != 0:
			return None
		if length % 4 != 0:
			return None
		if length <= 0:
			return True
		
		self.uart.FlushBuffers()
		
		# Does this forth interpreter have the me (memory erase) command?
		if 'me' not in self.ForthFunctions:
			# This forth interpreter does NOT have a memory erase command
			if not createIfNotDefined:
				return False
			
			# Remove the previous arguments from the stack
			if self.uart.WriteLine('2 drop 0x7C .') is None:
				return None
			r = self.uart.ReadUntil('124')
			if r is None:
				return None
			
			# So send it a little forth program to do so
			# me ( length start_address -- )
			me_cmd = ': me tuck + swap do 0 i ! loop ;'
			oldTimeout = self.uart.Timeout
			self.uart.Timeout = 1

			if self.uart.WriteLine(me_cmd + ' 0x7C .') is None:
				return None
			r = self.uart.ReadUntil('124')
			if r is None:
				return None
			if '?' in r:
				return None
			self.uart.Timeout = oldTimeout
		
		self.uart.FlushBuffers()

		# Send the forth command
		s = str(length) + ' ' + str(startAddress) + ' me 0x7D .'
		if self.uart.WriteLine(s) is None:
			return None

		# Receive the "done" reply
		if self.uart.ReadUntil('125') is None:
			return None
		
		return True
	
	def MemorySetBlock(self, startAddress:int, length:int, setByte:int, createIfNotDefined:bool=True):
		if self.uart.IsOpen != True:
			return None
		if startAddress < 0:
			return None
		if type(setByte) != int or setByte < 0 or setByte >= 256:
			return None
		if length <= 0:
			return True
		
		self.uart.FlushBuffers()
		
		# Does this forth interpreter have the ms (memory set) command?
		if 'ms' not in self.ForthFunctions:
			# This forth interpreter does NOT have a memory set command
			if not createIfNotDefined:
				return False
			
			# Remove the previous arguments from the stack
			if self.uart.WriteLine('3 drop 0x7C .') is None:
				return None
			r = self.uart.ReadUntil('124')
			if r is None:
				return None

			# Send it a little forth program to do so
			# ms ( set_byte length start_address -- )
			#ms_cmd = ': ms tuck + swap do dup i ! loop drop ;'
			ms_cmd = ': ms tuck + swap do dup i 3 & 3 sll tuck sll swap 255 swap sll swap i mask loop drop ;'
			oldTimeout = self.uart.Timeout
			self.uart.Timeout = 1

			if self.uart.WriteLine(ms_cmd + ' 0x7C .') is None:
				return None
			r = self.uart.ReadUntil('124')
			if r is None:
				return None
			if '?' in r:
				return None
			self.uart.Timeout = oldTimeout
		
		self.uart.FlushBuffers()

		# Send the forth command
		oldTimeout = self.uart.Timeout
		self.uart.Timeout *= 2
		s = str(setByte) + ' ' + str(length) + ' ' + str(startAddress) + ' ms 0x7D .'
		print(s)
		if self.uart.WriteLine(s) is None:
			return None

		# Receive the "done" reply
		if self.uart.ReadUntil('125') is None:
			return 
		
		self.uart.Timeout = oldTimeout
		
		return True
	
	def ListDirectory(self, path:str):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveBootMode != 'SpiFlash':
			return None
		
		self.uart.FlushBuffers()
		
		path = path.replace('\\', '/').upper()
		while '//' in path:
			path = path.replace('//', '/')
		if len(path) > 100:
			return None
		
		s = 'ls'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('$')
		if self.detectImproperReply(r):
			return None
		
		if self.uart.WriteLine(path) is None:
			return None
		r = self.uart.ReadLine()
		if r is None:
			return None
		if r[0] == '?':
			return None
		
		s = r.split('|')
		
		d = {'Path': path, 'Files': [], 'Subdirectories': [], 'CapacityBytes': None, 'FreeBytes': None}
		
		for fileinfo in s:
			if len(fileinfo) <= 0:
				continue
			if fileinfo[0] == '\n':
				continue
			fsplit = fileinfo.split(':')
			if len(fsplit) != 3:
				return None
			
			objectType = None
			if fsplit[0] == 'F':
				d['Files'].append({'Type': 'file', 'Name': fsplit[1], 'Path': (path + '/' + fsplit[1]).replace('//', '/'), 'SizeBytes': strToInt(fsplit[2].strip())})
			elif fsplit[0] == 'D':
				d['Subdirectories'].append({'Type': 'directory', 'Name': fsplit[1], 'Path': (path + '/' + fsplit[1]).replace('//', '/')})
			elif fsplit[0] == 'M':
				d['CapacityBytes'] = strToInt(fsplit[1].strip())
				d['FreeBytes'] = strToInt(fsplit[2].strip())
		
		return d
	
	def MakeDirectory(self, path:str):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveBootMode != 'SpiFlash':
			return None
		
		self.uart.FlushBuffers()
		
		path = path.replace('\\', '/')
		while '//' in path:
			path = path.replace('//', '/')
		if len(path) > 100:
			return None
		
		s = 'mkdir'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('$')
		if self.detectImproperReply(r):
			return None
		
		if self.uart.WriteLine(path) is None:
			return None
		oldTimeout = self.uart.Timeout
		self.uart.Timeout = 2
		r = self.uart.ReadLine()
		self.uart.Timeout = oldTimeout
		if self.detectImproperReply(r):
			return None
		
		return True
	
	def DeleteFileOrDirectory(self, path:str):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveBootMode != 'SpiFlash':
			return None
		
		self.uart.FlushBuffers()
		
		path = path.replace('\\', '/')
		while '//' in path:
			path = path.replace('//', '/')
		if len(path) > 100:
			return None
		
		s = 'rm'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('$')
		if self.detectImproperReply(r):
			return None
		
		if self.uart.WriteLine(path) is None:
			return None
		r = self.uart.ReadLine()
		if self.detectImproperReply(r):
			return None
		
		return True
	
	def DeleteRecursive(self, path:str):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveBootMode != 'SpiFlash':
			return None
		
		path = path.replace('\\', '/')
		while '//' in path:
			path = path.replace('//', '/')
		if len(path) > 100:
			return None
			
		# Assume the path points to a directory. Try to get its contents
		contents = self.ListDirectory(path)
		
		if contents is None:
			# This is a file or an invalid path
			return self.DeleteFileOrDirectory(path)
		
		# The path points to a directory. Delete all subdirectories and files
		for obj in contents['Files'] + contents['Subdirectories']:
			subPath = path + '/' + obj['Name']
			ret = self.DeleteRecursive(subPath)
			if ret != True:
				return ret
			
		# Delete the directory itself
		return self.DeleteFileOrDirectory(path)
	
	def DownloadFile(self, path:str, returnAsString:bool=False):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveBootMode != 'SpiFlash':
			return None
		
		self.uart.FlushBuffers()
		
		path = path.replace('\\', '/')
		while '//' in path:
			path = path.replace('//', '/')
		if len(path) > 100:
			return None
		
		s = 'df'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('$')
		if self.detectImproperReply(r):
			return None
		
		if self.uart.WriteLine(path) is None:
			return None
		r = self.uart.ReadUntil(' ')
		if self.detectImproperReply(r):
			return None
		fileSize = None
		try:
			fileSize = int(r)
		except:
			return None
		binData = self.uart.ReadBytes(fileSize)
		if type(binData) != bytes:
			return None
		
		crcStr = self.uart.Read(4)
		if crcStr is None:
			return None
		receivedCrc = hexToUint(crcStr)
		if receivedCrc is None:
			return None
		calcCrc = compute_CRC16_CDMA2000(binData)
		if calcCrc != receivedCrc:
			# The CRCs do not match
			return None
		
		if self.uart.ReadLine() is None:
			return None
		
		if returnAsString:
			return binData.encode(self.uart.Encoding)
		
		return binData
	
	def UploadFile(self, path:str, data):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveBootMode != 'SpiFlash':
			return None
		
		if not (type(data) == str or type(data) == bytes):
			return None
		
		self.uart.FlushBuffers()
		
		path = path.replace('\\', '/')
		while '//' in path:
			path = path.replace('//', '/')
		if len(path) > 100:
			return None
		
		s = str(len(data)) + ' uf'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('$')
		if self.detectImproperReply(r):
			return None
		
		if self.uart.WriteLine(path) is None:
			return None
		r = self.uart.Peek(1)
		if r != '$':
			return None
		
		for i in range(0, len(data), 256):
			r = self.uart.ReadUntil('$')
			if self.detectImproperReply(r):
				return None
			
			endIndex = i + 256
			if endIndex > len(data):
				endIndex = len(data)
			
			ret = self.uart.Write(data[i:endIndex])
			if type(ret) != int or ret != (endIndex - i):
				return None
		
		crcStr = self.uart.Read(4)
		if crcStr is None:
			return None
		receivedCrc = hexToUint(crcStr)
		if receivedCrc is None:
			return None
		calcCrc = compute_CRC16_CDMA2000(data)
		if calcCrc != receivedCrc:
			# The CRCs do not match
			return False
		
		if self.uart.ReadLine() is None:
			return None
		
		return True
	
	def EnablePhaDma(self, afeIndex:int):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		
		# Get the current value of the register with the "Enable DMA" bit
		originalValue = self.ReadRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister)
		if originalValue is None:
			return None

		# Set the enable bit
		newValue = originalValue | (0b1 << self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaBitNum)
		if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=newValue, addToHistory=False) != True:
			return None
		
		return originalValue
	
	def DisablePhaDma(self, afeIndex:int):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		
		# Get the current value of the register with the "Enable DMA" bit
		originalValue = self.ReadRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister)
		if originalValue is None:
			return None

		# Clear the enable bit
		newValue = originalValue & ~(0b1 << self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaBitNum)
		if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=newValue, addToHistory=False) != True:
			return None
		
		return originalValue
	
	def EnablePsdDma(self, afeIndex:int):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		
		# Get the current value of the register with the "Enable DMA" bit
		originalValue = self.ReadRegister(reg=self.ActiveChip.AFEs[afeIndex].PsdDma.EnableDmaRegister)
		if originalValue is None:
			return None

		# Set the enable bit
		newValue = originalValue | (0b1 << self.ActiveChip.AFEs[afeIndex].PsdDma.EnableDmaBitNum)
		if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PsdDma.EnableDmaRegister, value=newValue, addToHistory=False) != True:
			return None
		
		return originalValue
	
	def DisablePsdDma(self, afeIndex:int):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		
		# Get the current value of the register with the "Enable DMA" bit
		originalValue = self.ReadRegister(reg=self.ActiveChip.AFEs[afeIndex].PsdDma.EnableDmaRegister)
		if originalValue is None:
			return None

		# Clear the enable bit
		newValue = originalValue & ~(0b1 << self.ActiveChip.AFEs[afeIndex].PsdDma.EnableDmaBitNum)
		if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PsdDma.EnableDmaRegister, value=newValue, addToHistory=False) != True:
			return None
		
		return originalValue
	
	def GetHistogram(self, afeIndex:int, accumulate=False):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		
		afe = self.ActiveChip.AFEs[afeIndex]
		#self.uart.FlushBuffers()
		'''
		# Disable the DMA if necessary
		if afe.PhaDma.DisableDmaToAccess:
			originalValue = self.DisablePhaDma(afeIndex)
			if originalValue is None:
				return None
		
		# Send the memory read command
		bdata = self.ReadMemoryBlock(afe.PhaDma.StartAddress, afe.NumBins * afe.PhaDma.BytesPerBin, swapBytes=(not afe.PhaDma.WordBytesReversed))
		if bdata is None or len(bdata) != (afe.NumBins * afe.PhaDma.BytesPerBin):
			return None
		
		# Re-enable the DMA if necessary
		if afe.PhaDma.DisableDmaToAccess:
			if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
				return None
		
		# Parse the data into a histogram
		counts = [0 for i in range(afe.NumBins)]
		for i in range(afe.NumBins):
			# Assumes bdata is ordered in LSbyte first order
			for j in range(afe.PhaDma.BytesPerBin):
				counts[i] += bdata[(i * afe.PhaDma.BytesPerBin) + j] << (j * 8)
		'''
		
		# Send the forth command
		s = str(afeIndex) + ' pha'
		if self.uart.WriteLine(s) is None:
			return None

		# Receive the payload
		bytesToReceive = afe.NumBins * afe.PhaDma.BytesPerBin
		payload = self.uart.ReadBytes(bytesToReceive)
		if payload is None:
			return None

		# Receive the CRC
		receivedCrc = self.uart.ReadBytes(2)
		if receivedCrc is None:
			return None
		receivedCrc = receivedCrc[0] + (receivedCrc[1] << 8)

		# Compare the CRCs
		calcCrc = compute_CRC16_CDMA2000(payload)
		if receivedCrc != calcCrc:
			print(payload)
			print('Bad CRC. Expected', hex(calcCrc), 'but got', hex(receivedCrc))
			return False
		
		# Optionally swap the bytes around
		swapBytes = not afe.PhaDma.WordBytesReversed
		if swapBytes:
			payload = swapWordBytesInArray(payload)
		
		if payload is None or len(payload) != (bytesToReceive):
			return None
		
		# Parse the data into a histogram
		counts = [0 for i in range(afe.NumBins)]
		for i in range(afe.NumBins):
			# Assumes payload is ordered in LSbyte first order
			for j in range(afe.PhaDma.BytesPerBin):
				counts[i] += payload[(i * afe.PhaDma.BytesPerBin) + j] << (j * 8)
		
		# Set the new histogram
		if accumulate:
			afe.Histogram.SetCounts([x + y for x, y in zip(afe.Histogram.Counts, counts)])
		else:
			afe.Histogram.SetCounts(counts)
		
		return afe.Histogram

	def ClearHistogram(self, afeIndex:int, clearComputerHistogram:bool=True):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		self.uart.FlushBuffers()
		afe = self.ActiveChip.AFEs[afeIndex]

		'''
		# Disable the DMA if necessary
		if afe.PhaDma.DisableDmaToAccess:
			originalValue = self.DisablePhaDma(afeIndex)
			if originalValue is None:
				return None
		
		# Send the memory set command
		if self.MemorySetBlock(afe.PhaDma.StartAddress, afe.NumBins * afe.PhaDma.BytesPerBin, 0, createIfNotDefined=True) != True:
			return None
		#elif self.ActiveChip.BootForthHasMemoryEraseCommand:
		#	if self.EraseMemoryBlock(afe.PhaDma.StartAddress, afe.NumBins * afe.PhaDma.BytesPerBin, createIfNotDefined=True) != True:
		#		return None
		
		# Re-enable the DMA if necessary
		if afe.PhaDma.DisableDmaToAccess:
			if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
				return None
		'''
		if 'ClearPha' not in self.ForthFunctions:
			return None
		
		# Send the forth command
		s = str(afeIndex) + ' ClearPha ' + str(ord('!')) + ' emit'
		if self.uart.WriteLine(s) is None:
			return None

		# Get the "done" reply
		r = self.uart.ReadUntil('!')
		if r is None:
			return None
		
		# Clear the computer's internal histogram data
		if clearComputerHistogram:
			afe.Histogram.ClearCounts()

		return True
	
	def RunNpuIsotopeID(self, afeIndex:int):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		
		afe = self.ActiveChip.AFEs[afeIndex]

		# Disable the DMA if necessary
		if afe.PhaDma.DisableDmaToAccess:
			originalValue = self.DisablePhaDma(afeIndex)
			if originalValue is None:
				return None
		
		# Send the mlp command
		s = str(afeIndex) + ' mlp'
		if self.uart.WriteLine(s) is None:
			return None
		
		# If successful, the mlp function prints a string containing the isotope names separated by spaces and followed by a '$' char
		# Does the forth interpreter have this command?
		isotopesStr = self.uart.ReadUntil('$', stripTerminator=True)
		if self.detectImproperReply(isotopesStr):
			# There is still the afeIndex on the stack, drop it
			if self.uart.WriteLine('drop 36 emit') is None:
				return None
			r = self.uart.ReadUntil('$')
			if self.detectImproperReply(r):
				return None
			
			# Re-enable the DMA if necessary
			self.uart.FlushBuffers()
			if afe.PhaDma.DisableDmaToAccess:
				if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
					return None
			return False
		
		# Did the command execute properly on the chip?
		if self.uart.WriteLine('.') is None:
			return None
		r = self.uart.ReadUntil(' ')
		if self.detectImproperReply(r):
			return None
		errorNum = strToInt(r)
		if errorNum is None:
			return None
		if errorNum != 0:
			# The mlp command was not executed properly. Perhaps MLPNN.BIN is not present on the chip?
			# Re-enable the DMA if necessary
			self.uart.FlushBuffers()
			if afe.PhaDma.DisableDmaToAccess:
				if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
					return None
			return False
		
		# The command executed properly. Get the number of outputs
		if self.uart.WriteLine('.') is None:
			return None
		r = self.uart.ReadUntil(' ')
		if self.detectImproperReply(r):
			return None
		numOutputs = strToInt(r)
		if type(numOutputs) != int:
			return None
		if not (0 < numOutputs <= 256):
			# Re-enable the DMA if necessary
			if afe.PhaDma.DisableDmaToAccess:
				if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
					return None
			return False
		
		# Get the outputs
		outputs = [None for i in range(numOutputs)]
		s = '. . ' * numOutputs
		s += '36 emit'
		if self.uart.WriteLine(s) is None:
			return None
		r = self.uart.ReadUntil('$', stripTerminator=True)
		if self.detectImproperReply(r):
			return None
		resultStrings = r.strip().split(' ')
		for i in range(numOutputs):
			present = bool(int(resultStrings[(i * 2) + 0]))
			output = int(resultStrings[(i * 2) + 1])
			outputs[i] = (present, output)
		outputs = outputs[::-1]

		# Parse the isotopes string
		isotopes = isotopesStr.strip().split(' ')
		if len(isotopes) != len(outputs):
			# Re-enable the DMA if necessary
			if afe.PhaDma.DisableDmaToAccess:
				if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
					return None
			return False
		
		# Create a dictionary of the isotopes with their associated presence state and output value
		d = {}
		for i, iso in enumerate(isotopes):
			d[iso] = {'Present': outputs[i][0], 'NpuOutput': outputs[i][1]}

		# Re-enable the DMA if necessary
		if afe.PhaDma.DisableDmaToAccess:
			if self.WriteRegister(reg=self.ActiveChip.AFEs[afeIndex].PhaDma.EnableDmaRegister, value=originalValue, addToHistory=False) != True:
				return None

		return d
	
	def SetDpsAValue(self, dpsIndex:int, a:int):
		if self.uart.IsOpen != True:
			return None
		
		if type(a) != int or (not (0 <= a < 2048)):
			return None
		
		if type(dpsIndex) != int or (not (0 <= dpsIndex <= 1)):
			return None

		# Send the command
		oldTimeout = self.uart.Timeout
		self.uart.Timeout = 1
		if self.uart.WriteLine(str(dpsIndex) + ' ' + str(a) + ' setA 0x7B .') is None:
			return None
		
		# Get the reply
		r = self.uart.ReadUntil('123')
		self.uart.Timeout = oldTimeout
		if self.detectImproperReply(r):
			return False
		
		return True
	
	def StartTimedHist(self, afeIndex:int, duration):
		if self.uart.IsOpen != True:
			return None
		
		if type(afeIndex) != int or (not (0 <= afeIndex < len(self.ActiveChip.AFEs))):
			return None

		if type(duration) != int or duration < 1:
			return None

		# Send the command
		if self.uart.WriteLine(str(duration) + ' ' + str(afeIndex) + ' timedHist') is None:
			return None
		
		return True
	
	def GetPsdData(self, afeIndex:int):
		#AfeBase_cmd = ': AfeBase 8 sll 0x5000 + ;'	# ( afeIndex -- afeBaseAddress )
		#AFExCR0_cmd = ': AFExCR0 AfeBase 0 + ;'		# ( afeIndex -- (AFExCR0 address for afeIndex))
		#AFExCR1_cmd = ': AFExCR1 AfeBase 4 + ;'		# ( afeIndex -- (AFExCR1 address for afeIndex))
		#AFExSR_cmd = ': AFExSR AfeBase 8 + ;'		# ( afeIndex -- (AFExSR address for afeIndex))
		#DisDma_cmd = ': DisDma dup AFExCR1 @ 0x200000 & not not swap AFExCR1 21 swap cbi ;'	# ( afeIndex -- (boolean: true if EnDma was enabled before DisDma, false otherwise))
		#EnDmaIf_cmd = ': EnDmaIf if AFExCR1 21 swap sbi else drop then ;'	# ( afeIndex enable -- ))
		#ClearPsdFull_cmd = ': ClearPsdFull AFExSR 1 swap ! ;'	# ( afeIndex -- )
		#PsdRamAddr_cmd = ': PsdRamAddr 12 sll 0x21000 + ;'	# ( afeIndex -- (PsdRamAddress for afeIndex))
		#psd_cmd = ': psd dup dup DisDma swap dup PsdRamAddr 1 swap 4096 swap mr swap EnDmaIf ClearPsdFull ;'

		#for cmd in [AfeBase_cmd, AFExCR0_cmd, AFExCR1_cmd, AFExSR_cmd, DisDma_cmd, EnDmaIf_cmd, ClearPsdFull_cmd, PsdRamAddr_cmd, psd_cmd]:
		#	name = cmd.split(' ')[1]
		#	if name in self.ForthFunctions:
		#		continue
		#	# Add the command
		#	if self.uart.WriteLine(cmd + ' 0x7B .') is None:
		#		return None
		#	r = self.uart.ReadUntil('123')
		#	if self.detectImproperReply(r):
		#		return None
		#	self.UpdateAvailableFunctionsList()
		
		afe = self.ActiveChip.AFEs[afeIndex]

		# Send the forth command
		self.uart.FlushBuffers()
		s = str(afeIndex) + ' psd'
		if self.uart.WriteLine(s) is None:
			return None
		
		# Get the confirmation (is the PSD data full or not?)
		r = self.uart.Read(1)
		if r != 'G':
			print('PSD data not full. Reply:', r)
			return None
		
		# Get the payload
		numDataPoints = 2**afe.AdcBits
		bytesPerDataPoint = 4
		payload = self.uart.ReadBytes(numbytes=(bytesPerDataPoint * numDataPoints))
		if payload is None:
			return None
		
		# Get the CRC
		receivedCrc = self.uart.ReadBytes(2)
		if receivedCrc is None:
			return None
		receivedCrc = receivedCrc[0] + (receivedCrc[1] << 8)
		
		## Read the suffix
		#re = self.uart.ReadUntil('!')
		#if self.detectImproperReply(re):
		#	return None
		
		# Compare the CRCs
		calcCrc = compute_CRC16_CDMA2000(payload)
		if receivedCrc != calcCrc:
			print('Bad CRC. Expected', hex(calcCrc), 'but got', hex(receivedCrc))
			return False
		
		# Parse the payload
		mask = 2**afe.AdcBits - 1
		if self.ActiveChip.Name == 'teewinot':
			psdData = [None for i in range(len(payload) // 4)]
			# Each data point contains 4 bytes
			for i in range(len(payload) // 4):
				point = payload[i*4:(i*4) + 4]
				early = (point[0] | (point[1] << 8)) & mask
				late = (point[2] | (point[3] << 8)) & mask
				psdData[i] = [early, late]
		else:
			psdData = []	# format: [[early, late, full], ...]
			for i in range(numDataPoints):
				dataPoint = (payload[3 + i*4] << 24) | (payload[2 + i*4] << 16) | (payload[1 + i*4] << 8) | payload[i*4]	# extracted 32-bit value
				# Format for 32-bit value: (MSB) 2-bit "valid" sequence "10", 10-bit full window, 10-bit late window, 10-bit early window (LSB)
				validSequence = dataPoint >> 30
				if validSequence == 0b10:
					early = dataPoint & mask
					late = (dataPoint >> 10) & mask
					full = (dataPoint >> 20) & mask
					psdData.append([early, late, full])
		
		# Add to the PSD channel
		afe.Psd.AppendPsdDataPoints(psdData)
		
		return psdData

	def ClearPsdData(self, afeIndex:int, clearComputerPsdData:bool=True):
		if self.uart.IsOpen != True:
			return None
		if self.ActiveChip.AFEs is None or len(self.ActiveChip.AFEs) <= afeIndex or afeIndex < 0:
			return None
		self.uart.FlushBuffers()
		afe = self.ActiveChip.AFEs[afeIndex]
		
		if 'ClearPsd' not in self.ForthFunctions:
			return None
		
		# Send the forth command
		s = str(afeIndex) + ' ClearPsd ' + str(ord('!')) + ' emit'
		if self.uart.WriteLine(s) is None:
			return None

		# Get the "done" reply
		r = self.uart.ReadUntil('!')
		if r is None:
			return None
		
		# Clear the computer's internal histogram data
		if clearComputerPsdData:
			afe.Psd.ClearPsdData()

		return True
		



		

	def HasResetPin(self):
		return ((self.ActiveBoard.FtdiAssertReset is not None) and (self.ActiveBoard.FtdiDeassertReset is not None)) or self.ActiveBoard.FtdiUseRtsDtrSequencing
	
	def HasBootSelectPin(self):
		return ((self.ActiveBoard.FtdiBootRom is not None) and (self.ActiveBoard.FtdiBootSpiFlash is not None)) or self.ActiveBoard.FtdiUseRtsDtrSequencing
	
	def AssertReset(self):
		'''
		Asserts the reset pin on the chip through one of the FTDI pins, if there is hardware support
		'''
		if self.ActiveBoard.FtdiUseRtsDtrSequencing:
			return self.SendDtrRtsSequence(1)
		else:
			return self.setFtdiPin(self.ActiveBoard.FtdiAssertReset)
	
	def DeassertReset(self):
		'''
		Deasserts the reset pin on the chip (takes the chip out of reset) through one of the FTDI pins, if there is hardware support
		'''
		if self.ActiveBoard.FtdiUseRtsDtrSequencing:
			return self.SendDtrRtsSequence(2)
		else:
			return self.setFtdiPin(self.ActiveBoard.FtdiDeassertReset)
	
	def SetBootToRom(self):
		'''
		Sets the BOOT pin on the chip to ROM mode through one of the FTDI pins, if there is hardware support
		'''
		if self.ActiveBoard.FtdiUseRtsDtrSequencing:
			return self.SendDtrRtsSequence(3)
		else:
			return self.setFtdiPin(self.ActiveBoard.FtdiBootRom)
	
	def SetBootToSpiFlash(self):
		'''
		Sets the BOOT pin on the chip to SPI Flash mode through one of the FTDI pins, if there is hardware support
		'''
		if self.ActiveBoard.FtdiUseRtsDtrSequencing:
			return self.SendDtrRtsSequence(4)
		else:
			return self.setFtdiPin(self.ActiveBoard.FtdiBootSpiFlash)
	
	def ResetChip(self, bootToForth=False):
		if self.ActiveBoard.FtdiUseRtsDtrSequencing:
			rtsAsserted = 0
			rtsDeasserted = 1
			if self.ActiveBoard.InvertRts:
				rtsAsserted = 1
				rtsDeasserted = 0
			dtrAsserted = 0
			dtrDeasserted = 1
			if self.ActiveBoard.InvertDtr:
				dtrAsserted = 1
				dtrDeasserted = 0
			
			# Initialize RTS and DTR pins
			self.uart.SetFtdiPin('rts', rtsDeasserted)
			self.uart.SetFtdiPin('dtr', dtrDeasserted)
			
			# Reset into desired boot mode
			if bootToForth:
				self.uart.SetFtdiPin('dtr', dtrAsserted)
			else:
				self.uart.SetFtdiPin('rts', rtsAsserted)
			sleep(20e-3)
			
			# Return RTS and DTR pins to deasserted state
			self.uart.SetFtdiPin('rts', rtsDeasserted)
			self.uart.SetFtdiPin('dtr', dtrDeasserted)
		else:
			self.AssertReset()
			if bootToForth:
				self.SetBootToRom()
			self.DeassertReset()
			self.SetBootToSpiFlash()
		
		return
	
	def SendDtrRtsSequence(self, numPulses):
		rtsAsserted = 1
		rtsDeasserted = 0
		if self.ActiveBoard.InvertRts:
			rtsAsserted = 0
			rtsDeasserted = 1
		dtrAsserted = 1
		dtrDeasserted = 0
		if self.ActiveBoard.InvertDtr:
			dtrAsserted = 0
			dtrDeasserted = 1
		
		delayTime = 6e-3
		
		# Initialize by deasserting both RTS and DTR
		self.uart.SetFtdiPin('rts', rtsDeasserted)
		self.uart.SetFtdiPin('dtr', dtrDeasserted)
		sleep(delayTime)
		
		# Send the start sequence
		self.uart.SetFtdiPin('rts', rtsAsserted)
		sleep(delayTime)
		self.uart.SetFtdiPin('dtr', dtrAsserted)
		sleep(delayTime)
		self.uart.SetFtdiPin('rts', rtsDeasserted)
		sleep(delayTime)
		self.uart.SetFtdiPin('dtr', dtrDeasserted)
		sleep(delayTime)
		
		# Send pulses on RTS
		for i in range(numPulses):
			self.uart.SetFtdiPin('rts', rtsAsserted)
			sleep(delayTime)
			self.uart.SetFtdiPin('rts', rtsDeasserted)
			sleep(delayTime)
		
		# Send the stop sequence
		self.uart.SetFtdiPin('dtr', dtrAsserted)
		sleep(delayTime)
		self.uart.SetFtdiPin('rts', rtsAsserted)
		sleep(delayTime)
		self.uart.SetFtdiPin('dtr', dtrDeasserted)
		sleep(delayTime)
		self.uart.SetFtdiPin('rts', rtsDeasserted)
		sleep(delayTime)
		
		return True
	
	def GetBootPinMode(self):
		'''
		Reads the status of the BOOT pin on the chip to determine 
		'''
		return self.getFtdiPin(self.ActiveBoard.FtdiSenseBootState)
	
	def DisableEcho(self):
		'''
		Disables the forth interpreter from echoing back the serial data it receives.
		
		Returns: bool (success)
		'''
		if not self.uart.IsOpen:
			return False
		self.uart.FlushBuffers()
		
		# Disable echo and then print a '$' character
		if self.uart.WriteLine('0 echo ' + str(ord('$')) + ' emit') is None:
			return False
		if self.uart.ReadUntil('$') is None:
			return False
		
		return True
	
	
	
	
	
	
	
	
	def setFtdiPin(self, ftdiHardwareData):
		'''
		Sets the pin state of the desired FTDI pin
		
		@ftdiHardwareData: dict {"FtdiPin": "pin name", "Polariy": int (the polarity to set the pin to)}
		
		Returns: bool (success) or None (if unable to connect)
		'''
		if not self.uart.IsOpen:
			return None
		if ftdiHardwareData is None:
			return False
		if type(ftdiHardwareData) != dict:
			return False
		if 'FtdiPin' not in ftdiHardwareData:
			return False
		ftdiPin = ftdiHardwareData['FtdiPin']
		if 'Polarity' not in ftdiHardwareData:
			return False
		polarity = ftdiHardwareData['Polarity']
		ret = self.uart.SetFtdiPin(ftdiPin, polarity)
		if ret != True:
			return ret
		if self.uart.GetFtdiPin(ftdiPin) != polarity:
			return False
		return True
	
	def getFtdiPin(self, ftdiHardwareData):
		'''
		Gets the pin state of the desired FTDI pin
		
		@ftdiHardwareData: dict {"FtdiPin": "pin name", "0": "value if pin is 0", "1", "value if pin is 1"}
		
		Returns: int (pin value) or None (if unable to detect value of pin)
		'''
		if not self.uart.IsOpen:
			return None
		if ftdiHardwareData is None:
			return None
		if type(ftdiHardwareData) != dict:
			return None
		if 'FtdiPin' not in ftdiHardwareData:
			return None
		if "0" not in ftdiHardwareData:
			return None
		if "1" not in ftdiHardwareData:
			return None
		ftdiPin = ftdiHardwareData['FtdiPin']
		val = self.uart.GetFtdiPin(ftdiPin)
		if val is None:
			return None
		return ftdiHardwareData[str(val)]
	
	def testForthConnection(self):
		'''
		Determines if the serial port is connected to a Forth interpreter at the desired baudrate
		'''
		if self.uart.IsOpen != True:
			return None
		sleep(10e-3)
		if self.uart.WriteLine('') is None:
			self.Disconnect()
			#print('Unable to detect baudrate')
			return None
		sleep(50e-3)
		self.uart.FlushReadBuffer()
		if self.uart.WriteLine('0xBEEF . 36 emit') is None:
			self.Disconnect()
			#print('Unable to detect baudrate')
			return None
		s = ''
		while len(s) < 50:
			r = self.uart.Read(1)
			if r is None:
				return False
			s += r
			if s.endswith('48879 $'):
				return True
		return False
	
	def detectChipNameAndBootMode(self):
		'''
		Attempts to detect the chip name by issuing the "42 bye" command. Also clears the math stack, address stack, and any newly defined Forth programs, and also disables echo.
		
		Returns: tuple(str (chip name), str (boot mode)) or None (if chip cannot be identified, which could be for a variety of reasons, including the serial port being disconnected, improper baud rate, the chip currently being unresponsive, the forth interpreter not running, an improper version of the forth interpreter running, etc.)
		'''
		if not self.uart.IsOpen:
			return None
		self.uart.FlushBuffers()
		
		# Give Forth interpreter a moment to be ready for commands
		sleep(0.1)
		
		# Issue the command
		if self.uart.WriteLine('1 echo') is None:	# Enable echo
			return None
		if self.uart.ReadUntil('>') is None:	# Wait to receive the '>' character (the interactive prompt character)
			return None
		if self.uart.WriteLine('42 bye') is None:
			return None
		
		# Read the reply
		if self.uart.ReadUntil('42 bye' + self.uart.NewlineRead) is None:	# Read the echo'ed string
			return None
		r = self.uart.ReadUntil('>', stripTerminator=True)	# Read the rest of the reply until the prompt character
		if r is None:
			return None
		r = r.strip()
		
		# Determine the boot mode
		bootMode = None
		if self.ActiveChip.ForthInitStringFlash in r:
			bootMode = 'SpiFlash'
		elif self.ActiveChip.ForthInitStringRom in r:
			bootMode = 'ROM'
		else:
			# Not a forth interpreter at all!
			return None
		
		# Parse the reply
		lines = r.split('\n')
		chipName = lines[0].strip().replace(':', '')
		
		# Disable echo (echo is automatically enabled after a bye command)
		if self.DisableEcho() != True:
			return None
		
		return chipName, bootMode
	
	def detectImproperReply(self, reply):
		if type(reply) != str:
			return True
		if '?' in reply:
			return True
		if 'rv4th' in reply:
			return True
		return False
	
	def calcBcrRegister(self, clockFrequency, desiredBaudrate):
		return int(round(((clockFrequency / (16 * desiredBaudrate)) - 1) + 1e-15))
	
	def calcBaudrate(self, clockFrequency, bcrRegisterValue):
		return int(round((clockFrequency / (16 * (bcrRegisterValue + 1))) + 1e-15))

if __name__ == "__main__":
	print('Testing...')
	chip = Chip.CreateFromMemoryMapJson('../../picorv32-fpga/config/MemoryMap.json')
	chip.LoadBoardsFromJson('../../picorv32-fpga/config/BoardConfig.json')
	
	fakeUart = UART()
	port = fakeUart.InteractivePortChooser()
	
	forth = ForthInterface()
	if forth.Connect(chip, chip.Boards[0], port, desiredBootMode='ROM') != True:
		exit()
	print('Connected to', forth.ActiveChip.Name, 'PCB', forth.ActiveBoard.Name, 'Rev.', forth.ActiveBoard.Revision, 'on', forth.uart.Port, 'at', forth.uart.Baudrate, 'baud')
	print('Boot mode:', forth.ActiveBootMode)
	print('SYSCLKCR =', hex(forth.ReadRegister(regName='SYSCLKCR')))
	if forth.ChangeBaudrateUsingHFXT(9600) != True:
		print('Unable to change baudrate')
		exit()
	print('SMCLK frequency:', forth.MeasureClockFrequency('SMCLK'))
	print('MCLK frequency:', forth.MeasureClockFrequency('MCLK'))
	
	s = 'Cool dude!'
	binData = s.encode('ascii') + bytes(256 - len(s))
	if forth.WriteFlashPage(0, binData) != True:
		print('Unable to write to flash memory')
	r = forth.ReadFlashPage(0, len(s))
	print('Data in flash memory:', r)