#!/usr/bin/env python3
"""
Fast DSADC (Dual-Slope ADC) Data Acquisition Script

Reads the DSADC ADC_VAL register at maximum speed via UART/Forth and logs to
file.  The log format is identical to that produced by fast_saradc_acquire.py
so that plot_saradc_log.py (and any other SARADC tooling) can be used directly
on the output.

The DSADC result register (ADC_VAL) is 12 bits wide (range 0-4095) and lives
at address 0x4C0C.  Each read triggers/captures the latest conversion result.

Usage:
    python3 fast_dsadc_acquire.py [duration_seconds] [output_file]

Examples:
    python3 fast_dsadc_acquire.py 10                         # 10 seconds, auto-named file
    python3 fast_dsadc_acquire.py 30 my_acquisition.txt      # 30 seconds, custom filename
    python3 fast_dsadc_acquire.py                            # Run until Ctrl+C

The script assumes the DSADC is already enabled and running (AFE_CR configured
appropriately before running this script).
Press Ctrl+C to stop acquisition at any time.
"""

import sys
import time
import serial
import signal
import os
from datetime import datetime


# DSADC ADC_VAL register address
DSADC_ADC_VAL_ADDR = 0x4C0C

# DSADC is 12-bit
ADC_MAX = 4095
ADC_BITS = 12


