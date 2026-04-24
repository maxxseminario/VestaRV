#!/usr/bin/env python3
"""
forthram.py - Upload a program to RAM over the Forth UART and jump to 0x8200.

This is an analog of forthprog.py that completely bypasses the SPI flash boot
path. Instead it:

  1. Connects to the ROM-resident Forth interpreter over UART (ROM boot mode).
  2. Uploads the program bytes directly into RAM using the Forth `mw`
	 (memory write) word (opcode 94).
  3. Issues a `0x8200 call0` Forth command (opcode 59) so the CPU jumps to
	 address 0x8200 in RAM and executes the freshly-uploaded program.

This is useful on silicon where the SPI flash boot path is broken (e.g. the
AT45DB021E Power-Up / CS-framing bug in start.S on myshkin-2025-11), because
no boot-from-flash step is ever performed.

Accepts either:
	*.rcf  -- a RAM-command-format file as emitted by the linker tooling
			  (layout: stream of 32-bit words; each command is one of
			   0x10adbeef <start> <end> <word0>...<wordN>  (load segment),
			   0xdeadbeef <start> <end> <fill_word>		(fill segment),
			   0xcafebabe								 (execute).)
	*.hex  -- an Intel-Hex file.

The final jump target is hard-coded to 0x8200 per user request; it is NOT
derived from the RCF's 0xcafebabe terminator or from the Intel-Hex EIP field.
"""

import sys
import os
import argparse
import time
from time import sleep

thisScriptDir = os.path.dirname(os.path.abspath(__file__))
repoRootDir = os.path.abspath(thisScriptDir + '/../../')
sys.path.append(repoRootDir + '/tools/chip_programmer/python')

from UART import UART
from Chip import Chip
from ForthInterface import ForthInterface
from HelperFunctions import compute_CRC16_CDMA2000

try:
	import progressbar  # optional
	HAVE_PROGRESSBAR = True
except Exception:
	HAVE_PROGRESSBAR = False


# ---------------------------------------------------------------------------
# User-requested fixed entry point.
# ---------------------------------------------------------------------------
ENTRY_ADDRESS = 0x8200


# ---------------------------------------------------------------------------
# UART I/O logger
# ---------------------------------------------------------------------------
# Hooks pyserial's underlying `write()` and `read()` so every byte that
# crosses the wire in EITHER direction is captured, regardless of which
# higher-level helper (Connect, ChangeBaudrateUsingHFXT, mw, call0, ...)
# produced it. Output is a human-readable transcript: direction, relative
# timestamp, ASCII representation, and a raw hex side-channel.
# ---------------------------------------------------------------------------

