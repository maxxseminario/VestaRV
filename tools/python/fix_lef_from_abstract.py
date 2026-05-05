#!/usr/bin/env python3
import argparse

parser = argparse.ArgumentParser()

parser.add_argument(
	'lefFile',
	metavar='lefFile',
	help='Path to .lef file to modify')

args = parser.parse_args()

# Open LEF file
s = None
with open(args.lefFile, 'r', newline='\n') as f:
	s = f.read()
	
# Remove property definitions
startStr = 'PROPERTYDEFINITIONS\n'
endStr = 'END PROPERTYDEFINITIONS\n'
startIndex = s.find(startStr)
if startIndex >= 0:
	endIndex = s.find(endStr, startIndex + len(startStr))
	if endIndex < 0:
		raise Exception('Could not find "' + endStr + '"')
	endIndex += len(endStr)
	s = s[:startIndex] + s[endIndex:]

# Remove layer definition data
startStr = 'BUSBITCHARS "[]" ;\n'
endStr = '\nMACRO'
startIndex = s.find(startStr)
if startIndex < 0:
	raise Exception('Could not find "' + startStr + '"')
endIndex = s.find(endStr, startIndex + len(startStr))
if endIndex < 0:
	raise Exception('Could not find "' + endStr + '"')

startIndex += len(startStr)
s = s[:startIndex] + s[endIndex:]

# Retype as a block
s = s.replace('  CLASS CORE ;', '  CLASS BLOCK ;')

# Remove extra properties
s = s.replace('  PROPERTY CatenaDesignType "asic" ;\n', '')
s = s.replace('  PROPERTY CatenaDesignType "deviceLevel" ;\n', '')
s = s.replace('  PROPERTY oaTaper "virtuosoDefaultSetup" ;\n', '')

# Save LEF file
with open(args.lefFile, 'w', newline='\n') as f:
	f.write(s)

print('Finished fixing LEF file "' + args.lefFile + '"')
