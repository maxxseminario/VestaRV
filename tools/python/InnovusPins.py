#!/usr/bin/env python3

# Global constants
outputFile = '../innovus/in/MCU.io'

PathWidth		= 02.770
Space			= 01.000
Depth			= 00.400
Grid			= 00.005
PadWidth		= 25.000
FillOnSides		= 07.500
FillBetweenPads	= 50.000
PadsPerSide		= 11
Layer		 	= 2


def getPathStart(terminalStart, terminalEnd):
	# The start of the path is the center
	av = (terminalStart + terminalEnd) / 2
	roundedPathStart = (int(round(av / Grid))) * Grid
	widthGrid2 = (int(round(PathWidth / Grid)))
	if widthGrid2 % 2 == 1:
		roundedPathStartGrid2 = (int(round(roundedPathStart / Grid)))
		if roundedPathStartGrid2 % 2 == 1:
			raise Exception('Edge of path is not on the grid!')
	return roundedPathStart



# I/O Pad: PDUW16SDGZ_G in library tphn65pgpv2od3_sl
# All dimensions are in a counter clockwise direction
class PadPDUW16SDGZ_G():
	TerminalI_Start		= 00.995
	TerminalI_End		= 03.765
	TerminalI			= None

	TerminalOEN_Start	= 11.590
	TerminalOEN_End		= 14.360
	TerminalOEN			= None

	TerminalREN_Start	= 15.550
	TerminalREN_End		= 18.320
	TerminalREN			= None

	TerminalC_Start		= 21.230
	TerminalC_End		= 24.000
	TerminalC			= None

	PadBaseName = None
	Index = None

	PadNumber = None
	BaseOffset = None

	def __init__(self, padBaseName, index=None):
		self.PadBaseName = padBaseName
		self.Index = index
	
	def CalculatePlacement(self, baseOffset):
		self.BaseOffset = baseOffset

		self.TerminalI		= self.BaseOffset + getPathStart(self.TerminalI_Start, self.TerminalI_End)
		self.TerminalOEN	= self.BaseOffset + getPathStart(self.TerminalOEN_Start, self.TerminalOEN_End)
		self.TerminalREN	= self.BaseOffset + getPathStart(self.TerminalREN_Start, self.TerminalREN_End)
		self.TerminalC		= self.BaseOffset + getPathStart(self.TerminalC_Start, self.TerminalC_End)
	
	def GetTerminalStringsForGPIO(self):
		sIndex = ''
		if self.Index is not None:
			sIndex = '[' + str(self.Index) + ']'

		sI		= '\t\t(pin name="' + self.PadBaseName + 'OUT' + sIndex + '"  offset=' + str(round(self.TerminalI, 3))   + ' layer=' + str(Layer) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + '  place_status=fixed  )\n'
		sOEN	= '\t\t(pin name="' + self.PadBaseName + 'DIR' + sIndex + '"  offset=' + str(round(self.TerminalOEN, 3)) + ' layer=' + str(Layer) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + '  place_status=fixed  )\n'
		sREN	= '\t\t(pin name="' + self.PadBaseName + 'REN' + sIndex + '"  offset=' + str(round(self.TerminalREN, 3)) + ' layer=' + str(Layer) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + '  place_status=fixed  )\n'
		sC		= '\t\t(pin name="' + self.PadBaseName + 'IN'  + sIndex + '"  offset=' + str(round(self.TerminalC, 3))   + ' layer=' + str(Layer) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + '  place_status=fixed   )\n'
		ss = [sI, sOEN, sREN, sC]
		return ss

# Create list of pads
pads = []	# Starts at #1 on the west side in the northern corner and proceeds counter clockwise

padNumber = 1
ports = [(1, 8), (2, 8), (3, 8), (4, 8), (5, 5)]	# (port number, number of pins in port)
for port in ports:
	portNum = port[0]
	pinsInPort = port[1]
	for i in range(pinsInPort):
		pad = PadPDUW16SDGZ_G('Prt' + str(portNum), index=i)
		pad.PadNumber = padNumber
		pads.append(pad)
		padNumber += 1

# Create LFXT pad
padClkLFXT = PadPDUW16SDGZ_G('ClkLFXT_')
padClkLFXT.PadNumber = padNumber
pads.append(padClkLFXT)
padNumber += 1

# Create HFXT pad
padClkHFXT = PadPDUW16SDGZ_G('ClkHFXT_')
padClkHFXT.PadNumber = padNumber
pads.append(padClkHFXT)
padNumber += 1

# Create resetn pad
padresetn = PadPDUW16SDGZ_G('resetn_')
padresetn.PadNumber = padNumber
pads.append(padresetn)
padNumber += 1



# Calculate pad positions
for pad in pads:
	padNumZeroIndex = pad.PadNumber - 1
	padIndexSideZeroIndex = padNumZeroIndex % PadsPerSide
	padOffset = FillOnSides + (padIndexSideZeroIndex * (FillBetweenPads + PadWidth))
	pad.CalculatePlacement(padOffset)



# Start the string
s = '(globals\n'
s += '\tversion = 3\n'
s += '\tio_order = counterclockwise\n'
s += ')\n\n'
s += '(iopin\n'

# Do the west side
s += '\t(west (locals space=' + str(Space) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + ')\n'

for i in range(PadsPerSide * 0, PadsPerSide * 1):
	if i >= len(pads):
		break
	pad = pads[i]
	terminalStrings = pad.GetTerminalStringsForGPIO()
	for terminalString in terminalStrings:
		s += terminalString
s += '\t)\n\n'

# Do the south side
s += '\t(south (locals space=' + str(Space) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + ')\n'

for i in range(PadsPerSide * 1, PadsPerSide * 2):
	if i >= len(pads):
		break
	pad = pads[i]
	terminalStrings = pad.GetTerminalStringsForGPIO()
	for terminalString in terminalStrings:
		s += terminalString
s += '\t)\n\n'

# Do the east side
s += '\t(east (locals space=' + str(Space) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + ')\n'

for i in range(PadsPerSide * 2, PadsPerSide * 3):
	if i >= len(pads):
		break
	pad = pads[i]
	terminalStrings = pad.GetTerminalStringsForGPIO()
	for terminalString in terminalStrings:
		s += terminalString
s += '\t)\n\n'

# Do the north side
s += '\t(north (locals space=' + str(Space) + ' width=' + str(PathWidth) + ' depth=' + str(Depth) + ')\n'

for i in range(PadsPerSide * 3, PadsPerSide * 4):
	if i >= len(pads):
		break
	pad = pads[i]
	terminalStrings = pad.GetTerminalStringsForGPIO()
	for terminalString in terminalStrings:
		s += terminalString
s += '\t)\n\n'


s += ')\n'

with open(outputFile, 'w', newline='\n') as f:
	f.write(s)

