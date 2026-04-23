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
	
	def WriteRcfFile(self, rcfFilePath:str, verify=False, showProgressBar=False):
		"""
		Write an RCF file directly to flash starting at address 0.
		RCF format: one 32-bit word per line in binary (e.g., 00010000101011011011111011101111)
		"""
		# Read the RCF file
		try:
			with open(rcfFilePath, 'r') as f:
				lines = f.readlines()
		except Exception as e:
			print(f'Error reading RCF file: {e}')
			return False
		
		# Parse words from binary strings
		words = []
		for line in lines:
			line = line.strip()
			if len(line) == 32 and all(c in '01' for c in line):
				# Convert binary string to 32-bit word (big-endian in file)
				word = int(line, 2)
				words.append(word)
		
		if len(words) == 0:
			print('No valid data found in RCF file')
			return False
		
		print(f'Read {len(words)} words from RCF file')
		
		# Convert words to bytes (little-endian for SPI flash)
		allBytes = b''
		for word in words:
			allBytes += word.to_bytes(4, byteorder='little')
		
		# Pad to 256-byte page boundary
		if len(allBytes) % 256 != 0:
			padLen = 256 - (len(allBytes) % 256)
			allBytes += b'\x00' * padLen
		
		# Split into 256-byte pages
		pages = []
		for pageAddr in range(0, len(allBytes), 256):
			pageBytes = allBytes[pageAddr:pageAddr+256]
			pages.append({'PageAddress': pageAddr, 'Bytes': pageBytes})
		
		print(f'Writing {len(pages)} pages to flash starting at address 0x0')
		
		# Show first 16 bytes for debugging
		if len(allBytes) >= 16:
			firstBytes = allBytes[:16]
			hexStr = ' '.join([f'{b:02x}' for b in firstBytes])
			print(f'First 16 bytes: {hexStr}')
			word0 = int.from_bytes(firstBytes[0:4], 'little')
			word1 = int.from_bytes(firstBytes[4:8], 'little')
			word2 = int.from_bytes(firstBytes[8:12], 'little')
			word3 = int.from_bytes(firstBytes[12:16], 'little')
			print(f'First 4 words (little-endian): {hex(word0)} {hex(word1)} {hex(word2)} {hex(word3)}')
		
		# Program the pages
		iter = pages
		if showProgressBar:
			pbar = ProgressBar(widgets=['Programming: ', Percentage(), ' ', Bar(), ' ', ETA()])
			iter = pbar(iter)
		
		pagesVerified = 0
		for pageDict in iter:
			pageAddress = pageDict['PageAddress']
			pageBytes = pageDict['Bytes']
			
			# Write the page
			sleep(2e-3)
			if self.WritePage(pageAddress, pageBytes) != True:
				print('Failed to write page')
				return False
			
			# Verify
			if verify:
				sleep(10e-3)
				readbackPageBytes = self.Read(pageAddress, 256)
				if (readbackPageBytes is None) or (pageBytes != readbackPageBytes):
					print(f'Verification error at page address {hex(pageAddress)}')
					return False
				pagesVerified += 1
		
		# Print verification summary
		if verify:
			print(f'Verification successful: {pagesVerified} pages verified')
		
		print('Successfully wrote RCF to flash memory')
		return True
	
	def WritePage(self, pageAddress:int, binData:bytes):
		attempt = 0
		ret = False
		while ret != True:
			if attempt == self.Attempts:
				print(f'ERROR: Failed to write page at address {hex(pageAddress)} after {self.Attempts} attempts')
				return False
			ret = self.forth.WriteFlashPage(pageAddress, binData)
			if ret is None:
				print(f'WARNING: WriteFlashPage returned None for address {hex(pageAddress)} (attempt {attempt+1}/{self.Attempts})')
				attempt += 1
				continue
			if ret is True:
				return True
			attempt += 1
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
		fillEmptySegments = True  # TODO: Sourece of error
		
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
		
		# Debug: print first page address
		if len(nonblankPages) > 0:
			firstPage = nonblankPages[0]
			print(f'First page will be written to flash address: {hex(firstPage["PageAddress"])}')
			# Show first 16 bytes of data
			firstBytes = firstPage["Bytes"][:16]
			hexStr = ' '.join([f'{b:02x}' for b in firstBytes])
			print(f'First 16 bytes: {hexStr}')
			# Interpret as 4 little-endian 32-bit words
			if len(firstBytes) >= 16:
				word0 = int.from_bytes(firstBytes[0:4], 'little')
				word1 = int.from_bytes(firstBytes[4:8], 'little')
				word2 = int.from_bytes(firstBytes[8:12], 'little')
				word3 = int.from_bytes(firstBytes[12:16], 'little')
				print(f'First 4 words (little-endian): {hex(word0)} {hex(word1)} {hex(word2)} {hex(word3)}')
			
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
				print('Failed to write page')
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
			print(f'Verification successful: {pagesVerified} pages verified')
		
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
	