class _UartLogger:
	def __init__(self, logPath):
		self.path = logPath
		self.fp = open(logPath, 'w', buffering=1)  # line-buffered
		self.t0 = time.time()
		self.tx_accum = bytearray()
		self.rx_accum = bytearray()
		self.last_dir = None
		self.last_ts = self.t0
		# Coalesce consecutive same-direction activity that happens within
		# this many seconds into a single log line. Keeps the transcript
		# readable while still showing ordering.
		self.coalesce_window = 0.020

	def _flush_dir(self, direction):
		if direction == 'TX' and self.tx_accum:
			self._emit('TX', bytes(self.tx_accum), self.last_ts)
			self.tx_accum = bytearray()
		elif direction == 'RX' and self.rx_accum:
			self._emit('RX', bytes(self.rx_accum), self.last_ts)
			self.rx_accum = bytearray()

	def _emit(self, direction, data, ts):
		rel = ts - self.t0
		# Show printable ASCII, escape control chars.
		ascii_repr = ''.join(
			(chr(b) if 32 <= b < 127 else
			 '\\n' if b == 0x0A else
			 '\\r' if b == 0x0D else
			 '\\t' if b == 0x09 else
			 f'\\x{b:02x}')
			for b in data
		)
		hex_repr = data.hex()
		self.fp.write(
			f'[{rel:10.4f}s] {direction} {len(data):4d}B  {ascii_repr!r}\n'
		)
		if len(data) <= 64:
			self.fp.write(f'             hex: {hex_repr}\n')
		else:
			self.fp.write(f'             hex: {hex_repr[:128]}...[truncated {len(data)}B]\n')

	def _now(self):
		return time.time()

	def log_tx(self, data):
		if not data:
			return
		now = self._now()
		if self.last_dir == 'RX':
			self._flush_dir('RX')
		if self.tx_accum and (now - self.last_ts) > self.coalesce_window:
			self._flush_dir('TX')
		if not self.tx_accum:
			self.last_ts = now
		self.tx_accum.extend(data)
		self.last_dir = 'TX'

	def log_rx(self, data):
		if not data:
			return
		now = self._now()
		if self.last_dir == 'TX':
			self._flush_dir('TX')
		if self.rx_accum and (now - self.last_ts) > self.coalesce_window:
			self._flush_dir('RX')
		if not self.rx_accum:
			self.last_ts = now
		self.rx_accum.extend(data)
		self.last_dir = 'RX'

	def note(self, msg):
		"""Emit a free-form annotation (e.g. phase markers)."""
		self._flush_dir('TX')
		self._flush_dir('RX')
		rel = self._now() - self.t0
		self.fp.write(f'[{rel:10.4f}s] -- {msg}\n')

	def close(self):
		self._flush_dir('TX')
		self._flush_dir('RX')
		try:
			self.fp.close()
		except Exception:
			pass


def install_uart_logger(uart, logger):
	"""Wrap the pyserial object inside `uart` so every byte is logged."""
	ser = uart.ser
	if ser is None:
		raise RuntimeError('UART has no underlying serial object to wrap')

	orig_write = ser.write
	orig_read = ser.read

	def logged_write(data):
		try:
			logger.log_tx(bytes(data))
		except Exception:
			pass
		return orig_write(data)

	def logged_read(n=1):
		r = orig_read(n)
		try:
			if r:
				logger.log_rx(bytes(r))
		except Exception:
			pass
		return r

	ser.write = logged_write
	ser.read = logged_read
	# Stash for later restore / access from the app code.
	uart._forthram_logger = logger


# ---------------------------------------------------------------------------
# File parsing helpers
# ---------------------------------------------------------------------------

def _parse_rcf_words(rcfPath):
	"""Return the list of 32-bit words from a .rcf file (one binary string per line)."""
	words = []
	with open(rcfPath, 'r') as f:
		for line in f:
			line = line.strip()
			if len(line) != 32:
				continue
			if any(c not in '01' for c in line):
				continue
			words.append(int(line, 2))
	return words


def _rcf_to_byte_image(rcfPath):
	"""
	Walk an RCF command stream and return a dict {byte_address: byte_value}.

	Only 0x10adbeef (load segment) and 0xdeadbeef (fill segment) commands
	actually place bytes in memory; 0xcafebabe terminates the stream.
	"""
	words = _parse_rcf_words(rcfPath)
	image = {}
	i = 0
	while i < len(words):
		cmd = words[i]; i += 1

		if cmd == 0x10adbeef:
			# load segment: start, end, word0 .. wordN (end exclusive)
			if i + 1 >= len(words):
				raise ValueError('Truncated loadSegment header in RCF')
			start = words[i]; i += 1
			end   = words[i]; i += 1
			if end < start or ((end - start) % 4) != 0:
				raise ValueError(f'Bad loadSegment span: start=0x{start:08x} end=0x{end:08x}')
			n = (end - start) // 4
			if i + n > len(words):
				raise ValueError('Truncated loadSegment payload in RCF')
			for j in range(n):
				w = words[i + j]
				addr = start + 4 * j
				image[addr + 0] = (w >>  0) & 0xFF
				image[addr + 1] = (w >>  8) & 0xFF
				image[addr + 2] = (w >> 16) & 0xFF
				image[addr + 3] = (w >> 24) & 0xFF
			i += n

		elif cmd == 0xdeadbeef:
			# fill segment: start, end, fill_word
			if i + 2 >= len(words):
				raise ValueError('Truncated eraseSegment header in RCF')
			start = words[i]; i += 1
			end   = words[i]; i += 1
			fill  = words[i]; i += 1
			if end < start or ((end - start) % 4) != 0:
				raise ValueError(f'Bad eraseSegment span: start=0x{start:08x} end=0x{end:08x}')
			for a in range(start, end, 4):
				image[a + 0] = (fill >>  0) & 0xFF
				image[a + 1] = (fill >>  8) & 0xFF
				image[a + 2] = (fill >> 16) & 0xFF
				image[a + 3] = (fill >> 24) & 0xFF

		elif cmd == 0xcafebabe:
			break

		else:
			raise ValueError(f'Unknown RCF command 0x{cmd:08x} at word index {i-1}')

	return image


