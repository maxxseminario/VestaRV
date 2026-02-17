import string

class TabbedTable():
	
	Items = None
	
	TabWidth = 4
	Newline = '\n'
	ValidChars = string.ascii_letters + string.digits + string.punctuation + ' '
	
	def __init__(self):
		self.Items = []
	
	def AddRow(self, row, prefixTabs=0):
		if type(row) != list and type(row) != tuple:
			raise Exception('row must be a list or a tuple')
		
		for col in row:
			if type(col) != str:
				raise Exception('Each item in a row must be a str')
			self.checkText(col)
		
		item = ('row', row, prefixTabs)
		self.Items.append(item)
		return
	
	def AddLine(self, line, prefixTabs=0):
		if type(line) != str:
			raise Exception('line must be a str')
		
		self.checkText(line)
		
		item = ('line', line, prefixTabs)
		self.Items.append(item)
		return
	
	def AddBlankLines(self, numBlankLines=1):
		for i in range(numBlankLines):
			self.AddLine('')
		return
	
	def AddBlankLine(self):
		self.AddBlankLines(numBlankLines=1)
		return
	
	def ToString(self):
		# How many columns are there?
		maxColumns = 1
		for item in self.Items:
			if item[0] == 'row':
				colCount = len(item[1])
				if colCount > maxColumns:
					maxColumns = colCount
		
		# Count the maximum number of chars in each column
		colMaxChars = [0 for i in range(maxColumns)]
		for item in self.Items:
			if item[0] == 'row':
				for col, txt in enumerate(item[1]):
					txtlen = len(txt) + self.TabWidth * item[2]
					if colMaxChars[col] < txtlen:
						colMaxChars[col] = txtlen
		
		# Expand the maximum number of chars in each column to align with the tab width
		colChars = [maxChars + (self.TabWidth - (maxChars % self.TabWidth)) for maxChars in colMaxChars]
		for col, numChars in enumerate(colChars):
			if numChars == colMaxChars[col]:
				colChars[col] = numChars + self.TabWidth
		
		# Build string
		s = ''
		for item in self.Items:
			for i in range(item[2]):
				s += '\t'
			
			if item[0] == 'row':
				for col, txt in enumerate(item[1]):
					if col == len(item[1]) - 1:
						s += txt
						continue
					txtlen = len(txt) + self.TabWidth * item[2]
					if len(txt) % self.TabWidth != 0:
						txt += '\t'
						txtlen += self.TabWidth - (txtlen % self.TabWidth)
					while txtlen < colChars[col]:
						txt += '\t'
						txtlen += self.TabWidth
					s += txt
				s += self.Newline
			elif item[0] == 'line':
				s += item[1] + self.Newline
			else:
				raise Exception('Invalid item')
		
		return s
	
	def checkText(self, txt):
		for c in txt:
			if c not in self.ValidChars:
				raise Exception('Character "' + c + '" is not allowed in a TabbedTable')
		return