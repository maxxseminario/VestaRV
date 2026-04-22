#!/usr/bin/env python3
"""
Send AT45DB021E flash test commands to VestaRV chip via UART.
This script sends Forth commands to test the flash chip connected to SPI0.
"""

import serial
import time
import sys

# UART Configuration
UART_PORT = '/dev/ttyAMA0'  # Raspberry Pi 4 UART (adjust for your system)
UART_BAUDRATE = 115200

# SPI0 Register Addresses
SPI0CR = 0x4200
SPI0SR = 0x4204
SPI0TX = 0x4208
SPI0RX = 0x420C

# AT45DB021E Commands
CMD_POWER_ON = 0xAB
CMD_READ_STATUS = 0xD7
CMD_READ_MFG_ID = 0x9F
CMD_BUF1_WRITE = 0x84
CMD_BUF1_TO_PAGE = 0x83
CMD_READ_ARRAY = 0xD2


class UARTInterface:
    """Simple UART interface for sending Forth commands"""
    
    def __init__(self, port=UART_PORT, baudrate=UART_BAUDRATE):
        """Initialize UART connection"""
        self.uart = None
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
            print(f"✓ Connected to {port} at {baudrate} baud")
        except serial.SerialException as e:
            print(f"✗ Error: Could not open UART port {port}: {e}")
            sys.exit(1)
    
    def send_command(self, command, expect_response=True):
        """Send a Forth command and get response
        
        Args:
            command: Forth command string
            expect_response: Wait for and return response
            
        Returns:
            Response string or None
        """
        if self.uart is None:
            return None
        
        try:
            # Clear input buffer
            if self.uart.in_waiting > 0:
                self.uart.reset_input_buffer()
                time.sleep(0.01)
            
            # Send command
            print(f"TX: {command}")
            self.uart.write((command + '\n').encode('utf-8'))
            self.uart.flush()
            
            if not expect_response:
                time.sleep(0.05)
                return None
            
            # Wait for response
            time.sleep(0.1)
            response = b''
            start_time = time.time()
            last_data_time = time.time()
            
            while time.time() - start_time < 0.5:
                if self.uart.in_waiting > 0:
                    chunk = self.uart.read(self.uart.in_waiting)
                    response += chunk
                    last_data_time = time.time()
                    
                    # Look for prompt
                    if b'>' in chunk:
                        break
                    time.sleep(0.01)
                elif response and time.time() - last_data_time > 0.05:
                    break
                else:
                    time.sleep(0.01)
            
            response_str = response.decode('utf-8', errors='replace').strip()
            if response_str:
                print(f"RX: {response_str}")
            
            return response_str
            
        except Exception as e:
            print(f"Error: {e}")
            return None
    
    def close(self):
        """Close UART connection"""
        if self.uart:
            self.uart.close()


def init_spi0(uart):
    """Initialize SPI0 for AT45DB021E"""
    print("\n" + "="*60)
    print("Initializing SPI0...")
    print("="*60)
    
    # SPI0 Control Register: Master, CPOL=0, CPHA=0, MSB first, 8-bit, BR=4
    cr_value = (1 << 7) | (1 << 6) | (4 << 8) | (1 << 18)
    uart.send_command(f"${cr_value:X} ${SPI0CR:X} !")
    print("✓ SPI0 initialized")


def spi_transfer(uart, byte_val, read_response=False):
    """Send a byte via SPI0 and optionally read response
    
    Args:
        uart: UART interface
        byte_val: Byte to send
        read_response: If True, read and return received byte
        
    Returns:
        Received byte value or None
    """
    # Send byte
    uart.send_command(f"${byte_val:X} ${SPI0TX:X} !", expect_response=False)
    
    # Wait for SPI ready (BUSY bit = 0)
    uart.send_command(f"BEGIN ${SPI0SR:X} @ 4 AND 0= UNTIL", expect_response=False)
    
    if read_response:
        # Read received byte
        response = uart.send_command(f"${SPI0RX:X} @ .")
        if response:
            # Parse the numeric value from response
            try:
                tokens = response.replace('?', '').split()
                for i, token in enumerate(tokens):
                    if token == '>' and i > 0:
                        return int(tokens[i-1], 0)
                # Fallback: find any number
                for token in reversed(tokens):
                    if token not in ['@', '.', '>']:
                        try:
                            return int(token, 0)
                        except ValueError:
                            continue
            except (ValueError, IndexError):
                pass
    return None


def read_manufacturer_id(uart):
    """Read manufacturer and device ID"""
    print("\n" + "-"*60)
    print("Reading Manufacturer ID (0x9F)...")
    print("-"*60)
    
    spi_transfer(uart, CMD_READ_MFG_ID, read_response=False)
    
    mfg_id = spi_transfer(uart, 0x00, read_response=True)
    dev_id1 = spi_transfer(uart, 0x00, read_response=True)
    dev_id2 = spi_transfer(uart, 0x00, read_response=True)
    ext_info = spi_transfer(uart, 0x00, read_response=True)
    
    print(f"  Manufacturer ID: 0x{mfg_id:02X}" + (" (Atmel/Microchip)" if mfg_id == 0x1F else ""))
    print(f"  Device ID 1:     0x{dev_id1:02X}")
    print(f"  Device ID 2:     0x{dev_id2:02X}")
    print(f"  Extended Info:   0x{ext_info:02X}")
    
    return mfg_id


