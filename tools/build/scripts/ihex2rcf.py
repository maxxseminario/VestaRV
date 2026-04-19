#!/usr/bin/env python3

import argparse
from intelhex import IntelHex

parser = argparse.ArgumentParser()

parser.add_argument(
	'hexFile',
	help='The input Intel hex file')

parser.add_argument(
	'rcfFile',
	help='The output RCF file')

parser.add_argument(
	'startAddr',
	help='The start address of the memory (RAM or ROM) to begin reading from the Intel hex file')

parser.add_argument(
	'size',
	help='The size of the memory (RAM or ROM) in bytes')

parser.add_argument(
	'width',
	type=int,
	help='Word size in bits')

parser.add_argument(
	'--default',
	default='0xFFFFFFFF',
	help='Default word for unspecified addresses')

parser.add_argument(
	'--bootloaderUsesSpiFlashCommands',
	action='store_true',
	default=False,
	help='Used if the bootloader expects RAM sections of a 4-byte start address, a 4-byte end address, and then (end - start) bytes in between')

parser.add_argument(
	'--eraseEmptySegments',
	action='store_true',
	default=False,
	help='If this and --bootloaderUsesSpiFlashCommands are enabled, then all empty segments in RAM will be filled with the default word')

parser.add_argument(
	'--allow_undefined',
	action='store_true',
	default=False,
	help='Allows data sections that are undefined and fills them with the default value')

args = parser.parse_args()

# Convert hex to ints
if args.startAddr.startswith('0x'):
	args.startAddr = int(args.startAddr, 16)
else:
	args.startAddr = int(args.startAddr)

if args.size.startswith('0x'):
	args.size = int(args.size, 16)
else:
	args.size = int(args.size)

if args.default.startswith('0x'):
	args.default = int(args.default, 16)
else:
	args.default = int(args.default)



def binword(w, width=32):
	"""Return a width-length, left-zero-padded bit string binary representation
	of the integer w."""
	fmtstr = '{:0' + str(width) + 'b}'
	return fmtstr.format(w)


bytewidth = args.width // 8
if args.width not in [8, 16, 32, 64]:
	raise Exception('--width must be a power of 2 and be at least 8')

if args.startAddr % bytewidth != 0:
	raise Exception('--startAddr must be divisible by', bytewidth)
if args.size % bytewidth != 0:
	raise Exception('--size must be divisible by', bytewidth)

cmdDumpSegment = 0x831D2F7C
cmdEraseSegment = 0xDBE556E8
cmdWriteWord = 0x44573DB0
cmdWriteMaskedWord = 0x1EC021EE
cmdExecuteProgram = 0xAE3BF97C

h = IntelHex(args.hexFile)

# Padding is *per byte* here, we need complete words and are specifying the
# Default *word*.  This lets us detect the missing values
h.padding = None

s = ''

