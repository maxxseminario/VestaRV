#!/usr/bin/env python3

import argparse
import sys
import os

def read_rcf_file(filename):
    """Read an RCF file and return list of 32-bit binary strings"""
    lines = []
    try:
        with open(filename, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Validate that it's a 32-bit binary string
                    if len(line) == 32 and all(c in '01' for c in line):
                        lines.append(line)
                    else:
                        print(f"Warning: Skipping invalid line in {filename}: {line}")
    except FileNotFoundError:
        print(f"Error: File {filename} not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading {filename}: {e}")
        sys.exit(1)
    return lines

def write_rcf_file(filename, lines):
    """Write list of 32-bit binary strings to RCF file"""
    try:
        with open(filename, 'w') as f:
            for line in lines:
                f.write(line + '\n')
    except Exception as e:
        print(f"Error writing {filename}: {e}")
        sys.exit(1)

def insert_rcf_at_index(base_rcf, insert_rcf, word_index, pad_value='11111111111111111111111111111111'):
    """
    Insert one RCF file into another at specified word index.
    
    Args:
        base_rcf: List of binary strings from base RCF file
        insert_rcf: List of binary strings to insert
        word_index: Word offset where to insert (0-based)
        pad_value: Binary string to use for padding (default is 0xFFFFFFFF)
    
    Returns:
        Combined list of binary strings
    """
    # If word_index is beyond current file, pad with pad_value
    while len(base_rcf) < word_index:
        base_rcf.append(pad_value)
    
    # Create result list
    result = []
    
    # Add everything before insertion point
    result.extend(base_rcf[:word_index])
    
    # Add inserted content
    result.extend(insert_rcf)
    
    # Optionally add remaining content from base after insertion
    # (uncomment if you want to preserve content after insertion point)
    # if word_index < len(base_rcf):
    #     result.extend(base_rcf[word_index:])
    
    return result

def hex_to_binary(hex_str):
    """Convert hex string to 32-bit binary string"""
    # Remove 0x prefix if present
    if hex_str.startswith('0x'):
        hex_str = hex_str[2:]
    
    try:
        # Convert to integer then to 32-bit binary
        num = int(hex_str, 16)
        return format(num, '032b')
    except ValueError:
        print(f"Error: Invalid hex value: {hex_str}")
        return None

def main():
    parser = argparse.ArgumentParser(
        description='Insert one RCF file into another at a specified word index',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # Insert test.rcf at word offset 0x8000 (32768) in base.rcf
  %(prog)s base.rcf test.rcf output.rcf --index 0x8000
  
  # Insert at decimal offset 1000
  %(prog)s base.rcf test.rcf output.rcf --index 1000
  
  # Use custom padding value (0x00000000 instead of 0xFFFFFFFF)
  %(prog)s base.rcf test.rcf output.rcf --index 0x8000 --pad 0x00000000
  
  # Specify byte offset instead of word offset
  %(prog)s base.rcf test.rcf output.rcf --byte-offset 0x20000
        '''
    )
    
    parser.add_argument('base_file', help='Base RCF file')
    parser.add_argument('insert_file', help='RCF file to insert')
    parser.add_argument('output_file', help='Output RCF file')
    parser.add_argument('--index', '-i', type=str, required=False,
                        help='Word index where to insert (hex with 0x prefix or decimal)')
    parser.add_argument('--byte-offset', '-b', type=str, required=False,
                        help='Byte offset where to insert (will be divided by 4)')
    parser.add_argument('--pad', '-p', type=str, default='0xFFFFFFFF',
                        help='Padding value in hex (default: 0xFFFFFFFF for erased flash)')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Verbose output')
    
    args = parser.parse_args()
    
    # Determine word index
    if args.index and args.byte_offset:
        print("Error: Cannot specify both --index and --byte-offset")
        sys.exit(1)
    elif args.byte_offset:
        # Convert byte offset to word index
        try:
            if args.byte_offset.startswith('0x'):
                byte_offset = int(args.byte_offset, 16)
            else:
                byte_offset = int(args.byte_offset)
            word_index = byte_offset // 4
            if args.verbose:
                print(f"Byte offset 0x{byte_offset:x} = word index {word_index}")
        except ValueError:
            print(f"Error: Invalid byte offset: {args.byte_offset}")
            sys.exit(1)
    elif args.index:
        try:
            if args.index.startswith('0x'):
                word_index = int(args.index, 16)
            else:
                word_index = int(args.index)
        except ValueError:
            print(f"Error: Invalid index: {args.index}")
            sys.exit(1)
    else:
        print("Error: Must specify either --index or --byte-offset")
        sys.exit(1)
    
    # Convert padding value to binary
    pad_binary = hex_to_binary(args.pad)
    if not pad_binary:
        sys.exit(1)
    
    if args.verbose:
        print(f"Reading base file: {args.base_file}")
    base_data = read_rcf_file(args.base_file)
    
    if args.verbose:
        print(f"Reading insert file: {args.insert_file}")
    insert_data = read_rcf_file(args.insert_file)
    
    if args.verbose:
        print(f"Base file has {len(base_data)} words")
        print(f"Insert file has {len(insert_data)} words")
        print(f"Inserting at word index {word_index} (byte offset 0x{word_index*4:x})")
    
    # Perform insertion
    result = insert_rcf_at_index(base_data, insert_data, word_index, pad_binary)
    
    # Write output
    write_rcf_file(args.output_file, result)
    
    if args.verbose:
        print(f"Output file has {len(result)} words")
    
    print(f"Successfully created {args.output_file}")
    print(f"  Base: {len(base_data)} words from {args.base_file}")
    print(f"  Insert: {len(insert_data)} words from {args.insert_file}")
    print(f"  Location: word {word_index} (byte 0x{word_index*4:08x})")
    print(f"  Total size: {len(result)} words ({len(result)*4} bytes)")
    
    # If this is for flash memory, show CPU address mapping
    if word_index >= 0x4000:  # Assuming flash starts at 0x10000 in CPU space
        cpu_address = 0x10000 + (word_index * 4)
        print(f"  CPU address (if flash at 0x10000): 0x{cpu_address:08x}")

if __name__ == "__main__":
    main()