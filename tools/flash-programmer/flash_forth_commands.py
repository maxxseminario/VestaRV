#!/usr/bin/env python3
"""
Generate Forth commands to access AT45DB021E flash via SPI0 peripheral.
This script generates commands to be sent to the VestaRV chip via Forth interface.

SPI0 Register Map (from MemoryMap.h):
  SPI0CR  @ 0x4200 - Control Register
  SPI0SR  @ 0x4204 - Status Register  
  SPI0TX  @ 0x4208 - Transmit Register
  SPI0RX  @ 0x420C - Receive Register
  SPI0FOS @ 0x4210 - FIFO Offset Select

AT45DB021E Flash Commands:
  0xAB - Resume from Deep Power-Down
  0xD7 - Status Register Read
  0x9F - Manufacturer/Device ID
  0xD2 - Main Memory Page Read
  0x84 - Buffer 1 Write
  0x83 - Buffer 1 to Main Memory Page Program with Built-In Erase
"""

# SPI0 Register Addresses
SPI0_BASE = 0x4200
SPI0CR = 0x4200
SPI0SR = 0x4204
SPI0TX = 0x4208
SPI0RX = 0x420C
SPI0FOS = 0x4210

# AT45DB021E Commands
CMD_POWER_ON = 0xAB
CMD_READ_STATUS = 0xD7
CMD_READ_MFG_ID = 0x9F
CMD_READ_ARRAY = 0xD2
CMD_BUF1_WRITE = 0x84
CMD_BUF1_TO_PAGE = 0x83

def forth_comment(text):
    """Generate a Forth comment"""
    return f"\\ {text}"

def forth_hex(value):
    """Format value as Forth hex"""
    return f"${value:X}"

def forth_store(value, address):
    """Generate Forth code to store value at address"""
    return f"{forth_hex(value)} {forth_hex(address)} !"

def forth_fetch(address):
    """Generate Forth code to fetch value from address"""
    return f"{forth_hex(address)} @"

def forth_c_store(value, address):
    """Generate Forth code to store byte at address"""
    return f"{forth_hex(value)} {forth_hex(address)} C!"

def forth_c_fetch(address):
    """Generate Forth code to fetch byte from address"""
    return f"{forth_hex(address)} C@"

def init_spi0():
    """Generate Forth commands to initialize SPI0"""
    commands = []
    commands.append(forth_comment("=" * 60))
    commands.append(forth_comment("Initialize SPI0 for AT45DB021E Flash"))
    commands.append(forth_comment("=" * 60))
    
    # SPI0 Control Register setup:
    # Bit 0 (CPHA) = 0 - Clock phase 0
    # Bit 1 (CPOL) = 0 - Clock polarity 0  
    # Bits 3-2 (DL) = 00 - 8-bit data length
    # Bit 6 (MSB) = 1 - MSB first
    # Bit 7 (EN) = 1 - Enable SPI
    # Bits 15-8 (BR) = 4 - Baud rate divisor (adjust as needed)
    # Bit 18 (SM) = 1 - Master mode
    # Bit 19 (FEN) = 0 - FIFO disabled (for simple operation)
    
    cr_value = (1 << 7) | (1 << 6) | (4 << 8) | (1 << 18)  # EN, MSB, BR=4, SM
    
    commands.append(forth_comment("Configure SPI0: Master mode, CPOL=0, CPHA=0, MSB first, 8-bit"))
    commands.append(forth_store(cr_value, SPI0CR))
    commands.append("")
    
    return commands

def spi_wait_ready():
    """Generate Forth commands to wait for SPI not busy"""
    commands = []
    commands.append(forth_comment("Wait for SPI ready (BUSY=0)"))
    commands.append("BEGIN")
    commands.append(f"  {forth_fetch(SPI0SR)}")
    commands.append("  4 AND 0=")  # Check bit 2 (BUSY) = 0
    commands.append("UNTIL")
    return commands

def spi_transfer_byte(byte_value, receive=True):
    """Generate Forth commands to transfer a byte via SPI0"""
    commands = []
    commands.append(forth_comment(f"Send byte 0x{byte_value:02X}"))
    commands.append(forth_store(byte_value, SPI0TX))
    commands.extend(spi_wait_ready())
    if receive:
        commands.append(forth_comment("Read received byte"))
        commands.append(forth_fetch(SPI0RX))
    return commands

