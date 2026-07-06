#!/bin/bash

# Usage: ./flash_insert_line.sh <file-filter> [target-basename-len]
# Example: ./flash_insert_line.sh "*periph*.rcf"
#          ./flash_insert_line.sh "*periph*.rcf" 22
#
# All matched .rcf files will be:
#   1. Renamed so their basename is exactly TARGET_BASENAME_LEN characters,
#      padded with leading 'x' characters (any existing leading x's are stripped
#      first so re-running is idempotent).
#   2. Modified in-place to prepend the SPI flash load/execute header words.
#
# TARGET_BASENAME_LEN is the basename length to pad to.
# Reference: "xxxxxxperiph-p-NPU.rcf" has length 22.
TARGET_BASENAME_LEN="${2:-22}"

# Function to convert decimal to binary with padding
dec_to_bin() {
    local num=$1
    local padding=${2:-32}
    echo "obase=2; $num" | bc | xargs printf "%0${padding}s"
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <file-filter> [target-basename-len]"
    echo "Example: $0 \"*rv32*.rcf\""
    echo "         $0 \"*rv32*.rcf\" 22"
    exit 1
fi

filter="$1"

# Define the binary strings for each hex value
line1="00010000101011011011111011101111"  # Command word (0x10adbeef)
line2="00000000000000001000000000000000"  # Start address for vectors (0x00008000)
line3="00000000000000001000001000000000"  # End address for vectors (0x00008200) - fill with zeros
line4="11001010111111101011101010111110"  # Execute (0xcafebabe)

# Start address where actual program code begins in memory
program_start_address=0x8000
# Convert to decimal
program_start_dec=$((program_start_address))

# 32-bit binary conversion in PURE BASH. This used to shell out to
# `python3 -c "print(format(N, '032b'))"`, but EDA environments (Calibre's
# aoj_cal wrapper) can shadow python3 with a script that re-evals its
# arguments, stripping the inner quotes -> SyntaxError -> EMPTY segment-
# address lines silently corrupting every image. No interpreter, no problem.
to_bin32() {
    local n=$1 out="" k
    for ((k = 31; k >= 0; k--)); do
        out+=$(( (n >> k) & 1 ))
    done
    printf '%s\n' "$out"
}

shopt -s nullglob
for file in $filter; do
    [ -e "$file" ] || continue

    # ---- Rename file to have exactly TARGET_BASENAME_LEN chars in basename ----
    file_dir="$(dirname "$file")"
    file_base="$(basename "$file")"

    # Strip any existing leading x's so re-running is idempotent
    stripped_base="${file_base#"${file_base%%[!x]*}"}"

    base_len=${#stripped_base}
    pad_count=$(( TARGET_BASENAME_LEN - base_len ))
    if [ $pad_count -lt 0 ]; then
        echo "WARNING: '${stripped_base}' (${base_len} chars) exceeds TARGET_BASENAME_LEN=${TARGET_BASENAME_LEN}, skipping rename."
        pad_count=0
    fi

    # NOTE: printf repeats its format once even with ZERO args (seq 1 0 is
    # empty), which used to prepend a spurious 'x' to exactly-22-char names
    # (23 chars -> truncated TEST_FILE -> "Test file not found").
    if [ "$pad_count" -gt 0 ]; then
        x_prefix=$(printf '%0.s x' $(seq 1 "$pad_count") | tr -d ' ')
    else
        x_prefix=""
    fi
    new_base="${x_prefix}${stripped_base}"
    new_file="${file_dir}/${new_base}"

    if [ "$file_base" != "$new_base" ]; then
        mv -- "$file" "$new_file"
        echo "Renamed: ${file_base} -> ${new_base}"
        file="$new_file"
    fi
    # -------------------------------------------------------------------------

    echo "Formatting: $file ..."


    # Read file into array for processing
    mapfile -t file_lines < "$file"
    total_lines=${#file_lines[@]}

    tmpfile=$(mktemp)
    
    # First, write the interrupt vector area (0x8000 to 0x8200) filled with zeros
    # This is 512 bytes = 128 words
    echo "$line1" >> "$tmpfile"
    echo "$line2" >> "$tmpfile"
    echo "$line3" >> "$tmpfile"
    # Write 128 zero words (512 bytes from 0x8000 to 0x81FF)
    for ((z = 0; z < 128; z++)); do
        echo "00000000000000000000000000000000" >> "$tmpfile"
    done

    # Now process the actual program data starting at 0x8200
    # We'll find all contiguous nonzero regions
    in_region=0
    region_start=0
    region_end=0

    for ((i = 0; i <= total_lines; i++)); do
        line="${file_lines[i]}"
        
        # Check if current line is zero
        is_current_zero=0
        if [[ $i -lt $total_lines ]] && [[ "$line" == "00000000000000000000000000000000" ]]; then
            is_current_zero=1
        fi
        
        # Check if next line is also zero (for consecutive zero detection)
        is_next_zero=0
        if [[ $((i + 1)) -lt $total_lines ]] && [[ "${file_lines[$((i + 1))]}" == "00000000000000000000000000000000" ]]; then
            is_next_zero=1
        fi
        
        # A line is considered "separator" if it's part of two consecutive zeros
        # OR if we're at EOF
        is_separator=0
        if [[ $i -eq $total_lines ]]; then
            # EOF
            is_separator=1
        elif [[ $is_current_zero -eq 1 && $is_next_zero -eq 1 ]]; then
            # Current and next are both zero - this is start of consecutive zeros
            is_separator=1
        elif [[ $i -gt 0 ]]; then
            # Check if previous line was zero and current is zero (end of consecutive zeros)
            prev_line="${file_lines[$((i - 1))]}"
            if [[ "$prev_line" == "00000000000000000000000000000000" ]] && [[ $is_current_zero -eq 1 ]]; then
                is_separator=1
            fi
        fi
        
        if [[ $i -lt $total_lines ]] && [[ $is_separator -eq 0 ]]; then
            # Non-separator line: start or continue a region
            if [ $in_region -eq 0 ]; then
                region_start=$i
                in_region=1
            fi
            region_end=$i
        else
            # Separator or EOF: if we were in a region, end it
            if [ $in_region -eq 1 ]; then
                # region_start ... region_end is a region to be written
                # Calculate addresses based on program starting at 0x8200
                seg_start_dec=$((program_start_dec + 4 * region_start))
                seg_end_dec=$((program_start_dec + 4 * (region_end + 1))) # not inclusive
                seg_start_bin=$(to_bin32 "$seg_start_dec")
                seg_end_bin=$(to_bin32 "$seg_end_dec")

                # Write loadSegment command
                echo "$line1" >> "$tmpfile"
                echo "$seg_start_bin" >> "$tmpfile"
                echo "$seg_end_bin" >> "$tmpfile"

                # Write the data
                for ((j = region_start; j <= region_end; j++)); do
                    echo "${file_lines[j]}" >> "$tmpfile"
                done

                in_region=0
            fi
            # Otherwise, continue looking for next region
        fi
    done

    # Write the execute command (Line4) at the very end
    echo "$line4" >> "$tmpfile"

    mv "$tmpfile" "$file"
done

# #!/bin/bash

# # Usage: ./flash_insert_line.sh <file-filter>
# # Example: ./flash_insert_line.sh "*periph*.rcf"

# # Function to convert decimal to binary with padding
# dec_to_bin() {
#     local num=$1
#     local padding=${2:-32}
#     echo "obase=2; $num" | bc | xargs printf "%0${padding}s"
# }

# if [ $# -ne 1 ]; then
#     echo "Usage: $0 <file-filter>"
#     echo "Example: $0 \"*rv32*.rcf\""
#     exit 1
# fi

# filter="$1"

# # Define the binary strings for each hex value
# line1="00010000101011011011111011101111"  # Command word (0x10adbeef)
# line2="00000000000000001000000000000000"  # Start address (program)
# line4="11001010111111101011101010111110"  # Execute (0xcafebabe)

# # Convert line2 (start address) to decimal for calculation
# start_dec=$((2#${line2}))

# shopt -s nullglob
# for file in $filter; do
#     [ -e "$file" ] || continue

#     echo "Formatting: $file ..."

#     # Read file into array for processing
#     mapfile -t file_lines < "$file"
#     total_lines=${#file_lines[@]}

#     # We'll find all contiguous nonzero regions
#     in_region=0
#     region_start=0
#     region_end=0

#     tmpfile=$(mktemp)

#     for ((i = 0; i <= total_lines; i++)); do
#         line="${file_lines[i]}"
#         if [[ $i -lt $total_lines ]] && [[ "$line" != "00000000000000000000000000000000" ]]; then
#             # Nonzero line: start or continue a region
#             if [ $in_region -eq 0 ]; then
#                 region_start=$i
#                 in_region=1
#             fi
#             region_end=$i
#         else
#             # Zero line or EOF: if we were in a region, end it
#             if [ $in_region -eq 1 ]; then
#                 # region_start ... region_end is a region to be written
#                 seg_start_dec=$((start_dec + 4 * region_start))
#                 seg_end_dec=$((start_dec + 4 * (region_end + 1))) # not inclusive
#                 seg_start_bin=$(python3 -c "print(format($seg_start_dec, '032b'))")
#                 seg_end_bin=$(python3 -c "print(format($seg_end_dec, '032b'))")

#                 # Write loadSegment command
#                 echo "$line1" >> "$tmpfile"
#                 echo "$seg_start_bin" >> "$tmpfile"
#                 echo "$seg_end_bin" >> "$tmpfile"

#                 # Write the data
#                 for ((j = region_start; j <= region_end; j++)); do
#                     echo "${file_lines[j]}" >> "$tmpfile"
#                 done

#                 in_region=0
#             fi
#             # Otherwise, continue looking for next region
#         fi
#     done

#     # Write the execute command (Line4) at the very end
#     echo "$line4" >> "$tmpfile"

#     mv "$tmpfile" "$file"
# done