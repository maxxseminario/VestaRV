#!/usr/bin/env python3

import sys, os, json, csv, argparse, pathlib
from time import sleep
from datetime import datetime
import numpy as np
from scipy.stats import linregress
from scipy.signal import savgol_filter
from progressbar import ProgressBar, Percentage, Bar, ETA	# progressbar2 (install with pip install progressbar2)

from matplotlib import pyplot as plt

from Chip import Chip, Board
#from UART import UART
from ForthInterface import ForthInterface
from HistogramChannel import HistogramChannel
from HelperFunctions import *

class AdcTest():
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	
	def MeasureAdc(self, forth:ForthInterface, dieIDSuffix:str, jsonOutPath=None):
		if checkDieID(dieIDSuffix) == False:
			print('Invalid Die ID')
			return None
		if len(dieIDSuffix) == 5:
			dieIDSuffix = dieIDSuffix[2:]
		dieID = forth.ActiveChip.IDChipPrefix + dieIDSuffix.upper()
		forth.ActiveChip.DieID = dieID
		
		# Create the output dict
		datetimeStr = get_string_timestamp(includeSeconds=True)
		d = {
			'Type': 'AdcMeasurement',
			'Timestamp': datetimeStr,
			'ChipName': forth.ActiveChip.Name,
			'DieID': dieID
		}
		
		# Reset the chip and boot into SPI flash mode
		t1 = datetime.now()
		forth.uart.Timeout = 0.5
		forth.SetBootToSpiFlash()
		forth.AssertReset()
		oldBaudrate = forth.uart.Baudrate
		forth.uart.Baudrate = 115200
		sleep(50e-3)
		forth.uart.FlushBuffers()
		forth.DeassertReset()
		
		# Try to read the header
		r = forth.uart.ReadUntil(forth.ActiveChip.Name + ' ADC testbench')
		if type(r) != str or len(r) == 0:
			print('ADC test program is not loaded into the SPI flash.')
			return None
		forth.uart.ReadLine()	# Discard the rest of the line
		
		# Receive the setup data
		r = forth.uart.ReadUntil('SetupBegin')
		if type(r) != str or len(r) == 0:
			print('Failed to read setup data pt 1')
			return None
		r = forth.uart.ReadLine()
		if type(r) != str or len(r) == 0:
			print('Failed to read setup data pt 2')
			return None
		
		r = forth.uart.ReadUntil('SetupEnd', stripTerminator=True)
		if type(r) != str or len(r) == 0:
			print('Failed to read setup data pt 3')
			return None
		
		# Parse the setup data
		lines = r.strip().split('\n')
		for i, line in enumerate(lines):
			lines[i] = line.strip().split(' ')
			if len(lines[i]) != 2:
				print('Setup line #' + str(i + 1) + ' does not have exactly two elements in it, separated by a space. It has ' + str(len(lines[i])))
				print('Line:', lines[i])
				return None
		
		for line in lines:
			key = line[0]
			valstr = line[1]
			if key == 'DAC_VRefP':
				d['DAC_VRefP'] = float(valstr)
			elif key == 'DAC_VRefM':
				d['DAC_VRefM'] = float(valstr)
			elif key == 'DAC_bits':
				d['DAC_bits'] = int(valstr)
			elif key == 'ADC_bits':
				d['ADC_bits'] = int(valstr)
			elif key == 'AfeAdcCp':
				d['AfeAdcCp'] = int(valstr)
			elif key == 'DacValueM':
				d['DacValueM'] = int(valstr)
			elif key == 'DacStepP':
				d['DacStepP'] = int(valstr)
			elif key == 'NumAdcs':
				d['NumAdcs'] = int(valstr)
		
		r = forth.uart.ReadLine()
		if type(r) != str or len(r) == 0:
			print('Failed to read setup data pt 4')
			return None
		
		'''
		# Receive the data
		print('Receiving data (this may take tens of seconds to several minutes, depending on how many ADCs are being tested, the step increment, and how many times each ADC samples a single step)...')
		forth.uart.Timeout = 1
		forth.uart.WriteLine('')	# Send any character to begin the test
		r = forth.uart.ReadUntil('Done')
		if type(r) != str or len(r) == 0:
			print(r)
			print('Could not receive data from the chip')
			return None
		'''
		
		# Receive the ADC data
		DacMaxValue = 2**d['DAC_bits']
		DacStepP = d['DacStepP']
		DataPointsPerAdc = DacMaxValue // DacStepP
		NumAdcs = d['NumAdcs']
		
		dacValueP = [None for i in range(DataPointsPerAdc)]
		adcData = [[None for i in range(DataPointsPerAdc)] for j in range(NumAdcs)]
		
		d['DacValueP'] = dacValueP
		d['AdcData'] = adcData
		
		forth.uart.Write('y')
		
		pbar = ProgressBar(widgets=['Testing ADCs: ', Percentage(), ' ', Bar(), ' ', ETA()])
		for i in pbar(range(DataPointsPerAdc)):
			# Try multiple times to receive the line
			tries = 10
			while tries > 0:
				# Read the correct number of bytes (2 bytes for DacValueP, 2 * NumAdcs bytes for the ADC data, 2 bytes for the CRC) 
				numBytes = (2 * (1 + NumAdcs)) + 2
				r = forth.uart.ReadBytes(numBytes)
				if type(r) != bytes or len(r) != numBytes:
					# This line is bad, retry
					tries -= 1
					sleep(20e-3)
					forth.uart.Write('n')
					continue
				
				# Compute the CRC
				receivedCrc = int.from_bytes(r[-2:], byteorder='big')
				computedCrc = compute_CRC16_CDMA2000(r[:-2])
				
				if receivedCrc == computedCrc:
					# This line is good
					break
				
				# This line is bad, retry
				tries -= 1
				sleep(20e-3)
				forth.uart.Write('n')
				#print('len(r) =', len(r), 'r =', r, 'receivedCrc =', receivedCrc, 'computedCrc =', computedCrc)
			
			if tries == 0:
				print('Failed to read ADC data on line', i)
				return None
			
			# Signal the successful reception of the data
			forth.uart.Write('y')
			
			# Parse the data
			dacValueP[i] = int.from_bytes(r[:2], byteorder='big')
			if dacValueP[i] != (i * DacStepP):
				print('Unexpected DacValueP on line', i)
				return None
			r = r[2:-2]	# Clip off the dacValueP and the CRC
			for adcIndex in range(NumAdcs):
				adcData[adcIndex][i] = int.from_bytes(r[adcIndex * 2:2 + adcIndex * 2], byteorder='big')
			
		'''
		# Parse the header
		# The header line is between "DacValueP" and the next newline
		hstr = r[r.index('DacValueP '):]
		hstr = hstr[:hstr.index('\n')].strip()
		columnLabels = hstr.split(' ')
		numAdcs = len(columnLabels) - 1
		
		# Parse the column data
		# Column data is between the header line and "MissingCodes"
		cstr = r[r.index('DacValueP '):]
		cstr = cstr[cstr.index('\n'):]
		cstr = cstr[:cstr.index('MissingCodes')].strip()
		
		clines = cstr.split('\n')
		adcData = [[None for i in range(len(clines))] for j in range(numAdcs)]
		dacValueP = [None for i in range(len(clines))]
		for i, line in enumerate(clines):
			elements = line.strip().split(' ')
			if len(elements) != len(columnLabels):
				print('Data line #' + str(i + 1) + ' does not have the same number of elements as the header')
				return None
			dacValueP[i] = int(elements[0])
			for j in range(1, len(elements)):
				adcData[j - 1][i] = int(elements[j])
		
		d['AdcLabels'] = []
		d['DacValueP'] = dacValueP
		for i in range(1, len(columnLabels)):
			d['AdcLabels'].append(columnLabels[i])
		d['AdcData'] = adcData
		'''
		
		# Read the missing codes
		forth.uart.Timeout = 1
		r = forth.uart.ReadUntil('MissingCodesBegin')
		if type(r) != str or len(r) == 0:
			print('Failed to read missing codes data pt 1')
			return None
		r = forth.uart.ReadLine()
		if type(r) != str or len(r) == 0:
			print('Failed to read missing codes data pt 2')
			return None
		
		r = forth.uart.ReadUntil('MissingCodesEnd', stripTerminator=True)
		if type(r) != str or len(r) == 0:
			print('Failed to read missing codes data pt 3')
			return None
		
		# Parse the missing codes
		lines = r.strip().split('\n')
		if len(lines) != NumAdcs:
			print('There should be ' + str(NumAdcs) + ' lines for missing codes, but there are not')
			return None
		
		d['MissingCodeAdcBins'] = []
		for i, line in enumerate(lines):
			elements = line.strip().split(' ')
			if not elements[0].endswith(':'):
				print('Missing codes line does not begin with the ADC number')
				return None
			if int(elements[0][:-1]) != i:
				print('Missing codes has the wrong ADC number. Line', i, 'has ADC number', elements[0])
				return None
			d['MissingCodeAdcBins'].append([int(el) for el in elements[1:]])
		
		if jsonOutPath is None:
			# Generate an automatic file name
			csvOutDir = forth.ActiveChip.DataDirectory + '/AdcTest/' + dieID
			if not os.path.isdir(csvOutDir):
				os.makedirs(csvOutDir)
			jsonOutPath = csvOutDir + '/AdcMeasurement-' + dieID + '-' + datetimeStr + '.json'
		
		with open(jsonOutPath, 'w') as f:
			json.dump(d, f)
		
		t2 = datetime.now()
		print('ADC test took', (t2 - t1).total_seconds(), 'seconds')
		print('Saved measurement JSON to', jsonOutPath)
		
		return jsonOutPath
		
		'''
		# Parse the data
		# Find the setup data
		a = r[:r.index('DacValueP')].strip()
		setupData = a.split('\n')
		for i, line in enumerate(setupData):
			setupData[i] = setupData[i].strip().split(' ')
		
		# Parse the ADC data
		a = r[r.index('DacValueP'):]
		adcColumnLabels = a[:a.index('\n')].strip().split(' ')
		a = a[a.index('\n'):a.index('MissingCodes')].strip()
		adcData = a.split('\n')
		for i, line in enumerate(adcData):
			adcData[i] = [strToInt(element) for element in line.strip().split(' ')]
		
		# Parse the missing codes data
		a = r[r.index('MissingCodes'):]
		a = a[a.index('\n'):a.index('Done')].strip()
		allMissingCodes = a.split('\n')
		for i in range(len(allMissingCodes)):
			allMissingCodes[i] = allMissingCodes[i].strip().split(' ')
			if allMissingCodes[i][0] != 'Missing' + str(i):
				print('Error parsing missing codes')
				return False
			allMissingCodes[i][0] = 'MissingCodesAdc' + str(i)
		
		# Save the data
		datetimeStr = get_string_timestamp(includeSeconds=True)
		if csvOutPath is None:
			# Generate an automatic file name
			csvOutDir = forth.ActiveChip.DataDirectory + '/AdcTest/' + dieID
			if not os.path.isdir(csvOutDir):
				os.makedirs(csvOutDir)
			csvOutPath = csvOutDir + '/AdcMeasurement-' + dieID + '-' + datetimeStr + '.csv'
		
		with open(csvOutPath, 'w', newline='\n') as f:
			f.write('AdcMeasurement\n')
			f.write('DateTime,' + datetimeStr + '\n')
			f.write('DieID,' + dieID + '\n')
			
			wr = csv.writer(f, delimiter=',', quoting=csv.QUOTE_NONE)
			
			for row in setupData:
				wr.writerow(row)
			for row in allMissingCodes:
				wr.writerow(row)
			wr.writerow(adcColumnLabels)
			for row in adcData:
				wr.writerow(row)
		
		t2 = datetime.now()
		print('ADC test took', (t2 - t1).total_seconds(), 'seconds')
		print('Saved CSV to', csvOutPath)
		
		return csvOutPath
		'''
	
	def CharacterizeAdc(self, activeChip:Chip, jsonInPath:str, plot=False):
		# Load the data from the AdcMeasurement json file
		with open(jsonInPath, 'r') as f:
			d = json.load(f)
		
		if type(d) != dict or 'Type' not in d or d['Type'] != 'AdcMeasurement':
			print('Not a vaild ADC measurement file')
			return False
		
		if d['ChipName'] != activeChip.Name:
			print('The active chip (' + activeChip.Name + ') and the chip in the ADC measurement file (' + d['ChipName'] + ') differ. Is this file in the wrong chip directory?')
		
		# Unpack the setup data
		dieID = d['DieID'].upper()
		TimestampStr = d['Timestamp']
		DacVrefP = d['DAC_VRefP']
		DacVrefM = d['DAC_VRefM']
		DacBits = d['DAC_bits']
		AdcBits = d['ADC_bits']
		DacValueM = d['DacValueM']
		AfeAdcCp = d['AfeAdcCp']
		
		# Unpack the missing codes data
		missingCodes = d['MissingCodeAdcBins']
		
		# Unpack the ADC data
		dacValues = np.array(d['DacValueP'])
		dacVoltages = self.DacValueToVoltage(dacValues, DacBits, DacVrefP, DacVrefM)
		allAdcValues = [np.array(adcValues) for adcValues in d['AdcData']]
		
		
		'''
		# Load the data from the AdcMeasurement CSV file
		s = ''
		with open(csvInPath, 'r') as f:
			s = f.read()
		if not s.startswith('AdcMeasurement'):
			print('Not a vaild ADC measurement file')
			return False
		headerLines = s[s.index('\n'):s.index('MissingCodes')].strip().split('\n')
		for i, line in enumerate(headerLines):
			headerLines[i] = line.strip().split(',')
		headerDict = {line[0]: line[1] for line in headerLines}
		print(headerDict)
		
		# Parse the header data
		dieID = headerDict['DieID'].upper()
		DateTime = headerDict['DateTime']
		DacVrefP = float(headerDict['DAC_VRefP'])
		DacVrefM = float(headerDict['DAC_VRefM'])
		DacBits = int(headerDict['DAC_bits'])
		AdcBits = int(headerDict['ADC_bits'])
		DacValueM = int(headerDict['DacValueM'])
		AfeAdcCp = int(headerDict['AfeAdcCp'])
		
		if dieID[:2] != activeChip.IDChipPrefix:
			print('Invalid Chip ID prefix')
			return False
		
		# Parse the missing codes data
		missingCodesLines = s[s.index('MissingCodes'):s.index('DacValueP')].strip().split('\n')
		missingCodes = dict()
		for line in missingCodesLines:
			elements = line.split(',')
			if not elements[0].startswith('MissingCodesAdc'):
				print('Invalid missing codes data')
				return False
			adcNum = int(elements[0].replace('MissingCodesAdc', ''))
			codes = [int(code) for code in elements[1:]]
			missingCodes[adcNum] = codes
		
		# Parse the ADC data
		a = s[s.index('DacValueP'):]
		a = a[a.index('\n'):].strip()
		lines = a.split('\n')
		for i, line in enumerate(lines):
			lines[i] = [int(element) for element in line.split(',')]
		data = np.array(lines)
		print(data)
		dacValues = data[:, 0]
		dacVoltages = self.DacValueToVoltage(dacValues, DacBits, DacVrefP, DacVrefM)
		allAdcValues = [data[:, i] for i in range(1, data.shape[1])]
		'''
		
		# Get the voltage step increment for the DAC
		dacValuesDifferences = dacValues[1:] - dacValues[:-1]
		dacValuesDifferenceMax = np.max(dacValuesDifferences)
		dacValuesDifferenceMin = np.min(dacValuesDifferences)
		if dacValuesDifferenceMax != dacValuesDifferenceMin:
			print('The DAC voltage step is not uniform')
			return False
		dacValueStep = dacValuesDifferenceMax
		dacVoltageStep = self.DacValueToVoltage(dacValueStep, DacBits, DacVrefP, DacVrefM)
		
		outDir = activeChip.DataDirectory + '/AdcTest/' + dieID
		
		adcDatas = []
		
		# Process the ADC from each AFE
		for AfeIndex, adcValues in enumerate(allAdcValues):
			# Invert the DAC voltage to ADC value function. In other words, make a list of all associated DAC values for each ADC output
			dacValuesForEachAdcValue = [[] for i in range(2**AdcBits)]
			for i, adcValue in enumerate(adcValues):
				dacValue = dacValues[i]
				dacValuesForEachAdcValue[adcValue].append(dacValue)
			yAdcValues = np.arange(2**AdcBits, dtype=int)
			
			# Remove ADC bins with no DAC values associated. These are missing bins
			for i in reversed(range(len(dacValuesForEachAdcValue))):
				if len(dacValuesForEachAdcValue[i]) == 0:
					dacValuesForEachAdcValue = dacValuesForEachAdcValue[:i] + dacValuesForEachAdcValue[i+1:]
					yAdcValues = np.concatenate((yAdcValues[:i], yAdcValues[i+1:]))
			
			# Calculate the center of each ADC bin by averaging the DAC values associated with each ADC bin
			adcValueAverageDacValue = np.zeros((len(dacValuesForEachAdcValue)))
			for i in range(len(dacValuesForEachAdcValue)):
				adcValueAverageDacValue[i] = np.average(dacValuesForEachAdcValue[i])
			adcValueAverageDacVoltage = self.DacValueToVoltage(adcValueAverageDacValue, DacBits, DacVrefP, DacVrefM)
			
			if (len(adcValueAverageDacVoltage) <= 2) or (len(yAdcValues) <= 2):
				m, b, r2, pval, stderr = None, None, None, None, None
				xInt = None
				lsbVoltage = None
				inl = None
				dnl = None
				maxAbsDnl = None
			else:
				# Do a linear regression to find the idealized ADC characteristic for the bin centers. Exclude the first and last bin, as these are outliers
				m, b, r2, pval, stderr = linregress(adcValueAverageDacVoltage[1:-1], yAdcValues[1:-1])
				xInt = -b/m
				
				# Calculate the voltage of 1 LSB
				lsbVoltage = (((2**AdcBits - 1) - b) / m - xInt) / (2**AdcBits - 1)
				
				# Calculate INL using the ADC bin centers
				inl = ((((yAdcValues - b) / m) - adcValueAverageDacVoltage) / lsbVoltage)
				inl = inl.tolist()
				
				# Calculate the DNL by counting the number of DAC voltages fell into each ADC value. Missing codes automatically get a DNL of -1 (the lowist possible value)
				dnl = -1 * np.ones((2**AdcBits))
				for i in range(len(yAdcValues)):
					dnl[yAdcValues[i]] = ((len(dacValuesForEachAdcValue[i]) * dacVoltageStep) / lsbVoltage) - 1
				maxAbsDnl = np.max(np.abs(dnl[1:-1]))
				dnl = dnl.tolist()
			
			# Calculate the minimum and maximum voltages the ADC can handle
			minInputVoltage = None
			maxInputVoltage = None
			for i in range(len(adcValues)):
				if adcValues[i] > 0:
					if i > 0:
						i -= 1
					minInputVoltage = dacVoltages[i]
					break
			for i in reversed(range(len(adcValues))):
				if adcValues[i] > 0:
					if i < (len(adcValues) - 1):
						i += 1
					maxInputVoltage = dacVoltages[i]
					break
			
			# Gather the testing data into a dictionary
			adcData = {
				'AfeIndex': AfeIndex,
				'AdcBits': AdcBits,
				'TestedAfeAdcCp': AfeAdcCp,
				'LinearityData': {
					'm': m,
					'b': b,
					'xIntercept': xInt,
					'r2': r2,
					'pval': pval,
					'VLSB': lsbVoltage,
					'MinInputVoltage': minInputVoltage,
					'MaxInputVoltage': maxInputVoltage,
					'MaxAbsDnl': maxAbsDnl,
					'INL': inl,
					'DNL': dnl,
				},
				'MissingCodes': missingCodes[AfeIndex],
			}
			adcDatas.append(adcData)
			
			if plot:
				# Plot ADC transfer characteristic
				plt.style.use(self.ThisFileDirectory + '/pgf.mplstyle')
				
				plt.clf()	# clear figure
				if m is not None:
					fitLine, = plt.plot([xInt, DacVrefP], [0, m*DacVrefP + b], 'b-', label='Fit')
				measLine, = plt.plot(adcValueAverageDacVoltage[1:-1], yAdcValues[1:-1], 'r-', label='Measurement')
				plt.xlim([DacVrefM, DacVrefP])
				plt.ylim([0, 2**AdcBits])
				plt.yticks(np.arange(0, 2**AdcBits + 1, 2**AdcBits // 4))
				plt.xlabel('Input Voltage (V)')
				plt.ylabel('ADC Code')
				if m is not None:
					plt.legend(handles=[measLine, fitLine], loc='upper left')
				plt.grid()
				plt.savefig(outDir + '/AdcTransfer-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + TimestampStr + '.png')
				plt.savefig(outDir + '/AdcTransfer-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + TimestampStr + '.pgf')
				
				# Plot INL
				if inl is not None:
					plt.clf()	# clear figure
					plt.plot(yAdcValues[1:-1], inl[1:-1], 'r-')
					plt.xlim([0, 2**AdcBits])
					plt.xticks(np.arange(0, 2**AdcBits + 1, 2**AdcBits // 4))
					plt.xlabel('ADC Code')
					plt.ylabel('INL (LSB)')
					plt.grid()
					plt.savefig(outDir + '/AdcINL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + TimestampStr + '.png')
					plt.savefig(outDir + '/AdcINL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + TimestampStr + '.pgf')
				
				# Plot DNL
				if dnl is not None:
					plt.clf()	# clear figure
					plt.plot([i for i in range(1, 2**AdcBits - 1)], dnl[1:-1], 'r-')
					plt.xlim([0, 2**AdcBits])
					plt.xticks(np.arange(0, 2**AdcBits + 1, 2**AdcBits // 4))
					plt.xlabel('ADC Code')
					plt.ylabel('DNL (LSB)')
					plt.grid()
					plt.savefig(outDir + '/AdcDNL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + TimestampStr + '.png')
					plt.savefig(outDir + '/AdcDNL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + TimestampStr + '.pgf')
		
		# Save the ADC characteristics
		d = {
			'Type': 'AdcCharacterization',
			'DieID': dieID,
			'Timestamp': TimestampStr,
			'AdcDatas': adcDatas
		}
		
		with open(outDir + '/AdcCharacterization-' + dieID + '-' + TimestampStr + '.json', 'w', newline='\n') as f:
			json.dump(d, f)
		
		return True
			
	def CharacterizeUsingHistogram(self, activeChip:Chip, histogramJsonPath:str, triangleMinMax=None, plot=False):
		# Open the histogram
		h = HistogramChannel.CreateHistogramFromJson(histogramJsonPath)
		if h is None:
			print('Not a valid histogram file')
			return False
		
		if h.DieID[:2] != activeChip.IDChipPrefix:
			print('The active chip (' + activeChip.Name + ') and the chip in the ADC measurement file (' + h.DieID[:2] + ') differ. Is this file in the wrong chip directory?')
		
		dieID = h.DieID
		outDir = activeChip.DataDirectory + '/AdcTest/' + dieID
		
		# Copy the counts
		counts = [x for x in h.Counts]
		
		# Estimate the minimum and maximum voltages the ADC can measure in this range
		AdcVoltageLimits = None
		VLSB = None
		if triangleMinMax is not None:
			# Assumption: the percentage of counts of the whole contained in the first and last bins is each one's effective voltage distance from the triange wave limits
			pctLow = counts[0] / sum(counts)
			pctHigh = counts[-1] / sum(counts)
			
			triangleVoltageDifference = triangleMinMax[1] - triangleMinMax[0]
			AdcVoltageLimits = [triangleMinMax[0] + pctLow * triangleVoltageDifference, triangleMinMax[0] + (1 - pctHigh) * triangleVoltageDifference]
			
			VLSB = (AdcVoltageLimits[1] - AdcVoltageLimits[0]) / (h.NumBins - 1)

		# Replace the min and max bins with the inner bins average, since the min and max bins can often have many more counts than they should
		average_mid = np.average(counts[5:-5])
		counts[0] = average_mid
		counts[-1] = average_mid

		average = np.average(counts)
		total = np.sum(counts)

		# Find the baseline, which should be the ideal count for every bin. Filter twice to smooth the baseline further
		baseline_rough = savgol_filter(np.array(counts), 51, 7)
		baseline = savgol_filter(baseline_rough, 33, 3)

		# Calculate the DNL
		#dnl = [(counts[binNum] / baseline[binNum]) - 1 for binNum in range(len(counts))]	# uses moving baseline, not average
		dnl = [(counts[binNum] / average) - 1 for binNum in range(len(counts))]	# uses average, not moving baseline
		#maxAbsDnl = np.max(np.abs(dnl[1:-1]))
		worstPosDnlBin = int(np.argmax(dnl[1:-1]) + 1)
		worstPosDnl = dnl[worstPosDnlBin]
		worstNegDnlBin = int(np.argmin(dnl[1:-1]) + 1)
		worstNegDnl = dnl[worstNegDnlBin]

		# Calculate the missing codes
		missingCodes = [binNum for binNum in range(len(counts)) if counts[binNum] == 0]

		# Calculate the INL without using the moving baseline (use the average instead)
		inl = [0 for i in range(len(counts))]
		for i in range(1, len(counts)):
			bin_dnl = (counts[i] / average) - 1
			#bin_dnl = dnl[i]
			inl[i] = inl[i - 1] + bin_dnl
		
		# Calculate ADC transfer characteristic
		transferCharacteristic, m, b, r2, pval, xInt = None, None, None, None, None, None
		if triangleMinMax is not None:
			# Caluclate the transfer characteristic using the ADC voltage limits and the INL
			transferCharacteristic = np.linspace(AdcVoltageLimits[0], AdcVoltageLimits[1], h.NumBins) + VLSB * np.asarray(inl)
			
			m, b, r2, pval, stderr = linregress(transferCharacteristic, list(range(0, h.NumBins)))
			xInt = -b/m
		
		# Gather the testing data into a dictionary
		AdcBits = np.log2(h.NumBins)
		if np.abs(AdcBits - int(AdcBits)) > 1e-6:
			print('NumBits is not a power of 2')
			return False
		AdcBits = int(AdcBits)
		AfeIndex = int(h.AfeName[3:])
		
		adcData = {
			'AfeIndex': AfeIndex,
			'AdcBits': AdcBits,
			'MissingCodes': missingCodes,
			'TriangleWaveVoltageLimits': triangleMinMax,
			'LinearityData':
			{
				'AdcVoltageLimits': AdcVoltageLimits,
				'VLSB': VLSB,
				'm': m,
				'b': b,
				'xIntercept': xInt,
				'r2': r2,
				'pval': pval,
				'WorstPosDnl': worstPosDnl,
				'WorstPosDnlBin': worstPosDnlBin,
				'WorstNegDnl': worstNegDnl,
				'WorstNegDnlBin': worstNegDnlBin,
				'DNL': dnl,
				'INL': inl,
				'VoltageTransferCharacteristic': transferCharacteristic.tolist()
			}
		}

		# Save the ADC characteristics
		d = {
			'Type': 'AdcCharacterization',
			'DieID': dieID,
			'Timestamp': h.TimestampStr,
			'MeasurementType': 'HistogramWaveform',
			'AdcDatas': [adcData]
		}

		if not os.path.isdir(outDir):
			os.makedirs(outDir)
		
		fileName = 'AdcCharacterization-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.json'
		with open(outDir + '/' + fileName, 'w', newline='\n') as f:
			json.dump(d, f)

		if plot:
			plt.style.use(self.ThisFileDirectory + '/dissertation.mplstyle')
			
			# Plot INL
			if inl is not None:
				plt.clf()	# clear figure
				plt.plot([i for i in range(1, 2**AdcBits - 1)], inl[1:-1], 'r-')
				plt.xlim([0, 2**AdcBits])
				plt.xticks(np.arange(0, 2**AdcBits + 1, 2**AdcBits // 4))
				plt.xlabel('ADC Code')
				plt.ylabel('INL (LSB)')
				plt.grid()
				plt.savefig(outDir + '/AdcINL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.png')
				plt.savefig(outDir + '/AdcINL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.pgf')
			
			# Plot DNL
			if dnl is not None:
				plt.clf()	# clear figure
				plt.plot([i for i in range(1, 2**AdcBits - 1)], dnl[1:-1], 'r-', linewidth=0.5)
				plt.xlim([0, 2**AdcBits])
				plt.xticks(np.arange(0, 2**AdcBits + 1, 2**AdcBits // 4))
				plt.xlabel('ADC Code')
				plt.ylabel('DNL (LSB)')
				plt.grid()
				plt.savefig(outDir + '/AdcDNL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.png')
				plt.savefig(outDir + '/AdcDNL-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.pgf')
			
			if transferCharacteristic is not None:
				plt.clf()	# clear figure
				plt.plot([AdcVoltageLimits[0], AdcVoltageLimits[0]], [0, h.NumBins], 'k--')
				plt.plot([AdcVoltageLimits[1], AdcVoltageLimits[1]], [0, h.NumBins], 'k--')
				plt.annotate('{:.3f} V'.format(AdcVoltageLimits[0]), (AdcVoltageLimits[0], 0.9*h.NumBins), (AdcVoltageLimits[0] + .2, 0.9*h.NumBins), horizontalalignment='left', verticalalignment='center', arrowprops=dict(arrowstyle='->'))
				plt.annotate('{:.3f} V'.format(AdcVoltageLimits[1]), (AdcVoltageLimits[1], 0.1*h.NumBins), (AdcVoltageLimits[1] - .2, 0.1*h.NumBins), horizontalalignment='right', verticalalignment='center', arrowprops=dict(arrowstyle='->'))
				plt.text(1.25, 0.2 * h.NumBins, '$V_\\mathit{LSB} = ' + '{:.3f}$'.format(VLSB * 1000) + ' \\si{\\mV}', horizontalalignment='center', verticalalignment='center')
				plt.plot(transferCharacteristic, list(range(0, h.NumBins)), 'r-')
				plt.ylim([0, 2**AdcBits])
				plt.yticks(np.arange(0, 2**AdcBits + 1, 2**AdcBits // 4))
				plt.ylabel('ADC Code')
				plt.xlabel('Input Voltage (V)')
				plt.xlim([0, 2.5])
				plt.grid()
				plt.savefig(outDir + '/AdcVoltageTransferCharacteristic-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.png')
				plt.savefig(outDir + '/AdcVoltageTransferCharacteristic-' + dieID + '-' + 'AFE' + str(AfeIndex) + '-' + h.TimestampStr + '.pgf')
		
		return True
		
	def GenerateChipAdcStatistics(self, activeChip:Chip):
		# Get the chip AdcTest directory
		adcTestDir = activeChip.DataDirectory + '/AdcTest'

		# Get all subdirs in adcTestDir
		chipAdcDirs = [adcTestDir + '/' + d for d in os.listdir(adcTestDir) if os.path.isdir(adcTestDir + '/' + d)]
		
		# Open all of the ADC characterization JSON files as dictionaries and put them in a list
		dies = []
		for chipAdcDir in chipAdcDirs:
			# Get all JSON files
			jsonFiles = [chipAdcDir + '/' + f for f in os.listdir(chipAdcDir) if (os.path.isfile(chipAdcDir + '/' + f) and f.lower().endswith('.json'))]

			# Parse each JSON file and see if it is an ADC Characterization file
			thisDieAdcCharacterizations = []
			for jsonFile in jsonFiles:
				with open(jsonFile, 'r') as f:
					d = json.load(f)
				if (type(d) == dict) and (d['Type'] == 'AdcCharacterization'):
					# Add the ADC characterization dictionary to the list
					thisDieAdcCharacterizations.append(d)
			
			if len(thisDieAdcCharacterizations) == 0:
				continue
			
			# Get the most recent data collection for each AFE among all ADC characterization files
			dieAdcCharacterization = {
				'Type': "AdcCharacterization",
				'DieID': thisDieAdcCharacterizations[0]['DieID'],
				'Timestamp': None,
				'MeasurementType': 'HistogramWaveform',
				'AdcDatas': []
			}
			
			for afe in activeChip.AFEs:
				# Get all characterization files that include this AFE
				thisAfeAdcCharacterizations = []
				for adcCharacterization in thisDieAdcCharacterizations:
					#print(adcCharacterization['AdcDatas'])
					if afe.Index in [x['AfeIndex'] for x in adcCharacterization['AdcDatas']]:
						thisAfeAdcCharacterizations.append(adcCharacterization)
				
				# Sort by timestamp, pick the most recent one
				thisAfeAdcCharacterizations.sort(key = lambda d: d['Timestamp'])
				mostRecentAfeAdcCharacterization = thisAfeAdcCharacterizations[-1]
				
				# Add it to this die's master characterization
				for afeData in mostRecentAfeAdcCharacterization['AdcDatas']:
					if afeData['AfeIndex'] == afe.Index:
						dieAdcCharacterization['AdcDatas'].append(afeData)
						break
				if dieAdcCharacterization['Timestamp'] is None:
					dieAdcCharacterization['Timestamp'] = mostRecentAfeAdcCharacterization['Timestamp']
				elif mostRecentAfeAdcCharacterization['Timestamp'] < dieAdcCharacterization['Timestamp']:
					dieAdcCharacterization['Timestamp'] = mostRecentAfeAdcCharacterization['Timestamp']
			
			# Add to the list of dies
			dies.append(dieAdcCharacterization)
		
		# Get the stats for all ADCs
		avDnls = []
		allDnls = []
		worstPosDnls = []
		worstNegDnls = []
		scalingFactors = []
		yIntercepts = []
		minInputVoltages = []
		maxInputVoltages = []
		voltageRanges = []
		diesMissingCodes = []
		testedAdcs = []
		badAdcs = []
		
		dies.sort(key = lambda die: int(die['DieID'], 16))

		for die in dies:
			for adc in die['AdcDatas']:
				adcStr = die['DieID'] + ':AFE' + str(adc['AfeIndex']) + 'ADC'
				testedAdcs.append(adcStr)

				key = 'MissingCodes'
				if key in adc and adc[key] is not None:
					missingCodes = adc[key]

				adc = adc['LinearityData']

				"""
				if 'WorstPosDnl' in adc:
					worstPosDnl = adc['WorstPosDnl']
					if worstPosDnl is None:
						if 'm' not in adc or adc['m'] is None:
							badAdcs.append(adcStr)
					else:
						worstPosDnls.append(adc[key])
				elif 'm' not in adc or adc['m'] is None:
						badAdcs.append(adcStr)
				"""
				if 'DNL' not in adc or adc['DNL'] is None:
					badAdcs.append(adcStr)
					continue
					
				dnl = adc['DNL']
				
				if len(missingCodes) == len(dnl):
					badAdcs.append(adcStr)
					continue
				
				worstPosDnl = max(np.max(dnl[1:-1]), 0)
				worstNegDnl = min(np.min(dnl[1:-1]), 0)
				worstPosDnls.append(worstPosDnl)
				worstNegDnls.append(worstNegDnl)
				avDnls.append(np.average(dnl))
				allDnls.append(dnl[1:-1])
				diesMissingCodes.append(missingCodes)
			
				key = 'WorstNegDnl'
				if key in adc and adc[key] is not None:
					worstNegDnls.append(adc[key])
				
				key = 'm'
				if key in adc and adc[key] is not None:
					scalingFactors.append(adc[key])
				
				key = 'b'
				if key in adc and adc[key] is not None:
					yIntercepts.append(adc[key])
				
				key = 'AdcVoltageLimits'
				if key in adc and adc[key] is not None:
					minInputVoltages.append(adc[key][0])
					maxInputVoltages.append(adc[key][1])
					voltageRanges.append(adc[key][1] - adc[key][0])
		
		# Calculate statistics
		adcYield = 1 - (len(badAdcs) / len(testedAdcs))

		numMissingCodes = [len(l) for l in diesMissingCodes]

		meanWorstPosDnl		= np.average(worstPosDnls)
		meanWorstNegDnl		= np.average(worstNegDnls)
		meanNumMissingCodes	= np.average(numMissingCodes)
		if len(scalingFactors) > 0:
			meanScalingFactor	= np.average(scalingFactors)
			meanYIntercept		= np.average(yIntercepts)

		stdvWorstPosDnl		= np.std(worstPosDnls)
		stdvWorstNegDnl		= np.std(worstNegDnls)
		stdvNumMissingCodes	= np.std(numMissingCodes)
		if len(scalingFactors) > 0:
			stdvScalingFactor	= np.std(scalingFactors)
			stdvYIntercept		= np.std(yIntercepts)

		# y = m*x + b: y is ADC output code, x is input voltage. m has units of code/V, b has units of codes
		if len(scalingFactors) > 0:
			voltsPerBins = 1/np.array(scalingFactors)
			adcOffsetVoltages = -np.array(yIntercepts) / np.array(scalingFactors)

		numAdcsWithOneMissingCode = sum([1 for missingCodes in numMissingCodes if missingCodes > 0])

		# Get the output string
		s = 'ADC Statistics for ' + activeChip.Name + '\n'
		s += 'Number of dies tested: ' + str(len(dies)) + '\n'
		s += 'Number of ADCs tested: ' + str(len(testedAdcs)) + ' (There are multiple ADCs per chip. However, not all ADCs were necessarily tested on each chip)\n\n'

		s += 'ADC Yield: ' + str(len(testedAdcs) - len(badAdcs)) + '/' + str(len(testedAdcs)) + ' operational ADCs, ' + '{:.2f}%\n'.format(adcYield * 100)
		
		s += '\nDNL stats:\n'
		s += 'All ADC Bins DNL Stats: mean = {:.2e} LSB, std. dev. = {:.2f} LSB, min = {:.2f} LSB, max = {:.2f} LSB, RMS = {:.2f} LSB\n'.format(np.average(allDnls), np.std(allDnls), np.min(allDnls), np.max(allDnls), np.sqrt(np.mean(np.array(allDnls)**2)))
		s += 'Worst Positive DNL: mean = {:.2f} LSB, std. dev. = {:.2f} LSB, min = {:.2f} LSB, max = {:.2f} LSB\n'.format(np.average(worstPosDnls), np.std(worstPosDnls), np.min(worstPosDnls), np.max(worstPosDnls))
		s += 'Worst Negative DNL: mean = {:.2f} LSB, std. dev. = {:.2f} LSB, min = {:.2f} LSB, max = {:.2f} LSB\n'.format(np.average(worstNegDnls), np.std(worstNegDnls), np.min(worstNegDnls), np.max(worstNegDnls))
		
		if len(scalingFactors) > 0:
			s += '\nLinear fit stats:\n'
			s += 'Note: these stats can be easily adjusted by changing the ADC parasitic capacitance setting\n'
			s += 'LSB: mean = {:.3f} mV/bin, std. dev. = {:.3f} mV/bin, min = {:.3f} mV/bin, max = {:.3f} mV/bin\n'.format(1e3*np.average(voltsPerBins), 1e3*np.std(voltsPerBins), 1e3*np.min(voltsPerBins), 1e3*np.max(voltsPerBins))
			s += 'ADC Offset: mean = {:.2f} mV, std. dev. = {:.2f} mV, min = {:.2f} mV, max = {:.2f} mV\n'.format(1e3*np.average(adcOffsetVoltages), 1e3*np.std(adcOffsetVoltages), 1e3*np.min(adcOffsetVoltages), 1e3*np.max(adcOffsetVoltages))
		
		if len(voltageRanges) > 0:
			s += '\nInput voltage limit stats:\n'
			s += 'Minimum Input Voltage: mean {:.3f} V, std. dev. = {:.3f} V, min = {:.3f} V, max = {:.3f} V\n'.format(np.average(minInputVoltages), np.std(minInputVoltages), min(minInputVoltages), max(minInputVoltages))
			s += 'Maximum Input Voltage: mean {:.3f} V, std. dev. = {:.3f} V, min = {:.3f} V, max = {:.3f} V\n'.format(np.average(maxInputVoltages), np.std(maxInputVoltages), min(maxInputVoltages), max(maxInputVoltages))
			s += 'Input Voltage Range: mean {:.3f} V, std. dev. = {:.3f} V, min = {:.3f} V, max = {:.3f} V\n'.format(np.average(voltageRanges), np.std(voltageRanges), min(voltageRanges), max(voltageRanges))

		s += '\nNumber of missing codes per functioning ADC: mean = {:.2f} codes, std. dev. = {:.2f} codes, min = {:} codes, max = {:} codes\n'.format(np.average(numMissingCodes), np.std(numMissingCodes), np.min(numMissingCodes), np.max(numMissingCodes))
		s += 'Number of ADCs with at least one missing code: {:}/{:}, {:.2f}%\n' .format(numAdcsWithOneMissingCode, len(numMissingCodes), 100 * numAdcsWithOneMissingCode / len(numMissingCodes))
		
		s += '\nTested dies: ' + str([die['DieID'] for die in dies]) + '\n'

		# Write the output file
		outPath = adcTestDir + '/AdcStatisticsCondensed.txt'
		with open(outPath, 'w') as f:
			f.write(s)
		

		print('Yield:', len(testedAdcs) - len(badAdcs), '/', len(testedAdcs), '=', adcYield * 100, '%')
		print('Tested dies:', [die['DieID'] for die in dies])
		
		
		# Generate chip-wide ADC data spreadsheet
		outPath = adcTestDir + '/AllAdcStatistics.csv'
		with open(outPath, 'w') as f:
			f.write('#ADC statistics for ' + activeChip.Name + '\n')
			f.write('#Die ID, AFE Index, DNL mean (LSB), DNL std. dev. (LSB), Min DNL (LSB), Min DNL Bin, Max DNL (LSB), Max DNL Bin, DNL RMS (LSB), Num Missing Codes, VLSB (mV), m (bin/V), b (bin), xIntercept (V), r2, Voltage Input Min (V), Voltage Input Max (V), Voltage Range (V)\n')
			for die in dies:
				for adcData in die['AdcDatas']:
					linDat = adcData['LinearityData']
					data = []
					data.append(die['DieID'])
					data.append(adcData['AfeIndex'])
					data.append(np.mean(linDat['DNL'][1:-1]))
					data.append(np.std(linDat['DNL'][1:-1]))
					data.append(linDat['WorstNegDnl'])
					data.append(linDat['WorstNegDnlBin'])
					data.append(linDat['WorstPosDnl'])
					data.append(linDat['WorstPosDnlBin'])
					data.append(np.sqrt(np.mean(np.array(linDat['DNL'][1:-1])**2)))
					data.append(len(adcData['MissingCodes']))
					data.append(linDat['VLSB'] * 1000)
					data.append(linDat['m'])
					data.append(linDat['b'])
					data.append(linDat['xIntercept'])
					data.append(linDat['r2'])
					data.append(linDat['AdcVoltageLimits'][0])
					data.append(linDat['AdcVoltageLimits'][1])
					data.append(linDat['AdcVoltageLimits'][1] - linDat['AdcVoltageLimits'][0])
					
					s = ''
					for d in data:
						s += str(d) + ', '
					s = s[:-2] + '\n'
					f.write(s)
		return
		

	
	def DacValueToVoltage(self, dacValue, dacBits, VrefP, VrefM):
		return VrefM + (VrefP - VrefM) * dacValue / 2**dacBits
			

if __name__ == "__main__":
	
	parser = argparse.ArgumentParser()

	parser.add_argument(
		'--all',
		'-a',
		action='store_true',
		default=False,
		help='Measure and characterize')
		
	parser.add_argument(
		'--measure',
		'-m',
		action='store_true',
		default=False,
		help='Measure the ADC')

	parser.add_argument(
		'--characterizeFromDAC',
		default=None,
		help='Characterize the provided measurement file')
	
	parser.add_argument(
		'--characterizeFromHistogram',
		default=None,
		help='Characterize the provided measurement file')
	
	parser.add_argument(
		'--generateChipAdcStats',
		action='store_true',
		default=False,
		help='Generate chip-wide ADC measurement statistics')
	
	parser.add_argument(
		'--plot',
		'-p',
		default=False,
		action='store_true',
		help='Plot the INL, DNL, and linearity data'
	)
	
	parser.add_argument(
		'--triangleWaveMin',
		default=None,
		type=float)
	
	parser.add_argument(
		'--triangleWaveMax',
		default=None,
		type=float)

	parser.add_argument(
		'--DieID',
		'-i',
		type=str,
		default=None,
		help='The die ID of the chip')

	args = parser.parse_args()
		
	csvPath = None
	activeChip = None
	
	triangleMinMax = None
	if args.triangleWaveMin is not None and args.triangleWaveMax is not None:
		triangleMinMax = [args.triangleWaveMin, args.triangleWaveMax]
	
	# Measure
	if args.all or args.measure:
		# Check the die id
		if args.DieID is None:
			print('Please ensure all of the PMTx and ATPx switches are closed.')
			dieIDSuffix = input('Please enter the Die ID of this chip: ')
		else:
			dieIDSuffix = args.DieID
		if len(dieIDSuffix) == 5:
			dieIDSuffix = dieIDSuffix[2:]
		if len(dieIDSuffix) != 3:
			print('Invalid Die ID')
			exit()
		
		print('Connecting... ', end='')
		forth = ForthInterface()
		if not forth.InteractiveConnect(desiredBootMode='ROM'):
			print('Could not connect to serial port')
		print('Connected to ' + forth.ActiveChip.Name + ' on ' + str(forth.uart.Port))
		
		adc = AdcTest()
		csvPath = adc.MeasureAdc(forth, dieIDSuffix)
		if csvPath is None:
			exit()
		activeChip = forth.ActiveChip
		print('WARNING: Remember to open all of the PMTx and ATPx switches before using with a PMT!')
	
	# Characterize from DAC measurement file
	if args.all or (args.characterizeFromDAC is not None):
		if activeChip is None:
			activeChip = Chip.CreateFromPath(args.characterizeFromDAC)
		if activeChip is None:
			activeChip = Chip.InteractiveChipChooser()
		adc = AdcTest()
		adc.CharacterizeAdc(activeChip, args.characterizeFromDAC, plot=args.plot)
		print('Finished characterizing ADC from DAC measurement file')
	
	# Characterize from histogram file
	if args.characterizeFromHistogram is not None:
		if activeChip is None:
			activeChip = Chip.CreateFromPath(args.characterizeFromHistogram)
		if activeChip is None:
			activeChip = Chip.InteractiveChipChooser()
		adc = AdcTest()
		adc.CharacterizeUsingHistogram(activeChip, args.characterizeFromHistogram, triangleMinMax=triangleMinMax, plot=args.plot)
		print('Finished characterizing ADC from histogram')
	
	# Generate chip-wide ADC statistics
	if args.generateChipAdcStats:
		if activeChip is None:
			activeChip = Chip.InteractiveChipChooser()
		adc = AdcTest()
		adc.GenerateChipAdcStatistics(activeChip)
		print('Finished generating chip-wide ADC statistics for', activeChip.Name)

	