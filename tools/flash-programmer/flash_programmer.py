#!/usr/bin/env python3
"""
Flash Programmer for TI Serial Flash via Raspberry Pi SPI
Reads RCF files and programs them to the flash chip.

GPIO Pin Connections:
    SCK  - GPIO27
    MISO - GPIO22
    MOSI - GPIO23
    CS   - GPIO4

Flash Commands (from serial_flash.vhd):
    0xAB - Power On (Release from Deep Power Down)
    0xB9 - Power Down
    0xD7 - Read Status Register
    0x03 - Read Data (Low Frequency)
    0x0B - Read Data (High Frequency)
    0x02 - Page Program
    0x06 - Write Enable
    0x04 - Write Disable
    0xC7 - Chip Erase
    0x20 - Sector Erase (4KB)
    0xD8 - Block Erase (64KB)

Author: VestaRV Build System
Date: April 21, 2026
"""

import RPi.GPIO as GPIO
import time
import sys
import os
from pathlib import Path

# GPIO Pin Definitions
PIN_SCK = 27
PIN_MISO = 22
PIN_MOSI = 23
PIN_CS = 4

# Flash Commands
CMD_POWER_ON = 0xAB
CMD_POWER_DOWN = 0xB9
CMD_READ_STATUS = 0xD7
CMD_READ_DATA = 0x03
CMD_READ_DATA_FAST = 0x0B
CMD_PAGE_PROGRAM = 0x02
CMD_WRITE_ENABLE = 0x06
CMD_WRITE_DISABLE = 0x04
CMD_CHIP_ERASE = 0xC7
CMD_SECTOR_ERASE = 0x20
CMD_BLOCK_ERASE = 0xD8

# Flash Parameters
PAGE_SIZE = 256  # Typical flash page size in bytes
SECTOR_SIZE = 4096  # 4KB sectors
BLOCK_SIZE = 65536  # 64KB blocks
POWER_ON_DELAY = 0.030  # 30us delay after power-on
WRITE_CYCLE_DELAY = 0.005  # 5ms typical page program time
ERASE_SECTOR_DELAY = 0.400  # 400ms typical sector erase time
ERASE_CHIP_DELAY = 20.0  # 20s typical chip erase time


