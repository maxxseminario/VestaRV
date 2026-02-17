#!/bin/bash

# Check if input file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <weights_file.txt> [output_file.s] [bits_to_keep]"
    echo "Example: $0 weights.txt neural_network.s 16"
    echo "  bits_to_keep: Number of bottom bits to keep (default: 32, all bits)"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-output.s}"
BITS_TO_KEEP="${3:-32}"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

# Validate bits_to_keep parameter
if ! [[ "$BITS_TO_KEEP" =~ ^[0-9]+$ ]] || [ "$BITS_TO_KEEP" -lt 1 ] || [ "$BITS_TO_KEEP" -gt 32 ]; then
    echo "Error: bits_to_keep must be a number between 1 and 32"
    exit 1
fi

# Extract filename without extension for section name
SECTION_NAME=$(basename "$OUTPUT_FILE" .s)

# Function to convert signed decimal to hexadecimal with specified bit masking
decimal_to_hex() {
    local decimal=$1
    local bits=$2
    
    # Create mask for the specified number of bits using bc for safety
    local mask=$(echo "2^$bits - 1" | bc)
    
    # Mask the value to keep only the bottom N bits
    local masked_value=$(( decimal & mask ))
    
    # Format as 32-bit hex with leading zeros
    printf "0x%08X" $masked_value
}

# Read weights from file into array
mapfile -t weights < "$INPUT_FILE"

# Remove empty lines and trim whitespace
weights_clean=()
for weight in "${weights[@]}"; do
    # Trim whitespace and check if not empty
    weight=$(echo "$weight" | tr -d '[:space:]')
    if [ -n "$weight" ]; then
        weights_clean+=("$weight")
    fi
done

echo "Processing ${#weights_clean[@]} weights from $INPUT_FILE"
echo "Keeping bottom $BITS_TO_KEEP bits (top $((32 - BITS_TO_KEEP)) bits will be zero)"

# Create output file with dynamic section name
cat > "$OUTPUT_FILE" << EOF
# NPU Test Weights
.section .$SECTION_NAME , "ax"
$SECTION_NAME:
# NPU Data Here
EOF

# Convert weights to hex and write to file
hex_weights=()
for weight in "${weights_clean[@]}"; do
    hex_weight=$(decimal_to_hex "$weight" "$BITS_TO_KEEP")
    hex_weights+=("$hex_weight")
done

# Write weights in groups of 8 per line
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

# Show first few lines of output
echo ""
echo "Preview of generated assembly:"
head -10 "$OUTPUT_FILE"
if [ ${#weights_clean[@]} -gt 32 ]; then
    echo "... (output truncated)"
fi