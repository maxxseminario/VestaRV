#!/usr/bin/env python3
from ForthInterface import ForthInterface
from ProgramDump import *

from intelhex import IntelHex	# intelhex (install with pip install intelhex)
from progressbar import ProgressBar, Percentage, Bar, ETA	# progressbar2 (install with pip install progressbar2)
from time import sleep

class ProgramFlash():
	
	forth = None
	
	Attempts = 3
	
	def Setup(self, forthInterface:ForthInterface):
		if forthInterface.uart is None:
			return False
		if not forthInterface.uart.IsOpen:
			return False
		if forthInterface.ActiveChip is None:
			return False
		if forthInterface.ActiveBoard is None:
			return False
		if forthInterface.ActiveBootMode is None:
			return False
		
		self.forth = forthInterface
		return True
	
	def WritePage(self, pageAddress:int, binData:bytes):
		attempt = 0
		ret = False
		while ret != True:
			if attempt == self.Attempts:
				return False
			ret = self.forth.WriteFlashPage(pageAddress, binData)
			if ret is None:
				return None
			if ret is True:
				return True
		return False
	
	def ErasePage(self, pageAddress:int):
		return self.forth.EraseFlashPage(pageAddress)
	
	def Read(self, startAddress:int, length:int):
		return self.forth.ReadFlash(startAddress, length)
	
	def Write(self, startAddress:int, binData:bytes, showProgressBar=False):
		if startAddress < 0:
			return None
		totalLength = len(binData)
		if totalLength <= 0:
			return True
		
		endAddress = startAddress + totalLength	# Actually, this is 1 + the last address
		
		# Create a progress bar (if desired)
		numPages = (255 + (startAddress + totalLength) - (startAddress & 0xFFFFFF00)) // 256
		iter = range(numPages)
		if showProgressBar:
			pbar = ProgressBar(widgets=['Programming: ', Percentage(), ' ', Bar(), ' ', ETA()])
			iter = pbar(range(numPages))
		
		# Segment into 256-byte pages
		pageAddress = startAddress
		for i in iter:
			# Get the size of the prefix, payload, and suffix (where applicable)
			pageStartAddress = pageAddress & 0xFFFFFF00	# 256-byte aligned
			prefixLen = pageAddress % 256
			payloadLen = 256 - prefixLen
			if payloadLen > len(binData):
				payloadLen = len(binData)
			suffixLen = 256 - prefixLen - payloadLen
			suffixStartAddress = pageStartAddress + prefixLen + payloadLen
			
			# Read the prefix from the flash memory (if necessary)
			prefixData = b''
			if prefixLen > 0:
				prefixData = self.Read(pageStartAddress, prefixLen)
				if type(prefixData) != bytes:
					return None
			
			# Get the payload data
			payloadData = binData[:prefixLen]
			binData = binData[prefixLen:]
			
			# Read the suffix from the flash memory (if necessary)
			suffixData = b''
			if suffixLen > 0:
				suffixData = self.Read(suffixStartAddress, suffixLen)
				if type(suffixData) != bytes:
					return None
			
			# Construct the 256-byte page and write it to the flash memory
			pageData = prefixData + payloadData + suffixData
			ret = self.WritePage(pageStartAddress, pageData)
			if ret != True:
				return ret
		
		return True
	
	def WriteProgram(self, intelHexFilePath:str, verify=False, skipBlank=False, showProgressBar=False):
		defaultWordValue = 0xDEADBEEF
		fillEmptySegments = True
		
		if self.forth.ActiveChip.BootloaderUsesSpiFlashCommands:
			pages = SpiFlashCommandsToSpiFlashPages(self.forth.ActiveChip, IntelHexToSpiFlashCommands(self.forth.ActiveChip, intelHexFilePath, defaultWordValue=defaultWordValue, fillEmptySegments=fillEmptySegments), defaultWordValue=defaultWordValue)
		else:
			pages = IntelHexToRawWords(self.forth.ActiveChip, intelHexFilePath, defaultWordValue=defaultWordValue)
		
		if pages is None:
			print('Failed to get pages to write')
			return False
		
		nonblankPages = pages['PagesToWrite']
		consecutiveBlankPages = pages['ConsecutiveBlankPages']
		
		# Print verification status
		if verify:
			print('Verification enabled: will read back and verify each page')
			
		# Program the non-blank pages
		iter = nonblankPages
		if showProgressBar:
			pbar = ProgressBar(widgets=['Programming: ', Percentage(), ' ', Bar(), ' ', ETA()])
			iter = pbar(iter)
		
		pagesVerified = 0
		for pageDict in iter:
			PageAddress = pageDict['PageAddress']
			pageBytes = pageDict['Bytes']
			# Bytes within the words have already been swapped at this point
			# Write the page
			sleep(2e-3)
			if self.WritePage(PageAddress, pageBytes) != True:
				print(f'Failed to write page at address {hex(PageAddress)}')
				return False
			
			# Verify
			if verify:
				sleep(10e-3)
				readbackPageBytes = self.Read(PageAddress, 256)
				if (readbackPageBytes is None) or (pageBytes != readbackPageBytes):
					print('Verification error at page address', hex(PageAddress))
					return False
				pagesVerified += 1
		
		# Print verification summary
		if verify:
			print(f'✓ Verification successful: {pagesVerified} pages verified')
		
		# Erase blank pages
		if len(consecutiveBlankPages) > 0:
			print('Erasing blank pages...')
			if self.forth.ActiveChip.BootForthHasMultiPageFlashEraseCommand:
				for cbp in consecutiveBlankPages:
					# Erase the pages
					if self.forth.EraseFlashMultiPage(cbp['PageAddress'], cbp['NumConsecutiveBlankPages']) != True:
						print('Failed to erase pages at address', PageAddress)
						return False
			else:
				for PageAddress in blankPages:
					# Erase the page
					if self.ErasePage(PageAddress) != True:
						print('Failed to erase pages starting at address', PageAddress)
						return False
			
		return True
	