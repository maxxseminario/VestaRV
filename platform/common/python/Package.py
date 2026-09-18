# VestaRV: the package model: pin list, sides, dimensions and power domains.
# A PackageData is the pad ring the TRM pinout chapter, config/PadRing.json and the Innovus
# pad-placement template are all rendered from.
import datetime, os, pathlib

# The pad-instance placeholder the Innovus pad-placement template gives a package pin.
# Module level because two readers must agree on it: the template emitter in generate.py and
# the die-row ball-map gate below.
def PadInstanceName(name):
	'''"P3.0(GPIO24)/SDA0" -> PAD_P3_0 ; "VDDPST" -> PAD_VDDPST ; "ATP-IN" -> PAD_ATP_IN'''
	base = name.split('(')[0].split('/')[0].strip()
	return 'PAD_' + base.replace('.', '_').replace('-', '_')


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

	DieRow = None		# the die-row pad list this model is derived from, or None
	DieRowSource = None	# where those rows were read from, named in the gate's messages

	ThermalPad = None	# {'net': str, 'dimensions': [x, y]} exposed pad, or None (no paddle)

	def __init__(self, packageType:str, pinCount:int, units:str, dimensions:list, pinsOnEachSide:dict, pinPitch:float, pinWidth:float, pinDepth:float, gpioPowerDomain=None, thermalPad=None):
		allowedPackageTypes = ['QFN', 'LQFP']
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

		# The exposed thermal pad (paddle) a QFN/similar package may carry underneath the die.
		# Purely descriptive: no pin number, no ball-map row, and no gate depends on it. A
		# design that bonds latch-up anchors or ground to numbered peripheral pins instead
		# (as every model in this tree does today) simply leaves this None; a design that
		# ever wants a down-bond to the paddle records it here rather than inventing a fake
		# pin number for it.
		if thermalPad is not None:
			if 'net' not in thermalPad or 'dimensions' not in thermalPad:
				raise Exception("thermalPad must be {'net': str, 'dimensions': [x, y]}. Given: "
					+ str(thermalPad))
		self.ThermalPad = thermalPad

		self.Pins = []
		self.PowerDomains = []	# creation order; consumed by the PadRing.json emitter

		return

	def AddPowerDomain(self, powerDomainName:str, positiveVoltage:float, negativeVoltage:float, positiveRailPinNumber:int, positiveRailPinName:str, negativeRailPinNumber:int, negativeRailPinName:str, isGpioPowerDomain:bool=False, positiveRailExtraPins=None, negativeRailExtraPins=None):
		'''A power domain whose + and - rails each land on one package pin by default.
		positiveRailExtraPins and negativeRailExtraPins, lists of (pinNumber, pinName), bond the same
		rail net out on additional pads, which is how a multi-pad supply is declared.
		'''
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

	# ---- the die row, and the ball-number gate over it -------------------------------
	# A package model may be DERIVED from a die-row pad list: a file that says which pad
	# instance sits where on the die and which ball, if any, it bonds to. Two descriptions
	# of one ring drift, and the ball number is the column that drifts silently, because
	# nothing downstream of the model re-reads the die row. AttachDieRow declares the rows
	# and CheckDieRowBallMap compares them, ball for ball, against this model AND against
	# the pad list the model emits. A model with no die row declares none and the gate is a
	# no-op, so this costs nothing for the models that are their own authority.

	def AttachDieRow(self, pads, source):
		'''Declare the die-row pad list this package model is derived from.

		`pads` is a sequence of mappings with:
		  net           the pad's net, which must be the package pin NAME on its ball
		  packagePin    the ball, or None for a die pad with no package finger
		  side          optional, 'W'/'S'/'E'/'N', the edge the die row places it on
		  inst          optional, the pad instance name, carried for the message only
		`source` is where the rows were read from; it is quoted in every complaint, so a
		failing build names the file to fix.
		'''
		rows = []
		for pad in pads:
			net = pad.get('net')
			if not isinstance(net, str) or len(net) < 1:
				raise Exception('die row ' + str(source) + ': a pad has no "net" name: ' + str(pad))
			ball = pad.get('packagePin')
			if ball is not None and (type(ball) != int or ball < 1 or ball > self.PinCount):
				raise Exception('die row ' + str(source) + ': pad "' + net + '" has packagePin '
					+ str(ball) + ', which is not a ball on this ' + str(self.PinCount) + '-pin package'
					+ ' (use null for a die pad with no package finger)')
			side = pad.get('side')
			if side is not None and side not in ('W', 'S', 'E', 'N'):
				raise Exception('die row ' + str(source) + ': pad "' + net + '" declares side "'
					+ str(side) + '"; the sides are W, S, E, N')
			rows.append({'net': net, 'packagePin': ball, 'side': side, 'inst': pad.get('inst')})
		self.DieRow = rows
		self.DieRowSource = source

	def SideOfPin(self, packagePinNumber):
		'''Which edge a ball sits on, from PinsOnEachSide alone: the same W/S/E/N walk over
		ascending pin numbers that ChipGenerator.CheckPackagePins does, so it answers before
		the sides have been assigned. None for a number off the package.'''
		if type(packagePinNumber) != int or packagePinNumber < 1 or packagePinNumber > self.PinCount:
			return None
		low = 0
		for side in ('W', 'S', 'E', 'N'):
			high = low + self.PinsOnEachSide[side]
			if low < packagePinNumber <= high:
				return side
			low = high
		return None

	def PadListRows(self):
		'''The rows the Innovus pad-placement template emits, as (side, pin, instance): one per
		declared pin, in emission order (W and N pin-descending, S and E ascending), with the
		uniquified instance placeholder each will carry and None for a no-connect. One
		derivation, shared by the template emitter and the gate below, so a ball cannot read
		one way in the template and another in the check.'''
		ordered = []
		for side, descending in (('W', True), ('S', False), ('E', False), ('N', True)):
			ordered += [(side, p) for p in sorted(
				[q for q in self.Pins if self.SideOfPin(q.PackagePinNumber) == side],
				key=lambda q: q.PackagePinNumber, reverse=descending)]
		totals = {}
		for side, p in ordered:
			if p.NoConnect:
				continue
			base = PadInstanceName(p.Name)
			totals[base] = totals.get(base, 0) + 1
		seen = {}
		rows = []
		for side, p in ordered:
			if p.NoConnect:
				rows.append((side, p, None))
				continue
			base = PadInstanceName(p.Name)
			if totals[base] > 1:
				inst = base + '_' + str(seen.get(base, 0))
				seen[base] = seen.get(base, 0) + 1
			else:
				inst = base
			rows.append((side, p, inst))
		return rows

	def CheckDieRowBallMap(self):
		'''Compare every die-row pad's BALL NUMBER against this model and against the pad list
		the model emits. Returns a list of complaints; empty means the three agree.

		Three legs, all keyed on the ball, because the ball is what a bonding diagram is:
		  1. the pin the model puts on that ball must be the net the die row puts there;
		  2. every ball the die row gives a net must be one of the balls the model gives it,
		     a subset rather than an equality so a multi-pad rail may appear on one island in
		     the die row and on four balls in the model;
		  3. that ball must survive into the emitted pad list, on the edge the die row names.
		A die pad with no ball (packagePin null) is the un-bonded case and is skipped here:
		which pads may be un-bonded is a package decision and belongs to whoever writes the
		die row.

		DEFERRED PADS. A pad the model has not declared when the gate runs -- GPIO pads
		attach to the ring after the model is built -- cannot be compared, so its row is
		skipped rather than failed. Calling the gate again on the finished ring closes that
		half; the call inside the model builder is what stops a bad build early.
		'''
		if not self.DieRow:
			return []
		where = ' (die row ' + str(self.DieRowSource) + ')'
		complaints = []
		pinsOnBall = {}
		ballsOfName = {}
		for pin in self.Pins:
			pinsOnBall.setdefault(pin.PackagePinNumber, []).append(pin)
			if not pin.NoConnect:
				ballsOfName.setdefault(pin.Name, set()).add(pin.PackagePinNumber)
		emitted = dict((p.PackagePinNumber, (side, p, inst))
			for (side, p, inst) in self.PadListRows() if inst is not None)
		dieRowBalls = {}
		for row in self.DieRow:
			net, ball = row['net'], row['packagePin']
			if ball is None:
				continue
			dieRowBalls.setdefault(net, set()).add(ball)
			here = pinsOnBall.get(ball, [])
			if not here:
				continue	# deferred: the model has not attached this ball's pad yet
			if len(here) > 1:
				complaints.append('ball ' + str(ball) + ' carries ' + str(len(here))
					+ ' package pins (' + ', '.join(sorted(p.Name for p in here)) + '); the die row'
					+ ' puts "' + net + '" there' + where)
				continue
			pin = here[0]
			if pin.NoConnect:
				complaints.append('the die row bonds "' + net + '" to ball ' + str(ball)
					+ ', which the package model declares NO-CONNECT' + where)
				continue
			if pin.Name != net:
				complaints.append('ball ' + str(ball) + ': the die row bonds "' + net
					+ '", the package model bonds "' + pin.Name + '"' + where)
				continue
			if row['side'] is not None and row['side'] != self.SideOfPin(ball):
				complaints.append('"' + net + '" is on ball ' + str(ball) + ', which is on the '
					+ str(self.SideOfPin(ball)) + ' edge; the die row places it on the '
					+ row['side'] + ' edge' + where)
			if ball not in emitted:
				complaints.append('"' + net + '" is on ball ' + str(ball)
					+ ', which the emitted pad list does not carry' + where)
		for net in sorted(dieRowBalls):
			if net not in ballsOfName:
				continue	# deferred, as above
			extra = dieRowBalls[net] - ballsOfName[net]
			if extra:
				complaints.append('"' + net + '" is on ball(s) '
					+ ', '.join(str(b) for b in sorted(extra)) + ' in the die row; the package model'
					+ ' puts it on ' + ', '.join(str(b) for b in sorted(ballsOfName[net])) + where)
		return complaints





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