def flash_read_status():
    """Generate Forth commands to read AT45DB021E status register"""
    commands = []
    commands.append(forth_comment(""))
    commands.append(forth_comment("Read Flash Status Register"))
    commands.append(forth_comment("-" * 40))
    
    # Send status command
    commands.extend(spi_transfer_byte(CMD_READ_STATUS, receive=False))
    
    # Read status byte
    commands.extend(spi_transfer_byte(0x00, receive=True))
    
    commands.append(forth_comment("Status byte is now on stack"))
    commands.append(forth_comment("Bit 7 = Ready, Bit 0 = Page size (0=264, 1=256)"))
    commands.append(".")  # Print status
    commands.append("")
    
    return commands

def flash_read_mfg_id():
    """Generate Forth commands to read manufacturer/device ID"""
    commands = []
    commands.append(forth_comment(""))
    commands.append(forth_comment("Read Manufacturer and Device ID"))
    commands.append(forth_comment("-" * 40))
    
    # Send ID command
    commands.extend(spi_transfer_byte(CMD_READ_MFG_ID, receive=False))
    
    # Read 4 ID bytes
    commands.append(forth_comment("Read Manufacturer ID"))
    commands.extend(spi_transfer_byte(0x00, receive=True))
    commands.append(". \\ Print MFG ID (should be 0x1F for Atmel)")
    
    commands.append(forth_comment("Read Device ID bytes"))
    commands.extend(spi_transfer_byte(0x00, receive=True))
    commands.append(". \\ Device ID 1")
    commands.extend(spi_transfer_byte(0x00, receive=True))
    commands.append(". \\ Device ID 2")
    commands.extend(spi_transfer_byte(0x00, receive=True))
    commands.append(". \\ Extended info")
    commands.append("")
    
    return commands

def flash_write_buffer1(data_bytes):
    """Generate Forth commands to write data to Buffer 1
    
    Args:
        data_bytes: List of bytes to write to buffer
    """
    commands = []
    commands.append(forth_comment(""))
    commands.append(forth_comment(f"Write {len(data_bytes)} bytes to Buffer 1"))
    commands.append(forth_comment("-" * 40))
    
    # Send Buffer 1 Write command
    commands.extend(spi_transfer_byte(CMD_BUF1_WRITE, receive=False))
    
    # Send 3 address bytes (all zeros for offset 0)
    commands.append(forth_comment("Address bytes (offset 0)"))
    commands.extend(spi_transfer_byte(0x00, receive=False))
    commands.extend(spi_transfer_byte(0x00, receive=False))
    commands.extend(spi_transfer_byte(0x00, receive=False))
    
    # Send data bytes
    commands.append(forth_comment("Data bytes:"))
    for i, byte_val in enumerate(data_bytes):
        commands.append(forth_comment(f"  Byte {i}: 0x{byte_val:02X}"))
        commands.extend(spi_transfer_byte(byte_val, receive=False))
    
    commands.append("")
    return commands

def flash_buffer1_to_page(page_num):
    """Generate Forth commands to program Buffer 1 to a page with erase
    
    Args:
        page_num: Page number (0-1023 for AT45DB021E)
    """
    commands = []
    commands.append(forth_comment(""))
    commands.append(forth_comment(f"Program Buffer 1 to Page {page_num} (with erase)"))
    commands.append(forth_comment("-" * 40))
    
    # Send Buffer 1 to Main Memory command
    commands.extend(spi_transfer_byte(CMD_BUF1_TO_PAGE, receive=False))
    
    # Send page address (3 bytes)
    # AT45DB021E: PA9-PA0 (10 bits) + don't care bits
    addr_byte1 = (page_num >> 7) & 0x07
    addr_byte2 = (page_num << 1) & 0xFE
    addr_byte3 = 0x00
    
    commands.append(forth_comment(f"Page address: {page_num}"))
    commands.extend(spi_transfer_byte(addr_byte1, receive=False))
    commands.extend(spi_transfer_byte(addr_byte2, receive=False))
    commands.extend(spi_transfer_byte(addr_byte3, receive=False))
    
    commands.append(forth_comment("Wait for program to complete (check status)"))
    commands.append("")
    
    return commands

