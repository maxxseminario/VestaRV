#!/usr/bin/env python3

import argparse

parser = argparse.ArgumentParser()

parser.add_argument(
	'inputCdlFile',
	help='Input CDL file')

parser.add_argument(
	'outputCdlFile',
	help='Output CDL file')

args = parser.parse_args()

s = None
print('Reading CDL netlist from ' + args.inputCdlFile)
with open(args.inputCdlFile, 'r', newline='\n') as fr:
	s = fr.read()

# Find each $PINS declaration
while True:
	# Find $PINS
	indexPins = s.find('$PINS')
	
	if indexPins < 0:
		break
	
	# Get the cell name
	indexCellNameEnd = indexPins - 1
	while s[indexCellNameEnd].isspace():
		indexCellNameEnd -= 1
	indexCellNameEnd += 1
	indexCellNameBegin = indexCellNameEnd - 1
	while not s[indexCellNameBegin].isspace():
		indexCellNameBegin -= 1
	indexCellNameBegin += 1
	cellName = s[indexCellNameBegin:indexCellNameEnd]
	
	# Get the instance name
	indexInstanceNameEnd = indexCellNameBegin - 1
	while s[indexInstanceNameEnd] != '/':
		indexInstanceNameEnd -= 1
	indexInstanceNameEnd -= 1
	while s[indexInstanceNameEnd].isspace():
		indexInstanceNameEnd -= 1
	indexInstanceNameEnd += 1
	indexInstanceNameBegin = indexInstanceNameEnd - 1
	while not s[indexInstanceNameBegin].isspace():
		indexInstanceNameBegin -= 1
	indexInstanceNameBegin += 1
	instanceName = s[indexInstanceNameBegin:indexInstanceNameEnd]
	
	# Get the $PINS map
	indexPinsMapBegin = indexPins + len('$PINS')
	indexPinsMapEnd = indexPinsMapBegin
	while not ((s[indexPinsMapEnd] == '\n') and (s[indexPinsMapEnd + 1] != '+')):
		indexPinsMapEnd += 1
	indexPinsMapEnd -= 1
	pinsMap = s[indexPinsMapBegin:indexPinsMapEnd]
	
	# Create the new pins map
	newPinsMap = pinsMap
	while True:
		iend = newPinsMap.find('=')
		if iend < 0:
			break
		iend += 1
		ibegin = iend - 1
		while not newPinsMap[ibegin].isspace():
			ibegin -= 1
			if ibegin < 0:
				break
		ibegin += 1
		
		newPinsMap = newPinsMap[:ibegin] + newPinsMap[iend:]
	
	# Create the replacement line(s)
	s2 = instanceName + ' ' + newPinsMap + ' / ' + cellName + '\n'
	
	# Replace the old instance declaration with the new one
	s = s[:indexInstanceNameBegin] + s2 + s[indexPinsMapEnd:]
	
	# Print
	print('Fixing pins map in cell ' + cellName + ', instance ' + instanceName)

with open(args.outputCdlFile, 'w', newline='\n') as fw:
	fw.write(s)

print('Modified CDL netlist written to ' + args.outputCdlFile)
