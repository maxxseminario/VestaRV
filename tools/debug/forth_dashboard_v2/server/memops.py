"""VestaRV: bulk memory and flash operations built on the SerialManager.

Synchronous, each step blocking on its transaction Future, so REST handlers run them in a
thread executor; every step still goes through the one serial queue. ASCII mr (mode 0) is
prompt-framed and carries a CRC, binary mr (mode 1) is length-counted because a payload byte
can be 0x3E. Bulk RAM writes use mw; peripheral space and short writes use ! because mw stores
single bytes and peripheral registers take whole words.
"""

import base64
from typing import Any, Callable, Dict, List, Optional

from server import forth
from server.serial_manager import Channel, SerialManager

FLASH_PAGE = 256
# Ground truth (Myshkin ROM, riscv-tests/gcc/bootrom/src/flash_memory.c writePage/erasePage):
# the SPI address is sent as opcode<<24 | page_address, so bits [31:24] are out
# of range ("MSB 8 bits ignored") -> 24-bit space = 16 MiB addressable;
# LSB 8 bits ignored -> 256-byte page boundary.
FLASH_TOTAL_BYTES = 0x1000000              # 2**24 = 16 MiB
FLASH_PAGE_COUNT = FLASH_TOTAL_BYTES // FLASH_PAGE   # 65536

BINARY_TIMEOUT = 5.0
FLASH_TIMEOUT = 6.0

PERIPHERAL_BASE = 0x4000
PERIPHERAL_END = 0x5000
MW_MIN_WORDS = 4           # below this, the mw handshake saves nothing over ! loops
UART_BYTES_PER_SEC = 11520  # 115200 baud, 8N1


def transfer_timeout(wire_bytes: int, base: float = BINARY_TIMEOUT) -> float:
    """Deadline for moving *wire_bytes* over the UART, with 50% margin on top of *base*."""
    return base + 1.5 * wire_bytes / UART_BYTES_PER_SEC


def flash_info() -> Dict[str, int]:
    """Flash geometry for GET /api/flash/info."""
    return {
        "page_size": FLASH_PAGE,
        "page_count": FLASH_PAGE_COUNT,
        "total_bytes": FLASH_TOTAL_BYTES,
    }


def _result(future: Any, timeout: float) -> Any:
    # Covers the first attempt, its retry, and the resync between them.
    return future.result(timeout=2 * timeout + 2.0)


# Memory read

def read_memory(manager: SerialManager, addr: int, length: int,
                mode: int = 0, timeout: Optional[float] = None) -> Dict[str, Any]:
    """Read *length* bytes from *addr*.  mode 0 = ASCII hex, 1 = binary.

    Returns {addr, length, mode, hex, base64, crc, crc_ok}.
    """
    if length <= 0:
        return {"addr": addr, "length": 0, "mode": mode, "hex": "",
                "base64": "", "crc": None, "crc_ok": True}

    if timeout is None:
        timeout = transfer_timeout(length if mode == 1 else 2 * length)
    if mode == 1:
        payload, crc = _read_memory_binary(manager, addr, length, timeout)
    else:
        text = _result(manager.submit(forth.build_mr(0, length, addr),
                                      timeout=timeout), timeout)
        payload, crc = forth.parse_mr_ascii(text, length)

    expected = forth.crc16_cdma2000(payload)
    return {
        "addr": addr,
        "length": length,
        "mode": mode,
        "hex": payload.hex(),
        "base64": base64.b64encode(payload).decode("ascii"),
        "crc": crc,
        "crc_ok": crc == expected,
    }


def _read_memory_binary(manager: SerialManager, addr: int, length: int,
                        timeout: float):
    command = forth.build_mr(1, length, addr)
    line = command + "\n"

    def run(ch: Channel):
        ch.write(line.encode("latin-1"))
        ch.expect_echo(line)
        raw = ch.read_exact(length + 2)            # payload + 2-byte LSB CRC
        ch.read_until(forth.PROMPT)                # consume trailing prompt
        payload = raw[:length]
        crc = raw[length] | (raw[length + 1] << 8)
        return payload, crc

    return _result(manager.submit_interaction(run, command, timeout=timeout),
                   timeout)


