#!/usr/bin/python3.6
"""Derive the RISCOF bench from the generated riscv_tb.vhd.

The chip's bench stays the source of truth for the DUT hookup. Only these change,
each by an exact-match replacement that aborts if the source moved:
  * fixed image name, so one snapshot serves every test from its own directory,
  * flash model sized for the largest image,
  * longer simulation timeout,
  * the a0 monitors are replaced. a0 holds test data while a test runs on hart 0
    (and a0_1..4 on a tile), so a bare 0xCAFEBABE or 0xDEADBEEF means nothing.
    Pass requires the whole tagged stream of vesta_stub.S, in order.
Usage: gen_tb.py <riscv_tb.vhd> <out.vhd>
"""
import re
import sys

MONITOR = r'''
    -- RISCOF signature receiver. See verification/riscof/vesta/env/vesta_stub.S.
    sig_rx: process(a0)
        file sig_f : text;
        variable l : line;
        variable st : natural := 0;
        variable total : natural := 0;
        variable idx : natural := 0;
        variable lo : std_logic_vector(15 downto 0);
        constant HEX : string(1 to 16) := "0123456789abcdef";
        function tag_idx(v : std_logic_vector(31 downto 0)) return natural is
        begin
            return conv_integer(v(27 downto 16));
        end function;
    begin
        if not is_x(a0) and not a0_reached_pass and not a0_reached_fail then
            case st is
                when 0 => if a0 = x"51C0DE00" then st := 1; end if;
                when 1 => if a0 = x"51C0DE01" then st := 2; else st := 0; end if;
                when 2 => if a0 = x"51C0DE02" then st := 3; else st := 0; end if;
                when 3 =>
                    total := conv_integer(a0);
                    idx := 0;
                    file_open(sig_f, "signature.out", WRITE_MODE);
                    report "RISCOF: signature begin, words=" & integer'image(total) severity note;
                    st := 4;
                when 4 =>
                    if a0 = PASS_LABEL and idx = total then
                        file_close(sig_f);
                        report "RISCOF: signature complete, words=" & integer'image(idx) severity note;
                        a0_reached_pass <= true;
                    elsif a0(31 downto 28) = x"A" and tag_idx(a0) = idx mod 4096 then
                        lo := a0(15 downto 0);
                        st := 5;
                    else
                        report "RISCOF: stream error at word " & integer'image(idx) severity note;
                        a0_reached_fail <= true;
                    end if;
                when others =>
                    if a0(31 downto 28) = x"B" and tag_idx(a0) = idx mod 4096 then
                        for n in 3 downto 0 loop
                            write(l, HEX(1 + conv_integer(a0(4*n+3 downto 4*n))));
                        end loop;
                        for n in 3 downto 0 loop
                            write(l, HEX(1 + conv_integer(lo(4*n+3 downto 4*n))));
                        end loop;
                        writeline(sig_f, l);
                        idx := idx + 1;
                        st := 4;
                    else
                        report "RISCOF: stream error at word " & integer'image(idx) severity note;
                        a0_reached_fail <= true;
                    end if;
            end case;
        end if;
    end process;

'''


def sub1(text, old, new, what):
    n = text.count(old)
    if n != 1:
        sys.exit('gen_tb: %s: expected 1 match, found %d' % (what, n))
    return text.replace(old, new)


def main():
    src, out = sys.argv[1:3]
    t = open(src).read()
    t = sub1(t, 'use ieee.numeric_std.all;\n',
             'use ieee.numeric_std.all;\nuse std.textio.all;\n', 'textio')
    t = sub1(t, ':= "../rcf/xxxrv32ui-p-simple.rcf"',
             ':= "xxxxxxxxxxxxxxxxxxxximage.rcf"', 'image name')
    t = sub1(t, 'RamSizeBytes => 16#8100#,', 'RamSizeBytes => 16#120000#,', 'flash size')
    t = sub1(t, 'constant SIMULATION_TIMEOUT : time := 100000 us;',
             'constant SIMULATION_TIMEOUT : time := 2000000 us;', 'timeout')
    m = re.search(r'    -- Monitoring for pass/fail detection\n.*(?=^end )', t, re.S | re.M)
    if not m:
        sys.exit('gen_tb: monitor block not found')
    t = t[:m.start()] + MONITOR + t[m.end():]
    open(out, 'w').write(t)


if __name__ == '__main__':
    main()
