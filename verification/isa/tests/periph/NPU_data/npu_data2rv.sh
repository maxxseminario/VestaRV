#!/bin/bash

# Script to convert all NPU files to RISC-V assembly format
# This script runs the npu_w2rv.sh converter on input, weight, and output files

echo "Converting NPU files to RISC-V assembly format..."
echo "=============================================="

# Convert input data
echo "Converting NPU inputs..."
./npu_w2rv.sh npu_fp_inputs.txt npu0_x.s 25

# Convert weights
echo "Converting NPU weights..."
./npu_w2rv.sh npu_fp_weights.txt npu0_w.s 32

# Convert expected outputs
echo "Converting NPU expected outputs..."
./npu_w2rv.sh npu_expected_fp_outputs.txt npu0_yhat.s 32

echo "=============================================="
echo "Conversion complete!"
echo "Generated files:"
echo "  - npu0_x.s (inputs)"
echo "  - npu0_w.s (weights)" 
echo "  - npu0_yhat.s (expected outputs)"