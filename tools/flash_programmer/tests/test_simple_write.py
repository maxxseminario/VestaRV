#!/usr/bin/env python3
"""
Simple test to write and read a single word (4 bytes) to AT45DB021E flash.
This is for basic functionality testing.
"""

import RPi.GPIO as GPIO
import time
import sys

# GPIO Pin Definitions
PIN_SCK = 27
PIN_MISO = 22
PIN_MOSI = 23
PIN_CS = 4

# AT45DB021E Commands
CMD_POWER_ON = 0xAB
CMD_READ_STATUS = 0xD7
CMD_READ_ARRAY = 0xD2
CMD_BUF1_WRITE = 0x84
CMD_BUF1_TO_PAGE = 0x83

def spi_transfer_byte(byte_out):
    """Transfer one byte via bit-banged SPI, return received byte"""
    byte_in = 0
    for bit in range(7, -1, -1):
        # Set MOSI
        GPIO.output(PIN_MOSI, (byte_out >> bit) & 0x01)
        time.sleep(0.000001)  # 1us
        
        # Clock high
        GPIO.output(PIN_SCK, GPIO.HIGH)
        time.sleep(0.000001)  # 1us
        
        # Read MISO
        if GPIO.input(PIN_MISO):
            byte_in |= (1 << bit)
        
        # Clock low
        GPIO.output(PIN_SCK, GPIO.LOW)
        time.sleep(0.000001)  # 1us
    
    return byte_in

def read_status():
    """Read status register"""
    GPIO.output(PIN_CS, GPIO.LOW)
    time.sleep(0.000010)
    spi_transfer_byte(CMD_READ_STATUS)
    status = spi_transfer_byte(0x00)
    GPIO.output(PIN_CS, GPIO.HIGH)
    time.sleep(0.000010)
    return status

def wait_ready(timeout=5.0):
    """Wait for flash ready bit"""
    start = time.time()
    while time.time() - start < timeout:
        status = read_status()
        if status & 0x80:  # Ready bit
            return True
        time.sleep(0.001)
    return False

def write_buffer1(data):
    """Write data to Buffer 1 starting at offset 0"""
    GPIO.output(PIN_CS, GPIO.LOW)
    time.sleep(0.000010)
    spi_transfer_byte(CMD_BUF1_WRITE)
    # Address bytes: all zeros for buffer offset 0
    spi_transfer_byte(0x00)
    spi_transfer_byte(0x00)
    spi_transfer_byte(0x00)
    # Write data
    for byte in data:
        spi_transfer_byte(byte)
    GPIO.output(PIN_CS, GPIO.HIGH)
    time.sleep(0.000010)

def buffer1_to_page(page_num):
    """Transfer Buffer 1 to main memory page with built-in erase"""
    GPIO.output(PIN_CS, GPIO.LOW)
    time.sleep(0.000010)
    spi_transfer_byte(CMD_BUF1_TO_PAGE)
    # Page address (10 bits for AT45DB021E)
    spi_transfer_byte((page_num >> 7) & 0x07)
    spi_transfer_byte((page_num << 1) & 0xFE)
    spi_transfer_byte(0x00)
    GPIO.output(PIN_CS, GPIO.HIGH)
    time.sleep(0.000010)
    
    print(f"  Waiting for page program to complete...")
    if not wait_ready(timeout=1.0):
        raise Exception("Page program timeout")

def read_page(page_num, offset, length):
    """Read data from main memory page"""
    GPIO.output(PIN_CS, GPIO.LOW)
    time.sleep(0.000010)
    spi_transfer_byte(CMD_READ_ARRAY)
    # Page address
    spi_transfer_byte((page_num >> 7) & 0x07)
    spi_transfer_byte(((page_num << 1) & 0xFE) | ((offset >> 8) & 0x01))
    spi_transfer_byte(offset & 0xFF)
    # 4 don't care bytes
    for _ in range(4):
        spi_transfer_byte(0x00)
    # Read data
    data = []
    for _ in range(length):
        data.append(spi_transfer_byte(0x00))
    GPIO.output(PIN_CS, GPIO.HIGH)
    time.sleep(0.000010)
    return bytes(data)

def main():
    print("=" * 60)
    print("AT45DB021E Simple Write/Read Test")
    print("=" * 60)
    
    # Setup GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    GPIO.setup(PIN_SCK, GPIO.OUT, initial=GPIO.LOW)
    time.sleep(0.001)
    GPIO.setup(PIN_MOSI, GPIO.OUT, initial=GPIO.LOW)
    time.sleep(0.001)
    GPIO.setup(PIN_MISO, GPIO.IN)
    time.sleep(0.001)
    GPIO.setup(PIN_CS, GPIO.OUT, initial=GPIO.HIGH)
    time.sleep(0.010)
    
    try:
        # Test word to write (0xDEADBEEF in little-endian)
        test_word = 0xDEADBEEF
        test_data = bytes([
            (test_word >> 0) & 0xFF,
            (test_word >> 8) & 0xFF,
            (test_word >> 16) & 0xFF,
            (test_word >> 24) & 0xFF
        ])
        
        print(f"\nTest data: 0x{test_word:08X}")
        print(f"As bytes: {' '.join(f'{b:02X}' for b in test_data)}")
        
        # Power on (resume from deep power-down)
        print("\n[1] Powering on flash...")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)
        spi_transfer_byte(CMD_POWER_ON)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000030)  # 30us delay
        
        # Check status
        print("[2] Reading status register...")
        status = read_status()
        print(f"    Status: 0x{status:02X}")
        print(f"    Ready: {'Yes' if status & 0x80 else 'No'}")
        print(f"    Page size: {'256 bytes' if status & 0x01 else '264 bytes'}")
        
        if not (status & 0x80):
            print("    ERROR: Flash not ready!")
            return
        
        # Write to Buffer 1
        print("\n[3] Writing 4 bytes to Buffer 1...")
        write_buffer1(test_data)
        print(f"    Wrote: {' '.join(f'{b:02X}' for b in test_data)}")
        
        # Transfer Buffer 1 to Page 0
        print("\n[4] Programming Buffer 1 to Page 0 (with built-in erase)...")
        buffer1_to_page(0)
        print("    Page 0 programmed successfully")
        
        # Read back from Page 0
        print("\n[5] Reading 4 bytes from Page 0...")
        read_data = read_page(0, 0, 4)
        print(f"    Read:  {' '.join(f'{b:02X}' for b in read_data)}")
        
        # Verify
        print("\n[6] Verification:")
        if test_data == read_data:
            print("    ✓ SUCCESS! Data matches!")
            read_word = (read_data[0] | (read_data[1] << 8) | 
                        (read_data[2] << 16) | (read_data[3] << 24))
            print(f"    Read word: 0x{read_word:08X}")
        else:
            print("    ✗ FAILURE! Data mismatch!")
            print(f"    Expected: {' '.join(f'{b:02X}' for b in test_data)}")
            print(f"    Got:      {' '.join(f'{b:02X}' for b in read_data)}")
            for i, (expected, actual) in enumerate(zip(test_data, read_data)):
                if expected != actual:
                    print(f"    Byte {i}: expected 0x{expected:02X}, got 0x{actual:02X}")
        
        print("\n" + "=" * 60)
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Cleanup
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.010)
        GPIO.setup(PIN_CS, GPIO.IN)
        GPIO.setup(PIN_SCK, GPIO.IN)
        GPIO.setup(PIN_MOSI, GPIO.IN)
        GPIO.cleanup()

if __name__ == "__main__":
    main()
