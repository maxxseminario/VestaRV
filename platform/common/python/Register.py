from BitField import BitField

class RegisterTemplate():
	NameTemplate = None
	RegisterMemorySlot = None
	Description = None
	Size = None	# In bits
	BitFields = None
	
	Offset = None
	
	Parent = None
	
	ResetValue = None
	
	def __init__(self, nameTemplate, registerMemorySlot, description='', size=32, bitFields=None):
		# Check nameTemplate
		if type(nameTemplate) != str:
			raise Exception('nameTemplate must be a string')
		if len(nameTemplate) < 1:
			raise Exception('nameTemplate cannot be empty')
		validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_x'
		for c in nameTemplate:
			if c not in validChars:
				raise Exception('RegisterTemplate\'s nameTemplate "' + nameTemplate + '" contains illegal character "' + c + '"')
		poundSignsInNameTemplate = nameTemplate.count('x')
		if poundSignsInNameTemplate > 1:
			raise Exception('Only one "x" character may be used in a name template')
		
		self.NameTemplate = nameTemplate
		
		# Set description
		self.Description = description
		
		# Check memory slot. The REAL bound is per-peripheral (the global
		# registerMemorySlotsPerPeripheralMemorySlot, or the peripheral's
		# registerSlotCount override for absolute-base shared-window devices
		# whose register file outgrows one page-0 slot pitch — A2/Argus:
		# IRQROUTER rows at 4*h, PWRSR words at N harts) and is enforced in
		# Register.__init__; this is only a template-level sanity bound.
		if type(registerMemorySlot) != int:
			raise Exception('registerMemorySlot must be an integer')

		if registerMemorySlot < 0 or registerMemorySlot > 1023:
			raise Exception('registerMemorySlot must be on the range of [0, 1023]')
		
		self.RegisterMemorySlot = registerMemorySlot
		self.Offset = registerMemorySlot * 4
		
		# Check size
		if type(size) is str:
			sizeOriginal = size
			size = size.lower().replace(' ', '')
			if size == 'byte' or size == 'quarterword':
				size = 8
			elif size == 'halfword':
				size = 16
			elif size == 'word':
				size = 32
			else:
				raise Exception('Invalid register size "' + sizeOriginal + '"')
		
		if not (size in [8, 16, 32]):
			raise Exception('Invalid register size ' + str(size) + ', must be 8, 16, or 32 bits')
		
		self.Size = size
		
		# Add bit fields
		self.BitFields = []
		if bitFields is not None:
			if type(bitFields) != list:
				raise Exception('bitFields must be a list of BitField objects')
			for bitField in bitFields:
				self.AddBitField(bitField)
		
		return
	
	def AddBitField(self, bitField):
		if type(bitField) != BitField:
			raise Exception('Not a BitField type')
		bitField.Parent = self
		if bitField.Name == self.NameTemplate:
			bitField.SameNameAsRegister = True
		self.BitFields.append(bitField)
		return
	
	def GetBitFieldAt(self, bitNum):
		for bf in self.BitFields:
			if bf.LSB <= bitNum <= bf.MSB:
				return bf
		return None
	
	def GetBitResetValue(self, bitNum):
		bf = self.GetBitFieldAt(bitNum)
		if bf is None:
			return None
		if bf.Unused:
			return None
		
		mask = 0b1 << bitNum
		resetVal = bf.ResetValue << bf.LSB
		if mask & resetVal > 0:
			return 1
		return 0
	
	def CheckBitFields(self):
		# Create the available bit mask for the register, depending on the size
		maskneg = None
		if self.Size == 8:
			maskneg = 0xFFFFFF00
		elif self.Size == 16:
			maskneg = 0xFFFF0000
		else:
			maskneg = 0x00000000
		
		# Check for bit overlaps in the bit fields
		for bf1 in self.BitFields:
			if bf1.BitMask & maskneg != 0:
				raise Exception('BitField "' + bf1.Name + '" with MSB=' + str(bf1.MSB) + ' and LSB=' + str(bf1.LSB) + ' is out-of-bounds for the size of the register "' + self.NameTemplate + '", which is ' + str(self.Size) + ' bits')
			if bf1.SameNameAsRegister:
				# If the bit field's name is the same as the register, then it is the only non-Unused bit field allowed in the register
				for bf2 in self.BitFields:
					if bf1 == bf2:
						continue
					if bf2.Unused != True:
						raise Exception('RegisterTemplates that contain a bit field with the same name as the register')
			
			for bf2 in self.BitFields:
				if bf1 == bf2:
					continue
				if bf1.BitMask & bf2.BitMask != 0:
					raise Exception('BitField "' + bf1.Name + '" overlaps bits with BitField "' + bf2.Name + '"')
		
		# Check each bit field's value descriptions
		for bf in self.BitFields:
			bf.CheckValueDescriptions()
		
		# Ensure that the register is fully defined, that is, that every bit is attached to a bit field
		undefinedBits = []
		for i in range(self.Size):
			if self.GetBitFieldAt(i) is None:
				undefinedBits.append(i)
		
		if len(undefinedBits) > 0:
			raise Exception('The following bits in RegisterTemplate "' + self.NameTemplate + '" are undefined: ' + str(undefinedBits)[1:-1] + '. Please define all bits in the register templates by adding bit fields to it. Bits that are not used must be designated with an "Unused" bit field')
		
		# Sort the bit fields by MSB in descending order
		self.BitFields = sorted(self.BitFields, key=lambda bitField: bitField.MSB, reverse=True)

		# Calculate the reset value
		self.ResetValue = 0
		for i in range(self.Size):
			if self.GetBitFieldAt(i) is None:
				continue
			if self.GetBitFieldAt(i).Unused:
				continue
			self.ResetValue |= (self.GetBitResetValue(i) << i)
		
		return
	