class FlashProgrammer:
    """SPI Flash Programmer for Raspberry Pi"""
    
    def __init__(self):
        """Initialize GPIO and SPI interface"""
        # Setup GPIO
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        
        # Configure SPI pins
        GPIO.setup(PIN_CS, GPIO.OUT, initial=GPIO.HIGH)
        GPIO.setup(PIN_SCK, GPIO.OUT, initial=GPIO.LOW)
        GPIO.setup(PIN_MOSI, GPIO.OUT, initial=GPIO.LOW)
        GPIO.setup(PIN_MISO, GPIO.IN)
        
        self.powered_on = False
        
    def cleanup(self):
        """Release GPIO pins as floating inputs"""
        GPIO.setup(PIN_CS, GPIO.IN)
        GPIO.setup(PIN_SCK, GPIO.IN)
        GPIO.setup(PIN_MOSI, GPIO.IN)
        GPIO.setup(PIN_MISO, GPIO.IN)
        print("All SPI pins set to floating inputs")
        
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
        
    def spi_write_enable(self):
        """Enable writing to flash"""
        self.spi_command(CMD_WRITE_ENABLE)
        
    def spi_write_disable(self):
        """Disable writing to flash"""
        self.spi_command(CMD_WRITE_DISABLE)
        
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
        """Read status register"""
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_READ_STATUS)
        status = self.spi_transfer_byte(0x00)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        return status
    
    def wait_ready(self, timeout=10.0):
        """Wait for flash to be ready (bit 7 of status register)"""
        start_time = time.time()
        while True:
            status = self.read_status()
            if status & 0x80:  # Ready bit (bit 7)
                return True
            if time.time() - start_time > timeout:
                return False
            time.sleep(0.001)
    
    def chip_erase(self):
        """Erase entire chip"""
        print("Erasing entire flash chip...")
        self.spi_write_enable()
        self.spi_command(CMD_CHIP_ERASE)
        print(f"Waiting for chip erase to complete (up to {ERASE_CHIP_DELAY}s)...")
        if not self.wait_ready(timeout=ERASE_CHIP_DELAY + 5.0):
            raise Exception("Chip erase timeout")
        print("Chip erase complete")
        
    def sector_erase(self, address):
        """Erase a 4KB sector at the given address"""
        self.spi_write_enable()
        time.sleep(0.000100)  # 100us after write enable
        
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_SECTOR_ERASE)
        self.spi_transfer_byte((address >> 16) & 0xFF)
        self.spi_transfer_byte((address >> 8) & 0xFF)
        self.spi_transfer_byte(address & 0xFF)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        
        if not self.wait_ready(timeout=ERASE_SECTOR_DELAY + 1.0):
            raise Exception(f"Sector erase timeout at address 0x{address:06X}")
    
    def page_program(self, address, data):
        """
        Program one page (up to 256 bytes) at the given address
        Data must not cross page boundary
        """
        if len(data) > PAGE_SIZE:
            raise ValueError(f"Data length {len(data)} exceeds page size {PAGE_SIZE}")
        
        self.spi_write_enable()
        time.sleep(0.000100)  # 100us after write enable
        
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_PAGE_PROGRAM)
        self.spi_transfer_byte((address >> 16) & 0xFF)
        self.spi_transfer_byte((address >> 8) & 0xFF)
        self.spi_transfer_byte(address & 0xFF)
        
        for byte in data:
            self.spi_transfer_byte(byte)
            
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        
        if not self.wait_ready(timeout=WRITE_CYCLE_DELAY + 1.0):
            raise Exception(f"Page program timeout at address 0x{address:06X}")
    
    def read_data(self, address, length):
        """Read data from flash starting at address"""
        data = []
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)  # 10us CS setup time
        self.spi_transfer_byte(CMD_READ_DATA)
        self.spi_transfer_byte((address >> 16) & 0xFF)
        self.spi_transfer_byte((address >> 8) & 0xFF)
        self.spi_transfer_byte(address & 0xFF)
        
        for _ in range(length):
            data.append(self.spi_transfer_byte(0x00))
            
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)  # 10us CS hold time
        return bytes(data)
    
    def program_flash(self, data, start_address=0x0000, erase_before_write=True):
        """
        Program flash with binary data
        
        Args:
            data: bytes to write
            start_address: starting address in flash
            erase_before_write: if True, erase sectors before programming
        """
        if not self.powered_on:
            raise Exception("Flash chip not powered on")
        
        total_bytes = len(data)
        print(f"Programming {total_bytes} bytes starting at address 0x{start_address:06X}")
        
        # Calculate sectors to erase
        if erase_before_write:
            start_sector = start_address // SECTOR_SIZE
            end_sector = (start_address + total_bytes - 1) // SECTOR_SIZE
            sectors_to_erase = end_sector - start_sector + 1
            
            print(f"Erasing {sectors_to_erase} sectors...")
            for sector in range(start_sector, end_sector + 1):
                sector_addr = sector * SECTOR_SIZE
                print(f"  Erasing sector at 0x{sector_addr:06X}")
                self.sector_erase(sector_addr)
        
        # Program pages
        print("Programming pages...")
        address = start_address
        offset = 0
        
        while offset < total_bytes:
            # Calculate bytes to write in this page
            page_offset = address % PAGE_SIZE
            bytes_in_page = min(PAGE_SIZE - page_offset, total_bytes - offset)
            
            # Extract page data
            page_data = data[offset:offset + bytes_in_page]
            
            # Program page
            print(f"  Programming page at 0x{address:06X} ({bytes_in_page} bytes)")
            self.page_program(address, page_data)
            
            # Move to next page
            address += bytes_in_page
            offset += bytes_in_page
        
        print("Programming complete")
    
    def verify_flash(self, expected_data, start_address=0x0000):
        """Verify flash contents match expected data"""
        print(f"Verifying {len(expected_data)} bytes...")
        read_data = self.read_data(start_address, len(expected_data))
        
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
    if len(sys.argv) < 2:
        print("Usage: flash_programmer.py <rcf_file> [start_address]")
        print("  rcf_file: Path to RCF file to program")
        print("  start_address: Optional starting address (default: 0x0000)")
        sys.exit(1)
    
    rcf_file = sys.argv[1]
    start_address = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x0000
    
    if not os.path.exists(rcf_file):
        print(f"Error: RCF file not found: {rcf_file}")
        sys.exit(1)
    
    programmer = None
    try:
        # Read RCF file
        data = read_rcf_file(rcf_file)
        
        # Initialize programmer
        programmer = FlashProgrammer()
        
        # Power on flash
        programmer.power_on()
        
        # Wait for ready
        print("Waiting for flash ready...")
        if not programmer.wait_ready():
            raise Exception("Flash not ready after power-on")
        
        # Read status
        status = programmer.read_status()
        print(f"Flash status: 0x{status:02X}")
        
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