class FastDSADCAcquire:
    """High-speed DSADC data acquisition via UART/Forth"""

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
                timeout=0.05,
                xonxoff=False,
                rtscts=False,
                dsrdtr=False,
            )
            print(f"✓ UART opened: {port} @ {baudrate} baud")
        except serial.SerialException as e:
            print(f"✗ Error: Could not open UART port {port}: {e}")
            sys.exit(1)

    def read_dsadc_fast(self):
        """
        Read DSADC ADC_VAL register with minimal overhead.

        Returns:
            int: ADC value (0-4095), or None if read failed
        """
        # Clear buffer
        if self.uart.in_waiting > 0:
            self.uart.reset_input_buffer()

        # Send Forth read command: "0x4C0C @ ."
        command = f"0x{DSADC_ADC_VAL_ADDR:X} @ .\n"
        tx_time = time.time() - self.acquisition_start_time
        self.uart.write(command.encode('utf-8'))
        self.uart.flush()

        # Log TX
        if self.uart_tx_log:
            self.uart_tx_log.write(f"{tx_time:.6f}, TX, {repr(command)}\n")
        if self.uart_combined_log:
            self.uart_combined_log.write(f"{tx_time:.6f}, TX, {repr(command)}\n")

        # Read response
        response = b''
        start_time = time.time()
        addr_str = f"0x{DSADC_ADC_VAL_ADDR:X}"

        while time.time() - start_time < 0.1:  # 100 ms timeout
            if self.uart.in_waiting > 0:
                chunk = self.uart.read(self.uart.in_waiting)
                rx_time = time.time() - self.acquisition_start_time

                if self.uart_rx_log:
                    self.uart_rx_log.write(f"{rx_time:.6f}, RX, {repr(chunk.decode('utf-8', errors='replace'))}\n")
                if self.uart_combined_log:
                    self.uart_combined_log.write(f"{rx_time:.6f}, RX, {repr(chunk.decode('utf-8', errors='replace'))}\n")

                response += chunk
                if b'>' in chunk:  # Forth prompt = complete response
                    break
                time.sleep(0.005)
            else:
                time.sleep(0.005)

        try:
            response_str = response.decode('utf-8', errors='replace').strip()

            # Strict validation: address echo must be present
            if addr_str not in response_str:
                return None

            # Reject if corruption markers present
            if '?' in response_str or '\x1a' in response_str:
                return None

            # Parse value line (between command echo and '>' prompt)
            for line in response_str.split('\n'):
                line = line.strip()
                if '@' in line or '>' in line or not line:
                    continue
                try:
                    value = int(line, 0)
                    if 0 <= value <= ADC_MAX:
                        return value
                    else:
                        return None  # Out of range for 12-bit ADC
                except ValueError:
                    continue

            return None

        except Exception:
            return None

    def acquire(self, duration=None, log_file=None):
        """
        Acquire DSADC data continuously.

        Args:
            duration: Acquisition duration in seconds (None = run until Ctrl+C)
            log_file: Output log file path
        """
        # Create logs directory
        log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logs')
        os.makedirs(log_dir, exist_ok=True)

        # Create log file
        if log_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            log_file = os.path.join(log_dir, f"fast_dsadc_data_{timestamp}.txt")
        elif not os.path.isabs(log_file):
            log_file = os.path.join(log_dir, log_file)

        # UART log files
        base_name = os.path.splitext(os.path.basename(log_file))[0]
        uart_combined_file = os.path.join(log_dir, f"{base_name}_uart_combined.txt")
        uart_rx_file       = os.path.join(log_dir, f"{base_name}_uart_rx.txt")
        uart_tx_file       = os.path.join(log_dir, f"{base_name}_uart_tx.txt")

        print(f"\n{'='*60}")
        print(f"Fast DSADC Acquisition")
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

        # Write header to data log (same format as SARADC log)
        with open(log_file, 'w') as f:
            f.write("# Fast DSADC Data Acquisition Log\n")
            f.write(f"# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# DSADC ADC_VAL Register: 0x{DSADC_ADC_VAL_ADDR:04X}\n")
            f.write(f"# ADC resolution: {ADC_BITS}-bit (range 0-{ADC_MAX})\n")
            f.write("# Timestamp(s), ADC_Value(decimal), ADC_Value(hex)\n")

        # Open UART log files
        self.uart_combined_log = open(uart_combined_file, 'w')
        self.uart_rx_log       = open(uart_rx_file, 'w')
        self.uart_tx_log       = open(uart_tx_file, 'w')

        uart_header = f"# UART Communication Log\n# Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n# Timestamp(s), Direction, Data\n"
        self.uart_combined_log.write(uart_header)
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
                if duration and (time.time() - start_time) >= duration:
                    break

                adc_value = self.read_dsadc_fast()

                if adc_value is not None:
                    timestamp = time.time() - start_time

                    # Write in same format as fast_saradc_acquire.py so
                    # plot_saradc_log.py can read it directly
                    with open(log_file, 'a') as f:
                        f.write(f"{timestamp:.6f}, {adc_value}, 0x{adc_value:03X}\n")

                    self.sample_count += 1

                    if time.time() - last_print_time >= 1.0:
                        elapsed = time.time() - start_time
                        rate = self.sample_count / elapsed if elapsed > 0 else 0
                        total = self.sample_count + self.corrupted_count
                        corruption_pct = 100.0 * self.corrupted_count / total if total > 0 else 0
                        print(f"Samples: {self.sample_count:6d} | Corrupted: {self.corrupted_count:4d} ({corruption_pct:4.1f}%) | "
                              f"Rate: {rate:6.1f} Hz | Elapsed: {elapsed:6.1f}s | Last: {adc_value:4d}")
                        last_print_time = time.time()
                else:
                    self.corrupted_count += 1

        except KeyboardInterrupt:
            print("\n\nCtrl+C detected - stopping acquisition...")

        finally:
            self.running = False

            for fh in [self.uart_combined_log, self.uart_rx_log, self.uart_tx_log]:
                if fh:
                    fh.close()
            self.uart_combined_log = None
            self.uart_rx_log       = None
            self.uart_tx_log       = None

            elapsed = time.time() - start_time
            rate = self.sample_count / elapsed if elapsed > 0 else 0
            total = self.sample_count + self.corrupted_count
            corruption_pct = 100.0 * self.corrupted_count / total if total > 0 else 0

            print(f"\n{'='*60}")
            print(f"Acquisition Complete")
            print(f"{'='*60}")
            print(f"Valid samples:   {self.sample_count}")
            print(f"Corrupted:       {self.corrupted_count} ({corruption_pct:.1f}%)")
            print(f"Total attempts:  {total}")
            print(f"Duration:        {elapsed:.2f} seconds")
            print(f"Valid rate:      {rate:.1f} Hz")
            print(f"Data log:        {log_file}")
            print(f"UART combined:   {uart_combined_file}")
            print(f"UART RX only:    {uart_rx_file}")
            print(f"UART TX only:    {uart_tx_file}")
            print(f"{'='*60}\n")

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
    print("\n\nInterrupt received - stopping acquisition...")
    sys.exit(0)


def main():
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

    signal.signal(signal.SIGINT, signal_handler)

    acquirer = FastDSADCAcquire()
    try:
        acquirer.acquire(duration=duration, log_file=log_file)
    finally:
        acquirer.close()


if __name__ == '__main__':
    main()