def _intel_hex_to_byte_image(hexPath):
	"""Return a dict {byte_address: byte_value} from an Intel-Hex file."""
	from intelhex import IntelHex
	ihex = IntelHex(hexPath)
	image = {}
	for (start, end) in ihex.segments():  # end exclusive
		for a in range(start, end):
			image[a] = ihex[a] & 0xFF
	return image


def _image_to_contiguous_runs(image):
	"""
	Collapse a {byte_address: byte_value} dict into a list of
	[(start_address, bytes), ...] for every maximal contiguous run.
	"""
	if not image:
		return []
	addrs = sorted(image.keys())
	runs = []
	runStart = addrs[0]
	runBytes = bytearray([image[runStart]])
	prev = runStart
	for a in addrs[1:]:
		if a == prev + 1:
			runBytes.append(image[a])
		else:
			runs.append((runStart, bytes(runBytes)))
			runStart = a
			runBytes = bytearray([image[a]])
		prev = a
	runs.append((runStart, bytes(runBytes)))
	return runs


# ---------------------------------------------------------------------------
# Forth memory write via the `mw` opcode (94)
# ---------------------------------------------------------------------------
#
# On-chip protocol (see memoryWriteFunc in software/bootrom/src/rv4th.c):
#
#   host -> chip:  "1 <length> <start_address> mw\n"   (bin_payload=1)
#   chip -> host:  "$"                                 (ready handshake)
#   host -> chip:  <length> raw bytes                  (LSByte ordering: byte
#                                                       at offset i goes to
#                                                       address start+i)
#   chip -> host:  4-char hex CRC16-CDMA2000 of payload
#
# The ROM UART has NO receive FIFO (see software/bootrom/src/uart.c
# uartx_getc). Two bytes arriving between polls at 115200 baud cause byte
# loss. We therefore pace the TX in small chunks, exactly as WriteFlashPage
# does after commit e8c816d.
# ---------------------------------------------------------------------------

