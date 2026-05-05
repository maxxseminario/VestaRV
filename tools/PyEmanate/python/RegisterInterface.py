import sys, os, pathlib, json
from time import sleep
from PyQt5 import uic, QtCore, QtGui, QtWidgets, Qt
from PyQt5.QtWidgets import QTreeWidgetItem, QSizePolicy, QPushButton, QFileDialog, QDialog

from UART import UART
from ForthInterface import ForthInterface
from Chip import *
from HelperFunctions import *

class Ui_RegisterInterfaceWindow(QtWidgets.QMainWindow):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	App = None
	Parent = None
	Forth = None

	pushButtonBits = None
	labelBitFields = None

	SelectedPeripheral = None
	SelectedRegister = None
	SelectedBitField = None

	MarkToBeSavedEnable = False

	def __init__(self, app, parent):
		super(Ui_RegisterInterfaceWindow, self).__init__(parent)
		self.App = app
		self.Parent = parent
		return
    
	def setupUi(self, forth:ForthInterface):
		# Load the UI configuration file
		uic.loadUi(self.ThisFileDirectory + '/../qt/RegisterInterface.ui', self)

		# Add all the peripherals/registers to the tree view
		self.Forth = forth
		
		items = []
		for peripheral in self.Forth.ActiveChip.Peripherals:
			periphItem = QTreeWidgetItem([peripheral.Name])

			for register in peripheral.Registers:
				register.ClearValueHistory()
				registerItem = QTreeWidgetItem([register.Name])

				for bitField in register.BitFields:
					if not bitField.Unused:
						bitFieldItem = QTreeWidgetItem([bitField.Name])
						registerItem.addChild(bitFieldItem)
				
				periphItem.addChild(registerItem)

			items.append(periphItem)	
		self.treeWidgetRegisters.clear()
		self.treeWidgetRegisters.addTopLevelItems(items)

		# Set up the bits GUI
		self.pushButtonBits = [self.pushButtonBit0, self.pushButtonBit1, self.pushButtonBit2, self.pushButtonBit3, self.pushButtonBit4, self.pushButtonBit5, self.pushButtonBit6, self.pushButtonBit7, self.pushButtonBit8, self.pushButtonBit9, self.pushButtonBit10, self.pushButtonBit11, self.pushButtonBit12, self.pushButtonBit13, self.pushButtonBit14, self.pushButtonBit15, self.pushButtonBit16, self.pushButtonBit17, self.pushButtonBit18, self.pushButtonBit19, self.pushButtonBit20, self.pushButtonBit21, self.pushButtonBit22, self.pushButtonBit23, self.pushButtonBit24, self.pushButtonBit25, self.pushButtonBit26, self.pushButtonBit27, self.pushButtonBit28, self.pushButtonBit29, self.pushButtonBit30, self.pushButtonBit31]
		self.labelBitFields = [self.labelBitField0, self.labelBitField1, self.labelBitField2, self.labelBitField3, self.labelBitField4, self.labelBitField5, self.labelBitField6, self.labelBitField7, self.labelBitField8, self.labelBitField9, self.labelBitField10, self.labelBitField11, self.labelBitField12, self.labelBitField13, self.labelBitField14, self.labelBitField15, self.labelBitField16, self.labelBitField17, self.labelBitField18, self.labelBitField19, self.labelBitField20, self.labelBitField21, self.labelBitField22, self.labelBitField23, self.labelBitField24, self.labelBitField25, self.labelBitField26, self.labelBitField27, self.labelBitField28, self.labelBitField29, self.labelBitField30, self.labelBitField31]

		self.ResetGui()

		# Add event handlers
		self.treeWidgetRegisters.itemSelectionChanged.connect(self.treeWidgetRegisters_itemSelectionChanged)
		self.pushButtonRefresh.clicked.connect(self.pushButtonRefresh_clicked)
		self.pushButtonSetValue.clicked.connect(self.pushButtonSetValue_clicked)
		self.lineEditSetValue.returnPressed.connect(self.pushButtonSetValue_clicked)
		self.pushButtonBitFieldSetValue.clicked.connect(self.pushButtonBitFieldSetValue_clicked)
		self.pushButtonUndo.clicked.connect(self.pushButtonUndo_clicked)
		self.pushButtonRedo.clicked.connect(self.pushButtonRedo_clicked)

		for pushButtonBit in self.pushButtonBits:
			pushButtonBit.clicked.connect(self.pushButtonBit_clicked)
		
		self.labelCurrentValueHex.installEventFilter(self)
		self.labelCurrentValueDec.installEventFilter(self)
		self.labelCurrentValueBin.installEventFilter(self)

		self.checkBoxMarkToBeSaved.stateChanged.connect(self.checkBoxMarkToBeSaved_stateChanged)
		self.actionQuick_Save_All.triggered.connect(self.actionQuickSaveAll_triggered)
		self.actionQuick_Save_Marked.triggered.connect(self.actionQuickSaveMarked_triggered)
		self.actionSave_All.triggered.connect(self.actionSaveAll_triggered)
		self.actionSave_Marked.triggered.connect(self.actionSaveMarked_triggered)
		self.actionLoad_All.triggered.connect(self.actionLoadAll_triggered)
		self.actionLoad_Marked.triggered.connect(self.actionLoadMarked_triggered)
		self.actionNotes.triggered.connect(self.actionNotes_triggered)
		self.actionPeripheral_Config.triggered.connect(self.actionPeripheral_Config_triggered)
		self.actionOpen_Register_Saves_Folder.triggered.connect(self.actionOpen_Register_Saves_Folder_triggered)

		return
	
	def ResetGui(self):
		self.labelName.setText('Peripheral: N/A, Register: N/A, Address: N/A, Bit Field: N/A')
		self.textEditDescription.setText('')
		self.labelCurrentValueHex.setText('')
		self.labelCurrentValueDec.setText('')
		self.labelCurrentValueBin.setText('')
		
		for pushButtonBit in self.pushButtonBits:
			pushButtonBit.setText('N/A')
			pushButtonBit.setStyleSheet('')
			pushButtonBit.setEnabled(False)
		
		for labelBitField in self.labelBitFields:
			labelBitField.setText('')
			labelBitField.setStyleSheet('')
		
		return
	
	def UpdateGui(self):
		self.MarkToBeSavedEnable = False

		if self.SelectedBitField is not None:
			# A bit field is selected
			self.labelName.setText('Peripheral: ' + self.SelectedPeripheral.Name + ', Register: ' + self.SelectedRegister.Name + ', Address: ' + self.SelectedRegister.AddressHex + ', Bit Field: ' + self.SelectedBitField.Name)
			self.textEditDescription.setText(self.SelectedBitField.Description)
			self.labelCurrentValueHex.setText(self.SelectedBitField.CurrentValueHex)
			self.labelCurrentValueDec.setText(str(self.SelectedBitField.CurrentValue))
			self.labelCurrentValueBin.setText(self.SelectedBitField.CurrentValueBinSeparated)
			self.checkBoxMarkToBeSaved.setTristate(False)
			self.checkBoxMarkToBeSaved.setChecked(self.SelectedRegister.MarkToBeSaved)
			self.checkBoxMarkToBeSaved.setEnabled(True)
		elif self.SelectedRegister is not None:
			# A register is selected
			self.labelName.setText('Peripheral: ' + self.SelectedPeripheral.Name + ', Register: ' + self.SelectedRegister.Name + ', Address: ' + self.SelectedRegister.AddressHex)
			self.textEditDescription.setText(self.SelectedRegister.Description)
			self.labelCurrentValueHex.setText(self.SelectedRegister.CurrentValueHex)
			self.labelCurrentValueDec.setText(str(self.SelectedRegister.CurrentValue))
			self.labelCurrentValueBin.setText(self.SelectedRegister.CurrentValueBinSeparated)
			self.checkBoxMarkToBeSaved.setTristate(False)
			self.checkBoxMarkToBeSaved.setChecked(self.SelectedRegister.MarkToBeSaved)
			self.checkBoxMarkToBeSaved.setEnabled(True)
		elif self.SelectedPeripheral is not None:
			# A peripheral is selected
			self.labelName.setText('Peripheral: ' + self.SelectedPeripheral.Name)
			self.textEditDescription.setText(self.SelectedPeripheral.Description)
			self.labelCurrentValueHex.setText('')
			self.labelCurrentValueDec.setText('')
			self.labelCurrentValueBin.setText('')
			marksToBeSaved = [r.MarkToBeSaved for r in self.SelectedPeripheral.Registers]# if r.WriteCheckMask != 0]
			if all(marksToBeSaved):
				self.checkBoxMarkToBeSaved.setTristate(False)
				self.checkBoxMarkToBeSaved.setChecked(True)
			elif any(marksToBeSaved):
				self.checkBoxMarkToBeSaved.setTristate(True)
				self.checkBoxMarkToBeSaved.setCheckState(1)
			else:
				self.checkBoxMarkToBeSaved.setTristate(False)
				self.checkBoxMarkToBeSaved.setChecked(False)
		else:
			self.labelName.setText('Peripheral: N/A, Register: N/A, Address: N/A, Bit Field: N/A')
			self.textEditDescription.setText('')
			self.labelCurrentValueHex.setText('')
			self.labelCurrentValueDec.setText('')
			self.labelCurrentValueBin.setText('')
			self.checkBoxMarkToBeSaved.setTristate(False)
			self.checkBoxMarkToBeSaved.setChecked(False)
			self.checkBoxMarkToBeSaved.setEnabled(False)
		
		# Update the buttons
		if self.SelectedRegister is not None:
			# Update the bits that are outside the size of the register
			for i in range(self.SelectedRegister.Size, 32):
				self.pushButtonBits[i].setText('N/A')
				self.pushButtonBits[i].setStyleSheet('')
				self.pushButtonBits[i].setEnabled(False)
				self.pushButtonBits[i].setToolTip('')
			for i in range(self.SelectedRegister.Size):
				bitField = self.SelectedRegister.GetBitFieldAt(i)
				if bitField is None or bitField.Unused or self.SelectedRegister.CurrentValue is None:
					self.pushButtonBits[i].setText('N/A')
					self.pushButtonBits[i].setStyleSheet('')
					self.pushButtonBits[i].setEnabled(False)
				else:
					value = (self.SelectedRegister.CurrentValue >> i) & 0x1
					self.pushButtonBits[i].setText(str(value))
					if 'w' not in bitField.Accessibility or ((self.SelectedBitField is not None) and not (self.SelectedBitField.LSB <= i <= self.SelectedBitField.MSB)):
						self.pushButtonBits[i].setStyleSheet('')
						self.pushButtonBits[i].setToolTip('')
						self.pushButtonBits[i].setEnabled(False)
					else:
						self.pushButtonBits[i].setEnabled(True)
						if value == 0:
							self.pushButtonBits[i].setStyleSheet('background-color: #ffaaaa')
						else:
							self.pushButtonBits[i].setStyleSheet('background-color: #aaffaa')
						#s = 'Change '
						#if self.SelectedBitField is not None:
						#	s += 'bit field value to ' + str(self.SelectedBitField.CurrentValue ^ (0x1 << (i - self.SelectedBitField.LSB)))
						#else:
						#	s += 'register value to ' + str(self.SelectedRegister.CurrentValue ^ (0x1 << i))
						#self.pushButtonBits[i].setToolTip(s)
						bf = self.SelectedRegister.GetBitFieldAt(i)
						if bf is not None:
							s = bf.Description
							if type(s) != str or len(s) < 0:
								s = 'Description: None'

							valueIfClicked = bf.CurrentValue ^ (0x1 << (i - bf.LSB))
							vdIfClicked = bf.GetValueDescription(value=valueIfClicked)
							if type(vdIfClicked) == dict and 'Name' in vdIfClicked and type(vdIfClicked['Name']) == str:
								s += '\nClick to change to ' + vdIfClicked['Name']
							
							self.pushButtonBits[i].setToolTip(s)

			self.pushButtonUndo.setEnabled(self.SelectedRegister.ValueHistoryIndex > 0)
			self.pushButtonRedo.setEnabled(self.SelectedRegister.ValueHistoryIndex + 1 < len(self.SelectedRegister.ValueHistory))
		else:
			for i in range(32):
				self.pushButtonBits[i].setText('N/A')
				self.pushButtonBits[i].setStyleSheet('')
				self.pushButtonBits[i].setEnabled(False)
			self.pushButtonUndo.setEnabled(False)
			self.pushButtonRedo.setEnabled(False)
		
		# Update the bit field labels
		for labelBitField in self.labelBitFields:
			self.groupBoxBits.layout().removeWidget(labelBitField)
			labelBitField.hide()
		
		if self.SelectedRegister is not None:
			alt = False
			lastBitFieldName = None
			i = 31
			while i >= 0:
				bitField = self.SelectedRegister.GetBitFieldAt(i)
				if bitField is None:
					i -= 1
					continue
				if bitField.Unused:
					i -= 1
					continue
				if self.SelectedBitField is not None and bitField != self.SelectedBitField:
					# If a bit field is selected, display only that bit field
					i -= 1
					continue
				self.labelBitFields[i].setText(bitField.Name)
				if bitField.Name == lastBitFieldName:
					alt = not alt
				if alt:
					self.labelBitFields[i].setStyleSheet('background-color: #ffe4b5')	# Add this for a black border: '; border: 1px solid black'
				else:
					self.labelBitFields[i].setStyleSheet('background-color: #afeeee')
				alt = not alt
				lineLsb = (i // 8) * 8
				lsb = max([bitField.LSB, lineLsb])
				row = 14 - ((i // 8) * 4)
				column = 8 - (i % 8)
				columnSpan = 1 + i - lsb
				self.groupBoxBits.layout().addWidget(self.labelBitFields[i], row, column, 1, columnSpan)#, Qt.Qt.AlignHCenter)
				lastBitFieldName = bitField.Name
				self.labelBitFields[i].setSizePolicy(QtWidgets.QSizePolicy(QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Preferred))
				self.labelBitFields[i].setAutoFillBackground(True)
				self.labelBitFields[i].show()
				i = lsb - 1
		
		# Update bit field information if a bit field is selected
		self.comboBoxValueDescriptions.clear()
		if self.SelectedBitField is not None:
			vds = self.SelectedBitField.ValueDescriptions
			vdsWithNames = [vd for vd in vds if 'Name' in vd and len(vd['Name']) > 0]
			self.comboBoxValueDescriptions.addItems([vd['Name'] for vd in vdsWithNames])
			
			currentVD = self.SelectedBitField.GetCurrentValueDescription()
			if currentVD is not None:
				s = 'Current ' + self.SelectedBitField.Name + ' value description: '
				if 'Name' in currentVD and len(currentVD['Name']) > 0:
					s += currentVD['Name']
				else:
					s += 'Unnamed'
				s += '\nDescription: ' + currentVD['Description']
				self.textEditBitFieldValueDescription.setText(s)
				if currentVD in vdsWithNames:
					self.comboBoxValueDescriptions.setCurrentIndex(vdsWithNames.index(currentVD))
			else:
				self.textEditBitFieldValueDescription.setText('No value description for this value of ' + self.SelectedBitField.Name)
			
			if len(vdsWithNames) > 0:
				self.pushButtonBitFieldSetValue.setEnabled(True)
			else:
				self.pushButtonBitFieldSetValue.setEnabled(False)
		else:
			self.textEditBitFieldValueDescription.setText('')
			self.pushButtonBitFieldSetValue.setEnabled(False)
		
		self.MarkToBeSavedEnable = True
		return
	
	def SaveRegisters(self, outPath=None, quick=False, dialog=False, onlyMarked=False):
		# Collect a list of registers to be saved
		registers = [r for r in self.Forth.ActiveChip.Registers if (not onlyMarked) or r.MarkToBeSaved]
		registerCount = len(registers)
		if registerCount <= 0:
			if onlyMarked:
				self.statusbar.showMessage('No registers marked to be saved', 5000)
			else:
				self.statusbar.showMessage('No registers to save', 5000)
			return False
		
		# Get the path to the output file
		if dialog:
			registerSavesDirectory = self.Forth.ActiveChip.DataDirectory + '/RegisterSaves/' + self.Forth.ActiveChip.DieID
			fileName = 'RegisterSave-' + self.Forth.ActiveChip.DieID + '-' + get_string_timestamp(includeSeconds=True) + '.json'
			path = registerSavesDirectory + '/' + fileName
			#dia = QtGui.QFileDialog(self, 'Save Registers', registerSavesDirectory, filter)
			outPath = QFileDialog.getSaveFileName(self, 'Save Registers', path, 'JSON Files (*.json)')[0]
			if len(outPath) <= 0:
				return False
		if outPath is not None:
			parentDir = os.path.dirname(outPath)
			if not os.path.isdir(parentDir):
				self.statusbar.showMessage('Cannot save registers: invalid path', 5000)
				return False
			fileName = outPath.replace('\\', '/').split('/')[-1]
		elif quick:
			registerSavesDirectory = self.Forth.ActiveChip.DataDirectory + '/RegisterSaves/' + self.Forth.ActiveChip.DieID
			if not os.path.isdir(registerSavesDirectory):
				os.makedirs(registerSavesDirectory)
			if not os.path.isdir(registerSavesDirectory):
				self.statusbar.showMessage('Cannot save registers: invalid path', 5000)
			fileName = 'RegisterSave-' + self.Forth.ActiveChip.DieID + '-' + get_string_timestamp(includeSeconds=True) + '.json'
			outPath = registerSavesDirectory + '/' + fileName
		else:
			return False

		# Read all registers to be saved
		s = 'Saving ' + str(len(registers)) + ' register'
		if len(registers) != 1:
			s += 's'
		s += '...'
		self.statusbar.showMessage(s, 5000)
		self.repaint()	# Force the thread to update the GUI right now

		for r in registers:
			#self.statusbar.showMessage('Reading register ' + str(i + 1) + '/' + str(registerCount) + '...', 1000)
			#self.repaint()	# Force the thread to update the GUI right now
			ret = self.Forth.ReadRegister(reg=r)
			if ret is None:
				self.statusbar.showMessage('Could not save registers to ' + fileName, 5000)
				return ret
		
		# Save the read registers
		ret = self.Forth.ActiveChip.SaveRegisterValuesToJson(outPath, onlyMarked=onlyMarked)
		if ret:
			s = 'Saved ' + str(len(registers)) + ' register'
			if len(registers) != 1:
				s += 's'
			s += ' to ' + fileName
			self.statusbar.showMessage(s, 5000)
		else:
			self.statusbar.showMessage('Could not save registers to ' + fileName, 5000)
		return ret
	
	def LoadRegisters(self, inPath=None, dialog=None, onlyMarked=False):
		# Get the path to the input file
		if dialog:
			registerSavesDirectory = self.Forth.ActiveChip.DataDirectory + '/RegisterSaves/' + self.Forth.ActiveChip.DieID
			inPath = QFileDialog.getOpenFileName(self, 'Load Registers', registerSavesDirectory, 'JSON Files (*.json)')[0]
			if len(inPath) <= 0:
				return False

		if not os.path.isfile(inPath):
			self.statusbar.showMessage('Cannot load registers: invalid path', 5000)
			return False
		
		# Load the json file
		with open(inPath, 'r') as f:
			d = json.load(f)
		if 'Type' not in d:
			self.statusbar.showMessage('Cannot load registers: invalid JSON file', 5000)
			return False
		
		# Enable the ability to load register values from a histogram or histogram collection file
		if (d['Type'] == 'Histogram' or d['Type'] == 'Histograms' or d['Type'] == 'PsdData') and 'RegisterValues' in d:
			# This histogram or histogram collection file contains register values
			if type(d['RegisterValues']) == dict:
				d = d['RegisterValues']
		
		# Is this a valid register save file?
		if 'Type' not in d or d['Type'] != 'RegisterValues':
			self.statusbar.showMessage('Cannot load registers: file does not contain register values', 5000)
			return False
		if 'ChipName' not in d:
			self.statusbar.showMessage('Cannot load registers: invalid JSON file', 5000)
			return False
		if d['ChipName'] != self.Forth.ActiveChip.Name:
			self.statusbar.showMessage('Cannot load registers: JSON file is for another chip', 5000)
			return False
		if ('Peripherals' not in d) or (type(d['Peripherals']) != list):
			self.statusbar.showMessage('Cannot load registers: no peripheral data in JSON file', 5000)
			return False
		peripherals = d['Peripherals']
		registers = []
		for p in peripherals:
			if 'Registers' in p:
				registers += p['Registers']
		
		# Set each register to the loaded value
		s = 'Loading ' + str(len(registers)) + ' register'
		if len(registers) != 1:
			s += 's'
		s += '...'
		self.statusbar.showMessage(s, 5000)
		self.repaint()	# Force the thread to update the GUI right now

		count = 0
		for lr in registers:
			if 'Name' not in lr:
				continue
			name = lr['Name']
			if 'Value' not in lr:
				continue
			value = lr['Value']
			r = self.Forth.ActiveChip.GetRegister(name=name)
			if r is None:
				continue
			if r.WriteCheckMask == 0:
				continue
			if onlyMarked and not r.MarkToBeSaved:
				continue
			sleep(20e-3)	# TODO: This is done because writing many registers at 2048 baud causes read glitches. Find a way to not have to sleep
			ret = self.Forth.WriteRegister(reg=r, value=value)
			if ret is None:
				self.statusbar.showMessage('Load failed, check connection', 5000)
				return False
			if self.actionMark_Loaded_Registers.isChecked():
				r.MarkToBeSaved = True
			count += 1
		if 'NotesForRegisterSave' in d:
			self.Forth.ActiveChip.NotesForRegisterSave = d['NotesForRegisterSave']
		s = 'Loaded ' + str(count) + ' register'
		if count != 1:
			s += 's'
		s += ' from ' + os.path.basename(inPath)
		self.statusbar.showMessage(s, 5000)
		self.UpdateGui()
		return
			



	# Event Handlers
	def treeWidgetRegisters_itemSelectionChanged(self):
		# Identify the selected item
		selectedItems = self.treeWidgetRegisters.selectedItems()
		if len(selectedItems) != 1:
			return
		item = selectedItems[0]
		parent = item.parent()
		grandparent = None
		if parent is not None:
			grandparent = parent.parent()
		
		# What is it?
		self.SelectedPeripheral = None
		self.SelectedRegister = None
		self.SelectedBitField = None

		peripheral = None
		register = None
		bitField = None

		if item is None:
			pass
		elif parent is None:
			# It's a peripheral
			peripheral = self.Forth.ActiveChip.GetPeripheral(item.text(0))
		elif grandparent is None:
			# It's a register
			register = self.Forth.ActiveChip.GetRegister(item.text(0))
			if register is not None:
				peripheral = register.Parent
		else:
			# It's a bit field
			register = self.Forth.ActiveChip.GetRegister(parent.text(0))
			if register is not None:
				peripheral = register.Parent
			bitField = register.GetBitField(item.text(0))
		
		self.SelectedPeripheral = peripheral
		self.SelectedRegister = register
		self.SelectedBitField = bitField

		# If it was a register or bit field, update the value of the associated register
		if self.SelectedRegister is not None:
			ret = self.Forth.ReadRegister(reg=self.SelectedRegister)
			if ret is None:
				if not self.Forth.Connected:
					self.statusbar.showMessage('Disconnected!', 10000)
				else:
					self.statusbar.showMessage('Error while reading register ' + self.SelectedRegister.Name + '...', 5000)
			else:
				self.statusbar.showMessage('Read register ' + self.SelectedRegister.Name, 5000)
		
		self.UpdateGui()
		return
	
	def pushButtonRefresh_clicked(self):
		if self.SelectedRegister is not None:
			ret = self.Forth.ReadRegister(reg=self.SelectedRegister)
			if ret is None:
				if not self.Forth.Connected:
					self.statusbar.showMessage('Disconnected!', 10000)
				else:
					self.statusbar.showMessage('Error while reading register ' + self.SelectedRegister.Name + '...', 5000)
			else:
				self.statusbar.showMessage('Read register ' + self.SelectedRegister.Name, 5000)
		
		self.UpdateGui()
		return
	
	def pushButtonBit_clicked(self):
		if self.SelectedRegister is None:
			return
		pushButtonBit = self.sender()
		bitNum = self.pushButtonBits.index(pushButtonBit) if pushButtonBit in self.pushButtonBits else None
		if bitNum is None:
			return

		# Get the bit field
		bf = self.SelectedRegister.GetBitFieldAt(bitNum)
		if bf is not None and ('w0' in bf.Accessibility or 'w1' in bf.Accessibility):
			if 'w0' in bf.Accessibility:
				ret = self.Forth.ClearRegisterBit(reg=self.SelectedRegister, bitNum=bitNum)
				s = 'Cleared '
			elif 'w1' in bf.Accessibility:
				ret = self.Forth.SetRegisterBit(reg=self.SelectedRegister, bitNum=bitNum)
				s = 'Set '
		else:
			# Get the current bit value
			value = (self.SelectedRegister.CurrentValue >> bitNum) & 0x1

			# Write the toggled bit to the register
			if value == 1:
				ret = self.Forth.ClearRegisterBit(reg=self.SelectedRegister, bitNum=bitNum)
				s = 'Cleared '
			else:
				ret = self.Forth.SetRegisterBit(reg=self.SelectedRegister, bitNum=bitNum)
				s = 'Set '
		
		if ret != True:
			if not self.Forth.Connected:
				self.statusbar.showMessage('Disconnected!', 10000)
			else:
				self.statusbar.showMessage('Error while toggling bit...', 5000)
		else:
			#self.statusbar.showMessage('Wrote ' + self.SelectedRegister.CurrentValueHex + ' to register ' + self.SelectedRegister.Name, 5000)
			s += 'bit ' + str(bitNum) + ' of register ' + self.SelectedRegister.Name
			self.statusbar.showMessage(s, 5000)
		
		self.UpdateGui()
		return
	
	def pushButtonSetValue_clicked(self):
		if self.SelectedRegister is None:
			return
		
		# Parse the string in the text box
		s = self.lineEditSetValue.text()
		if type(s) != str:
			return
		s = s.strip()
		if len(s) < 1:
			return

		value = None
		neg = False
		if s.startswith('0x'):
			# This should be parsed as a hex string
			s = s[2:].upper()
			for c in s:
				if c not in '0123456789ABCDEF':
					self.statusbar.showMessage('Invalid HEX string', 5000)
					return
			value = int(s, 16)
		elif s.startswith('0b'):
			# This should be parsed as a binary string
			s = s[2:].upper()
			for c in s:
				if c not in '01':
					self.statusbar.showMessage('Invalid binary string', 5000)
					return
			value = int(s, 2)
		else:
			# This should be parsed as an integer string
			neg = s.startswith('-')
			if neg:
				s = s[1:]
			for c in s:
				if c not in '0123456789':
					self.statusbar.showMessage('Invalid integer string', 5000)
					return
			value = int(s)
			if neg:
				value = -value
		
		# If the value is negative, make it positive

		# Is this value for a bit field or for a register?
		if self.SelectedBitField is not None:
			# It's for a bit field
			if neg:
				if self.SelectedBitField.Size < 2 or -(2**(self.SelectedBitField.Size - 1)) > value:
					self.statusbar.showMessage('Integer string results in an overflow', 5000)
					return
				value = neg_int_to_unsigned_int(value, self.SelectedBitField.Size)
			elif value >= 2**self.SelectedBitField.Size:
				self.statusbar.showMessage('Integer string results in an overflow', 5000)
				return
			
			ret = self.Forth.SetRegisterMask(reg=self.SelectedRegister, value=(value << self.SelectedBitField.LSB), mask=self.SelectedBitField.RegisterBitMask)
			if ret != True:
				if not self.Forth.Connected:
					self.statusbar.showMessage('Disconnected!', 10000)
				else:
					self.statusbar.showMessage('Error while writing register...', 5000)
			else:
				self.statusbar.showMessage('Wrote ' + self.SelectedRegister.CurrentValueHex + ' to register ' + self.SelectedRegister.Name, 5000)
		else:
			# It's for a register
			if neg:
				if self.SelectedRegister.Size < 2 or -(2**(self.SelectedRegister.Size - 1)) > value:
					self.statusbar.showMessage('Integer string results in an overflow', 5000)
					return
				value = neg_int_to_unsigned_int(value, self.SelectedRegister.Size)
			elif value >= 2**self.SelectedRegister.Size:
				self.statusbar.showMessage('Integer string results in an overflow', 5000)
				return
			
			ret = self.Forth.WriteRegister(reg=self.SelectedRegister, value=value)
			if ret != True:
				if not self.Forth.Connected:
					self.statusbar.showMessage('Disconnected!', 10000)
				else:
					self.statusbar.showMessage('Error while writing register...', 5000)
			else:
				self.statusbar.showMessage('Wrote ' + self.SelectedRegister.CurrentValueHex + ' to register ' + self.SelectedRegister.Name, 5000)
		
		self.UpdateGui()
		return

	def pushButtonBitFieldSetValue_clicked(self):
		if self.SelectedBitField is None:
			return
		vdName = self.comboBoxValueDescriptions.currentText()
		if vdName is None or len(vdName) == 0:
			return
		for vd in self.SelectedBitField.ValueDescriptions:
			if vd['Name'] == vdName:
				ret = self.Forth.SetRegisterMask(reg=self.SelectedRegister, value=(vd['Value'] << self.SelectedBitField.LSB), mask=self.SelectedBitField.RegisterBitMask)
				if ret != True:
					if not self.Forth.Connected:
						self.statusbar.showMessage('Disconnected!', 10000)
					else:
						self.statusbar.showMessage('Error while writing...', 5000)
				else:
					self.statusbar.showMessage('Wrote ' + self.SelectedRegister.CurrentValueHex + ' to register ' + self.SelectedRegister.Name, 5000)
		self.UpdateGui()
		return
	
	def checkBoxMarkToBeSaved_stateChanged(self):
		if self.MarkToBeSavedEnable != True:
			return
		if self.checkBoxMarkToBeSaved.isTristate():
			if self.checkBoxMarkToBeSaved.checkState() == 1:
				return
		if self.SelectedRegister is not None:
			#if self.SelectedRegister.WriteCheckMask == 0:
			#	return
			self.MarkToBeSavedEnable = False
			self.checkBoxMarkToBeSaved.setTristate(False)
			self.SelectedRegister.MarkToBeSaved = self.checkBoxMarkToBeSaved.isChecked()
			self.MarkToBeSavedEnable = True
		elif self.SelectedPeripheral is not None:
			self.MarkToBeSavedEnable = False
			self.checkBoxMarkToBeSaved.setTristate(False)
			state = self.checkBoxMarkToBeSaved.isChecked()
			for register in self.SelectedPeripheral.Registers:
				#if register.WriteCheckMask == 0:
				#	continue
				register.MarkToBeSaved = state
			self.MarkToBeSavedEnable = True
		return
	
	def pushButtonUndo_clicked(self):
		if self.SelectedRegister is None:
			return
		ret = self.Forth.UndoWriteRegister(reg=self.SelectedRegister)
		if ret != True:
			if not self.Forth.Connected:
				self.statusbar.showMessage('Disconnected!', 10000)
			else:
				self.statusbar.showMessage('Error while writing...', 5000)
		else:
			self.statusbar.showMessage('Undo action: Wrote ' + self.SelectedRegister.CurrentValueHex + ' to register ' + self.SelectedRegister.Name, 5000)
		self.UpdateGui()
		return
	
	def pushButtonRedo_clicked(self):
		if self.SelectedRegister is None:
			return
		ret = self.Forth.RedoWriteRegister(reg=self.SelectedRegister)
		if ret != True:
			if not self.Forth.Connected:
				self.statusbar.showMessage('Disconnected!', 10000)
			else:
				self.statusbar.showMessage('Error while writing...', 5000)
		else:
			self.statusbar.showMessage('Undo action: Wrote ' + self.SelectedRegister.CurrentValueHex + ' to register ' + self.SelectedRegister.Name, 5000)
		self.UpdateGui()
		return
	
	def actionQuickSaveAll_triggered(self):
		self.SaveRegisters(quick=True, onlyMarked=False)
		return
	
	def actionQuickSaveMarked_triggered(self):
		self.SaveRegisters(quick=True, onlyMarked=True)
		return
	
	def actionSaveAll_triggered(self):
		self.SaveRegisters(dialog=True, onlyMarked=False)
		return
	
	def actionSaveMarked_triggered(self):
		self.SaveRegisters(dialog=True, onlyMarked=True)
		return
	
	def actionLoadAll_triggered(self):
		self.LoadRegisters(dialog=True, onlyMarked=False)
		return
	
	def actionLoadMarked_triggered(self):
		self.LoadRegisters(dialog=True, onlyMarked=True)
		return
	
	def actionNotes_triggered(self):
		diag = Ui_RegisterSaveNotes()
		diag.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
		diag.textEditNotes.setText(self.Forth.ActiveChip.NotesForRegisterSave)
		if diag.exec():
			self.Forth.ActiveChip.NotesForRegisterSave = diag.textEditNotes.toPlainText()
		return
	
	def actionPeripheral_Config_triggered(self):
		diag = Ui_CopyPeripheralTo()
		diag.setWindowFlag(QtCore.Qt.WindowContextHelpButtonHint, False)
		diag.Setup(self.Forth.ActiveChip, firstSelectedPeripheral=self.SelectedPeripheral)
		if diag.exec():
			# Get the src and dst peripherals
			src, dsts, onlyCopyMarked = diag.GetSrcAndDst()
			if src is None or dsts is None or len(dsts) == 0:
				return

			# Count the number of registers to copy
			numSrcRegsToCopy = 0
			for rsrc in src.Registers:
				if not (onlyCopyMarked and rsrc.MarkToBeSaved):
					continue
				if rsrc.WriteCheckMask == 0:
					# Don't write to read-only registers
					continue
				numSrcRegsToCopy += 1
			numDstRegsToPaste = numSrcRegsToCopy * len(dsts)

			# Print message
			s = 'Copying ' + str(numSrcRegsToCopy) + ' source register'
			if numSrcRegsToCopy != 1:
				s += 's'
			s +=' from ' + src.Name + ' to ' + str(numDstRegsToPaste) + ' destination register'
			if numDstRegsToPaste != 1:
				s += 's'
			s +=  '...'
			self.statusbar.showMessage(s, 5000)
			self.repaint()	# Force the thread to update the GUI right now
			
			# Copy each register from src to dst
			for rsrc in src.Registers:
				if not (onlyCopyMarked and rsrc.MarkToBeSaved):
					continue
				if rsrc.WriteCheckMask == 0:
					# Don't write to read-only registers
					continue

				# Read the register value
				value = self.Forth.ReadRegister(reg=rsrc)
				if value is None:
					self.statusbar.showMessage('Copy failed, check connection', 5000)
					return
				
				# Write each dst peripheral's register
				for pdst in dsts:
					# Get the register
					address = pdst.BaseAddress + rsrc.Offset
					rdst = self.Forth.ActiveChip.GetRegister(address=address)
					
					# Write to the register
					if self.Forth.WriteRegister(reg=rdst, value=value, addToHistory=True) != True:
						self.statusbar.showMessage('Copy failed, check connection', 5000)
						return
					
					if onlyCopyMarked:
						rdst.MarkToBeSaved = True
			
			# Print message
			s = 'Copied ' + str(numSrcRegsToCopy) + ' source register'
			if numSrcRegsToCopy != 1:
				s += 's'
			s +=' from ' + src.Name + ' to ' + str(numDstRegsToPaste) + ' destination register'
			if numDstRegsToPaste != 1:
				s += 's'
			s +=  '...'
			self.statusbar.showMessage(s, 5000)

			# Update GUI
			self.UpdateGui()
			
		return
	
	def actionOpen_Register_Saves_Folder_triggered(self):
		directory = self.Forth.ActiveChip.DataDirectory + '/RegisterSaves/' + self.Forth.ActiveChip.DieID
		if os.path.isdir(directory):
			os.startfile(directory)
		return

	
	def eventFilter(self, sender, event):
		if event.type() == QtCore.QEvent.MouseButtonPress:
			if sender == self.labelCurrentValueHex:
				if event.button() == QtCore.Qt.RightButton:
					text = sender.text().replace(' ', '')
					if len(text) > 0:
						# Copy to clipboard
						cb = self.App.clipboard()
						cb.clear(mode=cb.Clipboard)
						cb.setText(text, mode=cb.Clipboard)
						self.statusbar.showMessage('Copied "' + text + '" to clipboard', 5000)
			if sender == self.labelCurrentValueDec:
				if event.button() == QtCore.Qt.RightButton:
					text = sender.text().replace(' ', '')
					if len(text) > 0:
						# Copy to clipboard
						cb = self.App.clipboard()
						cb.clear(mode=cb.Clipboard)
						cb.setText(text, mode=cb.Clipboard)
						self.statusbar.showMessage('Copied "' + text + '" to clipboard', 5000)
			if sender == self.labelCurrentValueBin:
				if event.button() == QtCore.Qt.RightButton:
					text = sender.text().replace(' ', '')
					if len(text) > 0:
						# Copy to clipboard
						cb = self.App.clipboard()
						cb.clear(mode=cb.Clipboard)
						cb.setText(text, mode=cb.Clipboard)
						self.statusbar.showMessage('Copied "' + text + '" to clipboard', 5000)
		return QtCore.QObject.event(sender, event)





class Ui_RegisterSaveNotes(QDialog):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	def __init__(self, parent=None):
		super().__init__(parent)
		uic.loadUi(self.ThisFileDirectory + '/../qt/Notes.ui', self)
		return



class Ui_CopyPeripheralTo(QDialog):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	ActiveChip = None

	def __init__(self, parent=None):
		super().__init__(parent)
		uic.loadUi(self.ThisFileDirectory + '/../qt/CopyPeripheralTo.ui', self)

		# Load event handlers
		self.listWidgetSrc.currentItemChanged.connect(self.listWidgetSrc_currentItemChanged)
		return
	
	def Setup(self, activeChip:Chip, firstSelectedPeripheral=None):
		self.ActiveChip = activeChip

		peripherals = self.ActiveChip.Peripherals

		# Configure the "source" list box
		self.listWidgetSrc.clear()
		self.listWidgetSrc.addItems([p.Name for p in peripherals])

		if (firstSelectedPeripheral is None) or (firstSelectedPeripheral not in peripherals):
			self.listWidgetSrc.setCurrentItem(None)
		else:
			for i in range(self.listWidgetSrc.count()):
				item = self.listWidgetSrc.item(i)
				if item.text() == firstSelectedPeripheral.Name:
					self.listWidgetSrc.setCurrentItem(item)
					break
	
	def listWidgetSrc_currentItemChanged(self):
		# Clear the destination list box
		self.listWidgetDst.clear()

		peripherals = self.ActiveChip.Peripherals

		# Get the source peripheral
		srcPeripheralName = self.listWidgetSrc.currentItem().text()
		srcPeripheral = None
		for p in peripherals:
			if p.Name == srcPeripheralName:
				srcPeripheral = p
				break
		if srcPeripheral is None:
			return

		# Get all like peripherals
		likePeripherals = []
		for p in peripherals:
			if p.NameTemplate == srcPeripheral.NameTemplate:
				likePeripherals.append(p)
		likePeripheralNames = [p.Name for p in likePeripherals]
		self.listWidgetDst.addItems(likePeripheralNames)

		return
	
	def GetSrcAndDst(self):
		peripherals = self.ActiveChip.Peripherals

		# Get the source peripheral
		srcPeripheralName = self.listWidgetSrc.currentItem().text()
		srcPeripheral = None
		for p in peripherals:
			if p.Name == srcPeripheralName:
				srcPeripheral = p
				break
		
		# Get the destination peripheral(s)
		dstPeripheralNames = [s.text() for s in self.listWidgetDst.selectedItems()]
		dstPeripherals = []
		for dpName in dstPeripheralNames:
			for p in peripherals:
				if p.Name == dpName and p != srcPeripheral:
					dstPeripherals.append(p)
					break
		
		onlyCopyMarked = self.checkBoxMarked.isChecked()
		
		return srcPeripheral, dstPeripherals, onlyCopyMarked

		
	
	