"""Parser + builder tests.

NOTE on "real transcript lines": the recorded log
tools/debug/forth_dashboard/myshkin_commands.log contains ONLY sim-mode TX
lines (no genuine chip RX) -- see the escalation note in the WP2 report.  The
RX lines below are therefore reconstructed to the EXACT byte format the chip
emits, verified against:

    software/rv4th/src/rv4th.c  (case 6 '.', 28 'h.', 13 'hb.', 92 'mr', 83 'fe')
    software/rv4th/src/uart.c   (uart_puti signed decimal; uart_puth* UPPERCASE)

They also include the exact noise bytes (0x1a, '?') that v1's parser had to
strip (tools/debug/forth_dashboard/myshkin.py).  Real TX command strings ARE
lifted from the log to pin the builders.
"""

from server import forth


# --- command builders (pinned against real TX strings in the log) -----------

def test_builder_read_dec_matches_log_shape():
    # log line: "0x04B0C @ ." -> same numeric address, canonical hex form.
    cmd = forth.build_read_dec(0x04B0C)
    assert cmd.endswith("@ .")
    assert cmd.split()[0].lower() in ("0x4b0c", "0x04b0c")
    assert int(cmd.split()[0], 16) == 0x4B0C


def test_builder_write_matches_log_shape():
    # log line: "142 0x04C14 !"
    cmd = forth.build_write(0x04C14, 142)
    parts = cmd.split()
    assert parts[-1] == "!"
    assert int(parts[0], 0) == 142
    assert int(parts[1], 16) == 0x04C14


def test_builder_clk_matches_log():
    # log line: "3 1 clk ." -> time_sel=3 pushed first, clock_sel=1 (rv4th case 80)
    assert forth.build_clk(clock_sel=1, time_sel=3) == "3 1 clk ."


def test_builder_read_hex():
    assert forth.build_read_hex(0x4B00) == "0x4B00 @ h."


def test_builder_flash_erase_uses_key_123():
    assert forth.build_flash_erase(0x20000).startswith("123 ")
    assert forth.build_flash_erase(0x20000).endswith("fe .")


def test_builder_exec_stack_order():
    assert forth.build_exec(0x8200) == "0x8200 call0 ."
    assert forth.build_exec(0x8200, [1, 2]) == "0x1 0x2 0x8200 call2 ."


def test_builder_mr_and_me():
    assert forth.build_mr(1, 256, 0x10000) == "1 256 0x10000 mr"
    assert forth.build_erase(0x10000, 64) == "64 0x10000 me"


# --- '.' signed decimal parsing ---------------------------------------------

def test_parse_decimal_basic():
    assert forth.parse_decimal("124 ") == 124


def test_parse_decimal_negative():
    # from rv4th_terminal example: -500 75689 * . -> -37844500
    assert forth.parse_decimal("-37844500 ") == -37844500


def test_parse_decimal_strips_noise():
    # 0x1a (SUB) and '?' are the exact bytes v1 had to strip.
    assert forth.parse_decimal("\x1a124 ?") == 124


def test_parse_decimal_multiline_takes_last():
    assert forth.parse_decimal("\n8 \n") == 8


# --- 'h.' hex parsing (8 uppercase digits, no prefix) -----------------------

def test_parse_hex_word():
    assert forth.parse_hex_word("0000007B ") == 123


def test_parse_hex_word_high_bit():
    # h. is unsigned: 0x80000000 prints "80000000", not a negative decimal.
    assert forth.parse_hex_word("80000000 ") == 0x80000000


def test_parse_hex_word_with_prompt_leftover():
    assert forth.parse_hex_word("DEADBEEF \n") == 0xDEADBEEF


# --- fe flag ----------------------------------------------------------------

def test_parse_bool():
    assert forth.parse_bool("1 ") is True
    assert forth.parse_bool("0 ") is False


# --- mr ascii payload + CRC -------------------------------------------------

def test_parse_hexdump_slices_payload():
    # mr mode 0: 4 payload bytes then a 4-hex CRC; parse_hexdump ignores the CRC.
    payload = bytes([0x01, 0x02, 0x03, 0x04])
    crc = forth.crc16_cdma2000(payload)
    line = "01020304%04X " % crc
    assert forth.parse_hexdump(line, 4) == payload


def test_parse_mr_ascii_returns_payload_and_crc():
    payload = bytes(range(8))
    crc = forth.crc16_cdma2000(payload)
    line = payload.hex().upper() + ("%04X" % crc)
    got_payload, got_crc = forth.parse_mr_ascii(line, 8)
    assert got_payload == payload
    assert got_crc == crc


# --- 32-bit helpers + CRC ---------------------------------------------------

def test_to_i32_wraps():
    assert forth.to_i32(0xFFFFFFFF) == -1
    assert forth.to_i32(0x80000000) == -2147483648
    assert forth.to_i32(0x7FFFFFFF) == 2147483647


def test_to_u32():
    assert forth.to_u32(-1) == 0xFFFFFFFF


def test_crc16_is_deterministic_and_ranged():
    crc = forth.crc16_cdma2000(b"\x00" * 256)
    assert 0 <= crc <= 0xFFFF
    assert forth.crc16_cdma2000(b"hello") == forth.crc16_cdma2000(b"hello")
    assert forth.crc16_cdma2000(b"hello") != forth.crc16_cdma2000(b"hellp")


def test_banner_detection():
    assert forth.contains_banner("myshkin rv4th-rom!\n")
    assert not forth.contains_banner("just a prompt >")
