#!/bin/bash
# =============================================================================
# build_one_rcf.sh -- build ONE rv32ua test image out of tree, without touching
# verification/isa/build/ or its .imgset.
#
#   ./tools/build_one_rcf.sh <src.S> <basename> [extra -D flags ...]
#   ./tools/build_one_rcf.sh tests/rv32ua/dbgdenymp.S rv32ua-p-dbgdenymp
#   ./tools/build_one_rcf.sh tests/rv32ua/dbgdenymp.S rv32ua-p-ddnc7b0 -DDBGDENY_NC_7B0
#
# WHY IT EXISTS.  `make rv32ua-flash` is the right tool for the standing image
# set and the wrong tool for a single staged instrument or a negative control:
#   * `build/` is WIPED whenever `build/.imgset` changes (CLAUDE.md), so adding
#     one test name to a Makefrag destroys and rebuilds every rv32ua image --
#     shared state, and the reason only one agent works in this tree at a time;
#   * a per-test `-D` control arm has no expression in the Makefrag at all;
#   * `make <suite>-flash` re-prepends the SPI header over a glob, and a STALE
#     .rcf in rcf/ picks up a SECOND header (the K5 026a0ae trap) -- an image
#     that traps at 0x8200 with instr_curr = 0 and looks exactly like a core bug.
# This script builds into its own directory, prepends exactly once, and writes
# the finished padded image straight to rcf/ with `rm -f` first (the safe idiom).
#
# It replicates the Makefile recipe verbatim; if that recipe ever changes, this
# file is wrong and the drift will show up as an image that does not boot.
#   arch:    -march=rv32imac -mabi=ilp32           (Makefile:278, rv32ua)
#   opts:    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles
#   image:   MEM_SIZE 0x14000 -> 20480 words, BIN_OFFSET 0
#   header:  flash_prepend.sh, applied ONCE, name padded to 22 chars
# =============================================================================
set -e

SRC="${1:?usage: build_one_rcf.sh <src.S> <basename> [extra -D ...]}"
BASE="${2:?usage: build_one_rcf.sh <src.S> <basename> [extra -D ...]}"
shift 2
EXTRA=("$@")

cd "$(dirname "$0")/.."          # verification/isa
ISA_DIR="$PWD"
OUT="$ISA_DIR/build_oneoff/$BASE"
rm -rf "$OUT"; mkdir -p "$OUT"

PREFIX=riscv-none-elf-
ARCH="-march=rv32imac -mabi=ilp32"
OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"
WORDS=20480                      # MEM_SIZE 0x14000 / 4

${PREFIX}gcc $ARCH $OPTS "${EXTRA[@]}" \
    -I"$ISA_DIR/../env/p" -I"$ISA_DIR/macros/scalar" \
    -I"$ISA_DIR/../../platform/myshkin/gcc/lib/include" \
    -T"$ISA_DIR/../env/p/link.ld" "$ISA_DIR/$SRC" -o "$OUT/$BASE"

${PREFIX}objdump --disassemble-all --disassemble-zeroes \
    --section=.text --section=.text.init --section=.ivt --section=.data \
    "$OUT/$BASE" > "$OUT/$BASE.dump"

${PREFIX}objcopy -O binary --gap-fill=0x00 "$OUT/$BASE" "$OUT/$BASE.bin"
dd if=/dev/zero of="$OUT/${BASE}_padded.bin" bs=81920 count=1 2>/dev/null
dd if="$OUT/$BASE.bin" of="$OUT/${BASE}_padded.bin" bs=1 seek=0 conv=notrunc 2>/dev/null

od -v -An -tx4 -w4 "$OUT/${BASE}_padded.bin" | awk '
{ hex=$1; bin="";
  for (i=1;i<=8;i++) { c=substr(hex,i,1);
    if (c=="0") bin=bin "0000"; else if (c=="1") bin=bin "0001";
    else if (c=="2") bin=bin "0010"; else if (c=="3") bin=bin "0011";
    else if (c=="4") bin=bin "0100"; else if (c=="5") bin=bin "0101";
    else if (c=="6") bin=bin "0110"; else if (c=="7") bin=bin "0111";
    else if (c=="8") bin=bin "1000"; else if (c=="9") bin=bin "1001";
    else if (c=="a") bin=bin "1010"; else if (c=="b") bin=bin "1011";
    else if (c=="c") bin=bin "1100"; else if (c=="d") bin=bin "1101";
    else if (c=="e") bin=bin "1110"; else if (c=="f") bin=bin "1111"; }
  print bin; }' > "$OUT/$BASE.rcf"

LINES=$(wc -l < "$OUT/$BASE.rcf")
if [ "$LINES" -ne "$WORDS" ]; then
    echo "FATAL: $OUT/$BASE.rcf has $LINES lines (expected $WORDS)"; exit 2
fi

# pad the basename to 22 chars with leading x's, exactly as pad_all_rcf does
NAME="$BASE.rcf"
PAD=$((22 - ${#NAME})); [ $PAD -lt 0 ] && PAD=0
PADDED="$(printf '%*s' $PAD '' | tr ' ' x)$NAME"
[ "$PADDED" != "$NAME" ] && mv "$OUT/$NAME" "$OUT/$PADDED"

# prepend the SPI flash header EXACTLY ONCE, in the one-off dir
( cd "$ISA_DIR" && ./flash_prepend.sh "build_oneoff/$BASE/$PADDED" )

# rm -f FIRST, then copy -- never let a stale destination take a second header
rm -f "$ISA_DIR/rcf/$PADDED"
cp "$OUT/$PADDED" "$ISA_DIR/rcf/$PADDED"
echo "wrote rcf/$PADDED  ($(wc -l < "$ISA_DIR/rcf/$PADDED") lines)"
echo "dump: $OUT/$BASE.dump"
