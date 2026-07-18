"""SerialManager tests driven against the byte-level SimChip transport.

These exercise the WHOLE framing path (echo consumption, prompt detection,
length-counted binary reads) plus the state machine, timeout/retry, and the
unsolicited banner channel.
"""

import threading
import time

import pytest

from server import forth, memops
from server.serial_manager import (ConnectionState, SerialManager,
                                    TransactionTimeout)
from server.sim_chip import SimChip


def _wait(predicate, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return False


class _CollectingListener:
    def __init__(self):
        self.events = []
        self._lock = threading.Lock()

    def __call__(self, event):
        with self._lock:
            self.events.append(event)

    def types(self):
        with self._lock:
            return [e["type"] for e in self.events]


@pytest.fixture
def manager():
    mgr = SerialManager(lambda port, baud: SimChip())
    listener = _CollectingListener()
    mgr.add_listener(listener)
    mgr.start()
    mgr.connect("sim", 115200)
    assert _wait(lambda: mgr.connected), "manager never connected"
    mgr._listener = listener  # stash for tests
    yield mgr
    mgr.stop()


# --- basic round trips ------------------------------------------------------

def test_connect_sets_banner(manager):
    assert _wait(lambda: manager.banner_seen)
    assert manager.state == ConnectionState.IDLE


def test_arithmetic_round_trip(manager):
    rx = manager.submit("5 3 + .").result(timeout=3)
    assert forth.parse_decimal(rx) == 8


def test_write_then_read_hex(manager):
    manager.submit(forth.build_write(0x10000, 0xDEADBEEF)).result(timeout=3)
    rx = manager.submit(forth.build_read_hex(0x10000)).result(timeout=3)
    assert forth.parse_hex_word(rx) == 0xDEADBEEF


def test_read_default_is_zero(manager):
    rx = manager.submit(forth.build_read_hex(0x10040)).result(timeout=3)
    assert forth.parse_hex_word(rx) == 0


def test_status_shape(manager):
    st = manager.status()
    assert st["connected"] is True
    assert st["state"] == "idle"
    assert st["banner_seen"] is True
    assert st["uptime"] >= 0.0


# --- events / WS stream -----------------------------------------------------

def test_events_include_tx_rx_state_and_banner(manager):
    manager.submit("1 2 + .").result(timeout=3)
    assert _wait(lambda: "rx" in manager._listener.types())
    types = manager._listener.types()
    assert "tx" in types
    assert "rx" in types
    assert "state" in types
    assert "info" in types  # banner info event


# --- binary + ascii mr via memops (length-counted framing) ------------------

def test_memory_write_read_ascii_and_binary(manager):
    words = [0x11223344, 0x55667788, 0x00000000, 0xFFFFFFFF]
    res = memops.write_memory(manager, 0x10010, words, verify=True)
    assert res["mismatches"] == []
    assert res["verified"] == len(words)

    # ASCII mr (mode 0, prompt-framed + CRC)
    ascii_read = memops.read_memory(manager, 0x10010, 16, mode=0)
    assert ascii_read["crc_ok"] is True
    # little-endian bytes of the first word
    assert ascii_read["hex"][:8] == "44332211"

    # Binary mr (mode 1, length-counted -- payload may contain 0x3E '>')
    bin_read = memops.read_memory(manager, 0x10010, 16, mode=1)
    assert bin_read["crc_ok"] is True
    assert bin_read["hex"] == ascii_read["hex"]


def test_binary_mr_survives_gt_byte_in_payload(manager):
    # 0x3E is '>' -- a naive prompt scan would truncate here; length-counting
    # must not.  Word 0x0000003E has byte 0x3E at offset 0.
    manager.submit(forth.build_write(0x10020, 0x3E3E3E3E)).result(timeout=3)
    res = memops.read_memory(manager, 0x10020, 4, mode=1)
    assert res["crc_ok"] is True
    assert res["hex"] == "3e3e3e3e"


# --- erase ------------------------------------------------------------------

def test_memory_erase(manager):
    manager.submit(forth.build_write(0x10030, 0xABCDEF01)).result(timeout=3)
    memops.erase_memory(manager, 0x10030, 4)
    rx = manager.submit(forth.build_read_hex(0x10030)).result(timeout=3)
    assert forth.parse_hex_word(rx) == 0


# --- flash handshake --------------------------------------------------------

def test_flash_erase_write_read_roundtrip(manager):
    page = 0x200                                   # page INDEX -> byte addr 0x20000
    assert memops.flash_erase(manager, page)["ok"] is True
    payload = bytes((i * 7) & 0xFF for i in range(256))
    res = memops.flash_write_page(manager, page, payload)
    assert res["ok"] is True
    assert res["crc"] == res["expected_crc"]
    back = memops.flash_read(manager, page * 256, 16)   # fr takes a byte address
    assert back["hex"] == payload[:16].hex()


def test_flash_page_index_out_of_range_rejected(manager):
    with pytest.raises(ValueError):
        memops.flash_erase(manager, memops.FLASH_PAGE_COUNT)   # == 65536, invalid


def test_sim_fw_masks_nonaligned_byte_address(manager):
    # Fable ruling: fw/fe mask their forth argument like the ROM SPI driver
    # (addr & 0x00FFFF00).  A raw "fw" to a non-aligned byte address must land
    # at the masked page base -- same as hardware.
    payload = bytes((i ^ 0x5A) & 0xFF for i in range(256))

    def raw_fw(ch):
        line = "1 0x305 fw\n"                       # byte addr 0x305 -> masks to 0x300
        ch.write(line.encode("latin-1"))
        ch.expect_echo(line)
        ch.read_until(b"$")
        ch.write(payload)
        crc_hex = ch.read_exact(4).decode("latin-1")
        ch.write(b"Y")
        ch.read_until(forth.PROMPT)
        return int(crc_hex, 16)

    manager.submit_interaction(raw_fw, "raw fw").result(timeout=5)
    back = memops.flash_read(manager, 0x300, 16)    # data landed at the masked base
    assert back["hex"] == payload[:16].hex()
    # nothing at 0x305 that wasn't already in the masked page
    assert memops.flash_read(manager, 0x400, 4)["hex"] == "ffffffff"


# --- exec / clk -------------------------------------------------------------

def test_exec_returns_canned_value(manager):
    rx = manager.submit(forth.build_exec(0x8200, [1, 2, 3])).result(timeout=3)
    assert forth.parse_decimal(rx) == 0x2A


def test_clk_returns_frequency(manager):
    rx = manager.submit(forth.build_clk(clock_sel=2, time_sel=0)).result(timeout=3)
    assert forth.parse_decimal(rx) == 32768  # LFXT canned value


# --- timeout / UNRESPONSIVE (no SimChip: a silent transport) ----------------

class _SilentTransport:
    description = "silent"
    baud = 0

    def read(self, max_bytes, timeout):
        threading.Event().wait(timeout)  # block, then report nothing
        return b""

    def write(self, data):
        pass

    def close(self):
        pass


def test_timeout_marks_unresponsive():
    mgr = SerialManager(lambda p, b: _SilentTransport(),
                        default_timeout=0.2, default_retries=1)
    mgr.start()
    mgr.connect("silent", 0)
    assert _wait(lambda: mgr.connected)
    fut = mgr.submit("0x4000 @ h.")
    with pytest.raises(TimeoutError):
        fut.result(timeout=5)
    assert _wait(lambda: mgr.state == ConnectionState.UNRESPONSIVE)
    mgr.stop()


def test_channel_read_until_and_exact_are_deadline_bounded():
    # Direct unit check of the framing primitives against a silent transport.
    from server.serial_manager import Channel
    ch = Channel(_SilentTransport(), deadline=time.monotonic() + 0.15)
    with pytest.raises(TransactionTimeout):
        ch.read_until(b">")


# --- retry resynchronisation (Fable G2 FIX 2) -------------------------------

class _ResyncProbeTransport:
    """Preloaded with stale bytes; answers a lone '\n' write with a prompt."""

    def __init__(self, stale):
        self.cond = threading.Condition()
        self.buf = bytearray(stale)
        self.got_newline = False

    def read(self, max_bytes, timeout):
        with self.cond:
            if not self.buf:
                self.cond.wait(timeout)
            if not self.buf:
                return b""
            out = bytes(self.buf[:max_bytes])
            del self.buf[:max_bytes]
            return out

    def write(self, data):
        with self.cond:
            if b"\n" in data:
                self.got_newline = True
                self.buf.extend(b"\n>")
                self.cond.notify_all()

    def close(self):
        pass


def test_resync_drains_stale_and_reestablishes_prompt():
    transport = _ResyncProbeTransport(b"stale echo/output with no prompt ")
    mgr = SerialManager(lambda p, b: transport)
    mgr._transport = transport                 # unit-drive _resync directly
    assert mgr._resync() is True
    assert transport.got_newline is True       # elicited a fresh prompt


class _StaleRetryTransport:
    """Attempt 1 stays silent (forces a timeout); the timed-out attempt's stale
    bytes are released during the resync drain/prompt phase, and the retry gets
    a clean echo+output.  Records whether the resync '\n' was ever written."""

    def __init__(self):
        self.cond = threading.Condition()
        self.buf = bytearray()
        self.cmd_writes = 0
        self.saw_resync = False
        self.stale = b"late-stale-bytes-from-attempt-1 "

    def read(self, max_bytes, timeout):
        with self.cond:
            if not self.buf:
                self.cond.wait(timeout)
            if not self.buf:
                return b""
            out = bytes(self.buf[:max_bytes])
            del self.buf[:max_bytes]
            return out

    def write(self, data):
        with self.cond:
            if data == b"\n":
                self.saw_resync = True
                self.buf.extend(self.stale)     # stale surfaces during resync
                self.stale = b""
                self.buf.extend(b"\n>")
            else:
                self.cmd_writes += 1
                if self.cmd_writes >= 2:         # the retry: clean echo + output
                    self.buf.extend(data)
                    self.buf.extend(b"8 \n>")
                # attempt 1 (cmd_writes == 1): stay silent -> timeout
            self.cond.notify_all()

    def close(self):
        pass


def test_retry_resyncs_and_parses_after_stale_bytes():
    transport = _StaleRetryTransport()
    mgr = SerialManager(lambda p, b: transport,
                        default_timeout=0.3, default_retries=1)
    mgr.start()
    mgr.connect("stale", 0)
    assert _wait(lambda: mgr.connected)
    rx = mgr.submit("5 3 + .").result(timeout=5)
    assert forth.parse_decimal(rx) == 8        # retry parsed correctly
    assert transport.saw_resync is True        # the resync '\n' ran before retry
    assert mgr.state == ConnectionState.IDLE
    mgr.stop()
