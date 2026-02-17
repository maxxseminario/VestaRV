#!/bin/bash
MEM_SIZE=65536  # Adjust to your ROM size

for elf_file in $(find . -type f -exec file {} \; | grep "ELF 32-bit.*RISC-V" | cut -d: -f1); do
    base="${elf_file%.*}"
    echo "Processing $base..."
    
    # Step 2: Generate binary
     ${RISCV_PREFIX} -O binary "$elf_file" "$base.bin"
    
    # Step 3: Pad binary
    dd if=/dev/zero of="$base_padded.bin" bs=1 count=$MEM_SIZE
    dd if="$base.bin" of="$base_padded.bin" conv=notrunc
    
    # Step 4: Generate RCF
    od -v -An -tx4 -w4 "$base_padded.bin" | awk '{print $1}' > "$base.rcf"
done