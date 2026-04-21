#!/usr/bin/env python3
"""
AT45DB021E DataFlash SPI Test Script
=====================================
Tests SPI0 communication with AT45DB021E DataFlash chip connected to VestaRV.

This script:
1. Initializes SPI0 peripheral
2. Reads manufacturer ID from flash
3. Writes test data (0xDEADBEEF) to flash Buffer 1
4. Programs Buffer 1 to Page 0 with erase
5. Reads back the data from Page 0
6. Verifies data integrity

Hardware:
- VestaRV RISC-V chip with SPI0 at base address 0x4200
- AT45DB021E DataFlash (2-Mbit, 264-byte pages)
- UART connection to Raspberry Pi
"""

import time
import serial
import sys


class FlashTester:
    """SPI Flash memory test interface"""
    
    # SPI0 Register addresses
    SPI0_BASE = 0x4200
    SPI0CR = 0x4200  # Control Register
    SPI0SR = 0x4204  # Status Register
    SPI0TX = 0x4208  # Transmit Register
    SPI0RX = 0x420C  # Receive Register
    
    # GPIO Registers (for manual CS control)
    # GPIO0 base = 0x4000, typical offsets:
    GPIO0_BASE = 0x4000
    GPIO0_DIR = 0x4000   # Direction register
    GPIO0_OUT = 0x4004   # Output data register
    GPIO0_SET = 0x4008   # Set bits (write 1 to set)
    GPIO0_CLR = 0x400C   # Clear bits (write 1 to clear)
    
    # AT45DB021E Commands
    CMD_READ_ID = 0x9F           # Read Manufacturer and Device ID
    CMD_READ_STATUS = 0xD7       # Read Status Register
    CMD_BUFFER1_WRITE = 0x84     # Buffer 1 Write
    CMD_BUFFER1_TO_PAGE = 0x83   # Buffer 1 to Main Memory Page Program with Built-in Erase
    CMD_PAGE_READ = 0xD2         # Main Memory Page Read
    
    # Test data
    TEST_WORD = 0xDEADBEEF
    TEST_BYTES = [0xEF, 0xBE, 0xAD, 0xDE]  # Little-endian byte order
    
    def __init__(self, port='/dev/ttyAMA0', baudrate=115200, verbose=False, cs_pin=None):
        """
        Initialize UART connection
        
        Args:
            port: Serial port device (default: /dev/ttyAMA0 for RPi 4)
            baudrate: UART baudrate (default: 115200)
            verbose: Enable verbose debugging output
            cs_pin: GPIO pin number for chip select (None = no CS control, e.g., 0-7 for GPIO0 pins)
        """
        self.uart = None
        self.verbose = verbose
        self.cs_pin = cs_pin
        
        try:
            self.uart = serial.Serial(
                port=port,
                baudrate=baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.1,
                xonxoff=False,
                rtscts=False,
                dsrdtr=False,
            )
            print(f"✓ UART connection established on {port} at {baudrate} baud")
            if cs_pin is not None:
                print(f"✓ Using GPIO0.{cs_pin} for chip select")
        except serial.SerialException as e:
            print(f"✗ Error: Could not open UART port {port}: {e}")
            sys.exit(1)
    
    def addr_to_forth(self, address):
        """Convert address to Forth hex format"""
        return f"${address:X}"
    
    def send_forth(self, command, expect_output=False):
        """
        Send a Forth command and return response
        
        Args:
            command: Forth command string
            expect_output: If True, wait for and parse numeric output
            
        Returns:
            Response string or parsed integer if expect_output=True
        """
        try:
            # Clear input buffer
            if self.uart.in_waiting > 0:
                self.uart.reset_input_buffer()
                time.sleep(0.01)
            
            # Debug: Print command being sent
            if self.verbose:
                print(f"  [TX] {command}")
            
            # Send command
            self.uart.write((command + '\n').encode('utf-8'))
            self.uart.flush()
            time.sleep(0.05)  # Wait for processing
            
            # Read response
            response = b''
            start_time = time.time()
            last_data_time = time.time()
            
            while time.time() - start_time < 0.5:
                if self.uart.in_waiting > 0:
                    chunk = self.uart.read(self.uart.in_waiting)
                    response += chunk
                    last_data_time = time.time()
                    
                    if b'>' in chunk:
                        break
                    time.sleep(0.01)
                elif response and time.time() - last_data_time > 0.05:
                    break
                else:
                    time.sleep(0.01)
            
            response_str = response.decode('utf-8', errors='replace').strip()
            
            # Debug: Print raw response
            if self.verbose:
                print(f"  [RX] {repr(response_str)}")
            
            if expect_output:
                # Parse numeric output from response
                # Look for hex numbers (starting with $ or ?$) or decimal numbers (possibly with ? prefix)
                lines = response_str.split('\n')
                for line in lines:
                    line = line.strip()
                    
                    # Remove leading ? if present (Forth output prefix)
                    if line.startswith('?'):
                        line = line[1:].strip()
                    
                    if line.startswith('$'):
                        # Hex number
                        try:
                            value = int(line[1:], 16)
                            if self.verbose:
                                print(f"  [PARSED] 0x{value:X} ({value})")
                            return value
                        except ValueError:
                            pass
                    elif line and line[0].isdigit():
                        # Decimal number
                        try:
                            value = int(line.split()[0])  # Take first token in case there's extra text
                            if self.verbose:
                                print(f"  [PARSED] {value} (0x{value:X})")
                            return value
                        except ValueError:
                            pass
                if self.verbose:
                    print(f"  [PARSED] None (no numeric output found)")
                return None
            
            return response_str
            
        except Exception as e:
            print(f"✗ UART error: {e}")
            return None
    
    def write_register(self, addr, value):
        """Write value to register"""
        cmd = f"{self.addr_to_forth(value)} {self.addr_to_forth(addr)} !"
        self.send_forth(cmd)
    
    def read_register(self, addr):
        """Read value from register"""
        cmd = f"{self.addr_to_forth(addr)} @ ."
        return self.send_forth(cmd, expect_output=True)
    
    def cs_low(self):
        """Assert chip select (drive CS pin LOW)"""
        if self.cs_pin is not None:
            # Clear the bit to drive pin low
            mask = 1 << self.cs_pin
            self.write_register(self.GPIO0_CLR, mask)
            if self.verbose:
                print(f"  [CS] Asserted (GPIO0.{self.cs_pin} = LOW)")
            time.sleep(0.001)  # Small delay after CS assertion
    
    def cs_high(self):
        """Deassert chip select (drive CS pin HIGH)"""
        if self.cs_pin is not None:
            # Set the bit to drive pin high
            mask = 1 << self.cs_pin
            self.write_register(self.GPIO0_SET, mask)
            if self.verbose:
                print(f"  [CS] Deasserted (GPIO0.{self.cs_pin} = HIGH)")
            time.sleep(0.001)  # Small delay after CS deassertion
    
    def spi_transfer_byte(self, byte_val):
        """
        Send one byte via SPI and return received byte
        
        Args:
            byte_val: Byte to transmit (0-255)
            
        Returns:
            Received byte value
        """
        if self.verbose:
            print(f"  [SPI] TX: 0x{byte_val:02X}")
        
        # Write byte to TX register
        self.write_register(self.SPI0TX, byte_val)
        
        # Wait for SPI to become not busy (bit 2 of status = 0)
        # Forth: BEGIN $4204 @ 4 AND 0= UNTIL
        timeout = 100
        busy_count = 0
        while timeout > 0:
            status = self.read_register(self.SPI0SR)
            if status is not None:
                if self.verbose and busy_count < 3:  # Only print first few status reads
                    print(f"  [SPI] Status: 0x{status:04X} (busy={bool(status & 0x04)})")
                    busy_count += 1
                if (status & 0x04) == 0:
                    break
            time.sleep(0.001)
            timeout -= 1
        
        if timeout == 0 and self.verbose:
            print(f"  [SPI] Warning: Timeout waiting for SPI ready")
        
        # Read received byte
        rx_val = self.read_register(self.SPI0RX)
        
        # Mask to byte (in case register returns more bits)
        rx_byte = (rx_val & 0xFF) if rx_val is not None else 0
        
        if self.verbose:
            print(f"  [SPI] RX: 0x{rx_byte:02X} (raw: 0x{rx_val:X})")
        
        return rx_byte
    
    def init_spi(self):
        """Initialize SPI0 peripheral and CS GPIO pin"""
        print("\n--- Initializing SPI0 ---")
        
        # Configure CS GPIO pin if specified
        if self.cs_pin is not None:
            # Set GPIO pin as output (set bit in direction register)
            mask = 1 << self.cs_pin
            dir_val = self.read_register(self.GPIO0_DIR)
            if dir_val is None:
                dir_val = 0
            new_dir = dir_val | mask
            self.write_register(self.GPIO0_DIR, new_dir)
            
            # Set CS high (inactive)
            self.cs_high()
            print(f"✓ GPIO0.{self.cs_pin} configured as output for CS")
        
        # SPI0CR configuration:
        # Bit 18: SM = 1 (Master mode)
        # Bit 7: EN = 1 (Enable)
        # Bit 6: MSB = 1 (MSB first)
        # Bits 15-8: BR = 4 (Baud rate divisor)
        # Bits 1-0: CPOL=0, CPHA=0 (SPI mode 0)
        # 
        # Value: 0x404C0 = 0100 0000 0100 1100 0000
        #   Bit 18 (0x40000) = 1 (Master)
        #   Bit 7 (0x80) = 1 (Enable)
        #   Bit 6 (0x40) = 1 (MSB first)
        #   Bits 15-8 (0x400) = 4 (BR divisor)
        
        spi_config = 0x404C0
        self.write_register(self.SPI0CR, spi_config)
        time.sleep(0.01)
        
        print(f"✓ SPI0 configured: Master mode, CPOL=0, CPHA=0, BR=4")
    
    def read_manufacturer_id(self):
        """Read and verify manufacturer ID"""
        print("\n--- Reading Manufacturer ID ---")
        
        # Assert CS
        self.cs_low()
        
        # Send Read ID command (0x9F)
        self.spi_transfer_byte(self.CMD_READ_ID)
        
        # Read 4 bytes of response
        # Byte 0: Manufacturer ID (should be 0x1F for Atmel)
        # Bytes 1-3: Device ID
        mfg_id = self.spi_transfer_byte(0x00)
        dev_id1 = self.spi_transfer_byte(0x00)
        dev_id2 = self.spi_transfer_byte(0x00)
        dev_id3 = self.spi_transfer_byte(0x00)
        
        # Deassert CS
        self.cs_high()
        
        print(f"Manufacturer ID: 0x{mfg_id:02X}")
        print(f"Device ID: 0x{dev_id1:02X} 0x{dev_id2:02X} 0x{dev_id3:02X}")
        
        if mfg_id == 0x1F:
            print("✓ Atmel/Adesto manufacturer ID confirmed")
            return True
        else:
            print(f"✗ Warning: Expected 0x1F, got 0x{mfg_id:02X}")
            return False
    
    def wait_flash_ready(self, timeout_ms=100):
        """
        Poll flash status register until ready (bit 7 = 1)
        
        Args:
            timeout_ms: Maximum wait time in milliseconds
            
        Returns:
            True if ready, False if timeout
        """
        start_time = time.time()
        
        while (time.time() - start_time) * 1000 < timeout_ms:
            # Assert CS, send Read Status command, deassert CS
            self.cs_low()
            self.spi_transfer_byte(self.CMD_READ_STATUS)
            status = self.spi_transfer_byte(0x00)
            self.cs_high()
            
            if status is not None and (status & 0x80):
                return True
            
            time.sleep(0.001)
        
        return False
    
    def write_buffer1(self, data_bytes):
        """
        Write data to Buffer 1 starting at offset 0
        
        Args:
            data_bytes: List of bytes to write
        """
        print(f"\n--- Writing {len(data_bytes)} bytes to Buffer 1 ---")
        
        # Assert CS
        self.cs_low()
        
        # Send Buffer 1 Write command (0x84)
        self.spi_transfer_byte(self.CMD_BUFFER1_WRITE)
        
        # Send 3 address bytes (all zeros for buffer offset 0)
        self.spi_transfer_byte(0x00)  # Don't care for buffer write
        self.spi_transfer_byte(0x00)  # Buffer address MSB
        self.spi_transfer_byte(0x00)  # Buffer address LSB
        
        # Write data bytes
        for i, byte_val in enumerate(data_bytes):
            self.spi_transfer_byte(byte_val)
            print(f"  Byte {i}: 0x{byte_val:02X}")
        
        # Deassert CS
        self.cs_high()
        
        print("✓ Data written to Buffer 1")
    
    def program_buffer_to_page(self, page_num):
        """
        Program Buffer 1 to a page in main memory with built-in erase
        
        Args:
            page_num: Page number (0-1023)
        """
        print(f"\n--- Programming Buffer 1 to Page {page_num} ---")
        
        # Assert CS
        self.cs_low()
        
        # Send Buffer 1 to Main Memory command (0x83)
        self.spi_transfer_byte(self.CMD_BUFFER1_TO_PAGE)
        
        # Send 3 address bytes for page address
        # Page address format (10 bits for page number):
        # Byte 0: bits 2-0 = PA9-PA7 (upper 3 bits of page)
        # Byte 1: bits 7-1 = PA6-PA0 (lower 7 bits of page), bit 0 = don't care
        # Byte 2: all don't care
        
        addr_byte0 = (page_num >> 7) & 0x07  # Upper 3 bits of page
        addr_byte1 = (page_num << 1) & 0xFE  # Lower 7 bits of page, shifted left
        addr_byte2 = 0x00                     # Don't care
        
        self.spi_transfer_byte(addr_byte0)
        self.spi_transfer_byte(addr_byte1)
        self.spi_transfer_byte(addr_byte2)
        
        # Deassert CS
        self.cs_high()
        
        print(f"  Address bytes: 0x{addr_byte0:02X} 0x{addr_byte1:02X} 0x{addr_byte2:02X}")
        print("  Waiting for programming to complete...")
        
        # Wait for programming to complete (typically ~15ms)
        time.sleep(0.020)  # 20ms delay
        
        if self.wait_flash_ready(timeout_ms=100):
            print("✓ Programming complete")
            return True
        else:
            print("✗ Programming timeout")
            return False
    
    def read_page(self, page_num, offset, num_bytes):
        """
        Read data from main memory page
        
        Args:
            page_num: Page number (0-1023)
            offset: Byte offset within page (0-263)
            num_bytes: Number of bytes to read
            
        Returns:
            List of bytes read
        """
        print(f"\n--- Reading {num_bytes} bytes from Page {page_num} offset {offset} ---")
        
        # Assert CS
        self.cs_low()
        
        # Send Main Memory Page Read command (0xD2)
        self.spi_transfer_byte(self.CMD_PAGE_READ)
        
        # Send 3 address bytes for page and offset
        # Address format:
        # Byte 0: bits 2-0 = PA9-PA7 (upper 3 bits of page)
        # Byte 1: bits 7-1 = PA6-PA0 (lower 7 bits of page), bit 0 = BA8 (offset MSB)
        # Byte 2: bits 7-0 = BA7-BA0 (offset LSB)
        
        addr_byte0 = (page_num >> 7) & 0x07          # Upper 3 bits of page
        addr_byte1 = ((page_num & 0x7F) << 1) | ((offset >> 8) & 0x01)  # Page bits + offset MSB
        addr_byte2 = offset & 0xFF                    # Offset LSB
        
        self.spi_transfer_byte(addr_byte0)
        self.spi_transfer_byte(addr_byte1)
        self.spi_transfer_byte(addr_byte2)
        
        # Send 4 don't care bytes (required by datasheet before data output)
        for _ in range(4):
            self.spi_transfer_byte(0x00)
        
        # Read data bytes
        data = []
        for i in range(num_bytes):
            byte_val = self.spi_transfer_byte(0x00)
            data.append(byte_val if byte_val is not None else 0)
            print(f"  Byte {i}: 0x{data[i]:02X}")
        
        # Deassert CS
        self.cs_high()
        
        return data
    
    def run_test(self):
        """Execute the complete flash test sequence"""
        print("\n" + "="*60)
        print("AT45DB021E DataFlash Test")
        print("="*60)
        
        # Step 1: Initialize SPI
        self.init_spi()
        
        # Step 2: Read manufacturer ID
        if not self.read_manufacturer_id():
            print("\n✗ WARNING: Manufacturer ID mismatch - continuing anyway")
        
        # Step 3: Write test data to Buffer 1
        print(f"\nTest data: 0x{self.TEST_WORD:08X}")
        self.write_buffer1(self.TEST_BYTES)
        
        # Step 4: Program Buffer 1 to Page 0
        if not self.program_buffer_to_page(0):
            print("\n✗ TEST FAILED: Programming timeout")
            return False
        
        # Step 5: Read back data from Page 0
        read_data = self.read_page(0, 0, 4)
        
        # Step 6: Verify data
        print("\n--- Verification ---")
        print(f"Written: {' '.join(f'{b:02X}' for b in self.TEST_BYTES)}")
        print(f"Read:    {' '.join(f'{b:02X}' for b in read_data)}")
        
        if read_data == self.TEST_BYTES:
            print("\n" + "="*60)
            print("✓ SUCCESS! Data verified correctly")
            print("="*60)
            return True
        else:
            print("\n" + "="*60)
            print("✗ FAILURE! Data mismatch")
            print("="*60)
            return False
    
    def close(self):
        """Close UART connection"""
        if self.uart:
            self.uart.close()
            print("\n✓ UART connection closed")


def main():
    """Main entry point"""
    # Default port for Raspberry Pi 4
    port = '/dev/ttyAMA0'
    verbose = False
    cs_pin = None
    
    # Parse command line arguments
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg in ['-v', '--verbose']:
            verbose = True
        elif arg in ['--cs']:
            if i + 1 < len(sys.argv):
                cs_pin = int(sys.argv[i + 1])
                i += 1
        elif not arg.startswith('-'):
            port = arg
        i += 1
    
    print(f"Using UART port: {port}")
    if verbose:
        print("Verbose debugging: ENABLED")
    if cs_pin is not None:
        print(f"Chip select: GPIO0.{cs_pin}")
    else:
        print("Chip select: Not controlled (WARNING: May not work without CS!)")
    print("(Usage: python3 test_flash_spi.py [port] [-v|--verbose] [--cs PIN])")
    print("  Example: python3 test_flash_spi.py /dev/ttyAMA0 --cs 0 -v")
    
    tester = FlashTester(port=port, verbose=verbose, cs_pin=cs_pin)
    
    try:
        success = tester.run_test()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        tester.close()


if __name__ == '__main__':
    main()
