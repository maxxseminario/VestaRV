#!/usr/bin/env python3
"""
Single-Shot SARADC Acquisition Script

Performs single SARADC measurements by triggering individual conversions.
Unlike continuous mode, this script triggers one conversion at a time,
waits for completion, reads the data, and repeats.

Usage:
    python3 single_shot_saradc.py [num_samples] [output_file]
    
Examples:
    python3 single_shot_saradc.py 100                    # 100 samples, auto-named file
    python3 single_shot_saradc.py 1000 my_data.txt       # 1000 samples, custom filename
    python3 single_shot_saradc.py                        # Run until Ctrl+C

SARADC Operation:
    - CR[8] = 0: Single-shot mode (not continuous)
    - CR[5] = 1: Enable ADC
    - CR[4:1]: Sample time (default: 0xF = 15)
    - SR[1]: Data valid flag (cleared by writing 1 to SR[1])
    - SR[0]: Conversion busy flag
    
Measurement sequence:
    1. Configure SARADC for single-shot mode
    2. Enable ADC (starts conversion)
    3. Poll SR until data_valid = 1
    4. Read DATA register
    5. Clear data_valid flag (write 1 to SR[1])
    6. Disable ADC
    7. Re-enable ADC to start next conversion
"""

import sys
import time
import serial
import signal
import os
from datetime import datetime


