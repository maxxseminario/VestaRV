#!/usr/bin/python3.6
"""mk_image.py hex to a Myshkin flash stream: 0x10ADBEEF, start, end, words, 0xCAFEBABE.

usage: mk_rcf.py <hex> <rcf> <end address>
"""
import sys

src, out, end = sys.argv[1], sys.argv[2], int(sys.argv[3], 16)
words = [int(line, 16) for line in open(src)][:(end - 0x8000) // 4]
stream = [0x10ADBEEF, 0x8000, end] + words + [0xCAFEBABE]
open(out, 'w').write(''.join('{:032b}\n'.format(word) for word in stream))
