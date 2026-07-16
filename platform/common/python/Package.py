import datetime, os, pathlib

class PackageData():
	PackageType = None	# QFN, DIP, etc.
	PinCount = None
	Units = None	# in, mm, etc.
	Dimensions = None	# [xdim, ydim]
	PinsOnEachSide = None	# dict {'W': ?, 'S': ?, 'E': ?, 'N': ?}
	PinPitch = None	# pin pitch from center to center
	PinWidth = None	# pin dimension parallel to side/edge
	PinDepth = None	# pin dimension perpendicular to side/edge
	
	GpioPowerDomain = None

	Pins = None

	def __init__(self, packageType:str, pinCount:int, units:str, dimensions:list, pinsOnEachSide:dict, pinPitch:float, pinWidth:float, pinDepth:float, gpioPowerDomain=None):
		allowedPackageTypes = ['QFN']
		if packageType not in allowedPackageTypes:
			raise Exception('Package type "' + str(packageType) + '" not in list of allowed package types: ' + str(allowedPackageTypes))
		self.PackageType = packageType

		if type(pinCount) != int or pinCount <= 0:
			raise Exception('Pin count must be a positive integer')
		self.PinCount = pinCount
		
		allowedUnits = ['mm']
		if units not in allowedUnits:
			raise Exception('Units "' + str(units) + '" not in list of allowed units: ' + str(allowedUnits))
		self.Units = units

		if type(dimensions) != list or len(dimensions) != 2 or dimensions[0] <= 0 or dimensions[1] <= 0:
			raise Exception('Dimensions must be a list of length 2 of positive, nonzero numbers. Given: ' + str(dimensions))
		self.Dimensions = dimensions

		if type(pinsOnEachSide) != dict or 'W' not in pinsOnEachSide or 'S' not in pinsOnEachSide or 'E' not in pinsOnEachSide or 'N' not in pinsOnEachSide:
			raise Exception("pinsOnEachSide must be a dict {'W': ?, 'S': ?, 'E': ?, 'N': ?} where each element is a positive integer, all of which sum to the pinCount. Given: " + str(pinsOnEachSide))
		sidePinsCount = 0
		for k in pinsOnEachSide:
			e = pinsOnEachSide[k]
			if type(e) != int or e <= 0:
				raise Exception("pinsOnEachSide must be a dict {'W': ?, 'S': ?, 'E': ?, 'N': ?} where each element is a positive integer, all of which sum to the pinCount. Given: " + str(pinsOnEachSide))
			sidePinsCount += e
		if pinCount != sidePinsCount:
			raise Exception("pinsOnEachSide must be a dict {'W': ?, 'S': ?, 'E': ?, 'N': ?} where each element is a positive integer, all of which sum to the pinCount. Given: " + str(pinsOnEachSide))
		self.PinsOnEachSide = pinsOnEachSide

		if pinPitch <= 0:
			raise Exception('pinPitch must be greater than 0')
		self.PinPitch = pinPitch
		
		if pinWidth <= 0 or pinWidth >= pinPitch:
			raise Exception('pinWidth must be greater than 0 and less than pinPitch')
		self.PinWidth = pinWidth

		if pinDepth <= 0:
			raise Exception('pinDetph must be greater than 0')
		self.PinDepth = pinDepth

		if gpioPowerDomain is not None:
			if 'Power Domain Name' not in gpioPowerDomain or 'Voltage' not in gpioPowerDomain or 'Positive Rail Pin' not in gpioPowerDomain or 'Negative Rail Pin' not in gpioPowerDomain:
				raise Exception

		self.Pins = []
		self.PowerDomains = []	# creation order; consumed by the PadRing.json emitter

		return

	def AddPowerDomain(self, powerDomainName:str, positiveVoltage:float, negativeVoltage:float, positiveRailPinNumber:int, positiveRailPinName:str, negativeRailPinNumber:int, negativeRailPinName:str, isGpioPowerDomain:bool=False, positiveRailExtraPins=None, negativeRailExtraPins=None):
		'''A power domain's + and - rails each land on ONE package pin by default.
		positiveRailExtraPins/negativeRailExtraPins (lists of (pinNumber, pinName))
		bond the SAME rail net out on ADDITIONAL package pads — a multi-pad rail
		(e.g. the CQ QFN-64 core/IO supplies, one pair per die edge). Single-pad
		domains pass neither and behave exactly as before.'''
		pd = PowerDomain(name=powerDomainName, positiveVoltage=positiveVoltage, negativeVoltage=negativeVoltage)
		vddPin = self.AddPin(packagePinNumber=positiveRailPinNumber, name=positiveRailPinName, ioType='pi', powerDomain=pd)
		vddPin.IsPowerDomainPin = True
		vssPin = self.AddPin(packagePinNumber=negativeRailPinNumber, name=negativeRailPinName, ioType='pi', powerDomain=pd)
		vssPin.IsPowerDomainPin = True
		pd.PositiveRailPackagePin = vddPin
		pd.NegativeRailPackagePin = vssPin
		pd.PositiveRailPins = [vddPin]
		pd.NegativeRailPins = [vssPin]

		# Additional pads sharing the same rail net (multi-pad rails).
		for (num, nm) in (positiveRailExtraPins or []):
			ep = self.AddPin(packagePinNumber=num, name=nm, ioType='pi', powerDomain=pd)
			ep.IsPowerDomainPin = True
			pd.PositiveRailPins.append(ep)
		for (num, nm) in (negativeRailExtraPins or []):
			ep = self.AddPin(packagePinNumber=num, name=nm, ioType='pi', powerDomain=pd)
			ep.IsPowerDomainPin = True
			pd.NegativeRailPins.append(ep)

		if isGpioPowerDomain:
			if self.GpioPowerDomain is not None:
				raise Exception('GPIO Power Domain is already defined')
			self.GpioPowerDomain = pd

		self.PowerDomains.append(pd)

		return pd

	def AddPin(self, packagePinNumber:int, name:str, ioType:str, powerDomain=None, noConnect:bool=False):
		p = PackagePin(packagePinNumber=packagePinNumber, name=name, ioType=ioType, powerDomain=powerDomain, noConnect=noConnect)
		self.Pins.append(p)
		return p
	
	def AddGpioPin(self, packagePinNumber:int, gpio):
		p = self.AddPin(packagePinNumber, gpio.GpioName, 'io')
		p.Gpio = gpio
		return p




