"""Bulk memory / flash operations built on the SerialManager.

These orchestrate multiple transactions (word-wise ! upload, mr dumps, the fw
flash handshake).  They are synchronous -- each step blocks on the transaction
Future -- so REST handlers run them in a thread executor while the event loop
stays free.  Every step still goes through the one serial queue, so nothing
interleaves.

Rationale for the key choices:
* ASCII mr (mode 0) is prompt-framed and carries a CRC; binary mr (mode 1) is
  length-counted (payload+2 CRC bytes) because a payload byte can be 0x3E ('>').
* mw is a ROM stub (rv4th.c case 93 is empty) -- uploads MUST use ! loops.
* fw is interactive: header -> '$' -> 256 bytes -> 4-hex CRC -> 'Y'/'N'.
"""

import base64
from typing import Any, Callable, Dict, List, Optional

from server import forth
from server.serial_manager import Channel, SerialManager

FLASH_PAGE = 256
# Ground truth (software/bootrom/src/flash_memory.c writePage/erasePage):
# the SPI address is sent as opcode<<24 | page_address, so bits [31:24] are out
# of range ("MSB 8 bits ignored") -> 24-bit space = 16 MiB addressable;
# LSB 8 bits ignored -> 256-byte page boundary.
FLASH_TOTAL_BYTES = 0x1000000              # 2**24 = 16 MiB
FLASH_PAGE_COUNT = FLASH_TOTAL_BYTES // FLASH_PAGE   # 65536

BINARY_TIMEOUT = 5.0
FLASH_TIMEOUT = 6.0


def flash_info() -> Dict[str, int]:
    """Flash geometry for GET /api/flash/info (Fable ruling 3)."""
    return {
        "page_size": FLASH_PAGE,
        "page_count": FLASH_PAGE_COUNT,
        "total_bytes": FLASH_TOTAL_BYTES,
    }


def _result(future: Any, timeout: float) -> Any:
    return future.result(timeout=timeout + 1.0)


# ---------------------------------------------------------------------------
# Memory read
# ---------------------------------------------------------------------------

def read_memory(manager: SerialManager, addr: int, length: int,
                mode: int = 0, timeout: float = BINARY_TIMEOUT) -> Dict[str, Any]:
    """Read *length* bytes from *addr*.  mode 0 = ASCII hex, 1 = binary.

    Returns {addr, length, mode, hex, base64, crc, crc_ok}.
    """
    if length <= 0:
        return {"addr": addr, "length": 0, "mode": mode, "hex": "",
                "base64": "", "crc": None, "crc_ok": True}

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


# ---------------------------------------------------------------------------
# Memory write (word-wise ! loop) + erase
# ---------------------------------------------------------------------------

def write_memory(manager: SerialManager, addr: int, words: List[int],
                 verify: bool = True, timeout: float = 2.0,
                 progress: Optional[Callable[[int, int], None]] = None
                 ) -> Dict[str, Any]:
    """Write *words* (32-bit each) sequentially from *addr* via ``!`` loops.

    With *verify*, each word is read back with ``h.`` and compared.  Returns
    {written, verified, mismatches:[{index, addr, wrote, read}]}.
    """
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


def erase_memory(manager: SerialManager, addr: int, length: int,
                 timeout: float = 3.0) -> Dict[str, Any]:
    """Zero-fill *length* bytes from *addr* using ``me`` (word-aligned)."""
    _result(manager.submit(forth.build_erase(addr, length), timeout=timeout),
            timeout)
    return {"addr": addr & ~3, "length": length & ~3, "erased": True}


# ---------------------------------------------------------------------------
# Flash
# ---------------------------------------------------------------------------

def _page_to_addr(page: int) -> int:
    """Convert a 0-based flash PAGE INDEX to its byte address for fe/fw.

    The REST/API "page" is a page index (0..page_count-1); the ROM fe/fw words
    take a byte address whose low 8 bits are ignored (256-byte page boundary),
    so the byte address is page*256 (Fable ruling, G2).
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
               timeout: float = FLASH_TIMEOUT) -> Dict[str, Any]:
    """Read *length* flash bytes from *addr* (a BYTE address; fr reads arbitrary
    addresses, no page masking).  ASCII-hex, no CRC.  {hex, base64}."""
    if length <= 0:
        return {"addr": addr, "length": 0, "hex": "", "base64": ""}
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
    """Write one 256-byte page via the fw binary handshake.  *page* is a page
    INDEX (converted to byte address page*256, Fable ruling G2).

    Short data is padded with 0xFF; longer data is rejected.  With *verify_crc*
    a mismatch between the host and chip CRC aborts the write ('N') and reports
    ok=False.  Returns {page, crc, expected_crc, ok, written}.
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

    return _result(manager.submit_interaction(run, command, timeout=timeout),
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