def format_hexdump(addr: int, data: bytes, width: int = 16) -> str:
    """Render a canonical offset/hex/ascii dump (for the F4 viewer / export)."""
    lines = []
    for off in range(0, len(data), width):
        chunk = data[off:off + width]
        hexpart = " ".join("%02x" % b for b in chunk)
        hexpart = hexpart.ljust(width * 3 - 1)
        asciipart = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append("%08x  %s  |%s|" % (addr + off, hexpart, asciipart))
    return "\n".join(lines)


# Memory write (word-wise ! loop) + erase

def write_memory(manager: SerialManager, addr: int, words: List[int],
                 verify: bool = True, timeout: float = 2.0,
                 progress: Optional[Callable[[int, int], None]] = None
                 ) -> Dict[str, Any]:
    """Write *words*, 32 bits each, sequentially from *addr*. RAM blocks go through mw, whose CRC
    is always checked; anything else uses `!`, with each word read back when *verify* is set.
    Returns {written, verified, mismatches:[{index, addr, wrote, read}]}.
    """
    in_peripherals = addr < PERIPHERAL_END and addr + 4 * len(words) > PERIPHERAL_BASE
    if len(words) >= MW_MIN_WORDS and not in_peripherals:
        return _write_memory_bulk(manager, addr, words, progress)

    mismatches = []  # type: List[Dict[str, Any]]
    verified = 0
    total = len(words)
    for index, word in enumerate(words):
        word_addr = addr + 4 * index
        _result(manager.submit(forth.build_write(word_addr, word),
                               timeout=timeout), timeout)
        if verify:
            text = _result(manager.submit(forth.build_read_hex(word_addr),
                                          timeout=timeout), timeout)
            read_back = forth.parse_hex_word(text)
            if read_back == forth.to_u32(word):
                verified += 1
            else:
                mismatches.append({
                    "index": index, "addr": word_addr,
                    "wrote": forth.to_u32(word), "read": read_back,
                })
        if progress is not None:
            progress(index + 1, total)
    return {"written": total, "verified": verified, "mismatches": mismatches}


def _write_memory_bulk(manager: SerialManager, addr: int, words: List[int],
                       progress: Optional[Callable[[int, int], None]] = None
                       ) -> Dict[str, Any]:
    """Write a RAM block through the mw binary handshake, checking the chip's CRC of what it got.
    Not retried: a failed attempt can leave the chip still waiting for payload bytes.
    """
    data = b"".join(forth.to_u32(word).to_bytes(4, "little") for word in words)
    expected = forth.crc16_cdma2000(data)
    command = forth.build_mw(1, len(data), addr)
    line = command + "\n"
    timeout = transfer_timeout(len(data))

    def run(ch: Channel) -> int:
        ch.write(line.encode("latin-1"))
        ch.expect_echo(line)
        ch.read_until(b"$")                        # ready character
        ch.write(data)
        chip_crc = int(ch.read_exact(4).decode("latin-1"), 16)
        ch.read_until(forth.PROMPT)
        return chip_crc

    chip_crc = _result(manager.submit_interaction(run, command, timeout=timeout, retries=0),
                       timeout)
    total = len(words)
    if progress is not None:
        progress(total, total)
    if chip_crc == expected:
        return {"written": total, "verified": total, "mismatches": []}
    return {"written": total, "verified": 0,
            "mismatches": [{"index": 0, "addr": addr, "wrote": expected, "read": chip_crc}]}


def erase_memory(manager: SerialManager, addr: int, length: int,
                 timeout: float = 3.0) -> Dict[str, Any]:
    """Zero-fill *length* bytes from *addr* using ``ms``."""
    _result(manager.submit(forth.build_erase(addr, length), timeout=timeout),
            timeout)
    return {"addr": addr, "length": length, "erased": True}


# Flash

