#!/bin/bash
# VestaRV: convert every RISC-V ELF under the working directory into a padded
# .rcf memory image. RISCV_PREFIX must name an objcopy; MEM_SIZE is the image
# size in bytes and must match the target memory.
MEM_SIZE=65536

for elf_file in $(find . -type f -exec file {} \; | grep "ELF 32-bit.*RISC-V" | cut -d: -f1); do
    base="${elf_file%.*}"
    echo "Processing $base..."
    
     ${RISCV_PREFIX} -O binary "$elf_file" "$base.bin"
    
    dd if=/dev/zero of="$base_padded.bin" bs=1 count=$MEM_SIZE
    dd if="$base.bin" of="$base_padded.bin" conv=notrunc
    
    od -v -An -tx4 -w4 "$base_padded.bin" | awk '{print $1}' > "$base.rcf"
done