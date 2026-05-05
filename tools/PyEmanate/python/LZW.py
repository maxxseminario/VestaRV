#!/usr/bin/env python3

class LZW():

	NULL_CODE = -1
	CLEAR_CODE = 256
	FIRST_STRING = 257

	shifter = None
	bits = None
	output_bytes = None
	dst = None

	def Compress(self, src:bytes, maxbits:int=11, require_maxbits_prefix:bool=False):
		next_ = self.FIRST_STRING
		prefix = self.NULL_CODE
		self.bits = 0
		input_bytes = 0
		self.output_bytes = 0
		self.shifter = 0
		self.dst = b''

		if (maxbits < 9 or maxbits > 12):
			return None
		
		total_codes = 1 << maxbits

		# Initialize arrays to 0
		first_references = [0 for i in range(total_codes)]
		next_references = [0 for i in range(total_codes - 256)]
		terminators = [0 for i in range(total_codes - 256)]

		# The first byte in the output is the value of maxbits
		self.dst = bytes()
		if require_maxbits_prefix:
			self.dst = bytes([maxbits])

		for c in src:	# Converts the element in the bytes string to an int
			input_bytes += 1

			if prefix == self.NULL_CODE:
				prefix = c
				continue
				
			cti = first_references[prefix]	# Coding Table Index

			if cti != 0:	# If any longer strings are built on the current prefix...
				while True:
					if terminators[cti - 256] == c:	# Found a matching string. Just update the prefix to that string and continue without outputting anything
						prefix = cti
						break
					elif next_references[cti - 256] == 0:	# This string did not match nte new character and there aren't any more, so we'll add a new string and point to it with next_reference
						next_references[cti - 256] = next_
						cti = 0
						break
					else:
						cti = next_references[cti - 256]	# There are more possible matches to check, so loop back
			else:	# No longer strings are based on the current prefix, so now the current prefix plus the new byte will be the next string
				first_references[prefix] = next_
			
			# If "cti" is zero, we could not simply extend our "prefix" to a longer string because we did not find a dictionary match, so we send the symbol representing the current "prefix" and add the new string to the dictionary. Since the current byte "c" was not included in the prefix, that now becomes our new prefix
			if cti == 0:
				self.WRITE_CODE(prefix, next_)	# Write symbol for current prefix (0 to next_ - 1)
				terminators[next_ - 256] = c	# Newly created string has current byte as the terminator
				prefix = c	# Current byte also becomes new prefix for next string

				# This is where we bump the next string index and decide whether to clear the dictionary and start over. The triggers for that are either the dictionary is full or we've been outputting too many bytes and decide to cut our losses before the symbols get any larger. Note that for the dictionary full case we do NOT send the CLEAR_CODE because the decoder knows about this and we don't want to be redundant.
				next_ += 1
				if (next_ == total_codes) or (self.output_bytes > (8 + input_bytes + (input_bytes >> 4))):
					if next_ < total_codes:
						self.WRITE_CODE(self.CLEAR_CODE, next_)
					
					# Clear the dictionary and reset the byte counters. Basically everything starts over except that we keep the last pending "prefix" (which, of course, was never sent)
					first_references = [0 for i in range(total_codes)]
					next_references = [0 for i in range(total_codes - 256)]
					terminators = [0 for i in range(total_codes - 256)]
					input_bytes = 0
					self.output_bytes = 0
					next_ = self.FIRST_STRING
		
		# Done with the input, so if anything else is received the pending prefix must still be sent

		if prefix != self.NULL_CODE:
			self.WRITE_CODE(prefix, next_)
			next_ += 1
			if next == total_codes:	# Watch for clearing to the first string to stay in step with the decoder! (this was actually a corner-case bug that did not trigger often)
				next_ = self.FIRST_STRING
		
		self.WRITE_CODE(next_, next_)	# The maximum possible code is always reserved for our END_CODE

		if self.bits != 0:
			self.dst += bytes([self.shifter & 0xFF])
		
		return self.dst
	
	def Decompress(self, src:bytes, maxbits:int=11, require_maxbits_prefix:bool=False):
		read_byte = None
		next_ = self.FIRST_STRING
		prefix = self.CLEAR_CODE,
		bits = 0
		total_codes = None
		shifter = 0
		srcIndex = 0
		dst = b''

		# Read the first byte, which is the value of maxbits
		if require_maxbits_prefix:
			maxbits = src[0]
			srcIndex += 1

		total_codes = 1 << maxbits
		reverse_buffer = [0 for i in range(total_codes - 256)]
		prefixes = [0 for i in range(total_codes - 256)]
		terminators = [0 for i in range(total_codes - 256)]

		# This is the main loop where we read input symbols. The values range from 0 to the code value of the "next" string in the dictionary (although the actual "next" code cannot be used yet, and so we reserve that code for the END_CODE). Note that receiving an EOF from the input stream is actually an error because we should have gotten the END_CODE first.
		while True:
			if next_ < 1024:
				if next_ < 512:
					code_bits = 8
				else:
					code_bits = 9
			else:
				if next_ < 2048:
					code_bits = 10
				else:
					code_bits = 11
			extras = (1 << (code_bits + 1)) - next_ - 1

			while True:
				read_byte = src[srcIndex]
				srcIndex += 1

				shifter |= read_byte << bits
				bits += 8
				if bits >= code_bits:
					break
			
			# First, assume the code will fit in the minimum number of required bits
			code = shifter & ((1 << code_bits) - 1)
			shifter >>= code_bits
			bits -= code_bits

			# If code >= extras, then we need to read another bit to calculate the real code (this is the "adjusted binary" part)
			if code >= extras:
				if bits == 0:
					read_byte = src[srcIndex]
					srcIndex += 1

					shifter = read_byte
					bits = 8
				code = (code << 1) - extras + (shifter & 0x1)
				shifter >>= 1
				bits -= 1
			
			if code == next_:	# Sending the maximum code is reserved for the end of the file
				break
			elif code == self.CLEAR_CODE:	# Otherwise, check for a CLEAR_CODE condition to start over early
				next_ = self.FIRST_STRING
			elif prefix == self.CLEAR_CODE:	# This only happens at the first symbol with is always sent literally and becomes our initial prefix
				dst += bytes([code & 0xFF])
				next_ += 1
			else:	# Otherwise we have a valid prefix so we step through the string from end to beginning storing the bytes in the "reverse_buffer", and then we send them out in the proper order. One corner-case we have to handle here is that the string might be the same one that is actually being defined now (code == next-1). Also, the first 256 entries of "terminators" and "prefixes" are fixed and not allocated, so that messes things up a bit.
				if code == (next_ - 1):
					cti = prefix
				else:
					cti = code
				rbp_index = 0
				
				while True:
					if cti < 256:
						reverse_buffer[rbp_index] = cti
					else:
						reverse_buffer[rbp_index] = terminators[cti - 256]	# Step backwards thorugh string...
					rbp_index += 1
					if cti < 256:
						cti = self.NULL_CODE
					else:
						cti = prefixes[cti - 256]
					if cti == self.NULL_CODE:
						break
				
				rbp_index -= 1
				c = reverse_buffer[rbp_index]	# The first byte in this string is the terminator for the last string, which is the one that we'll create a new dictionary entry for this time

				while True:	# send string in corrected order (except for the terminator which we don't know yet)
					dst += bytes([reverse_buffer[rbp_index]])
					rbp_index -= 1
					if rbp_index <= -1:
						break
				
				if code == (next_ - 1):
					dst += bytes([c])
				
				prefixes[next_ - 1 - 256] = prefix	# Now update the next dictionary entry with the new string (but we're always one behind, so it's not the string just sent)
				terminators[next_ - 1 - 256] = c

				next_ += 1
				if next_ == total_codes:
					next_ = self.FIRST_STRING
			
			prefix = code	# The code we just received becomes the prefix for the next dictionary string entry (which we'll create once we find out the terminator)

		return dst
	
	def WRITE_CODE(self, code, maxcode):
		if maxcode < 1024:
			if maxcode < 512:
				code_bits = 8
			else:
				code_bits = 9
		else:
			if maxcode < 2048:
				code_bits = 10
			else:
				code_bits = 11
		extras = (1 << (code_bits + 1)) - maxcode - 1
		if code < extras:
			self.shifter |= code << self.bits
			self.bits += code_bits
		else:
			self.shifter |= ((code + extras) >> 1) << self.bits
			self.bits += code_bits
			self.shifter |= ((code + extras) & 0x01) << self.bits
			self.bits += 1
		while True:
			self.dst += bytes([self.shifter & 0xFF])
			self.shifter >>= 8
			self.output_bytes += 1
			self.bits -= 8
			if self.bits < 8:
				break
		return


