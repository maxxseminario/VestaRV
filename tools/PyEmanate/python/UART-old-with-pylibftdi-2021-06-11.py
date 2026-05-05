import serial	# pyserial (install with pip install pyserial)
from serial.tools import list_ports	# also pyserial
import platform
from time import sleep
from datetime import datetime

def GetOS():
	'''
	Returns: str (A string corresponding to the operating system, including if running on WSL for Windows)
	'''
	uname = platform.uname()
	system = uname.system.lower()
	release = uname.release.lower()
	
	# Which OS?
	if 'windows' in system:
		return 'windows'
	elif 'linux' in system:
		# Is this a raspberry pi?
		try:
			with open('/sys/firmware/devicetree/base/model', 'r') as f:
				s = f.read().lower()
				if 'raspberry pi' in s:
					return 'rpi'
		except:
			pass
		# Is this Linux proper or WSL?
		if 'microsoft' in release:
			return 'wsl'
		else:
			return 'linux'
	return None

if GetOS() not in [None, 'windows', 'rpi']:
	import pylibftdi	# install with pip install pylibftdi

class UART():
	# Public variables
	NewlineWrite = '\n'
	NewlineRead = '\n'
	Encoding = 'latin-1'	# Also could be 'ascii'
	
	# Private variables
	ser = None
	readbuffer = b''
	using_pylibftdi = False
	thisOS = None
	libftdi_timeout = None
	
	
	# Properties
	@property
	def IsOpen(self):
		if self.using_pylibftdi:
			return not self.ser.closed
		else:
			return self.ser.is_open
		
	@property
	def Connected(self):
		return self.IsOpen
	
	@property
	def Port(self):
		if self.using_pylibftdi:
			return self.ser.device_index
		else:
			return self.ser.port
	
	@property
	def Baudrate(self):
		return self.ser.baudrate
	
	@Baudrate.setter
	def Baudrate(self, newBaudrate):
		self.ser.baudrate = newBaudrate
	
	@property
	def Timeout(self):
		if self.using_pylibftdi:
			return self.libftdi_timeout
		else:
			return self.ser.timeout
	
	@Timeout.setter
	def Timeout(self, timeout):
		if self.using_pylibftdi:
			self.libftdi_timeout = timeout
		else:
			self.ser.timeout = timeout
	
	
	
	
	# Constructor
	def __init__(self, port=None, baudrate=None, autoconnect=False):
		self.thisOS = GetOS()
		self.ResetSerial()
		
		if port is not None:
			self.Open(port=port, baudrate=baudrate)
			return
		if autoconnect is True:
			self.Open(port=None, baudrate=baudrate)
			return
		return
	
	
	
	
	# Methods
	def ResetSerial(self):
		if (self.thisOS == 'linux'):
			# Use pylibftdi
			self.using_pylibftdi = True
			self.ser = pylibftdi.SerialDevice(lazy_open=True)
		elif self.thisOS in ['windows', 'wsl', 'rpi']:
			# Use pyserial
			self.using_pylibftdi = False
			self.ser = serial.Serial()
		else:
			raise Exception('This operating system is not supported')
		return
	
	def GetAvailableSerialPorts(self, removeConnectedPorts:bool=True, removeBlankPorts:bool=True):
		'''
		Returns a list of all available serial ports
		
		@removeConnectedPorts: Do not list ports that have already been opened
		@removeBlankPorts: Do not list ports that have no VID or PID information
		
		Returns: list[str] (A list of strings representing the available serial ports)
		'''
		if self.using_pylibftdi:
			from pylibftdi import Driver
			dev_list = []
			for device in Driver().list_devices():
				dev_info = map(lambda x: x, device)
				vendor, product, serialNum = dev_info
				dev_list.append('%s:%s:%s' % (vendor, product, serialNum))
			return dev_list
		else:
			allPorts = list_ports.comports()
			ports = []
			for port in allPorts:
				# Check if the port has a PID or VID
				if removeBlankPorts and (self.thisOS != 'wsl'):
					if (port.pid is None) and (port.vid is None):
						continue
				
				# Check if the port is already open or not
				if removeConnectedPorts or (self.thisOS == 'wsl'):
					try:
						dummyser = serial.Serial(port.device)
						dummyser.close()
					except serial.SerialException as e:
						if str(e).startswith('[Errno 5]'):
							# Serial port does not exist
							continue
						elif str(e).startswith('[Errno 13]'):
							# Serial port is already connected to by someone else
							continue
						elif str(e).startswith('[Errno 2]'):
							# This serial port doesn't even exist in the /dev/ttyS* folder, for whatever reason
							continue
						else:
							continue	# This re-raises the exception
				
				ports.append(port.device)
			return ports
	
	def InteractivePortChooser(self, removeConnectedPorts:bool=True, removeBlankPorts:bool=True):
		if self.using_pylibftdi:
			availPorts = self.GetAvailableSerialPorts()
			if len(availPorts) == 0:
				print('No serial ports available')
				return None
			elif len(availPorts) == 1:
				return 0
			else:
				for i, port in enumerate(availPorts):
					print('  ' + str(i) + ': ' + port)
				desiredPortKey = input('Desired port: ')
				try:
					desiredPortNum = int(desiredPortKey)
				except:
					print('Invalid port')
					return None
				if not (0 <= desiredPortNum < len(availPorts)):
					print('Invalid port')
					return None
				return desiredPortNum
		else:
			availPorts = self.GetAvailableSerialPorts(removeConnectedPorts=removeConnectedPorts, removeBlankPorts=removeBlankPorts)
			if len(availPorts) == 0:
				print('No serial ports are available')
				return None
			elif len(availPorts) == 1:
				return availPorts[0]
			else:
				availPortsDict = dict()
				for p in availPorts:
					if type(p) != str:
						continue
					if len(p) <= 0:
						continue
					i = len(p) - 1
					numstr = ''
					while p[i].isdigit():
						numstr = p[i] + numstr
						if i == 0:
							break
						i -= 1
					if len(numstr) <= 0:
						continue
					availPortsDict[int(numstr)] = p
				print('Available ports:')
				nums = []
				for k in availPortsDict:
					nums.append(k)
				nums.sort()
				for n in nums:
					print('  ' + str(n) + ': ' + availPortsDict[n])
				desiredPortKey = input('Desired port: ')
				desiredPortNum = None
				try:
					desiredPortNum = int(desiredPortKey)
				except:
					print('Invalid port')
					return None
				if desiredPortNum not in availPortsDict:
					print('Invalid port')
					return None
				return availPortsDict[desiredPortNum]
	
	def Open(self, port, baudrate:int, timeout=250e-3, initialRTS=None, initialDTR=None):
		'''
		Opens the serial port to establish a connection.
		No parity, one stop bit, 8-bit byte size.
		
		@port: The desired serial port to connect to
		@baudrate: The baud in bits per second
		@timeout: When reading/peeking, if the criteria to finish reading has not been met when the timeout has elapsed since the last received byte, the read/peek operation will be canceled.
		@initialDTR: int, the value DTR will have when the port is opened (0 or 1)
		@initialRTS:
		
		@Returns: bool (connection success state)
		'''
		# Error checking
		if baudrate < 0:
			print('baudrate must be > 0')
			return False
		if initialRTS not in [None, 0, 1]:
			print('initialRTS must be None, 0, or 1')
			return False
		if initialDTR not in [None, 0, 1]:
			print('initialDTR must be None, 0, or 1')
			return False
		
		self.readbuffer = b''
		
		# Is the port already open?
		if self.ser is not None:
			# Are the connection parameters identical to the open port?
			if (self.Port == port) and (self.Baudrate == baudrate):
				# Port parameters are identical, do nothing
				return True
			else:
				# Port parameters need to be changed, change them
				self.Close()
		
		# If no port is provided, use the interactive port chooser
		if port is None:
			port = self.InteractivePortChooser()
		if port is None:
			return False
		
		# Try to open the port
		if self.using_pylibftdi:
			if type(port) != int:
				print('port must be an int when using pylibftdi')
				return False
			
			try:
				ser = pylibftdi.SerialDevice(mode='b')
				if initialDTR is not None:
					ser.dtr = initialDTR
				if initialRTS is not None:
					ser.rts = initialRTS
				ser.device_index = port
				ser.baudrate = baudrate
				self.Timeout = timeout
				
				ser.open()
			except:
				print('Could not open serial port')
				self.ResetSerial()
				return False
		else:
			# Use pyserial
			if type(port) != str:
				print('port must be a string when using pyserial')
				return False
			
			try:
				ser = serial.Serial()
				if initialDTR is not None:
					ser.dtr = initialDTR
				if initialRTS is not None:
					ser.rts = initialRTS
				ser.port = port
				ser.baudrate = baudrate
				ser.parity = serial.PARITY_NONE
				ser.stopbits = serial.STOPBITS_ONE
				ser.bytesize = serial.EIGHTBITS
				ser.timeout = timeout
				
				ser.open()
			except serial.SerialException as e:
				print('Could not open serial port:', e)
				self.ResetSerial()
				return False
		
		self.ser = ser
		sleep(50e-3)
		return True
	
	def Close(self):
		'''
		Closes the serial port
		'''
		self.ser.close()
		self.ResetSerial()
		self.readbuffer = b''
		return
	
	def Write(self, data):
		'''
		Writes data to the serial port. Blocks until the data has been fully transmitted.
		
		@data: The data to write to the serial port. May be of type bytes, str, int, or float
		
		Returns: int (the number of bytes written)
		'''
		if (self.IsOpen == False) or (self.ser is None):
			return None
			
		# Convert numbers to a string
		if (type(data) == int) or (type(data) == float):
			data = str(data)
		
		# If data is a str type (Unicode), convert it to a bytes string
		if type(data) == str:
			data = data.encode(self.Encoding)
		
		if type(data) == bytes:
			return self.ser.write(data)
		else:
			return None
	
	def WriteLine(self, w):
		'''
		Writes data to the serial port with a line ending suffix (determined by NewlineWrite). Blocks until the data has been fully transmitted.
		
		@data: The data to write to the serial port. May be of type bytes, str, int, or float
		
		Returns: int (the number of bytes written)
		'''
		newline = self.NewlineWrite.encode(self.Encoding)
		count = self.Write(w)
		if count is None:
			return None
		count += self.Write(newline)
		return count
	
	def WriteBytes(self, w):
		if type(w) != bytes:
			return None
		return self.Write(w)
	
	def PeekBytes(self, numbytes=None):
		'''
		Reads bytes from the serial port without removing them from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@numbytes: the number of bytes to read. If None, reads the entire current buffer without waiting for any new data.
		
		Returns: bytes (the bytes read), or None (if timeout elapsed)
		'''
		if (self.IsOpen == False) or (self.ser is None):
			return None
		
		if self.using_pylibftdi:
			# Get all of the currently available bytes in the pylibftdi library and put them in the read buffer
			while True:
				t1 = datetime.now()
				c = self.ser.read(1)
				if len(c) < 1:
					break
				self.readbuffer += c
				tdiff = datetime.now() - t1
				if tdiff.total_seconds() > 5e-4:
					break
			
			# If numbytes is unspecified, simply return everything currently in the read buffer
			if numbytes is None:
				numbytes = len(self.readbuffer)
			
			# If the required number of bytes already exists in the read buffer, just read them from the read buffer
			if numbytes <= len(self.readbuffer):
				return self.readbuffer[:numbytes]
			
			# Wait for the proper number of bytes to be received. If the timeout elapses before the next byte is received, return None
			while len(self.readbuffer) < numbytes:
				# Start the timer
				t1 = datetime.now()
				
				# Wait for a new byte
				while True:
					c = self.ser.read(1)
					if len(c) > 0:
						self.readbuffer += c
						break
					tdiff = datetime.now() - t1
					if tdiff.total_seconds() > self.libftdi_timeout:
						return None
			
			return self.readbuffer[:numbytes]
		else:
			# If numbytes is unspecified, simply return everything currently in the read buffer
			if numbytes is None:
				try:
					numbytes = self.ser.in_waiting + len(self.readbuffer)
				except serial.serialutil.SerialException:
					self.Close()
					return None
			
			# If the required number of bytes already exists in the read buffer, just read them from the read buffer
			if numbytes <= len(self.readbuffer):
				return self.readbuffer[:numbytes]
			
			# Wait for the proper number of bytes to be received. If the timeout elapses before the next byte is received, return None
			while len(self.readbuffer) < numbytes:
				try:
					s = self.ser.read(1)
				except serial.serialutil.SerialException:
					self.Close()
				if len(s) <= 0:
					return None
				self.readbuffer += s
			
			return self.readbuffer[:numbytes]
	
	def Peek(self, numchars=None):
		'''
		Reads a string from the serial port without removing it from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@numchars: the number of chars to read. If None, reads the entire current buffer without waiting for any new data.
		
		Returns: str (the chars read), or None (if timeout elapsed)
		'''
		r = self.PeekBytes(numchars)
		if r is None:
			return None
		r = r.decode(self.Encoding)
		return r
	
	def ReadBytes(self, numbytes=None):
		'''
		Reads bytes from the serial port and removes them from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@numbytes: the number of bytes to read. If None, reads the entire current buffer without waiting for any new data.
		
		Returns: bytes (the bytes read), or None (if timeout elapsed)
		'''
		r = self.PeekBytes(numbytes)
		if r is None:
			return None
		self.readbuffer = self.readbuffer[len(r):]
		return r
	
	def Read(self, numchars=None):
		'''
		Reads a string from the serial port and removes it from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@numchars: the number of chars to read. If None, reads the entire current buffer without waiting for any new data.
		
		Returns: str (the chars read), or None (if timeout elapsed)
		'''
		r = self.ReadBytes(numchars)
		if r is None:
			return None
		r = r.decode(self.Encoding)
		return r
		
	def PeekBytesUntil(self, terminator_bytes:bytes, maxSize=None, stripTerminator=False):
		'''
		Reads bytes from the serial port until the terminator is found without removing them from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@terminator_bytes: The terminator. Reads from the serial port until the terminator is found.
		@maxSize: The maximum number of bytes to read. If there are maxSize bytes in the serial terminal and no terminator has been found, returns the read buffer up to maxSize. If maxSize is None, there is no limit.
		@stripTerminator: If true, removes the terminator from the end of the return bytes.
		
		Returns: bytes (the bytes read), or None (if timeout elapsed)
		'''
		if type(terminator_bytes) != bytes:
			return None
		if len(terminator_bytes) <= 0:
			return None
		
		# Get all initially available bytes into the read buffer
		r = self.PeekBytes()
		if r is None:
			return None
		currentBytesInReadBuffer = len(self.readbuffer)
		
		# Wait until the terminator is in the read buffer
		while terminator_bytes not in self.readbuffer:
			if maxSize is not None:
				if currentBytesInReadBuffer >= maxSize:
					return self.PeekBytes(currentBytesInReadBuffer)
			if self.PeekBytes(currentBytesInReadBuffer + 1) is None:
				return None
			currentBytesInReadBuffer = len(self.readbuffer)
		
		# Get the bytes up to the terminator
		r = self.readbuffer[:self.readbuffer.index(terminator_bytes)]
		if not stripTerminator:
			r += terminator_bytes
		return r
	
	def PeekUntil(self, terminator, maxSize=None, stripTerminator=False):
		'''
		Reads a string from the serial port until the terminator is found without removing it from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@terminator_bytes: The terminator. Reads from the serial port until the terminator is found.
		@maxSize: The maximum number of bytes to read. If there are maxSize bytes in the serial terminal and no terminator has been found, returns the read buffer up to maxSize. If maxSize is None, there is no limit.
		@stripTerminator: If true, removes the terminator from the end of the return string.
		
		Returns: str (the chars read), or None (if timeout elapsed)
		'''
		if type(terminator) != str:
			return None
		terminator_bytes = terminator.encode(self.Encoding)
		r = self.PeekBytesUntil(terminator_bytes, maxSize=maxSize, stripTerminator=stripTerminator)
		if r is None:
			return None
		r = r.decode(self.Encoding)
		return r
	
	def ReadBytesUntil(self, terminator_bytes, maxSize=None, stripTerminator=False):
		'''
		Reads bytes from the serial port until the terminator is found and removes them from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@terminator_bytes: The terminator. Reads from the serial port until the terminator is found.
		@maxSize: The maximum number of bytes to read. If there are maxSize bytes in the serial terminal and no terminator has been found, returns the read buffer up to maxSize. If maxSize is None, there is no limit.
		@stripTerminator: If true, removes the terminator from the end of the return bytes.
		
		Returns: bytes (the bytes read), or None (if timeout elapsed)
		'''
		r = self.PeekBytesUntil(terminator_bytes, maxSize=maxSize, stripTerminator=stripTerminator)
		if r is None:
			return None
		removeBytesCount = len(r)
		if stripTerminator:
			removeBytesCount += len(terminator_bytes)
		self.readbuffer = self.readbuffer[removeBytesCount:]
		return r
	
	def ReadUntil(self, terminator, maxSize=None, stripTerminator=False):
		'''
		Reads a string from the serial port until the terminator is found and removes it from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@terminator_bytes: The terminator. Reads from the serial port until the terminator is found.
		@maxSize: The maximum number of bytes to read. If there are maxSize bytes in the serial terminal and no terminator has been found, returns the read buffer up to maxSize. If maxSize is None, there is no limit.
		@stripTerminator: If true, removes the terminator from the end of the return string.
		
		Returns: str (the chars read), or None (if timeout elapsed)
		'''
		if type(terminator) != str:
			return None
		terminator_bytes = terminator.encode(self.Encoding)
		r = self.ReadBytesUntil(terminator_bytes, maxSize=maxSize, stripTerminator=stripTerminator)
		if r is None:
			return None
		r = r.decode(self.Encoding)
		return r
	
	def PeekLine(self, maxSize=None, stripNewline=False):
		'''
		Reads bytes from the serial port until a line ending is found (determined by NewlineRead) and removes them from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@maxSize: The maximum number of bytes to read. If there are maxSize bytes in the serial terminal and no line ending has been found, returns the read buffer up to maxSize. If maxSize is None, there is no limit.
		@stripNewline: If true, removes the line ending from the end of the return bytes.
		
		Returns: str (the chars read), or None (if timeout elapsed)
		'''
		r = self.PeekUntil(terminator=self.NewlineRead, maxSize=maxSize, stripTerminator=stripNewline)
		if r is None:
			return None
		return r
	
	def ReadLine(self, maxSize=None, stripNewline=False):
		'''
		Reads a string from the serial port until a line ending is found (determined by NewlineRead) and removes it from the read buffer. If it takes longer than the timeout to read any byte from the serial port, returns None.
		
		@maxSize: The maximum number of bytes to read. If there are maxSize bytes in the serial terminal and no line ending has been found, returns the read buffer up to maxSize. If maxSize is None, there is no limit.
		@stripNewline: If true, removes the line ending from the end of the return string.
		
		Returns: str (the chars read), or None (if timeout elapsed)
		'''
		r = self.ReadUntil(terminator=self.NewlineRead, maxSize=maxSize, stripTerminator=stripNewline)
		if r is None:
			return None
		return r
	
	def FlushReadBuffer(self):
		'''
		Removes all data from the read buffer
		'''
		if (self.IsOpen == False) or (self.ser is None):
			return
		if self.using_pylibftdi:
			self.ReadBytes()
		else:
			self.ser.reset_input_buffer()
		self.readbuffer = b''
		return
	
	def FlushWriteBuffer(self):
		'''
		Removes all data from the write buffer
		'''
		if (self.IsOpen == False) or (self.ser is None):
			return
		if self.using_pylibftdi:
			pass
		else:
			self.ser.reset_output_buffer()
		return
	
	def FlushBuffers(self):
		'''
		Removes all data from the read and write buffers
		'''
		self.FlushReadBuffer()
		self.FlushWriteBuffer()
		return
	
	def SetFtdiPin(self, pinName:str, polarity):
		if self.IsOpen != True:
			return None
		if type(polarity) == bool:
			polarity = int(polarity)
		if type(polarity) != int:
			return False
		if (polarity < 0) or (polarity > 1):
			return False
		pinName = pinName.lower()
		if pinName == 'dtr':
			# Data Terminal Ready
			self.ser.dtr = polarity
			return True
		elif pinName == 'rts':
			# Request To Send
			self.ser.rts = polarity
			return True
		return None
	
	def GetFtdiPin(self, pinName:str):
		if self.IsOpen != True:
			return None
		pinName = pinName.lower()
		if pinName == 'dtr':
			# Data Terminal Ready
			return int(self.ser.dtr)
		elif pinName == 'rts':
			# Request To Send
			return int(self.ser.rts)
		elif pinName == 'cts':
			# Clear To Send
			return int(self.ser.cts)
		elif pinName == 'dsr':
			# Data Set Ready
			return int(self.ser.dsr)
		elif pinName == 'ri':
			# Ring Indicator
			return int(self.ser.ri)
		elif pinName == 'cd':
			# Carrier Detect
			return int(self.ser.cd)
		return None
		