# If the bootloader is using RAM segments...
if args.bootloaderUsesSpiFlashCommands:
	endAddr = args.startAddr + args.size
	numWords = args.size // bytewidth

	# Collapse all the bytes in the program into words, leaving the word as "None" if the Intel Hex file has nothing in that location
	allWords = [None for i in range(numWords)]
	for i in range(numWords):
		start = args.startAddr + (i * bytewidth)
		wordBytes = [h[i] for i in range(start, start + bytewidth)]
		if all([b is None for b in wordBytes]):
			continue
		word = 0
		for j, b in enumerate(wordBytes):
			if b is None:
				if args.allow_undefined:
					b = 0xFF & (args.default >> (j * 8))
				else:
					raise Exception('Bytes must be specified for a complete word')
			word += b << (j * 8)
		allWords[i] = word
	
	# Get the addresses of all RAM segments separated by the minimum number of consecutive blanks
	minConsecutiveBlanks = 16 // bytewidth
	segments = []
	
	# Find the first non-blank word
	start = None
	end = None
	for i in range(len(allWords)):
		w = allWords[i]
		if w is not None:
			start = i
			break
	
	blankCount = 0
	for i in range(start, len(allWords)):
		w = allWords[i]
		if w is None:
			blankCount += 1
			if blankCount == minConsecutiveBlanks:
				# This is the end of a segment
				segments.append({'StartIndex': start, 'LengthWords': i + 1 - minConsecutiveBlanks - start})
				start = None
		else:
			blankCount = 0
			if start is None:
				start = i
	if start is not None:
		segments.append({'StartIndex': start, 'LengthWords': len(allWords) - start})
	
	# Write each dump segment to the RCF file
	defaultString = binword(args.default, args.width) + '\n'
	for seg in segments:
		startAddr = args.startAddr + (seg['StartIndex'] * bytewidth)
		endAddr = startAddr + (seg['LengthWords'] * bytewidth)
		print('Dump: start =', hex(startAddr), 'end =', hex(endAddr))
		s += binword(cmdDumpSegment, args.width) + '\n'
		s += binword(startAddr, args.width) + '\n'
		s += binword(endAddr, args.width) + '\n'
		for i in range(seg['StartIndex'], seg['StartIndex'] + seg['LengthWords']):
			word = allWords[i]
			if word is None:
				s += defaultString
			else:
				s += binword(allWords[i], args.width) + '\n'
	
	if args.eraseEmptySegments:
		# Write each erase segment to the RCF file
		if segments[0]['StartIndex'] != 0:
			seg = segments[0]
			startAddr = args.startAddr + (0 * bytewidth)
			endAddr = startAddr + (seg['StartIndex'] * bytewidth)
			print('Erase: start =', hex(startAddr), 'end =', hex(endAddr))
			s += binword(cmdEraseSegment, args.width) + '\n'
			s += binword(startAddr, args.width) + '\n'
			s += binword(endAddr, args.width) + '\n'
			s += binword(args.default, args.width) + '\n'
		
		for i in range(1, len(segments)):
			seg1 = segments[i - 1]
			seg2 = segments[i]
			startAddr = args.startAddr + ((seg1['StartIndex'] + seg1['LengthWords']) * bytewidth)
			endAddr = args.startAddr + (seg2['StartIndex'] * bytewidth)
			print('Erase: start =', hex(startAddr), 'end =', hex(endAddr))
			s += binword(cmdEraseSegment, args.width) + '\n'
			s += binword(startAddr, args.width) + '\n'
			s += binword(endAddr, args.width) + '\n'
			s += binword(args.default, args.width) + '\n'
		
		if (segments[-1]['StartIndex'] + segments[-1]['LengthWords']) < len(allWords):
			seg = segments[-1]
			startAddr = args.startAddr + ((seg['StartIndex'] + seg['LengthWords']) * bytewidth)
			endAddr = args.startAddr + args.size
			print('Erase: start =', hex(startAddr), 'end =', hex(endAddr))
			s += binword(cmdEraseSegment, args.width) + '\n'
			s += binword(startAddr, args.width) + '\n'
			s += binword(endAddr, args.width) + '\n'
			s += binword(args.default, args.width) + '\n'
	
	# Write the execute program command to the RCF file
	s += binword(cmdExecuteProgram, args.width) + '\n'
else:
	# Dump all the addresses
	for addr in range(args.startAddr, (args.startAddr + args.size), bytewidth):
		word = 0
		bites = [h[a] is None for a in range(addr, addr+bytewidth)]

		if all(bites):
			# All bytes in the word are None
			word = args.default
		else:
			if any(bites):
				# At least one of the bytes in the word is None
				if args.allow_undefined:
					for i, b in enumerate(bites):
						if b is True:	# True when None occupies the byte
							h[addr + i] = 0xFF & (args.default >> (i * 8))
				else:
					raise Exception('Bytes must be specified for a complete word')
			for b in range(bytewidth):
				word += h[addr + b] << (8*b)

		s += binword(word, args.width) + '\n'

#s += binword(0, args.width) + '\n'

# Write the output file
with open(args.rcfFile, 'w', newline='\n') as fw:
	fw.write(s)

print('Created RCF file', args.rcfFile, 'from Intel hex file', args.hexFile)