#!/bin/bash
# VestaRV: convert the NPU input, weight and expected-output vectors to RISC-V
# assembly. Wraps npu_w2rv.sh; the third argument is the fixed-point width.

echo "Converting NPU files to RISC-V assembly format..."
echo "=============================================="

echo "Converting NPU inputs..."
./npu_w2rv.sh npu_fp_inputs.txt npu0_x.s 25

echo "Converting NPU weights..."
./npu_w2rv.sh npu_fp_weights.txt npu0_w.s 32

echo "Converting NPU expected outputs..."
./npu_w2rv.sh npu_expected_fp_outputs.txt npu0_yhat.s 32

echo "=============================================="
echo "Conversion complete!"
echo "Generated files:"
echo "  - npu0_x.s (inputs)"
echo "  - npu0_w.s (weights)" 
echo "  - npu0_yhat.s (expected outputs)"