def _page_to_addr(page: int) -> int:
    """Convert a 0-based flash page index to its byte address for fe and fw. The API page is an index
    while the ROM words take a byte address whose low 8 bits are ignored, so the address is
    page*256.
    """
    if not (0 <= page < FLASH_PAGE_COUNT):
        raise ValueError("flash page index out of range 0..%d: %d"
                         % (FLASH_PAGE_COUNT - 1, page))
    return page * FLASH_PAGE


def flash_erase(manager: SerialManager, page: int,
                timeout: float = FLASH_TIMEOUT) -> Dict[str, Any]:
    """Erase a flash page (key 123).  *page* is a page INDEX.  Returns {page, ok}."""
    addr = _page_to_addr(page)
    text = _result(manager.submit(forth.build_flash_erase(addr), timeout=timeout),
                   timeout)
    return {"page": page, "ok": forth.parse_bool(text)}


def flash_read(manager: SerialManager, addr: int, length: int,
               timeout: Optional[float] = None) -> Dict[str, Any]:
    """Read *length* flash bytes from *addr* (a BYTE address; fr reads arbitrary
    addresses, no page masking).  ASCII-hex, no CRC.  {hex, base64}."""
    if length <= 0:
        return {"addr": addr, "length": 0, "hex": "", "base64": ""}
    if timeout is None:
        timeout = transfer_timeout(2 * length, FLASH_TIMEOUT)
    text = _result(manager.submit(forth.build_flash_read(0, length, addr),
                                  timeout=timeout), timeout)
    payload = forth.parse_hexdump(text, length)
    return {
        "addr": addr, "length": length,
        "hex": payload.hex(),
        "base64": base64.b64encode(payload).decode("ascii"),
    }


def flash_write_page(manager: SerialManager, page: int, data: bytes,
                     verify_crc: bool = True,
                     timeout: float = FLASH_TIMEOUT) -> Dict[str, Any]:
    """Write one 256-byte page via the fw binary handshake; *page* is an index, converted to
    page*256. Short data is padded with 0xFF and longer data rejected; with *verify_crc* a CRC
    mismatch aborts the write and reports ok=False. Returns {page, crc, expected_crc, ok, written}.
    """
    if len(data) > FLASH_PAGE:
        raise ValueError("flash page data must be <= %d bytes" % FLASH_PAGE)
    addr = _page_to_addr(page)
    padded = data + b"\xff" * (FLASH_PAGE - len(data))
    expected = forth.crc16_cdma2000(padded)
    command = forth.build_flash_write(1, addr)     # mode 1 = raw binary payload
    line = command + "\n"

    def run(ch: Channel) -> Dict[str, Any]:
        ch.write(line.encode("latin-1"))
        ch.expect_echo(line)
        ch.read_until(b"$")                        # ready character
        ch.write(padded)
        crc_hex = ch.read_exact(4).decode("latin-1")
        chip_crc = int(crc_hex, 16)
        ok = (not verify_crc) or (chip_crc == expected)
        ch.write(b"Y" if ok else b"N")
        ch.read_until(forth.PROMPT)                # prompt after write/abort
        return {"page": page, "crc": chip_crc, "expected_crc": expected,
                "ok": ok, "written": ok}

    # Not retried: resending after a timeout would land inside the chip's payload read.
    return _result(manager.submit_interaction(run, command, timeout=timeout, retries=0),
                   timeout)


def flash_program(manager: SerialManager, start_page: int, data: bytes,
                  erase: bool = True,
                  progress: Optional[Callable[[int, int], None]] = None
                  ) -> Dict[str, Any]:
    """Program an image page-by-page from *start_page* (a page INDEX).

    Returns {pages, failures} where failures lists the failing page INDICES.
    """
    chunks = [(i, data[off:off + FLASH_PAGE])
              for i, off in enumerate(range(0, len(data), FLASH_PAGE))]
    failures = []  # type: List[int]
    for i, chunk in chunks:
        page = start_page + i
        if erase:
            flash_erase(manager, page)
        res = flash_write_page(manager, page, chunk)
        if not res["ok"]:
            failures.append(page)
        if progress is not None:
            progress(i + 1, len(chunks))
    return {"pages": len(chunks), "failures": failures,
            "ok": len(failures) == 0}
