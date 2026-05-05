#!/usr/bin/env python3

import pathlib
from PyQt5 import uic, QtCore, QtGui, QtWidgets
from UART import UART
from ForthInterface import ForthInterface
from time import sleep

class Ui_SerialTerminalWindow(QtWidgets.QMainWindow):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	App = None
	Parent = None
	uart = UART()
	Forth = None
	Baudrates = [300, 1200, 2048, 2400, 4800, 9600, 19200, 38400, 57600, 74880, 115200, 230400, 250000]
	ReceiveTimer = None
	ReceiveString = ''
	ConnectedAtStartup = False

	History = ['']
	HistoryIndex = 0
	HistoryMaxSize = 1000


	def __init__(self, app, parent=None):
		super(Ui_SerialTerminalWindow, self).__init__(parent)
		self.App = app
		self.Parent = parent
		return
	
	def setupUi(self, forth=None):
		# Load the UI configuration file
		uic.loadUi(self.ThisFileDirectory + '/../qt/SerialTerminal.ui', self)
		
		# Populate the widgets with their appropriate starting values
		self.comboBoxBaud.clear()
		self.Baudrates.sort()
		self.comboBoxBaud.addItems([str(baud) for baud in self.Baudrates])
		if 2048 in self.Baudrates:
			self.comboBoxBaud.setCurrentIndex(self.Baudrates.index(2048))	# should be 2048
		
		self.ReceiveTimer = QtCore.QTimer()
		self.ReceiveTimer.setInterval(100)	# in ms

		# If this window is a child of PyEmanate, set it up with the connected chip parameters
		if forth is not None and type(forth) == ForthInterface:
			if forth.Connected:
				self.Forth = forth
				self.uart = self.Forth.uart
				self.ConnectedAtStartup = True

				# Set up GUI
				self.pushButtonRefreshPorts.setEnabled(False)
				self.comboBoxPort.setEnabled(False)
				self.pushButtonConnect.setEnabled(False)
				self.pushButtonConnect.setText('Disconnect')

				if self.uart.Port is not None:
					self.comboBoxPort.clear()
					self.comboBoxPort.addItems([self.uart.Port])
					self.comboBoxPort.setCurrentIndex(0)
				
				if self.Forth.ActiveBoard.RomBootBaudrate not in self.Baudrates:
					self.Baudrates.append(self.Forth.ActiveBoard.RomBootBaudrate)
				if self.Forth.ActiveBoard.SpiFlashBootBaudrate not in self.Baudrates:
					self.Baudrates.append(self.Forth.ActiveBoard.SpiFlashBootBaudrate)
				if self.uart.Baudrate not in self.Baudrates:
					self.Baudrates.append(self.uart.Baudrate)
				self.Baudrates.sort()
				self.comboBoxBaud.clear()
				self.comboBoxBaud.addItems([str(baud) for baud in self.Baudrates])
				self.comboBoxBaud.setCurrentIndex(self.Baudrates.index(self.uart.Baudrate))

				# Reset button
				if self.Forth is not None and self.Forth.ActiveBoard.FtdiUseRtsDtrSequencing:
					self.checkBoxRTS.setText('Reset')
					self.checkBoxRTS.setChecked(False)
					self.Forth.DeassertReset()
				elif self.Forth.ActiveBoard.FtdiDeassertReset is not None:
					if self.Forth.ActiveBoard.FtdiDeassertReset['FtdiPin'] == 'RTS':
						if self.Forth.ActiveBoard.FtdiDeassertReset['Polarity'] == 0:
							self.checkBoxRTS.setText('reset')
						else:
							self.checkBoxRTS.setText('resetn')
						if self.Forth.uart.GetFtdiPin('rts'):
							self.checkBoxRTS.setChecked(True)
						else:
							self.checkBoxRTS.setChecked(False)
					elif self.Forth.ActiveBoard.FtdiDeassertReset['FtdiPin'] == 'DTR':
						if self.Forth.ActiveBoard.FtdiDeassertReset['Polarity'] == 0:
							self.checkBoxDTR.setText('reset')
						else:
							self.checkBoxDTR.setText('resetn')
						if self.Forth.uart.GetFtdiPin('dtr'):
							self.checkBoxDTR.setChecked(True)
						else:
							self.checkBoxDTR.setChecked(False)
				
				# Boot button
				if self.Forth is not None and self.Forth.ActiveBoard.FtdiUseRtsDtrSequencing:
					self.checkBoxDTR.setText('ROM')
					self.checkBoxDTR.setChecked(False)
					self.Forth.SetBootToSpiFlash()
				elif self.Forth.ActiveBoard.FtdiBootRom is not None:
					if self.Forth.ActiveBoard.FtdiBootRom['FtdiPin'] == 'RTS':
						if self.Forth.ActiveBoard.FtdiBootRom['Polarity'] == 0:
							self.checkBoxRTS.setText('Flash')
						else:
							self.checkBoxRTS.setText('ROM')
						if self.Forth.uart.GetFtdiPin('rts'):
							self.checkBoxRTS.setChecked(True)
						else:
							self.checkBoxRTS.setChecked(False)
					elif self.Forth.ActiveBoard.FtdiBootRom['FtdiPin'] == 'DTR':
						if self.Forth.ActiveBoard.FtdiBootRom['Polarity'] == 0:
							self.checkBoxDTR.setText('Flash')
						else:
							self.checkBoxDTR.setText('ROM')
						if self.Forth.uart.GetFtdiPin('dtr'):
							self.checkBoxDTR.setChecked(True)
						else:
							self.checkBoxDTR.setChecked(False)

				# Start the receiver timer
				self.ReceiveTimer.start()

				# Focus on the transmission box
				self.lineEditTransmit.setFocus()
		
		# Connect event signals to the appropriate function via slots
		self.pushButtonRefreshPorts.clicked.connect(self.RefreshPorts)
		self.pushButtonConnect.clicked.connect(self.OpenClose)
		self.pushButtonSend.clicked.connect(self.Send)
		self.lineEditTransmit.returnPressed.connect(self.Send)
		self.ReceiveTimer.timeout.connect(self.LookForNewReceiveData)
		self.checkBoxDTR.stateChanged.connect(self.ToggleDTR)
		self.checkBoxRTS.stateChanged.connect(self.ToggleRTS)
		self.comboBoxBaud.currentIndexChanged.connect(self.ChangeBaud)
		self.pushButtonClearReceive.clicked.connect(self.ClearReceivedTranscript)
		self.lineEditTransmit.installEventFilter(self)

		return
	
	def RefreshPorts(self):
		if self.uart.IsOpen:
			return
		currentPort = None
		if self.comboBoxPort.currentIndex() >= 0:
			currentPort = self.comboBoxPort.currentText()
			if len(currentPort) < 1:
				currentPort = None
		tmpuart = UART()
		ports = tmpuart.GetAvailableSerialPorts()
		self.comboBoxPort.clear()
		self.comboBoxPort.addItems(ports)
		if currentPort is not None:
			for i, port in enumerate(ports):
				if port == currentPort:
					self.comboBoxPort.setCurrentIndex(i)
					break
		return
	
	def GetDesiredBaudFromComboBox(self):
		baudstr = self.comboBoxBaud.currentText()
		if baudstr is None:
			return None
		if len(baudstr) < 1:
			return None
		try:
			baud = int(baudstr)
		except ValueError:
			return None
		return baud
	
	def GetDesiredLineEnding(self):
		if self.radioButtonLineEndingLF.isChecked():
			return '\n'
		elif self.radioButtonLineEndingCR.isChecked():
			return '\r'
		elif self.radioButtonLineEndingCRLF.isChecked():
			return '\r\n'
		return ''
		
	def OpenClose(self):
		if self.uart.IsOpen:
			self.Close()
		else:
			self.Open()
		return
	
	def Open(self):
		if self.uart.IsOpen:
			return
		
		## Get the desired port
		#if self.uart.using_pylibftdi:
		#	port = self.comboBoxPort.currentIndex()
		#else:
		#	port = self.comboBoxPort.currentText()
		#	if port is None:
		#		return
		#	if len(port) < 1:
		#		return
			
		port = self.comboBoxPort.currentText()
		if port is None:
			return
		if len(port) < 1:
			return
		
		# Get the desired baud
		baudrate = self.GetDesiredBaudFromComboBox()
		if baudrate is None:
			return
		
		# Get RTS and DTR status
		initialRTS = self.checkBoxRTS.isChecked()
		initialDTR = self.checkBoxDTR.isChecked()
		
		# Open the port
		if not self.uart.Open(port, baudrate, initialRTS=initialRTS, initialDTR=initialDTR):
			return
		#self.uart.libftdi_timeout = 16e-3
		sleep(50e-3)
		self.uart.FlushBuffers()
		
		# Update the GUI
		self.pushButtonConnect.setText('Disconnect')
		self.comboBoxPort.setEnabled(False)
		
		# Start the timer
		self.ReceiveTimer.start()
		
		return
	
	def Close(self):
		# Stop the timer
		self.ReceiveTimer.stop()
		
		# Close the port
		self.uart.Close()
		
		# Update the GUI
		self.pushButtonConnect.setText('Connect')
		self.comboBoxPort.setEnabled(True)
		
		return
	
	def Send(self):
		if not self.uart.IsOpen:
			return
		s = self.lineEditTransmit.text()
		self.lineEditTransmit.setText('')
		self.lineEditTransmit.setFocus()
		self.uart.Write(s + self.GetDesiredLineEnding())
		if not s.isspace():
			if s == self.History[self.HistoryIndex]:
				# Sending an item from the history again
				# Move it from its location in the history and put it at the end of the history
				self.History = self.History[:self.HistoryIndex] + self.History[self.HistoryIndex + 1 : len(self.History) - 1] + [s, '']
			else:
				# Set the last index of the history to the text just sent, replacing the "blank" that is there
				self.History[-1] = s

				# Add a "blank" to the end of the history
				self.History.append('')

			if len(self.History) > self.HistoryMaxSize:
				self.History = self.History[(len(self.History) - self.HistoryMaxSize):len(self.History)]
		self.HistoryIndex = len(self.History) - 1
		return
	
	def LookForNewReceiveData(self):
		if not self.uart.IsOpen:
			self.Close()
			return
		
		newStringData = self.uart.Read()
		if newStringData is None:
			self.Close()
			return
		elif len(newStringData) > 0:
			self.ReceiveString += newStringData
			scrollValue = self.textEditReceive.verticalScrollBar().value()
			self.textEditReceive.moveCursor(QtGui.QTextCursor.End)
			self.textEditReceive.insertPlainText(newStringData)
			if self.checkBoxAutoscroll.isChecked():
				self.textEditReceive.moveCursor(QtGui.QTextCursor.End)
			else:
				self.textEditReceive.verticalScrollBar().setValue(scrollValue)
		
		return
	
	def ToggleDTR(self):
		if not self.uart.IsOpen:
			return
		if self.Forth is not None and self.Forth.ActiveBoard.FtdiUseRtsDtrSequencing:
			if self.checkBoxDTR.isChecked():
				self.Forth.SetBootToRom()
			else:
				self.Forth.SetBootToSpiFlash()
		else:
			self.uart.SetFtdiPin('DTR', self.checkBoxDTR.isChecked())
		return
	
	def ToggleRTS(self):
		if not self.uart.IsOpen:
			return
		if self.Forth is not None and self.Forth.ActiveBoard.FtdiUseRtsDtrSequencing:
			if self.checkBoxRTS.isChecked():
				self.Forth.AssertReset()
			else:
				self.Forth.DeassertReset()
		else:
			self.uart.SetFtdiPin('RTS', self.checkBoxRTS.isChecked())
		return
	
	def ChangeBaud(self):
		if not self.uart.IsOpen:
			return
		baud = self.GetDesiredBaudFromComboBox()
		if baud is None:
			return
		self.uart.Baudrate = baud
		return
	
	def ClearReceivedTranscript(self):
		self.ReceiveString = ''
		self.textEditReceive.setText('')
		return
	
	def eventFilter(self, sender, event):
		if sender == self.lineEditTransmit:
			if event.type() == QtCore.QEvent.KeyPress:
				if event.key() == QtCore.Qt.Key_Up:
					# Scroll backwards through history
					self.SelectRelativeHistoryItem(-1)
					return True
				elif event.key() == QtCore.Qt.Key_Down:
					# Scroll forwards through history
					self.SelectRelativeHistoryItem(1)
					return True
		return False

	def SelectRelativeHistoryItem(self, positionsAway:int):
		index = self.HistoryIndex
		if positionsAway < 0:
			index = max(self.HistoryIndex + positionsAway, 0)
		elif positionsAway > 0:
			index = min(self.HistoryIndex + positionsAway, len(self.History) - 1)
		
		self.HistoryIndex = index
		self.lineEditTransmit.setText(self.History[self.HistoryIndex])
		return
	
	def closeEvent(self, event):
		if self.ConnectedAtStartup != True:
			self.Close()
		self.ReceiveTimer.stop()
		return
		
if __name__ == '__main__':
	import sys
	app = QtWidgets.QApplication(sys.argv)
	MainWindow = Ui_SerialTerminalWindow(app)
	MainWindow.setupUi()
	MainWindow.show()
	sys.exit(app.exec_())
