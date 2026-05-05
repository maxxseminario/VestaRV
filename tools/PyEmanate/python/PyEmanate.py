#!/usr/bin/env python3

from audioop import add
import sys, os, pathlib, json
from PyQt5 import uic, QtCore, QtGui, QtWidgets
from PyQt5.QtWidgets import QMessageBox

from Chip import Chip
from UART import UART, GetOS
from ForthInterface import ForthInterface

from SerialTerminal import Ui_SerialTerminalWindow
from RegisterInterface import Ui_RegisterInterfaceWindow
from HistogramInterface import Ui_HistogramInterfaceWindow
from PsdInterface import Ui_PsdInterfaceWindow
from FatfsBrowser import Ui_FatfsBrowserWindow

class Ui_PyEmanateWindow(QtWidgets.QMainWindow):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	App = None
	Parent = None
	Forth = ForthInterface()
	
	RegisteredChips = None
	
	# Windows
	SerialTerminalWindow = None
	RegisterInterfaceWindow = None
	HistogramInterfaceWindow = None
	PsdInterfaceWindow = None
	FatfsBrowserWindow = None



	def __init__(self, app, parent=None):
		super(Ui_PyEmanateWindow, self).__init__(parent)
		self.App = app
		self.Parent = parent
		return
	

	# UI Setup
	def setupUi(self):
		# Load the UI configuration file
		uic.loadUi(self.ThisFileDirectory + '/../qt/PyEmanateQt.ui', self)

		# Set the icon
		if GetOS() == 'windows':
			import ctypes
			myappid = 'unl.PyEmanate.1.0'
			ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(myappid)
			self.setWindowIcon(QtGui.QIcon(self.ThisFileDirectory + '/../qt/ic2.png'))
		
		# Connect event signals to the appropriate function via slots
		self.pushButtonRefreshSerialPortsList.clicked.connect(self.pushButtonRefreshSerialPortsList_clicked)
		self.pushButtonConnect.clicked.connect(self.pushButtonConnect_clicked)
		self.listWidgetChipName.currentItemChanged.connect(self.listWidgetChipName_currentItemChanged)
		self.lineEditDieID.returnPressed.connect(self.pushButtonConnect_clicked)
		
		self.pushButtonSerialTerminal.clicked.connect(self.pushButtonSerialTerminal_clicked)
		self.pushButtonRegisterInterface.clicked.connect(self.pushButtonRegisterInterface_clicked)
		self.pushButtonHistogramInterface.clicked.connect(self.pushButtonHistogramInterface_clicked)
		self.pushButtonFatfsBrowser.clicked.connect(self.pushButtonFatfsBrowser_clicked)
		self.pushButtonPsdInterface.clicked.connect(self.pushButtonPsdInterface_clicked)

		return
	
	def setupChips(self):
		# Load config
		self.LoadPyEmanateConfig()

		# Automatically load the available serial ports
		self.RefreshAvailableSerialPorts()

		# Load the "last connection" data
		lastConnectionPath = self.ThisFileDirectory + '/../config/LastConnection.json'
		if os.path.exists(lastConnectionPath):
			with open(lastConnectionPath, 'r') as f:
				d = json.load(f)
			if (d is not None) and ('FileType' in d) and (d['FileType'] == 'LastConnection'):
				# Select the previously connected port
				for i in range(self.listWidgetSerialPorts.count()):
					item = self.listWidgetSerialPorts.item(i)
					if item.text() == d['Port']:
						self.listWidgetSerialPorts.setCurrentItem(item)
						break
				
				# Select the previously connected chip
				for i in range(self.listWidgetChipName.count()):
					item = self.listWidgetChipName.item(i)
					if item.text() == d['ChipName']:
						self.listWidgetChipName.setCurrentItem(item)
						break
				
				# Select the previously connected board
				for i in range(self.listWidgetBoardName.count()):
					item = self.listWidgetBoardName.item(i)
					if item.text() == d['BoardName']:
						self.listWidgetBoardName.setCurrentItem(item)
						break
				
				# Give focus to the Die ID text box
				self.lineEditDieID.setFocus()
		
		return
	


	# Methods
	def MessageBox(self, text:str, title='', icon=QMessageBox.Warning):
		msg = QMessageBox()
		msg.setText(text)
		msg.setWindowTitle(title)
		msg.setIcon(icon)
		msg.exec_()
		return

	def LoadPyEmanateConfig(self):
		# Load the PyEmanate config
		configPath = self.ThisFileDirectory + '/../config/PyEmanateConfig.json'
		if not os.path.exists(configPath):
			self.MessageBox('Could not find the PyEmanate config file, which should have been located at ' + configPath + '\nPlease set up the PyEmante config file at that location.', title='Error')
			exit(0)
		with open(configPath, 'r') as f:
			config = json.load(f)
		if config is None or type(config) != dict:
			self.MessageBox('The PyEmanate config file is not a properly formatted json file. Please set it up correctly. It needs to be located at ' + configPath, title='Error')
			exit(0)
		if ('FileType' not in config) or (config['FileType'] != 'PyEmanateConfig'):
			self.MessageBox('The PyEmanate config file is not a properly formatted json file. Please set it up correctly. It needs to be located at ' + configPath, title='Error')
			exit(0)
		
		# Get the chip root directories from the config file
		if not 'ChipRootDirectories' in config:
			self.MessageBox('The PyEmanate config file does not contain a list of chip root directories. Please set it up correctly. It is located at ' + configPath, title='Error')
			exit(0)
		chipRootDirs = config['ChipRootDirectories']

		# Load each registered chip config
		self.RegisteredChips = []
		for rootDir in chipRootDirs:
			absRootDir = str(pathlib.Path(os.path.expanduser(rootDir)).absolute())
			chipConfig = Chip.CreateFromChipRootDirectory(absRootDir)
			if chipConfig is not None:
				self.RegisteredChips.append(chipConfig)
			else:
				print('The path ' + rootDir + ' is not the root directory of a chip')
		
		self.RegisteredChips.sort(key=lambda x: x.Name)

		# Add each chip to the list widget
		chipNames = [chip.Name for chip in self.RegisteredChips]
		self.listWidgetChipName.clear()
		self.listWidgetChipName.addItems(chipNames)
		
		return
	
	def RefreshAvailableSerialPorts(self):
		# If a serial port has already been selected, remember it so it can be re-selected later
		priorSelectedPort = None
		priorSelectedPorts = [selectedItem.text() for selectedItem in self.listWidgetSerialPorts.selectedItems()]
		if len(priorSelectedPorts) == 1:
			priorSelectedPort = priorSelectedPorts[0]
		
		# Get the available serial ports	
		ser = UART()
		self.listWidgetSerialPorts.clear()
		availablePorts = ser.GetAvailableSerialPorts()
		self.listWidgetSerialPorts.addItems(availablePorts)

		# If a serial port was selected before, re-select it now
		if priorSelectedPort is not None:
			for i in range(self.listWidgetSerialPorts.count()):
				item = self.listWidgetSerialPorts.item(i)
				if item.text() == priorSelectedPort:
					self.listWidgetSerialPorts.setCurrentItem(item)
					break
		
		# If only one serial port is available, select it now
		if len(availablePorts) == 1:
			self.listWidgetSerialPorts.setCurrentItem(self.listWidgetSerialPorts.item(0))
			
		self.statusbar.showMessage('Refreshed available ports: ' + str(len(availablePorts)) + ' available', 5000)
		return
	
	def Connect(self):
		# Get the selected serial port
		selectedPorts = [selectedItem.text() for selectedItem in self.listWidgetSerialPorts.selectedItems()]
		if len(selectedPorts) == 0:
			self.MessageBox('No serial port selected', title='Warning')
			return False
		elif len(selectedPorts) > 1:
			self.MessageBox('Please select only one serial port', title='Warning')
			return False
		port = selectedPorts[0]

		# Get the chip name
		chipName = self.listWidgetChipName.currentItem()
		if chipName is None:
			self.MessageBox('Please select a chip', 'Warning')
			return False
		chipName = chipName.text()
		selectedChip = None
		for chip in self.RegisteredChips:
			if chipName == chip.Name:
				selectedChip = chip
				break
		if selectedChip is None:
			return False

		# Get the die ID
		dieID = self.lineEditDieID.text().upper()
		for c in dieID:
			if c not in '0123456789ABCDEF':
				self.MessageBox('Invalid character(s) in die ID', 'Warning')
				return False
		if len(dieID) == 0:
			self.MessageBox('Please enter a die ID')
			return False
		elif len(dieID) == 3:
			dieID = selectedChip.IDChipPrefix + dieID
		elif len(dieID) == 5:
			if dieID[0:2] != selectedChip.IDChipPrefix:
				self.MessageBox('Mismatched die ID prefix for chip.\n' + selectedChip.Name + ' has a die ID prefix of ' + selectedChip.IDChipPrefix)
				return False
		else:
			self.MessageBox('Improper die ID length. The die ID is 3 hexadecimal characters long (or 5 total characters if you include the 2-character chip ID prefix)')
			return False
		selectedChip.DieID = dieID
		selectedChip.DieIDSuffix = dieID[2:]
		
		# Get the board name
		boardName = self.listWidgetBoardName.currentItem()
		if boardName is None:
			self.MessageBox('Please select a board', 'Warning')
			return False
		boardName = boardName.text()
		selectedBoard = None
		for board in selectedChip.Boards:
			if boardName == board.Name:
				selectedBoard = board
				break
		if selectedBoard is None:
			return False
		
		# Connect
		self.statusbar.showMessage('Connecting...', 5000)
		self.repaint()	# Force the thread to update the GUI right now

		if not self.Forth.Connect(selectedChip, selectedBoard, port, desiredBootMode=None, addUserDefinedFunctions=False):
			self.MessageBox('Unable to connect')
			self.statusbar.showMessage('Unable to connect', 5000)
			return False
		
		# If in ROM boot mode and the baudrate is not the desired baud rate, change it
		if self.Forth.ActiveBootMode == 'ROM' and self.Forth.uart.Baudrate != self.Forth.ActiveBoard.NormalBaudrate:
			if self.Forth.ChangeBaudrateUsingHFXT(self.Forth.ActiveBoard.NormalBaudrate) != True:
				self.MessageBox('Unable to change baudrate')
				self.statusbar.showMessage('Unable to change baudrate', 5000)
				return False
		self.Forth.uart.Timeout = 0.5

		self.Forth.AddUserDefinedFunctions()

		# Save a json file with the "last connection" details
		d = {
			'FileType': 'LastConnection',
			'Port': str(port),
			'ChipName': chipName,
			'BoardName': boardName,
			'DieID': dieID
		}
		with open(self.ThisFileDirectory + '/../config/LastConnection.json', 'w', newline='\n') as f:
			json.dump(d, f, indent='\t')
		
		# Update the GUI
		self.labelConnection.setText('Status: Connected to ' + selectedChip.Name + ':' + dieID + ' on board ' + selectedBoard.Name)
		self.pushButtonConnect.setText('Disconnect')
		self.listWidgetSerialPorts.setEnabled(False)
		self.pushButtonRefreshSerialPortsList.setEnabled(False)
		self.listWidgetChipName.setEnabled(False)
		self.lineEditDieID.setEnabled(False)
		self.listWidgetBoardName.setEnabled(False)

		self.statusbar.showMessage('Connected to ' + selectedChip.Name + ':' + dieID, 5000)

		return True
	
	def Disconnect(self):
		self.Forth.Disconnect()

		# Update the GUI
		self.labelConnection.setText('Status: Not Connected')
		self.pushButtonConnect.setText('Connect')
		self.listWidgetSerialPorts.setEnabled(True)
		self.pushButtonRefreshSerialPortsList.setEnabled(True)
		self.listWidgetChipName.setEnabled(True)
		self.lineEditDieID.setEnabled(True)
		self.listWidgetBoardName.setEnabled(True)

		self.statusbar.showMessage('Disconnected', 5000)

		return




	# Event Handlers
	def pushButtonRefreshSerialPortsList_clicked(self):
		self.RefreshAvailableSerialPorts()
		return
	
	def pushButtonConnect_clicked(self):
		if self.Forth.Connected:
			self.Disconnect()
		else:
			self.Connect()
		return
	
	def listWidgetChipName_currentItemChanged(self):
		self.listWidgetBoardName.clear()

		# Get the selected chip
		chipName = self.listWidgetChipName.currentItem().text()
		selectedChip = None
		for chip in self.RegisteredChips:
			if chipName == chip.Name:
				selectedChip = chip
				break
		if selectedChip is None:
			return
		
		# Get the list of available boards
		boardNames = [board.Name for board in selectedChip.Boards]
		self.listWidgetBoardName.addItems(boardNames)

		return
	
	def pushButtonSerialTerminal_clicked(self):
		self.SerialTerminalWindow = Ui_SerialTerminalWindow(self.App, parent=None)
		forth = None
		if self.Forth.Connected:
			forth = self.Forth
		self.SerialTerminalWindow.setupUi(forth=forth)
		self.SerialTerminalWindow.show()
		return
	
	def pushButtonRegisterInterface_clicked(self):
		if self.Forth.ActiveChip is None or not self.Forth.uart.Connected:
			self.MessageBox('Must connect to a chip before lauching the register interface')
			return
		self.RegisterInterfaceWindow = Ui_RegisterInterfaceWindow(self.App, parent=None)
		self.RegisterInterfaceWindow.setupUi(self.Forth)
		self.RegisterInterfaceWindow.show()
		return
	
	def pushButtonHistogramInterface_clicked(self):
		if self.Forth.ActiveChip is None or not self.Forth.uart.Connected:
			self.MessageBox('Must connect to a chip before lauching the histogram interface')
			return
		if self.Forth.ActiveChip.AFEs is None or len(self.Forth.ActiveChip.AFEs) == 0:
			self.MessageBox('This chip does not have any analog front-ends that can display hisotgrams')
			return
		self.HistogramInterfaceWindow = Ui_HistogramInterfaceWindow(self.App, parent=None)
		self.HistogramInterfaceWindow.setupUi(self.Forth)
		self.HistogramInterfaceWindow.show()
		return
	
	def pushButtonFatfsBrowser_clicked(self):
		if self.Forth.ActiveChip is None or not self.Forth.uart.Connected:
			self.MessageBox('Must connect to a chip before lauching the histogram interface')
			return
		if self.Forth.ActiveBootMode != 'SpiFlash':
			self.MessageBox('The FATFS browser is only available when the chip is loaded with the rv4th program and booted in SPI Flash mode')
			return
		self.FatfsBrowserWindow = Ui_FatfsBrowserWindow(self.App, parent=None)
		self.FatfsBrowserWindow.setupUi(self.Forth)
		self.FatfsBrowserWindow.show()
		return
	
	def pushButtonPsdInterface_clicked(self):
		if self.Forth.ActiveChip is None or not self.Forth.uart.Connected:
			self.MessageBox('Must connect to a chip before lauching the PSD interface')
			return
		if self.Forth.ActiveChip.AFEs is None or len(self.Forth.ActiveChip.AFEs) == 0:
			self.MessageBox('This chip does not have any analog front-ends that can display hisotgrams')
			return
		self.PsdInterfaceWindow = Ui_PsdInterfaceWindow(self.App, parent=None)
		self.PsdInterfaceWindow.setupUi(self.Forth)
		self.PsdInterfaceWindow.show()
		return
	
	def closeEvent(self, event):
		if self.App is not None:
			self.App.closeAllWindows()
		return




if __name__ == "__main__":
	app = QtWidgets.QApplication(sys.argv)
	MainWindow = Ui_PyEmanateWindow(app)
	MainWindow.setupUi()
	MainWindow.show()
	MainWindow.setupChips()
	sys.exit(app.exec_())