def WriteMemoryBlock(forth, startAddress, data, chunkSize=8, interChunkSleep=3e-3):
	"""Upload `data` bytes into RAM starting at `startAddress` using `mw`.

	Returns True on success (CRC matches), False on CRC mismatch, None on
	transport failure.
	"""
	if len(data) == 0:
		return True
	if forth.uart.IsOpen is not True:
		return None

	forth.uart.FlushBuffers()

	calcCrc = compute_CRC16_CDMA2000(data)

	# Forth signature: ( bin_payload length start_address -- )
	cmd = f'1 {len(data)} {startAddress} mw'
	if forth.uart.WriteLine(cmd) is None:
		print(f'ERROR: could not send mw command for 0x{startAddress:08x}')
		return None

	# Wait for the '$' ready handshake.
	oldTimeout = forth.uart.Timeout
	forth.uart.Timeout = 2.0
	r = forth.uart.ReadUntil('$')
	forth.uart.Timeout = oldTimeout
	if r is None:
		print(f'ERROR: no $ handshake from mw at 0x{startAddress:08x}')
		return None

	# Send the payload paced to survive the ROM UART's polling-only RX path.
	# The chip's memoryWriteFunc busy-waits on uart_getchar() with no FIFO;
	# if two bytes land between polls the first is lost and the chip never
	# emits the terminating CRC. Default pacing is small + generous.
	for off in range(0, len(data), chunkSize):
		forth.uart.WriteBytes(data[off:off + chunkSize])
		try:
			forth.uart.ser.flush()
		except Exception:
			pass
		sleep(interChunkSleep)

	# Receive the 4-char hex CRC. Allow plenty of slack -- even with a stuck
	# chip we want to surface something useful to the user.
	forth.uart.Timeout = 10.0
	crcStr = forth.uart.Read(4)
	forth.uart.Timeout = oldTimeout
	if crcStr is None:
		# Dump whatever (if anything) DID arrive so the user can tell whether
		# a byte was lost, the chip is echoing a '?' (Forth parse error), or
		# the UART is simply dead.
		forth.uart.Timeout = 0.25
		leftover = forth.uart.ReadBytes()
		forth.uart.Timeout = oldTimeout
		print(f'ERROR: no CRC reply from mw at 0x{startAddress:08x} '
			  f'(sent {len(data)} bytes, expected 4 hex chars back).')
		if leftover:
			try:
				print(f'       RX buffer after timeout ({len(leftover)} bytes): '
					  f'{leftover!r}')
			except Exception:
				print(f'       RX buffer after timeout: {leftover}')
		else:
			print('       RX buffer is empty -- chip is likely stuck in '
				  'uart_getchar() waiting for a dropped payload byte.')
		print('       Try lowering --chunk-size or raising --chunk-delay '
			  '(e.g. --chunk-size 4 --chunk-delay 0.005).')
		return None

	try:
		receivedCrc = int(crcStr, 16)
	except ValueError:
		print(f'ERROR: bad CRC string "{crcStr!r}" from mw at 0x{startAddress:08x}')
		return None

	if receivedCrc != calcCrc:
		print(f'ERROR: CRC mismatch at 0x{startAddress:08x}: '
			  f'expected 0x{calcCrc:04x}, got 0x{receivedCrc:04x}')
		return False

	return True


