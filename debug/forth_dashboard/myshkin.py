"""
Myshkin Chip Interface
Simplified version using peripherals_config.py for register definitions
Communicates via UART using Forth commands
"""
import time
import serial
import numpy as np
import logging
from datetime import datetime
from collections import deque
from peripherals_config import PERIPHERALS, get_register_address, addr_to_forth

# Configure logging to file
log_file = 'myshkin_commands.log'
logging.basicConfig(
    filename=log_file,
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('myshkin')

# Global command history for GUI display (last 100 commands)
command_history = deque(maxlen=100)


class Myshkin:
    """
    Interface class for Myshkin MCU via UART/Forth
    """
    
    def __init__(self, port='/dev/ttyAMA0', baudrate=115200):
        """
        Initialize UART connection for Myshkin chip
        
        Args:
            port: Serial port device (default: /dev/ttyAMA0 for RPi 4)
            baudrate: UART baudrate (default: 115200)
        """
        self.uart = None
        self.register_cache = {}  # Cache for register values
        
        try:
            self.uart = serial.Serial(
                port=port,
                baudrate=baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.1,        # short timeout to avoid blocking
                xonxoff=False,      # no software flow control
                rtscts=False,       # no hardware RTS/CTS
                dsrdtr=False,       # no hardware DSR/DTR
            )
            print(f"✓ UART connection established on {port} at {baudrate} baud")
        except serial.SerialException as e:
            print(f"✗ Warning: Could not open UART port {port}: {e}")
            print("  Running in simulation mode (no hardware communication)")
            self.uart = None

    def send_forth_command(self, command):
        """
        Send a Forth command over UART and return the response
        
        Args:
            command: Forth command string
            
        Returns:
            Response string from the chip, or None if UART not available
        """
        timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]
        
        if self.uart is None:
            # Simulation mode - return dummy data
            log_msg = f"[SIM] TX: {command}"
            logger.info(log_msg)
            command_history.append(f"{timestamp} {log_msg}")
            return "0"
            
        try:
            # Log command being sent
            log_msg = f"TX: {command}"
            logger.info(log_msg)
            command_history.append(f"{timestamp} {log_msg}")
            
            # Send command with newline
            self.uart.write((command + '\n').encode('utf-8'))
            time.sleep(0.05)  # Small delay for processing
            
            # Read response
            response = b''
            while self.uart.in_waiting > 0:
                response += self.uart.read(self.uart.in_waiting)
                time.sleep(0.01)
            
            response_str = response.decode('utf-8', errors='ignore').strip()
            
            # Log response
            if response_str:
                log_msg = f"RX: {response_str}"
                logger.info(log_msg)
                command_history.append(f"{timestamp} {log_msg}")
            
            return response_str
        except Exception as e:
            error_msg = f"ERROR: UART communication error: {e}"
            logger.error(error_msg)
            command_history.append(f"{timestamp} {error_msg}")
            print(error_msg)
            return None

    def read(self, addr, cached=False):
        """
        Read a value from a register address
        
        Args:
            addr: Register address (hex)
            cached: Use cached value if True
            
        Returns:
            Register value (size depends on register definition)
        """
        if cached and addr in self.register_cache:
            return self.register_cache[addr]
        
        # Forth command to read from address: "addr @ ."
        # For multi-byte registers, we read the full word
        command = f"{addr_to_forth(addr)} @ ."
        response = self.send_forth_command(command)
        
        if response:
            try:
                # Parse the numeric response (handles hex and decimal)
                value = int(response.split()[-1], 0)
                self.register_cache[addr] = value
                return value
            except (ValueError, IndexError):
                print(f"Error parsing read response from {addr_to_forth(addr)}: {response}")
                return 0
        return 0

    def write(self, addr, value):
        """
        Write a value to a register address
        
        Args:
            addr: Register address (hex)
            value: Value to write
        """
        addr = int(addr)
        value = int(value)
        
        # Forth command to write to address: "value addr !"
        command = f"{value} {addr_to_forth(addr)} !"
        self.send_forth_command(command)
        
        # Update cache
        self.register_cache[addr] = value
        print(f"Write {addr_to_forth(addr)}: {value} (0x{value:04X})")

    def read_register(self, peripheral, register, cached=False):
        """
        Read a named register from a peripheral
        
        Args:
            peripheral: Peripheral name (e.g., 'GPIO0', 'UART0')
            register: Register name (e.g., 'CR', 'SR', 'DATA')
            cached: Use cached value if True
            
        Returns:
            Register value, or None if not found
        """
        addr = get_register_address(peripheral, register)
        if addr is None:
            print(f"Error: Unknown register {peripheral}.{register}")
            return None
        
        return self.read(addr, cached=cached)

    def write_register(self, peripheral, register, value):
        """
        Write a value to a named register in a peripheral
        
        Args:
            peripheral: Peripheral name (e.g., 'GPIO0', 'UART0')
            register: Register name (e.g., 'CR', 'DATA')
            value: Value to write
        """
        addr = get_register_address(peripheral, register)
        if addr is None:
            print(f"Error: Unknown register {peripheral}.{register}")
            return
        
        self.write(addr, value)

    def clear_cache(self):
        """Clear the register cache"""
        self.register_cache = {}
        print("Register cache cleared")

    def cache_all_registers(self):
        """
        Read all registers from all peripherals and cache them
        This is useful for bulk register synchronization
        """
        print("Caching all registers...")
        count = 0
        for periph_name, periph_info in PERIPHERALS.items():
            for reg_name in periph_info['registers'].keys():
                self.read_register(periph_name, reg_name, cached=False)
                count += 1
        print(f"Cached {count} registers")

    def close(self):
        """Close UART connection"""
        if self.uart and self.uart.is_open:
            self.uart.close()
            print("UART connection closed")

    def __del__(self):
        """Destructor - close UART when object is deleted"""
        self.close()


def get_command_history():
    """
    Get the current command history for GUI display
    
    Returns:
        List of command log strings
    """
    return list(command_history)


# Test function
if __name__ == "__main__":
    print("Testing Myshkin interface...")
    chip = Myshkin()
    
    # Test reading a register
    print("\nTesting register read:")
    val = chip.read_register('GPIO0', 'PIN')
    print(f"GPIO0.PIN = {val} (0x{val:02X})")
    
    # Test writing a register
    print("\nTesting register write:")
    chip.write_register('GPIO0', 'POUT', 0xFF)
    
    print("\nTest complete!")
    chip.close()
