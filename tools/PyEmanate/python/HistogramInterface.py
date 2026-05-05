import sys, os, pathlib, json
from time import sleep
from datetime import datetime
from PyQt5 import uic, QtCore, QtGui, QtWidgets, Qt
from PyQt5.QtWidgets import QVBoxLayout, QFileDialog, QDialog, QTableWidgetItem, QMessageBox, QInputDialog

from UART import UART
from ForthInterface import ForthInterface
from AFE import AFE
from HistogramChannel import HistogramChannel, HistogramCollection
from HelperFunctions import *

#import matplotlib
#matplotlib.use('Qt5Agg')
#from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg
#from matplotlib.figure import Figure

from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.backends.backend_qt5agg import NavigationToolbar2QT as NavigationToolbar
from matplotlib.figure import Figure
import matplotlib.pyplot as plt
import matplotlib

import numpy as np

class Ui_HistogramInterfaceWindow(QtWidgets.QMainWindow):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	App = None
	Parent = None
	Forth = None

	Figure = None
	Canvas = None
	FigureToolbar = None

	CurrentAfe = None
	AvailableAfeQActions = None

	AutoRefreshTime = None	# seconds
	AutoRefreshIterations = None
	AutoRefreshClearHistogramAtStart = False
	AutoRefreshIndex = None
	AutoRefreshTimer = None
	AutoRefreshUseTimedHist = False

	HistogramCollectionFilePath = None
	CollatedHistogramCollection = None

	CalibrationWindow = None

	#PreviousClearTimestamp = None	# For calculating counts per second
	#TotalCounts = None	# For calculating counts per second

	CurrentAValue = None

	def __init__(self, app, parent):
		super(Ui_HistogramInterfaceWindow, self).__init__(parent)
		self.App = app
		self.Parent = parent
		return
	
	def setupUi(self, forth:ForthInterface):
		# Load the UI configuration file
		uic.loadUi(self.ThisFileDirectory + '/../qt/HistogramInterface.ui', self)
		self.Forth = forth

		# Add each AFE to the action menu, selecting the first one
		self.CurrentAfe = self.Forth.ActiveChip.AFEs[0]
		for afe in self.Forth.ActiveChip.AFEs:
			# Set the die ID for each AFE histogram
			afe.Histogram.DieID = self.Forth.ActiveChip.DieID
		self.AvailableAfeQActions = []
		for afe in self.Forth.ActiveChip.AFEs:
			action = self.menu_Channel.addAction(afe.Name)
			self.AvailableAfeQActions.append(action)
			action.setCheckable(True)
			if afe.Name == self.CurrentAfe.Name:
				action.setChecked(True)
			else:
				action.setChecked(False)
			if 0 <= afe.Index <= 9:
				action.setShortcut('Ctrl+' + str(afe.Index))
			action.triggered.connect(self.action_Channel_triggered)
		
		# Create the auto refresh timer
		self.AutoRefreshTimer = QtCore.QTimer()
		self.actionAuto_Refresh_Toggle.setChecked(False)

		# Set up collated histograms
		self.HistogramCollectionFilePath = None
		self.CollatedHistogramCollection = None

		# Create a figure to plot on
		self.Figure = Figure()

		# Create a canvas widget to house the figure
		self.Canvas = FigureCanvas(self.Figure)

		# Create a navigation toolbar for the figure & canvas
		self.FigureToolbar = NavigationToolbar(self.Canvas, self)

		# Add the canvas to the central widget
		#vbox = QVBoxLayout()
		#self.centralwidget.setLayout(vbox)
		##vbox.addWidget(self.frameControlAndStatus)
		#vbox.addWidget(self.FigureToolbar)
		#vbox.addWidget(self.Canvas)
		layout = self.centralwidget.layout()
		layout.addWidget(self.labelStatus, 0, 1)
		layout.addWidget(self.FigureToolbar, 0, 0)
		layout.addWidget(self.Canvas, 1, 0, 1, 2)
		self.FigureToolbar.setMinimumSize(500, 0)

		# Create the Calibration Dialog
		self.CalibrationWindow = Ui_CalibrationDialog(self.App, parent=self)
		self.CalibrationWindow.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
			
		# Add event handlers
		self.actionRefresh.triggered.connect(self.RefreshHistogram)
		self.actionClear.triggered.connect(self.actionClear_triggered)
		self.actionLogarithmic_Scale.triggered.connect(self.UpdatePlot)
		self.actionLine.triggered.connect(self.actionPlot_Type_triggered)
		self.actionHistogram.triggered.connect(self.actionPlot_Type_triggered)
		self.action_Filled_Line.triggered.connect(self.actionPlot_Type_triggered)
		self.actionQuick_Save_Histogram.triggered.connect(self.actionQuick_Save_Histogram_triggered)
		self.actionSave_Histogram.triggered.connect(self.actionSave_Histogram_triggered)
		self.actionSave_Histogram_PNG.triggered.connect(self.actionSave_Histogram_PNG_triggered)
		self.actionSave_Histogram_PGF.triggered.connect(self.actionSave_Histogram_PGF_triggered)
		self.actionSave_Histogram_Images.triggered.connect(self.actionSave_Histogram_Images_triggered)
		self.actionAuto_Refresh_Setup.triggered.connect(self.actionAuto_Refresh_Setup_triggered)
		self.actionNotes.triggered.connect(self.actionNotes_triggered)
		self.actionAuto_Refresh_Toggle.triggered.connect(self.actionAuto_Refresh_Toggle_triggered)
		self.AutoRefreshTimer.timeout.connect(self.AutoRefreshTimer_timeout)
		self.actionSet_Parameters.triggered.connect(self.actionSet_Parameters_triggered)
		self.actionAuto_Collate_Histograms.triggered.connect(self.actionAuto_Collate_Histograms_triggered)
		self.actionAuto_Save.triggered.connect(self.actionAuto_Save_triggered)
		self.action_Calibrate.triggered.connect(self.action_Calibrate_triggered)
		self.actionDisplay_Calibration.triggered.connect(self.actionDisplay_Calibration_triggered)
		self.actionShow_First_Bin.triggered.connect(self.UpdatePlot)
		self.actionShow_Last_Bin.triggered.connect(self.UpdatePlot)
		self.actionSmooth.triggered.connect(self.UpdatePlot)
		self.actionLoad_DNL_Correction.triggered.connect(self.actionLoad_DNL_Correction_triggered)
		self.actionCorrect_for_DNL.triggered.connect(self.actionCorrect_for_DNL_triggered)
		self.actionSet_DPS_A_Value.triggered.connect(self.actionSet_DPS_A_Value_triggered)
		self.actionOpen_Histogram_Folder.triggered.connect(self.actionOpen_Histogram_Folder_triggered)
		self.Canvas.mpl_connect('scroll_event', self.matplotlib_scroll_event)
		self.Canvas.mpl_connect('button_press_event', self.matplotlib_button_press_event)
		
		# Update the plot
		self.UpdatePlot(preserveZoom=False)
		self.UpdateStatusText()
		self.CalibrationWindow.close()

		return
	
	def MessageBox(self, text:str, title='', icon=QMessageBox.Warning):
		msg = QMessageBox()
		msg.setText(text)
		msg.setWindowTitle(title)
		msg.setIcon(icon)
		msg.exec_()
		return
	
	def UpdatePlotPreserveZoom(self):
		self.UpdatePlot(preserveZoom=True)

	def UpdatePlot(self, preserveZoom=False):
		# This is a little forth program to make the chip display a line as a histogram:
		# : test 1024 0 do i i 4 * swap drop 0x1C000 + ! loop ;
		# Load the default style and make some changes
		self.CurrentAfe.Histogram.LoadPgfPlotStyle(plt)
		matplotlib.rcParams['font.size'] = 16
		matplotlib.rcParams['figure.subplot.top'] = 0.9

		# Get the plot options
		plotType = 'line'
		if self.actionLine.isChecked():
			plotType = 'line'
		elif self.actionHistogram.isChecked():
			plotType = 'histogram'
		elif self.action_Filled_Line.isChecked():
			plotType = 'filled line'
		xlabel = 'Bin'
		xTickSpacing = 128
		if self.actionDisplay_Calibration.isChecked() and self.CurrentAfe.Histogram.CalibratedScalingFactor is not None and self.CurrentAfe.Histogram.CalibratedYIntercept is not None:
			xlabel = 'Energy (keV)'
			xTickSpacing = None
		title = 'Histogram for ' + self.Forth.ActiveChip.DieID + ':' + self.CurrentAfe.Name
		grid = True

		# Make the plot
		self.CurrentAfe.Histogram.PlotHistogram(self.Figure, plotType=plotType, log=self.actionLogarithmic_Scale.isChecked(), title=title, xlabel=xlabel, xTickSpacing=xTickSpacing, grid=grid, useCalibration=self.actionDisplay_Calibration.isChecked(), showFirstBin=self.actionShow_First_Bin.isChecked(), showLastBin=self.actionShow_Last_Bin.isChecked(), correctDnl=self.actionCorrect_for_DNL.isChecked(), smooth=self.actionSmooth.isChecked(), preserveZoom=preserveZoom)
		
		# Add the interactive coordinate display
		self.Figure.axes[0].format_coord = self.format_coord

		# Update the status text
		self.UpdateStatusText()

		# Draw the plot
		self.Canvas.draw()
		return
	
	def RefreshHistogramPreserveZoom(self):
		self.RefreshHistogram(preserveZoom=True)

	def RefreshHistogram(self, preserveZoom:bool=False):
		# Update GUI
		self.statusbar.showMessage('Refreshing ' + self.CurrentAfe.Name + '...', 5000)
		self.repaint()	# Force the thread to update the GUI right now
		
		'''
		# Save data from previous timestamp
		prevHistTimestamp = self.CurrentAfe.Histogram.Timestamp
		prevTotalCounts = self.CurrentAfe.Histogram.TotalCounts
		if not self.actionShow_First_Bin.isChecked():
			prevTotalCounts -= self.CurrentAfe.Histogram.Counts[0]
		if not self.actionShow_Last_Bin.isChecked():
			prevTotalCounts -= self.CurrentAfe.Histogram.Counts[-1]
		'''

		# Get the new histogram
		if self.Forth.GetHistogram(self.CurrentAfe.Index, accumulate=False) is None:
			self.statusbar.showMessage('Could not refresh ' + self.CurrentAfe.Name, 5000)
			return
		if self.actionAuto_Clear.isChecked():
			self.ClearHistogram(clearComputerHistogram=False)
			self.CurrentAfe.Histogram.ClearCountsTimestamp = self.PreviousRefreshTimestamp

		'''
		# Compute the average count rate
		self.TotalCounts = self.CurrentAfe.Histogram.TotalCounts
		if not self.actionShow_First_Bin.isChecked():
			self.TotalCounts -= self.CurrentAfe.Histogram.Counts[0]
		if not self.actionShow_Last_Bin.isChecked():
			self.TotalCounts -= self.CurrentAfe.Histogram.Counts[-1]
		if self.PreviousClearTimestamp is not None:
			seconds = (self.CurrentAfe.Histogram.Timestamp - self.PreviousClearTimestamp).total_seconds()
			self.CurrentAfe.Histogram.AverageCountsPerSecond = self.TotalCounts / seconds
		else:
			self.CurrentAfe.Histogram.AverageCountsPerSecond = None

		# Compute the current count rate
		if prevHistTimestamp is not None:
			seconds = (self.CurrentAfe.Histogram.Timestamp - prevHistTimestamp).total_seconds()
			self.CurrentAfe.Histogram.CurrentCountsPerSecond = (self.TotalCounts - prevTotalCounts) / seconds
		else:
			self.CurrentAfe.Histogram.CurrentCountsPerSecond = None
		'''

		# Plot the histogram
		self.UpdatePlot(preserveZoom=preserveZoom)
		if self.actionAuto_Save.isChecked():
			self.actionQuick_Save_Histogram_triggered()
		if self.actionAuto_NPU.isChecked():
			ret = self.Forth.RunNpuIsotopeID(self.CurrentAfe.Index)
			if ret is None or ret is False:
				self.statusbar.showMessage(self.CurrentAfe.Name + ' has been updated, but the NPU failed to execute', 5000)
				return
			print(ret)
		self.statusbar.showMessage(self.CurrentAfe.Name + ' has been updated', 5000)
		return
	
	def ClearHistogram(self, clearComputerHistogram:bool=True):
		if self.Forth.ClearHistogram(self.CurrentAfe.Index, clearComputerHistogram=clearComputerHistogram) is None:
			self.statusbar.showMessage('Could not clear histogram for ' + self.CurrentAfe.Name, 5000)
			return False
		#self.PreviousClearTimestamp = datetime.now()
		#self.CurrentAfe.Histogram.Timestamp = self.PreviousClearTimestamp()
		#self.TotalCounts = None
		self.UpdatePlot(preserveZoom=False)
		return

	def SaveHistogram(self, dialog=False):
		# Get default directory and file name
		directory = self.CurrentAfe.Parent.DataDirectory + '/Histograms/' + self.CurrentAfe.Histogram.DieID
		
		timestampStr = get_string_timestamp(dt=self.CurrentAfe.Histogram.Timestamp, includeSeconds=True)

		if self.actionAuto_Collate_Histograms.isChecked():
			dialogText = 'Save Histogram Collection'
			dialogExtensions = 'JSON File (*.json)'
			fileName = 'Histograms-' + self.CurrentAfe.Histogram.DieID + '-' + self.CurrentAfe.Histogram.AfeName + '-' + timestampStr + '.json'
		else:
			dialogText = 'Save Histogram'
			dialogExtensions = 'JSON File (*.json);;CSV File (*.csv *.txt)'
			fileName = 'Histogram-' + self.CurrentAfe.Histogram.DieID + '-' + self.CurrentAfe.Histogram.AfeName + '-' + timestampStr + '.json'

		outPath = directory + '/' + fileName

		# Open the file save dialog, if desired
		if dialog:
			outPath, ok = QFileDialog.getSaveFileName(self, dialogText, outPath, dialogExtensions)
			if not ok:
				return
			fileName = os.path.basename(os.path.abspath(outPath))
			directory = os.path.dirname(os.path.abspath(outPath))
		else:
			if not os.path.isdir(directory):
				os.makedirs(directory)

		# Get register values
		registerValues = None
		if self.action_Include_Registers.isChecked():
			registerValues = self.Forth.ActiveChip.SaveRegisterValuesToDict(onlyMarked=True, timestampStr=timestampStr)

		# Is this one histogram, or a collection of histograms?
		if self.actionAuto_Collate_Histograms.isChecked():
			# Append the histogram to the collated histogram collection
			if self.CollatedHistogramCollection is None:
				self.CollatedHistogramCollection = HistogramCollection()
				self.CollatedHistogramCollection.Histograms = []
			self.CollatedHistogramCollection.Histograms.append(self.CurrentAfe.Histogram.Copy())

			# Is a histogram collection file defined?
			if (self.HistogramCollectionFilePath is None) or dialog:
				self.HistogramCollectionFilePath = outPath
			
			# Save the collated histogram collection
			self.CollatedHistogramCollection.SaveAsJson(self.HistogramCollectionFilePath, registerValues=registerValues)

			self.statusbar.showMessage('Appended ' + self.CurrentAfe.Histogram.DieID + ':' + self.CurrentAfe.Histogram.AfeName + ' histogram to ' + fileName, 5000)
		else:
			# What is the file type?
			fileNameLower = fileName.lower()
			if fileNameLower.endswith('.json'):
				# Save as a JSON
				# Include the register values and DNL data, if desired
				self.CurrentAfe.Histogram.SaveHistogramJson(outPath, registerValues=registerValues)
			elif fileNameLower.endswith('.csv') or fileNameLower.endswith('.txt'):
				# Save as a CSV
				# If correcting for DNL, save the corrected DNL histogram
				self.CurrentAfe.Histogram.SaveHistogramCsv(outPath, self.actionCorrect_for_DNL.isChecked())
			else:
				ext = fileName.split('.')[-1]
				self.MessageBox('Invalid file extension ' + ext, title='Error saving histogram')
				return
			
			# Show a message
			self.statusbar.showMessage('Saved ' + self.CurrentAfe.Histogram.DieID + ':' + self.CurrentAfe.Histogram.AfeName + ' histogram as ' + fileName, 5000)
		
		return
	
	def UpdateStatusText(self):
		s = 'Auto refresh '
		if self.actionAuto_Refresh_Toggle.isChecked():
			s += 'active ('
			if type(self.AutoRefreshIndex) == int and type(self.AutoRefreshTime) == int:
				totalSeconds = self.AutoRefreshIndex * self.AutoRefreshTime
				totalHours = totalSeconds // 3600
				totalSeconds -= totalHours * 3600
				totalMinutes = totalSeconds // 60
				totalSeconds -= totalMinutes * 60
				if totalHours > 0:
					s += str(totalHours) + ':'
				s += '{:02}:{:02} elapsed)'.format(totalMinutes, totalSeconds)
			else:
				s += '00:00 elapsed)'
		else:
			s += 'inactive'
		
		if self.CurrentAfe.Histogram.MeasuredIsotopeAbundances is None:
			s += '\nIsotopes not specified'
		else:
			s += '\nIsotopes: '
			for isotope in self.CurrentAfe.Histogram.MeasuredIsotopeAbundances:
				s += isotope + ', '
			s = s[:-2]
			if len(self.CurrentAfe.Histogram.MeasuredIsotopeAbundances) == 1 and 'Cs-137' in self.CurrentAfe.Histogram.MeasuredIsotopeAbundances:
				data = self.CurrentAfe.Histogram.CalculatePeakResolution()
				#if data is not None and data[0] is not None:
				#	s += ', resolution = ' + str(round(100 * data[0], 2)) + '%'
		
		#if self.actionShow_First_Bin.isChecked() and self.actionShow_Last_Bin.isChecked():
		#	totalCounts = self.CurrentAfe.Histogram.TotalCounts
		#	currentCps = self.CurrentAfe.Histogram.CurrentCountsPerSecond
		#	averageCps = self.CurrentAfe.Histogram.AverageCountsPerSecond
		#elif self.actionShow_First_Bin.isChecked():
		#	totalCounts = self.CurrentAfe.Histogram.TotalCountsMinusLastBin
		#	currentCps = self.CurrentAfe.Histogram.CurrentCountsPerSecondMinusLastBin
		#	averageCps = self.CurrentAfe.Histogram.AverageCountsPerSecondMinusLastBin
		#elif self.actionShow_Last_Bin.isChecked():
		#	totalCounts = self.CurrentAfe.Histogram.TotalCountsMinusFirstBin
		#	currentCps = self.CurrentAfe.Histogram.CurrentCountsPerSecondMinusFirstBin
		#	averageCps = self.CurrentAfe.Histogram.AverageCountsPerSecondMinusFirstBin
		#else:
		#	totalCounts = self.CurrentAfe.Histogram.TotalCountsMinusFirstAndLastBin
		#	currentCps = self.CurrentAfe.Histogram.CurrentCountsPerSecondMinusFirstAndLastBin
		#	averageCps = self.CurrentAfe.Histogram.AverageCountsPerSecondMinusFirstAndLastBin

		totalCounts = self.CurrentAfe.Histogram.TotalCounts
		currentCps = self.CurrentAfe.Histogram.CurrentCountsPerSecond
		averageCps = self.CurrentAfe.Histogram.AverageCountsPerSecond
		
		if totalCounts is not None:
			s += '\n{:,} total counts'.format(totalCounts)
			if currentCps is not None:
				s += '; inst. {:,} cps'.format(round(currentCps))
			if averageCps is not None:
				s += '; av. {:,} cps'.format(round(averageCps))
		
		if self.CurrentAfe.Histogram.DnlBinCorrectionFactors is not None and self.actionCorrect_for_DNL.isChecked():
			s += '\nCorrecting for DNL'
		
		if self.CurrentAValue is not None:
			s += '\nDPS "A" value = ' + str(self.CurrentAValue)

		self.labelStatus.setText(s)
		return

	def format_coord(self, x, y):
		hist = self.CurrentAfe.Histogram
		# Find the bin closest to the x value
		if self.actionDisplay_Calibration.isChecked() and (hist.CalibratedScalingFactor is not None) and (hist.CalibratedYIntercept is not None):
			# x is in units of keV, calculate the bin number from the energy
			# bin = (energy - b) / m
			b = int(round(((x * 1e3) - hist.CalibratedYIntercept) / hist.CalibratedScalingFactor))
			if 0 <= b < hist.NumBins:
				keV = hist.GetCalibratedEnergy(b) / 1e3
				count = hist.Counts[b]
				return '{:.1f} keV: '.format(keV) + '{:,} counts'.format(count)
			else:
				return ''
		else:
			# x is in units of bins
			b = int(x + 0.5)
			if (b < 0) or (b >= hist.NumBins):
				return ''
			return 'Bin ' + str(b) + ': {:,}'.format(hist.Counts[b]) + ' counts'
			
	



	# Event Handlers
	def action_Channel_triggered(self):
		# Get the sender
		action = self.sender()
		if type(action) != QtWidgets.QAction:
			return
		
		# Uncheck all other channels
		for a in self.AvailableAfeQActions:
			a.setChecked(a == action)
		
		# Set the current AFE
		for afe in self.Forth.ActiveChip.AFEs:
			if afe.Name == action.text():
				self.CurrentAfe = afe
				break
		
		# Update the plot
		self.UpdatePlot(preserveZoom=False)

		# Close the calibration window
		self.CalibrationWindow.close()

		return
	
	def actionClear_triggered(self):
		self.ClearHistogram()

	def actionPlot_Type_triggered(self):
		# Get the sender
		action = self.sender()
		if type(action) != QtWidgets.QAction:
			return
		
		# Uncheck all other plot types
		for pt in [self.actionLine, self.actionHistogram, self.action_Filled_Line]:
			pt.setChecked(pt == action)
		
		# Update the plot
		self.UpdatePlot(preserveZoom=False)
		return
	
	def actionQuick_Save_Histogram_triggered(self):
		self.SaveHistogram(dialog=False)
	
	def actionSave_Histogram_triggered(self):
		self.SaveHistogram(dialog=True)
	
	def actionSave_Histogram_PGF_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/HistogramPlots/' + self.CurrentAfe.Histogram.DieID
		fileName = 'HistogramPlot-' + self.CurrentAfe.Histogram.DieID + '-' + self.CurrentAfe.Histogram.AfeName + '-' + get_string_timestamp(dt=self.CurrentAfe.Histogram.Timestamp, includeSeconds=True) + '.pgf'
		outPath = directory + '/' + fileName
		if not os.path.isdir(directory):
			outPath = fileName
		outPath, ok = QFileDialog.getSaveFileName(self, 'Save Histogram Plot', outPath, 'PGF File (*.pgf)')
		if not ok:
			return

			# Get the plot options
		plotType = 'line'
		if self.actionLine.isChecked():
			plotType = 'line'
		elif self.actionHistogram.isChecked():
			plotType = 'histogram'
		elif self.action_Filled_Line.isChecked():
			plotType = 'filled line'
		xlabel = 'Bin'
		if self.actionDisplay_Calibration.isChecked() and self.CurrentAfe.Histogram.CalibratedScalingFactor is not None and self.CurrentAfe.Histogram.CalibratedYIntercept is not None:
			xlabel = 'Energy (keV)'
		
		self.CurrentAfe.Histogram.SaveHistogramPlot(outPath, plotType=plotType, log=self.actionLogarithmic_Scale.isChecked(), xlabel=xlabel, grid=True, useCalibration=self.actionDisplay_Calibration.isChecked(), showFirstBin=self.actionShow_First_Bin.isChecked(), showLastBin=self.actionShow_Last_Bin.isChecked(), correctDnl=self.actionCorrect_for_DNL.isChecked(), smooth=self.actionSmooth.isChecked())

		self.statusbar.showMessage('Saved ' + self.CurrentAfe.Histogram.DieID + ':' + self.CurrentAfe.Histogram.AfeName + ' histogram plot as ' + fileName, 5000)
		return
	
	def actionSave_Histogram_PNG_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/HistogramPlots/' + self.CurrentAfe.Histogram.DieID
		fileName = 'HistogramPlot-' + self.CurrentAfe.Histogram.DieID + '-' + self.CurrentAfe.Histogram.AfeName + '-' + get_string_timestamp(dt=self.CurrentAfe.Histogram.Timestamp, includeSeconds=True) + '.png'
		outPath = directory + '/' + fileName
		if not os.path.isdir(directory):
			outPath = fileName
		outPath, ok = QFileDialog.getSaveFileName(self, 'Save Histogram Plot', outPath, 'PNG Files (*.png)')
		if not ok:
			return
		
		# Get the plot options
		plotType = 'line'
		if self.actionLine.isChecked():
			plotType = 'line'
		elif self.actionHistogram.isChecked():
			plotType = 'histogram'
		elif self.action_Filled_Line.isChecked():
			plotType = 'filled line'
		xlabel = 'Bin'
		if self.actionDisplay_Calibration.isChecked() and self.CurrentAfe.Histogram.CalibratedScalingFactor is not None and self.CurrentAfe.Histogram.CalibratedYIntercept is not None:
			xlabel = 'Energy (keV)'

		self.CurrentAfe.Histogram.SaveHistogramPlot(outPath, plotType=plotType, log=self.actionLogarithmic_Scale.isChecked(), xlabel=xlabel, grid=True, useCalibration=self.actionDisplay_Calibration.isChecked(), showFirstBin=self.actionShow_First_Bin.isChecked(), showLastBin=self.actionShow_Last_Bin.isChecked(), correctDnl=self.actionCorrect_for_DNL.isChecked(), smooth=self.actionSmooth.isChecked())

		self.statusbar.showMessage('Saved ' + self.CurrentAfe.Histogram.DieID + ':' + self.CurrentAfe.Histogram.AfeName + ' histogram plot as ' + fileName, 5000)
		return
	
	def actionSave_Histogram_Images_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/HistogramPlots/' + self.CurrentAfe.Histogram.DieID
		if not os.path.isdir(directory):
			os.makedirs(directory)

		# Get the plot options
		plotType = 'line'
		if self.actionLine.isChecked():
			plotType = 'line'
		elif self.actionHistogram.isChecked():
			plotType = 'histogram'
		elif self.action_Filled_Line.isChecked():
			plotType = 'filled line'
		xlabel = 'Bin'
		if self.actionDisplay_Calibration.isChecked() and self.CurrentAfe.Histogram.CalibratedScalingFactor is not None and self.CurrentAfe.Histogram.CalibratedYIntercept is not None:
			xlabel = 'Energy (keV)'
		
		# Save the PNG
		fileName = 'HistogramPlot-' + self.CurrentAfe.Histogram.DieID + '-' + self.CurrentAfe.Histogram.AfeName + '-' + get_string_timestamp(dt=self.CurrentAfe.Histogram.Timestamp, includeSeconds=True) + '.png'
		outPath = directory + '/' + fileName
		self.CurrentAfe.Histogram.SaveHistogramPlot(outPath, plotType=plotType, log=self.actionLogarithmic_Scale.isChecked(), xlabel=xlabel, grid=True, useCalibration=self.actionDisplay_Calibration.isChecked(), showFirstBin=self.actionShow_First_Bin.isChecked(), showLastBin=self.actionShow_Last_Bin.isChecked(), correctDnl=self.actionCorrect_for_DNL.isChecked(), smooth=self.actionSmooth.isChecked())

		# Save the PGF
		fileName = 'HistogramPlot-' + self.CurrentAfe.Histogram.DieID + '-' + self.CurrentAfe.Histogram.AfeName + '-' + get_string_timestamp(dt=self.CurrentAfe.Histogram.Timestamp, includeSeconds=True) + '.pgf'
		outPath = directory + '/' + fileName
		self.CurrentAfe.Histogram.SaveHistogramPlot(outPath, plotType=plotType, log=self.actionLogarithmic_Scale.isChecked(), xlabel=xlabel, grid=True, useCalibration=self.actionDisplay_Calibration.isChecked(), showFirstBin=self.actionShow_First_Bin.isChecked(), showLastBin=self.actionShow_Last_Bin.isChecked(), correctDnl=self.actionCorrect_for_DNL.isChecked(), smooth=self.actionSmooth.isChecked())

		self.statusbar.showMessage('Saved ' + self.CurrentAfe.Histogram.DieID + ':' + self.CurrentAfe.Histogram.AfeName + ' histogram plots', 5000)
	
	def actionAuto_Refresh_Setup_triggered(self):
		if self.AutoRefreshTimer.isActive():
			self.statusbar.showMessage('Cannot change auto refresh parameters while auto refresh is active', 5000)
			return
		diag = Ui_AutoRefreshSetupDialog()
		diag.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
		if self.AutoRefreshTime is not None and self.AutoRefreshIterations is not None:
			seconds = self.AutoRefreshTime
			hours = seconds // 3600
			seconds -= hours * 3600
			minutes = seconds // 60
			seconds -= minutes * 60
			diag.spinBoxAutoRefreshTimeHours.setValue(hours)
			diag.spinBoxAutoRefreshTimeMinutes.setValue(minutes)
			diag.spinBoxAutoRefreshTimeSeconds.setValue(seconds)
			diag.spinBoxAutoRefreshIterations.setValue(self.AutoRefreshIterations)
		diag.checkBoxClearHistogramAtStart.setChecked(self.AutoRefreshClearHistogramAtStart)
		diag.checkBoxUseTimedHist.setChecked(self.AutoRefreshUseTimedHist)
		if diag.exec():
			# OK (or return) was pressed
			seconds = diag.spinBoxAutoRefreshTimeHours.value() * 3600 + diag.spinBoxAutoRefreshTimeMinutes.value() * 60 + diag.spinBoxAutoRefreshTimeSeconds.value()
			if seconds <= 0:
				self.statusbar.showMessage('Invalid auto refresh time, must be greater than 0', 5000)
				return
			self.AutoRefreshTime = seconds
			self.AutoRefreshIterations = diag.spinBoxAutoRefreshIterations.value()
			self.AutoRefreshClearHistogramAtStart = diag.checkBoxClearHistogramAtStart.isChecked()
			self.AutoRefreshUseTimedHist = diag.checkBoxUseTimedHist.isChecked()
		return
	
	def actionNotes_triggered(self):
		diag = Ui_HistogramNotes()
		diag.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
		diag.textEditNotes.setText(self.CurrentAfe.Histogram.Notes)
		if diag.exec():
			self.CurrentAfe.Histogram.Notes = diag.textEditNotes.toPlainText()
		return
	
	def actionAuto_Refresh_Toggle_triggered(self):
		if self.actionAuto_Refresh_Toggle.isChecked():
			# Are the parameters for auto refresh configured?
			if self.AutoRefreshTime is None or self.AutoRefreshIterations is None:
				self.actionAuto_Refresh_Setup_triggered()
			if self.AutoRefreshTime is None or self.AutoRefreshIterations is None:
				self.actionAuto_Refresh_Toggle.setChecked(False)
				return
			
			# Do we need to clear the histogram before beginning the auto refresh?
			if self.AutoRefreshClearHistogramAtStart:
				self.ClearHistogram()

			# Are we using the timedHist forth function?
			addedMilliseconds = 0
			if self.AutoRefreshUseTimedHist:
				# Send the initial timedHist function
				self.Forth.StartTimedHist(self.CurrentAfe.Index, self.AutoRefreshTime)
				addedMilliseconds = 500
			
			# Start the timer
			self.AutoRefreshTimer.setInterval(self.AutoRefreshTime * 1000 + addedMilliseconds)	# setInterval expects milliseconds, but AutoRefreshTime is in seconds
			self.AutoRefreshIndex = 0
			self.AutoRefreshTimer.start()
			msg = 'Auto refresh has started'
			if self.AutoRefreshIterations > 0:
				msg += ', 0/' + str(self.AutoRefreshIterations) + ' ('
				secondsRemaining = self.AutoRefreshIterations * self.AutoRefreshTime
				hoursRemaining = secondsRemaining // 3600
				secondsRemaining -= hoursRemaining * 3600
				minutesRemaining = secondsRemaining // 60
				secondsRemaining -= minutesRemaining * 60
				if hoursRemaining > 0:
					msg += str(hoursRemaining) + ':'
				msg += '{:02}'.format(minutesRemaining) + ':' + '{:02}'.format(secondsRemaining) + ' remaining)'
			self.statusbar.showMessage(msg, 5000)
		else:
			self.AutoRefreshTimer.stop()

		self.UpdateStatusText()
		return
	
	def AutoRefreshTimer_timeout(self):
		if not self.actionAuto_Refresh_Toggle.isChecked():
			return
		stop = False
		self.AutoRefreshIndex += 1
		if self.AutoRefreshIterations > 0 and self.AutoRefreshIndex >= self.AutoRefreshIterations:
			stop = True
		self.RefreshHistogram()

		# Should we issue another timedHist command?
		if self.AutoRefreshUseTimedHist and not stop:
			self.Forth.StartTimedHist(self.CurrentAfe.Index, self.AutoRefreshTime)

		msg = 'Auto refreshed histogram ' + str(self.AutoRefreshIndex)
		if self.AutoRefreshIterations > 0:
			# Write a status message
			msg += '/' + str(self.AutoRefreshIterations)
			if stop:
				msg += ' (completed)'
			else:
				secondsRemaining = (self.AutoRefreshIterations - self.AutoRefreshIndex) * self.AutoRefreshTime
				hoursRemaining = secondsRemaining // 3600
				secondsRemaining -= hoursRemaining * 3600
				minutesRemaining = secondsRemaining // 60
				secondsRemaining -= minutesRemaining * 60
				msg += ' ('
				if hoursRemaining > 0:
					msg += str(hoursRemaining) + ':'
				msg += '{:02}'.format(minutesRemaining) + ':' + '{:02}'.format(secondsRemaining) + ' remaining)'
		
		if stop:
			# No more iterations to do
			self.AutoRefreshTimer.stop()
			self.actionAuto_Refresh_Toggle.setChecked(False)
			self.UpdateStatusText()
			self.App.beep()
				
		self.statusbar.showMessage(msg, 5000)
	
	def actionSet_Parameters_triggered(self):
		h = self.CurrentAfe.Histogram
		previousHistogramSetupParametersPath = self.ThisFileDirectory + '/../config/PreviousHistogramSetupParameters.json'
		diag = Ui_HistogramParametersDialog(previousHistogramSetupParametersPath, h, isotopeAbundancesDict=h.MeasuredIsotopeAbundances)
		diag.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
		
		if diag.exec():
			# OK (or return) was pressed
			isotopeDict =  diag.GetIsotopeAbundancesDict()
			if len(isotopeDict) > 0:
				h.MeasuredIsotopeAbundances = isotopeDict
				self.UpdateStatusText()
			
			diag.GetParameters(updateHistogram=True)
		
		return
	
	def actionAuto_Collate_Histograms_triggered(self):
		self.HistogramCollectionFilePath = None
		self.CollatedHistogramCollection = None
	
	def actionAuto_Save_triggered(self):
		pass
	
	def action_Calibrate_triggered(self):
		if self.actionDisplay_Calibration.isChecked():
			self.actionDisplay_Calibration.activate(Qt.QAction.Trigger)
		self.CalibrationWindow.DisplayCurrentCalibration(self.CurrentAfe.Histogram.CalibratedScalingFactor, self.CurrentAfe.Histogram.CalibratedYIntercept)
		self.CalibrationWindow.show()
		return
	
	def actionDisplay_Calibration_triggered(self):
		self.UpdatePlot(preserveZoom=False)
		return
	
	def actionLoad_DNL_Correction_triggered(self):
		# Use a file dialog to get the ADC characterization file
		adcTestDirectory = self.Forth.ActiveChip.DataDirectory + '/AdcTest/' + self.Forth.ActiveChip.DieID
		inPath, ok = QFileDialog.getOpenFileName(self, 'Load ADC characterization', adcTestDirectory, 'JSON Files (*.json)')
		if not ok:
			return

		if not os.path.isfile(inPath):
			self.statusbar.showMessage('Cannot load ADC characterization: invalid path', 5000)
			return
		
		# Load the JSON file
		with open(inPath, 'r') as f:
			d = json.load(f)
		if d is None or 'Type' not in d:
			self.statusbar.showMessage('Cannot load ADC characterization: invalid JSON file', 5000)
			return
		
		if d['Type'] != 'AdcCharacterization':
			self.statusbar.showMessage('Cannot load ADC characterization: not an ADC characterization file', 5000)
			return
		if d['DieID'] != self.CurrentAfe.Histogram.DieID:
			self.statusbar.showMessage('Cannot load ADC characterization: file is not for this die ID', 5000)
			return
		
		# Load the ADC characterization and compute the DNL correction factor for each AFE channel
		good = False
		for afe in self.Forth.ActiveChip.AFEs:
			ret = afe.Histogram.LoadAdcDnlCorrectionFromDict(d)
			if (afe.Name == self.CurrentAfe.Name) and ret:
				good = True
		
		if good:
			self.statusbar.showMessage('Loaded ADC characterization for DNL correction', 5000)
		else:
			self.statusbar.showMessage('Cannot load ADC characterization: file does not include this AFE channel', 5000)
		return
	
	def actionCorrect_for_DNL_triggered(self):
		if self.CurrentAfe.Histogram.DnlBinCorrectionFactors is None:
			self.actionLoad_DNL_Correction_triggered()
		if (self.CurrentAfe.Histogram.DnlBinCorrectionFactors is None) and self.actionCorrect_for_DNL.isChecked():
			self.actionCorrect_for_DNL.setChecked(False)
			return
		self.UpdatePlot(preserveZoom=False)
		return
	
	def actionSet_DPS_A_Value_triggered(self):
		value = 1023
		if self.CurrentAValue is not None:
			value = self.CurrentAValue

		# Ask the user for the new A value
		A, ok = QInputDialog.getInt(self, 'New DPS "A" Value', 'Please choose an "A" value between 0 and 2047:', value=value, min=0, max=2047)

		if not ok:
			return
		
		if type(A) != int or (not (0 <= A < 2048)):
			self.MessageBox('Please choose an "A" value between 0 and 2047', title='Invalid "A" Value')
			return

		# Set the new "A" value
		if not self.Forth.SetDpsAValue(0, A):
			self.MessageBox('Could not update the DPS "A" value.\nDoes the current forth interpreter support the setA function?', 'Error')
			return
		
		# Update the "A" value data
		self.CurrentAValue = A
		self.CurrentAfe.Histogram.PowerSupplyVoltage = 'A = ' + str(A)
		self.UpdateStatusText()
		
		return
	
	def actionOpen_Histogram_Folder_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/Histograms/' + self.CurrentAfe.Histogram.DieID
		if os.path.isdir(directory):
			os.startfile(directory)
		return

	def matplotlib_scroll_event(self, event):
		#print(event.button, event.xdata, event.ydata)
		if event.xdata is None or event.ydata is None:
			return
		zoomFactor = 0.9
		current_xlim = self.Figure.axes[0].get_xlim()
		xspan = current_xlim[1] - current_xlim[0]
		xPercentLeft = (event.xdata - current_xlim[0]) / xspan
		if event.button == 'up':
			# Save current figure state so the zoom operation can be undone
			self.FigureToolbar.push_current()
			# Zoom in
			zoomFactor = 1 - zoomFactor
			new_xlim = (current_xlim[0] + (zoomFactor * xPercentLeft * xspan), current_xlim[1] - (zoomFactor * (1 - xPercentLeft) * xspan))
			self.Figure.axes[0].set_xlim(new_xlim)
			self.Canvas.draw()
		elif event.button == 'down':
			# Save current figure state so the zoom operation can be undone
			self.FigureToolbar.push_current()
			# Zoom out
			zoomFactor = (1 / zoomFactor) - 1
			new_xlim = (current_xlim[0] - (zoomFactor * xPercentLeft * xspan), current_xlim[1] + (zoomFactor * (1 - xPercentLeft) * xspan))
			self.Figure.axes[0].set_xlim(new_xlim)
			self.Canvas.draw()
		return
	
	def matplotlib_button_press_event(self, event):
		if event.xdata is None or event.ydata is None or event.button is None:
			return
		if not self.actionDisplay_Calibration.isChecked():
			if event.button == 1:
				# Left mouse button was pressed
				self.CalibrationWindow.lineEditP1Bin.setText(str(int(round(event.xdata))))
			if event.button == 3:
				# Right mouse button was pressed
				self.CalibrationWindow.lineEditP2Bin.setText(str(int(round(event.xdata))))
		return
	
	def closeEvent(self, event):
		# Disable auto refresh
		self.actionAuto_Refresh_Toggle.setChecked(False)
		
		# Close calibration window
		self.CalibrationWindow.close()
		return
		
		





