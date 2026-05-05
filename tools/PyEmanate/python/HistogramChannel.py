#!/usr/bin/env python3

import os, pathlib, json, argparse
from datetime import datetime, timedelta
import matplotlib
from matplotlib import ticker
import matplotlib.pyplot as plt
#from matplotlib.figure import Figure
import numpy as np
from scipy.ndimage import gaussian_filter
from scipy.signal import savgol_filter, find_peaks

from HelperFunctions import *

class HistogramChannel():
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	# Config data
	DieID = None
	AfeName = None
	ClearCountsTimestamp = None
	PreviousRefreshTimestamp = None
	Timestamp = None
	NumBins = None
	MeasuredIsotopeAbundances = None	# A dict whose keys are the names of the isotopes (and Background) and values are the abundances of the isotopes. The abundance values are not necessarily normalized, but also have no meaningful units. Note that a 'Background' key should not be present in this dict unless the histogram contains only background counts (in this case, the value for the 'Background' key should be set to 1)
	Notes = None

	# Histogram Data
	Counts = None
	DnlBinCorrectionFactors = None

	# Calibration data: Energy(eV) = bin* + CalibratedYIntercept
	CalibratedScalingFactor = None	# aka "m" in y = m*x + b
	CalibratedYIntercept = None		# aka "b" in y = m*x + b

	# PMT data
	Scintillator = None		# The type of scintillator (NaI, LaBr, CsI, CLYC)
	PmtModelNumber = None	# Model number of the PMT (not unique to an individual PMT, but unique to its design)
	PmtSerialNumber = None	# Serial number of an individual PMT (unique to that individual PMT)
	PmtTaper = None			# Taper scheme
	PowerSupplyModelNumber = None	# Model number of the power supply (not unique to an individual power supply, but unique to its design. Benchtop HV or DPS)
	PowerSupplySerialNumber = None	# Serial number of an individual power supply (unique to that individual power supply)
	PowerSupplyVoltage = None		# Output voltage of power supply

	# Total Counts
	TotalCounts = None
	TotalCountsMinusFirstBin = None
	TotalCountsMinusLastBin = None
	TotalCountsMinusFirstAndLastBin = None

	# New Counts (since last refresh)
	NewCounts = None
	NewCountsMinusFirstBin = None
	NewCountsMinusLastBin = None
	NewCountsMinusFirstAndLastBin = None

	# Count Rates
	AverageCountsPerSecond = None
	AverageCountsPerSecondMinusFirstBin = None
	AverageCountsPerSecondMinusLastBin = None
	AverageCountsPerSecondMinusFirstAndLastBin = None

	CurrentCountsPerSecond = None
	CurrentCountsPerSecondMinusFirstBin = None
	CurrentCountsPerSecondMinusLastBin = None
	CurrentCountsPerSecondMinusFirstAndLastBin = None
	
	@property
	def TimestampStr(self):
		return get_string_timestamp(dt=self.Timestamp, includeSeconds=True)

	@staticmethod
	def CreateFromAFE(afe):
		h = HistogramChannel()
		h.DieID = None	# Must be set later!
		h.AfeName = afe.Name
		h.ClearCountsTimestamp = None
		h.PreviousRefreshTimestamp = None
		h.Timestamp = None
		h.NumBins = afe.NumBins
		h.MeasuredIsotopeAbundances = None
		h.ClearCounts()
		h.CalibratedScalingFactor = None
		h.CalibratedYIntercept = None
		h.TotalCounts = None
		h.TotalCountsMinusFirstBin = None
		h.TotalCountsMinusLastBin = None
		h.TotalCountsMinusFirstAndLastBin = None
		h.NewCounts = None
		h.NewCountsMinusFirstBin = None
		h.NewCountsMinusLastBin = None
		h.NewCountsMinusFirstAndLastBin = None
		h.AverageCountsPerSecond = None
		h.AverageCountsPerSecondMinusFirstBin = None
		h.AverageCountsPerSecondMinusLastBin = None
		h.AverageCountsPerSecondMinusFirstAndLastBin = None
		h.CurrentCountsPerSecond = None
		h.CurrentCountsPerSecondMinusFirstBin = None
		h.CurrentCountsPerSecondMinusLastBin = None
		h.CurrentCountsPerSecondMinusFirstAndLastBin = None
		return h
	
	@staticmethod
	def StandardizeIsotopeString(s, allowUnknown:bool=True):
		a = s.lower()
		if a in ['background', 'bkgnd', 'bkgd']:
			return 'Background'
		if a in ['ba133', 'ba-133', '133ba', 'barium 133', 'barium-133', '133barium']:
			return 'Ba-133'
		if a in ['co60', 'co-60', '60co', 'cobalt 60', 'cobalt-60', '60cobalt']:
			return 'Co-60'
		if a in ['cs137', 'cs-137', '137cs', 'cesium 137', 'cesium-137', '137cesium', 'caesium 137', 'caesium-137', '137caesium']:
			return 'Cs-137'
		if a in ['mn54', 'mn-54', '54mn', 'manganese 54', 'manganese-54', '54manganese']:
			return 'Mn-54'
		if a in ['na22', 'na-22', '22na', 'sodium 22', 'sodium-22', '22sodium']:
			return 'Na-22'
		if allowUnknown:
			return s
		return None
	
	@staticmethod
	def IsotopeStringToLatex(s):
		s = HistogramChannel.StandardizeIsotopeString(s, allowUnknown=False)
		if s == 'Background':
			return 'Bkgnd'
		if s == 'Ba-133':
			return '$^{133}$Ba'
		if s == 'Co-60':
			return '$^{60}$Co'
		if s == 'Cs-137':
			return '$^{137}$Cs'
		if s == 'Mn-54':
			return '$^{54}$Mn'
		if s == 'Na-22':
			return '$^{22}$Na'
	
	def Copy(self):
		h = HistogramChannel()

		h.DieID = self.DieID
		h.AfeName = self.AfeName
		h.ClearCountsTimestamp = self.ClearCountsTimestamp
		h.PreviousRefreshTimestamp = self.PreviousRefreshTimestamp
		h.Timestamp = self.Timestamp
		h.NumBins = self.NumBins
		if self.MeasuredIsotopeAbundances is not None:
			h.MeasuredIsotopeAbundances = {}
			for e in self.MeasuredIsotopeAbundances:
				h.MeasuredIsotopeAbundances[e] = self.MeasuredIsotopeAbundances[e]
		h.Notes = self.Notes
		h.Counts = [c for c in self.Counts]
		h.AverageCountsPerSecond = self.AverageCountsPerSecond
		h.CurrentCountsPerSecond = self.CurrentCountsPerSecond
		h.CalibratedScalingFactor = self.CalibratedScalingFactor
		h.CalibratedYIntercept = self.CalibratedYIntercept
		h.Scintillator = self.Scintillator
		h.PmtModelNumber = self.PmtModelNumber
		h.PmtSerialNumber = self.PmtSerialNumber
		h.PmtTaper = self.PmtTaper
		h.PowerSupplyModelNumber = self.PowerSupplyModelNumber
		h.PowerSupplySerialNumber = self.PowerSupplySerialNumber
		h.PowerSupplyVoltage = self.PowerSupplyVoltage
		
		h.TotalCounts = self.TotalCounts
		h.TotalCountsMinusFirstBin = self.TotalCountsMinusFirstBin
		h.TotalCountsMinusLastBin = self.TotalCountsMinusLastBin
		h.TotalCountsMinusFirstAndLastBin = self.TotalCountsMinusFirstAndLastBin
		h.NewCounts = self.NewCounts
		h.NewCountsMinusFirstBin = self.NewCountsMinusFirstBin
		h.NewCountsMinusLastBin = self.NewCountsMinusLastBin
		h.NewCountsMinusFirstAndLastBin = self.NewCountsMinusFirstAndLastBin
		h.AverageCountsPerSecond = self.AverageCountsPerSecond
		h.AverageCountsPerSecondMinusFirstBin = self.AverageCountsPerSecondMinusFirstBin
		h.AverageCountsPerSecondMinusLastBin = self.AverageCountsPerSecondMinusLastBin
		h.AverageCountsPerSecondMinusFirstAndLastBin = self.AverageCountsPerSecondMinusFirstAndLastBin
		h.CurrentCountsPerSecond = self.CurrentCountsPerSecond
		h.CurrentCountsPerSecondMinusFirstBin = self.CurrentCountsPerSecondMinusFirstBin
		h.CurrentCountsPerSecondMinusLastBin = self.CurrentCountsPerSecondMinusLastBin
		h.CurrentCountsPerSecondMinusFirstAndLastBin = self.CurrentCountsPerSecondMinusFirstAndLastBin

		return h

	def SetCounts(self, newCounts):
		if len(newCounts) != self.NumBins:
			return False
		
		# Update timestamps
		self.PreviousRefreshTimestamp = self.Timestamp
		self.Timestamp = datetime.now()

		# Compute total counts
		totalCounts = sum(newCounts)
		totalCountsMinusFirstBin = totalCounts - newCounts[0]
		totalCountsMinusLastBin = totalCounts - newCounts[-1]
		totalCountsMinusFirstAndLastBin = totalCounts - newCounts[0] - newCounts[-1]

		# Update new counts
		if self.TotalCounts is None:
			self.NewCounts = totalCounts
			self.NewCountsMinusFirstBin = totalCountsMinusFirstBin
			self.NewCountsMinusLastBin = totalCountsMinusLastBin
			self.NewCountsMinusFirstAndLastBin = totalCountsMinusFirstAndLastBin
		else:
			self.NewCounts = totalCounts - self.TotalCounts
			self.NewCountsMinusFirstBin = totalCountsMinusFirstBin - self.TotalCountsMinusFirstBin
			self.NewCountsMinusLastBin = totalCountsMinusLastBin - self.TotalCountsMinusLastBin
			self.NewCountsMinusFirstAndLastBin = totalCountsMinusFirstAndLastBin - self.TotalCountsMinusFirstAndLastBin
		
		# Update total counts
		self.TotalCounts = totalCounts
		self.TotalCountsMinusFirstBin = totalCountsMinusFirstBin
		self.TotalCountsMinusLastBin = totalCountsMinusLastBin
		self.TotalCountsMinusFirstAndLastBin = totalCountsMinusFirstAndLastBin

		# Compute counts per second
		if self.ClearCountsTimestamp is not None and (self.Timestamp - self.ClearCountsTimestamp).total_seconds() > 0.01:
			timeDelta = (self.Timestamp - self.ClearCountsTimestamp).total_seconds()
			self.AverageCountsPerSecond = self.TotalCounts / timeDelta
			self.AverageCountsPerSecondMinusFirstBin = self.TotalCountsMinusFirstBin / timeDelta
			self.AverageCountsPerSecondMinusLastBin = self.TotalCountsMinusLastBin / timeDelta
			self.AverageCountsPerSecondMinusFirstAndLastBin = self.TotalCountsMinusFirstAndLastBin / timeDelta
		else:
			self.AverageCountsPerSecond = None
			self.AverageCountsPerSecondMinusFirstBin = None
			self.AverageCountsPerSecondMinusLastBin = None
			self.AverageCountsPerSecondMinusFirstAndLastBin = None

		if self.PreviousRefreshTimestamp is not None and (self.Timestamp - self.PreviousRefreshTimestamp).total_seconds() > 0.01:
			timeDelta = (self.Timestamp - self.PreviousRefreshTimestamp).total_seconds()
			self.CurrentCountsPerSecond = self.NewCounts / timeDelta
			self.CurrentCountsPerSecondMinusFirstBin = self.NewCountsMinusFirstBin / timeDelta
			self.CurrentCountsPerSecondMinusLastBin = self.NewCountsMinusLastBin / timeDelta
			self.CurrentCountsPerSecondMinusFirstAndLastBin = self.NewCountsMinusFirstAndLastBin / timeDelta
		else:
			self.CurrentCountsPerSecond = None
			self.CurrentCountsPerSecondMinusFirstBin = None
			self.CurrentCountsPerSecondMinusLastBin = None
			self.CurrentCountsPerSecondMinusFirstAndLastBin = None
		
		# Update the counts
		self.Counts = newCounts
		return True
	
	def ClearCounts(self):
		self.Counts = [0 for i in range(self.NumBins)]
		self.Timestamp = datetime.now()
		self.ClearCountsTimestamp = self.Timestamp
		self.PreviousRefreshTimestamp = None

		self.TotalCounts = None
		self.TotalCountsMinusFirstBin = None
		self.TotalCountsMinusLastBin = None
		self.TotalCountsMinusFirstAndLastBin = None
		self.NewCounts = None
		self.NewCountsMinusFirstBin = None
		self.NewCountsMinusLastBin = None
		self.NewCountsMinusFirstAndLastBin = None
		self.AverageCountsPerSecond = None
		self.AverageCountsPerSecondMinusFirstBin = None
		self.AverageCountsPerSecondMinusLastBin = None
		self.AverageCountsPerSecondMinusFirstAndLastBin = None
		self.CurrentCountsPerSecond = None
		self.CurrentCountsPerSecondMinusFirstBin = None
		self.CurrentCountsPerSecondMinusLastBin = None
		self.CurrentCountsPerSecondMinusFirstAndLastBin = None

		return
	
	def SetCountsFromBinFile(self, path:str, MSByteFirst=False):
		if not os.path.isfile(path):
			return False
		file_size = os.path.getsize(path)
		self.NumBins = file_size // 4
		
		bin_data = None
		with open(path, 'rb') as f:
			bin_data = f.read()
		
		hist = None
		if MSByteFirst:
			hist = [(bin_data[0 + i*4] << 24) | (bin_data[1 + i*4] << 16) | (bin_data[2 + i*4] << 8) | (bin_data[3 + i*4]) for i in range(self.NumBins)]
		else:
			hist = [(bin_data[0 + i*4]) | (bin_data[1 + i*4] << 8) | (bin_data[2 + i*4] << 16) | (bin_data[3 + i*4] << 24) for i in range(self.NumBins)]

		self.Counts = hist
		return True
	
	@staticmethod
	def CalculateCalibration(bin1:int, energy1:float, bin2:int=0, energy2:float=0):
		if bin1 == bin2:
			return None, None
		CalibratedScalingFactor = (energy1 - energy2) / (bin1 - bin2)
		CalibratedYIntercept = energy1 - CalibratedScalingFactor*bin1
		return CalibratedScalingFactor, CalibratedYIntercept

	def Calibrate(self, bin1, energy1, bin2=0, energy2=0):
		self.CalibratedScalingFactor, self.CalibratedYIntercept = self.CalculateCalibration(bin1, energy1, bin2, energy2)
		return self.CalibratedScalingFactor, self.CalibratedYIntercept
	
	def ClearCalibration(self):
		self.CalibratedScalingFactor = None
		self.CalibratedYIntercept = None
		return
	
	def GetHistogramDict(self, registerValues=None):
		d = {
			'Type': 'Histogram',
			'DieID': self.DieID,
			'AfeName': self.AfeName,
			'Timestamp': get_string_timestamp(includeSeconds=True, dt=self.Timestamp),
			'ClearCountsTimestamp': get_string_timestamp(includeSeconds=True, dt=self.ClearCountsTimestamp),
			'PreviousRefreshTimestamp': get_string_timestamp(includeSeconds=True, dt=self.PreviousRefreshTimestamp),
			'NumBins': self.NumBins,
			'MeasuredIsotopeAbundances': self.MeasuredIsotopeAbundances,
			'Scintillator': self.Scintillator,
			'PmtModelNumber': self.PmtModelNumber,
			'PmtSerialNumber': self.PmtSerialNumber,
			'PmtTaper': self.PmtTaper,
			'PowerSupplyModelNumber': self.PowerSupplyModelNumber,
			'PowerSupplySerialNumber': self.PowerSupplySerialNumber,
			'PowerSupplyVoltage': self.PowerSupplyVoltage,
			'TotalCounts': self.TotalCounts,
			'TotalCountsMinusFirstBin': self.TotalCountsMinusFirstBin,
			'TotalCountsMinusLastBin': self.TotalCountsMinusLastBin,
			'TotalCountsMinusFirstAndLastBin': self.TotalCountsMinusFirstAndLastBin,
			'NewCounts': self.NewCounts,
			'NewCountsMinusFirstBin': self.NewCountsMinusFirstBin,
			'NewCountsMinusLastBin': self.NewCountsMinusLastBin,
			'NewCountsMinusFirstAndLastBin': self.NewCountsMinusFirstAndLastBin,
			'AverageCountsPerSecond': self.AverageCountsPerSecond,
			'AverageCountsPerSecondMinusFirstBin': self.AverageCountsPerSecondMinusFirstBin,
			'AverageCountsPerSecondMinusLastBin': self.AverageCountsPerSecondMinusLastBin,
			'AverageCountsPerSecondMinusFirstAndLastBin': self.AverageCountsPerSecondMinusFirstAndLastBin,
			'CurrentCountsPerSecond': self.CurrentCountsPerSecond,
			'CurrentCountsPerSecondMinusFirstBin': self.CurrentCountsPerSecondMinusFirstBin,
			'CurrentCountsPerSecondMinusLastBin': self.CurrentCountsPerSecondMinusLastBin,
			'CurrentCountsPerSecondMinusFirstAndLastBin': self.CurrentCountsPerSecondMinusFirstAndLastBin,
			'Notes': self.Notes,
			'Counts': self.Counts,
			'CalibratedScalingFactor': None,
			'CalibratedYIntercept': None,
			'EnergyUnits': None
		}
		if (self.CalibratedScalingFactor is not None) and (self.CalibratedYIntercept is not None):
			d['CalibratedScalingFactor'] = self.CalibratedScalingFactor
			d['CalibratedYIntercept'] = self.CalibratedYIntercept
			d['EnergyUnits'] = 'eV'
		
		if self.DnlBinCorrectionFactors is not None:
			d['DnlBinCorrectionFactors'] = self.DnlBinCorrectionFactors
		
		if registerValues is not None and type(registerValues) == dict and 'Type' in registerValues and registerValues['Type'] == 'RegisterValues':
			d['RegisterValues'] = registerValues
		
		return d
	
	def SaveHistogramJson(self, outPath, registerValues=None):
		d = self.GetHistogramDict(registerValues=registerValues)
		with open(outPath, 'w', newline='\n') as f:
			#json.dump(d, f, indent='\t')
			json.dump(d, f)
		return True
	
	def SaveHistogramCsv(self, outPath, correctDnl:bool=False, smoothen:bool=False):
		s = ''

		# Counts
		if smoothen:
			counts = [max(0, int(round(x))) for x in self.SmoothenHistogram(showFirstBin=True, showLastBin=True, correctDnl=correctDnl)]
		elif correctDnl and (self.DnlBinCorrectionFactors is not None):
			counts = [int(round(x)) for x in self.GetDnlCorrectedCounts()]
		else:
			counts = self.Counts
		
		for b in counts:
			s += str(b) + '\n'
		
		# Metadata
		notes = None
		if type(notes) == str:
			notes = self.Notes.replace('\n', '\\n').replace('\r', '\\r')
		metadata = [
			['Type', 'Histogram'],
			['DieID', self.DieID],
			['AfeName', self.AfeName],
			['Timestamp', get_string_timestamp(includeSeconds=True, dt=self.Timestamp)],
			['ClearCountsTimestamp', get_string_timestamp(includeSeconds=True, dt=self.ClearCountsTimestamp)],
			['PreviousRefreshTimestamp', get_string_timestamp(includeSeconds=True, dt=self.PreviousRefreshTimestamp)],
			['NumBins', self.NumBins],
			['Scintillator', self.Scintillator],
			['PmtModelNumber', self.PmtModelNumber],
			['PmtSerialNumber', self.PmtSerialNumber],
			['PmtTaper', self.PmtTaper],
			['PowerSupplyModelNumber', self.PowerSupplyModelNumber],
			['PowerSupplySerialNumber', self.PowerSupplySerialNumber],
			['PowerSupplyVoltage', self.PmtModelNumber],
			['TotalCounts', self.TotalCounts],
			['TotalCountsMinusFirstBin', self.TotalCountsMinusFirstBin],
			['TotalCountsMinusLastBin', self.TotalCountsMinusLastBin],
			['TotalCountsMinusFirstAndLastBin', self.TotalCountsMinusFirstAndLastBin],
			['NewCounts', self.NewCounts],
			['NewCountsMinusFirstBin', self.NewCountsMinusFirstBin],
			['NewCountsMinusLastBin', self.NewCountsMinusLastBin],
			['NewCountsMinusFirstAndLastBin', self.NewCountsMinusFirstAndLastBin],
			['AverageCountsPerSecond', self.AverageCountsPerSecond],
			['AverageCountsPerSecondMinusFirstBin', self.AverageCountsPerSecondMinusFirstBin],
			['AverageCountsPerSecondMinusLastBin', self.AverageCountsPerSecondMinusLastBin],
			['AverageCountsPerSecondMinusFirstAndLastBin', self.AverageCountsPerSecondMinusFirstAndLastBin],
			['CurrentCountsPerSecond', self.CurrentCountsPerSecond],
			['CurrentCountsPerSecondMinusFirstBin', self.CurrentCountsPerSecondMinusFirstBin],
			['CurrentCountsPerSecondMinusLastBin', self.CurrentCountsPerSecondMinusLastBin],
			['CurrentCountsPerSecondMinusFirstAndLastBin', self.CurrentCountsPerSecondMinusFirstAndLastBin],
			['Notes', notes],
		]
		
		for line in metadata:
			s += '#' + line[0] + ': ' + str(line[1]) + '\n'
		
		# Write to file
		with open(outPath, 'w', newline='\n') as f:
			f.write(s)
		
		return True
	
	@staticmethod
	def CreateHistogramFromDict(d:dict):
		if 'Type' not in d or d['Type'] != 'Histogram':
			return None
		d.pop('Type')
		h = HistogramChannel()
		for k in d:
			h.__dict__[k] = d[k]
		if h.TotalCounts is None:
			h.TotalCounts = sum(h.Counts)
		if type(d['Timestamp']) == str:
			h.Timestamp = get_timestamp_from_string(d['Timestamp'])
			if 'ClearCountsTimestamp' in d:
				h.ClearCountsTimestamp = get_timestamp_from_string(d['ClearCountsTimestamp'])
			if 'PreviousRefreshTimestamp' in d:
				h.PreviousRefreshTimestamp = get_timestamp_from_string(d['PreviousRefreshTimestamp'])
		else:
			h.Timestamp = d.Timestamp
			if 'ClearCountsTimestamp' in d:
				h.ClearCountsTimestamp = d['ClearCountsTimestamp']
			if 'PreviousRefreshTimestamp' in d:
				h.PreviousRefreshTimestamp = d['PreviousRefreshTimestamp']
		return h
	
	@staticmethod
	def CreateHistogramFromJson(jsonPath:str):
		d = None
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		if d is None:
			return None
		return HistogramChannel.CreateHistogramFromDict(d)

	def GetCalibratedEnergy(self, binNum):
		if self.CalibratedScalingFactor is None or self.CalibratedYIntercept is None:
			return None
		return binNum * self.CalibratedScalingFactor + self.CalibratedYIntercept
	
	def GetCalibratedEnergyArray(self):
		if self.CalibratedScalingFactor is None or self.CalibratedYIntercept is None:
			return None
		return [self.GetCalibratedEnergy(x) for x in range(self.NumBins)]
	
	def LoadPgfPlotStyle(self, plt, mplstylePath=None):
		if mplstylePath is None:
			mplstylePath = self.ThisFileDirectory + '/pgf.mplstyle'
		plt.style.use(mplstylePath)
		#matplotlib.style.use(self.ThisFileDirectory + '/pgf.mplstyle')
		return

	def PlotHistogram(self, figure, plotType:str='line', log:bool=False, title=None, color='red', xlabel:str='Bin', xTickSpacing=None, grid:bool=True, useCalibration:bool=False, showFirstBin:bool=True, showLastBin:bool=True, correctDnl:bool=False, smooth:bool=False, showPeaks:bool=False, showPeakWidths:bool=False, clearFigure:bool=True, preserveZoom:bool=False, label=None, ymax=None):
		xlim = None
		if preserveZoom:
			xlim = figure.gca().get_xlim()
		
		# Create plot
		if clearFigure:
			figure.clear()
			ax = figure.add_subplot()
			ax.clear()
		else:
			ax = figure.get_axes()
			if len(ax) == 1:
				ax = ax[0]
			else:
				figure.clear()
				ax = figure.add_subplot()
				ax.clear()

		# Optionally smooth the histogram and optionally correct the bins for DNL
		if smooth:
			y = self.SmoothenHistogram(showFirstBin=showFirstBin, showLastBin=showLastBin, correctDnl=correctDnl)
		elif correctDnl and (self.DnlBinCorrectionFactors is not None):
			y = self.GetDnlCorrectedCounts()
		else:
			y = [x for x in self.Counts]

		x = None
		if useCalibration and self.CalibratedScalingFactor is not None and self.CalibratedYIntercept is not None:
			x = self.GetCalibratedEnergyArray()
			if 'keV' in xlabel:
				x = [xn / 1e3 for xn in x]
			elif 'MeV' in xlabel:
				x = [xn / 1e6 for xn in x]
		if x is None:
			useCalibration = False
			x = [i for i in range(self.NumBins)]
		
		if not showFirstBin:
			x = x[1:]
			y = y[1:]
		
		if not showLastBin:
			x = x[:-1]
			y = y[:-1]

		if log:
			for i, p in enumerate(y):
				if p <= 0:
					y[i] = 1
		
		plotType = plotType.lower()
		if plotType == 'line':
			if log:
				ax.semilogy(x, y, '-', color=color, label=label)
			else:
				ax.plot(x, y, '-', color=color, label=label)
		elif plotType == 'histogram' or plotType == 'bar':
			ax.bar(x, y, log=log, color=color, label=label)
		elif plotType == 'filled line':
			if log:
				ax.semilogy(x, y, 'r-', label=label)
				ax.fill_between(x, y, 1, color=color)
			else:
				ax.plot(x, y, 'r-', label=label)
				ax.fill_between(x, y, 0, color=color)
			
		ax.set_xlabel(xlabel)
		ax.set_ylabel('Counts')

		if grid:
			ax.grid(color='#d0d0d0', linestyle='-') # light gray
		else:
			ax.grid(False)
			ax.tick_params(top=True, right=True)
		
		if xlim is not None:
			# Use preserved x-axis limits
			ax.set_xlim(xlim[0], xlim[1])
		elif useCalibration and self.CalibratedScalingFactor is not None and self.CalibratedYIntercept is not None:
			ax.set_xlim(x[0], x[-1])
		else:
			ax.set_xlim(0, self.NumBins)
		
		ylimtop = ax.get_ylim()[1]
		if log:	
			ax.set_ylim(1, ylimtop)
		else:
			ax.set_ylim(0, ylimtop)
		
		if ymax is not None:
			ylim = list(ax.get_ylim())
			ylim[1] = ymax
			ax.set_ylim(ylim[0], ylim[1])
		
		if xTickSpacing is None:
			if useCalibration and self.CalibratedScalingFactor is not None and self.CalibratedYIntercept is not None:
				xTickSpacing = int((max(x) + 1) / 4)
			else:
				xTickSpacing = int(self.NumBins / 4)

		if useCalibration and self.CalibratedScalingFactor is not None and self.CalibratedYIntercept is not None:
			ax.set_xticks(range(0, int(max(x) + 2), xTickSpacing))
		else:
			ax.set_xticks(range(0, int(self.NumBins + 1), xTickSpacing))
		
		if title is not None:
			matplotlib.rcParams['figure.subplot.top'] = 0.9
			figure.suptitle(title)
		
		if log:
			ax.yaxis.set_major_formatter(ticker.LogFormatterMathtext())
		else:
			formatter = ticker.ScalarFormatter(useMathText=True)
			formatter.set_powerlimits([-3, 4]) # Use scientific notation if y becomes >= 10^4 or <= 10^-3
			ax.yaxis.set_major_formatter(formatter)

		# Plot peaks
		if showPeaks:
			peaks = self.FindPeaks()

			if peaks is not None:
				ymin, ymax = ax.get_ylim()

				# Plot peak widths
				if showPeakWidths:
					for peak in peaks:
						minbin = peak['FwhmLeftBound']
						maxbin = peak['FwhmRightBound']
						ax.fill_between(x[minbin:maxbin + 1], y[minbin:maxbin + 1], color='g', alpha=0.1)

				for peak in peaks:
					ax.vlines(peak['PeakMaxBin'], ymin, ymax, colors='g', linestyles='solid')

		return ax
	
	def SaveHistogramPlot(self, outPath:str, plotType:str='line', log:bool=False, title=None, xlabel:str='Bin', xTickSpacing=None, grid:bool=True, useCalibration:bool=False, showFirstBin:bool=True, showLastBin:bool=True, correctDnl:bool=False, smooth:bool=False, mplstylePath=None):
		#figure = Figure()
		self.LoadPgfPlotStyle(plt, mplstylePath=mplstylePath)
		figure = plt.gcf()
		self.PlotHistogram(figure, plotType=plotType, log=log, title=title, xlabel=xlabel, xTickSpacing=xTickSpacing, grid=grid, useCalibration=useCalibration, showFirstBin=showFirstBin, showLastBin=showLastBin, correctDnl=correctDnl, smooth=smooth)
		figure.savefig(outPath)
		figure.clear()
		#figure = None
		return
	
	def SmoothenHistogram(self, showFirstBin:bool=False, showLastBin:bool=False, sigma=3, correctDnl:bool=False):
		if correctDnl and (self.DnlBinCorrectionFactors is not None):
			counts = self.GetDnlCorrectedCounts()
		else:
			counts = [c for c in self.Counts]
		if not showFirstBin:
			counts[0] = counts[1]
		if not showLastBin:
			counts[-1] = counts[-2]

		#smoothedHist = gaussian_filter(counts, sigma=sigma)
		try:
			smoothedHist = savgol_filter(counts, 21, 7)
		except:
			return None
		return smoothedHist
	
	def CalculatePeakResolution(self):
		# This is designed to calculate the resolution of an energy histogram of Cs-137 alone. It smoothens the histogram, finds the bin with the largest number of counts (which is assumed to be the Cs-137 photopeak), and uses it to calculate resolution and FWHM

		# Smoothen the histogram
		smoothedHist = self.SmoothenHistogram(showFirstBin=False, showLastBin=False, correctDnl=True)
		if smoothedHist is None:
			return None
		
		# Find the Cs-137 photopeak, ignoring the bottom 1/8th of the histogram, which contains the X-ray peak and is likely larger than the photopeak
		truncatedSmoothedHist = [b for b in smoothedHist]
		for i in range(self.NumBins // 8):
			truncatedSmoothedHist[i] = 0
		peakBin = np.argmax(smoothedHist)
		peakCounts = smoothedHist[peakBin]
		halfMaximum = peakCounts / 2

		# Find the left half-maximum bin
		leftHMBin = None
		for i in reversed(range(0, peakBin)):
			if smoothedHist[i] < halfMaximum:
				leftHMBin = i
				break
		if leftHMBin is None:
			return None, None, None, None, None
		
		# Estimate the actual point where the half maximum is between the leftHMBin and the bin to its right
		m = smoothedHist[leftHMBin + 1] - smoothedHist[leftHMBin]
		b = smoothedHist[leftHMBin] - m*leftHMBin
		leftHMBin = (halfMaximum - b) / m
		
		# Find the right half-maximum bin
		rightHMBin = None
		for i in range(peakBin + 1, self.NumBins):
			if smoothedHist[i] < halfMaximum:
				rightHMBin = i
				break
		if rightHMBin is None:
			return None, None, None, None, None
		
		# Estimate the actual point where the half maximum is between the rightHMBin and the bin to its left
		m = smoothedHist[rightHMBin] - smoothedHist[rightHMBin - 1]
		b = smoothedHist[rightHMBin] - m*rightHMBin
		rightHMBin = (halfMaximum - b) / m
		
		# Calculate FWHM
		FWHM = rightHMBin - leftHMBin

		# Calculate resolution
		# Pulse Height Resolution (PHR) = (rightHMBin - leftHMBin) / peakBin, according to https://psec.uchicago.edu/library/photomultipliers/Photonis_PMT_basics.pdf
		resolution = FWHM / peakBin

		return resolution, FWHM, peakBin, leftHMBin, rightHMBin
	
	def FindPeaks(self, maxPeakCount=None):
		# Smoothen the histogram
		smoothedHist = self.SmoothenHistogram(showFirstBin=False, showLastBin=False, correctDnl=True)
		if smoothedHist is None:
			return None

		# Get some info about the histogram
		maxheight = max(smoothedHist[1:-1])

		# Set up parameters
		min_height_proportion = 0.02
		distance_proportion = 0.02
		prominence_proportion = 0.02
		width_range_proportion = (0.0, 0.2)
		rel_height = 0.5

		# Find the peaks
		height = min_height_proportion * maxheight
		distance = distance_proportion * self.NumBins
		prominence = prominence_proportion * maxheight
		width = (width_range_proportion[0] * self.NumBins, width_range_proportion[1] * self.NumBins)

		peakCenters, properties = find_peaks(smoothedHist, height=height, distance=distance, prominence=prominence, width=width, rel_height=rel_height)

		# Select only peaks that have a calculatable FWHM
		peaks = []
		for i, peakCenter in enumerate(peakCenters):
			peakMaximum = smoothedHist[peakCenter]
			peakHalfMaximum = peakMaximum / 2

			# Calculate the half-maximum left bound
			leftPeakCenter = -1
			if i > 0:
				leftPeakCenter = peakCenters[i - 1]
			leftBound = None
			for j in reversed(range(leftPeakCenter + 1, peakCenter)):
				if smoothedHist[j] < peakHalfMaximum:
					leftBound = j
					break
			if leftBound is None:
				continue

			# Calculate the half-maximum right bound
			rightPeakCenter = self.NumBins
			if i < (len(peakCenters) - 1):
				rightPeakCenter = peakCenters[i + 1]
			rightBound = None
			for j in range(peakCenter, rightPeakCenter):
				if smoothedHist[j] < peakHalfMaximum:
					rightBound = j
					break
			if rightBound is None:
				continue

			# Interpolate the left bound
			m = smoothedHist[leftBound + 1] - smoothedHist[leftBound]
			b = smoothedHist[leftBound] - m*leftBound
			leftBoundInterpolated = (peakHalfMaximum - b) / m

			# Interpolate the right bound
			m = smoothedHist[rightBound] - smoothedHist[rightBound - 1]
			b = smoothedHist[rightBound] - m*rightBound
			rightBoundInterpolated = (peakHalfMaximum - b) / m

			# Calculate FWHM (in bins)
			FWHM = rightBoundInterpolated - leftBoundInterpolated

			# Calculate resolution
			# Pulse Height Resolution (PHR) = (rightHMBin - leftHMBin) / peakBin, according to https://psec.uchicago.edu/library/photomultipliers/Photonis_PMT_basics.pdf
			resolution = FWHM / peakCenter
			if self.CalibratedScalingFactor is not None and self.CalibratedYIntercept is not None:
				resolution = (self.GetCalibratedEnergy(rightBoundInterpolated) - self.GetCalibratedEnergy(leftBoundInterpolated)) / self.GetCalibratedEnergy(peakCenter)

			# Add to the list
			peaks.append({
				'PeakMaxBin': peakCenter,
				'SmoothedPeakMaxBinCounts': smoothedHist[peakCenter],
				'RawPeakMaxBinCounts': self.Counts[peakCenter],
				'FwhmLeftBound': leftBound + 1,
				'FwhmRightBound': rightBound - 1,
				'FwhmLeftBoundInterpolated': leftBoundInterpolated,
				'FwhmRightBoundInterpolated': rightBoundInterpolated,
				'FWHM': FWHM,
				'Resolution': resolution
			})
		
		# Sort by peak heights
		peaks.sort(key=lambda x: x['SmoothedPeakMaxBinCounts'], reverse=True)

		if type(maxPeakCount) == int and maxPeakCount > 0 and len(peaks) > maxPeakCount:
			# Return only the top maxPeakCount peaks
			peaks = peaks[:maxPeakCount]

		return peaks
	
	def LoadAdcDnlCorrectionFromJson(self, jsonPath:str, anyDieID=False):
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		if d is None or 'Type' not in d or d['Type'] != 'AdcCharacterization':
			return False
		return self.LoadAdcDnlCorrectionFromDict(d, anyDieID=anyDieID)
	
	def LoadAdcDnlCorrectionFromDict(self, d:dict, anyDieID=False):
		if 'Type' not in d or d['Type'] != 'AdcCharacterization':
			return False
		if (d['DieID'] != self.DieID) and not anyDieID:
			return False
		if 'AdcDatas' not in d or type(d['AdcDatas']) != list:
			return False
		
		# Search through the dictionary to find the appropriate AFE
		for adcData in d['AdcDatas']:
			# Is this the right AFE?
			afeName = 'AFE' + str(adcData['AfeIndex'])
			if afeName != self.AfeName:
				continue
			dnl = adcData['LinearityData']['DNL']
			if len(dnl) != self.NumBins:
				return False

			# Calculate the DNL correction factor
			# correction factor = 1 / (1 + DNL)
			dnlBinCorrectionDenominators = [1 + binDnl for binDnl in dnl]
			dnlBinCorrectionFactors = [1 / denom if denom > 0 else 1 for denom in dnlBinCorrectionDenominators]
			dnlBinCorrectionFactors[0] = 1
			dnlBinCorrectionFactors[-1] = 1
			self.DnlBinCorrectionFactors = dnlBinCorrectionFactors
			return True
		return False
	
	def GetDnlCorrectedCounts(self, minAllowedCorrectionFactor=0.1, maxAllowedCorrectionFactor=10, averageExtrema=True):
		if self.DnlBinCorrectionFactors is None:
			return None
		correctedCounts = [0 for i in range(self.NumBins)]
		for i in range(self.NumBins):
			correctionFactor = self.DnlBinCorrectionFactors[i]
			if minAllowedCorrectionFactor <= correctionFactor <= maxAllowedCorrectionFactor:
				correctedCounts[i] = self.Counts[i] * correctionFactor
			elif averageExtrema:
				if i == 0:
					correctedCounts[i] = self.Counts[i + 1]
				elif i == self.NumBins - 1:
					correctedCounts[i] = self.Counts[i - 1]
				else:
					correctedCounts[i] = int((self.Counts[i + 1] + self.Counts[i - 1]) / 2)
			else:
				correctedCounts[i] = self.Counts[i]
		return correctedCounts
	
	@staticmethod
	def ReBinSimple(counts, desiredHistogramBits:int=6, removeFirstBin:bool=True, removeLastBin:bool=True):
		numOutputBins = 2**desiredHistogramBits
		if (numOutputBins < 2) or (numOutputBins > len(counts)) or ((len(counts) % numOutputBins) != 0):
			return None
		rebinnedHist = [0 for i in range(numOutputBins)]
		newBinsPerOldBin = len(counts) // numOutputBins
		
		# Sum the many bins into one, skipping the "old" first and last bins
		start = 0
		if removeFirstBin:
			start = 1
		end = len(counts)
		if removeLastBin:
			end -= 1
		
		for i in range(start, end):
			rebinnedHist[i // newBinsPerOldBin] += counts[i]
		return rebinnedHist
	
	@staticmethod
	def GetNormalizedCountsForNPU(counts):
		maxval = max(counts)
		if maxval >= 32768:
			# The maximum value needs to be scaled down
			normalizingFactor = (maxval << 16) // 32767
			return [((c << 16) // normalizingFactor) for c in counts]
		elif maxval == 0:
			return counts
		else:
			# The maximum value needs to be scaled up
			normalizingFactor = 1073709056 // maxval	# 1073709056 = 32767 << 15
			return [((c * normalizingFactor) >> 15) for c in counts]








	
class HistogramCollection():
	Histograms = None
	Timestamp = None

	@staticmethod
	def LoadFromDict(d:dict):
		# Is this a Histogram or HistogramCollection?
		if 'Type' not in d:
			return None
		hc = HistogramCollection()
		if d['Type'] == 'Histogram':
			# It's just a single histogram
			hc.Histograms = [HistogramChannel.CreateHistogramFromDict(d)]
			if 'Timestamp' in d:
				hc.Timestamp = d['Timestamp']
			else:
				timestamps = sorted([h.Timestamp for h in hc.Histograms])
				if len(timestamps) > 0:
					hc.Timestamp = timestamps[-1]
			return hc
		if d['Type'] == 'Histograms':
			# It's a histogram collection
			hc.Histograms = [HistogramChannel.CreateHistogramFromDict(hd) for hd in d['Histograms']]
			if 'Timestamp' in d:
				hc.Timestamp = d['Timestamp']
			else:
				timestamps = sorted([h.Timestamp for h in hc.Histograms if h.Timestamp is not None])
				if len(timestamps) > 0:
					hc.Timestamp = timestamps[-1]
			return hc
		return None
	
	@staticmethod
	def LoadFromJson(jsonPath:str):
		d = None
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		return HistogramCollection.LoadFromDict(d)
	
	def SaveAsJson(self, jsonPath:str, registerValues=None):
		d = {'Type': 'Histograms', 'Timestamp': None, 'Histograms': []}
		if self.Timestamp is None:
			self.Timestamp = get_string_timestamp(includeSeconds=True)
		if all([h.Timestamp is not None for h in self.Histograms]):
			if self.Timestamp is None:
				timestamps = sorted([h.Timestamp for h in self.Histograms])
				if len(timestamps) > 0:
					self.Timestamp = timestamps[-1]
		if type(self.Timestamp) == datetime:
			self.Timestamp = get_string_timestamp(includeSeconds=True, dt=self.Timestamp)
		d = {'Type': 'Histograms', 'Timestamp': self.Timestamp, 'Histograms': []}
		for h in self.Histograms:
			d['Histograms'].append(h.GetHistogramDict())
		if registerValues is not None and type(registerValues) == dict and 'Type' in registerValues and registerValues['Type'] == 'RegisterValues':
			d['RegisterValues'] = registerValues
		with open(jsonPath, 'w',) as f:
			json.dump(d, f)
		return




if __name__ == "__main__":

	parser = argparse.ArgumentParser()

	parser.add_argument(
		'--input',
		'-i',
		type=str,
		default=None,
		help='The input histogram JSON file')
	
	parser.add_argument(
		'--output',
		'-o',
		type=str,
		default=None,
		help='The output file')
	
	parser.add_argument(
		'--adcCharacterization',
		type=str,
		default=None,
		help='The ADC characterization JSON file that will be used to correct the histogram DNL')
	
	parser.add_argument(
		'--showPlot',
		action='store_true',
		default=False,
		help='Show the histogram plot in a Matplotlib GUI'
	)

	parser.add_argument(
		'--log',
		action='store_true',
		default=False,
		help='Logarithmic plot'
	)

	parser.add_argument(
		'--useCalibration',
		action='store_true',
		default=False,
		help='Use the calibration data to plot'
	)

	parser.add_argument(
		'--correctDnl',
		action='store_true',
		default=False,
		help='Correct the DNL in the plot'
	)

	parser.add_argument(
		'--hideFirstBin',
		action='store_true',
		default=False,
		help='Hide the first bin'
	)

	parser.add_argument(
		'--hideLastBin',
		action='store_true',
		default=False,
		help='Hide the last bin'
	)

	parser.add_argument(
		'--smooth',
		action='store_true',
		default=False,
		help='Smoothen the histogram'
	)

	parser.add_argument(
		'--showPeaks',
		action='store_true',
		default=False,
		help='Show the peaks'
	)

	parser.add_argument(
		'--showPeakWidths',
		action='store_true',
		default=False,
		help='Show the peak widths'
	)

	parser.add_argument(
		'--title',
		type=str,
		default=None,
		help='The plot title')
	
	parser.add_argument(
		'--timestamp',
		type=str,
		default=None,
		help='Timestamp of the first histogram in the collection'
	)

	parser.add_argument(
		'--refreshPeriod',
		type=int,
		default=None,
		help='Time between each histogram, in seconds'
	)
	
	args = parser.parse_args()

	# Load the input file (could be either a HistogramChannel or HistogramCollection)
	if args.input is None:
		print('-i input file does not exist at', args.input)
		exit(-1)
	h = None
	if os.path.isfile(args.input):
		ext = args.input.lower()
		if ext.endswith('.json'):
			h = HistogramChannel.CreateHistogramFromJson(args.input)
			if type(h) != HistogramChannel:
				h = HistogramCollection.LoadFromJson(args.input)
				if type(h) != HistogramCollection:
					print('-i input file is not a vaild HistogramChannel or HistogramCollection at', args.input)
					exit(-1)
		elif ext.endswith('.bin'):
			h = HistogramChannel()
			h.SetCountsFromBinFile(args.input)
	elif os.path.isdir(args.input):
		# Open all .bin files in directory
		binFiles = [os.path.join(args.input, f) for f in os.listdir(args.input) if os.path.isfile(os.path.join(args.input, f)) and f.lower().endswith('.bin')]
		binFiles.sort()
		if len(binFiles) == 0:
			print('-i input directory contains no valid .BIN files at', args.input)
			exit(-1)

		h = HistogramCollection()
		h.Histograms = []
		if args.timestamp is not None:
			h.Timestamp = get_timestamp_from_string(args.timestamp)
		for i, binFile in enumerate(binFiles):
			hist = HistogramChannel()
			hist.SetCountsFromBinFile(binFile)
			if args.timestamp is not None and args.refreshPeriod is not None:
				hist.Timestamp = h.Timestamp + timedelta(seconds=((i + 1) * args.refreshPeriod))
				hist.ClearCountsTimestamp = h.Timestamp + timedelta(seconds=(i * args.refreshPeriod))
				hist.PreviousRefreshTimestamp = h.Timestamp + timedelta(seconds=(i * args.refreshPeriod))
			h.Histograms.append(hist)
		
	
	
	# Load the ADC Characterization file
	if args.adcCharacterization is not None:
		if type(h) == HistogramCollection:
			# HistogramCollection
			for hist in h.Histograms:
				if hist.LoadAdcDnlCorrectionFromJson(args.adcCharacterization) == False:
					print('Could not load ADC characterization file at', args.adcCharacterization)
					exit(-1)
		else:
			# HistogramChannel
			if h.LoadAdcDnlCorrectionFromJson(args.adcCharacterization) == False:
				print('Could not load ADC characterization file at', args.adcCharacterization)
				exit(-1)

	# Create a plot, if needed (only works for HistogramChannel)
	outputIsPlotFile = args.output is not None and (args.output.lower().endswith('.png') or args.output.lower().endswith('.pgf') or args.output.lower().endswith('.pdf') or args.output.lower().endswith('.eps'))

	figure = None
	if args.showPlot or outputIsPlotFile:
		histograms = []
		if type(h) == HistogramChannel:
			histograms = [h]
		elif type(h) == HistogramCollection:
			histograms = h.Histograms
		
		import matplotlib.pyplot as plt
		for hist in histograms:
			figure = plt.figure()
			plt.clf()
			xlabel = 'Bin'
			if args.useCalibration:
				xlabel = 'keV'
			
			hist.LoadPgfPlotStyle(plt)
			hist.PlotHistogram(figure, log=args.log, title=args.title, xlabel=xlabel, xTickSpacing=None, grid=True, useCalibration=args.useCalibration, showFirstBin=(not args.hideFirstBin), showLastBin=(not args.hideLastBin), correctDnl=args.correctDnl, smooth=args.smooth, showPeaks=args.showPeaks, showPeakWidths=args.showPeakWidths)

			if args.showPlot:
				plt.show()
	
	# Save the output file (if it is not a figure)
	if args.output is not None:
		if args.output.lower().endswith('.json'):
			if type(h) == HistogramChannel:
				registerValues = None
				if 'RegisterValues' in h.__dict__:
					registerValues = h.RegisterValues
				h.SaveHistogramJson(args.output, registerValues=registerValues)
			elif type(h) == HistogramCollection:
				registerValues = None
				if 'RegisterValues' in h.__dict__:
					registerValues = h.RegisterValues
				h.SaveAsJson(args.output, registerValues=registerValues)
		if args.output.lower().endswith('.csv'):
			if type(h) == HistogramChannel:
				h.SaveHistogramCsv(args.output, correctDnl=args.correctDnl, smoothen=args.smooth)
		if args.output.lower().endswith('.png') or args.output.lower().endswith('.pgf'):
			import matplotlib.pyplot as plt
			figure = plt.figure()
			xlabel = 'Bin'
			if args.useCalibration:
				xlabel = 'keV'
			
			h.LoadPgfPlotStyle(plt)
			h.PlotHistogram(figure, log=args.log, title=args.title, xlabel=xlabel, xTickSpacing=None, grid=True, useCalibration=args.useCalibration, showFirstBin=(not args.hideFirstBin), showLastBin=(not args.hideLastBin), correctDnl=args.correctDnl, smooth=args.smooth, showPeaks=args.showPeaks, showPeakWidths=args.showPeakWidths)

			plt.savefig(args.output)
	