#!/usr/bin/env python3

import sys
import os
import argparse
from time import sleep

thisScriptDir = os.path.dirname(os.path.abspath(__file__))
repoRootDir = os.path.abspath(thisScriptDir + '/../../')
sys.path.append(repoRootDir + '/tools/chip_programmer/python')

from UART import UART
from Chip import Chip
from ForthInterface import ForthInterface
from ProgramFlash import ProgramFlash

parser = argparse.ArgumentParser()

parser.add_argument(
	'IntelHexFile',
	metavar='HexFile',
	help='Path to Intel hex file containing the program')

parser.add_argument(
	'--port',
	'-p',
	type=str,
	default=None,
	help='The name of the serial port to use')

parser.add_argument(
	'--chip',
	'-c',
	type=str,
	default='myshkin-2025-11',
	help='The chip implementation name (e.g., myshkin-2025-11)')

parser.add_argument(
	'--board',
	'-b',
	type=str,
	default=None,
	help='The name of the circuit board being used')

parser.add_argument(
	'--verify',
	'-v',
	action='store_true',
	default=False,
	help='Verifies the program was written to the SPI flash'
)

parser.add_argument(
	'--skipBlank',
	'-s',
	action='store_true',
	default=False,
	help='Skips erasing SPI flash pages that would are not used in the program.'
)

args = parser.parse_args()

# Does the Intel Hex file exist?
if not os.path.exists(args.IntelHexFile):
	print('Provided Intel Hex file does not exist')
	exit()

# If --port argument is not provided, try to autoconnect or ask the user to select from a list
fakeUart = UART()
if args.port is None:
	args.port = fakeUart.InteractivePortChooser()
	if args.port is None:
		exit()
else:
	availPorts = fakeUart.GetAvailableSerialPorts()
	if args.port not in availPorts:
		print('Invalid port')
		exit()

# Load the chip configuration data from implementation directory
chipImplDir = os.path.join(repoRootDir, 'implementations/asic', args.chip)
if not os.path.exists(chipImplDir):
	print(f'Error: Chip implementation directory not found: {chipImplDir}')
	exit()

print(f'Loading chip configuration from: {chipImplDir}')
chip = Chip.CreateFromChipRootDirectory(chipImplDir)

if chip is None:
	print(f'Error: Failed to load chip configuration from {chipImplDir}')
	print('Please check that the following files exist:')
	print(f'  - {chipImplDir}/config/MemoryMap.json')
	print(f'  - {chipImplDir}/config/ChipConfig.json')
	print(f'  - {chipImplDir}/config/BoardConfig.json')
	exit(1)

activeBoard = None

# if --board argument is not provided, try to autoselect or ask the user to select from a list
if args.board is None:
	activeBoard = chip.InteractiveBoardChooser()
	if activeBoard is None:
		exit()
elif args.board is not None:
	activeBoard = chip.GetBoard(args.board)
	if activeBoard is None:
		print('Invalid board')
		exit()
else:
	print('Must specify --board to use the interactive board chooser')
	exit()

# Connect to the forth interpreter via UART
forth = ForthInterface()
if forth.Connect(chip, activeBoard, args.port, desiredBootMode='ROM') != True:
	print('Unable to connect')
	exit()
if forth.ChangeBaudrateUsingHFXT(activeBoard.ProgrammingBaudrate) != True:
	print('Unable to change baudrate to', activeBoard.ProgrammingBaudrate)
	exit()
print('Connected to', forth.ActiveChip.Name, 'board', forth.ActiveBoard.Name, 'on', forth.uart.Port, 'at', forth.uart.Baudrate, 'baud')

# Program the flash memory
flash = ProgramFlash()
flash.Setup(forth)

# Check if input file is RCF or Intel Hex
if args.IntelHexFile.endswith('.rcf'):
	print('Detected RCF file, writing directly to flash')
	if flash.WriteRcfFile(args.IntelHexFile, verify=args.verify, showProgressBar=True) != True:
		print('')
		print('ERROR: unable to write RCF to flash memory')
		exit()
else:
	if flash.WriteProgram(args.IntelHexFile, verify=args.verify, skipBlank=args.skipBlank, showProgressBar=True) != True:
		print('')
		print('ERROR: unable to write program to flash memory')
		exit()
	
# Reset the chip in SPI Flash mode
forth.SetBootToSpiFlash()
forth.AssertReset()
sleep(25e-3)
forth.DeassertReset()

print('Successfully wrote program to flash memory')
