# VestaRV: NPU golden weight vector
# Emitted into its own section .npu0_w so the test can place it at the NPU's window; it is data, not code, despite the "ax" flags.
.section .npu0_w , "ax"
npu0_w:
# NPU Data Here
    .word 0xFE76A70A, 0xFE561906, 0xFFC25E27, 0x0004C163, 0xFBEE5EA8, 0xFC1ECEAD, 0xFEBD369D, 0x01657F72
    .word 0xFC0FAF23, 0x03CD76E9, 0x017790CB, 0x00F18BBD, 0x03D28D78, 0x014CFA13, 0x03FA77C4
