#!/usr/bin/env python3

pinsForBiasGen = [	# [name, number of pins, (optionally reversed boolean)]
	# From left to right (cw)
	['EnBG', 1],
	['UseBiasDac', 1],
	['EnBiasBuf', 1],
	['UseExtBias', 1],
	['EnBiasGen', 1],
	[None, 1],
	['BiasAdj', 6],
	['BIASDBP', 14],
	['BIASDBPC', 14],
	['BIASDBNC', 14],
	['BIASDBN', 14]
]

pinsForAfe = [	# [name, number of pins, (optionally reversed boolean)]
	# From left to right (cw)
	['AdcCmpBar', 1],
	['BLDip', 1],
	['ThreshCmp', 1],
	['AdcActiveBar', 1],
	['AdcBufEn', 1],
	['AdcCmpLatchBar', 1],
	['AdcSampling', 1],
	['CMSHSel', 1],
	['CsaReset', 1],
	['EnPhaSH', 1],
	['EnPsdSH', 1],
	['CsaBiasSel', 1],
	['IntPha', 1],
	['IntPsdE', 1],
	['IntPsdL', 1],
	['Atp0BufEn', 1],
	['Atp1BufEn', 1],
	['EnCM', 1],
	['AdcCp', 7],
	['AdcMidSel', 1],
	['CsaCmAdjBar', 3],
	['EnBLLT', 1],
	['EnAdc', 1],
	['EnCsa', 1],
	['EnThresh', 1],
	['ThreshSel', 2],
	['AdcMuxSel', 2],
	['CMSHTrack', 2],
	['EnTGCM', 1],
	['EnTGCMByp', 1],
	['BufCMMid', 1],
	[None, 1],
	['ISink', 6],
	['CLPF', 6],
	['AdcCDac', 10],
	['AOFST', 14],
	['CMSHR', 14],
	['BLLT', 14],
	['CSABP', 14],
	['CSABPC', 14],
	['CSABNC', 14],
	['CSABN', 14],
	['CSAREF', 14],
	['RFB', 14],
	['THR', 14],
	['CFB', 8],
	['Atp0Sel', 4],
	['Atp1Sel', 4]
]

pinsForExtras = [	# [name, number of pins, (optionally reversed boolean)]
	# From left to right (cw)
	['Op0Cmp', 1],
	['Op1Cmp', 1],
	['TPMR', 4],
	['gmC0En', 1],
	['Op0PullDownOutput', 1],
	['Op0Sel', 1],
	['Buf0En', 1],
	['Buf0Short', 1],
	['Op0BiasSel', 1],
	['gmC1En', 1],
	['Op1PullDownOutput', 1],
	['Op1Sel', 1],
	['Buf1En', 1],
	['Buf1Short', 1],
	['Op1BiasSel', 1],
	['Cmp0EnBar', 1],
	['Cmp1EnBar', 1],
	['DAC0EN', 1],
	['DAC1EN', 1],
	['DAC0VAL', 14],
	['DAC1VAL', 14],
]

def pinsToLines(pins, layer=2, width=0.1, depth=0.1, firstPinOffset=0, reversePins=False, prefix=None, forcedOffsetSpacing=None):
	# Both the width and the spacing are referenced to the center of the edge of each pin. For example, the empty space between the metal of the pins is spacing - width. The distance between the edge of the design and the metal of the first pin is offset - width/2
	lines = []

	firstPin = True
	iterPins = pins
	pinNum = 0
	if reversePins:
		iterPins = reversed(pins)
	for pin in iterPins:
		pinName = pin[0]
		if pinName is None:
			pinNum += 1
			continue
		if prefix is not None:
			pinName = prefix + pinName
		busCount = pin[1]
		reverseBus = False
		if len(pin) >= 3:
			reverseBus = pin[2]
		
		iterBus = range(busCount)
		if reverseBus:
			iterBus = reversed(iterBus)
		if reversePins:
			iterBus = reversed(iterBus)
		
		for busNum in iterBus:
			s = '(pin name="' + pinName
			if busCount > 1:
				s += '[' + str(busNum) + ']'
			s += '" layer=' + str(layer) + ' width=' + str(width) + ' depth=' + str(depth)
			if firstPin == True and firstPinOffset > 0:
				s += ' offset=' + str(round(firstPinOffset, 3))
			elif forcedOffsetSpacing is not None:
				s += ' offset=' + str(round(firstPinOffset + (forcedOffsetSpacing * pinNum), 3))
			firstPin = False
			s += ')'
			lines.append(s)
			pinNum += 1
	return lines

