from intelhex import IntelHex	# intelhex (install with pip install intelhex)

from Chip import Chip

def IntelHexToRawWords(activeChip:Chip, intelHexFilePath:str, defaultWordValue=0xDEADBEEF):
	# Get the RAM start address and length
	RamStartAddress = activeChip.RamStartAddress
	if type(RamStartAddress) != int:
		return None
	if (RamStartAddress < 0) or (RamStartAddress % 256 != 0):
		print('Improper RamStartAddress value')
		return None
	RamSize = activeChip.RamSize
	if type(RamSize) != int:
		return None
	if (RamSize <= 0) or (RamSize % 256 != 0):
		print('Improper RamSize value')
		return None
	RamEndAddress = RamStartAddress + RamSize
	SpiFlashAddressOffset = activeChip.SpiFlashProgramAddress - activeChip.RamStartAddress
	
	bitsPerWord = 32
	bytesPerWord = bitsPerWord // 8
	
	# Parse the Intel Hex file
	ihex = IntelHex(intelHexFilePath)
	if type(ihex) != IntelHex:
		return None

	# Make a list of every non-blank page and every blank page
	pagesToWrite = []
	blankPages = []
	for PageAddress in range(RamStartAddress, RamEndAddress, 256):
		page = [ihex[PageAddress + i] for i in range(256)]
		if all([b == 0xFF for b in page]):
			blankPages.append(PageAddress + SpiFlashAddressOffset)
		else:
			page = [page[i]  if (page[i] is not None) else ((defaultWordValue >> (8 * (i % 4))) & 0xFF) for i in range(len(page))]
			if activeChip.SwapProgramBytes:
				for i in range(0, len(page), bytesPerWord):
					page[i:i+bytesPerWord] = list(reversed(page[i:i+bytesPerWord]))
			pagesToWrite.append({'PageAddress': PageAddress + SpiFlashAddressOffset, 'Bytes': bytes(page)})
	
	# Collect blank pages together
	prevPageAddress = -1
	consecutiveBlankPages = []	# [(address, numConsecutiveBlankPages), ...]
	if len(blankPages) > 0:
		consecutiveBlankPages.append({'PageAddress': blankPages[0], 'NumConsecutiveBlankPages': 1})
	for i in range(len(blankPages[1:])):
		if blankPages[i] - blankPages[i - 1] == 256:
			# These two pages are consecutive. Increment the last element of consecutiveBlankPages
			consecutiveBlankPages[-1]['NumConsecutiveBlankPages'] += 1
		else:
			# These two pages are not consecutive. Create a new element in consecutiveBlankPages
			consecutiveBlankPages.append({'PageAddress': blankPages[i], 'NumConsecutiveBlankPages': 1})
	
	return {'PagesToWrite': pagesToWrite, 'ConsecutiveBlankPages': consecutiveBlankPages}

