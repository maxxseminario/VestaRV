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


# ---------------------------------------------------------------------------
# Fallback: per-word POKE using the Forth `!` opcode (42).
# ---------------------------------------------------------------------------
#
# This method completely avoids the `mw` binary-stream protocol. Every 32-bit
# word is written by a single ASCII Forth line:
#
#     <value> <address> !
#
# The chip parses the line through its normal command loop, stores one word,
# and emits its " ok" / echo as usual. No `$` handshake, no long binary RX
# burst, no CRC -- bytes are always ASCII and there is ample time between
# successive lines for the ROM UART polling to keep up.
#
# Drawback: ~25 UART chars per 4 bytes vs. ~1 byte per byte for `mw`, so it
# is roughly 6x slower on the wire AND each line adds parser/echo overhead
# on the chip. For a few-hundred-byte blinky it's still sub-second; for a
# 30 KB program it would be ~30s, which is fine for development.
#
# Requires: data length be a multiple of 4, and startAddress be word aligned.
# ---------------------------------------------------------------------------

def _pokeOneWord(forth, addr, word, interLineSleep, logger=None):
	"""Send a single `<val> <addr> !` Forth line. Returns:
	   True   on (apparent) success (no '?' seen in drain)
	   False  if chip replied with '?'  (parse error; byte likely dropped)
	   None   on transport failure.
	Does NOT abort; callers decide what to do.
	"""
	cmd = f'0x{word:08X} 0x{addr:08X} !'
	if forth.uart.WriteLine(cmd) is None:
		return None
	sleep(interLineSleep)
	try:
		leftover = forth.uart.ReadBytes()
	except Exception:
		leftover = b''
	if leftover and b'?' in leftover:
		if logger is not None:
			logger.note(f'poke parse error at 0x{addr:08x}: {leftover!r}')
		return False
	return True


def WriteMemoryBlockPoke(forth, startAddress, data, interLineSleep=10e-3,
						 showProgressBar=False, progressBar=None,
						 progressBase=0, logger=None):
	"""Upload `data` via one `<val> <addr> !` Forth line per 32-bit word.

	Sends every word regardless of per-line errors. Returns a dict:
	    { 'ok': True/None,
	      'errors': [list of (addr, reason) tuples for '?' replies] }
	The caller is expected to run a per-word verify+retry pass afterwards;
	a '?' almost always means a UART byte was dropped and exactly one word
	is wrong -- re-poking that word fixes it.
	"""
	result = {'ok': True, 'errors': []}
	if len(data) == 0:
		return result
	if forth.uart.IsOpen is not True:
		result['ok'] = None
		return result
	if startAddress % 4 != 0:
		print(f'ERROR: poke startAddress 0x{startAddress:08x} is not word aligned')
		result['ok'] = None
		return result
	if len(data) % 4 != 0:
		pad = 4 - (len(data) % 4)
		data = data + (b'\xff' * pad)

	forth.uart.FlushBuffers()
	oldTimeout = forth.uart.Timeout
	forth.uart.Timeout = 0.05

	for wordIndex in range(0, len(data), 4):
		w = (data[wordIndex + 0] <<  0 |
			 data[wordIndex + 1] <<  8 |
			 data[wordIndex + 2] << 16 |
			 data[wordIndex + 3] << 24)
		addr = startAddress + wordIndex

		r = _pokeOneWord(forth, addr, w, interLineSleep, logger=logger)
		if r is None:
			print(f'ERROR: transport failure writing 0x{addr:08x}')
			result['ok'] = None
			forth.uart.Timeout = oldTimeout
			return result
		if r is False:
			# '?' reply; very likely one dropped byte. Record and keep going.
			result['errors'].append((addr, 'parse_error'))

		if showProgressBar and progressBar is not None:
			progressBar.update(progressBase + wordIndex + 4)

	forth.uart.Timeout = oldTimeout
	return result


