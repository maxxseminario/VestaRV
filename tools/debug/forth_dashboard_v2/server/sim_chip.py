"""SimChip -- an in-process, byte-level emulation of the rv4th REPL.

It is a *transport* (same read/write/close surface as RealSerial), so the whole
real stack -- SerialManager framing, memops, the REST layer -- is exercised
against it with no hardware.  It is deliberately honest: it echoes every byte,
prints "\\n>" after every line, and speaks the fw '$'/CRC/'Y' handshake, exactly
like the chip.  It does NOT know anything about REST endpoints.

A background thread runs a blocking REPL that mirrors rv4th.c:

    getLine():  print "\\n>", then read+echo chars until '\\n'/'\\r'
    execVM():   the opcode switch (subset that the dashboard actually drives)

fw and other words that pull raw bytes just call the blocking byte reader, so
multi-phase transactions work with no special casing.
"""

import json
import os
import threading
from typing import Dict, List, Optional

from server import forth

ASIC_NAME = "myshkin"
BANNER = ASIC_NAME + " rv4th-rom!"
CALL_RETURN = 0x0000002A          # canned return value for call0..call4
CLK_FREQ = {0: 24000000, 1: 24000000, 2: 32768, 3: 24000000}  # SMCLK/MCLK/LFXT/HFXT
# fw/fe mask their forth argument exactly like the ROM SPI driver
# (software/bootrom/src/flash_memory.c:104-121): the low 8 bits (256-byte page
# boundary) AND the high 8 bits (out of the 16 MiB range) are ignored.
FLASH_PAGE_MASK = 0x00FFFF00


class _Stopped(Exception):
    """Raised inside the REPL thread when close() is requested."""


