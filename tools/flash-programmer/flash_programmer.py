#!/usr/bin/env python3
"""
Flash Programmer for AT45DB021E DataFlash via Raspberry Pi GPIO
Reads RCF files and programs them to the flash chip.

Chip: AT45DB021E (Atmel/Adesto DataFlash)
  - 2-Mbit (256KB) capacity
  - 1024 pages
  - 264 bytes per page (default) or 256 bytes (power-of-2 mode)
  - Page-based addressing with internal SRAM buffers

GPIO Pin Connections:
    SCK  - GPIO27
    MISO - GPIO22
    MOSI - GPIO23
    CS   - GPIO4

AT45DB021E Commands:
    0xAB - Resume from Deep Power-Down
    0xB9 - Deep Power-Down
    0xD7 - Status Register Read
    0xD2 - Main Memory Page Read
    0x82 - Buffer 1 to Main Memory Page Program with Built-In Erase
    0x81 - Page Erase
    0x50 - Block Erase (2KB)
    0xC7 94 80 9A - Chip Erase (4-byte sequence)

Author: VestaRV Build System
Date: April 21, 2026
"""

import RPi.GPIO as GPIO
import time
import sys
import os
import argparse
from pathlib import Path

# GPIO Pin Definitions
PIN_SCK = 27
PIN_MISO = 22
PIN_MOSI = 23
PIN_CS = 4

# AT45DB021E DataFlash Commands
CMD_POWER_ON = 0xAB  # Resume from Deep Power-Down
CMD_POWER_DOWN = 0xB9  # Deep Power-Down
CMD_READ_STATUS = 0xD7  # Status Register Read
CMD_READ_ARRAY = 0xD2  # Main Memory Page Read
CMD_READ_ARRAY_FAST = 0x0B  # Continuous Array Read (Legacy)
CMD_BUF1_WRITE = 0x84  # Buffer 1 Write
CMD_BUF2_WRITE = 0x87  # Buffer 2 Write
CMD_BUF1_TO_PAGE_ERASE = 0x83  # Buffer 1 to Main Memory Page Program with Built-in Erase
CMD_BUF2_TO_PAGE_ERASE = 0x86  # Buffer 2 to Main Memory Page Program with Built-in Erase
CMD_PAGE_ERASE = 0x81  # Page Erase
CMD_BLOCK_ERASE = 0x50  # Block Erase
CMD_SECTOR_ERASE = 0x7C  # Sector Erase (multi-byte command)
CMD_CHIP_ERASE_SEQ = [0xC7, 0x94, 0x80, 0x9A]  # Chip Erase sequence

# AT45DB021E Parameters
# Note: AT45DB021E has 264-byte pages by default, but can be configured for 256-byte mode
# Status register bit 0 indicates: 0=264 bytes/page, 1=256 bytes/page
PAGE_SIZE = 264  # Default page size (will be detected from status register)
PAGE_SIZE_BINARY = 256  # Power-of-2 mode page size
PAGES_PER_BLOCK = 8  # 8 pages per block
TOTAL_PAGES = 1024  # Total pages in device
POWER_ON_DELAY = 0.000030  # 30us delay after power-on
WRITE_CYCLE_DELAY = 0.015  # 15ms max page program time
ERASE_PAGE_DELAY = 0.015  # 15ms max page erase time
ERASE_BLOCK_DELAY = 0.045  # 45ms max block erase time
ERASE_SECTOR_DELAY = 0.600  # 600ms max sector erase time (Sector 0a/0b)