class SingleShotSARADC:
    """Single-shot SARADC measurement via UART/Forth"""
    
    # Register addresses
    SARADC_CR = 0x4B00
    SARADC_SR = 0x4B08
    SARADC_DATA = 0x4B0C
    
    def __init__(self, port='/dev/ttyAMA0', baudrate=115200):
        """
        Initialize UART connection
        
        Args:
            port: Serial port (default: /dev/ttyAMA0 for RPi)
            baudrate: UART baudrate (default: 115200)
        """
        self.uart = None
        self.sample_count = 0
        
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
            print(f"✓ UART opened: {port} @ {baudrate} baud")
        except serial.SerialException as e:
            print(f"✗ Error: Could not open UART port {port}: {e}")
            sys.exit(1)
    
    def send_forth_command(self, command):
        """Send Forth command and get response"""
        # Clear buffer
        if self.uart.in_waiting > 0:
            self.uart.reset_input_buffer()
        
        # Send command
        self.uart.write((command + '\n').encode('utf-8'))
        self.uart.flush()
        
        # Read response
        response = b''
        start_time = time.time()
        
        while time.time() - start_time < 0.2:
            if self.uart.in_waiting > 0:
                chunk = self.uart.read(self.uart.in_waiting)
                response += chunk
                if b'>' in chunk:
                    break
                time.sleep(0.01)
            else:
                time.sleep(0.01)
        
        return response.decode('utf-8', errors='replace').strip()
    
    def write_register(self, addr, value):
        """Write to SARADC register"""
        command = f"{value} 0x{addr:X} !"
        self.send_forth_command(command)
        time.sleep(0.01)
    
    def read_register(self, addr):
        """Read from SARADC register"""
        command = f"0x{addr:X} @ ."
        response = self.send_forth_command(command)
        
        # Parse response
        try:
            cleaned = response.replace('\x1a', '').replace('?', '')
            tokens = cleaned.split()
            
            # Find numeric value before '>'
            for i in range(len(tokens) - 1, -1, -1):
                if tokens[i] == '>' and i > 0:
                    try:
                        return int(tokens[i-1], 0)
                    except ValueError:
                        continue
            
            # Fallback: search for any valid number
            for token in reversed(tokens):
                if token not in ['@', '.', '>'] and not token.startswith('0x'):
                    try:
                        return int(token, 0)
                    except ValueError:
                        continue
        except Exception:
            pass
        
        return None
    
    def setup_saradc(self):
        """
        Configure SARADC for single-shot measurements
        
        CR register bits:
            [8] = 0: Single-shot mode (not continuous)
            [7] = 0: Interrupt disabled
            [6] = 0: Debug mode off
            [5] = 0: ADC initially disabled (will enable per measurement)
            [4:1] = 0xF (15): Sample time
            [0] = 0: No reset
        """
        print("Setting up SARADC for single-shot mode...")
        
        # CR = 0x001E (sample time = 15, single-shot, disabled initially)
        # Bits: [8:0] = 000011110 = 0x1E
        cr_value = 0x1E  # Sample time = 15, single-shot, disabled
        self.write_register(self.SARADC_CR, cr_value)
        
        # Clear any pending flags
        self.write_register(self.SARADC_SR, 0x06)  # Clear data_valid and ovf flags
        
        time.sleep(0.05)
        print("✓ SARADC configured for single-shot measurements")
    
    def trigger_and_read_single(self):
        """
        Trigger one ADC conversion and read the result
        
        Returns:
            int: ADC value (0-1023), or None if timeout
        """
        # Enable ADC to start conversion (set CR[5] = 1)
        cr_enable = 0x3E  # Sample time = 15, single-shot, enabled
        self.write_register(self.SARADC_CR, cr_enable)
        
        # Poll status register until data_valid (SR[1]) = 1
        timeout = time.time() + 0.5  # 500ms timeout
        while time.time() < timeout:
            sr = self.read_register(self.SARADC_SR)
            if sr is not None:
                data_valid = (sr >> 1) & 1
                if data_valid:
                    # Read ADC data
                    adc_value = self.read_register(self.SARADC_DATA)
                    
                    # Clear data_valid flag (write 1 to SR[1])
                    self.write_register(self.SARADC_SR, 0x02)
                    
                    # Disable ADC
                    cr_disable = 0x1E  # Sample time = 15, single-shot, disabled
                    self.write_register(self.SARADC_CR, cr_disable)
                    
                    return adc_value
            
            time.sleep(0.005)  # 5ms poll interval
        
        # Timeout - disable ADC and return None
        self.write_register(self.SARADC_CR, 0x1E)
        return None
    
    def acquire(self, num_samples=None, log_file=None):
        """
        Acquire SARADC data using single-shot measurements
        
        Args:
            num_samples: Number of samples to acquire (None = run until Ctrl+C)
            log_file: Output log file path
        """
        # Create logs directory
        log_dir = os.path.join(os.path.dirname(__file__), 'logs')
        os.makedirs(log_dir, exist_ok=True)
        
        # Create log file
        if log_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            log_file = os.path.join(log_dir, f"single_shot_saradc_{timestamp}.txt")
        elif not os.path.isabs(log_file):
            log_file = os.path.join(log_dir, log_file)
        
        print(f"\n{'='*60}")
        print(f"Single-Shot SARADC Acquisition")
        print(f"{'='*60}")
        print(f"Log file: {log_file}")
        if num_samples:
            print(f"Samples: {num_samples}")
        else:
            print(f"Samples: Until Ctrl+C")
        print(f"{'='*60}\n")
        
        # Setup SARADC
        self.setup_saradc()
        
        # Write header
        with open(log_file, 'w') as f:
            f.write("# Single-Shot SARADC Data Acquisition Log\n")
            f.write(f"# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("# Mode: Single-shot (one conversion per trigger)\n")
            f.write("# MSB inversion applied (XOR 512)\n")
            f.write("# Timestamp(s), ADC_Value(decimal), ADC_Value(hex)\n")
        
        self.sample_count = 0
        start_time = time.time()
        last_print_time = start_time
        
        print("Acquiring... (Press Ctrl+C to stop)\n")
        
        try:
            while True:
                # Check sample limit
                if num_samples and self.sample_count >= num_samples:
                    break
                
                # Trigger and read one measurement
                adc_value = self.trigger_and_read_single()
                
                if adc_value is not None and 0 <= adc_value <= 1023:
                    # Apply MSB inversion (hardware bug fix)
                    adc_value = adc_value ^ 512
                    
                    # Calculate timestamp
                    timestamp = time.time() - start_time
                    
                    # Log to file
                    with open(log_file, 'a') as f:
                        f.write(f"{timestamp:.6f}, {adc_value}, 0x{adc_value:03X}\n")
                    
                    self.sample_count += 1
                    
                    # Print progress every second
                    if time.time() - last_print_time >= 1.0:
                        elapsed = time.time() - start_time
                        rate = self.sample_count / elapsed if elapsed > 0 else 0
                        print(f"Samples: {self.sample_count:6d} | Rate: {rate:6.1f} Hz | "
                              f"Elapsed: {elapsed:6.1f}s | Last value: {adc_value:4d}")
                        last_print_time = time.time()
        
        except KeyboardInterrupt:
            print("\n\nCtrl+C detected - stopping acquisition...")
        
        finally:
            # Final statistics
            elapsed = time.time() - start_time
            rate = self.sample_count / elapsed if elapsed > 0 else 0
            
            print(f"\n{'='*60}")
            print(f"Acquisition Complete")
            print(f"{'='*60}")
            print(f"Total samples:   {self.sample_count}")
            print(f"Duration:        {elapsed:.2f} seconds")
            print(f"Average rate:    {rate:.1f} Hz")
            print(f"Log file:        {log_file}")
            print(f"{'='*60}\n")
            
            # Write summary to log file
            with open(log_file, 'a') as f:
                f.write(f"\n# Acquisition stopped: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"# Total samples: {self.sample_count}\n")
                f.write(f"# Duration: {elapsed:.2f} seconds\n")
                f.write(f"# Average rate: {rate:.1f} Hz\n")
    
    def close(self):
        """Close UART connection"""
        if self.uart:
            self.uart.close()
            print("UART closed")


def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    print("\n\nInterrupt received - stopping acquisition...")
    sys.exit(0)


def main():
    """Main function"""
    # Parse arguments
    num_samples = None
    log_file = None
    
    if len(sys.argv) > 1:
        try:
            num_samples = int(sys.argv[1])
            if num_samples <= 0:
                print("Error: Number of samples must be positive")
                sys.exit(1)
        except ValueError:
            print(f"Error: Invalid number '{sys.argv[1]}' - must be an integer")
            sys.exit(1)
    
    if len(sys.argv) > 2:
        log_file = sys.argv[2]
    
    # Setup signal handler
    signal.signal(signal.SIGINT, signal_handler)
    
    # Run acquisition
    acquirer = SingleShotSARADC()
    
    try:
        acquirer.acquire(num_samples=num_samples, log_file=log_file)
    finally:
        acquirer.close()


if __name__ == '__main__':
    main()
