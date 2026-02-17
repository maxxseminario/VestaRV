#!/bin/bash

# Usage: ./flash_insert_line.sh <file-filter>
# Example: ./flash_insert_line.sh "*periph*.rcf"

# Function to convert decimal to binary with padding
dec_to_bin() {
    local num=$1
    local padding=${2:-32}
    echo "obase=2; $num" | bc | xargs printf "%0${padding}s"
}

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file-filter>"
    echo "Example: $0 \"*rv32*.rcf\""
    exit 1
fi

filter="$1"

# Define the binary strings for each hex value
line1="00010000101011011011111011101111"  # Command word (0x10adbeef)
line2="00000000000000001000000000000000"  # Start address (program) (0x00008000)
line4="11001010111111101011101010111110"  # Execute (0xcafebabe)

# Convert line2 (start address) to decimal for calculation
start_dec=$((2#${line2}))

shopt -s nullglob
for file in $filter; do
    [ -e "$file" ] || continue

    echo "Formatting: $file ..."

    # Read file into array for processing
    mapfile -t file_lines < "$file"
    total_lines=${#file_lines[@]}

    # We'll find all contiguous nonzero regions
    in_region=0
    region_start=0
    region_end=0

    tmpfile=$(mktemp)

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
                seg_start_dec=$((start_dec + 4 * region_start))
                seg_end_dec=$((start_dec + 4 * (region_end + 1))) # not inclusive
                seg_start_bin=$(python3 -c "print(format($seg_start_dec, '032b'))")
                seg_end_bin=$(python3 -c "print(format($seg_end_dec, '032b'))")

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