class SimChip:
    """Transport that emulates the rv4th ROM Forth interpreter."""

    def __init__(self, registers_path: Optional[str] = None,
                 call_return: int = CALL_RETURN) -> None:
        self.description = "sim"
        self.baud = 115200
        self._call_return = call_return
        self._cond = threading.Condition()
        self._inbuf = bytearray()
        self._outbuf = bytearray()
        self._stop = threading.Event()

        self._mem = {}          # type: Dict[int, int]   word_addr -> u32
        self._flash = {}        # type: Dict[int, int]   byte_addr -> byte (0xFF erased)
        self._echo = True
        self._reset = False
        if registers_path:
            self._seed_from_registers(registers_path)

        self._thread = threading.Thread(
            target=self._repl, name="sim-chip", daemon=True)
        self._thread.start()

    # -- transport interface ----------------------------------------------

    def read(self, max_bytes: int, timeout: float) -> bytes:
        with self._cond:
            if not self._outbuf:
                self._cond.wait(timeout)
            if not self._outbuf:
                return b""
            out = bytes(self._outbuf[:max_bytes])
            del self._outbuf[:max_bytes]
            return out

    def write(self, data: bytes) -> None:
        with self._cond:
            self._inbuf.extend(data)
            self._cond.notify_all()

    def close(self) -> None:
        self._stop.set()
        with self._cond:
            self._cond.notify_all()
        if self._thread.is_alive():
            self._thread.join(timeout=2.0)

    # -- register seeding --------------------------------------------------

    def _seed_from_registers(self, path: str) -> None:
        try:
            with open(path) as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return
        for periph in (data.get("peripherals") or {}).values():
            for reg in (periph.get("registers") or {}).values():
                if "reset" in reg and "addr" in reg:
                    self._mem[int(reg["addr"]) & ~3] = forth.to_u32(int(reg["reset"]))

    # -- byte-level I/O for the REPL --------------------------------------

    def _get_byte(self) -> int:
        with self._cond:
            while not self._inbuf:
                if self._stop.is_set():
                    raise _Stopped()
                self._cond.wait(0.2)
            return self._inbuf.pop(0)

    def _emit(self, data: bytes) -> None:
        with self._cond:
            self._outbuf.extend(data)
            self._cond.notify_all()

    def _emit_str(self, text: str) -> None:
        self._emit(text.encode("latin-1"))

    # -- the REPL ----------------------------------------------------------

    def _repl(self) -> None:
        try:
            self._emit_str(BANNER + "\n")          # printStringln(banner)
            while not self._stop.is_set():
                self._emit_str("\n>")              # getLine() prompt
                line = self._read_line()
                self._reset = False
                self._execute(line)
        except _Stopped:
            return

    def _read_line(self) -> str:
        chars = []  # type: List[str]
        while True:
            byte = self._get_byte()
            if self._echo:
                self._emit(bytes([byte]))
            if byte in (10, 13):                   # '\n' or '\r'
                if byte == 13 and self._echo:
                    self._emit(b"\n")
                return "".join(chars)
            chars.append(chr(byte))

    # -- execution ---------------------------------------------------------

    def _execute(self, line: str) -> None:
        stack = []  # type: List[int]
        for token in line.split():
            if self._reset:
                return
            num = _parse_number(token)
            if num is not None:
                stack.append(forth.to_i32(num))
            else:
                self._word(token, stack)

    def _word(self, token: str, stack: List[int]) -> None:
        # Arithmetic / stack (handy for the interactive terminal)
        if token == "+":
            b = stack.pop(); a = stack.pop(); stack.append(forth.to_i32(a + b)); return
        if token == "-":
            b = stack.pop(); a = stack.pop(); stack.append(forth.to_i32(a - b)); return
        if token == "*":
            b = stack.pop(); a = stack.pop(); stack.append(forth.to_i32(a * b)); return
        if token == "neg":
            stack.append(forth.to_i32(-stack.pop())); return
        if token == "dup":
            stack.append(stack[-1]); return
        if token == "drop":
            stack.pop(); return
        if token == "swap":
            stack[-1], stack[-2] = stack[-2], stack[-1]; return
        # Output words
        if token == ".":
            self._emit_str("%d " % forth.to_i32(stack.pop())); return
        if token == "h.":
            self._emit_str("%08X " % forth.to_u32(stack.pop())); return
        if token == "hb.":
            self._emit_str("%02X " % (stack.pop() & 0xFF)); return
        if token == "s.":
            self._emit_str("".join("%d " % forth.to_i32(v) for v in stack)); return
        if token == "sh.":
            self._emit_str("".join("%08X " % forth.to_u32(v) for v in stack)); return
        # Memory words
        if token == "@":
            addr = stack.pop(); stack.append(self._read_word(addr)); return
        if token == "!":
            addr = stack.pop(); val = stack.pop(); self._write_word(addr, val); return
        if token == "sbi":
            addr = stack.pop(); bit = stack.pop()
            self._write_word(addr, self._read_word(addr) | (1 << bit)); return
        if token == "cbi":
            addr = stack.pop(); bit = stack.pop()
            self._write_word(addr, self._read_word(addr) & ~(1 << bit)); return
        if token == "mask":
            addr = stack.pop(); val = stack.pop(); posmask = stack.pop()
            cur = self._read_word(addr)
            self._write_word(addr, (cur & ~posmask) | (val & posmask)); return
        if token == "me":
            addr = stack.pop(); length = stack.pop(); self._mem_erase(addr, length); return
        if token == "mr":
            addr = stack.pop(); length = stack.pop(); mode = stack.pop()
            self._do_mr(mode, length, addr); return
        # Flash words
        if token == "fr":
            addr = stack.pop(); length = stack.pop(); binflag = stack.pop()
            self._do_fr(binflag, length, addr); return
        if token == "fe":
            page = stack.pop(); key = stack.pop()
            stack.append(1 if key == forth.FLASH_ERASE_KEY else 0)
            if key == forth.FLASH_ERASE_KEY:
                self._flash_erase(page)
            return
        if token == "fw":
            page = stack.pop(); mode = stack.pop(); self._do_fw(mode, page); return
        # System words
        if token == "clk":
            clock_sel = stack.pop(); stack.pop()  # time_sel unused in sim
            stack.append(CLK_FREQ.get(clock_sel & 0x3, 24000000)); return
        if token in ("call0", "call1", "call2", "call3", "call4"):
            n = int(token[-1])
            for _ in range(n + 1):                 # pop func ptr + n args
                stack.pop()
            stack.append(self._call_return); return
        if token == "rst":
            self._reset = True
            self._emit_str("\n" + BANNER + "\n"); return
        if token == "echo":
            self._echo = bool(stack.pop()); return
        # Unknown word -> the monitor prints '?' (see progBi[] undefined-string path)
        self._emit_str("?")

    # -- memory helpers ----------------------------------------------------

    def _read_word(self, addr: int) -> int:
        return self._mem.get(forth.to_u32(addr) & ~3, 0)

    def _write_word(self, addr: int, value: int) -> None:
        self._mem[forth.to_u32(addr) & ~3] = forth.to_u32(value)

    def _byte_at(self, addr: int) -> int:
        word = self._read_word(addr)
        return (word >> (8 * (forth.to_u32(addr) & 3))) & 0xFF

    def _mem_erase(self, addr: int, length: int) -> None:
        addr = forth.to_u32(addr) & ~3
        end = addr + (length & ~3)
        while addr < end:
            self._mem[addr] = 0
            addr += 4

    # -- mr / fr / fw ------------------------------------------------------

    def _do_mr(self, mode: int, length: int, addr: int) -> None:
        data = bytes(self._byte_at(addr + i) for i in range(length))
        crc = forth.crc16_cdma2000(data)
        if mode == 0:
            self._emit_str("".join("%02X" % b for b in data))
            self._emit_str("%04X" % crc)
        else:
            self._emit(data)
            self._emit(bytes([crc & 0xFF, (crc >> 8) & 0xFF]))  # LSB first

    def _do_fr(self, binflag: int, length: int, addr: int) -> None:
        data = bytes(self._flash.get(forth.to_u32(addr) + i, 0xFF)
                     for i in range(length))
        if binflag:
            self._emit(data)
        else:
            self._emit_str("".join("%02X" % b for b in data))

    def _do_fw(self, mode: int, page: int) -> None:
        self._emit_str("$")                        # ready character
        if mode == 0:
            buf = bytearray()
            for _ in range(256):
                hi = self._hex_nibble(self._get_byte())
                lo = self._hex_nibble(self._get_byte())
                buf.append((hi << 4) | lo)
        else:
            buf = bytearray(self._get_byte() for _ in range(256))
        crc = forth.crc16_cdma2000(bytes(buf))
        self._emit_str("%04X" % crc)               # 4-char hex CRC
        confirm = self._get_byte()
        if confirm == ord("Y"):
            base = forth.to_u32(page) & FLASH_PAGE_MASK   # hardware page masking
            for i, byte in enumerate(buf):
                self._flash[base + i] = byte

    def _flash_erase(self, page: int) -> None:
        base = forth.to_u32(page) & FLASH_PAGE_MASK        # hardware page masking
        for i in range(256):
            self._flash[base + i] = 0xFF

    @staticmethod
    def _hex_nibble(byte: int) -> int:
        char = chr(byte)
        return int(char, 16)


def _parse_number(token: str) -> Optional[int]:
    """Mirror rv4th numFunc(): base-10 or 0x-hex, optional leading '-'."""
    body = token[1:] if token.startswith("-") else token
    try:
        if body.lower().startswith("0x"):
            value = int(body, 16)
        else:
            value = int(body, 10)
    except ValueError:
        return None
    return -value if token.startswith("-") else value
