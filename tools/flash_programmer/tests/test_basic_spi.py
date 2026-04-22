#!/usr/bin/env python3
"""
Basic SPI diagnostic test for AT45DB021E
Tests fundamental communication before attempting write/read
"""

import RPi.GPIO as GPIO
import time

# GPIO Pin Definitions
PIN_SCK = 27
PIN_MISO = 22
PIN_MOSI = 23
PIN_CS = 4

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

def main():
    print("=" * 60)
    print("AT45DB021E SPI Diagnostics")
    print("=" * 60)
    
    # Setup GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    GPIO.setup(PIN_SCK, GPIO.OUT, initial=GPIO.LOW)
    GPIO.setup(PIN_MOSI, GPIO.OUT, initial=GPIO.LOW)
    GPIO.setup(PIN_MISO, GPIO.IN)
    GPIO.setup(PIN_CS, GPIO.OUT, initial=GPIO.HIGH)
    time.sleep(0.010)
    
    try:
        # Test 1: Check MISO idle state
        print("\n[Test 1] MISO idle state (CS=HIGH)")
        miso_readings = []
        for i in range(10):
            miso_readings.append(GPIO.input(PIN_MISO))
            time.sleep(0.001)
        miso_high_count = sum(miso_readings)
        print(f"  MISO readings: {miso_readings}")
        print(f"  High: {miso_high_count}/10, Low: {10-miso_high_count}/10")
        if miso_high_count == 10:
            print("  ⚠ WARNING: MISO stuck HIGH (could be pull-up or no chip)")
        elif miso_high_count == 0:
            print("  ⚠ WARNING: MISO stuck LOW")
        else:
            print("  ✓ MISO appears to be floating (normal when CS=HIGH)")
        
        # Test 2: Check MISO with CS active
        print("\n[Test 2] MISO state with CS=LOW (chip selected)")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000100)
        miso_readings = []
        for i in range(10):
            miso_readings.append(GPIO.input(PIN_MISO))
            time.sleep(0.001)
        GPIO.output(PIN_CS, GPIO.HIGH)
        miso_high_count = sum(miso_readings)
        print(f"  MISO readings: {miso_readings}")
        print(f"  High: {miso_high_count}/10, Low: {10-miso_high_count}/10")
        
        # Test 3: Try to read Manufacturer and Device ID (0x9F)
        print("\n[Test 3] Read Manufacturer/Device ID (cmd 0x9F)")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)
        spi_transfer_byte(0x9F)  # Manufacturer/Device ID command
        mfg_id = spi_transfer_byte(0x00)
        dev_id1 = spi_transfer_byte(0x00)
        dev_id2 = spi_transfer_byte(0x00)
        ext_info = spi_transfer_byte(0x00)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)
        
        print(f"  Manufacturer ID: 0x{mfg_id:02X}")
        print(f"  Device ID 1:     0x{dev_id1:02X}")
        print(f"  Device ID 2:     0x{dev_id2:02X}")
        print(f"  Extended Info:   0x{ext_info:02X}")
        
        if mfg_id == 0xFF and dev_id1 == 0xFF:
            print("  ✗ All 0xFF - chip not responding or MISO issue")
        elif mfg_id == 0x1F:
            print("  ✓ Atmel/Microchip manufacturer ID detected!")
        else:
            print(f"  ? Unexpected manufacturer ID")
        
        # Test 4: Read Status Register (0xD7)
        print("\n[Test 4] Read Status Register (cmd 0xD7)")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)
        spi_transfer_byte(0xD7)
        status = spi_transfer_byte(0x00)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)
        
        print(f"  Status: 0x{status:02X} = 0b{status:08b}")
        if status == 0xFF:
            print("  ✗ Reading 0xFF - likely MISO problem")
        else:
            print(f"  Bit 7 (Ready):     {(status >> 7) & 1}")
            print(f"  Bit 6 (Compare):   {(status >> 6) & 1}")
            print(f"  Bits 5-2 (Density): {(status >> 2) & 0x0F:04b} (should be 0010 for 2Mbit)")
            print(f"  Bit 1 (Protect):   {(status >> 1) & 1}")
            print(f"  Bit 0 (PageSize):  {status & 1} ({'256' if status & 1 else '264'} bytes)")
        
        # Test 5: Try sending all zeros and all ones
        print("\n[Test 5] SPI loopback test (send patterns)")
        GPIO.output(PIN_CS, GPIO.LOW)
        time.sleep(0.000010)
        recv_00 = spi_transfer_byte(0x00)
        recv_FF = spi_transfer_byte(0xFF)
        recv_AA = spi_transfer_byte(0xAA)
        recv_55 = spi_transfer_byte(0x55)
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.000010)
        
        print(f"  Sent 0x00, received: 0x{recv_00:02X}")
        print(f"  Sent 0xFF, received: 0x{recv_FF:02X}")
        print(f"  Sent 0xAA, received: 0x{recv_AA:02X}")
        print(f"  Sent 0x55, received: 0x{recv_55:02X}")
        
        if recv_00 == 0xFF and recv_FF == 0xFF and recv_AA == 0xFF and recv_55 == 0xFF:
            print("  ✗ Always receiving 0xFF - MISO problem!")
            print("  Possible causes:")
            print("    - MISO not connected")
            print("    - Wrong GPIO pin for MISO")
            print("    - Flash chip not powered")
            print("    - CS not connected or inverted")
        elif recv_00 == 0x00 and recv_FF == 0x00 and recv_AA == 0x00 and recv_55 == 0x00:
            print("  ✗ Always receiving 0x00 - MISO stuck low")
        else:
            print("  ✓ MISO shows varying data - SPI likely working")
        
        # Test 6: Check GPIO directions
        print("\n[Test 6] GPIO Configuration Check")
        print(f"  SCK (GPIO{PIN_SCK}):  Set as OUTPUT")
        print(f"  MOSI (GPIO{PIN_MOSI}): Set as OUTPUT")
        print(f"  MISO (GPIO{PIN_MISO}): Set as INPUT")
        print(f"  CS (GPIO{PIN_CS}):   Set as OUTPUT")
        
        print("\n" + "=" * 60)
        print("Diagnostic Summary:")
        print("=" * 60)
        
        if mfg_id == 0x1F:
            print("✓ Flash chip appears to be responding correctly")
        elif status == 0xFF and mfg_id == 0xFF:
            print("✗ Flash chip not responding - check hardware connections:")
            print("  1. Verify MISO connected to GPIO22")
            print("  2. Verify CS connected to GPIO4")
            print("  3. Verify flash chip has power (3.3V)")
            print("  4. Check for correct SPI mode wiring")
        else:
            print("? Unexpected response - may need further investigation")
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Cleanup
        GPIO.output(PIN_CS, GPIO.HIGH)
        time.sleep(0.010)
        GPIO.cleanup()

if __name__ == "__main__":
    main()
