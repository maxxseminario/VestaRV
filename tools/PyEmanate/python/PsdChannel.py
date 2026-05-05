#!/usr/bin/env python3

import os, pathlib, json, argparse
from datetime import datetime
from xml.etree.ElementInclude import include
import matplotlib
from matplotlib import ticker
import matplotlib.pyplot as plt
import matplotlib.colors as colors
#from matplotlib.figure import Figure
import numpy as np

from HelperFunctions import *

class PsdChannel():
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	# Config data
	DieID = None
	AfeName = None
	ClearDataTimestamp = None
	PreviousRefreshTimestamp = None
	Timestamp = None
	AdcBits = None
	MeasuredIsotopeAbundances = None	# A dict whose keys are the names of the isotopes (and Background) and values are the abundances of the isotopes. The abundance values are not necessarily normalized, but also have no meaningful units. Note that a 'Background' key should not be present in this dict unless the histogram contains only background counts (in this case, the value for the 'Background' key should be set to 1)
	Notes = None

	# PSD Data
	PsdDataPoints = []
	NumPsdDataPoints = None
	NumValidPsdDataPoints = None

	# PMT data
	Scintillator = None		# The type of scintillator (NaI, LaBr, CsI, CLYC)
	PmtModelNumber = None	# Model number of the PMT (not unique to an individual PMT, but unique to its design)
	PmtSerialNumber = None	# Serial number of an individual PMT (unique to that individual PMT)
	PmtTaper = None			# Taper scheme
	PowerSupplyModelNumber = None	# Model number of the power supply (not unique to an individual power supply, but unique to its design. Benchtop HV or DPS)
	PowerSupplySerialNumber = None	# Serial number of an individual power supply (unique to that individual power supply)
	PowerSupplyVoltage = None		# Output voltage of power supply
	
	@property
	def TimestampStr(self):
		return get_string_timestamp(dt=self.Timestamp, includeSeconds=True)
	
	@property
	def AllPsdRatios(self):
		return [PsdChannel.CalculatePsdRatio(dp[0], dp[1], allowNegativeRatios=True) for dp in self.PsdDataPoints]

	@property
	def ValidPsdRatios(self):
		a = [PsdChannel.CalculatePsdRatio(dp[0], dp[1], allowNegativeRatios=False) for dp in self.PsdDataPoints]
		return [r for r in a if r is not None]
	
	@staticmethod
	def CreateFromAFE(afe):
		p = PsdChannel()
		p.DieID = None	# Must be set later!
		p.AfeName = afe.Name
		p.ClearDataTimestamp = None
		p.PreviousRefreshTimestamp = None
		p.Timestamp = None
		p.AdcBits = afe.AdcBits
		p.MeasuredIsotopeAbundances = None
		p.ClearPsdData()
		return p
	
	@staticmethod
	def CalculatePsdRatio(early, late, allowNegativeRatios=False):
		if late > 0 and (allowNegativeRatios or (late - early) >= 0):
			return (late - early) / late
		return None

	def AppendPsdDataPoints(self, newPsdDataPoints):
		points = [None for i in range(len(newPsdDataPoints))]
		i = 0
		
		for dataPoint in newPsdDataPoints:
			if type(dataPoint) != list or not (2 <= len(dataPoint) <= 3):
				continue
			points[i] = dataPoint
			#print('Early =', dataPoint[0], 'Late =', dataPoint[1], 'Full =', dataPoint[2], 'Ratio =', self.CalculatePsdRatio(dataPoint[0], dataPoint[1], True))
			i += 1
		
		# Update timestamps
		self.PreviousRefreshTimestamp = self.Timestamp
		self.Timestamp = datetime.now()
		
		# Update the data points
		self.PsdDataPoints += points[:i]
		return
	
	def ClearPsdData(self):
		self.PsdDataPoints = []
		self.Timestamp = datetime.now()
		self.ClearDataTimestamp = self.Timestamp
		self.PreviousRefreshTimestamp = None

		return

	def GetValidData(self, psdDataPoints):
		return [dp for dp in psdDataPoints if dp[1] > 0 and (dp[1] - dp[0]) >= 0]
	
	def CalculateStats(self):
		validPsdDataPoints = self.GetValidData(self.PsdDataPoints)
		earlyValues = [dp[0] for dp in validPsdDataPoints]
		lateValues = [dp[1] for dp in validPsdDataPoints]
		fullValues = [dp[2] for dp in validPsdDataPoints]

		d = {
			'MinEarlyValues': min(earlyValues),
			'MaxEarlyValues': max(earlyValues),
			'MedianEarlyValues': np.median(earlyValues),
			'AverageEarlyValues': np.average(earlyValues),
			'StdDevEarlyValues': np.std(earlyValues),
			'MinLateValues': min(lateValues),
			'MaxLateValues': max(lateValues),
			'MedianLateValues': np.median(lateValues),
			'AverageLateValues': np.average(lateValues),
			'StdDevLateValues': np.std(lateValues),
		}

		return d
	
	def GetDict(self, registerValues=None):
		d = {
			'Type': 'PsdData',
			'DieID': self.DieID,
			'AfeName': self.AfeName,
			'Timestamp': get_string_timestamp(includeSeconds=True, dt=self.Timestamp),
			'ClearDataTimestamp': get_string_timestamp(includeSeconds=True, dt=self.ClearDataTimestamp),
			'PreviousRefreshTimestamp': get_string_timestamp(includeSeconds=True, dt=self.PreviousRefreshTimestamp),
			'AdcBits': self.AdcBits,
			'MeasuredIsotopeAbundances': self.MeasuredIsotopeAbundances,
			'Scintillator': self.Scintillator,
			'PmtModelNumber': self.PmtModelNumber,
			'PmtSerialNumber': self.PmtSerialNumber,
			'PmtTaper': self.PmtTaper,
			'PowerSupplyModelNumber': self.PowerSupplyModelNumber,
			'PowerSupplySerialNumber': self.PowerSupplySerialNumber,
			'PowerSupplyVoltage': self.PowerSupplyVoltage,
			'Notes': self.Notes,
			'PsdDataPointFormat': ['Early', 'Late', 'Full'],
			'PsdDataPoints': self.PsdDataPoints
		}

		if registerValues is not None and type(registerValues) == dict and 'Type' in registerValues and registerValues['Type'] == 'RegisterValues':
			d['RegisterValues'] = registerValues
		
		return d
	
	def SaveJson(self, outPath, registerValues=None):
		d = self.GetDict(registerValues=registerValues)
		with open(outPath, 'w', newline='\n') as f:
			json.dump(d, f)
		return True
	
	def SaveCsv(self, outPath, includeHeader=False):
		with open(outPath, 'w') as f:
			f.write('#Early,Late,Full\n')
			for dataPoint in self.PsdDataPoints:
				f.write(str(dataPoint[0]) + ',' + str(dataPoint[1]) + ',' + str(dataPoint[2]) + '\n')
		return True

	@staticmethod
	def CreateFromDict(d:dict):
		if 'Type' not in d or d['Type'] != 'PsdData':
			return None
		d.pop('Type')
		p = PsdChannel()
		for k in d:
			p.__dict__[k] = d[k]
		if type(d['Timestamp']) == str:
			p.Timestamp = get_timestamp_from_string(d['Timestamp'])
			if 'ClearDataTimestamp' in d:
				p.ClearDataTimestamp = get_timestamp_from_string(d['ClearDataTimestamp'])
			if 'PreviousRefreshTimestamp' in d:
				p.PreviousRefreshTimestamp = get_timestamp_from_string(d['PreviousRefreshTimestamp'])
		else:
			p.Timestamp = d.Timestamp
			if 'ClearDataTimestamp' in d:
				p.ClearDataTimestamp = d['ClearDataTimestamp']
			if 'PreviousRefreshTimestamp' in d:
				p.PreviousRefreshTimestamp = d['PreviousRefreshTimestamp']
		return p
	
	@staticmethod
	def CreateFromJson(jsonPath:str):
		d = None
		with open(jsonPath, 'r') as f:
			d = json.load(f)
		if d is None:
			return None
		return PsdChannel.CreateFromDict(d)
	
	def LoadPgfPlotStyle(self, plt, mplstylePath=None):
		if mplstylePath is None:
			mplstylePath = self.ThisFileDirectory + '/pgf.mplstyle'
		plt.style.use(mplstylePath)
		#matplotlib.style.use(self.ThisFileDirectory + '/pgf.mplstyle')
		return
	
	def GetHeatmapData(self, size=128):
		numRows, numCols = None, None
		if type(size) == int:
			numRows, numCols = size, size
		elif (type(size) == list or type(size) == tuple) and len(size) == 2 and type(size[0]) == int and type(size[1]) == int:
			numRows, numCols = size
		if type(numRows) != int or not (1 <= numRows <= 2**self.AdcBits):
			numRows = 2**self.AdcBits
		if type(numCols) != int or numCols < 1:
			numCols = 2**self.AdcBits
		
		# Filter the data points into a 2D histogram (heatmap)
		heatmap = np.zeros((numRows, numCols), dtype=int)

		numValidCounts = 0
		for dataPoint in self.PsdDataPoints:
			early = dataPoint[0]
			late = dataPoint[1]
			ratio = self.CalculatePsdRatio(early, late, allowNegativeRatios=False)
			if ratio is None or ratio < 0:
				continue
			if late is None:
				continue
			rowIndex = int(round((late / 2**self.AdcBits) * numRows))
			if not (0 <= rowIndex < numRows):
				continue
			colIndex = int(round(ratio * numCols))
			if not (0 <= colIndex < numCols):
				continue
			heatmap[rowIndex, colIndex] += 1
			numValidCounts += 1
		
		self.NumPsdDataPoints = len(self.PsdDataPoints)
		self.NumValidPsdDataPoints = numValidCounts
		
		b, a = np.meshgrid(np.linspace(0, 1, numRows), np.linspace(0, 2**self.AdcBits - 1, numCols))

		return a, b, heatmap

	def Plot(self, figure, title=None, log=False, grid=True, heatmapSize=128, smooth:bool=False, clearFigure:bool=True):
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

		a, b, heatmap = self.GetHeatmapData(size=heatmapSize)

		shading = 'auto'
		if smooth:
			shading = 'gouraud'
		
		#cmap = 'hot_r'
		#cmap = 'jet'
		#cmap = 'Greys'
		cmap = colors.LinearSegmentedColormap.from_list('', ['white', 'blue', 'green', 'yellow', 'orange', 'red'])

		norm = None
		vmin = 0
		if log:
			norm = colors.LogNorm(vmin=1, vmax=heatmap.max())
			vmin = None
		cbar = ax.pcolormesh(a, b, heatmap, norm=norm, cmap=cmap, vmin=vmin, shading=shading)
		figure.colorbar(cbar)

		# Axes
		ax.set_xlabel('Late Pulse Height')
		ax.set_ylabel('PSD Ratio')

		# Grid
		numBins = 2**self.AdcBits
		xTickSpacing = int(numBins / 4)
		ax.set_xticks(range(0, int(numBins + 1), xTickSpacing))

		if grid:
			ax.grid(color='#d0d0d0', linestyle='-') # light gray
			ax.set_axisbelow(False)
		else:
			ax.grid(False)
		
		if title is not None:
			matplotlib.rcParams['figure.subplot.top'] = 0.9
			figure.suptitle(title)

		return
	
	def SavePlot(self, outPath:str, title=None, log:bool=False, grid:bool=True, smooth:bool=False, mplstylePath=None):
		#figure = Figure()
		self.LoadPgfPlotStyle(plt, mplstylePath=mplstylePath)
		figure = plt.gcf()
		self.Plot(figure, title=title, grid=grid, smooth=smooth)
		figure.savefig(outPath)
		figure.clear()
		#figure = None
		return