class PackagePin():
	PackagePinNumber = None
	Name = None
	IOType = None
	NoConnect = False

	IsPowerDomainPin = False
	PowerDomain = None
	
	Side = None

	Gpio = None

	@property
	def FullName(self):
		if self.Gpio is None:
			return self.Name
		else:
			name = self.Name
			if len(self.Gpio.PrimaryName) > 0:
				name += '(' + self.Gpio.PrimaryName + ')'
			if len(self.Gpio.FuncName) > 0:
				name += '/' + self.Gpio.FuncName
			return name
	
	@property
	def PrimaryName(self):
		if self.Gpio is not None and len(self.Gpio.PrimaryName) > 0:
			return self.Gpio.PrimaryName
		return None
	
	@property
	def FuncName(self):
		if self.Gpio is not None and len(self.Gpio.FuncName) > 0:
			return self.Gpio.FuncName
		return None

	

	def __init__(self, packagePinNumber:int, name:str, ioType:str, powerDomain=None, noConnect:bool=False):
		if packagePinNumber < 1:
			raise Exception('packagePinNumber must be > 0')
		self.PackagePinNumber = packagePinNumber
		
		if noConnect:
			self.Name = 'NC'
			self.IOType = 'NC'
			self.NoConnect = True
			self.IsPowerDomainPin = False
			self.PowerDomain = None
			return
		
		if len(name) < 1:
			raise Exception('name must not be empty')
		self.Name = name

		validIOTypes = ['i', 'o', 'io', 'pi', 'po', 'z']
		if ioType not in validIOTypes:
			raise Exception('IO type "' + str(ioType) + '" not in list of valid IO types: ' + str(validIOTypes))
		self.IOType = ioType

		self.PowerDomain = powerDomain

		return
	
	@property
	def IOString(self):
		if self.IOType == 'i':
			return 'Input'
		elif self.IOType == 'o':
			return 'Output'
		elif self.IOType == 'io':
			return 'Input/Output'
		elif self.IOType == 'pi':
			return 'Power Input'
		elif self.IOType == 'po':
			return 'Power Output'
		elif self.IOType == 'z':
			return 'Passive'
		return None
		
		



class PowerDomain():
	Name = None
	PositiveVoltage = None
	NegativeVoltage = None
	PositiveRailPackagePin = None	# the primary + rail pad
	NegativeRailPackagePin = None	# the primary - rail pad
	PositiveRailPins = None	# ALL + rail pads (>=1; multi-pad rails)
	NegativeRailPins = None	# ALL - rail pads (>=1; multi-pad rails)

	def __init__(self, name:str, positiveVoltage:float, negativeVoltage:float):
		if len(name) < 1:
			raise Exception('name must not be empty')
		self.Name = name
		self.PositiveRailPins = []
		self.NegativeRailPins = []

		if type(positiveVoltage) != float:
			raise Exception('positiveVoltage must be a float')
		self.PositiveVoltage = positiveVoltage

		if type(negativeVoltage) != float:
			raise Exception('negativeVoltage must be a float')
		self.NegativeVoltage = negativeVoltage

		return
	
	@property
	def Description(self):
		s = self.Name + ' (' + str(self.PositiveVoltage)
		if not (-1e-9 <= self.NegativeVoltage <= 1e-9):
			s += ' to ' + str(self.NegativeVoltage)
		s += ' V)'
		return s
