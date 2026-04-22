#!/usr/bin/env python3
"""
Simple SPI test script to verify GPIO connections
Run this with a logic analyzer attached to debug signal integrity
"""

import RPi.GPIO as GPIO
import time
import sys

# GPIO Pin Definitions (same as flash_programmer.py)
PIN_SCK = 27
PIN_MISO = 22
PIN_MOSI = 23
PIN_CS = 4

def test_cs_only():
    """Test just the CS line"""
    print("CS Line Test")
    print("=" * 50)
    print("Watch CS on logic analyzer - should see clean transitions")
    print()
    
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Setup CS
    print("Setting up CS as output, initial HIGH...")
    GPIO.setup(PIN_CS, GPIO.OUT, initial=GPIO.HIGH)
    time.sleep(0.5)
    print("CS should be stable HIGH now")
    time.sleep(1.0)
    
    # Toggle CS slowly
    for i in range(5):
        print(f"\nIteration {i+1}:")
        print("  CS → LOW")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.5)
        print("  CS → HIGH")
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.5)
    
    print("\nTest complete")
    GPIO.cleanup()

def test_spi_signals():
    """Test all SPI signals"""
    print("Full SPI Test")
    print("=" * 50)
    
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Setup all pins
    print("Setting up SPI pins...")
    GPIO.setup(PIN_SCK, GPIO.OUT, initial=GPIO.LOW)
    GPIO.setup(PIN_MOSI, GPIO.OUT, initial=GPIO.LOW)
    GPIO.setup(PIN_MISO, GPIO.IN)
    GPIO.setup(PIN_CS, GPIO.OUT, initial=GPIO.HIGH)
    time.sleep(0.5)
    
    # Send one byte
    print("\nSending byte 0xAB (Power On command)...")
    print("CS → LOW")
    GPIO.output(PIN_CS, GPIO.LOW)
    time.sleep(0.01)
    
    data = 0xAB
    for bit in range(8):
        # Set MOSI
        if data & 0x80:
            GPIO.output(PIN_MOSI, GPIO.HIGH)
        else:
            GPIO.output(PIN_MOSI, GPIO.LOW)
        data <<= 1
        time.sleep(0.001)
        
        # Clock high
        GPIO.output(PIN_SCK, GPIO.HIGH)
        time.sleep(0.001)
        
        # Clock low
        GPIO.output(PIN_SCK, GPIO.LOW)
        time.sleep(0.001)
    
    time.sleep(0.01)
    print("CS → HIGH")
    GPIO.output(PIN_CS, GPIO.HIGH)
    
    print("\nTest complete - check logic analyzer")
    print("You should see:")
    print("  - CS goes LOW")
    print("  - 8 clock pulses on SCK")
    print("  - MOSI shows: 10101011 (0xAB)")
    print("  - CS goes HIGH")
    
    time.sleep(0.5)
    GPIO.cleanup()

def main():
    if len(sys.argv) > 1 and sys.argv[1] == 'cs':
        test_cs_only()
    else:
        test_spi_signals()

if __name__ == "__main__":
    print("SPI Test Utility")
    print("Usage:")
    print("  sudo python3 test_spi.py      - Test full SPI transmission")
    print("  sudo python3 test_spi.py cs   - Test CS line only")
    print()
    
    if len(sys.argv) > 1:
        main()
    else:
        print("Choose test:")
        print("1. Full SPI test")
        print("2. CS line only")
        choice = input("Enter choice (1 or 2): ").strip()
        
        if choice == '1':
            test_spi_signals()
        elif choice == '2':
            test_cs_only()
        else:
            print("Invalid choice")