if __name__ == "__main__":

	parser = argparse.ArgumentParser()

	parser.add_argument(
		'--input',
		'-i',
		type=str,
		default=None,
		help='The input PSD data JSON file')
	
	parser.add_argument(
		'--output',
		'-o',
		type=str,
		default=None,
		help='The output file')
	
	parser.add_argument(
		'--showPlot',
		action='store_true',
		default=False,
		help='Show the plot in a Matplotlib GUI'
	)

	parser.add_argument(
		'--log',
		action='store_true',
		default=False,
		help='Logarithmic plot'
	)

	parser.add_argument(
		'--smooth',
		action='store_true',
		default=False,
		help='Smoothen the histogram'
	)

	parser.add_argument(
		'--stats',
		action='store_true',
		default=False,
	)

	parser.add_argument(
		'--lateAdjust',
		type=int,
		default=0,
	)

	parser.add_argument(
		'--title',
		type=str,
		default=None,
		help='The plot title')
	
	args = parser.parse_args()

	# Load the input file
	if args.input is None or not os.path.isfile(args.input):
		print('-i input file does not exist at', args.input)
		exit(-1)
	
	p = PsdChannel.CreateFromJson(args.input)
	if type(p) != PsdChannel:
		print('-i input file is not a vaild PsdChannel at', args.input)
		exit(-1)
	
	# Do late adjust
	for i in range(len(p.PsdDataPoints)):
		p.PsdDataPoints[i][0] -= args.lateAdjust
		p.PsdDataPoints[i][1] -= args.lateAdjust
	
	# Create a plot, if needed
	outputIsPlotFile = args.output is not None and (args.output.lower().endswith('.png') or args.output.lower().endswith('.pgf') or args.output.lower().endswith('.pdf') or args.output.lower().endswith('.eps'))

	figure = None
	if args.showPlot or outputIsPlotFile:
		import matplotlib.pyplot as plt
		figure = plt.figure()
		
		p.LoadPgfPlotStyle(plt)
		p.Plot(figure, title=args.title, log=args.log, grid=True, smooth=args.smooth)

		if args.showPlot:
			plt.show()
		
		if outputIsPlotFile:
			plt.savefig(args.output)

	# Create CSV, if needed
	if type(args.output) == str and args.output.lower().endswith('.csv'):
		p.SaveCsv(args.output, includeHeader=False)
	
	if args.stats:
		print(p.CalculateStats())