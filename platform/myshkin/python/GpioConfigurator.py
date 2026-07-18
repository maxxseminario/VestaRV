

class GpioConfigurator():
	NoConnect = False

	BitNumber = None
	PrimaryName = None
	FuncName = None
	FuncIOType = None
	Description = None
	RstOUT = None
	RstDIR = None
	RstSEL = None
	RstREN = None
	
	PrimaryBitName = None
	PrimaryPxINName = None
	PrimaryPxOUTName = None
	PrimaryPxDIRName = None
	PrimaryPxIESName = None
	PrimaryPxIEName = None
	PrimaryPxIFGName = None
	PrimaryPxSELName = None
	PrimaryPxRENName = None
	
	FuncBitName = None
	FuncPxINName = None
	FuncPxSELName = None
	FuncPxDIRName = None
	FuncPxOUTName = None
	FuncPxRENName = None
	FuncPxIESName = None
	FuncPxIEName = None
	FuncPxIFGName = None

	ParentPeripheral = None

	@property
	def GpioName(self):
		if self.ParentPeripheral is None:
			return None
		return 'P' + self.ParentPeripheral.GetGPIOPortLabel() + '.' + str(self.BitNumber)
	
	
	def __init__(self, bitNumber, primaryName='', funcName='', funcIOType=None, description='', rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, noConnect:bool=False):
		'''
		@bitNumber: The pin number on the GPIO port
		@primaryName: The the name of the pin in its primary (GPIO) function. This is only used to generate helpful defines in the MemoryMap.h file, and has no hardware significance
		@funcName: The name of the secondary (peripheral) function. This name will be used to define all hardware signals and software defines.
		@funcIOType: Defines the I/O type of the pin. Valid inputs are: None, 'i', 'o', 'io'. If 'i' is included in the string, a hardware signal with its name as {funcName}_IN will be declared and set as the value from the pad's input terminal. If 'o' is included in the string, hardware signals with names of {funcName}_OUT, *_DIR, and *_REN will be declared and routed to the pad's output, direction, and resistor enable terminals. WARNING: Some peripherals, such as SPI, have pins that may be considered "inputs" only, such as MISO. However, it is sometimes necessary for an input pin to have its OUT, DIR, and REN lines set by the peripheral rather than the GPIO registers. Therefore, such pins should be declared as 'io' rather than just 'i' to allow the peripheral to control all I/O signals associated with the designated pad.
		@description: A description of the pin for the manual
		@rstOUT: The reset value of the PxOUT
		@rstDIR: The reset value of PxDIR
		@rstSEL: The reset value of PxSEL
		@rstREN: The reset value of PxREN
		'''
		# Pin Number
		if type(bitNumber) != int:
			raise Exception('bitNumber must be an integer on the range of [0, 31]')
		if bitNumber < 0 or bitNumber > 31:
			raise Exception('bitNumber must be an integer on the range of [0, 31]')
		
		self.BitNumber = bitNumber

		if noConnect:
			self.NoConnect = True
			return
		
		# Primary Name
		validChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
		if type(primaryName) != str:
			raise Exception('primaryName must be a string comprised of valid characters')
		for c in primaryName:
			if c not in validChars:
				raise Exception('The char "' + c + '" is not allowed in primaryName')
		
		self.PrimaryName = primaryName
		
		# Function Name
		if type(funcName) != str:
			raise Exception('funcName must be a string comprised of valid characters')
		for c in funcName:
			if c not in validChars:
				raise Exception('The char "' + c + '" is not allowed in funcName')
		
		self.FuncName = funcName
		
		# Function IO Type
		validIOTypes = ['none', '', 'input', 'i', 'output', 'o', 'inputoutput', 'io']
		if type(funcIOType) != str:
			raise Exception('funcIOType must be one of the following: ' + str(validIOTypes))
		funcIOType = funcIOType.lower()
		if funcIOType not in validIOTypes:
			raise Exception('funcIOType must be one of the following: ' + str(validIOTypes))
		
		if funcIOType == 'i' or funcIOType == 'input':
			self.FuncIOType = 'I'
		elif funcIOType == 'o' or funcIOType == 'output':
			self.FuncIOType = 'O'
		elif funcIOType == 'io' or funcIOType == 'inputoutput':
			self.FuncIOType = 'IO'
		elif funcIOType == '' or funcIOType == 'none':
			self.FuncIOType = ''
		
		if len(self.FuncName) < 1 and len(self.FuncIOType) > 0:
			raise Exception('Pin must have a non-empty FuncName if it has a FuncIOType')
		
		if len(self.FuncName) > 0 and len(self.FuncIOType) < 1:
			raise Exception('Pin must have a FuncIOType if it has a FuncName')
		
		# Description
		self.Description = description
		
		# Reset values
		if rstOUT == 0:
			self.RstOUT = 0
		elif rstOUT == 1:
			self.RstOUT = 1
		else:
			raise Exception('rstOUT must be either 0 or 1')
		
		if rstDIR == 0:
			self.RstDIR = 0
		elif rstDIR == 1:
			self.RstDIR = 1
		else:
			raise Exception('rstDIR must be either 0 or 1')
		
		if rstSEL == 0:
			self.RstSEL = 0
		elif rstSEL == 1:
			self.RstSEL = 1
		else:
			raise Exception('rstSEL must be either 0 or 1')
		
		if rstREN == 0:
			self.RstREN = 0
		elif rstREN == 1:
			self.RstREN = 1
		else:
			raise Exception('rstREN must be either 0 or 1')
		
		# Generate the primary bit names
		self.PrimaryBitName = ''
		self.PrimaryPxINName = ''
		self.PrimaryPxOUTName = ''
		self.PrimaryPxDIRName = ''
		self.PrimaryPxIESName = ''
		self.PrimaryPxIFGName = ''
		self.PrimaryPxIEName = ''
		self.PrimaryPxSELName = ''
		self.PrimaryPxRENName = ''
		
		if len(primaryName) > 0:
			self.PrimaryBitName = self.PrimaryName + '_BIT'
			self.PrimaryPxINName = self.PrimaryName + '_PxIN'
			self.PrimaryPxOUTName = self.PrimaryName + '_PxOUT'
			self.PrimaryPxDIRName = self.PrimaryName + '_PxDIR'
			self.PrimaryPxIESName = self.PrimaryName + '_PxIES'
			self.PrimaryPxIFGName = self.PrimaryName + '_PxIFG'
			self.PrimaryPxIEName = self.PrimaryName + '_PxIE'
			self.PrimaryPxSELName = self.PrimaryName + '_PxSEL'
			self.PrimaryPxRENName = self.PrimaryName + '_PxREN'
		
		# Generate the secondary function bit names
		self.FuncBitName = ''
		self.FuncPxINName = ''
		self.FuncPxSELName = ''
		self.FuncPxDIRName = ''
		self.FuncPxOUTName = ''
		self.FuncPxRENName = ''
		self.FuncPxIESName = ''
		self.FuncPxIFGName = ''
		self.FuncPxIEName = ''
		
		if len(funcName) > 0:
			self.FuncBitName = self.FuncName + '_BIT'
			self.FuncPxINName = self.FuncName + '_PxIN'
			self.FuncPxSELName = self.FuncName + '_PxSEL'
			self.FuncPxDIRName = self.FuncName + '_PxDIR'
			self.FuncPxOUTName = self.FuncName + '_PxOUT'
			self.FuncPxRENName = self.FuncName + '_PxREN'
			self.FuncPxIESName = self.FuncName + '_PxIES'
			self.FuncPxIFGName = self.FuncName + '_PxIFG'
			self.FuncPxIEName = self.FuncName + '_PxIE'
		
		return