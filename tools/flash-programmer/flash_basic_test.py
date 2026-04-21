#!/usr/bin/env python3
"""
Basic AT45DB021E Flash Test via Forth over UART
================================================
Performs the minimal write/read test by sending only the two basic Forth
primitives (`!` and `@`) that the forth_dashboard uses:

    Write register :  $VALUE $ADDR !
    Read  register :  $ADDR @ .

Hardware:
    - VestaRV chip, SPI0 @ 0x4200
    - AT45DB021E DataFlash, CS driven by GPIO0.0
    - GPIO0 @ 0x4000 (OUTS=$4008 sets bit, OUTC=$400C clears bit)

Test:
    1. Init SPI0 (Master, EN, MSB, BR=4, mode 0)
    2. Read manufacturer ID -> expect 0x1F
    3. Write 0xDEADBEEF (EF BE AD DE) to Buffer 1 at offset 0
    4. Program Buffer 1 -> Page 0 (built-in erase, cmd 0x83)
    5. Poll status until ready (bit 7 = 1)
    6. Read 4 bytes back from Page 0 -> expect EF BE AD DE
    7. Print PASS / FAIL

Usage:
    python3 flash_basic_test.py                    # default /dev/ttyAMA0
    python3 flash_basic_test.py /dev/ttyUSB0
    python3 flash_basic_test.py -q                 # quiet (less UART logging)
"""

import sys
import time
import serial


# -------- Register addresses --------
SPI0_CR  = 0x4200
SPI0_SR  = 0x4204
SPI0_TX  = 0x4208
SPI0_RX  = 0x420C

GPIO0_OUTS = 0x4008   # write 1s to set bits high
GPIO0_OUTC = 0x400C   # write 1s to clear bits low

CS_MASK = 1 << 0      # GPIO0.0 = flash CS

# -------- SPI config --------
# Bit 18 SM=1 (master), bit 7 EN=1, bit 6 MSB=1, BR=4 (bits 15-8), CPOL=0, CPHA=0
SPI_CR_VAL = 0x404C0

# -------- Flash commands --------
CMD_READ_ID        = 0x9F
CMD_READ_STATUS    = 0xD7
CMD_BUF1_WRITE     = 0x84
CMD_BUF1_TO_PAGE   = 0x83
CMD_PAGE_READ      = 0xD2

# Test data
TEST_BYTES = [0xEF, 0xBE, 0xAD, 0xDE]   # 0xDEADBEEF little-endian


# ANSI colors for pretty terminal output
class C:
    RESET  = "\033[0m"
    BOLD   = "\033[1m"
    DIM    = "\033[2m"
    RED    = "\033[31m"
    GREEN  = "\033[32m"
    YELLOW = "\033[33m"
    BLUE   = "\033[34m"
    CYAN   = "\033[36m"


class ForthUART:
    """Minimal UART/Forth interface - only uses ! and @ ."""

    def __init__(self, port, baud=115200, verbose=True):
        self.verbose = verbose
        self.uart = serial.Serial(
            port=port, baudrate=baud,
            bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE, timeout=0.1,
            xonxoff=False, rtscts=False, dsrdtr=False,
        )
        print(f"{C.GREEN}✓{C.RESET} UART opened on {port} @ {baud}")

    def close(self):
        if self.uart:
            self.uart.close()

    # ------- raw command transport -------
    def _send(self, cmd):
        if self.uart.in_waiting:
            self.uart.reset_input_buffer()
            time.sleep(0.005)

        if self.verbose:
            print(f"  {C.CYAN}TX>{C.RESET} {cmd}")

        self.uart.write((cmd + "\n").encode("utf-8"))
        self.uart.flush()
        time.sleep(0.03)

        resp = b""
        t0 = time.time()
        t_last = t0
        while time.time() - t0 < 0.5:
            if self.uart.in_waiting:
                chunk = self.uart.read(self.uart.in_waiting)
                resp += chunk
                t_last = time.time()
                if b">" in chunk:
                    break
                time.sleep(0.005)
            elif resp and (time.time() - t_last) > 0.05:
                break
            else:
                time.sleep(0.005)

        text = resp.decode("utf-8", errors="replace").strip()
        if self.verbose:
            printable = text.replace("\n", " | ").replace("\r", "")
            print(f"  {C.YELLOW}RX<{C.RESET} {printable}")
        return text

    @staticmethod
    def _parse_number(resp):
        """Extract first numeric token from Forth response (handles '?' prefix)."""
        for line in resp.split("\n"):
            tok = line.strip().lstrip("?").strip()
            if tok.startswith("$"):
                try:
                    return int(tok[1:], 16)
                except ValueError:
                    pass
            # try decimal token (split on whitespace, take first)
            parts = tok.split()
            if parts and parts[0].lstrip("-").isdigit():
                try:
                    return int(parts[0])
                except ValueError:
                    pass
        return None

    # ------- the only two Forth primitives we use -------
    def write(self, addr, value):
        """Forth:  $VALUE $ADDR !"""
        self._send(f"${value:X} ${addr:X} !")

    def read(self, addr):
        """Forth:  $ADDR @ .   -> returns integer"""
        resp = self._send(f"${addr:X} @ .")
        return self._parse_number(resp)