# Set the widths
ChipWidth = 3000
ChipHeight = 3000
IOPadInset = 155
CoreWidth = ChipWidth - 2*IOPadInset
CoreHeight = ChipHeight - 2*IOPadInset
McuInset = 2
McuWidth = CoreWidth - 2*McuInset
McuHeight = CoreHeight - 2*McuInset - 20
McuX = IOPadInset + McuInset
McuY = IOPadInset + McuInset
McuOffsetFromLeft = IOPadInset + McuInset
McuOffsetFromRight = IOPadInset + McuInset
McuThinBarWidth = 91
McuThinBarHeight = 1185
AfeWidth = 355
AfeFirstPinOffsetFromLeft = 118.415
BiasGenWidth = 250
BiasGenFirstPinLocalOffsetFromLeft = 110.050
AFE0_X = 250	# this is the X coordinate of AFE0 in the entire chip
AFE3_X = 1665	# this is the X coordinate of AFE3 in the entire chip
BiasGen_X = 1375	# this is the X coordinate of the global bias generator in the entire chip
Extras_X = 1345
SpaceBetweenAnalogBlocks = 10
AnalogPinSpacing = 0.545

# Calculate the pin offsets
AfePinsFirstCenterToLastCenterWidth = (sum([pin[1] for pin in pinsForAfe]) - 1) * AnalogPinSpacing
BiasGenPinsFirstCenterToLastCenterWidth = (sum([pin[1] for pin in pinsForBiasGen]) - 1) * AnalogPinSpacing
ExtrasPinsFirstCenterToLastCenterWidth = (sum([pin[1] for pin in pinsForExtras]) - 1) * AnalogPinSpacing
AfePitch = AfeWidth + SpaceBetweenAnalogBlocks

AFE0FirstPinX = (AFE0_X + AfeFirstPinOffsetFromLeft) + (AfePitch * 0)
AFE1FirstPinX = (AFE0_X + AfeFirstPinOffsetFromLeft) + (AfePitch * 1)
AFE2FirstPinX = (AFE0_X + AfeFirstPinOffsetFromLeft) + (AfePitch * 2)

BiasGenFirstPinX = BiasGen_X + BiasGenFirstPinLocalOffsetFromLeft
ExtrasFirstPinX = Extras_X

AFE3FirstPinX = (AFE3_X + AfeFirstPinOffsetFromLeft) + (AfePitch * (3 - 3))
AFE4FirstPinX = (AFE3_X + AfeFirstPinOffsetFromLeft) + (AfePitch * (4 - 3))
AFE5FirstPinX = (AFE3_X + AfeFirstPinOffsetFromLeft) + (AfePitch * (5 - 3))

AFE0LastPinX = AFE0FirstPinX + AfePinsFirstCenterToLastCenterWidth
AFE1LastPinX = AFE1FirstPinX + AfePinsFirstCenterToLastCenterWidth
AFE2LastPinX = AFE2FirstPinX + AfePinsFirstCenterToLastCenterWidth
AFE3LastPinX = AFE3FirstPinX + AfePinsFirstCenterToLastCenterWidth
AFE4LastPinX = AFE4FirstPinX + AfePinsFirstCenterToLastCenterWidth
AFE5LastPinX = AFE5FirstPinX + AfePinsFirstCenterToLastCenterWidth
BiasGenLastPinX = BiasGenFirstPinX + BiasGenPinsFirstCenterToLastCenterWidth
ExtrasLastPinX = ExtrasFirstPinX + ExtrasPinsFirstCenterToLastCenterWidth

AFE0LastPinOffsetFromRight = ChipWidth - AFE0LastPinX - McuOffsetFromLeft - McuThinBarWidth
AFE1LastPinOffsetFromRight = ChipWidth - AFE1LastPinX - McuOffsetFromLeft - McuThinBarWidth
AFE2LastPinOffsetFromRight = ChipWidth - AFE2LastPinX - McuOffsetFromLeft - McuThinBarWidth
AFE3LastPinOffsetFromRight = ChipWidth - AFE3LastPinX - McuOffsetFromLeft - McuThinBarWidth
AFE4LastPinOffsetFromRight = ChipWidth - AFE4LastPinX - McuOffsetFromLeft - McuThinBarWidth
AFE5LastPinOffsetFromRight = ChipWidth - AFE5LastPinX - McuOffsetFromLeft - McuThinBarWidth
BiasGenLastPinOffsetFromRight = ChipWidth - BiasGenLastPinX - McuOffsetFromLeft - McuThinBarWidth
ExtrasLastPinOffsetFromRight = ChipWidth - ExtrasLastPinX - McuOffsetFromLeft - McuThinBarWidth



