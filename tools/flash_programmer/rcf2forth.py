#!/usr/bin/env python3
"""
rcf2forth.py - Convert an RCF (or Intel-Hex) program file into a plain-text
list of rv4th Forth commands that, when pasted/streamed into the ROM Forth
REPL, load the program into RAM and jump to it.

Each 32-bit word becomes one line of the form:
    0xVVVVVVVV 0xAAAAAAAA !

and the file ends with:
    0xEEEEEEEE call0

where EEEEEEEE is the entry address (default 0x8200).

Usage:
    python3 rcf2forth.py program.rcf                    # prints to stdout
    python3 rcf2forth.py program.rcf -o program.forth   # write to file
    python3 rcf2forth.py program.hex --entry 0x8200
    python3 rcf2forth.py program.rcf --no-jump          # omit final call0
    python3 rcf2forth.py program.rcf --skip-zero        # omit words that are 0

This is a pure offline translator -- it talks to no hardware. The output is
intended to be pasted into rv4th_terminal.py or fed via:
    cat program.forth > /dev/serial0

(note: for the serial-cat approach you almost certainly want one-word-at-a-time
pacing; prefer forthram.py --method poke for actual uploads.)
"""

import sys
import os
import argparse

# Re-use the parsers from forthram.py which lives next door.
_thisDir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _thisDir)
from forthram import (_rcf_to_byte_image,
                      _intel_hex_to_byte_image,
                      _image_to_contiguous_runs)


def _strToInt(s):
    s = s.strip()
    if s.lower().startswith('0x'):
        return int(s, 16)
    return int(s, 10)


def imageToForthLines(image, entry, addJump=True, skipZero=False):
    """Turn an address->byte dict into a list of Forth text lines.

    The image is walked as contiguous runs, each run is word-aligned
    (pad-tail with 0xFF if needed), and every 32-bit word emits one line:
        0xVVVVVVVV 0xAAAAAAAA !
    Finally, if addJump is True, append a `<entry> call0` line.
    """
    lines = []
    runs = _image_to_contiguous_runs(image)
    for (startAddr, data) in runs:
        # pad up to word boundary
        if len(data) % 4 != 0:
            data = data + b'\xff' * (4 - (len(data) % 4))
        for i in range(0, len(data), 4):
            w = (data[i + 0] <<  0 |
                 data[i + 1] <<  8 |
                 data[i + 2] << 16 |
                 data[i + 3] << 24)
            addr = startAddr + i
            if skipZero and w == 0:
                continue
            lines.append(f'0x{w:08X} 0x{addr:08X} !')
    if addJump:
        lines.append(f'0x{entry:08X} call0')
    return lines


def main():
    parser = argparse.ArgumentParser(
        description='Convert an RCF or Intel-Hex file into a list of rv4th '
                    'Forth commands (`<val> <addr> !` per word, optionally '
                    'followed by `<entry> call0`).')
    parser.add_argument('ProgramFile',
        help='Path to a .rcf or .hex file to translate.')
    parser.add_argument('-o', '--output', default=None,
        help='Write the Forth commands to this file. If omitted, prints '
             'to stdout.')
    parser.add_argument('--entry', type=_strToInt, default=0x8200,
        help='Entry point to jump to with call0 (default: 0x8200).')
    parser.add_argument('--no-jump', action='store_true',
        help='Do not emit the trailing "<entry> call0" line.')
    parser.add_argument('--skip-zero', action='store_true',
        help='Skip words whose value is 0x00000000. Useful when RAM is '
             'known to be zero-initialised by the bootloader; saves '
             'upload time at the cost of correctness if RAM is dirty.')
    parser.add_argument('--header', action='store_true',
        help='Prepend a human-readable comment header describing the '
             'program. Comments start with "\\" which rv4th ignores.')
    args = parser.parse_args()

    if not os.path.exists(args.ProgramFile):
        print(f'ERROR: file not found: {args.ProgramFile}', file=sys.stderr)
        sys.exit(1)

    # Parse file
    ext = os.path.splitext(args.ProgramFile)[1].lower()
    if ext == '.rcf':
        image = _rcf_to_byte_image(args.ProgramFile)
    elif ext in ('.hex', '.ihex'):
        image = _intel_hex_to_byte_image(args.ProgramFile)
    else:
        print(f'ERROR: unrecognised extension {ext!r}; expected .rcf or .hex',
              file=sys.stderr)
        sys.exit(1)

    if image is None or len(image) == 0:
        print('ERROR: no data parsed from input file', file=sys.stderr)
        sys.exit(1)

    runs = _image_to_contiguous_runs(image)
    totalBytes = sum(len(d) for (_a, d) in runs)

    lines = imageToForthLines(image, args.entry,
                              addJump=(not args.no_jump),
                              skipZero=args.skip_zero)

    out = []
    if args.header:
        out.append(f'\\ rcf2forth.py output')
        out.append(f'\\ source : {os.path.basename(args.ProgramFile)}')
        out.append(f'\\ bytes  : {totalBytes} across {len(runs)} segment(s)')
        for (a, d) in runs:
            out.append(f'\\ segment: 0x{a:08X} .. 0x{a + len(d):08X} '
                       f'({len(d)} bytes)')
        out.append(f'\\ entry  : 0x{args.entry:08X}')
        out.append(f'\\ lines  : {len(lines)}')
        out.append('')
    out.extend(lines)
    text = '\n'.join(out) + '\n'

    if args.output:
        with open(args.output, 'w') as f:
            f.write(text)
        print(f'Wrote {len(lines)} Forth line(s) ({totalBytes} RAM bytes) '
              f'to {args.output}', file=sys.stderr)
    else:
        sys.stdout.write(text)


if __name__ == '__main__':
    main()
