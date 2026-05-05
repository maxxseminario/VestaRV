#!/usr/bin/env python3

'''pinsForAnalog = [	# [name, number of pins, (optionally reversed boolean)]
	# From AFE
	['AdcCmpBar', 1],
	['CsaDip', 1],
	['ThreshCmp', 1],
	
	# To AFE (changing signals)
	['AdcActiveBar', 1],
	['AdcBufEn', 1],
	['AdcCDac', 10],
	['AdcCmpLatchBar', 1],
	['AdcMuxSel', 2],
	['AdcSampling', 1],
	['CMSHSel', 1],
	['CMSHTrack', 2],
	['CsaReset', 1],
	['EnPhaSH', 1],
	['EnPsdSH', 1],
	['InMuxSel', 1],
	['PhaTrack', 1],
	['PsdEarlyTrack', 1],
	['PsdLateTrack', 1],
	
	# AFE static configuration signals (only the outputs, which go the the AFE, are included here)
	['AdcCp_out', 7],
	['AdcRef_out', 14],
	['AtpBufEn_out', 1],
	['AtpSel_out', 4],
	['BaselineRstVEn_out', 1],
	['BaselineRstV_out', 14],
	['CMCC_out', 8],
	['CMEn_out', 1],
	['CMOutEn_out', 1],
	['CMSHRef_out', 14],
	['CS_out', 6],
	['Cfb_out', 8],
	['CsaCmAdjBar_out', 3],
	['CsaDipThresh_out', 14],
	['CsaDipThreshEn_out', 1],
	['CsaHCBP_out', 14],
	['CsaHCBPC_out', 14],
	['CsaHCBNC_out', 14],
	['CsaHCBN_out', 14],
	['CsaHCRef_out', 14],
	['CsaLCBiasAdj_out', 6],
	['CsaLCBP_out', 6],
	['CsaLCBN_out', 6],
	['CsaLCBNC_out', 6],
	['CsaLCFB_out', 6],
	['CsaLCRef_out', 6],
	['CMCCB_out', 1],
	['En_out', 1],
	['EnCsaHC_out', 1],
	['EnCsaLC_out', 1],
	['PeakSHRef_out', 14],
	['Rfb_out', 14],
	['Thresh_out', 14],
	['ThreshSel_out', 1]
]
'''

pinsForAnalog = [	# [name, number of pins, (optionally reversed boolean)]
	# From AFE
	['AdcCmpBar', 1],
	['CsaDip', 1],
	['ThreshCmp', 1],
	
	# Odd buses (and singleton signals) to AFE
	['AdcActiveBar', 1],
	['AdcBufEn', 1],
	['AdcCmpLatchBar', 1],
	['AdcSampling', 1],
	['CMSHSel', 1],
	['CsaReset', 1],
	['EnPhaSH', 1],
	['EnPsdSH', 1],
	['InMuxSel', 1],
	['PhaTrack', 1],
	['PsdEarlyTrack', 1],
	['PsdLateTrack', 1],
	['AdcCp_out', 7],
	['AtpBufEn_out', 1],
	['BaselineRstVEn_out', 1],
	['CMEn_out', 1],
	['CMOutEn_out', 1],
	['CsaCmAdjBar_out', 3],
	['CsaDipThreshEn_out', 1],
	['CMCCB_out', 1],
	['En_out', 1],
	['EnCsaHC_out', 1],
	['EnCsaLC_out', 1],
	['ThreshSel_out', 1],
	
	# Even buses to AFE
	['AdcCDac', 10],
	['AdcMuxSel', 2],
	['CMSHTrack', 2],
	['AdcRef_out', 14],
	['AtpSel_out',  4],
	['BaselineRstV_out', 14],
	['CMCC_out', 8],
	['CMSHRef_out', 14],
	['CS_out', 6],
	['Cfb_out', 8],
	['CsaDipThresh_out', 14],
	['CsaHCBP_out', 14],
	['CsaHCBPC_out', 14],
	['CsaHCBNC_out', 14],
	['CsaHCBN_out', 14],
	['CsaHCRef_out', 14],
	['CsaLCBiasAdj_out', 6],
	['CsaLCBP_out', 6],
	['CsaLCBN_out', 6],
	['CsaLCBNC_out', 6],
	['CsaLCFB_out', 6],
	['CsaLCRef_out', 6],
	['PeakSHRef_out', 14],
	['Rfb_out', 14],
	['Thresh_out', 14]
]

