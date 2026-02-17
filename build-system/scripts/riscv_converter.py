#!/usr/bin/env python3
import os
import sys
from elftools.elf.elffile import ELFFile
from capstone import Cs, CS_ARCH_RISCV, CS_MODE_RISCV32

def elf_to_bin(elf_path, bin_path):
    """Extract executable sections from ELF and write to binary file"""
    with open(elf_path, 'rb') as elf_file, open(bin_path, 'wb') as bin_file:
        elffile = ELFFile(elf_file)
        
        # Find the text section (where code lives)
        text_section = elffile.get_section_by_name('.text')
        if text_section:
            bin_file.write(text_section.data())
        else:
            # Fallback to executable segments
            for segment in elffile.iter_segments():
                if segment['p_type'] == 'PT_LOAD' and segment['p_flags'] & 0x1:
                    bin_file.write(segment.data())

def disassemble_riscv(instruction_bytes, address):
    """Disassemble RISC-V instruction and return detailed description"""
    md = Cs(CS_ARCH_RISCV, CS_MODE_RISCV32)
    md.detail = True
    
    # Skip disassembly for likely non-instruction data
    if address < 0x1000:
        return "(non-code section)"
    
    for insn in md.disasm(instruction_bytes, address):
        parts = [
            f"{insn.mnemonic.ljust(8)}",
            insn.op_str
        ]
        
        details = []
        if insn.id != 0:
            # Instruction type detection
            opcode = insn.bytes[0] & 0x7f
            if opcode in [0x37, 0x17]:  # LUI, AUIPC
                instr_type = "U-type"
            elif opcode == 0x6f:       # JAL
                instr_type = "J-type"
            elif opcode == 0x63:       # Branches
                instr_type = "B-type"
            elif opcode == 0x23:       # Stores
                instr_type = "S-type"
            elif opcode in [0x67, 0x03, 0x13]: # JALR, Loads, OPIMM
                instr_type = "I-type"
            elif opcode == 0x33:       # ALU ops
                instr_type = "R-type"
            else:
                instr_type = f"opcode:0x{opcode:02x}"
            
            details.append(instr_type)
            
            # Registers and immediates
            if insn.regs_read:
                details.append(f"rs:{','.join(insn.reg_name(r) for r in insn.regs_read)}")
            if insn.regs_write:
                details.append(f"rd:{insn.reg_name(insn.regs_write[0])}")
            for op in insn.operands:
                if op.type == 2:  # Immediate
                    details.append(f"imm:0x{op.value.imm:x}")
        
        return ' '.join(parts) + " | " + ', '.join(details)
    
    return "(data)"

# def bin_to_rcf_and_txt(bin_path, rcf_path, txt_path):
#     """Convert binary file to RCF and TXT with proper disassembly"""
#     with open(bin_path, 'rb') as bin_file, \
#          open(rcf_path, 'w') as rcf_file, \
#          open(txt_path, 'w') as txt_file:
        
#         # Start at typical text section address
#         address = 0x1000  
        
#         while True:
#             instruction = bin_file.read(4)
#             if not instruction:
#                 break
                
#             if len(instruction) < 4:
#                 instruction += b'\x00' * (4 - len(instruction))
            
#             # Binary output
#             binary_str = ''.join(f'{byte:08b}' for byte in instruction)
#             rcf_file.write(binary_str + '\n')
            
#             # Disassembly output
#             hex_str = instruction.hex()
#             disasm = disassemble_riscv(instruction, address)
#             txt_file.write(f"0x{address:08x}: {hex_str}  {disasm}\n")
            
#             address += 4

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <input.elf>")
        sys.exit(1)
    
    elf_path = sys.argv[1]
    base_path = os.path.splitext(elf_path)[0]
    
    bin_path = base_path + '.bin'
    rcf_path = base_path + '.rcf'
    txt_path = base_path + '.txt'
    
    # Convert ELF to binary
    elf_to_bin(elf_path, bin_path)
    print(f"Created binary file: {bin_path}")
    
    # Convert to RCF and TXT
    bin_to_rcf_and_txt(bin_path, rcf_path, txt_path)
    print(f"Created RCF file: {rcf_path}")
    print(f"Created TXT file: {txt_path}")

if __name__ == '__main__':
    main()