def _readOneWordMr(forth, addr):
	"""Read one 32-bit word at `addr` via the chip's `mr` (CRC-checked) path.
	Returns the word value (int) on success, None on failure.

	On failure we MUST drain the UART thoroughly. Otherwise stale bytes from
	the failed transfer (a partial payload, an unread CRC, an echoed Forth
	prompt, ...) will be picked up by the NEXT `mr` as its payload, returning
	plausible-looking but completely bogus data on every subsequent word.
	Without this drain, verify never converges: each pass re-pokes the
	wrongly-flagged word, then re-reads garbage again next time.
	"""
	buf = forth.ReadMemoryBlock(addr, 4)
	if buf is None or buf is False or len(buf) < 4:
		# Hard drain: read everything that's queued, wait briefly for any
		# trailing bytes the chip is still transmitting, then read again.
		try:
			oldTimeout = forth.uart.Timeout
			forth.uart.Timeout = 0.05
			for _ in range(3):
				junk = forth.uart.ReadBytes()
				if not junk:
					break
				sleep(0.01)
			forth.uart.Timeout = oldTimeout
			forth.uart.FlushBuffers()
		except Exception:
			try:
				forth.uart.FlushBuffers()
			except Exception:
				pass
		return None
	return (buf[0] <<  0 | buf[1] <<  8 | buf[2] << 16 | buf[3] << 24)


def VerifyAndRepairBlock(forth, startAddress, data,
						 interLineSleep=10e-3,
						 knownErrors=None,
						 maxRepairPasses=3,
						 logger=None,
						 progressBar=None,
						 progressBase=0,
						 showProgressBar=False):
	"""Per-word readback + repair.

	For each 32-bit word in `data`, read it back from the chip via `mr` and
	compare to the expected value. If any word mismatches (or is listed in
	`knownErrors`), re-poke it and re-read. Repeat up to `maxRepairPasses`
	times. Returns True if the whole block matches at the end, False if
	anything still mismatches.

	`knownErrors` is an optional iterable of addresses that the upload
	already flagged as suspicious (from '?' replies); they get unconditionally
	re-poked before the first readback pass, regardless of what is currently
	at that address.
	"""
	if len(data) % 4 != 0:
		pad = 4 - (len(data) % 4)
		data = data + (b'\xff' * pad)

	expected = {}
	for wordIndex in range(0, len(data), 4):
		w = (data[wordIndex + 0] <<  0 |
			 data[wordIndex + 1] <<  8 |
			 data[wordIndex + 2] << 16 |
			 data[wordIndex + 3] << 24)
		expected[startAddress + wordIndex] = w

	# First: re-poke any addresses the upload flagged as errored.
	if knownErrors:
		uniqErr = sorted(set(knownErrors))
		if logger is not None:
			logger.note(f'repair: re-poking {len(uniqErr)} upload-flagged '
						f'address(es) before verify')
		print(f'Re-poking {len(uniqErr)} upload-flagged word(s) before verify...')
		for a in uniqErr:
			if a in expected:
				_pokeOneWord(forth, a, expected[a], interLineSleep, logger=logger)

	attempt = 0
	prevMismatchCount = None
	noProgressStreak = 0
	# Hard ceiling so we can never loop literally forever in pathological
	# cases (chip dead, etc.). 64 passes over a few hundred words is still
	# only a few seconds of work.
	HARD_CEILING = max(maxRepairPasses * 8, 32)
	while True:
		mismatches = []
		readbackFailures = []
		# Walk every word, read-back, compare. A transient `mr` failure
		# (None) is treated as a mismatch -- it almost always means a UART
		# byte was dropped on the readback path, NOT that the RAM contents
		# are bad. Re-poking the word and re-reading it on the next pass
		# is much more reliable than aborting the whole verify.
		nWords = len(data) // 4
		for i, addr in enumerate(sorted(expected.keys())):
			got = _readOneWordMr(forth, addr)
			if got is None:
				if logger is not None:
					logger.note(f'verify: readback hiccup at 0x{addr:08x} '
								f'(attempt {attempt}); will retry')
				readbackFailures.append(addr)
				mismatches.append(addr)
			elif got != expected[addr]:
				mismatches.append(addr)
			if showProgressBar and progressBar is not None:
				progressBar.update(progressBase + (i + 1) * 4)
		if readbackFailures:
			print(f'  {len(readbackFailures)} readback hiccup(s) on '
				  f'attempt {attempt} (will retry)')

		if not mismatches:
			if logger is not None:
				logger.note(f'verify OK on attempt {attempt} '
							f'({nWords} words checked)')
			return True

		# Decide whether to keep going. We keep going as long as we are
		# making progress (mismatch count is strictly decreasing). Once we
		# stop making progress, we allow `maxRepairPasses` more no-progress
		# passes (the chip might just be having a bad UART moment) and only
		# THEN give up.
		if prevMismatchCount is not None and len(mismatches) >= prevMismatchCount:
			noProgressStreak += 1
		else:
			noProgressStreak = 0
		prevMismatchCount = len(mismatches)

		if noProgressStreak > maxRepairPasses or attempt >= HARD_CEILING:
			print(f'ERROR: {len(mismatches)} word(s) still mismatch after '
				  f'{attempt + 1} pass(es) (no progress for the last '
				  f'{noProgressStreak} pass(es)). First few:')
			for a in mismatches[:8]:
				got = _readOneWordMr(forth, a)
				print(f'  0x{a:08x}: expected 0x{expected[a]:08x}, '
					  f'read 0x{(got if got is not None else 0):08x}')
			if logger is not None:
				logger.note(f'verify FAILED: {len(mismatches)} mismatches '
							f'remain after {attempt + 1} passes')
			return False

		# Repair pass: re-poke each mismatching word.
		if logger is not None:
			logger.note(f'verify attempt {attempt}: {len(mismatches)} '
						f'mismatch(es); repairing')
		print(f'Verify pass {attempt}: {len(mismatches)} mismatch(es); '
			  f're-poking...')
		for a in mismatches:
			_pokeOneWord(forth, a, expected[a], interLineSleep, logger=logger)
		# Settle for a moment so any in-flight stale bytes finish arriving
		# before the next readback pass.
		sleep(0.02)
		try:
			forth.uart.FlushBuffers()
		except Exception:
			pass
		attempt += 1

	# Unreachable.