def read_status(uart):
    """Read flash status register"""
    print("\n" + "-"*60)
    print("Reading Status Register (0xD7)...")
    print("-"*60)
    
    spi_transfer(uart, CMD_READ_STATUS, read_response=False)
    status = spi_transfer(uart, 0x00, read_response=True)
    
    if status is not None:
        print(f"  Status: 0x{status:02X} = 0b{status:08b}")
        print(f"    Bit 7 (Ready):   {(status >> 7) & 1}")
        print(f"    Bits 5-2 (Density): {(status >> 2) & 0x0F:04b} (should be 0010 for 2Mbit)")
        print(f"    Bit 0 (PageSize): {status & 1} ({'256' if status & 1 else '264'} bytes)")
    
    return status


def write_test_data(uart):
    """Write test word 0xDEADBEEF to Buffer 1"""
    print("\n" + "-"*60)
    print("Writing 0xDEADBEEF to Buffer 1...")
    print("-"*60)
    
    test_word = 0xDEADBEEF
    test_bytes = [
        (test_word >> 0) & 0xFF,
        (test_word >> 8) & 0xFF,
        (test_word >> 16) & 0xFF,
        (test_word >> 24) & 0xFF
    ]
    
    # Send Buffer 1 Write command
    spi_transfer(uart, CMD_BUF1_WRITE, read_response=False)
    
    # Send address bytes (offset 0)
    spi_transfer(uart, 0x00, read_response=False)
    spi_transfer(uart, 0x00, read_response=False)
    spi_transfer(uart, 0x00, read_response=False)
    
    # Send data bytes
    for i, byte_val in enumerate(test_bytes):
        print(f"  Byte {i}: 0x{byte_val:02X}")
        spi_transfer(uart, byte_val, read_response=False)
    
    print("✓ Data written to Buffer 1")


def program_to_page(uart, page_num=0):
    """Program Buffer 1 to main memory page with erase"""
    print("\n" + "-"*60)
    print(f"Programming Buffer 1 to Page {page_num}...")
    print("-"*60)
    
    # Send command
    spi_transfer(uart, CMD_BUF1_TO_PAGE, read_response=False)
    
    # Send page address
    addr_byte1 = (page_num >> 7) & 0x07
    addr_byte2 = (page_num << 1) & 0xFE
    addr_byte3 = 0x00
    
    spi_transfer(uart, addr_byte1, read_response=False)
    spi_transfer(uart, addr_byte2, read_response=False)
    spi_transfer(uart, addr_byte3, read_response=False)
    
    print("  Waiting for program to complete...")
    time.sleep(0.02)  # 15-20ms typical program time
    
    # Poll status until ready
    for i in range(50):  # Try up to 50 times (500ms)
        status = read_status(uart)
        if status and (status & 0x80):
            print(f"✓ Page {page_num} programmed (took ~{(i+1)*10}ms)")
            return True
        time.sleep(0.01)
    
    print("✗ Warning: Timeout waiting for program complete")
    return False


def read_from_page(uart, page_num=0, offset=0, num_bytes=4):
    """Read data from main memory page"""
    print("\n" + "-"*60)
    print(f"Reading {num_bytes} bytes from Page {page_num}, offset {offset}...")
    print("-"*60)
    
    # Send command
    spi_transfer(uart, CMD_READ_ARRAY, read_response=False)
    
    # Send page address
    addr_byte1 = (page_num >> 7) & 0x07
    addr_byte2 = ((page_num << 1) & 0xFE) | ((offset >> 8) & 0x01)
    addr_byte3 = offset & 0xFF
    
    spi_transfer(uart, addr_byte1, read_response=False)
    spi_transfer(uart, addr_byte2, read_response=False)
    spi_transfer(uart, addr_byte3, read_response=False)
    
    # Send 4 don't care bytes (required for 0xD2)
    for _ in range(4):
        spi_transfer(uart, 0x00, read_response=False)
    
    # Read data bytes
    data = []
    for i in range(num_bytes):
        byte_val = spi_transfer(uart, 0x00, read_response=True)
        data.append(byte_val if byte_val is not None else 0)
        print(f"  Byte {i}: 0x{data[i]:02X}")
    
    return data


def main():
    """Main test sequence"""
    print("\n" + "="*60)
    print("AT45DB021E Flash Test via SPI0/UART")
    print("="*60)
    
    # Connect to UART
    uart = UARTInterface()
    
    try:
        # Initialize SPI0
        init_spi0(uart)
        
        # Read manufacturer ID
        mfg_id = read_manufacturer_id(uart)
        if mfg_id != 0x1F:
            print(f"\n✗ Warning: Expected manufacturer ID 0x1F, got 0x{mfg_id:02X}")
            print("  Check SPI connections and flash chip power")
        
        # Read initial status
        status = read_status(uart)
        
        # Write test data
        write_test_data(uart)
        
        # Program to page 0
        program_to_page(uart, page_num=0)
        
        # Read back data
        read_data = read_from_page(uart, page_num=0, offset=0, num_bytes=4)
        
        # Verify
        print("\n" + "="*60)
        print("Verification:")
        print("="*60)
        expected = [0xEF, 0xBE, 0xAD, 0xDE]
        match = read_data == expected
        
        if match:
            print("✓ SUCCESS! Data matches!")
            print(f"  Expected: {' '.join(f'{b:02X}' for b in expected)}")
            print(f"  Read:     {' '.join(f'{b:02X}' for b in read_data)}")
        else:
            print("✗ FAILURE! Data mismatch!")
            print(f"  Expected: {' '.join(f'{b:02X}' for b in expected)}")
            print(f"  Read:     {' '.join(f'{b:02X}' for b in read_data)}")
            for i, (exp, act) in enumerate(zip(expected, read_data)):
                if exp != act:
                    print(f"  Byte {i}: expected 0x{exp:02X}, got 0x{act:02X}")
        
        print("="*60)
        
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        uart.close()
        print("\nUART connection closed")


if __name__ == "__main__":
    main()
