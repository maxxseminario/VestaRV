#!/bin/bash
# Build csr_stall.S, run it on Spike and on the chip at each named hart, print the
# words side by side. usage: [TEST=mis_trap] run_repro.sh <workdir> <hart> [<hart> ...]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; RS="$HERE/.."
W="$1"; shift
mkdir -p "$W"; cd "$W" || exit 2
TEST="${TEST:-csr_stall}"
G="riscv-none-elf-gcc -march=rv32iac_zicsr -mabi=ilp32 -DXLEN=32 -static -mcmodel=medany -nostdlib -nostartfiles"
$G -T "$RS/vesta/env/link.ld" -I "$RS/vesta/env" "$RS/vesta/env/vesta_stub.S" "$HERE/$TEST.S" -o dut.elf || exit 1
$G -T "$RS/ref/env/link.ld" -I "$RS/ref/env" "$HERE/$TEST.S" -o ref.elf 2>/dev/null || exit 1
source "$HOME/local/spike_env.sh"
E=$(riscv-none-elf-nm ref.elf | awk '/ rvtest_entry_point$/{print "0x"$1}')
spike --isa=rv32iac_zicsr --priv=m --pmpregions=0 -m0x8000:0x200000 --disable-dtb --pc="$E" \
    +signature=spike.sig +signature-granularity=4 ref.elf
cols=(spike.sig)
for h in "$@"; do
    mkdir -p "h$h/img"
    /usr/bin/python3.6 "$RS/sim/mk_rcf.py" dut.elf "h$h/img/image.rcf" "$h" preload
    "$RS/sim/run_test.sh" "h$h/img/image.rcf" "h$h/run" 120 && cp "h$h/run/signature.out" "h$h.sig"
    cols+=("h$h.sig")
done
echo "row: spike ${cols[*]:1}"
paste "${cols[@]}"
for c in "${cols[@]:1}"; do cmp spike.sig "$c" && echo "$c matches spike"; done
