class BitField():
	Name = None
	Description = None
	MSB = None
	LSB = None
	Accessibility = None
	ResetValue = None
	Unused = None
	
	Parent = None
	
	Size = None
	BitMask = None
	SameNameAsRegister = False

	ValueDescriptions = None	# Form: list of tuples (value, description[, name])
	
	def __init__(self, name=None, msb=None, lsb=None, description:str='', accessibility:str='rw', resetValue:int=0, unused:bool=False, valueDescriptions=None):
		# Validate the MSB and LSB
		if msb is None and lsb is None:
			raise Exception('MSB and LSB cannot both be None. If one is None, then it will be automatically set to the value of the other')
		
		if lsb is None:
			lsb = msb
		elif msb is None:
			msb = lsb
		
		if type(msb) != int or type(lsb) != int:
			raise Exception('MSB and LSB must be integers (one of them may be None, in which case it will be automatically set to the value of the other)')
		
		if lsb < 0:
			raise Exception('LSB must be >= 0')
		
		if msb > 31:
			raise Exception('MSB must be <= 31')
		
		if lsb > msb:
			raise Exception('LSB cannot be greater than MSB')
		
		# Set the size
		self.Size = msb - lsb + 1
		self.MSB = msb
		self.LSB = lsb
		
		# Set the bit mask
		self.BitMask = 0
		for i in range(lsb, msb + 1):
			self.BitMask |= 0b1 << i
		
		# Check if unused
		if unused == True:
			self.Unused = True
			self.Name = 'Unused'
			self.Description = ''
			self.Accessibility = 'r0'
			self.ResetValue = 0
			self.ValueDescriptions = []
			return
		
		# This is not unused
		self.Unused = False
		
		# Check name
		if type(name) != str:
			raise Exception('name must be a string')
		if len(name) < 1:
			raise Exception('name cannot be empty')
		validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_'
		for c in name:
			if c not in validChars:
				raise Exception('BitField\'s name "' + name + '" contains illegal character "' + c + '"')
		self.Name = name
		
		# Set description
		self.Description = description
		
		# Set accessibility
		a = accessibility.lower()
		if not (a in ['rw', 'r', 'r0', 'r1', 'rw0', 'rw1', 'w', 'w0', 'w1']):
			raise Exception('Invalid BitField accessibility "' + str(accessibility) + '"')
		self.Accessibility = a
		
		# Set reset value
		mask = 0
		for i in range(self.Size):
			mask = (mask << 1) | 0b1
		
		if resetValue > mask:
			raise Exception('Reset value is out of bounds of the size of the BitMask')
		
		self.ResetValue = resetValue
		
		# Add optional value descriptions
		self.ValueDescriptions = []
		if valueDescriptions is not None:
			if type(valueDescriptions) != list:
				raise Exception('valueDescriptions must be a list of value description tuples, or None. The value description tuples must be of the form (value, description, nameSuffix) or (value, description)')
			for valueDescription in valueDescriptions:
				value = None
				description = None
				nameSuffix = ''
				if type(valueDescription) != tuple:
					raise Exception('Value description tuples must be of the form (value, description, nameSuffix) or (value, description)')
				if len(valueDescription) not in [2, 3]:
					raise Exception('Value description tuples must be of the form (value, description, nameSuffix) or (value, description)')
				
				value = valueDescription[0]
				description = valueDescription[1]
				
				if len(valueDescription) == 3:
					nameSuffix = valueDescription[2]
				
				self.AddValueDescription(value, description, nameSuffix=nameSuffix)
		
		return
	
	def AddValueDescription(self, value:int, description:str, nameSuffix:str=''):
		mask = 0
		for i in range(self.Size):
			mask = (mask << 1) | 0b1
			
		if value > mask:
			raise Exception('Value for value description is out of bounds of the size of the BitField')
		
		name = ''
		if len(nameSuffix) > 0:
			name = self.Name + nameSuffix
		
		if nameSuffix.startswith(self.Name):
			print('WARNING: The name suffix "' + nameSuffix + '" for a value description in BitField "' + self.Name + '" starts with the name of the BitField, making the name of the value description "' + name + '". You may wish to consider renaming the name suffix of the value description so that it is not redundant.')
		
		validChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_'
		for c in name:
			if c not in validChars:
				raise Exception('Value Description\'s name "' + name + '" contains illegal character "' + c + '"')
		
		valueDescription = (value, description, name)
		self.ValueDescriptions.append(valueDescription)
		return
	
	def CheckValueDescriptions(self):
		if len(self.ValueDescriptions) < 1:
			return
		
		for vd1 in self.ValueDescriptions:
			# Check to see if the value of the value description is out-of-bounds of the bit field
			mask = 0
			for i in range(self.Size):
				mask = (mask << 1) | 0b1
			if vd1[0] > mask:
				raise Exception('Value ' + str(vd1[0]) + 'for value description in BitField "' + self.Name + '" is out-of-bounds of the size of the BitField')
			
			# Check for the same value or name among the other value descriptions
			for vd2 in self.ValueDescriptions:
				if vd1 == vd2:
					continue
				
				if vd1[0] == vd2[0]:
					raise Exception('Value ' + bin(vd1[0]) + ' for value description ' + vd1[1] + ' more than once, which is not allowed')
				
				if (vd1[2] == vd2[2]) and (vd1[2] != ''):
					raise Exception('Value description name "' + vd1[2] + '" is used more than once, which is not allowed')
		
		# Sort value descriptions by value in ascending order
		self.ValueDescriptions = sorted(self.ValueDescriptions, key=lambda tup: tup[0])
		return
	
	def Copy(self, parent):
		bf = BitField(name=self.Name, description=self.Description, msb=self.MSB, lsb=self.LSB, accessibility=self.Accessibility, resetValue=self.ResetValue, unused=self.Unused)

		bf.Parent = parent
		bf.SameNameAsRegister = self.SameNameAsRegister
		
		bf.ValueDescriptions = []
		for vdold in self.ValueDescriptions:
			vdnew = (vdold[0], vdold[1], vdold[2])
			bf.ValueDescriptions.append(vdnew)

		return bf
	
	def ToDict(self):
		# Create a dictionary of the BitField object
		bf = dict()

		bf['BitFieldName'] = self.Name
		bf['MSB'] = self.MSB
		bf['LSB'] = self.LSB
		bf['Accessibility'] = self.Accessibility
		bf['ResetValue'] = self.ResetValue
		bf['Unused'] = self.Unused
		bf['Description'] = self.Description
		bf['ValueDescriptions'] = self.ValueDescriptions
		
		return bf