def VerifyMemoryBlock(forth, startAddress, data):
	"""Legacy bulk-mr verify (kept for API compat). Prefer
	VerifyAndRepairBlock for actual use."""
	readBack = forth.ReadMemoryBlock(startAddress, len(data))
	if readBack is None or readBack is False:
		print(f'ERROR: readback failed at 0x{startAddress:08x}')
		return False
	if bytes(readBack) != bytes(data):
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
	parser.add_argument('--method', choices=['mw', 'poke'], default='mw',
		help='Upload strategy. "mw" (default) uses the fast binary-stream '
			 '`mw` Forth opcode. "poke" writes one 32-bit word at a time '
			 'via `<val> <addr> !` Forth lines -- much slower but completely '
			 'bypasses the binary RX path and the `mw` CRC handshake, so it '
			 'is robust when the ROM UART drops bytes mid-stream.')
	parser.add_argument('--poke-delay', type=float, default=10e-3,
		help='Seconds to sleep between `!` lines when --method=poke '
			 '(default: 0.010).')
	parser.add_argument('--repair-passes', type=int, default=3,
		help='When --verify is set, number of per-word readback/repair '
			 'passes to run after the initial upload (default: 3). Each '
			 'pass reads every word via `mr` and re-pokes any that do '
			 'not match. Setting to 0 effectively makes --verify a '
			 'one-shot read-only check.')
	parser.add_argument('--strict-verify', action='store_true', default=False,
		help='If --verify fails after all repair passes, abort instead '
			 'of jumping to the entry point. Default behaviour is to '
			 'print a warning and jump anyway -- on a chip that is '
			 'actually running fine, verify failures are usually just '
			 'host-side UART hiccups on the readback path, not real RAM '
			 'corruption.')
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

	# Populate the list of available Forth functions on the chip. Connect()
	# does not do this by default, but ReadMemoryBlock() (used by verify) asserts
	# that 'mr' is present, so we need to query the chip now.
	if forth.UpdateAvailableFunctionsList() is None:
		print('Unable to query available Forth functions from chip')
		if logger: logger.close()
		sys.exit(1)
	if logger:
		logger.note(f'forth functions: {sorted(forth.ForthFunctions)}')

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
	# Collect any per-word errors (e.g. '?' replies from dropped bytes) from
	# the poke path so the verify/repair pass can re-poke those words.
	pokeErrorsByRun = {}  # (addr_run_start, run_len) -> [addr,...]
	for (addr, data) in runs:
		if bar is None:
			print(f'  writing 0x{addr:08x} .. 0x{addr + len(data):08x} '
				  f'({len(data)} bytes) via {args.method}')
		if logger:
			logger.note(f'{args.method} start addr=0x{addr:08x} len={len(data)}')
		if args.method == 'mw':
			ret = WriteMemoryBlock(forth, addr, data,
								   chunkSize=args.chunk_size,
								   interChunkSleep=args.chunk_delay)
			if ret is not True:
				if bar is not None:
					bar.finish()
				print(f'\nERROR: upload failed at 0x{addr:08x}')
				if logger:
					logger.note(f'{args.method} FAILED')
					logger.close()
				sys.exit(2)
		else:  # poke
			result = WriteMemoryBlockPoke(forth, addr, data,
										  interLineSleep=args.poke_delay,
										  showProgressBar=(bar is not None),
										  progressBar=bar,
										  progressBase=written,
										  logger=logger)
			if result['ok'] is None:
				if bar is not None:
					bar.finish()
				print(f'\nERROR: transport failure at 0x{addr:08x}')
				if logger:
					logger.note('poke TRANSPORT FAILED')
					logger.close()
				sys.exit(2)
			errs = [a for (a, _r) in result['errors']]
			if errs:
				msg = (f'  {len(errs)} word(s) flagged during upload '
					   f'(will be re-poked during verify): '
					   f'{", ".join(f"0x{a:08x}" for a in errs[:6])}'
					   + (' ...' if len(errs) > 6 else ''))
				print(msg)
				if logger:
					logger.note(f'poke errors in run 0x{addr:08x}: {errs}')
			pokeErrorsByRun[(addr, len(data))] = errs
		written += len(data)
		if bar is not None:
			bar.update(written)

	if bar is not None:
		bar.finish()

	# ---- optional verify (per-word readback + repair) ---------------------
	verifyFailed = False
	if args.verify:
		print('Verifying RAM contents (per-word readback + repair)...')
		if logger:
			logger.note('verify start (per-word readback + repair)')
		for (addr, data) in runs:
			knownErrors = pokeErrorsByRun.get((addr, len(data)), [])
			ok = VerifyAndRepairBlock(
				forth, addr, data,
				interLineSleep=args.poke_delay,
				knownErrors=knownErrors,
				maxRepairPasses=args.repair_passes,
				logger=logger)
			if ok is not True:
				verifyFailed = True
				print(f'WARNING: verification did not fully pass at '
					  f'0x{addr:08x}.')
				if logger:
					logger.note(f'verify FAILED at 0x{addr:08x}')
				if args.strict_verify:
					print('--strict-verify set; aborting instead of jumping.')
					if logger:
						logger.close()
					sys.exit(3)
		if not verifyFailed:
			print('Verify OK')
			if logger:
				logger.note('verify OK')
		else:
			print('NOTE: continuing to jump anyway. Most verify failures '
				  'are host-side UART hiccups on the readback path; if the '
				  'program does not run, re-flash with --strict-verify to '
				  'catch real RAM corruption, or raise --repair-passes.')
			if logger:
				logger.note('verify FAILED but jumping anyway '
							'(--strict-verify not set)')

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
