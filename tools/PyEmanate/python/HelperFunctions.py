from datetime import datetime

def fmthex(unum:int, minDigits=4):
	if unum < 0:
		return None
	fmtstr = '{:0' + str(minDigits) + 'x}'
	return '0x' + fmtstr.format(unum).upper()

def fmtint(num:int, minDigits=2):
	fmtstr = '{:0' + str(minDigits) + '}'
	return fmtstr.format(num)

def fmtbin(unum:int, minDigits=16, separatedBits=None):
	if unum < 0:
		return None
	fmtstr = '{:0' + str(minDigits) + 'b}'
	s = fmtstr.format(unum).upper()
	totalBits = len(s)
	if separatedBits in [4, 8, 16]:
		for i in reversed(range(separatedBits, totalBits, separatedBits)):
			s = s[:i] + ' ' + s[i:]
	return '0b' + s

def strToInt(s:str):
	value = None
	try:
		value = int(s)
	except:
		return None
	return value

def hexToUint(hexStr:str):
	if hexStr.startswith('0x'):
		hexStr = hexStr[2:]
	value = None
	try:
		value = int(hexStr, 16)
	except:
		return None
	return value

def binToUint(binStr:str):
	if binStr.startswith('0b'):
		binStr = binStr[2:]
	value = None
	try:
		value = int(binStr, 2)
	except:
		return None
	return value

def isPowerOf2(num):
	''' Returns True if num is a power of 2, returns False if not'''
	if type(num) != int:
		raise TypeException('num must be an int')
	if num < 0:
		raise ValueException('num must be >= 0')
	return num != 0 and ((num & (num - 1)) == 0)

def crc_reflect(data, numbits):
	reflection = 0
	for i in range(numbits):
		if (data & 0x1) > 0:
			reflection |= 1 << ((numbits - 1) - i)
		data >>= 1
	return reflection

def computeCRC(datalist, crcsize:int, polynomial:int, init_crc:int=0, final_xor:int=0, reflectData:bool=False, reflectOutput:bool=False):
	# See https://barrgroup.com/Embedded-Systems/How-To/CRC-Calculation-C-Code
	topbit = 1 << (crcsize - 1)
	mask = 0
	for i in range(crcsize):
		mask |= 1 << i
	polynomial &= mask

	crc = init_crc
	for b in datalist:
		if reflectData:
			b = crc_reflect(b, 8)
		crc ^= b << (crcsize - 8)
		for i in range(8):
			if (crc & topbit) > 0:
				crc = ((crc << 1) & mask) ^ polynomial
			else:
				crc = ((crc << 1) & mask)
	crc ^= final_xor
	crc &= mask

	if reflectOutput:
		crc = crc_reflect(crc, crcsize)

	return crc

def compute_CRC16_CDMA2000(data:bytes):
	return computeCRC(data, 16, 0xC857, init_crc=0xFFFF, final_xor=0x0000, reflectData=False, reflectOutput=False)

def neg_int_to_unsigned_int(data:int, bits:int):
	if data >= 0:
		return data
	if bits < 2:
		raise Exception('Cannot have a signed integer with fewer than two bits')
	if -data > 2**(bits - 1):
		raise Exception('Integer overflow')
	return 2**bits + data

def get_string_timestamp(includeSeconds=False, dt=None):
	if dt is None:
		d = datetime.now()
	else:
		d = dt
	s = '{:04d}'.format(d.year) + '-' + '{:02d}'.format(d.month) + '-' + '{:02d}'.format(d.day)  + '-' + '{:02d}'.format(d.hour) + '{:02d}'.format(d.minute)
	if includeSeconds:
		s += '-' + '{:02d}'.format(d.second)
	return s

def get_timestamp_from_string(dtStr:str):
	split = dtStr.split('-')
	if not (len(split) == 4 or len(split) == 5):
		return None
	year = strToInt(split[0])
	month = strToInt(split[1])
	day = strToInt(split[2])
	hour = strToInt(split[3][:2])
	minute = strToInt(split[3][2:4])
	if len(split) == 5:
		second = strToInt(split[4])
		return datetime(year, month, day, hour, minute, second)
	return datetime(year, month, day, hour, minute)

def checkDieID(dieID):
	if type(dieID) != str or (len(dieID) != 3 and len(dieID) != 5):
		return False
	if hexToUint(dieID) is None:
		return False
	return True

def swapWordBytesInArray(b:bytes):
	if len(b) % 4 != 0:
		return None
	bs = [0 for i in range(len(b))]
	for i in range(len(b)):
		bs[i] = b[((i // 4) * 4) + 3 - (i % 4)]
	return bytes(bs)

def decodeBytes(b:bytes):
	return b.decode('latin-1')

def NormalizeFatfsPath(path:str, includeDefaultDriveNumber:bool=False):
	# Remove extra /
	path = path.replace('\\', '/').upper()
	while '//' in path:
		path = path.replace('//', '/')
	if ':' in path and path[1] != ':':
		return None

	# Strip the drive string
	driveStr = '0:'
	if len(path) >= 2 and path[1] == ':':
		driveStr = path[:2]
		path = path[2:]
	
	# Add root if it is missing
	if not path.startswith('/'):
		path = '/' + path
	
	# Trim the / off the tail directory if it is there
	split = path.split('/')
	if len(split) >= 3 and path.endswith('/'):
		path = path[:-1]
	if includeDefaultDriveNumber or driveStr != '0:':
		path = driveStr + path
	
	return path

def GetFatfsDirectoryNameFromPath(path:str):
	path = NormalizeFatfsPath(path)
	split = path.split('/')
	if len(split) == 2 and split[1] == '':
		return '/'
	return split[-1]

def CheckFatfsName(name:str, allowFileExtension:bool=True):
	split = name.split('.')
	if len(split) == 2:
		if not allowFileExtension:
			return False
		if len(split[1]) < 1 or len(split[1]) > 3:
			return False
		if not split[1].isalnum():
			return False
	elif len(split) != 1:
		return False
	if len(split[0]) < 1 or len(split[0]) > 8:
		return False
	if not split[0].isalnum():
		return False
	return True

def CheckFatfsPath(path:str, allowFileExtension:bool=True):
	path = NormalizeFatfsPath(path, includeDefaultDriveNumber=True)
	if len(path) > 100:
		return False
	driveNum = strToInt(path[0])
	if driveNum is None or driveNum < 0 or driveNum > 9:
		return False
	if path[1] != ':':
		return False
	if path[2] != '/':
		return False
	path = path[3:]
	if len(path) == 0:
		return True
	split = path.split('/')
	for i, s in enumerate(split):
		if not CheckFatfsName(s, allowFileExtension=((i + 1 == len(split)) and allowFileExtension)):
			return False
	return True
