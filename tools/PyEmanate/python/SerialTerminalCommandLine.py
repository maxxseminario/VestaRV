#!/usr/bin/env python3

import argparse

from UART import UART

try:
	import msvcrt

	def key_pressed():
		return msvcrt.kbhit()
	
	def read_key():
		key = msvcrt.getch()

		try:
			result = str(key, encoding="utf8")
		except:
			result = key
		
		return result

except:

	try:
		import sys
		import select
		import tty
		import termios
		import atexit

		def key_pressed():
			return select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], [])

		def read_key():
			return sys.stdin.read(1)

		def restore_settings():
			termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)


		atexit.register(restore_settings)
		old_settings = termios.tcgetattr(sys.stdin)

		tty.setcbreak(sys.stdin.fileno())
	except:
		print("Can't deal with your keyboard!")
		

if __name__ == "__main__":
	# Get the arguments
	parser = argparse.ArgumentParser()
	
	parser.add_argument(
		'--port',
		'-p',
		type=str,
		default=None,
		nargs=1,
		help='The name of the serial port to use')

	parser.add_argument(
		'--baudrate',
		'-b',
		type=int,
		default=None,
		nargs=1,
		help='The baudrate of the UART. If this argument is not provided, the baudrate defaults to 115200')
	
	parser.add_argument(
		'--noEcho',
		'-n',
		default=False,
		action='store_true',
		help='Use this if you do not want the serial terminal to print the keys you type back into the command line. This is useful if the device you have connected to already echos your keystrokes.')

	args = parser.parse_args()
	
	if args.port is not None:
		args.port = args.port[0]
	
	if args.baudrate is None:
		args.baudrate = 115200
	else:
		args.baudrate = args.baudrate[0]
	
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
	
	# Connect to the chip via UART
	uart = UART()
	if not uart.Open(args.port, baudrate=args.baudrate, initialRTS=0, initialDTR=0):
		print('Could not connect to port', uart.Port)
		exit(-1)
	
	print('Connected to port', uart.Port, 'at', uart.Baudrate, 'baud')
	print('Press Esc to exit, press Ctrl+E to toggle echo, press Ctrl+R to toggle reset, press Ctrl+B to toggle boot mode')
	
	escapeKey = chr(27)
	CtrlE = chr(5)
	CtrlR = chr(18)
	CtrlB = chr(2)
	
	resetPin = 'rts'
	bootPin = 'dtr'
	if uart.thisOS == 'rpi':
		resetPin = 'rpiboard11'
		bootPin = 'rpiboard12'
	
	echo = not args.noEcho
	while True:
		# Check for any key presses
		if key_pressed():
			c = read_key()
			if c == escapeKey:
				# Escape was pressed, exit
				break
			elif c == CtrlE:
				# Toggle echo
				echo = not echo
			elif c == CtrlR:
				# Toggle reset
				if uart.GetFtdiPin(resetPin):
					uart.SetFtdiPin(resetPin, 0)
				else:
					uart.SetFtdiPin(resetPin, 1)
			elif c == CtrlB:
				# Toggle boot mode
				if uart.GetFtdiPin(bootPin):
					uart.SetFtdiPin(bootPin, 0)
				else:
					uart.SetFtdiPin(bootPin, 1)
			elif c == '\r':
				# A Windows return key was pressed, print a '\r\n' rather than just an '\n'
				if not uart.WriteLine(''):
					print('')
					print('Connection lost, exiting...')
				if echo:
					print('', flush=True)
			else:
				if not uart.Write(c):
					print('')
					print('Connection lost, exiting...')
				if echo:
					print(c, end='', flush=True)
		
		# Check for any new data from the chip
		r = uart.Read()
		if r is None:
			print('')
			print('Connection lost, exiting...')
			break
		if len(r) > 0:
			print(r, end='', flush=True)
	
	# Exit
	print('')