class FlashProgrammer:
    """SPI Flash Programmer for Raspberry Pi"""
    
    def __init__(self, skip_ready_check=False):
        """Initialize GPIO and SPI interface
        
        Args:
            skip_ready_check: If True, skip waiting for flash ready (for debugging)
        """
        self.skip_ready_check = skip_ready_check
        self.page_size = PAGE_SIZE  # Will be detected later
        
        # Setup GPIO
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        
        # Configure SPI pins - setup one at a time with delays
        GPIO.setup(PIN_SCK, GPIO.OUT, initial=GPIO.LOW)
        time.sleep(0.001)
        GPIO.setup(PIN_MOSI, GPIO.OUT, initial=GPIO.LOW)
        time.sleep(0.001)
        GPIO.setup(PIN_MISO, GPIO.IN)
        time.sleep(0.001)
        GPIO.setup(PIN_CS, GPIO.OUT, initial=GPIO.HIGH)
        time.sleep(0.01)  # 10ms to let CS stabilize high
        
        self.powered_on = False
        
    def cleanup(self):
        """Release GPIO pins as floating inputs"""
        # Set CS high before releasing to avoid glitches
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.01)
        
        GPIO.setup(PIN_CS, GPIO.IN)
        GPIO.setup(PIN_SCK, GPIO.IN)
        GPIO.setup(PIN_MOSI, GPIO.IN)
        GPIO.setup(PIN_MISO, GPIO.IN)
        print("All SPI pins set to floating inputs")
    
    def test_cs_line(self):
        """Test CS line - toggle it a few times"""
        print("Testing CS line...")
        for i in range(5):
            print(f"  CS LOW (iteration {i+1})")
            GPIO.output(PIN_CS, GPIO.LOW)
            time.sleep(0.1)
            print(f"  CS HIGH (iteration {i+1})")
            GPIO.output(PIN_CS, GPIO.HIGH)
            time.sleep(0.1)
        print("CS test complete - check logic analyzer for clean transitions")
        
    def spi_transfer_byte(self, data):
        """
        Transfer one byte via SPI (bit-banged)
        Returns received byte
        """
        rx_data = 0
        
        for bit in range(8):
            # Set MOSI on falling edge
            if data & 0x80:
                GPIO.output(PIN_MOSI, GPIO.HIGH)
            else:
                GPIO.output(PIN_MOSI, GPIO.LOW)
            data <<= 1
            time.sleep(0.000001)  # 1us delay for setup time
            
            # Rising edge - slave samples MOSI
            GPIO.output(PIN_SCK, GPIO.HIGH)
            time.sleep(0.000001)  # 1us delay for hold time
            
            # Falling edge - sample MISO
            GPIO.output(PIN_SCK, GPIO.LOW)
            rx_data <<= 1
            if GPIO.input(PIN_MISO):
                rx_data |= 1
            time.sleep(0.000001)  # 1us delay between bits
                
        return rx_data
    
    def spi_command(self, cmd):
        """Send a single command byte"""
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(cmd)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        
    def power_on(self):
        """Power on the flash chip (release from deep power-down)"""
        print("Powering on flash chip...")
        self.spi_command(CMD_POWER_ON)
        time.sleep(POWER_ON_DELAY)
        self.powered_on = True
        print("Flash chip powered on")
        
    def power_down(self):
        """Put flash chip into deep power-down mode"""
        print("Powering down flash chip...")
        self.spi_command(CMD_POWER_DOWN)
        self.powered_on = False
        print("Flash chip powered down")
        
    def read_status(self):
        """Read status register
        
        Returns status byte:
            Bit 7: Ready/Busy (1=ready, 0=busy)
            Bit 6: Compare result
            Bit 5-2: Device density (0010 for 2-Mbit)
            Bit 1: Protection status
            Bit 0: Page size (1=256 bytes, 0=264 bytes)
        """
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_READ_STATUS)
        status = self.spi_transfer_byte(0x00)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        return status
    
    def detect_page_size(self):
        """Detect page size from status register"""
        status = self.read_status()
        page_size_bit = status & 0x01
        if page_size_bit:
            self.page_size = PAGE_SIZE_BINARY  # 256 bytes
            print(f"  Page size: 256 bytes (power-of-2 mode)")
        else:
            self.page_size = PAGE_SIZE  # 264 bytes
            print(f"  Page size: 264 bytes (default mode)")
        return self.page_size
    
    def wait_ready(self, timeout=10.0):
        """Wait for flash to be ready (bit 7 of status register)"""
        if self.skip_ready_check:
            print("  [DEBUG] Skipping ready check")
            return True
        
        start_time = time.time()
        while True:
            status = self.read_status()
            if status & 0x80:  # Ready bit (bit 7)
                return True
            if time.time() - start_time > timeout:
                return False
            time.sleep(0.001)
    
    def chip_erase(self):
        """Erase entire chip using AT45DB021E chip erase sequence"""
        print("Erasing entire flash chip...")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        for cmd_byte in CMD_CHIP_ERASE_SEQ:
            self.spi_transfer_byte(cmd_byte)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        print("Waiting for chip erase to complete (up to 20s)...")
        if not self.wait_ready(timeout=25.0):
            raise Exception("Chip erase timeout")
        print("Chip erase complete")
        
    def page_erase(self, page_num):
        """Erase a single page in AT45DB021E
        
        Args:
            page_num: Page number (0-1023 for AT45DB021E)
        """
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_PAGE_ERASE)
        # AT45DB021E uses page addressing: PA9-PA0 (10 bits)
        self.spi_transfer_byte((page_num >> 7) & 0x07)  # Upper 3 bits of page address
        self.spi_transfer_byte((page_num << 1) & 0xFE)  # Lower 7 bits of page address
        self.spi_transfer_byte(0x00)  # Don't care byte
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        
        if not self.wait_ready(timeout=ERASE_PAGE_DELAY + 0.1):
            raise Exception(f"Page erase timeout at page {page_num}")
    
    def page_program(self, page_num, data):
        """Program one page using Buffer 1 with built-in erase (AT45DB021E)
        
        Args:
            page_num: Page number (0-1023)
            data: Data to write (up to self.page_size bytes)
        """
        if len(data) > self.page_size:
            raise ValueError(f"Data length {len(data)} exceeds page size {self.page_size}")
        
        # Use Buffer 1 to Main Memory Page Program with Built-In Erase (0x82)
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_BUF1_TO_PAGE_ERASE)
        # AT45DB021E addressing: PA9-PA0 for page, then buffer address
        self.spi_transfer_byte((page_num >> 7) & 0x07)  # Upper 3 bits of page
        self.spi_transfer_byte((page_num << 1) & 0xFE)  # Lower 7 bits of page
        self.spi_transfer_byte(0x00)  # Buffer byte address (start at 0)
        
        # Write data to buffer
        for byte in data:
            self.spi_transfer_byte(byte)
            
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        
        if not self.wait_ready(timeout=WRITE_CYCLE_DELAY + 0.1):
            raise Exception(f"Page program timeout at page {page_num}")
    
    def read_data(self, page_num, offset, length):
        """Read data from AT45DB021E main memory
        
        Args:
            page_num: Page number to read from
            offset: Byte offset within page
            length: Number of bytes to read
        """
        data = []
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_READ_ARRAY)
        # AT45DB021E addressing for page read
        self.spi_transfer_byte((page_num >> 7) & 0x07)  # Upper 3 bits of page
        self.spi_transfer_byte(((page_num << 1) & 0xFE) | ((offset >> 8) & 0x01))  # Lower 7 bits of page + upper bit of offset
        self.spi_transfer_byte(offset & 0xFF)  # Lower 8 bits of offset
        # 4 don't care bytes for Main Memory Page Read (0xD2)
        for _ in range(4):
            self.spi_transfer_byte(0x00)
        
        # Read data
        for _ in range(length):
            data.append(self.spi_transfer_byte(0x00))
            
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        return bytes(data)
    
    def program_flash(self, data, start_address=0x0000, erase_before_write=True):
        """Program flash with binary data using AT45DB021E page-based architecture
        
        Args:
            data: bytes to write
            start_address: starting byte address in flash (will be converted to page/offset)
            erase_before_write: if True, erase pages before programming
        """
        if not self.powered_on:
            raise Exception("Flash chip not powered on")
        
        total_bytes = len(data)
        print(f"Programming {total_bytes} bytes starting at address 0x{start_address:06X}")
        print(f"Using page size: {self.page_size} bytes")
        
        # Convert byte address to page number and offset
        start_page = start_address // self.page_size
        start_offset = start_address % self.page_size
        
        # Calculate total pages needed
        end_address = start_address + total_bytes - 1
        end_page = end_address // self.page_size
        total_pages = end_page - start_page + 1
        
        print(f"Pages {start_page} to {end_page} ({total_pages} pages total)")
        
        # Note: For AT45DB021E, we use Buffer 1 to Main Memory Page Program
        # with Built-In Erase (0x82), so no separate erase step is needed
        if erase_before_write:
            print("Note: Using built-in erase during page program (AT45DB021E feature)")
        
        # Program pages
        print("Programming pages...")
        data_offset = 0
        page_num = start_page
        
        while data_offset < total_bytes:
            # Calculate how much data to write in this page
            if page_num == start_page and start_offset > 0:
                # First page with offset
                bytes_to_write = min(self.page_size - start_offset, total_bytes - data_offset)
                # For partial pages, we need to read-modify-write
                print(f"  Page {page_num}: Writing {bytes_to_write} bytes at offset {start_offset} (partial page)")
            else:
                bytes_to_write = min(self.page_size, total_bytes - data_offset)
                print(f"  Page {page_num}: Writing {bytes_to_write} bytes")
            
            # Extract data for this page
            page_data = data[data_offset:data_offset + bytes_to_write]
            
            # Program the page (built-in erase)
            self.page_program(page_num, page_data)
            
            data_offset += bytes_to_write
            page_num += 1
        
        print("Programming complete")
    
    def verify_flash(self, expected_data, start_address=0x0000):
        """Verify flash contents match expected data"""
        print(f"Verifying {len(expected_data)} bytes...")
        
        # Convert byte address to page/offset
        start_page = start_address // self.page_size
        start_offset = start_address % self.page_size
        total_bytes = len(expected_data)
        
        # Read all data
        read_data = bytearray()
        bytes_remaining = total_bytes
        current_page = start_page
        current_offset = start_offset
        
        while bytes_remaining > 0:
            bytes_to_read = min(self.page_size - current_offset, bytes_remaining)
            page_data = self.read_data(current_page, current_offset, bytes_to_read)
            read_data.extend(page_data)
            bytes_remaining -= bytes_to_read
            current_page += 1
            current_offset = 0  # After first page, start at offset 0
        
        # Compare
        mismatches = 0
        for i, (expected, actual) in enumerate(zip(expected_data, read_data)):
            if expected != actual:
                print(f"  Mismatch at 0x{start_address + i:06X}: expected 0x{expected:02X}, got 0x{actual:02X}")
                mismatches += 1
                if mismatches >= 10:
                    print("  ... (more mismatches)")
                    break
        
        if mismatches == 0:
            print("Verification passed!")
            return True
        else:
            print(f"Verification failed: {mismatches} mismatches")
            return False


