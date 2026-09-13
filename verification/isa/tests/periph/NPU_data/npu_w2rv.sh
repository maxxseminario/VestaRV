#!/bin/bash
# VestaRV: convert one column of signed decimal NPU values into a RISC-V .word
# table. The section name is the output basename; bits_to_keep masks each value
# to its bottom N bits, which is how a narrower NPU datapath is modelled.
#   ./npu_w2rv.sh <weights_file.txt> [output_file.s] [bits_to_keep]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <weights_file.txt> [output_file.s] [bits_to_keep]"
    echo "Example: $0 weights.txt neural_network.s 16"
    echo "  bits_to_keep: Number of bottom bits to keep (default: 32, all bits)"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-output.s}"
BITS_TO_KEEP="${3:-32}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

if ! [[ "$BITS_TO_KEEP" =~ ^[0-9]+$ ]] || [ "$BITS_TO_KEEP" -lt 1 ] || [ "$BITS_TO_KEEP" -gt 32 ]; then
    echo "Error: bits_to_keep must be a number between 1 and 32"
    exit 1
fi

SECTION_NAME=$(basename "$OUTPUT_FILE" .s)

# Signed decimal to 32-bit hex, masked to the bottom $bits bits.
decimal_to_hex() {
    local decimal=$1
    local bits=$2
    
    # bc builds the mask: 2^32 - 1 overflows a shell arithmetic left shift.
    local mask=$(echo "2^$bits - 1" | bc)
    local masked_value=$(( decimal & mask ))
    printf "0x%08X" $masked_value
}

mapfile -t weights < "$INPUT_FILE"

# Drop empty lines and trim whitespace.
weights_clean=()
for weight in "${weights[@]}"; do
    weight=$(echo "$weight" | tr -d '[:space:]')
    if [ -n "$weight" ]; then
        weights_clean+=("$weight")
    fi
done

echo "Processing ${#weights_clean[@]} weights from $INPUT_FILE"
echo "Keeping bottom $BITS_TO_KEEP bits (top $((32 - BITS_TO_KEEP)) bits will be zero)"

cat > "$OUTPUT_FILE" << EOF
# NPU Test Weights
.section .$SECTION_NAME , "ax"
$SECTION_NAME:
# NPU Data Here
EOF

hex_weights=()
for weight in "${weights_clean[@]}"; do
    hex_weight=$(decimal_to_hex "$weight" "$BITS_TO_KEEP")
    hex_weights+=("$hex_weight")
done

# Eight values per .word directive.
for ((i=0; i<${#hex_weights[@]}; i+=8)); do
    line="    .word "
    for ((j=0; j<8 && i+j<${#hex_weights[@]}; j++)); do
        if [ $j -eq 0 ]; then
            line+="${hex_weights[i+j]}"
        else
            line+=", ${hex_weights[i+j]}"
        fi
    done
    echo "$line" >> "$OUTPUT_FILE"
done

echo "Assembly file created: $OUTPUT_FILE"
echo "Section name: .$SECTION_NAME"
echo "Converted ${#weights_clean[@]} weights to hexadecimal format"

echo ""
echo "Preview of generated assembly:"
head -10 "$OUTPUT_FILE"
if [ ${#weights_clean[@]} -gt 32 ]; then
    echo "... (output truncated)"
fi