if __name__ == "__main__":
	import os, argparse

	parser = argparse.ArgumentParser()

	parser.add_argument(
		'inputFile',
		help='The input file to the LZW compressor/decompressor')
	
	parser.add_argument(
		'outputFile',
		help='The output file from the LZW compressor/decompressor')
	
	parser.add_argument(
		'--compress',
		'-c',
		action='store_true',
		default=False,
		help='Compress flag, indicates a compression operation')
	
	parser.add_argument(
		'--decompress',
		'-d',
		action='store_true',
		default=False,
		help='Decompress flag, indicates a decompression operation')
	
	parser.add_argument(
		'--maxbits',
		'-m',
		type=int,
		default=11,
		help='Maximum number of bits per code')
	
	parser.add_argument(
		'--test',
		action='store_true',
		default=False)
	
	args = parser.parse_args()
	
	if args.test:
		import random
		from progressbar import ProgressBar, Percentage, Bar, ETA	# progressbar2 (install with pip install progressbar2)
		pbar = ProgressBar(widgets=['Programming: ', Percentage(), ' ', Bar(), ' ', ETA()])
		l = LZW()
		numTests = 10000
		lengthMin = 256
		lengthMax = 65536
		compressionRatioSum = 0
		for i in pbar(range(numTests)):
			length = random.randrange(lengthMin, lengthMax)
			uncompressed = bytes(random.getrandbits(8) for _ in range(length))
			compressed = l.Compress(uncompressed)
			decompressed = l.Decompress(compressed)
			if uncompressed != decompressed:
				print('FAIL')
				exit(0)
			compressionRatioSum += len(compressed) / len(uncompressed)
		averageCompressionRatio = compressionRatioSum / numTests
		print('TEST PASSED')
		print('Average Compression Ratio =', '{:02}%'.format(averageCompressionRatio * 100))
		exit(0)

	inputFile = args.inputFile
	if not os.path.isfile(inputFile):
		print(inputFile, 'is not a valid file')
		exit(-1)
	outputFile = args.outputFile
	if not os.path.isdir(os.path.dirname(os.path.abspath(outputFile))):
		print(outputFile, 'has no parent directory')
		exit(-1)
	
	with open(inputFile, 'rb') as f:
		inputData = f.read()
	
	l = LZW()
	if args.compress and args.decompress:
		print('Please select either compression or decompression, not both')
		exit(-1)
	elif args.compress:
		outputData = l.Compress(inputData)
		with open(outputFile, 'wb') as f:
			f.write(outputData)
	elif args.decompress:
		outputData = l.Decompress(inputData)
		with open(outputFile, 'wb') as f:
			f.write(outputData)
	else:
		print('Please select either compression or decompression. Exiting...')
		exit(-1)
	exit(0)