def read_rcf_file(rcf_path):
    """
    Read RCF file and convert to binary data
    RCF format: 32-bit binary strings (ASCII '0' and '1'), one word per line
    """
    print(f"Reading RCF file: {rcf_path}")
    binary_data = bytearray()
    
    with open(rcf_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if len(line) != 32:
                raise ValueError(f"Line {line_num}: expected 32 bits, got {len(line)}")
            
            # Convert binary string to 32-bit word
            try:
                word = int(line, 2)
            except ValueError:
                raise ValueError(f"Line {line_num}: invalid binary data: {line}")
            
            # Convert to bytes (little-endian)
            binary_data.extend([
                (word >> 0) & 0xFF,
                (word >> 8) & 0xFF,
                (word >> 16) & 0xFF,
                (word >> 24) & 0xFF
            ])
    
    print(f"Read {len(binary_data)} bytes from RCF file")
    return bytes(binary_data)


def main():
    """Main program entry point"""
    parser = argparse.ArgumentParser(
        description='Program TI serial flash chip via Raspberry Pi GPIO',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''Examples:
  sudo python3 flash_programmer.py firmware.rcf
  sudo python3 flash_programmer.py firmware.rcf 0x1000
  sudo python3 flash_programmer.py firmware.rcf --no-wait  # Debug mode
''')
    parser.add_argument('rcf_file', help='Path to the .rcf file to program')
    parser.add_argument('start_address', nargs='?', default='0x0000',
                        help='Starting flash address (default: 0x0000)')
    parser.add_argument('--no-wait', action='store_true',
                        help='Skip waiting for flash ready (for logic analyzer debugging)')
    
    args = parser.parse_args()
    
    rcf_file = args.rcf_file
    start_address = int(args.start_address, 0)
    
    if not os.path.exists(rcf_file):
        print(f"Error: RCF file not found: {rcf_file}")
        sys.exit(1)
    
    if args.no_wait:
        print("[DEBUG MODE] Flash ready checks disabled for logic analyzer debugging\n")
    
    programmer = None
    try:
        # Read RCF file
        data = read_rcf_file(rcf_file)
        
        # Initialize programmer
        programmer = FlashProgrammer(skip_ready_check=args.no_wait)
        
        # Power on flash
        programmer.power_on()
        
        # Wait for ready
        print("Waiting for flash ready...")
        if not programmer.wait_ready():
            raise Exception("Flash not ready after power-on")
        
        # Read status and detect page size
        status = programmer.read_status()
        print(f"Flash status: 0x{status:02X}")
        print(f"  Ready/Busy: {'Ready' if status & 0x80 else 'Busy'}")
        print(f"  Device density: {(status >> 2) & 0x0F:04b} (should be 0010 for AT45DB021E)")
        programmer.detect_page_size()
        
        # Program flash
        programmer.program_flash(data, start_address, erase_before_write=True)
        
        # Verify
        programmer.verify_flash(data, start_address)
        
        # Power down
        programmer.power_down()
        
        print("\nFlash programming completed successfully!")
        
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if programmer:
            programmer.cleanup()
        GPIO.cleanup()


if __name__ == "__main__":
    main()
