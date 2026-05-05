#!/usr/bin/env python3

import argparse

def FindOrError(haystack, needle, startindex=0):
	index1 = haystack.find(needle, startindex)
	if index1 < 0:
		raise Exception('Could not find string \"' + needle + '\"')
	index2 = index1 + len(needle)
	return index1, index2

def FindOrNone(haystack, needle, startindex=0):
	index1 = haystack.find(needle, startindex)
	if index1 < 0:
		return None
	index2 = index1 + len(needle)
	return index1, index2

parser = argparse.ArgumentParser()

parser.add_argument(
	'inputVerilogFile',
	help='Input Verilog file that contains undesired power nets')

parser.add_argument(
	'outputVerilogFile',
	help='Output Verilog file that the power nets are removed from')

parser.add_argument(
	'--excludeCellsFile',
	type=str,
	default='',
	help='A list of cells, one per line, that will not be modified by this program. VDD and VSS will not be removed within these cells.')

parser.add_argument(
	'--removePowerWires',
	action='store_true',
	default=False,
	help='Removes the wire VDD ; and wire VSS ; lines')

parser.add_argument(
	'--renamePowerNets',
	action='store_true',
	default=False,
	help='Renames all instances of VDD and VSS to vdd! and vss! respectively')

parser.add_argument(
	'--removeFill',
	action='store_true',
	default=False,
	help='Removes FILL cells')

parser.add_argument(
	'--addPowerPorts',
	action='store_true',
	default=False,
	help='Adds VDD and VSS inout ports and wires so that VerilogIn will create them')




args = parser.parse_args()

# Parse the exclude cells file
excludeCells = []
if len(args.excludeCellsFile) > 0:
	with open(args.excludeCellsFile, 'r', newline='\n') as fr:
		s = fr.read()
	excludeCells = list(filter(None, s.strip().split('\n')))

# Read the input file
with open(args.inputVerilogFile, 'r', newline='\n') as fr:
	s = fr.read()

# Remove power wires
if (args.removePowerWires is True) or (args.addPowerPorts is True):
	s = s.replace('wire VDD;', '')
	s = s.replace('wire VSS;', '')

if args.addPowerPorts is True:
	# Find the end of the module
	# This assumes that the top module is the first one instantiated
	s = s.replace(");", ",\n\tVDD,\n\tVSS);\n\tinout VDD;\n\tinout VSS;", 1)

# Open the output file for writing
with open(args.outputVerilogFile, 'w', newline='\n') as fw:
	writeindex = 0
	fillCellsRemoved = 0

	# Find the top module
	i1, i2 = FindOrError(s, 'module ')
	i1, i2 = FindOrError(s, '(', i2)
	i1, i2 = FindOrError(s, ');', i2)

	# Find each module within the top module
	while True:
		# Find the opening parenthesis of the module
		f = FindOrNone(s, '(', i2)
		if f is None:
			break
		par1begin, par1end = f

		# Find the closing parenthesis of the module
		par2begin, par2end = FindOrError(s, ');', par1end)

		# Get the instance name of the module
		i = par1begin - 1
		while s[i].isspace():
			i -= 1
		instnameend = i + 1
		while not s[i].isspace():
			i -= 1
		instnamebegin = i + 1
		instname = s[instnamebegin:instnameend]

		# Get the cell name and instance name of the module
		while s[i].isspace():
			i -= 1
		cellnameend = i + 1
		while not s[i].isspace():
			i -= 1
		cellnamebegin = i + 1
		cellname = s[cellnamebegin:cellnameend]

		# Is this an excluded cell?
		if cellname in excludeCells:
			i2 = par2end
			continue

		# Is this a fill cell to remove?
		if args.removeFill is True:
			if cellname.startswith('FILL'):
				#if not cellname[4:].startswith('TIE'):
				# Get the beginning of the line
				while s[i] != '\n':
					if not s[i].isspace():
						i += 1
						break
					i -= 1
				if (s[i - 1] == '\r') and (s[i] == '\n'):
					i -= 1

				# Remove the fill cell
				fw.write(s[writeindex:i])
				writeindex = par2end
				fillCellsRemoved += 1
				i2 = par2end
				continue

		# Find .VSS within the instance and remove it
		vssbegin = None
		f = FindOrNone(s, '.VSS(', par1end)
		if f is not None:
			vssbegin, i2 = f
			i1, vssend = FindOrError(s, ')', i2)

			# Include everything before .VSS until either '(' or ')'
			i = vssbegin - 1
			while not ((s[i] == ')') or (s[i] == '(')):
				i -= 1
			vssbegin = i + 1

			## Remove .VSS(*)
			#vsslen = vssend - vssbegin
			#s = s[:vssbegin] + s[vssend:]
			#
			## Adjust all indices after vssend
			##par2begin -= vsslen
			#ar2end -= vsslen

		# Find .VDD within the instance and remove it
		vddbegin = None
		f = FindOrNone(s, '.VDD(', par1end)
		if f is not None:
			vddbegin, i2 = f
			i1, vddend = FindOrError(s, ')', i2)

			# Include everything before .VDD until either '(' or ')'
			i = vddbegin - 1
			while not ((s[i] == ')') or (s[i] == '(')):
				i -= 1
			vddbegin = i + 1

			## Remove .VDD(*)
			#vddlen = vddend - vddbegin
			#s = s[:vddbegin] + s[vddend:]
			#
			## Adjust all indices after vddend
			##par2begin -= vddlen
			#par2end -= vddlen

		# Remove the unwanted pieces
		if (vssbegin is not None) and (vddbegin is not None):
			if set(range(vssbegin, vssend)).intersection(range(vddbegin, vddend)):
				# The ranges overlap
				rembegin = min(vssbegin, vddbegin)
				remend = max(vssend, vddend)

				fw.write(s[writeindex:rembegin])
				writeindex = remend
			else:
				# The ranges do not overlap. Which comes first?
				if vssbegin < vddbegin:
					# Remove VSS first
					fw.write(s[writeindex:vssbegin])
					writeindex = vssend
					fw.write(s[writeindex:vddbegin])
					writeindex = vddend
				else:
					# Remove VDD first
					fw.write(s[writeindex:vddbegin])
					writeindex = vddend
					fw.write(s[writeindex:vssbegin])
					writeindex = vssend
		else:
			if vssbegin is not None:
				# Remove VSS
				fw.write(s[writeindex:vssbegin])
				writeindex = vssend
			if vddbegin is not None:
				# Remove VDD
				fw.write(s[writeindex:vddbegin])
				writeindex = vddend

		i2 = par2end

	# Write to the end of the file
	fw.write(s[writeindex:])

# Rename power nets
if args.renamePowerNets is True:
	with open(args.outputVerilogFile, 'r', newline='\n') as fr:
		s = fr.read()
	s = s.replace('VDD', 'vdd')
	s = s.replace('VSS', 'vss')
	with open(args.outputVerilogFile, 'w', newline='\n') as fw:
		fw.write(s)

print('Finished removing VDD and VSS connections from the Verilog file')
if fillCellsRemoved > 0:
	print('Removed', fillCellsRemoved, 'fill cells from the Verilog file')