def VerifyMemoryBlock(forth, startAddress, data):
	"""Read back and compare against `data`. Returns True on match."""
	readBack = forth.ReadMemoryBlock(startAddress, len(data))
	if readBack is None or readBack is False:
		print(f'ERROR: readback failed at 0x{startAddress:08x}')
		return False
	if bytes(readBack) != bytes(data):
		# find first diff for diagnostics
		for i, (a, b) in enumerate(zip(readBack, data)):
			if a != b:
				print(f'ERROR: verify mismatch at 0x{startAddress + i:08x}: '
					  f'wrote 0x{b:02x}, read 0x{a:02x}')
				break
		return False
	return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
	parser = argparse.ArgumentParser(
		description='Upload a program to RAM via Forth and jump to 0x8200 '
					'(bypasses the SPI flash boot path entirely).')

	parser.add_argument(
		'ProgramFile',
		help='Path to an RCF (.rcf) or Intel-Hex (.hex) file')
	parser.add_argument('--port', '-p', type=str, default=None,
		help='The name of the serial port to use')
	parser.add_argument('--chip', '-c', type=str, default='myshkin-2025-11',
		help='The chip implementation name (e.g., myshkin-2025-11)')
	parser.add_argument('--board', '-b', type=str, default=None,
		help='The name of the circuit board being used')
	parser.add_argument('--verify', '-v', action='store_true', default=False,
		help='Read back RAM after write and compare against the upload')
	parser.add_argument('--no-jump', action='store_true', default=False,
		help='Skip the final call0 jump (useful for debugging the upload)')
	parser.add_argument('--entry', type=lambda s: int(s, 0),
		default=ENTRY_ADDRESS,
		help=f'Override the jump entry address (default: 0x{ENTRY_ADDRESS:08x})')
	parser.add_argument('--chunk-size', type=int, default=8,
		help='Bytes per TX chunk during RAM upload (default: 8). '
			 'Lower if you see "no CRC reply" errors.')
	parser.add_argument('--chunk-delay', type=float, default=3e-3,
		help='Seconds to sleep between TX chunks (default: 0.003). '
			 'Raise if you see "no CRC reply" errors.')
	parser.add_argument('--log', type=str, default=None,
		metavar='FILE',
		help='Write a full UART transcript (every byte TX/RX, with '
			 'timestamps) to FILE for debugging. Pass "auto" to write to '
			 './forthram-<timestamp>.log in the current directory.')

	args = parser.parse_args()

	# ---- file exists ------------------------------------------------------
	if not os.path.exists(args.ProgramFile):
		print('Provided program file does not exist:', args.ProgramFile)
		sys.exit(1)

	# ---- pick port --------------------------------------------------------
	fakeUart = UART()
	if args.port is None:
		args.port = fakeUart.InteractivePortChooser()
		if args.port is None:
			sys.exit(1)
	else:
		availPorts = fakeUart.GetAvailableSerialPorts()
		if args.port not in availPorts:
			print('Invalid port:', args.port)
			print('Available:', availPorts)
			sys.exit(1)

	# ---- load chip / board ------------------------------------------------
	chipImplDir = os.path.join(repoRootDir, 'implementations/asic', args.chip)
	if not os.path.exists(chipImplDir):
		print(f'Error: Chip implementation directory not found: {chipImplDir}')
		sys.exit(1)

	print(f'Loading chip configuration from: {chipImplDir}')
	chip = Chip.CreateFromChipRootDirectory(chipImplDir)
	if chip is None:
		print(f'Error: Failed to load chip configuration from {chipImplDir}')
		sys.exit(1)

	if args.board is None:
		activeBoard = chip.InteractiveBoardChooser()
		if activeBoard is None:
			sys.exit(1)
	else:
		activeBoard = chip.GetBoard(args.board)
		if activeBoard is None:
			print('Invalid board:', args.board)
			sys.exit(1)

	# ---- parse program file ----------------------------------------------
	lowerPath = args.ProgramFile.lower()
	if lowerPath.endswith('.rcf'):
		print('Parsing RCF file ...')
		image = _rcf_to_byte_image(args.ProgramFile)
	elif lowerPath.endswith('.hex'):
		print('Parsing Intel-Hex file ...')
		image = _intel_hex_to_byte_image(args.ProgramFile)
	else:
		print('ERROR: unknown file extension, expected .rcf or .hex')
		sys.exit(1)

	if not image:
		print('ERROR: program file contains no data')
		sys.exit(1)

	runs = _image_to_contiguous_runs(image)
	totalBytes = sum(len(d) for _, d in runs)
	lo = min(s for s, _ in runs)
	hi = max(s + len(d) for s, d in runs)
	print(f'Loaded {totalBytes} bytes across {len(runs)} segment(s), '
		  f'span 0x{lo:08x}..0x{hi:08x}')

	# Sanity: make sure the entry point lives inside what we are about to write.
	inAnyRun = any(s <= args.entry < s + len(d) for s, d in runs)
	if not inAnyRun:
		print(f'WARNING: entry point 0x{args.entry:08x} is NOT inside any '
			  f'loaded segment. The jump will run whatever happens to be in RAM '
			  f'at that address.')

	# ---- connect ----------------------------------------------------------
	forth = ForthInterface()
	if forth.Connect(chip, activeBoard, args.port, desiredBootMode='ROM') is not True:
		print('Unable to connect')
		sys.exit(1)

	# ---- optional UART transcript logger ---------------------------------
	logger = None
	if args.log is not None:
		logPath = args.log
		if logPath == 'auto':
			logPath = f'forthram-{time.strftime("%Y%m%d-%H%M%S")}.log'
		logger = _UartLogger(logPath)
		install_uart_logger(forth.uart, logger)
		logger.note(f'forthram.py transcript start; port={forth.uart.Port} '
					f'baud={forth.uart.Baudrate} chip={args.chip} '
					f'board={activeBoard.Name} file={args.ProgramFile} '
					f'entry=0x{args.entry:08x}')
		print(f'UART transcript -> {logPath}')

	if forth.ChangeBaudrateUsingHFXT(activeBoard.ProgrammingBaudrate) is not True:
		print('Unable to change baudrate to', activeBoard.ProgrammingBaudrate)
		if logger: logger.close()
		sys.exit(1)
	if logger:
		logger.note(f'baudrate now {forth.uart.Baudrate}')
	print('Connected to', forth.ActiveChip.Name, 'board', forth.ActiveBoard.Name,
		  'on', forth.uart.Port, 'at', forth.uart.Baudrate, 'baud')

	# ---- upload every run -------------------------------------------------
	bar = None
	if HAVE_PROGRESSBAR:
		bar = progressbar.ProgressBar(max_value=totalBytes,
			widgets=['Uploading ',
					 progressbar.Bar(), ' ',
					 progressbar.Percentage(), ' ',
					 progressbar.ETA()])
		bar.start()

	written = 0
	for (addr, data) in runs:
		if bar is None:
			print(f'  writing 0x{addr:08x} .. 0x{addr + len(data):08x} '
				  f'({len(data)} bytes)')
		if logger:
			logger.note(f'mw start addr=0x{addr:08x} len={len(data)}')
		ret = WriteMemoryBlock(forth, addr, data,
							   chunkSize=args.chunk_size,
							   interChunkSleep=args.chunk_delay)
		if ret is not True:
			if bar is not None:
				bar.finish()
			print(f'\nERROR: upload failed at 0x{addr:08x}')
			if logger:
				logger.note('mw FAILED')
				logger.close()
			sys.exit(2)
		written += len(data)
		if bar is not None:
			bar.update(written)

	if bar is not None:
		bar.finish()

	# ---- optional verify --------------------------------------------------
	if args.verify:
		print('Verifying RAM contents ...')
		if logger:
			logger.note('verify start')
		for (addr, data) in runs:
			if VerifyMemoryBlock(forth, addr, data) is not True:
				print(f'ERROR: verification failed at 0x{addr:08x}')
				if logger:
					logger.note('verify FAILED')
					logger.close()
				sys.exit(3)
		print('Verify OK')
		if logger:
			logger.note('verify OK')

	# ---- jump -------------------------------------------------------------
	if args.no_jump:
		print(f'--no-jump specified; program is in RAM but not executing. '
			  f'To jump manually, send `{args.entry} call0` over the Forth '
			  f'UART.')
		if logger:
			logger.note('no-jump; transcript end')
			logger.close()
		return

	print(f'Jumping to 0x{args.entry:08x} via `call0` ...')
	# Make sure the TX pipe is clean so the jump command is not corrupted.
	forth.uart.FlushBuffers()
	cmd = f'{args.entry} call0'
	if logger:
		logger.note(f'call0 jump to 0x{args.entry:08x}')
	if forth.uart.WriteLine(cmd) is None:
		print('ERROR: failed to send call0 command')
		if logger:
			logger.note('call0 send FAILED')
			logger.close()
		sys.exit(4)

	# call0 returns the function's return value onto the math stack. If the
	# uploaded program never returns (e.g. an infinite blinky loop), the
	# Forth interpreter simply never returns either. That's fine -- we just
	# leave the UART open so the user can observe any output the program
	# emits.
	print('Program launched. Forth is now running your code at '
		  f'0x{args.entry:08x}.')
	print('(If the program returns, the Forth interpreter will resume on '
		  'this UART.)')
	if logger:
		logger.note('launched; transcript end')
		logger.close()


if __name__ == '__main__':
	main()