def flash_read_page(page_num, offset, num_bytes):
    """Generate Forth commands to read data from a page
    
    Args:
        page_num: Page number to read from
        offset: Byte offset within page
        num_bytes: Number of bytes to read
    """
    commands = []
    commands.append(forth_comment(""))
    commands.append(forth_comment(f"Read {num_bytes} bytes from Page {page_num}, offset {offset}"))
    commands.append(forth_comment("-" * 40))
    
    # Send Main Memory Page Read command
    commands.extend(spi_transfer_byte(CMD_READ_ARRAY, receive=False))
    
    # Send page address (3 bytes)
    addr_byte1 = (page_num >> 7) & 0x07
    addr_byte2 = ((page_num << 1) & 0xFE) | ((offset >> 8) & 0x01)
    addr_byte3 = offset & 0xFF
    
    commands.append(forth_comment(f"Page address: {page_num}, offset: {offset}"))
    commands.extend(spi_transfer_byte(addr_byte1, receive=False))
    commands.extend(spi_transfer_byte(addr_byte2, receive=False))
    commands.extend(spi_transfer_byte(addr_byte3, receive=False))
    
    # Send 4 don't care bytes (required for 0xD2 command)
    commands.append(forth_comment("4 don't care bytes"))
    for _ in range(4):
        commands.extend(spi_transfer_byte(0x00, receive=False))
    
    # Read data bytes
    commands.append(forth_comment(f"Read {num_bytes} data bytes:"))
    for i in range(num_bytes):
        commands.append(forth_comment(f"  Byte {i}:"))
        commands.extend(spi_transfer_byte(0x00, receive=True))
        commands.append(". \\ Print byte")
    
    commands.append("")
    return commands

def generate_simple_test():
    """Generate a complete simple write/read test"""
    commands = []
    
    # Test data - write a single 32-bit word (0xDEADBEEF)
    test_word = 0xDEADBEEF
    test_bytes = [
        (test_word >> 0) & 0xFF,
        (test_word >> 8) & 0xFF,
        (test_word >> 16) & 0xFF,
        (test_word >> 24) & 0xFF
    ]
    
    commands.append(forth_comment("=" * 60))
    commands.append(forth_comment("AT45DB021E Flash Test via SPI0"))
    commands.append(forth_comment(f"Test: Write 0x{test_word:08X} to page 0, then read back"))
    commands.append(forth_comment("=" * 60))
    commands.append("")
    
    # Initialize SPI0
    commands.extend(init_spi0())
    
    # Read manufacturer ID
    commands.extend(flash_read_mfg_id())
    
    # Read status
    commands.extend(flash_read_status())
    
    # Write test data to Buffer 1
    commands.extend(flash_write_buffer1(test_bytes))
    
    # Program Buffer 1 to Page 0
    commands.extend(flash_buffer1_to_page(0))
    
    # Check status until ready
    commands.append(forth_comment("Poll status until ready"))
    commands.append("BEGIN")
    commands.extend(flash_read_status())
    commands.append("  $80 AND 0<>")  # Check bit 7 (ready) = 1
    commands.append("UNTIL")
    commands.append("")
    
    # Read back data from Page 0
    commands.extend(flash_read_page(0, 0, 4))
    
    commands.append(forth_comment("=" * 60))
    commands.append(forth_comment("Test complete - check if read values match 0xEF 0xBE 0xAD 0xDE"))
    commands.append(forth_comment("=" * 60))
    
    return commands

def main():
    """Main function to generate and save Forth commands"""
    import sys
    
    # Generate test commands
    commands = generate_simple_test()
    
    # Output file
    output_file = "flash_test.fth"
    
    # Write to file
    with open(output_file, 'w') as f:
        for cmd in commands:
            f.write(cmd + '\n')
    
    print(f"Generated {len(commands)} Forth commands")
    print(f"Saved to: {output_file}")
    print()
    print("To use:")
    print("  1. Connect to VestaRV chip via Forth interface")
    print("  2. Load and execute the commands from flash_test.fth")
    print("  3. Check the output values")
    print()
    print("Expected output:")
    print("  - Manufacturer ID: 0x1F (Atmel)")
    print("  - Status: 0x9C or similar (ready, 264-byte pages)")
    print("  - Read data: 0xEF 0xBE 0xAD 0xDE (little-endian DEADBEEF)")

if __name__ == "__main__":
    main()
