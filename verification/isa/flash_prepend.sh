#!/bin/bash
# VestaRV: give every matched .rcf image the SPI-flash load and execute header.
#   ./flash_prepend.sh <file-filter> [target-basename-len]
# Each match is renamed so its basename is exactly TARGET_BASENAME_LEN characters
# (default 22, the length of "xxxxxxperiph-p-NPU.rcf"), padded with leading 'x',
# then rewritten in place with the header words prepended. Both steps are
# idempotent: existing leading x's are stripped first, and an image that already
# carries the command word is skipped.
TARGET_BASENAME_LEN="${2:-22}"

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

# The four header words, as the 32-bit binary strings an .rcf line carries.
line1="00010000101011011011111011101111"  # Command word (0x10adbeef)
line2="00000000000000001000000000000000"  # Start address for vectors (0x00008000)
line3="00000000000000001000001000000000"  # End address for vectors (0x00008200) - fill with zeros
line4="11001010111111101011101010111110"  # Execute (0xcafebabe)

# Where program code begins in memory.
program_start_address=0x8000
program_start_dec=$((program_start_address))

# 32-bit binary conversion in pure bash, with no interpreter. EDA environments
# such as Calibre's aoj_cal wrapper shadow python3 with a script that re-evals
# its arguments and strips the inner quotes, which turns a `python3 -c` call into
# a SyntaxError and leaves the segment-address lines empty in every image.
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

    # Rename to exactly TARGET_BASENAME_LEN characters in the basename.
    file_dir="$(dirname "$file")"
    file_base="$(basename "$file")"

    # Strip existing leading x's so re-running is idempotent.
    stripped_base="${file_base#"${file_base%%[!x]*}"}"

    base_len=${#stripped_base}
    pad_count=$(( TARGET_BASENAME_LEN - base_len ))
    if [ $pad_count -lt 0 ]; then
        echo "WARNING: '${stripped_base}' (${base_len} chars) exceeds TARGET_BASENAME_LEN=${TARGET_BASENAME_LEN}, skipping rename."
        pad_count=0
    fi

    # printf repeats its format once even with zero arguments, and `seq 1 0` is
    # empty, so a zero pad count must skip the printf entirely. Otherwise an
    # exactly-22-character name gains a spurious 'x' and TEST_FILE truncates.
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

    # Idempotency guard on the header, not just the name. `<group>-flash` in the
    # ISA Makefile globs rcf/*<group>*.rcf and runs this script over every match,
    # including orphaned images whose .S no longer exists and which make cannot
    # rebuild, so the file arriving here is the already-flashed one and grows by
    # one header per build. The guard is content based: $line1 is the 0x10adbeef
    # command word and cannot begin an un-flashed image, which starts with the
    # program's own first word. An mtime, a marker file or a name convention
    # would not answer the question actually being asked of the bytes.
    if [ "$(sed -n '1p' "$file")" = "$line1" ]; then
        echo "Already flashed, skipping: $file"
        continue
    fi

    echo "Formatting: $file ..."


    mapfile -t file_lines < "$file"
    total_lines=${#file_lines[@]}

    tmpfile=$(mktemp)
    
    # The interrupt vector area, 0x8000 to 0x81FF, zero filled: 128 words.
    echo "$line1" >> "$tmpfile"
    echo "$line2" >> "$tmpfile"
    echo "$line3" >> "$tmpfile"
    for ((z = 0; z < 128; z++)); do
        echo "00000000000000000000000000000000" >> "$tmpfile"
    done

    # Find the load regions. A zero program word must not be mistaken for an
    # inter-section gap and dropped: behavioural RTL memories zero-initialise and
    # mask the loss, while a gate or silicon TCM powers up X and the fetch
    # returns X. Two rules close that class, and both only ever add loaded words,
    # so every existing image consumer is unaffected.
    #   GAP_MIN: only a run of GAP_MIN or more zero words separates regions.
    #     Short zero runs are real content (alignment padding, zero constants,
    #     unimp landing pads) and stay inside the region.
    #   REGION_PAD: every region is extended by REGION_PAD trailing zero words.
    #     An instruction can straddle into a long zero run, heading it, which
    #     GAP_MIN alone cannot cover.
    GAP_MIN=8
    REGION_PAD=2

    # Collect the nonzero lines, merging runs separated by fewer than GAP_MIN
    # zeros into a single region.
    in_region=0
    region_start=0
    region_end=0        # last NONZERO line of the current region
    zero_run=0

    flush_region() {
        # Pad the region tail into the following zeros, clamped to EOF.
        local pend=$((region_end + REGION_PAD))
        [ $pend -ge $total_lines ] && pend=$((total_lines - 1))
        local seg_start_dec=$((program_start_dec + 4 * region_start))
        local seg_end_dec=$((program_start_dec + 4 * (pend + 1))) # not inclusive
        {
            echo "$line1"
            to_bin32 "$seg_start_dec"
            to_bin32 "$seg_end_dec"
            for ((j = region_start; j <= pend; j++)); do
                echo "${file_lines[j]}"
            done
        } >> "$tmpfile"
    }

    for ((i = 0; i < total_lines; i++)); do
        if [[ "${file_lines[i]}" == "00000000000000000000000000000000" ]]; then
            zero_run=$((zero_run + 1))
            if [ $in_region -eq 1 ] && [ $zero_run -ge $GAP_MIN ]; then
                flush_region
                in_region=0
            fi
        else
            if [ $in_region -eq 0 ]; then
                region_start=$i
                in_region=1
            fi
            region_end=$i
            zero_run=0
        fi
    done
    if [ $in_region -eq 1 ]; then
        flush_region
    fi

    # The execute command goes last.
    echo "$line4" >> "$tmpfile"

    mv "$tmpfile" "$file"
done
