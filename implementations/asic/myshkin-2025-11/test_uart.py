#!/usr/bin/env python3
"""
Test UART communication with Myshkin chip
Run this to verify basic Forth communication is working
"""
import serial
import time

port = '/dev/ttyAMA0'
baudrate = 115200

print(f"Opening {port} at {baudrate} baud...")
try:
    ser = serial.Serial(port, baudrate, timeout=1)
    time.sleep(0.5)
except Exception as e:
    print(f"ERROR: Cannot open serial port: {e}")
    print("Make sure you're in the 'dialout' group: groups")
    print("If not, run: sudo usermod -a -G dialout $USER")
    exit(1)

print("✓ Serial port opened successfully")

print("\nClearing buffer...")
if ser.in_waiting > 0:
    print(f"Found {ser.in_waiting} bytes in buffer")
    data = ser.read(ser.in_waiting)
    print(f"Initial data: {data}")
else:
    print("Buffer is empty")

print("\n=== Test 1: Stack display ===")
print("Sending: .s")
ser.write(b'.s\n')
time.sleep(0.2)

if ser.in_waiting > 0:
    response = ser.read(ser.in_waiting)
    print(f"✓ Response received: {response}")
else:
    print("✗ No response (timeout)")

print("\n=== Test 2: Simple addition ===")
print("Sending: 1 2 + .")
ser.write(b'1 2 + .\n')
time.sleep(0.2)

if ser.in_waiting > 0:
    response = ser.read(ser.in_waiting)
    print(f"✓ Response received: {response}")
    if b'3' in response:
        print("✓ Forth is working correctly!")
else:
    print("✗ No response (timeout)")

print("\n=== Test 3: Echo test ===")
print("Sending: 42")
ser.write(b'42\n')
time.sleep(0.2)

if ser.in_waiting > 0:
    response = ser.read(ser.in_waiting)
    print(f"✓ Response received: {response}")
else:
    print("✗ No response (timeout)")

ser.close()
print("\n=== Summary ===")
print("If you see responses above, UART communication is working!")
print("If not, check:")
print("  1. Is the chip powered and in ROM/Forth mode?")
print("  2. Are GPIO pins connected correctly?")
print("  3. Is the correct UART port being used?")