class Register():
	Template = None
	NameIndex = None
	
	Name = None
	Address = None
	Parent = None
	
	RegisterMemorySlot = None
	Description = None
	Size = None	# In bits
	ResetValue = None
	Offset = None
	BitFields = None
	
	def __init__(self, registerTemplate, peripheralBaseAddress, registerMemorySlotsPerPeripheralMemorySlot, nameIndex=''):
		# Check registerTemplate
		if type(registerTemplate) != RegisterTemplate:
			raise Exception('Not a RegisterTemplate type')
		
		self.Template = registerTemplate
		
		# Check the name index
		validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
		nameIndexNeeded = 'x' in self.Template.NameTemplate
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
				raise Exception('Register\'s nameIndex "' + nameIndex + '" contains illegal character "' + c + '"')
		
		# Set the name
		self.Name = self.Template.NameTemplate.replace('x', nameIndex)
		
		# Check the memory slot
		if type(peripheralBaseAddress) != int:
			raise Exception('peripheralBaseAddress in "' + self.Name + '" must be an int >= 0x0000')
		if peripheralBaseAddress < 0:
			raise Exception('peripheralBaseAddress in "' + self.Name + '" must be an int >= 0x0000')
		
		if type(registerMemorySlotsPerPeripheralMemorySlot) != int:
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot in "' + self.Name + '" must be an int > 0')
		if registerMemorySlotsPerPeripheralMemorySlot < 1:
			raise Exception('registerMemorySlotsPerPeripheralMemorySlot in "' + self.Name + '" must be an int > 0')
		
		if type(self.Template.RegisterMemorySlot) != int:
			raise Exception('{Register}.Template.RegisterMemorySlot in "' + self.Name + '" must be an int on the range of [0, ' + str(registerMemorySlotsPerPeripheralMemorySlot) + '), but its value is ' + str(self.Template.RegisterMemorySlot))
		if (self.Template.RegisterMemorySlot < 0) or (self.Template.RegisterMemorySlot >= registerMemorySlotsPerPeripheralMemorySlot):
			raise Exception('{Register}.Template.RegisterMemorySlot in "' + self.Name + '" must be an int on the range of [0, ' + str(registerMemorySlotsPerPeripheralMemorySlot) + '), but its value is ' + str(self.Template.RegisterMemorySlot))
		
		# Copy data from RegisterTemplate for ease-of-use
		self.RegisterMemorySlot = self.Template.RegisterMemorySlot
		self.Description = self.Template.Description
		self.Size = self.Template.Size
		self.ResetValue = self.Template.ResetValue
		self.Offset = self.Template.Offset

		# Copy bit fields
		self.BitFields = []
		for bf in self.Template.BitFields:
			bfc = bf.Copy(self)
			if bfc.SameNameAsRegister:
				bfc.Name = bfc.Name.replace('x', nameIndex)
				for i in range(len(bfc.ValueDescriptions)):
					vd = bfc.ValueDescriptions[i]
					if len(vd) >= 3 and 'x' in vd[2]:
						bfc.ValueDescriptions[i] = (vd[0], vd[1], vd[2].replace('x', nameIndex))
			#if 'x' in bfc.Name:
			#	raise Exception('BitField\'s name "' + bfc.Name + '" contains illegal character "x"')
			#for vd in bfc.ValueDescriptions:
			#	if 'x' in vd[2]:
			#		raise Exception('Value Description\'s name "' + vd[2] + '" contains illegal character "x"')
			self.BitFields.append(bfc)
		
		# Set the address
		self.Address = peripheralBaseAddress + self.Offset
		
		return
		
	def CheckIfAllBitsDefined(self):
		undefinedBits = []
		for i in range(self.Size):
			if self.GetBitFieldAt(i) is None:
				undefinedBits.append(i)
		
		if len(undefinedBits) > 0:
			raise Exception('The following bits in register "' + self.Name + '" are undefined: ' + str(undefinedBits)[1:-1] + '. Please define all bits in the register by adding bit fields to it. Bits that are not used must be designated with an "Unused" bit field')

		return

	def GetBitFieldAt(self, bitNum):
		for bf in self.BitFields:
			if bf.LSB <= bitNum <= bf.MSB:
				return bf
		return None
	
	def GetBitResetValue(self, bitNum):
		bf = self.GetBitFieldAt(bitNum)
		if bf is None:
			return None
		
		mask = 0b1 << bitNum
		resetVal = bf.ResetValue << bf.LSB
		if mask & resetVal > 0:
			return 1
		return 0
	
	def ToDict(self):
		# Create a dictionary of the Register object
		r = dict()

		r['RegisterName'] = self.Name
		r['Address'] = self.Address
		r['Offset'] = self.Offset
		r['RegisterMemorySlot'] = self.RegisterMemorySlot
		r['Size'] = self.Size
		r['ResetValue'] = self.ResetValue
		r['Description'] = self.Description

		bitFields = []
		for bf in self.BitFields:
			bitFields.append(bf.ToDict())
		r['BitFields'] = bitFields
		
		return r