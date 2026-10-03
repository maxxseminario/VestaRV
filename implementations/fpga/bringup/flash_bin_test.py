#!/usr/bin/env python3
"""VestaRV: gate on the flash binary handed to the board: byte order and length.

argv: the flashed RCF, the converted binary.
"""

import sys

rcf, binary = sys.argv[1], sys.argv[2]
words = [ln.strip() for ln in open(rcf) if ln.strip()]
data = open(binary, "rb").read()

if data[:4] != bytes([0xEF, 0xBE, 0xAD, 0x10]):
    sys.exit("FAIL: first four bytes are %s, want ef be ad 10" % data[:4].hex(" "))
if len(data) != 4 * len(words):
    sys.exit("FAIL: %d bytes for %d words" % (len(data), len(words)))
for i, w in enumerate(words):
    if int.from_bytes(data[4 * i:4 * i + 4], "little") != int(w, 2):
        sys.exit("FAIL: word %d differs" % i)
print("PASS: %d words, little-endian, starts ef be ad 10" % len(words))
