#!/bin/bash
# usage: run.sh <workdir>. Builds errata.S and runs it without and with the CSR freeze.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
W="$1"
mkdir -p "$W"
cd "$W" || exit 2
set +u; source "$REPO/cdspaths.sh" >/dev/null; set -u
riscv-none-elf-gcc -march=rv32imac_zba_zbb_zbc_zbs_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
    -T "$HERE/link.ld" "$HERE/errata.S" -o e.elf || exit 1
/usr/bin/python3.6 "$HERE/mk_image.py" e.elf image.hex || exit 1
PC=$((16#$(riscv-none-elf-nm e.elf | awk '/ csr_rw$/{print $1}')))
M="${MYSHKIN_RTL:-$REPO/hdl/myshkin}"   # the tape-out RTL is ~/chips/myshkin/hdl/MCU
SRC="$M/constants.vhd $M/MemoryMap.vhd $M/sim/ClkGate.vhd"
for f in div alu extend regfile_sbirq irq_handler loadext store_ext \
         branch_valid datapath aludec maindec controller c_dec csr_unit pulse_extender vesta; do
    SRC="$SRC $M/vesta/$f.vhd"
done
echo 'run; exit' > go.tcl
for s in 0 1; do
    xrun -q -v200x -relax -controlrelax nlstex -access +r $SRC "$HERE/myshkin_core_tb.vhd" \
        -top myshkin_core_tb -gpg "myshkin_core_tb.STALL => $s" \
        -gpg "myshkin_core_tb.CSR_PC => $PC" -input go.tcl -l "run$s.log" > /dev/null 2>&1
    echo "--- STALL=$s"
    grep -E '^(END|SIG)|\*E' "run$s.log" | head -30
done
