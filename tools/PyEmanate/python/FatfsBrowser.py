import sys, os, pathlib, json
from time import sleep
from PyQt5 import uic, QtCore, QtGui, QtWidgets, Qt
from PyQt5.QtWidgets import QFileDialog, QMessageBox, QInputDialog

from UART import UART
from ForthInterface import ForthInterface
from HelperFunctions import *

class Ui_FatfsBrowserWindow(QtWidgets.QMainWindow):
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	App = None
	Parent = None
	Forth = None

	CurrentDirectoryContents = None

	def __init__(self, app, parent):
		super(Ui_FatfsBrowserWindow, self).__init__(parent)
		self.App = app
		self.Parent = parent
		return
	
	def setupUi(self, forth:ForthInterface):
		# Load the UI configuration file
		uic.loadUi(self.ThisFileDirectory + '/../qt/FatfsBrowser.ui', self)
		self.Forth = forth

		# Refresh the root directory
		self.RefreshDirectory('/')

		# Add event handlers
		self.listWidgetDirectoryContents.currentItemChanged.connect(self.listWidgetDirectoryContents_currentItemChanged)
		self.listWidgetDirectoryContents.itemDoubleClicked.connect(self.listWidgetDirectoryContents_itemDoubleClicked)
		self.pushButtonDownload.clicked.connect(self.Download)
		self.pushButtonNewDirectory.clicked.connect(self.MakeDirectory)
		self.pushButtonDelete.clicked.connect(self.Delete)
		self.pushButtonUploadFile.clicked.connect(self.pushButtonUploadFile_clicked)
		self.lineEditCurrentDirectoryPath.returnPressed.connect(self.lineEditCurrentDirectoryPath_clicked)

		return
	
	def RefreshDirectory(self, dirPath:str):
		# Get the directories at the path
		self.statusbar.showMessage('Listing directory...', 5000)
		self.repaint()	# Force the thread to update the GUI right now
		dirContents = self.Forth.ListDirectory(dirPath)
		if type(dirContents) != dict or 'Subdirectories' not in dirContents:
			self.CurrentDirectoryContents = None
			self.DisplayCurrentDirectory()
			self.statusbar.showMessage('List directory error', 5000)
			return
		self.statusbar.showMessage('Done listing directory', 5000)
		self.CurrentDirectoryContents = dirContents

		self.DisplayCurrentDirectory()
		return

	def DisplayCurrentDirectory(self):
		if self.CurrentDirectoryContents is None:
			self.lineEditCurrentDirectoryPath.setStyleSheet('color: red')
			self.labelMemoryCapacity.setText('')
			self.listWidgetDirectoryContents.clear()
		else:
			self.lineEditCurrentDirectoryPath.setStyleSheet('')
			self.lineEditCurrentDirectoryPath.setText(NormalizeFatfsPath(self.CurrentDirectoryContents['Path']))
			capacity = self.CurrentDirectoryContents['CapacityBytes']
			free = self.CurrentDirectoryContents['FreeBytes']
			capacityStr = 'Capacity: Unkown'
			if type(capacity) == int and capacity > 0 and type(free) == int:
				usagePct = round(100 * (capacity - free) / capacity)
				capacityStr = 'Capacity: ' + str(capacity) + ' bytes, Free Memory: ' + str(free) + ' bytes, ' + str(usagePct) + '% used'
			self.labelMemoryCapacity.setText(capacityStr)
			
			dirContents = ['.']
			path = self.CurrentDirectoryContents['Path']
			if ':' in path:
				path = path[path.index(':') + 1:]
			path = path.replace('/', '').replace('\\', '')
			if len(path) > 0:
				dirContents.append('..')
			directories = sorted([d['Name'] for d in self.CurrentDirectoryContents['Subdirectories']])
			files = sorted([f['Name'] for f in self.CurrentDirectoryContents['Files']])
			dirContents += directories + files
			self.listWidgetDirectoryContents.clear()
			self.listWidgetDirectoryContents.addItems(dirContents)
		
		self.DisplaySelectedItemInfo()
		
		return
	
	def DisplaySelectedItemInfo(self):
		element = self.listWidgetDirectoryContentsSelectionToElement()
		if element is None:
			self.labelSelectionName.setText('Name:')
			self.labelSelectionType.setText('Type:')
			self.labelSelectionSize.setText('Size:')
			self.labelSelectionPath.setText('Path:')
		else:
			if element['Type'] == 'directory':
				self.labelSelectionType.setText('Type: Directory')
				self.labelSelectionSize.setText('')
			elif element['Type'] == 'file':
				self.labelSelectionType.setText('Type: File')
				self.labelSelectionSize.setText('Size: ' + str(element['SizeBytes']) + ' bytes')
			self.labelSelectionName.setText('Name: ' + element['Name'])
			self.labelSelectionPath.setText('Path: ' + NormalizeFatfsPath(element['Path']))
		
		return
	
	def MakeDirectory(self):
		if self.CurrentDirectoryContents is None:
			return
		
		name, ok = QInputDialog.getText(self, 'Directory Name', 'New directory name:')
		if ok:
			name = name.upper()
			newDirPath = self.CurrentDirectoryContents['Path'] + '/' + name
			if not CheckFatfsPath(newDirPath, allowFileExtension=False):
				self.MessageBox('Invalid directory name', 'New Directory Error')
				return
			self.statusbar.showMessage('Creating new directory "' + name + '"...', 5000)
			self.repaint()	# Force the thread to update the GUI right now
			if self.Forth.MakeDirectory(newDirPath) != True:
				self.MessageBox('Failed to create directory "' + name + '"', 'New Directory Error')
				return
			self.RefreshDirectory(self.CurrentDirectoryContents['Path'])
			self.statusbar.showMessage('Created new directory "' + name + '"', 5000)
		return
	
	def Delete(self):
		element = self.listWidgetDirectoryContentsSelectionToElement()
		if element is None:
			return
		
		if self.Forth.DeleteRecursive(element['Path']) != True:
			self.MessageBox('Failed to delete fatfs ' + element['Type'] + ' "' + element['Path'] + '"', 'Delete Error')
			return
		self.RefreshDirectory(self.CurrentDirectoryContents['Path'])
		self.statusbar.showMessage('Deleted ' + element['Type'] + ' "' + element['Name'] + '"', 5000)
		return
	
	def DownloadFile(self, fatfsPath:str, computerPath:str):
		binData = self.Forth.DownloadFile(fatfsPath)
		if type(binData) != bytes:
			return False
		try:
			with open(computerPath, 'wb') as f:
				f.write(binData)
		except:
			return False
		return True
	
	def Download(self):
		element = self.listWidgetDirectoryContentsSelectionToElement()
		if element is None:
			return
		if element['Type'] == 'file':
			outPath, ok = QFileDialog.getSaveFileName(self, 'Download File', element['Name'], '')
			if not ok:
				return
			self.statusbar.showMessage('Downloading file "' + element['Name'] + '"...', 5000)
			self.repaint()	# Force the thread to update the GUI right now
			if self.DownloadFile(element['Path'], outPath) != True:
				self.MessageBox('Failed to download file "' + element['Name'] + '"', 'Download Error')
				return
			self.statusbar.showMessage('Downloaded file "' + element['Name'] + '"', 5000)
		elif element['Type'] == 'directory':
			outPath = str(QFileDialog.getExistingDirectory(self, 'Select Download Directory'))
			if len(outPath) <= 0:
				return
			outDir = outPath + '/' + element['Name']
			self.statusbar.showMessage('Downloading directory "' + element['Name'] + '"...', 5000)
			self.repaint()	# Force the thread to update the GUI right now
			if self.DownloadDirectory(element['Path'], outDir):
				self.statusbar.showMessage('Downloaded directory "' + element['Name'] + '"', 5000)
			else:
				self.statusbar.showMessage('Failed to download directory "' + element['Name'] + '"', 5000)
		return
	
	def DownloadDirectory(self, fatfsPath:str, computerPath:str):
		if os.path.exists(computerPath):
			self.MessageBox('Directory "' + computerPath + '" already exists', 'Directory Exists Error')
			return False
		
		dirContents = self.Forth.ListDirectory(fatfsPath)
		if dirContents is None:
			self.MessageBox('Fatfs directory "' + fatfsPath + '" does not exist', 'Directory Does Not Exist Error')
			return False
		
		os.makedirs(computerPath)

		for f in dirContents['Files']:
			if self.DownloadFile(fatfsPath + '/' + f['Name'], computerPath + '/' + f['Name']) != True:
				self.MessageBox('Failed to download file "' + f['Name'] + '"', 'Download Error')
				return False
		
		for d in dirContents['Subdirectories']:
			if self.DownloadDirectory(fatfsPath + '/' + d['Name'], computerPath + '/' + d['Name']) != True:
				self.MessageBox('Failed to download directory "' + d['Name'] + '"', 'Download Error')
				return False
		
		return True
	
	def UploadFile(self, fatfsPath:str, computerPath:str):
		if not CheckFatfsPath(fatfsPath, allowFileExtension=True):
			return False
		try:
			with open(computerPath, 'rb') as f:
				binData = f.read()
		except:
			return False
		return self.Forth.UploadFile(fatfsPath, binData)
	
	def listWidgetDirectoryContentsSelectionToElement(self):
		item = self.listWidgetDirectoryContents.currentItem()
		if item is None:
			return None
		item = item.text()
		if item == '.':
			return {'Type': 'directory', 'Name': GetFatfsDirectoryNameFromPath(self.CurrentDirectoryContents['Path']), 'Path': NormalizeFatfsPath(self.CurrentDirectoryContents['Path'])}
		if item == '..':
			path = NormalizeFatfsPath(self.CurrentDirectoryContents['Path'])
			split = path.split('/')
			path = ''
			for i in range(len(split) - 1):
				path += split[i] + '/'
			path = path[:-1]
			if '/' not in path:
				path += '/'
			name = split[-2]
			if ':' in name or name == '':
				name = '/'
			return {'Type': 'directory', 'Name': GetFatfsDirectoryNameFromPath(path), 'Path': NormalizeFatfsPath(path)}
		for element in self.CurrentDirectoryContents['Files'] + self.CurrentDirectoryContents['Subdirectories']:
			if element['Name'] == item:
				return element
		return None




	def MessageBox(self, text:str, title='', icon=QMessageBox.Warning):
		msg = QMessageBox()
		msg.setText(text)
		msg.setWindowTitle(title)
		msg.setIcon(icon)
		msg.exec_()
		return
	
	def listWidgetDirectoryContents_currentItemChanged(self):
		self.DisplaySelectedItemInfo()
		return
	
	def listWidgetDirectoryContents_itemDoubleClicked(self):
		element = self.listWidgetDirectoryContentsSelectionToElement()
		if element is None:
			return
		if element['Type'] == 'directory':
			self.RefreshDirectory(element['Path'])
		elif element['Type'] == 'file':
			self.Download()
		return
	
	def pushButtonUploadFile_clicked(self):
		if self.CurrentDirectoryContents is None:
			return
		fatfsPathPrefix = self.CurrentDirectoryContents['Path']
		inPath, ok = QFileDialog.getOpenFileName(self, 'Upload File', '', '')
		if ok:
			inPath = inPath.replace('\\', '/')
			fileName = inPath.split('/')[-1].upper()

			if not CheckFatfsName(fileName, allowFileExtension=True):
				fileName, ok = QInputDialog.getText(self, 'File Name', 'The file name "' + fileName + " is incompatible with FATFS.\nEnter a new 8.3 name for the file:")
				if not ok:
					return
			
			fileName = fileName.upper()
			fatfsPath = fatfsPathPrefix + '/' + fileName
			self.statusbar.showMessage('Uploading file "' + fileName + '"...', 5000)
			self.repaint()	# Force the thread to update the GUI right now
			if self.UploadFile(fatfsPath, inPath):
				self.RefreshDirectory(self.CurrentDirectoryContents['Path'])
				self.statusbar.showMessage('Uploaded file "' + fileName + '"', 5000)
			else:
				self.MessageBox('Failed to upload file "' + fileName + '"', 'Upload Error')
		return
		
	def lineEditCurrentDirectoryPath_clicked(self):
		self.RefreshDirectory(self.lineEditCurrentDirectoryPath.text())
		return
	