#!/bin/bash
# usage: [TEST=flash] chip.sh <workdir> <behavioral|innovus> [hdl dir]
# Runs errata.S -DCHIP on the complete Myshkin chip through the original riscv_tb flow.
# innovus is MCU.xsim.v with the sign-off SDF. Nothing is written under ~/chips: the work
# directory holds symlinks to it, and the mask image comes from the ROM compiler's output
# of 2025-11-18 because ip/rom_hvt_pg/rom_hvt_pg_verilog.rcf has since been overwritten.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
T=/home/mseminario2/chips/myshkin
W="$1"; KIND="$2"; HDL="${3:-$T/hdl}"
R="$W/xcelium/riscv_test"; D="$R/$KIND"
mkdir -p "$D/log" "$R/rcf"
ln -sfn "$HDL" "$W/hdl"; ln -sfn "$T/ip" "$W/ip"; ln -sfn "$T/innovus" "$W/innovus"
ln -sfn "$T/genus" "$W/genus"
cp "$T/xcelium/disable_x_warnings.tcl" "$W/xcelium/"
set +u; source "$REPO/cdspaths.sh" >/dev/null; set -u
cd "$D" || exit 2
CC="riscv-none-elf-gcc -march=rv32imac_zba_zbb_zbc_zbs_zicsr -mabi=ilp32 -nostdlib -nostartfiles"
if [ "${TEST:-chip}" = flash ]; then
    # The bench routes the flash for SPIFM names, and the UART shorts for UART names.
    RCF=xxxxxmyshkin-SPIFM.rcf
    $CC -I"$T/riscv-tests/isa/macros/scalar" -T "$HERE/link_flash.ld" "$HERE/errata_flash.S" -o e.elf || exit 1
    /usr/bin/python3.6 "$HERE/mk_image.py" e.elf image.hex || exit 1
    /usr/bin/python3.6 "$HERE/mk_rcf.py" image.hex "../rcf/$RCF" 0x8400 || exit 1
    riscv-none-elf-objcopy -O binary -j .flash e.elf flash.bin || exit 1
    /usr/bin/python3.6 -c "
import struct, sys
lines = open('../rcf/$RCF').read().split()
assert len(lines) < 0x800
lines += ['0' * 32] * (0x800 - len(lines))
data = open('flash.bin', 'rb').read()
data += bytes(-len(data) % 4)
lines += ['{:032b}'.format(w) for w in struct.unpack('<%dI' % (len(data) // 4), data)]
open('../rcf/$RCF', 'w').write('\\n'.join(lines) + '\\n')
" || exit 1
else
    RCF=xxxxxxmyshkin-UART.rcf
    $CC -DCHIP -T "$HERE/link.ld" "$HERE/errata.S" -o e.elf || exit 1
    /usr/bin/python3.6 "$HERE/mk_image.py" e.elf image.hex || exit 1
    /usr/bin/python3.6 "$HERE/mk_rcf.py" image.hex "../rcf/$RCF" 0x9200 || exit 1
fi
TOP=$(riscv-none-elf-nm -n e.elf | awk '$3!="" {a=$1} END{print a}')
echo "last symbol at 0x$TOP"
cp "$T/ip/rom_hvt_pg/rom_hvt_pg_tmax.rcf" rom_hvt_pg_verilog.rcf
cp rom_hvt_pg_verilog.rcf ../rcf/rom_hvt_pg_verilog.rcf
# Local bench: the one test, and a monitor that prints a0 once it settles.
/usr/bin/python3.6 - "$HDL/MCU/tb" "$RCF" <<'PY'
import re, sys
tb, rcf = sys.argv[1:3]
d = open(tb + '/tb_defs.vhd', newline='').read()
a = d.index('constant test_files : file_array := (')
b = d.index(');', a)
d = d[:a] + 'constant test_files : file_array := (0 => "../rcf/' + rcf + '"' + d[b:]
open('tb_defs.vhd', 'w', newline='').write(d)
t = open(tb + '/riscv_tb.vhd', newline='').read()
mon = '''
    a0_mon : process
        function hx(v : std_logic_vector(31 downto 0)) return string is
            constant h : string(1 to 16) := "0123456789abcdef";
            variable s : string(1 to 8);
            variable n : integer;
        begin
            for k in 0 to 7 loop
                n := 0;
                for b in 3 downto 0 loop
                    if v(4*k+b) = '1' then n := n*2 + 1;
                    elsif v(4*k+b) = '0' then n := n*2;
                    else n := 16; exit; end if;
                end loop;
                if n > 15 then s(8-k) := 'x'; else s(8-k) := h(n+1); end if;
            end loop;
            return s;
        end function;
        variable last : std_logic_vector(31 downto 0) := (others => '0');
        variable prev : std_logic_vector(31 downto 0) := (others => '0');
    begin
        wait for 200 ns;
        if a0 = prev and a0 /= last then
            last := a0;
            report "A0 " & hx(a0) severity note;
            if a0 = x"600D0001" then
                wait for 100 us;
                report "FINAL a0 " & hx(a0) severity note;
                report "ERRATA RUN END" severity failure;
            end if;
        end if;
        prev := a0;
    end process;
'''
k = [m.start() for m in re.finditer(r'(?im)^end\b', t)][-1]
t = t[:k] + mon + t[k:]
open('riscv_tb.vhd', 'w', newline='').write(t)
PY
sed -e '/tb_defs.vhd/d' -e '/riscv_tb.vhd/d' "$T/xcelium/riscv_test/$KIND/cell_list_$KIND.txt" > cells.txt
# The behavioral ROM model opens the overwritten image by absolute path.
sed 's#"/home/mseminario2/chips/myshkin/ip/rom_hvt_pg/rom_hvt_pg_verilog.rcf"#"rom_hvt_pg_verilog.rcf"#' \
    "$HDL/MCU/sim/ARM_IP_ROM.vhd" > ARM_IP_ROM.vhd
sed -i 's#^.*sim/ARM_IP_ROM.vhd#ARM_IP_ROM.vhd#' cells.txt
SDF=""
[ "$KIND" = innovus ] && { cp "$T/xcelium/riscv_test/innovus/MCU.sdfcmd" .; SDF="-sdf_cmd_file MCU.sdfcmd"; }
echo 'run; exit' > go.tcl
xrun -q -top riscv_tb $SDF -v200x -work work -access +r -controlrelax nlstex -relax \
    -input ../../disable_x_warnings.tcl -input go.tcl $(cat cells.txt) tb_defs.vhd riscv_tb.vhd \
    -l run.log > /dev/null 2>&1
grep -E 'A0 |FINAL|ERRATA RUN END|TIMEOUT|FATAL|TEST PASSED|TEST FAILED|\*E,' run.log | sed 's/^.*: A0/A0/' | head -120