class Ui_AutoRefreshSetupDialog(QDialog):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	def __init__(self, parent=None):
		super().__init__(parent)
		uic.loadUi(self.ThisFileDirectory + '/../qt/AutoRefreshSetupDialog.ui', self)
		return

class Ui_HistogramNotes(QDialog):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	def __init__(self, parent=None):
		super().__init__(parent)
		uic.loadUi(self.ThisFileDirectory + '/../qt/Notes.ui', self)
		return

class Ui_HistogramParametersDialog(QDialog):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	PreviousHistogramSetupParametersPath = None
	PreviousHistogramSetupParameters = None
	HistogramOrPsdData = None

	def __init__(self, previousHistogramSetupParametersPath, histogramOrPsdData, parent=None, isotopeAbundancesDict=None):
		super().__init__(parent)
		uic.loadUi(self.ThisFileDirectory + '/../qt/HistogramParametersDialog.ui', self)
		self.LoadPreviousHistogramSetupParameters(previousHistogramSetupParametersPath)
		self.SetupAbundancesTableWithDict(isotopeAbundancesDict)
		
		self.tableWidgetIsotopeAbundances.cellChanged.connect(self.tableWidgetIsotopeAbundances_cellChanged)
		self.comboBoxScintillator.currentTextChanged.connect(self.comboBoxScintillator_changed)
		self.comboBoxPmtModelNumber.currentTextChanged.connect(self.comboBoxPmtModelNumber_changed)
		self.comboBoxPowerSupplyModelNumber.currentTextChanged.connect(self.comboBoxPowerSupplyModelNumber_changed)

		self.SetUpComboBoxes(histogramOrPsdData)
		return
	
	def SetupAbundancesTableWithDict(self, d):
		if type(d) != dict or len(d) <= 0:
			return
		isotopeCount = len(d)
		self.tableWidgetIsotopeAbundances.setRowCount(isotopeCount + 1)
		for row, isotope in enumerate(d):
			self.tableWidgetIsotopeAbundances.setItem(row, 0, QTableWidgetItem(isotope))
			self.tableWidgetIsotopeAbundances.setItem(row, 1, QTableWidgetItem(str(d[isotope])))
		self.tableWidgetIsotopeAbundances.setItem(isotopeCount, 0, None)
		self.tableWidgetIsotopeAbundances.setItem(isotopeCount, 1, None)
		return
	
	def GetIsotopeAbundancesDict(self):
		d = {}
		for row in range(self.tableWidgetIsotopeAbundances.rowCount()):
			isotope = self.tableWidgetIsotopeAbundances.item(row, 0)
			if isotope is None:
				continue
			isotope = HistogramChannel.StandardizeIsotopeString(isotope.text())
			if isotope == 'Background':
				d['Background'] = 1
				continue
			abundance = self.tableWidgetIsotopeAbundances.item(row, 1)
			if abundance is None:
				continue
			try:
				abundance = float(abundance.text())
			except:
				continue
			d[isotope] = abundance
		if len(d) > 1 and 'Background' in d:
			d.pop('Background')
		return d
	
	def LoadPreviousHistogramSetupParameters(self, filepath):
		# Get the prev parameters
		self.PreviousHistogramSetupParameters = {'Type': 'PreviousHistogramSetupParameters', 'Scintillators': dict(), 'PowerSupplyModelNumbers': dict()}
		if not os.path.isfile(filepath):
			return
		self.PreviousHistogramSetupParametersPath = filepath
		
		with open(filepath) as f:
			d = json.load(f)
		
		if d is None or type(d) != dict or d['Type'] != 'PreviousHistogramSetupParameters':
			return

		# Check and build the dictionary
		real_scintillators = {}
		if 'Scintillators' in d and type(d['Scintillators']) == dict:
			scintillators = d['Scintillators']
			for scintillatorName in scintillators:
				if type(scintillatorName) != str or 'PmtModelNumbers' not in scintillators[scintillatorName] or type(scintillators[scintillatorName]['PmtModelNumbers']) != dict:
					continue
					
				real_pmtModelNumbers = {}
				pmtModelNumbers = scintillators[scintillatorName]['PmtModelNumbers']
				for pmtModelNumberName in pmtModelNumbers:
					if type(pmtModelNumberName) != str or 'PmtSerialNumbers' not in pmtModelNumbers[pmtModelNumberName] or type(pmtModelNumbers[pmtModelNumberName]['PmtSerialNumbers']) != list:
						continue

					real_pmtSerialNumbers = [s for s in pmtModelNumbers[pmtModelNumberName]['PmtSerialNumbers'] if type(s) == str and len(s) > 0 and not s.isspace()]
					
					real_tapers = [s for s in pmtModelNumbers[pmtModelNumberName]['PmtTapers'] if type(s) == str and len(s) > 0 and not s.isspace()]

					real_pmtModelNumbers[pmtModelNumberName] = {'PmtSerialNumbers': real_pmtSerialNumbers, 'PmtTapers': real_tapers}
				real_scintillators[scintillatorName] = {'PmtModelNumbers': real_pmtModelNumbers}
		
		real_powerSupplyModelNumbers = {}
		if 'PowerSupplyModelNumbers' in d and type(d['PowerSupplyModelNumbers']) == dict:
			powerSupplyModelNumbers = d['PowerSupplyModelNumbers']
			for powerSupplyModelNumberName in powerSupplyModelNumbers:
				if type(powerSupplyModelNumberName) != str or 'PowerSupplySerialNumbers' not in powerSupplyModelNumbers[powerSupplyModelNumberName] or type(powerSupplyModelNumbers[powerSupplyModelNumberName]['PowerSupplySerialNumbers']) != list:
					continue

				real_powerSupplySerialNumbers = [s for s in powerSupplyModelNumbers[powerSupplyModelNumberName]['PowerSupplySerialNumbers'] if type(s) == str and len(s) > 0 and not s.isspace()]

				real_powerSupplyModelNumbers[powerSupplyModelNumberName] = {"PowerSupplySerialNumbers": real_powerSupplySerialNumbers}
		
		self.PreviousHistogramSetupParameters['Scintillators'] = real_scintillators
		self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers'] = real_powerSupplyModelNumbers
		
		return
	
	def SetUpComboBoxes(self, histogramOrPsdData):
		#if type(histogramOrPsdData) != HistogramChannel:
		#	return
		self.HistogramOrPsdData = histogramOrPsdData
		h = histogramOrPsdData

		scintillators = list(self.PreviousHistogramSetupParameters['Scintillators'].keys())
		if type(h.Scintillator) == str and len(h.Scintillator) > 0 and not h.Scintillator.isspace():
			if h.Scintillator not in scintillators:
				scintillators.append(h.Scintillator)
		scintillators.sort()
		self.comboBoxScintillator.addItems([''] + scintillators)
		if h.Scintillator in scintillators:
			items = [self.comboBoxScintillator.itemText(i) for i in range(self.comboBoxScintillator.count())]
			self.comboBoxScintillator.setCurrentIndex(items.index(h.Scintillator))
		
		items = [self.comboBoxPmtModelNumber.itemText(i) for i in range(self.comboBoxPmtModelNumber.count())]
		if type(h.PmtModelNumber) == str and len(h.PmtModelNumber) > 0 and not h.PmtModelNumber.isspace():
			if h.PmtModelNumber not in items:
				items.append(h.PmtModelNumber)
				items.sort()
				self.comboBoxPmtModelNumber.clear()
				self.comboBoxPmtModelNumber.addItems(items)
				self.comboBoxPmtModelNumber.setCurrentIndex(items.index(h.PmtModelNumber))
		
		items = [self.comboBoxPmtSerialNumber.itemText(i) for i in range(self.comboBoxPmtSerialNumber.count())]
		if type(h.PmtSerialNumber) == str and len(h.PmtSerialNumber) > 0 and not h.PmtSerialNumber.isspace():
			if h.PmtSerialNumber not in items:
				items.append(h.PmtSerialNumber)
				items.sort()
				self.comboBoxPmtSerialNumber.clear()
				self.comboBoxPmtSerialNumber.addItems(items)
				self.comboBoxPmtSerialNumber.setCurrentIndex(items.index(h.PmtSerialNumber))
		
		items = [self.comboBoxPmtTaper.itemText(i) for i in range(self.comboBoxPmtTaper.count())]
		if type(h.PmtTaper) == str and len(h.PmtTaper) > 0 and not h.PmtTaper.isspace():
			if h.PmtTaper not in items:
				items.append(h.PmtTaper)
				items.sort()
				self.comboBoxPmtTaper.clear()
				self.comboBoxPmtTaper.addItems(items)
				self.comboBoxPmtTaper.setCurrentIndex(items.index(h.PmtTaper))

		powerSupplyModelNumbers = list(self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers'].keys())
		if type(h.PowerSupplyModelNumber) == str and len(h.PowerSupplyModelNumber) > 0 and not h.PowerSupplyModelNumber.isspace():
			if h.PowerSupplyModelNumber not in powerSupplyModelNumbers:
				powerSupplyModelNumbers.append(h.PowerSupplyModelNumber)
		powerSupplyModelNumbers.sort()
		self.comboBoxPowerSupplyModelNumber.addItems([''] + powerSupplyModelNumbers)
		if h.PowerSupplyModelNumber in powerSupplyModelNumbers:
			items = [self.comboBoxPowerSupplyModelNumber.itemText(i) for i in range(self.comboBoxPowerSupplyModelNumber.count())]
			self.comboBoxPowerSupplyModelNumber.setCurrentIndex(items.index(h.PowerSupplyModelNumber))
		
		items = [self.comboBoxPowerSupplySerialNumber.itemText(i) for i in range(self.comboBoxPowerSupplySerialNumber.count())]
		if type(h.PowerSupplySerialNumber) == str and len(h.PowerSupplySerialNumber) > 0 and not h.PowerSupplySerialNumber.isspace():
			if h.PowerSupplySerialNumber not in items:
				items.append(h.PowerSupplySerialNumber)
				items.sort()
				self.comboBoxPowerSupplySerialNumber.clear()
				self.comboBoxPowerSupplySerialNumber.addItems(items)
				self.comboBoxPowerSupplySerialNumber.setCurrentIndex(items.index(h.PowerSupplySerialNumber))

		self.lineEditPowerSupplyVoltage.setText(str(self.HistogramOrPsdData.PowerSupplyVoltage))

		return
	
	def GetParameters(self, updateHistogram=True):
		s = self.comboBoxScintillator.currentText().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		scintillator = s

		s = self.comboBoxPmtModelNumber.currentText().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		pmtModelNumber = s

		s = self.comboBoxPmtSerialNumber.currentText().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		pmtSerialNumber = s

		s = self.comboBoxPmtTaper.currentText().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		pmtTaper = s

		s = self.comboBoxPowerSupplyModelNumber.currentText().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		powerSupplyModelNumber = s

		s = self.comboBoxPowerSupplySerialNumber.currentText().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		powerSupplySerialNumber = s

		s = self.lineEditPowerSupplyVoltage.text().strip()
		if type(s) != str or len(s) == 0 or s.isspace():
			s = None
		powerSupplyVoltage = s

		if updateHistogram:
			self.HistogramOrPsdData.Scintillator = scintillator
			self.HistogramOrPsdData.PmtModelNumber = pmtModelNumber
			self.HistogramOrPsdData.PmtSerialNumber = pmtSerialNumber
			self.HistogramOrPsdData.PmtTaper = pmtTaper
			self.HistogramOrPsdData.PowerSupplyModelNumber = powerSupplyModelNumber
			self.HistogramOrPsdData.PowerSupplySerialNumber = powerSupplySerialNumber
			self.HistogramOrPsdData.PowerSupplyVoltage = powerSupplyVoltage
		
		# Update the previous parameters list
		changed = False
		pmtModelNumbers = dict()
		if scintillator is not None:
			if scintillator not in self.PreviousHistogramSetupParameters['Scintillators']:
				self.PreviousHistogramSetupParameters['Scintillators'][scintillator] = {'PmtModelNumbers': dict()}
				changed = True
			pmtModelNumbers = self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers']
		
		pmtSerialNumbers = []
		pmtTapers = []
		if pmtModelNumber is not None:
			if pmtModelNumber not in pmtModelNumbers:
				pmtModelNumbers[pmtModelNumber] = {'PmtSerialNumbers': [], 'PmtTapers': []}
				changed = True
			pmtSerialNumbers = pmtModelNumbers[pmtModelNumber]['PmtSerialNumbers']
			pmtTapers = pmtModelNumbers[pmtModelNumber]['PmtTapers']
		
		if pmtSerialNumber is not None and pmtSerialNumber not in pmtSerialNumbers:
			pmtSerialNumbers.append(pmtSerialNumber)
			changed = True
		
		if pmtTaper is not None and pmtTaper not in pmtTapers:
			pmtTapers.append(pmtTaper)
			changed = True
		
		powerSupplySerialNumbers = []
		if powerSupplyModelNumber is not None:
			if powerSupplyModelNumber not in self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers']:
				self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers'][powerSupplyModelNumber] = {'PowerSupplySerialNumbers': []}
				changed = True
			powerSupplySerialNumbers = self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers'][powerSupplyModelNumber]['PowerSupplySerialNumbers']
		
		if powerSupplySerialNumber is not None and powerSupplySerialNumber not in powerSupplySerialNumbers:
			powerSupplySerialNumbers.append(powerSupplySerialNumber)
			changed = True

		if changed:
			with open(self.PreviousHistogramSetupParametersPath, 'w') as f:
				json.dump(self.PreviousHistogramSetupParameters, f, indent='\t')

		return scintillator, pmtModelNumber, pmtSerialNumber, pmtTaper, powerSupplyModelNumber, powerSupplySerialNumber, powerSupplyVoltage

	def comboBoxScintillator_changed(self):
		if self.PreviousHistogramSetupParameters is None:
			return
		# Populate the PMT model number box with options
		scintillator = self.comboBoxScintillator.currentText().strip()
		pmtModelNumber = self.comboBoxPmtModelNumber.currentText().strip()
		if len(pmtModelNumber) == 0 or pmtModelNumber.isspace():
			self.comboBoxPmtModelNumber.clear()
			if scintillator in self.PreviousHistogramSetupParameters['Scintillators']:
				self.comboBoxPmtModelNumber.addItems(list(self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'].keys()))
				if len(self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers']) == 1:
					self.comboBoxPmtModelNumber.setCurrentIndex(0)
				else:
					self.comboBoxPmtModelNumber.setCurrentIndex(-1)
		return
	
	def comboBoxPmtModelNumber_changed(self):
		if self.PreviousHistogramSetupParameters is None:
			return
		# Populate the PMT serial number box and taper box with options
		scintillator = self.comboBoxScintillator.currentText().strip()
		pmtModelNumber = self.comboBoxPmtModelNumber.currentText().strip()
		pmtSerialNumber = self.comboBoxPmtSerialNumber.currentText().strip()
		pmtTaper = self.comboBoxPmtTaper.currentText().strip()
		if len(pmtSerialNumber) == 0 or pmtSerialNumber.isspace():
			self.comboBoxPmtSerialNumber.clear()
			if scintillator in self.PreviousHistogramSetupParameters['Scintillators']:
				if pmtModelNumber in self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'] and 'PmtSerialNumbers' in self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'][pmtModelNumber]:
					self.comboBoxPmtSerialNumber.addItems(self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'][pmtModelNumber]['PmtSerialNumbers'])
					if len(self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'][pmtModelNumber]['PmtSerialNumbers']) == 1:
						self.comboBoxPmtSerialNumber.setCurrentIndex(0)
					else:
						self.comboBoxPmtSerialNumber.setCurrentIndex(-1)
		if len(pmtTaper) == 0 or pmtTaper.isspace():
			self.comboBoxPmtTaper.clear()
			if scintillator in self.PreviousHistogramSetupParameters['Scintillators']:
				if pmtModelNumber in self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'] and 'PmtTapers' in self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'][pmtModelNumber]:
					self.comboBoxPmtTaper.addItems(self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'][pmtModelNumber]['PmtTapers'])
					if len(self.PreviousHistogramSetupParameters['Scintillators'][scintillator]['PmtModelNumbers'][pmtModelNumber]['PmtTapers']) == 1:
						self.comboBoxPmtTaper.setCurrentIndex(0)
					else:
						self.comboBoxPmtTaper.setCurrentIndex(-1)
		return
	
	def comboBoxPowerSupplyModelNumber_changed(self):
		if self.PreviousHistogramSetupParameters is None:
			return
		# Populate the PMT model number box with options
		powerSupplyModelNumber = self.comboBoxPowerSupplyModelNumber.currentText().strip()
		powerSupplySerialNumber = self.comboBoxPowerSupplySerialNumber.currentText().strip()
		if len(powerSupplySerialNumber) == 0 or powerSupplySerialNumber.isspace():
			self.comboBoxPowerSupplySerialNumber.clear()
			if powerSupplyModelNumber in self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers']:
				self.comboBoxPowerSupplySerialNumber.addItems(self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers'][powerSupplyModelNumber]['PowerSupplySerialNumbers'])
				if len(self.PreviousHistogramSetupParameters['PowerSupplyModelNumbers'][powerSupplyModelNumber]['PowerSupplySerialNumbers']) == 1:
					self.comboBoxPowerSupplySerialNumber.setCurrentIndex(0)
				else:
					self.comboBoxPowerSupplySerialNumber.setCurrentIndex(-1)
		return
	
	def tableWidgetIsotopeAbundances_cellChanged(self, row, column):
		isotope = self.tableWidgetIsotopeAbundances.item(row, 0)
		abundance = self.tableWidgetIsotopeAbundances.item(row, 1)

		noIsotope = (isotope is None) or len(isotope.text()) == 0
		noAbundance = (abundance is None) or len(abundance.text()) == 0

		# Remove any entries that are not valid numbers
		if (not noAbundance) and column == 1:
			a = -1
			try:
				a = float(abundance.text())
			except:
				a = -1
			if a < 0:
				self.tableWidgetIsotopeAbundances.setItem(row, 1, None)
				return
		
		if noIsotope and noAbundance:
			# Remove the row
			self.tableWidgetIsotopeAbundances.removeRow(row)

		# Are any rows left?
		rowCount = self.tableWidgetIsotopeAbundances.rowCount()
		if rowCount < 1:
			# There must be at least one row, so make a blank one
			self.tableWidgetIsotopeAbundances.setRowCount(1)
			return
		
		# The last row must be blank
		isotope = self.tableWidgetIsotopeAbundances.item(rowCount - 1, 0)
		abundance = self.tableWidgetIsotopeAbundances.item(rowCount - 1, 1)
		
		noIsotope = (isotope is None) or len(isotope.text()) == 0
		noAbundance = (abundance is None) or len(abundance.text()) == 0

		if not (noIsotope and noAbundance):
			# Add a blank row
			self.tableWidgetIsotopeAbundances.setRowCount(rowCount + 1)
		return

class Ui_CalibrationDialog(QDialog):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	App = None
	Parent = None

	def __init__(self, app, parent):
		super().__init__(parent)
		self.App = app
		self.Parent = parent
		uic.loadUi(self.ThisFileDirectory + '/../qt/CalibrationDialog.ui', self)

		self.DisplayNewCalibration()

		self.lineEditP1Bin.textChanged.connect(self.DisplayNewCalibration)
		self.lineEditP1Energy.textChanged.connect(self.DisplayNewCalibration)
		self.lineEditP2Bin.textChanged.connect(self.DisplayNewCalibration)
		self.lineEditP2Energy.textChanged.connect(self.DisplayNewCalibration)

		self.buttonBox.accepted.connect(self.CommitNewCalibration)
		return
	
	def GetPointsFromDialog(self):
		try:
			bin1 = int(self.lineEditP1Bin.text())
			energy1 = float(self.lineEditP1Energy.text())
		except:
			return None, None, None, None
		bin2 = 0
		energy2 = 0
		if len(self.lineEditP2Bin.text()) > 0 or len(self.lineEditP2Energy.text()) > 0:
			try:
				bin2 = int(self.lineEditP2Bin.text())
				energy2 = float(self.lineEditP2Energy.text())
			except:
				return None, None, None, None
		return bin1, energy1, bin2, energy2
	
	def DisplayCurrentCalibration(self, CalibratedScalingFactor, CalibratedYIntercept):
		if None in [CalibratedScalingFactor, CalibratedYIntercept]:
			self.labelCurrentCalibration.setText('None')
			return

		# Update the current calibration label
		self.labelCurrentCalibration.setText('m = ' + str(round(CalibratedScalingFactor / 1e3, 1)) + ' keV/bin, b = ' + str(round(CalibratedYIntercept / 1e3, 1)) + ' keV')
		return
	
	def DisplayNewCalibration(self):
		# Get the points
		bin1, energy1, bin2, energy2 = self.GetPointsFromDialog()
		if None in [bin1, energy1, bin2, energy2]:
			self.labelNewCalibration.setText('Invalid')
			return
		
		# Calculate the new calibration, changing keV in the lineEdit boxes to eV
		CalibratedScalingFactor, CalibratedYIntercept = HistogramChannel.CalculateCalibration(bin1, energy1 * 1e3, bin2, energy2 * 1e3)
		if None in [CalibratedScalingFactor, CalibratedYIntercept]:
			self.labelNewCalibration.setText('Invalid')
			return
		
		# Update the new calibration label
		self.labelNewCalibration.setText('m = ' + str(round(CalibratedScalingFactor / 1e3, 1)) + ' keV/bin, b = ' + str(round(CalibratedYIntercept / 1e3, 1)) + ' keV')
		return
	
	def CommitNewCalibration(self):
		# Get the points
		bin1, energy1, bin2, energy2 = self.GetPointsFromDialog()
		if None in [bin1, energy1, bin2, energy2]:
			return
		
		# Calculate the new calibration, changing keV in the lineEdit boxes to eV
		CalibratedScalingFactor, CalibratedYIntercept = HistogramChannel.CalculateCalibration(bin1, energy1 * 1e3, bin2, energy2 * 1e3)
		
		# Set the new calibration
		if self.Parent.CurrentAfe is not None:
			if None in [CalibratedScalingFactor, CalibratedYIntercept]:
				self.Parent.CurrentAfe.Histogram.ClearCalibration()
			else:
				self.Parent.CurrentAfe.Histogram.Calibrate(bin1, energy1 * 1e3, bin2, energy2 * 1e3)
				if not self.Parent.actionDisplay_Calibration.isChecked():
					self.Parent.actionDisplay_Calibration.activate(Qt.QAction.Trigger)
		return