# ============================================================================
# SPI helpers built on top of read/write
# ============================================================================

def cs_low(f):
    f.write(GPIO0_OUTC, CS_MASK)

def cs_high(f):
    f.write(GPIO0_OUTS, CS_MASK)

def spi_wait_ready(f, timeout=1.0):
    """Poll SPI status until BUSY (bit 2) clears."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        sr = f.read(SPI0_SR)
        if sr is not None and (sr & 0x04) == 0:
            return True
    return False

def spi_xfer(f, tx_byte):
    """Send one byte, return RX byte (masked to 8 bits)."""
    f.write(SPI0_TX, tx_byte & 0xFF)
    spi_wait_ready(f)
    rx = f.read(SPI0_RX)
    return (rx & 0xFF) if rx is not None else 0


# ============================================================================
# Test steps
# ============================================================================

def step(title):
    print(f"\n{C.BOLD}{C.BLUE}--- {title} ---{C.RESET}")

def init_spi(f):
    step("Step 1: Init SPI0 and CS")
    # Set CS high (inactive) first - GPIO0.0 is already an output after reset
    cs_high(f)
    # Configure SPI0
    f.write(SPI0_CR, SPI_CR_VAL)
    print(f"{C.GREEN}✓{C.RESET} SPI0 CR = 0x{SPI_CR_VAL:05X} (Master, EN, MSB, BR=4, mode 0)")

def read_manufacturer_id(f):
    step("Step 2: Read Manufacturer ID (expect 0x1F)")
    cs_low(f)
    spi_xfer(f, CMD_READ_ID)
    mfg  = spi_xfer(f, 0x00)
    dev1 = spi_xfer(f, 0x00)
    dev2 = spi_xfer(f, 0x00)
    cs_high(f)
    print(f"  Manufacturer ID : 0x{mfg:02X}")
    print(f"  Device ID       : 0x{dev1:02X} 0x{dev2:02X}")
    if mfg == 0x1F:
        print(f"{C.GREEN}✓{C.RESET} Atmel/Adesto manufacturer ID confirmed")
        return True
    print(f"{C.RED}✗{C.RESET} Expected 0x1F, got 0x{mfg:02X}")
    return False

def write_buffer1(f, data):
    step(f"Step 3: Write {len(data)} bytes to Buffer 1 (cmd 0x84)")
    cs_low(f)
    spi_xfer(f, CMD_BUF1_WRITE)
    spi_xfer(f, 0x00)   # addr byte 0
    spi_xfer(f, 0x00)   # addr byte 1
    spi_xfer(f, 0x00)   # addr byte 2 (offset 0)
    for i, b in enumerate(data):
        spi_xfer(f, b)
        print(f"  wrote byte {i}: 0x{b:02X}")
    cs_high(f)
    print(f"{C.GREEN}✓{C.RESET} Data loaded into Buffer 1")

def program_buffer_to_page(f, page=0):
    step(f"Step 4: Program Buffer 1 -> Page {page} (cmd 0x83, with erase)")
    a0 = (page >> 7) & 0x07
    a1 = (page << 1) & 0xFE
    a2 = 0x00
    cs_low(f)
    spi_xfer(f, CMD_BUF1_TO_PAGE)
    spi_xfer(f, a0)
    spi_xfer(f, a1)
    spi_xfer(f, a2)
    cs_high(f)
    print(f"  address bytes: 0x{a0:02X} 0x{a1:02X} 0x{a2:02X}")
    print(f"  {C.DIM}(programming takes ~15 ms...){C.RESET}")

def wait_flash_ready(f, timeout_ms=200):
    step("Step 5: Poll flash status until ready (bit 7 = 1)")
    t0 = time.time()
    attempts = 0
    while (time.time() - t0) * 1000 < timeout_ms:
        cs_low(f)
        spi_xfer(f, CMD_READ_STATUS)
        status = spi_xfer(f, 0x00)
        cs_high(f)
        attempts += 1
        print(f"  attempt {attempts}: status = 0x{status:02X} "
              f"(ready={bool(status & 0x80)})")
        if status & 0x80:
            print(f"{C.GREEN}✓{C.RESET} Flash ready after {attempts} polls")
            return True
        time.sleep(0.005)
    print(f"{C.RED}✗{C.RESET} Timeout waiting for flash ready")
    return False

def read_page(f, page=0, offset=0, nbytes=4):
    step(f"Step 6: Read {nbytes} bytes from Page {page} offset {offset} (cmd 0xD2)")
    a0 = (page >> 7) & 0x07
    a1 = ((page & 0x7F) << 1) | ((offset >> 8) & 0x01)
    a2 = offset & 0xFF
    cs_low(f)
    spi_xfer(f, CMD_PAGE_READ)
    spi_xfer(f, a0)
    spi_xfer(f, a1)
    spi_xfer(f, a2)
    for _ in range(4):       # 4 don't-care bytes per datasheet
        spi_xfer(f, 0x00)
    data = []
    for i in range(nbytes):
        b = spi_xfer(f, 0x00)
        data.append(b)
        print(f"  read byte {i}: 0x{b:02X}")
    cs_high(f)
    return data


# ============================================================================
# Main
# ============================================================================

def main():
    port = "/dev/ttyAMA0"
    verbose = True

    for arg in sys.argv[1:]:
        if arg in ("-q", "--quiet"):
            verbose = False
        elif arg in ("-h", "--help"):
            print(__doc__)
            return 0
        elif not arg.startswith("-"):
            port = arg

    print(f"{C.BOLD}{'='*60}{C.RESET}")
    print(f"{C.BOLD} AT45DB021E Basic Flash Test (via Forth/UART){C.RESET}")
    print(f"{C.BOLD}{'='*60}{C.RESET}")
    print(f"  Port   : {port}")
    print(f"  Verbose: {verbose}  (use -q to silence TX/RX logging)")

    try:
        f = ForthUART(port, verbose=verbose)
    except serial.SerialException as e:
        print(f"{C.RED}✗ Could not open {port}: {e}{C.RESET}")
        return 2

    ok = False
    try:
        init_spi(f)
        id_ok = read_manufacturer_id(f)
        write_buffer1(f, TEST_BYTES)
        program_buffer_to_page(f, page=0)
        time.sleep(0.020)          # give the chip ~20 ms before polling
        ready = wait_flash_ready(f)
        if not ready:
            raise RuntimeError("Flash never became ready")
        got = read_page(f, page=0, offset=0, nbytes=len(TEST_BYTES))

        print(f"\n{C.BOLD}--- Verification ---{C.RESET}")
        print(f"  Written: {' '.join(f'{b:02X}' for b in TEST_BYTES)}")
        print(f"  Read   : {' '.join(f'{b:02X}' for b in got)}")

        data_ok = (got == TEST_BYTES)
        ok = data_ok and id_ok

        print(f"\n{C.BOLD}{'='*60}{C.RESET}")
        if ok:
            print(f"{C.GREEN}{C.BOLD} ✓ PASS — Flash write/read verified{C.RESET}")
        else:
            if not id_ok:
                print(f"{C.RED}{C.BOLD} ✗ FAIL — Manufacturer ID mismatch{C.RESET}")
            if not data_ok:
                print(f"{C.RED}{C.BOLD} ✗ FAIL — Data readback mismatch{C.RESET}")
        print(f"{C.BOLD}{'='*60}{C.RESET}")

    except KeyboardInterrupt:
        print(f"\n{C.YELLOW}Interrupted by user{C.RESET}")
    except Exception as e:
        print(f"\n{C.RED}✗ Error: {e}{C.RESET}")
        import traceback; traceback.print_exc()
    finally:
        f.close()

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
