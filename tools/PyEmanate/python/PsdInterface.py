import sys, os, pathlib, json
from time import sleep
from datetime import datetime
from PyQt5 import uic, QtCore, QtGui, QtWidgets, Qt
from PyQt5.QtWidgets import QVBoxLayout, QFileDialog, QDialog, QTableWidgetItem, QMessageBox, QInputDialog

from UART import UART
from ForthInterface import ForthInterface
from AFE import AFE
from PsdChannel import PsdChannel
from HistogramChannel import HistogramChannel
from HistogramInterface import Ui_HistogramParametersDialog
from HelperFunctions import *

from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.backends.backend_qt5agg import NavigationToolbar2QT as NavigationToolbar
from matplotlib.figure import Figure
import matplotlib.pyplot as plt
import matplotlib

import numpy as np

class Ui_PsdInterfaceWindow(QtWidgets.QMainWindow):
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
	AutoRefreshClearAtStart = False
	AutoRefreshIndex = None
	AutoRefreshTimer = None

	CurrentAValue = None

	def __init__(self, app, parent):
		super(Ui_PsdInterfaceWindow, self).__init__(parent)
		self.App = app
		self.Parent = parent
		return
	
	def setupUi(self, forth:ForthInterface):
		# Load the UI configuration file
		uic.loadUi(self.ThisFileDirectory + '/../qt/PsdInterface.ui', self)
		self.Forth = forth

		# Add each AFE to the action menu, selecting the first one
		self.CurrentAfe = self.Forth.ActiveChip.AFEs[0]
		for afe in self.Forth.ActiveChip.AFEs:
			# Set the die ID for each AFE
			afe.Psd.DieID = self.Forth.ActiveChip.DieID
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

		# Create a figure to plot on
		self.Figure = Figure()

		# Create a canvas widget to house the figure
		self.Canvas = FigureCanvas(self.Figure)

		# Create a navigation toolbar for the figure & canvas
		self.FigureToolbar = NavigationToolbar(self.Canvas, self)

		# Add the canvas to the central widget
		layout = self.centralwidget.layout()
		layout.addWidget(self.labelStatus, 0, 1)
		layout.addWidget(self.FigureToolbar, 0, 0)
		layout.addWidget(self.Canvas, 1, 0, 1, 2)
		self.FigureToolbar.setMinimumSize(500, 0)
			
		# Add event handlers
		self.action_Save_PSD_Data.triggered.connect(self.action_Save_PSD_Data_triggered)
		self.action_Quick_Save_PSD_Data.triggered.connect(self.action_Quick_Save_PSD_Data_triggered)
		self.action_Save_PSD_Plot_PNG.triggered.connect(self.action_Save_PSD_Plot_PNG_triggered)
		self.action_Save_PSD_Plot_PGF.triggered.connect(self.action_Save_PSD_Plot_PGF_triggered)
		self.action_Save_PSD_Plot_Images.triggered.connect(self.action_Save_PSD_Plot_Images_triggered)

		self.actionRefresh.triggered.connect(self.RefreshPsdData)
		self.action_Clear.triggered.connect(self.actionClear_triggered)
		self.actionAuto_Refresh_Setup.triggered.connect(self.actionAuto_Refresh_Setup_triggered)
		self.actionAuto_Refresh_Toggle.triggered.connect(self.actionAuto_Refresh_Toggle_triggered)
		self.actionSet_Parameters.triggered.connect(self.actionSet_Parameters_triggered)
		self.actionNotes.triggered.connect(self.actionNotes_triggered)
		self.actionOpen_PsdData_Folder.triggered.connect(self.actionOpen_PsdData_Folder_triggered)
		self.actionGrid.triggered.connect(self.UpdatePlot)
		self.action_Logarithmic_Scale.triggered.connect(self.UpdatePlot)
		
		self.AutoRefreshTimer.timeout.connect(self.AutoRefreshTimer_timeout)
		
		# Update the plot
		self.UpdatePlot()
		self.UpdateStatusText()

		return
	
	def MessageBox(self, text:str, title='', icon=QMessageBox.Warning):
		msg = QMessageBox()
		msg.setText(text)
		msg.setWindowTitle(title)
		msg.setIcon(icon)
		msg.exec_()
		return

	def UpdatePlot(self):
		# Load the default style and make some changes
		self.CurrentAfe.Psd.LoadPgfPlotStyle(plt)
		matplotlib.rcParams['font.size'] = 16
		matplotlib.rcParams['figure.subplot.top'] = 0.9

		# Make the plot
		title = 'PSD Heatmap for ' + self.Forth.ActiveChip.DieID + ':' + self.CurrentAfe.Name
		self.CurrentAfe.Psd.Plot(self.Figure, title=title, log=self.action_Logarithmic_Scale.isChecked(), grid=self.actionGrid.isChecked(), smooth=self.action_Smooth.isChecked())

		# Update the status text
		self.UpdateStatusText()

		# Draw the plot
		self.Canvas.draw()
		return
	

	def RefreshPsdData(self):
		# Update GUI
		self.statusbar.showMessage('Refreshing ' + self.CurrentAfe.Name + '...', 5000)
		self.repaint()	# Force the thread to update the GUI right now

		# Get the new data
		if self.Forth.GetPsdData(self.CurrentAfe.Index) is None:
			self.statusbar.showMessage('Could not refresh ' + self.CurrentAfe.Name, 5000)
			return
		if self.actionAuto_Clear.isChecked():
			self.ClearPsdData()
			self.CurrentAfe.Psd.ClearDataTimestamp = self.PreviousRefreshTimestamp

		# Plot the PSD data
		self.UpdatePlot()
		if self.action_Auto_Save_PSD_Data.isChecked():
			self.action_Quick_Save_PSD_Data_triggered()
		self.statusbar.showMessage(self.CurrentAfe.Name + ' has been updated', 5000)
		return
	
	def ClearPsdData(self):
		self.Forth.ClearPsdData(self.CurrentAfe.Index, clearComputerPsdData=True)
		self.UpdatePlot()
		self.statusbar.showMessage(self.CurrentAfe.Name + ' PSD data has been cleared', 5000)
		return

	def SavePsdData(self, dialog=False):
		# Get default directory and file name
		directory = self.CurrentAfe.Parent.DataDirectory + '/PsdData/' + self.CurrentAfe.Psd.DieID
		
		timestampStr = get_string_timestamp(dt=self.CurrentAfe.Psd.Timestamp, includeSeconds=True)

		dialogText = 'Save PSD Data'
		dialogExtensions = 'JSON File (*.json);;CSV File (*.csv *.txt)'
		fileName = 'PsdData-' + self.CurrentAfe.Psd.DieID + '-' + self.CurrentAfe.Psd.AfeName + '-' + timestampStr + '.json'

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

		# What is the file type?
		fileNameLower = fileName.lower()
		if fileNameLower.endswith('.json'):
			# Save as a JSON
			# Include the register values and DNL data, if desired
			self.CurrentAfe.Psd.SaveJson(outPath, registerValues=registerValues)
		elif fileNameLower.endswith('.csv') or fileNameLower.endswith('.txt'):
			# Save as a CSV
			self.CurrentAfe.Psd.SaveCsv(outPath, self.actionCorrect_for_DNL.isChecked())
		else:
			ext = fileName.split('.')[-1]
			self.MessageBox('Invalid file extension ' + ext, title='Error saving PSD data')
			return
		
		# Show a message
		self.statusbar.showMessage('Saved ' + self.CurrentAfe.Psd.DieID + ':' + self.CurrentAfe.Psd.AfeName + ' PSD data as ' + fileName, 5000)
		
		return
	
	def UpdateStatusText(self):
		s = 'Auto refresh '
		if self.actionAuto_Refresh_Toggle.isChecked():
			s += 'active'
		else:
			s += 'inactive'
		
		if self.CurrentAfe.Psd.MeasuredIsotopeAbundances is None:
			s += '\nIsotopes not specified'
		else:
			s += '\nIsotopes: '
			for isotope in self.CurrentAfe.Psd.MeasuredIsotopeAbundances:
				s += isotope + ', '
			s = s[:-2]
		
		
		if self.CurrentAfe.Psd.NumPsdDataPoints is not None:
			s += '\n{:,} total data points'.format(self.CurrentAfe.Psd.NumPsdDataPoints)
			if self.CurrentAfe.Psd.NumValidPsdDataPoints is not None:
				s += '; {:,} valid'.format(self.CurrentAfe.Psd.NumValidPsdDataPoints)
		
		if self.CurrentAValue is not None:
			s += '\nDPS "A" value = ' + str(self.CurrentAValue)

		self.labelStatus.setText(s)
		return
			
	



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
		self.UpdatePlot()

		return
	
	def actionClear_triggered(self):
		self.ClearPsdData()
	
	def action_Quick_Save_PSD_Data_triggered(self):
		self.SavePsdData(dialog=False)
	
	def action_Save_PSD_Data_triggered(self):
		self.SavePsdData(dialog=True)
	
	def action_Save_PSD_Plot_PGF_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/PsdPlots/' + self.CurrentAfe.Psd.DieID
		fileName = 'PsdPlot-' + self.CurrentAfe.Psd.DieID + '-' + self.CurrentAfe.Psd.AfeName + '-' + get_string_timestamp(dt=self.CurrentAfe.Psd.Timestamp, includeSeconds=True) + '.pgf'
		outPath = directory + '/' + fileName
		if not os.path.isdir(directory):
			outPath = fileName
		outPath, ok = QFileDialog.getSaveFileName(self, 'Save PSD Plot', outPath, 'PGF File (*.pgf)')
		if not ok:
			return
		
		self.CurrentAfe.Psd.SavePlot(outPath, grid=self.actionGrid.isChecked())

		self.statusbar.showMessage('Saved ' + self.CurrentAfe.Psd.DieID + ':' + self.CurrentAfe.Psd.AfeName + ' PSD plot as ' + fileName, 5000)
		return
	
	def action_Save_PSD_Plot_PNG_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/PsdPlots/' + self.CurrentAfe.Psd.DieID
		fileName = 'PsdPlot-' + self.CurrentAfe.Psd.DieID + '-' + self.CurrentAfe.Psd.AfeName + '-' + get_string_timestamp(dt=self.CurrentAfe.Psd.Timestamp, includeSeconds=True) + '.png'
		outPath = directory + '/' + fileName
		if not os.path.isdir(directory):
			outPath = fileName
		outPath, ok = QFileDialog.getSaveFileName(self, 'Save PSD Plot', outPath, 'PGF File (*.pgf)')
		if not ok:
			return
		
		self.CurrentAfe.Psd.SavePlot(outPath, grid=self.actionGrid.isChecked())

		self.statusbar.showMessage('Saved ' + self.CurrentAfe.Psd.DieID + ':' + self.CurrentAfe.Psd.AfeName + ' PSD plot as ' + fileName, 5000)
		return
	
	def action_Save_PSD_Plot_Images_triggered(self):
		self.action_Save_PSD_Plot_PNG_triggered()
		self.action_Save_PSD_Plot_PGF_triggered()
		return
	
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
		diag.checkBoxClearHistogramAtStart.setChecked(self.AutoRefreshClearAtStart)
		diag.checkBoxUseTimedHist.setChecked(False)
		diag.checkBoxUseTimedHist.setVisible(False)
		if diag.exec():
			# OK (or return) was pressed
			seconds = diag.spinBoxAutoRefreshTimeHours.value() * 3600 + diag.spinBoxAutoRefreshTimeMinutes.value() * 60 + diag.spinBoxAutoRefreshTimeSeconds.value()
			if seconds <= 0:
				self.statusbar.showMessage('Invalid auto refresh time, must be greater than 0', 5000)
				return
			self.AutoRefreshTime = seconds
			self.AutoRefreshIterations = diag.spinBoxAutoRefreshIterations.value()
			self.AutoRefreshClearAtStart = diag.checkBoxClearHistogramAtStart.isChecked()
		return
	
	def actionNotes_triggered(self):
		diag = Ui_HistogramNotes()
		diag.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
		diag.textEditNotes.setText(self.CurrentAfe.Psd.Notes)
		if diag.exec():
			self.CurrentAfe.Psd.Notes = diag.textEditNotes.toPlainText()
		return
	
	def actionAuto_Refresh_Toggle_triggered(self):
		if self.actionAuto_Refresh_Toggle.isChecked():
			# Are the parameters for auto refresh configured?
			if self.AutoRefreshTime is None or self.AutoRefreshIterations is None:
				self.actionAuto_Refresh_Setup_triggered()
			if self.AutoRefreshTime is None or self.AutoRefreshIterations is None:
				self.actionAuto_Refresh_Toggle.setChecked(False)
				return
			
			# Do we need to clear the data before beginning the auto refresh?
			if self.AutoRefreshClearAtStart:
				self.ClearPsdData()
			
			# Start the timer
			self.AutoRefreshTimer.setInterval(self.AutoRefreshTime * 1000)	# setInterval expects milliseconds, but AutoRefreshTime is in seconds
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
		self.RefreshPsdData()

		msg = 'Auto refreshed PSD data ' + str(self.AutoRefreshIndex)
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
		h = self.CurrentAfe.Psd
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
	
	def actionAuto_Save_triggered(self):
		pass
	
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
		self.CurrentAfe.Psd.PowerSupplyVoltage = 'A = ' + str(A)
		self.UpdateStatusText()
		
		return
	
	def actionOpen_PsdData_Folder_triggered(self):
		directory = self.CurrentAfe.Parent.DataDirectory + '/PsdData/' + self.CurrentAfe.Psd.DieID
		if os.path.isdir(directory):
			os.startfile(directory)
		return
	
	def closeEvent(self, event):
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
