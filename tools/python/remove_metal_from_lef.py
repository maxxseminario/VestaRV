#!/usr/bin/env python3
import argparse

def removeBetween(string, startKey, endKey, required=False, printout=False):
	startIndex = string.find(startKey)
	if startIndex < 0:
		if required is True:
			raise Exception('Could not find startKey "' + startKey + '"')
		else:
			return s
	endIndex = string.find(endKey, startIndex + len(startKey))
	if endIndex < 0:
		raise Exception('Could not find endKey "' + endKey + '"')
	endIndex += len(endKey)
	if printout is True:
		print('Removing:')
		print(s[startIndex:endIndex])
		print('')
		print('')
		print('')
	return s[:startIndex] + s[endIndex:]

parser = argparse.ArgumentParser()

parser.add_argument(
	'lefFile',
	metavar='lefFile',
	help='Path to .lef file to modify')

parser.add_argument(
	'metalName',
	metavar='metalName',
	help='Name of the metal to remove')

parser.add_argument(
	'--metalBelowName',
	metavar='metalBelowName',
	nargs=1,
	default=None,
	help='Name of the metal that is below the metal to be removed')

parser.add_argument(
	'--viaName',
	metavar='viaName',
	nargs=1,
	default=None,
	help='Name of the via to remove below the metal to be removed')

parser.add_argument(
	'--metalAboveName',
	metavar='metalAboveName',
	nargs=1,
	default=None,
	help='Name of the metal that is above the metal to be removed')

parser.add_argument(
	'--viaAboveName',
	metavar='viaAboveName',
	nargs=1,
	default=None,
	help='Name of the via to remove above the metal to be removed')

args = parser.parse_args()

m = args.metalName
mbelow = args.metalBelowName
v = args.viaName
mabove = args.metalAboveName
vabove = args.viaAboveName

if mbelow is not None:
	mbelow = mbelow[0]	# Take the first and only element out of the list (artifact of nargs = 1)

if v is not None:
	v = v[0]	# Take the first and only element out of the list (artifact of nargs = 1)

if mabove is not None:
	mabove = mabove[0]	# Take the first and only element out of the list (artifact of nargs = 1)

if vabove is not None:
	vabove = vabove[0]	# Take the first and only element out of the list (artifact of nargs = 1)

s = ''
with open(args.lefFile, 'r') as f:
	s = f.read()

s = removeBetween(s, 'LAYER ' + m + '\n', 'END ' + m)
if mbelow is not None:
	s = removeBetween(s, 'VIARULE ' + m + '_' + mbelow + ' GENERATE', 'END ' + m + '_' + mbelow)
	s = removeBetween(s, 'VIA ' + m + '_' + mbelow + 'c\n', 'END ' + m + '_' + mbelow + 'c')
	s = removeBetween(s, 'VIA ' + m + '_' + mbelow + 's\n', 'END ' + m + '_' + mbelow + 's')

s = removeBetween(s, 'SAMENET ' + m + ' ' + m, ';', required=False)
s = removeBetween(s, '  LAYER ' + m + '\n    WIDTH', 'END ' + m, required=False)

if mbelow is not None:
	s = removeBetween(s, 'USEVIARULE ' + m + '_' + mbelow, ';', required=False)

if v is not None:
	s = removeBetween(s, 'LAYER ' + v + '\n', 'END ' + v)
	s = removeBetween(s, 'SAMENET ' + v, ';')

if mabove is not None:
	s = removeBetween(s, 'VIARULE ' + mabove + '_' + m + ' GENERATE', 'END ' + mabove + '_' + m)
	s = removeBetween(s, 'VIA ' + mabove + '_' + m + 'c\n', 'END ' + mabove + '_' + m + 'c')
	s = removeBetween(s, 'VIA ' + mabove + '_' + m + 's\n', 'END ' + mabove + '_' + m + 's')

if vabove is not None:
	s = removeBetween(s, 'SAMENET ' + vabove + ' ' + v, ';')


if m in s:
	print('Warning: metal ' + m + ' is still in the .lef file!')

if v is not None:
	if v in s:
		print('Warning: via ' + v + ' is still in the .lef file!')

with open(args.lefFile, 'w', newline='\n') as f:
	f.write(s)