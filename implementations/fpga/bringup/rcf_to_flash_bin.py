#!/usr/bin/env python3
"""VestaRV: flashed RCF -> raw SPI-flash binary, for an external flash programmer.

Input is a *_flashed_rcf image: one 32-bit word per line as 32 ASCII '0'/'1' characters,
starting with the 0x10ADBEEF load command. Output is the bytes to write at flash address 0.

Each word is stored LITTLE-ENDIAN. The boot ROM reads the flash in 32-bit MSB-first frames
with SPIRXSB set (SPI_CR_LOADBEEF = 0x108C8, bit 16), which byte-swaps the received word, so
the first four flash bytes must be EF BE AD 10. hdl/common/tb/serial_flash.vhd serves the
same order (flash byte 4n is word n bits 7:0) and so does ProgramFlash.WriteRcfFile.
"""

import sys

CMD_LOAD = 0x10ADBEEF
CMD_EXEC = 0xCAFEBABE


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: rcf_to_flash_bin.py IN.rcf OUT.bin")
    words = []
    with open(sys.argv[1]) as f:
        for n, line in enumerate(f, 1):
            s = line.strip()
            if not s:
                continue
            if len(s) != 32 or set(s) - {"0", "1"}:
                sys.exit("rcf_to_flash_bin: line %d is not a 32-bit binary word: %r" % (n, s))
            words.append(int(s, 2))
    if not words or words[0] != CMD_LOAD:
        sys.exit("rcf_to_flash_bin: first word is not 0x10ADBEEF; is this a *_flashed_rcf image?")
    if CMD_EXEC not in words:
        sys.exit("rcf_to_flash_bin: no 0xCAFEBABE execute command; the ROM would trap")
    with open(sys.argv[2], "wb") as f:
        f.write(b"".join(w.to_bytes(4, "little") for w in words))


if __name__ == "__main__":
    main()
