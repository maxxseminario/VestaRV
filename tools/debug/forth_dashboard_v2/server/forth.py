"""Forth command builders + response parsers for the rv4th REPL.

Every function here is PURE (string/bytes in -> typed value out) so it is
trivially unit-testable against real transcript lines.  Nothing in this module
touches a serial port.

Ground truth for the on-chip output formats (verified 2026-07-18):

  software/rv4th/src/rv4th.c
    case  6  ".":   printNumberInt32(pop)  -> uart_puti(n) then ' '
                    => SIGNED decimal followed by a single trailing space.
    case 28  "h.":  printHex32(pop) then ' '
                    => 8 UPPERCASE hex digits, NO "0x" prefix, trailing space.
    case 13  "hb.": printHex8(pop) then ' '  => 2 hex digits + space.
    case 83  "fe":  pushes 1/0 (erase_successful) to TOS  -> read with ".".
    case 80  "clk": leaves measured frequency on TOS      -> read with ".".
    case 92  "mr":  memoryReadFunc(): mode 0 = ASCII hex bytes then 4-hex CRC16;
                    mode 1 = raw bytes then 2-byte LSB-first CRC16;
                    mode 2 = 2-byte LSB-first length, then LZW payload.
    case 81  "fr":  flashReadFunc(): mode 0 = ASCII hex bytes (NO CRC);
                    mode 1 = raw bytes (NO CRC).

  software/rv4th/src/uart.c
    uart_puth4:  values > 9 map to 'A'..'F'  => hex output is UPPERCASE.
    uart_puti :  '-' then unsigned decimal   => signed decimal, no padding.

  software/rv4th/src/main.c + bootrom/src/rv4th.c:1842
    reset banner = ASIC_NAME + " rv4th-rom!"  => "myshkin rv4th-rom!\n".
"""

import re
from typing import List, Optional, Tuple

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROMPT = b">"          # getLine() prints "\n>" every time it wants input.
BANNER_MARK = "rv4th-rom!"   # substring that identifies the reset banner.
FLASH_ERASE_KEY = 123        # fe requires this confirmation key (case 83).

# Noise bytes v1's parser had to strip from real transcripts
# (see tools/debug/forth_dashboard/myshkin.py: .replace('\x1a','').replace('?','')).
_NOISE_RE = re.compile(r"[\x1a\x00]")
_SIGNED_DEC_RE = re.compile(r"-?\d+")
_HEX_TOKEN_RE = re.compile(r"[0-9A-Fa-f]+")


# ---------------------------------------------------------------------------
# 32-bit helpers
# ---------------------------------------------------------------------------

def to_u32(value: int) -> int:
    """Reduce an int to an unsigned 32-bit value."""
    return value & 0xFFFFFFFF


def to_i32(value: int) -> int:
    """Reduce an int to a signed 32-bit value (two's complement)."""
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def _num(value: int) -> str:
    """Render an int as a Forth literal.

    Non-negative values become ``0x``-prefixed hex so large unsigned values
    (>0x7FFFFFFF) survive the chip's 32-bit base-10 parser; negatives use
    decimal (rv4th numFunc() honours a leading '-').
    """
    if value < 0:
        return str(value)
    return "0x%X" % (value & 0xFFFFFFFF)


# ---------------------------------------------------------------------------
# CRC16 / CDMA2000  (poly 0xC857, init 0xFFFF, no reflection, no final xor)
# Matches the chip's CRCSTATE/CRCDATA hardware used by mr / fw.
# ---------------------------------------------------------------------------

def crc16_cdma2000(data: bytes) -> int:
    """Compute CRC16-CDMA2000 over *data* (the format mr/fw emit)."""
    crc = 0xFFFF
    for byte in data:
        crc ^= (byte << 8) & 0xFFFF
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0xC857) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc & 0xFFFF


# ---------------------------------------------------------------------------
# Command builders
# ---------------------------------------------------------------------------

def build_read_hex(addr: int) -> str:
    """Word read, printed as unsigned hex (preferred for registers/memory)."""
    return "0x%X @ h." % to_u32(addr)


def build_read_dec(addr: int) -> str:
    """Word read, printed as signed decimal."""
    return "0x%X @ ." % to_u32(addr)


def build_write(addr: int, value: int) -> str:
    """Word write: ``value addr !``."""
    return "%s 0x%X !" % (_num(value), to_u32(addr))


def build_setbit(bit: int, addr: int) -> str:
    """Set a single bit: ``bit addr sbi``."""
    return "%d 0x%X sbi" % (bit, to_u32(addr))


def build_clearbit(bit: int, addr: int) -> str:
    """Clear a single bit: ``bit addr cbi``."""
    return "%d 0x%X cbi" % (bit, to_u32(addr))


