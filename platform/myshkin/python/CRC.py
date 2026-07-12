#!/usr/bin/env python3

def Reflect(data, numbits):
	reflection = 0
	for i in range(numbits):
		if (data & 0x1) > 0:
			reflection |= 1 << ((numbits - 1) - i)
		data >>= 1
	return reflection

def ComputeCRC(datalist, crcsize:int, polynomial:int, init_crc:int=0, final_xor:int=0, reflectData:bool=False, reflectOutput:bool=False):
	# See https://barrgroup.com/Embedded-Systems/How-To/CRC-Calculation-C-Code
	topbit = 1 << (crcsize - 1)
	mask = 0
	for i in range(crcsize):
		mask |= 1 << i
	polynomial &= mask

	crc = init_crc
	for b in datalist:
		if reflectData:
			b = Reflect(b, 8)
		crc ^= b << (crcsize - 8)
		for i in range(8):
			if (crc & topbit) > 0:
				crc = ((crc << 1) & mask) ^ polynomial
			else:
				crc = ((crc << 1) & mask)
	crc ^= final_xor
	crc &= mask

	if reflectOutput:
		crc = Reflect(crc, crcsize)

	return crc

'''
hexstr = 'CAFEBABE'
bytestr = [int(hexstr[i*2:(i*2)+2], 16) for i in range(len(hexstr) // 2)]


for b in bytestr:
	print(hex(b)[2:].upper(), end='')
print('')

crc = ComputeCRC(bytestr, crcsize=16, polynomial=0xC867, init_crc=0xFFFF, final_xor=0x0000, reflectData=False, reflectOutput=False)
print('CRC:', hex(crc))
'''

if __name__ == '__main__':
	import binascii
	from intelhex import IntelHex
	import argparse
	import os
	
	parser = argparse.ArgumentParser()

	parser.add_argument(
		'HexFile',
		metavar='HexFile',
		help='Path to Intel hex file containing the program')

	parser.add_argument(
		'RAMStart',
		type=str,
		help='Memory location of the beginning of the RAM (in bytes)')

	parser.add_argument(
		'RAMLength',
		type=str,
		help='Length of the RAM (in bytes)')

	args = parser.parse_args()

	# Get the RAM start address
	RamStart = None
	if args.RAMStart.lower().startswith('0x'):
		RamStart = int(args.RAMStart[2:], 16)
	else:
		RamStart = int(args.RAMStart)

	# Get the RAM length
	RamLength = None
	if args.RAMLength.lower().startswith('0x'):
		RamLength = int(args.RAMLength[2:], 16)
	else:
		RamLength = int(args.RAMLength)

	# Compute the RAM end address
	RamEnd = RamStart + RamLength

	# Parse the hex file
	print('Using hex file', os.path.abspath(args.HexFile))
	h = IntelHex(args.HexFile)


	hex_str = h.tobinstr(start=RamStart, size=RamLength)
	crc_bin = binascii.crc_hqx(hex_str, 0x0000)

	print('CRC (binascii) = 0x' + hex(crc_bin)[2:].upper())

	# Compute the CRC using CRC16_CDMA2000
	data = [h[addr] for addr in range(RamStart, RamEnd)]
	crc = ComputeCRC(data, 16, 0xC857, init_crc=0xFFFF, final_xor=0x0000, reflectData=False, reflectOutput=False)

	print('CRC16_CDMA2000 = 0x' + hex(crc)[2:].upper())