def WordToBytes(word:int, swapProgramBytes:bool):
	if swapProgramBytes:
		return bytes([(word >> 24) & 0xFF, (word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF])
	else:
		return bytes([word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, (word >> 24) & 0xFF])

def WordsToBytes(words:list, swapProgramBytes:bool):
	return b''.join([WordToBytes(word, swapProgramBytes) for word in words])

def IntelHexToSpiFlashCommands(activeChip:Chip, intelHexFilePath:str, defaultWordValue=0xDEADBEEF, fillEmptySegments=True):	
	# Get the RAM start address and length
	RamStartAddress = activeChip.RamStartAddress
	if type(RamStartAddress) != int:
		return None
	if (RamStartAddress < 0) or (RamStartAddress % 256 != 0):
		print('Improper RamStartAddress value')
		return None
	RamSize = activeChip.RamSize
	if type(RamSize) != int:
		return None
	if (RamSize <= 0) or (RamSize % 256 != 0):
		print('Improper RamSize value')
		return None
	RamEndAddress = RamStartAddress + RamSize
	
	bitsPerWord = 32
	bytesPerWord = bitsPerWord // 8
	#numWords = RamSize // bytesPerWord
	maxConsecutiveBlankWords = 32 // bytesPerWord
	
	# Parse the Intel Hex file
	ihex = IntelHex(intelHexFilePath)
	if type(ihex) != IntelHex:
		return None
		
	# Get the RAM segments
	segments = [list(seg) for seg in ihex.segments()]
	
	# Floor all start addresses and end addresses of the segments to a word address
	for i in range(len(segments)):
		segments[i][0] = (segments[i][0] // bytesPerWord) * bytesPerWord
		segments[i][1] = ((segments[i][1] + bytesPerWord - 1) // bytesPerWord) * bytesPerWord
	
	# Filter out segments that are outside the RAM limits
	for i in reversed(range(len(segments))):
		start, afterEnd = segments[i]
		startOutside, endOutside = False, False
		if not (RamStartAddress <= start < RamEndAddress):
			startOutside = True
		if not (RamStartAddress <= (afterEnd - 1) <= RamEndAddress):
			endOutside = True
		if startOutside and endOutside:
			# Get rid of this segment
			segments.pop(i)
			continue
		elif startOutside or endOutside:
			print('Memory segment is partially in bounds and partially out of bounds of the RAM')
			return None
		
	# Merge segments that are too close together
	for i in reversed(range(1, len(segments))):
		if (segments[i - 1][1] + maxConsecutiveBlankWords * bytesPerWord) > segments[i][0]:
			segments[i - 1][1] = segments[i][1]
			segments.pop(i)
	
	# Create the commands
	commands = []
	
	# If there is nothing at the beginning of the RAM...
	if fillEmptySegments and RamStartAddress != segments[0][0]:
		commands.append({'Type': 'Erase', 'StartAddress': RamStartAddress, 'EndAddress': segments[0][0], 'Word': defaultWordValue})
	
	# Go through each segment
	for segmentIndex, segment in enumerate(segments):
		start = segment[0]
		sameCount = 1
		prevWord = None
		words = []
		for i in range(segment[0], segment[1], bytesPerWord):
			word = 0
			for j in range(bytesPerWord):
				b = ihex[i + j]
				if b is None:
					b = (defaultWordValue >> (i * 8)) & 0xFF
				word |= b << (j * 8)
			
			if word == prevWord:
				sameCount += 1
				if sameCount < maxConsecutiveBlankWords:
					words.append(word)
				elif sameCount == maxConsecutiveBlankWords:
					# End the data command here
					end = i - ((maxConsecutiveBlankWords - 1) * bytesPerWord)
					if end > start:
						commands.append({'Type': 'Dump', 'StartAddress': start, 'EndAddress': end, 'Words': words[:-(maxConsecutiveBlankWords - 1)]})
						start = end
			else:
				if sameCount >= maxConsecutiveBlankWords:
					# End the erase command here
					end = i
					commands.append({'Type': 'Erase', 'StartAddress': start, 'EndAddress': end, 'Word': prevWord})
					start = i
					words = [word]
				else:
					words.append(word)
				sameCount = 1
			
			prevWord = word
		
		# End the command no matter what here
		if sameCount >= maxConsecutiveBlankWords:
			# End the erase command here
			end = segment[1]
			commands.append({'Type': 'Erase', 'StartAddress': start, 'EndAddress': end, 'Word': prevWord})
		else:
			# End the data command here
			end = segment[1]
			commands.append({'Type': 'Dump', 'StartAddress': start, 'EndAddress': end, 'Words': words})
		
		# If there is a gap between this segment and the next...
		if fillEmptySegments and (segmentIndex + 1) < len(segments) and segments[segmentIndex][1] < segments[segmentIndex + 1][0]:
			commands.append({'Type': 'Erase', 'StartAddress': segments[segmentIndex][1], 'EndAddress': segments[segmentIndex + 1][0], 'Word': defaultWordValue})
	
	# If there is nothing at the end of the RAM...
	if fillEmptySegments and RamEndAddress != segments[-1][1]:
		commands.append({'Type': 'Erase', 'StartAddress': segments[-1][1], 'EndAddress': RamEndAddress, 'Word': defaultWordValue})
	
	# Create the bytes for each RAM command
	cmdDumpSegment = 0x831D2F7C
	cmdEraseSegment = 0xDBE556E8
	cmdWriteWord = 0x44573DB0
	cmdWriteMaskedWord = 0x1EC021EE
	cmdExecuteProgram = 0xAE3BF97C
	
	for command in commands:
		if command['Type'] == 'Dump':
			command['CommandWord'] = cmdDumpSegment
			command['Bytes'] = WordToBytes(command['CommandWord'], activeChip.SwapProgramBytes) + WordToBytes(command['StartAddress'], activeChip.SwapProgramBytes) + WordToBytes(command['EndAddress'], activeChip.SwapProgramBytes) + WordsToBytes(command['Words'], activeChip.SwapProgramBytes)
		elif command['Type'] == 'Erase':
			command['CommandWord'] = cmdEraseSegment
			command['Bytes'] = WordToBytes(command['CommandWord'], activeChip.SwapProgramBytes) + WordToBytes(command['StartAddress'], activeChip.SwapProgramBytes) + WordToBytes(command['EndAddress'], activeChip.SwapProgramBytes) + WordToBytes(command['Word'], activeChip.SwapProgramBytes)
	
	commands.append({'Type': 'Execute', 'CommandWord': cmdExecuteProgram, 'Bytes': WordToBytes(cmdExecuteProgram, activeChip.SwapProgramBytes)})

	return commands

def SpiFlashCommandsToSpiFlashPages(activeChip, commands, defaultWordValue=0xDEADBEEF):
	# Get the RAM start address and length
	RamStartAddress = activeChip.RamStartAddress
	if type(RamStartAddress) != int:
		return None
	if (RamStartAddress < 0) or (RamStartAddress % 256 != 0):
		print('Improper RamStartAddress value')
		return None
	RamSize = activeChip.RamSize
	if type(RamSize) != int:
		return None
	if (RamSize <= 0) or (RamSize % 256 != 0):
		print('Improper RamSize value')
		return None
	RamEndAddress = RamStartAddress + RamSize
	if commands is None:
		return None
	SpiFlashAddressOffset = activeChip.SpiFlashProgramAddress - RamStartAddress
	
	bitsPerWord = 32
	bytesPerWord = bitsPerWord // 8
	
	pages = []
	pageIndex = 0
	page = b''
	remainingPageLen = 256
	
	for command in commands:
		sliceIndex = 0
		remainingCommandBytesLen = len(command['Bytes'])
		remainingPageLen = 256 - len(page)
		while remainingCommandBytesLen > 0:
			sliceLen = min(remainingCommandBytesLen, remainingPageLen)
			page += command['Bytes'][sliceIndex:sliceIndex+sliceLen]
			sliceIndex += sliceLen
			remainingCommandBytesLen -= sliceLen
			remainingPageLen = 256 - len(page)
			if remainingPageLen == 0:
				pages.append({'PageAddress': activeChip.SpiFlashProgramAddress + pageIndex * 256, 'Bytes': page})
				page = b''
				remainingPageLen = 256
				pageIndex += 1
	if remainingPageLen > 0:
		defaultWordBytes = WordToBytes(defaultWordValue, activeChip.SwapProgramBytes)
		rem = len(page) % bytesPerWord
		if rem != 0:
			if activeChip.SwapProgramBytes:
				page += defaultWordBytes[rem:4]
			else:
				page += defaultWordBytes[0:rem]
		while len(page) < 256:
			page += defaultWordBytes
		pages.append({'PageAddress': activeChip.SpiFlashProgramAddress + pageIndex * 256, 'Bytes': page})
	
	return {'PagesToWrite': pages, 'ConsecutiveBlankPages': []}
	
def PrintCommands(commands):
	for command in commands:
		if command['Type'] == 'Dump':
			print('Dump: start = 0x{:x}, end = 0x{:x}, size = {:d}, total size = {:d}'.format(command['StartAddress'], command['EndAddress'], command['EndAddress'] - command['StartAddress'], len(command['Bytes'])))
		elif command['Type'] == 'Erase':
			print('Erase: start = 0x{:x}, end = 0x{:x}, size = {:d}, word = 0x{:x}, total size = {:d}'.format(command['StartAddress'], command['EndAddress'], command['EndAddress'] - command['StartAddress'], command['Word'], len(command['Bytes'])))
		elif command['Type'] == 'Execute':
			print('Execute: total size = {:d}'.format(len(command['Bytes'])))
	return