def build_mask(posmask: int, value: int, addr: int) -> str:
    """Masked write: ``posmask value addr mask`` (only masked bits change)."""
    return "%s %s 0x%X mask" % (_num(posmask), _num(value), to_u32(addr))


def build_erase(addr: int, length: int) -> str:
    """Memory erase (zero-fill): ``length addr me``."""
    return "%d 0x%X me" % (length, to_u32(addr))


def build_mr(mode: int, length: int, addr: int) -> str:
    """Bulk memory read: ``mode length addr mr``."""
    return "%d %d 0x%X mr" % (mode, length, to_u32(addr))


def build_flash_read(binary: int, length: int, addr: int) -> str:
    """SPI-flash read: ``bin length addr fr``."""
    return "%d %d 0x%X fr" % (1 if binary else 0, length, to_u32(addr))


def build_flash_erase(page: int) -> str:
    """SPI-flash page erase, result printed: ``123 page fe .``."""
    return "%d 0x%X fe ." % (FLASH_ERASE_KEY, to_u32(page))


def build_flash_write(mode: int, page: int) -> str:
    """SPI-flash page write header: ``mode page fw`` (interactive handshake)."""
    return "%d 0x%X fw" % (mode, to_u32(page))


def build_clk(clock_sel: int, time_sel: int) -> str:
    """Clock measure, printed: ``time_sel clock_sel clk .``.

    rv4th.c case 80 pops clock_select (TOS) first, then measurement_time_select,
    so time_sel must be pushed *before* clock_sel.
    """
    return "%d %d clk ." % (time_sel, clock_sel)


def build_exec(addr: int, args: Optional[List[int]] = None) -> str:
    """Execute code at *addr* with 0..4 args, printing the return value.

    call1..call4 take args below the function pointer on the stack, e.g.
    ``a b &func call2`` -> func(a, b).  Result printed with ".".
    """
    args = list(args or [])
    if len(args) > 4:
        raise ValueError("call supports at most 4 arguments")
    parts = [_num(a) for a in args]
    parts.append("0x%X" % to_u32(addr))
    parts.append("call%d" % len(args))
    parts.append(".")
    return " ".join(parts)


# ---------------------------------------------------------------------------
# Response parsers  (operate on the FRAMED output: echo + prompt already gone)
# ---------------------------------------------------------------------------

def strip_noise(text: str) -> str:
    """Drop the stray control bytes real transcripts carry (0x1a, NUL)."""
    return _NOISE_RE.sub("", text)


def parse_decimal(text: str) -> int:
    """Parse the signed-decimal value printed by ``.`` (last number wins)."""
    matches = _SIGNED_DEC_RE.findall(strip_noise(text))
    if not matches:
        raise ValueError("no decimal value in response: %r" % text)
    return to_i32(int(matches[-1]))


def parse_hex_word(text: str) -> int:
    """Parse the 8-digit hex value printed by ``h.`` (last token wins).

    Returns an unsigned 32-bit int.  ``h.`` always emits exactly 8 hex chars.
    """
    matches = _HEX_TOKEN_RE.findall(strip_noise(text))
    if not matches:
        raise ValueError("no hex value in response: %r" % text)
    return to_u32(int(matches[-1], 16))


def parse_bool(text: str) -> bool:
    """Parse a 0/1 flag printed by ``.`` (used by fe)."""
    return parse_decimal(text) != 0


def parse_hexdump(text: str, length: int) -> bytes:
    """Parse *length* bytes from an ASCII-hex payload (mr mode 0 / fr mode 0).

    Concatenates every hex digit in *text*, then takes the first ``2*length``
    of them.  For mr mode 0 the trailing 4 CRC chars therefore sit past the
    slice and are ignored; use :func:`parse_mr_ascii` when the CRC is wanted.
    """
    digits = "".join(_HEX_TOKEN_RE.findall(strip_noise(text)))
    need = 2 * length
    if len(digits) < need:
        raise ValueError(
            "hexdump too short: wanted %d hex chars, got %d" % (need, len(digits)))
    return bytes.fromhex(digits[:need])


def parse_mr_ascii(text: str, length: int) -> Tuple[bytes, int]:
    """Parse mr mode-0 output -> (payload bytes, CRC16).

    Layout: ``length`` bytes as 2-hex each, then a 4-hex CRC16.
    """
    digits = "".join(_HEX_TOKEN_RE.findall(strip_noise(text)))
    need = 2 * length + 4
    if len(digits) < need:
        raise ValueError(
            "mr ascii too short: wanted %d hex chars, got %d" % (need, len(digits)))
    payload = bytes.fromhex(digits[:2 * length])
    crc = int(digits[2 * length:2 * length + 4], 16)
    return payload, crc


def contains_banner(text: str) -> bool:
    """True if *text* holds the reset banner ("...rv4th-rom!")."""
    return BANNER_MARK in text
