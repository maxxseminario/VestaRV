#!/usr/bin/env python3
"""
Fast SARADC Data Acquisition Script

Reads SARADC data register at maximum speed via UART/Forth and logs to file.
This script bypasses the GUI's ~9Hz rate limitation and achieves much higher
sampling rates by continuously sending read commands without artificial delays.

Usage:
    python3 fast_saradc_acquire.py [duration_seconds] [output_file]
    
Examples:
    python3 fast_saradc_acquire.py 10                          # 10 seconds, auto-named file
    python3 fast_saradc_acquire.py 30 my_acquisition.txt       # 30 seconds, custom filename
    python3 fast_saradc_acquire.py                             # Run until Ctrl+C

The script assumes the SARADC is already configured to run continuously.
Press Ctrl+C to stop acquisition at any time.
"""

import sys
import time
import serial
import signal
import os
from datetime import datetime


class FastSARADCAcquire:
    """High-speed SARADC data acquisition via UART/Forth"""
    
    def __init__(self, port='/dev/ttyAMA0', baudrate=115200):
        """
        Initialize UART connection
        
        Args:
            port: Serial port (default: /dev/ttyAMA0 for RPi)
            baudrate: UART baudrate (default: 115200)
        """
        self.uart = None
        self.running = False
        self.sample_count = 0
        self.corrupted_count = 0
        self.uart_combined_log = None
        self.uart_rx_log = None
        self.uart_tx_log = None
        self.acquisition_start_time = None
        
        try:
            self.uart = serial.Serial(
                port=port,
                baudrate=baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.05,  # Shorter timeout for speed
                xonxoff=False,
                rtscts=False,
                dsrdtr=False,
            )
            print(f"✓ UART opened: {port} @ {baudrate} baud")
        except serial.SerialException as e:
            print(f"✗ Error: Could not open UART port {port}: {e}")
            sys.exit(1)
    
    def read_saradc_fast(self):
        """
        Read SARADC data register with minimal overhead
        
        Returns:
            int: ADC value, or None if read failed
        """
        SARADC_DATA_ADDR = 0x4B0C
        
        # Clear buffer
        if self.uart.in_waiting > 0:
            self.uart.reset_input_buffer()
        
        # Send Forth read command: "0x4B0C @ ."
        command = f"0x{SARADC_DATA_ADDR:X} @ .\n"
        tx_time = time.time() - self.acquisition_start_time
        self.uart.write(command.encode('utf-8'))
        self.uart.flush()
        
        # Log TX
        if self.uart_tx_log:
            self.uart_tx_log.write(f"{tx_time:.6f}, TX, {repr(command)}\n")
        if self.uart_combined_log:
            self.uart_combined_log.write(f"{tx_time:.6f}, TX, {repr(command)}\n")
        
        # Read response quickly
        response = b''
        start_time = time.time()
        
        while time.time() - start_time < 0.1:  # 100ms timeout
            if self.uart.in_waiting > 0:
                chunk = self.uart.read(self.uart.in_waiting)
                rx_time = time.time() - self.acquisition_start_time
                
                # Log RX chunk
                if self.uart_rx_log:
                    self.uart_rx_log.write(f"{rx_time:.6f}, RX, {repr(chunk.decode('utf-8', errors='replace'))}\n")
                if self.uart_combined_log:
                    self.uart_combined_log.write(f"{rx_time:.6f}, RX, {repr(chunk.decode('utf-8', errors='replace'))}\n")
                
                response += chunk
                if b'>' in chunk:  # Prompt indicates complete response
                    break
                time.sleep(0.005)
            else:
                time.sleep(0.005)
        
        # Parse response with strict validation
        try:
            response_str = response.decode('utf-8', errors='replace').strip()
            
            # Check for corruption markers in the entire response
            # If the VALUE itself is corrupted, we must reject it
            if '?' in response_str or '\x1a' in response_str:
                # Split to check if corruption is in the value or just the address echo
                tokens = response_str.split()
                
                # Expected format: "0x4B0C @ . \n <VALUE> \n >"
                # Find the value token (should be before '>')
                value_token = None
                for i in range(len(tokens) - 1, -1, -1):
                    if tokens[i] == '>' and i > 0:
                        value_token = tokens[i-1]
                        break
                
                # If value token contains corruption markers, reject this sample
                if value_token and ('?' in value_token or '\x1a' in value_token):
                    return None  # Corrupted value - reject
            
            # Validate address echo (optional - allows corrupted echo if value is clean)
            # Split on newlines to separate: echo, value, prompt
            lines = response_str.split('\n')
            
            # Find numeric value (should be on its own line or before '>')
            value = None
            for line in lines:
                line = line.strip()
                # Skip the command echo and prompt
                if '@' in line or '>' in line or not line:
                    continue
                # Try to parse as integer
                try:
                    value = int(line, 0)
                    # Additional validation: ensure it's in valid 10-bit range
                    if 0 <= value <= 1023:
                        return value
                    else:
                        return None  # Out of range
                except ValueError:
                    continue
            
            # Fallback: traditional token parsing
            tokens = response_str.replace('\x1a', '').replace('?', '').split()
            for i in range(len(tokens) - 1, -1, -1):
                if tokens[i] == '>' and i > 0:
                    try:
                        value = int(tokens[i-1], 0)
                        if 0 <= value <= 1023:
                            return value
                    except ValueError:
                        continue
            
            return None
            
        except Exception as e:
            return None
    
    def acquire(self, duration=None, log_file=None):
        """
        Acquire SARADC data continuously
        
        Args:
            duration: Acquisition duration in seconds (None = run until Ctrl+C)
            log_file: Output log file path
        """
        # Create logs directory
        log_dir = os.path.join(os.path.dirname(__file__), 'logs')
        os.makedirs(log_dir, exist_ok=True)
        
        # Create log file
        if log_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            log_file = os.path.join(log_dir, f"fast_saradc_data_{timestamp}.txt")
        elif not os.path.isabs(log_file):
            # If relative path given, put it in logs directory
            log_file = os.path.join(log_dir, log_file)
        
        # Create UART log files
        base_name = os.path.splitext(os.path.basename(log_file))[0]
        uart_combined_file = os.path.join(log_dir, f"{base_name}_uart_combined.txt")
        uart_rx_file = os.path.join(log_dir, f"{base_name}_uart_rx.txt")
        uart_tx_file = os.path.join(log_dir, f"{base_name}_uart_tx.txt")
        
        print(f"\n{'='*60}")
        print(f"Fast SARADC Acquisition")
        print(f"{'='*60}")
        print(f"Data log:        {log_file}")
        print(f"UART combined:   {uart_combined_file}")
        print(f"UART RX only:    {uart_rx_file}")
        print(f"UART TX only:    {uart_tx_file}")
        if duration:
            print(f"Duration:        {duration} seconds")
        else:
            print(f"Duration:        Until Ctrl+C")
        print(f"{'='*60}\n")
        
        # Write header to data log
        with open(log_file, 'w') as f:
            f.write("# Fast SARADC Data Acquisition Log\n")
            f.write(f"# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("# SARADC DATA Register: 0x4B0C\n")
            f.write("# MSB inversion applied (XOR 512)\n")
            f.write("# Timestamp(s), ADC_Value(decimal), ADC_Value(hex)\n")
        
        # Open UART log files
        self.uart_combined_log = open(uart_combined_file, 'w')
        self.uart_rx_log = open(uart_rx_file, 'w')
        self.uart_tx_log = open(uart_tx_file, 'w')
        
        # Write headers to UART logs
        header = f"# UART Communication Log\n# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n# Timestamp(s), Direction, Data\n"
        self.uart_combined_log.write(header)
        self.uart_rx_log.write(f"# UART RX Log\n# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n# Timestamp(s), Direction, Data\n")
        self.uart_tx_log.write(f"# UART TX Log\n# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n# Timestamp(s), Direction, Data\n")
        
        self.running = True
        self.sample_count = 0
        self.corrupted_count = 0
        start_time = time.time()
        self.acquisition_start_time = start_time
        last_print_time = start_time
        
        print("Acquiring... (Press Ctrl+C to stop)\n")
        
        try:
            while self.running:
                # Check duration
                if duration and (time.time() - start_time) >= duration:
                    break
                
                # Read ADC value
                adc_value = self.read_saradc_fast()
                
                if adc_value is not None:
                    # Validate 10-bit range (redundant check, but safe)
                    if 0 <= adc_value <= 1023:
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
                            corruption_pct = 100.0 * self.corrupted_count / (self.sample_count + self.corrupted_count) if (self.sample_count + self.corrupted_count) > 0 else 0
                            print(f"Samples: {self.sample_count:6d} | Corrupted: {self.corrupted_count:4d} ({corruption_pct:4.1f}%) | "
                                  f"Rate: {rate:6.1f} Hz | Elapsed: {elapsed:6.1f}s | Last: {adc_value:4d}")
                            last_print_time = time.time()
                else:
                    # Track corrupted/failed reads
                    self.corrupted_count += 1
        
        except KeyboardInterrupt:
            print("\n\nCtrl+C detected - stopping acquisition...")
        
        finally:
            self.running = False
            
            # Close UART log files
            if self.uart_combined_log:
                self.uart_combined_log.close()
                self.uart_combined_log = None
            if self.uart_rx_log:
                self.uart_rx_log.close()
                self.uart_rx_log = None
            if self.uart_tx_log:
                self.uart_tx_log.close()
                self.uart_tx_log = None
            
            # Final statistics
            elapsed = time.time() - start_time
            rate = self.sample_count / elapsed if elapsed > 0 else 0
            total_reads = self.sample_count + self.corrupted_count
            corruption_pct = 100.0 * self.corrupted_count / total_reads if total_reads > 0 else 0
            
            print(f"\n{'='*60}")
            print(f"Acquisition Complete")
            print(f"{'='*60}")
            print(f"Valid samples:   {self.sample_count}")
            print(f"Corrupted:       {self.corrupted_count} ({corruption_pct:.1f}%)")
            print(f"Total attempts:  {total_reads}")
            print(f"Duration:        {elapsed:.2f} seconds")
            print(f"Valid rate:      {rate:.1f} Hz")
            print(f"Data log:        {log_file}")
            print(f"UART combined:   {uart_combined_file}")
            print(f"UART RX only:    {uart_rx_file}")
            print(f"UART TX only:    {uart_tx_file}")
            print(f"{'='*60}\n")
            
            # Write summary to log file
            with open(log_file, 'a') as f:
                f.write(f"\n# Acquisition stopped: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"# Valid samples: {self.sample_count}\n")
                f.write(f"# Corrupted samples: {self.corrupted_count} ({corruption_pct:.1f}%)\n")
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
    duration = None
    log_file = None
    
    if len(sys.argv) > 1:
        try:
            duration = float(sys.argv[1])
            if duration <= 0:
                print("Error: Duration must be positive")
                sys.exit(1)
        except ValueError:
            print(f"Error: Invalid duration '{sys.argv[1]}' - must be a number")
            sys.exit(1)
    
    if len(sys.argv) > 2:
        log_file = sys.argv[2]
    
    # Setup signal handler
    signal.signal(signal.SIGINT, signal_handler)
    
    # Run acquisition
    acquirer = FastSARADCAcquire()
    
    try:
        acquirer.acquire(duration=duration, log_file=log_file)
    finally:
        acquirer.close()


if __name__ == '__main__':
    main()