# Do the pins for the AFE3-5 (the MCU I/O pins are counter clockwise, while the AFE pins are clockwise)
linesAFE5 = pinsToLines(pinsForAfe, layer=2, width=0.1, depth=0.1, firstPinOffset=AFE5LastPinOffsetFromRight, reversePins=True, prefix='AFE5', forcedOffsetSpacing=0.545)
linesAFE4 = pinsToLines(pinsForAfe, layer=2, width=0.1, depth=0.1, firstPinOffset=AFE4LastPinOffsetFromRight, reversePins=True, prefix='AFE4', forcedOffsetSpacing=0.545)
linesAFE3 = pinsToLines(pinsForAfe, layer=2, width=0.1, depth=0.1, firstPinOffset=AFE3LastPinOffsetFromRight, reversePins=True, prefix='AFE3', forcedOffsetSpacing=0.545)

# Do the extra analog pins (the MCU I/O pins are counter clockwise, while these pins are clockwise)
linesExtras = pinsToLines(pinsForExtras, layer=2, width=0.1, depth=0.1, firstPinOffset=ExtrasLastPinOffsetFromRight, reversePins=True, forcedOffsetSpacing=0.545)

# Do the pins for the bias generator (the MCU I/O pins are counter clockwise, while the bias generator pins are clockwise)
linesBiasGen = pinsToLines(pinsForBiasGen, layer=2, width=0.1, depth=0.1, firstPinOffset=BiasGenLastPinOffsetFromRight, reversePins=True, forcedOffsetSpacing=0.545)

# Do the pins for the AFE0-2 (the MCU I/O pins are counter clockwise, while the AFE pins are clockwise)
linesAFE2 = pinsToLines(pinsForAfe, layer=2, width=0.1, depth=0.1, firstPinOffset=AFE2LastPinOffsetFromRight, reversePins=True, prefix='AFE2', forcedOffsetSpacing=0.545)
linesAFE1 = pinsToLines(pinsForAfe, layer=2, width=0.1, depth=0.1, firstPinOffset=AFE1LastPinOffsetFromRight, reversePins=True, prefix='AFE1', forcedOffsetSpacing=0.545)
linesAFE0 = pinsToLines(pinsForAfe, layer=2, width=0.1, depth=0.1, firstPinOffset=AFE0LastPinOffsetFromRight, reversePins=True, prefix='AFE0', forcedOffsetSpacing=0.545)



# Do the GPIO pins
# There are 67 digital I/O pads
# 25 go to the south side, leaving 21 on both the west and east sides
FirstPadOffsetChip = 288.95	# closest point from chip edge to closest edge of pad (not the center) following a ccw path
#FirstPadOffsetMcu = FirstPadOffsetChip - McuOffsetFromLeft
FirstPadOffsetMcuFromNorth = FirstPadOffsetChip - (ChipHeight - McuY - McuHeight)
FirstPadOffsetMcuFromWest = FirstPadOffsetChip - (ChipWidth - McuX - McuWidth)
FirstPadOffsetMcuFromSouth = FirstPadOffsetChip - (McuY)
PadToPadSpacing = 108.95

