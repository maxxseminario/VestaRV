#!/usr/bin/env python3
import sys

# Get test names from command line
tests = sys.argv[1:]

header = """/* Auto-generated test globals */
.section .data
.global tohost, fromhost
tohost: .word 0
fromhost: .word 0
"""

with open('include/test_globals.S', 'w') as f:
    f.write(header)
    for test in tests:
        test_name = test.split('/')[-1].split('.')[0]
        f.write(f".global {test_name}_ret\n")
        f.write(f"{test_name}_ret: .word 0\n\n")