pinsForMCU = [	# [name, number of pins, (optionally reversed boolean)]
	# AFE static configuration signals (only the inputs which come from the MCU, are included here)
	['AdcCp', 7],
	['AdcRef', 14],
	['AtpBufEn', 1],
	['AtpSel', 4],
	['BaselineRstV', 14],
	['CMCC', 8],
	['CMOutEn', 1],
	['CMSHRef', 14],
	['CS', 6],
	['Cfb', 8],
	['CsaCmAdj', 3],
	['CsaDipThresh', 14],
	['CsaHCBP', 14],
	['CsaHCBPC', 14],
	['CsaHCBNC', 14],
	['CsaHCBN', 14],
	['CsaHCRef', 14],
	['CsaLCBiasAdj', 6],
	['CsaLCBP', 6],
	['CsaLCBN', 6],
	['CsaLCBNC', 6],
	['CsaLCFB', 6],
	['CsaLCRef', 6],
	['CMCCB', 1],
	['CsaSel', 1],
	['En', 1],
	['EnBaselineRst', 1],
	['EnCM', 1],
	['EnPsd', 1],
	['PeakSHRef', 14],
	['Rfb', 14],
	['Thresh', 14],
	['ThreshSel', 1],
	
	# MCU interface
	['resetn', 1],
	['ClkIn', 1],
	['RejectMode', 1],
	['CMSHClkDiv', 4],
	['EnCsaDip', 1],
	['CsaForceUnRst', 1],
	['CsaForceRst', 1],
	['CsaResetMin', 1],
	['CsaRstMode', 1],
	['ForcePhaTrack', 1],
	['DoPhaLast', 1],
	['SHPwrEvent', 1],
	['PhaIntTime', 16],
	['PsdEarlyIntTime', 16],
	['PsdLateIntTime', 16],
	['RejectTime', 16],
	['CsaResetTime', 8],
	['ForceTrigger', 1],
	['AdcClkDiv', 3],
	['AdcActive', 1],
	['AdcValueType', 2],
	['AdcData', 10],
	['AdcDataReady', 1],
	['AdcMuxTest', 1],
	['RstPulseCounts', 1],
	['TotalPulseCount', 32],
	['ValidPulseCount', 32],
	['DTP0Sel', 5],
	['DTP0', 1],
	['DTP1Sel', 5],
	['DTP1', 1]
]


def pinsToLines(pins, layer=2, width=0.1, depth=0.1, firstPinOffset=0, reversePins=False):
	# Both the width and the spacing are referenced to the center of the edge of each pin. For example, the empty space between the metal of the pins is spacing - width. The distance between the edge of the design and the metal of the first pin is offset - width/2
	lines = []

	firstPin = True
	iterPins = pins
	if reversePins:
		iterPins = reversed(pins)
	for pin in iterPins:
		pinName = pin[0]
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
				s += ' offset=' + str(firstPinOffset)
			firstPin = False
			s += ')'
			lines.append(s)
	return lines
	
# Do the pins to/from the analog circuits
lines = pinsToLines(pinsForAnalog, layer=2, width=0.1, depth=0.1, firstPinOffset=23.865)

print('There are', len(lines), 'digital pins that go to/from the analog circuits')
print('')
for line in lines:
	print('\t\t' + line)
	
# Do the pins to/from the MCU the analog circuits
lines = pinsToLines(pinsForMCU, layer=2, width=0.1, depth=0.1, firstPinOffset=11, reversePins=True)

print('')
print('')
print('')
print('')
print('There are', len(lines), 'digital pins that go to/from the MCU')
print('')
for line in lines:	# this is reversed because it is assumed that the pin direction is counter clockwise
	print('\t\t' + line)