pinsForGpioWest = [	# 'name',
	'Prt3.7',
	None,
	'Prt4.0',
	None,
	'Prt4.2',
	None,
	'Prt4.4',
	None,
	'Prt4.5',
	'resetn_',
	'Prt4.6',
	'Prt1.0',
	'Prt5.1',
	'Prt1.1',
	'Prt5.3',
	'Prt1.2',
	'Prt5.4',
	'Prt1.3',
	'Prt5.5',
	'Prt1.4',
	'Prt5.6',
	'Prt1.5',
	'Prt5.7',
]
pinsForGpioSouth = [
	'Prt6.0',
	'Prt1.6',
	'Prt6.1',
	'Prt1.7',
	'Prt6.2',
	'Prt2.0',
	'Prt6.3',
	'Prt2.1',
	'Prt6.4',
	'Prt2.2',
	'Prt6.5',
	'Prt2.3',
	'Prt6.6',
	'Prt2.4',
	'Prt6.7',
	'Prt2.5',
	'Prt7.0',
	'Prt2.6',
	'Prt7.1',
	'Prt2.7',
	'Prt7.2',
	'Prt3.0',
	'Prt7.3',
]
pinsForGpioEast = [
	'Prt7.4',
	'Prt3.1',
	'Prt7.5',
	'Prt3.2',
	'Prt7.6',
	'Prt3.3',
	'Prt7.7',
	'Prt3.4',
	'Prt8.0',
	'Prt3.5',
	'Prt8.1',
	'Prt3.6',
	'Prt8.2',
	'Prt4.1',
	'Prt8.3',
	'Prt4.3',
	'Prt8.4',
	'Prt4.7',
	'Prt8.5',
	'Prt5.0',
	'Prt8.6',
	'Prt5.2',
	'Prt8.7',
]

def GpioPinsToLines(pins, firstPadOffset, layer=2, width=0.1, depth=0.1):
	terminalWidth = 2.77
	OUToffset = 0.995 + terminalWidth / 2
	DIRoffset = 11.59 + terminalWidth / 2
	RENoffset = 15.55 + terminalWidth / 2
	INoffset = 21.23 + terminalWidth / 2
	
	lines = []
	
	i = 0
	for pin in pins:
		pinName = pin
		if pinName is None:
			i += 1
			continue
		pinIndexer = None
		if '.' in pin:
			pinIndexer = int(pinName[pinName.index('.') + 1 :])
			pinName = pinName[:pinName.index('.')]
		
		for suffix in [('OUT', OUToffset), ('DIR', DIRoffset), ('REN', RENoffset), ('IN', INoffset)]:
			s = '(pin name="' + pinName + suffix[0]
			if pinIndexer is not None:
				s += '[' + str(pinIndexer) + ']'
			s += '"'
			
			s += ' layer=' + str(layer) + ' width=' + str(width) + ' depth=' + str(depth) + ' offset=' + str(round(firstPadOffset + suffix[1] + (i * PadToPadSpacing), 3))
			s += ' )'
			lines.append(s)
		i += 1
	return lines



linesWest = GpioPinsToLines(pinsForGpioWest, FirstPadOffsetMcuFromNorth)
linesSouth = GpioPinsToLines(pinsForGpioSouth, FirstPadOffsetMcuFromWest)
linesEast = GpioPinsToLines(pinsForGpioEast, FirstPadOffsetMcuFromSouth)


s = ''

# Add the header
s += '''(globals
	version = 3
	io_order = counterclockwise
)

(iopin
'''

# Do the north side, with all of the analog interface and bias generator pins
s += '\t(edge num = 3 (locals space=0.4)\n'

for line in linesAFE5:
	s += '\t\t' + line + '\n'
for line in linesAFE4:
	s += '\t\t' + line + '\n'
for line in linesAFE3:
	s += '\t\t' + line + '\n'

for line in linesBiasGen:
	s += '\t\t' + line + '\n'
for line in linesExtras:
	s += '\t\t' + line + '\n'
	
for line in linesAFE2:
	s += '\t\t' + line + '\n'
for line in linesAFE1:
	s += '\t\t' + line + '\n'
for line in linesAFE0:
	s += '\t\t' + line + '\n'
	
s += '\t)\n\n'


# Do the west side
s += '\t(edge num = 0 (locals space=1)\n'

for line in linesWest:
	s += '\t\t' + line + '\n'
s += '\t\t\n'

s += '\t)\n\n'

# Do the south side
s += '\t(edge num = 7 (locals space=1)\n'

for line in linesSouth:
	s += '\t\t' + line + '\n'

s += '\t)\n\n'

# Do the east side
s += '\t(edge num = 6 (locals space=1)\n'

for line in linesEast:
	s += '\t\t' + line + '\n'
s += '\t\t\n'

s += '\t)\n\n'

# Add the footer
s += ')\n'


# Save file
with open('MCU.io', 'w') as f:
	f.write(s)

print('There are', len(linesAFE0), 'pins in each AFE')
print('There are', len(linesBiasGen), 'pins in the bias gen')
#print('There are', len(linesGPIO), 'pins for the GPIO')
