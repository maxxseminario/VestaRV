-- Self-checking bench for the PMP match/priority/permission unit (pmp_unit.vhd).
-- The DUT is PURE COMBINATIONAL: the bench drives the flat cfg/addr bank exactly as csr_unit exports it, waits a delta-settling delay, and asserts the two grant outputs.
-- Three instances share one stimulus bank: dut16 (16 entries), dut8 (8 entries, upper half must be dead) and dutoff (ENABLE_PMP false, both grants stuck '1').
-- Run: xcelium/mp_test/run_pmp_unit.sh
-- Compile is -V200X: VHDL-93 only.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity pmp_unit_tb is
end entity;

architecture tb of pmp_unit_tb is

    -- The flat 16-entry cfg/addr bank, shared by all three DUT instances.
    signal cfg_flat  : std_logic_vector(127 downto 0) := (others => '0');
    signal addr_flat : std_logic_vector(479 downto 0) := (others => '0');

    -- Fetch and data access requests presented to every instance.
    signal f_addr    : std_logic_vector(31 downto 0) := (others => '0');
    signal f_priv_m  : std_logic := '1';
    signal d_addr    : std_logic_vector(31 downto 0) := (others => '0');
    signal d_priv_m  : std_logic := '1';
    signal d_read    : std_logic := '0';
    signal d_write   : std_logic := '0';

    -- Fetch/data grants, one pair per instance.
    signal f16, d16  : std_logic;
    signal f8,  d8   : std_logic;
    signal foff, doff: std_logic;

    -- Score, mirrored out of the stimulus process so it is visible in a waveform.
    signal errors    : integer := 0;
    signal checks    : integer := 0;

begin

    -- The product shape: 16 entries, PMP enabled.
    dut16 : entity work.pmp_unit
        generic map (ENABLE_PMP => true, PMP_ENTRIES => 16)
        port map (
            pmp_cfg_flat => cfg_flat, pmp_addr_flat => addr_flat,
            f_addr => f_addr, f_priv_m => f_priv_m, f_grant => f16,
            d_addr => d_addr, d_priv_m => d_priv_m,
            d_read => d_read, d_write => d_write, d_grant => d16);

    -- Half bank: entries 8 and above must be dead here.
    dut8 : entity work.pmp_unit
        generic map (ENABLE_PMP => true, PMP_ENTRIES => 8)
        port map (
            pmp_cfg_flat => cfg_flat, pmp_addr_flat => addr_flat,
            f_addr => f_addr, f_priv_m => f_priv_m, f_grant => f8,
            d_addr => d_addr, d_priv_m => d_priv_m,
            d_read => d_read, d_write => d_write, d_grant => d8);

    -- PMP folded away: both grants must be constant '1'.
    dutoff : entity work.pmp_unit
        generic map (ENABLE_PMP => false, PMP_ENTRIES => 16)
        port map (
            pmp_cfg_flat => cfg_flat, pmp_addr_flat => addr_flat,
            f_addr => f_addr, f_priv_m => f_priv_m, f_grant => foff,
            d_addr => d_addr, d_priv_m => d_priv_m,
            d_read => d_read, d_write => d_write, d_grant => doff);

    -- Single stimulus process: it walks the phases in order and tallies the checks.
    stim : process
        variable errs : integer := 0;
        variable nchk : integer := 0;

        -- Bank helpers: the bench writes the flat vectors DIRECTLY, bypassing csr_unit's WARL/lock filtering.
        -- That lets it plant a locked entry, or an R=0/W=1 combination, that the CSR write path would never let software create.
        procedure clear_bank is
        begin
            cfg_flat  <= (others => '0');
            addr_flat <= (others => '0');
        end procedure;

        procedure set_cfg(i : integer; v : std_logic_vector(7 downto 0)) is
        begin
            cfg_flat(8*i+7 downto 8*i) <= v;
        end procedure;

        procedure set_addr(i : integer; v : unsigned(29 downto 0)) is
        begin
            addr_flat(30*i+29 downto 30*i) <= std_logic_vector(v);
        end procedure;

        -- pmpaddr for a TOR/NA4 boundary: the WORD address of a byte address.
        -- The intermediate variable is deliberate: -V200X is VHDL-93/2002, and slicing a FUNCTION CALL directly is a VHDL-2008-only construct.
        function wa(byte_addr : integer) return unsigned is
            variable t : unsigned(31 downto 0);
        begin
            t := to_unsigned(byte_addr, 32);
            return t(31 downto 2);
        end function;

        -- pmpaddr for a NAPOT region of `size` bytes (size >= 8, power of two) based at `base`: base/4 + (size/8 - 1).
        function napot(base : integer; size : integer) return unsigned is
        begin
            return to_unsigned(base/4 + (size/8 - 1), 30);
        end function;

        -- The all-ones NAPOT encoding: a region covering the whole address space.
        constant NAPOT_ALL : unsigned(29 downto 0) := (others => '1');

        -- Stimulus and check helpers; every check carries a name so a failure is localisable straight out of the log.
        -- Let the combinational DUTs re-evaluate before any grant is sampled.
        procedure settle is
        begin
            wait for 1 ns;
        end procedure;

        -- Count one check and report the named mismatch if the grant is wrong.
        procedure expect(name : string; got : std_logic; exp : std_logic) is
        begin
            nchk := nchk + 1;
            if got /= exp then
                errs := errs + 1;
                report "CHECK FAILED: " & name &
                       "  got=" & std_logic'image(got) &
                       "  expected=" & std_logic'image(exp)
                    severity error;
            end if;
        end procedure;

        -- A DATA access: privilege, R/W request and address in, expected dut16 grant out.
        procedure dchk(name : string; priv : std_logic;
                       rd : std_logic; wr : std_logic;
                       byte_addr : integer; exp : std_logic) is
        begin
            d_priv_m <= priv;
            d_read   <= rd;
            d_write  <= wr;
            d_addr   <= std_logic_vector(to_unsigned(byte_addr, 32));
            settle;
            expect(name, d16, exp);
        end procedure;

        -- A FETCH access (X permission at priv).
        procedure fchk(name : string; priv : std_logic;
                       byte_addr : integer; exp : std_logic) is
        begin
            f_priv_m <= priv;
            f_addr   <= std_logic_vector(to_unsigned(byte_addr, 32));
            settle;
            expect(name, f16, exp);
        end procedure;

        -- Same DATA access, asserted on the PMP_ENTRIES=8 instance.
        procedure dchk8(name : string; priv : std_logic;
                        rd : std_logic; wr : std_logic;
                        byte_addr : integer; exp : std_logic) is
        begin
            d_priv_m <= priv;
            d_read   <= rd;
            d_write  <= wr;
            d_addr   <= std_logic_vector(to_unsigned(byte_addr, 32));
            settle;
            expect(name, d8, exp);
        end procedure;

        -- Same DATA/FETCH access, asserted on the ENABLE_PMP=false instance.
        procedure offchk(name : string; priv : std_logic;
                         rd : std_logic; wr : std_logic;
                         byte_addr : integer) is
        begin
            d_priv_m <= priv;
            f_priv_m <= priv;
            d_read   <= rd;
            d_write  <= wr;
            d_addr   <= std_logic_vector(to_unsigned(byte_addr, 32));
            f_addr   <= std_logic_vector(to_unsigned(byte_addr, 32));
            settle;
            expect(name & ".d", doff, '1');
            expect(name & ".f", foff, '1');
        end procedure;

    begin
        report "=== pmp_unit_tb start ===";

        -- P0: empty bank (the reset state), so no entry can match; M grants and U denies.
        clear_bank; settle;
        dchk("P0.M.read",   '1', '1', '0', 16#00008000#, '1');
        dchk("P0.M.write",  '1', '0', '1', 16#00008000#, '1');
        dchk("P0.U.read",   '0', '1', '0', 16#00008000#, '0');
        dchk("P0.U.write",  '0', '0', '1', 16#00008000#, '0');
        fchk("P0.M.fetch",  '1',           16#00008000#, '1');
        fchk("P0.U.fetch",  '0',           16#00008000#, '0');

        -- P1: TOR. e0 RWX covers [0x0000, 0x1000); e1 no-perms covers [0x1000, 0x2000); e2 is A=OFF and never matches, but its pmpaddr VALUE is e3's TOR base; e3 R|X covers [0x3000, 0x4000).
        clear_bank; settle;
        set_cfg(0, x"0F"); set_addr(0, wa(16#00001000#));   -- TOR, R|W|X
        set_cfg(1, x"08"); set_addr(1, wa(16#00002000#));   -- TOR, no perms
        set_cfg(2, x"00"); set_addr(2, wa(16#00003000#));   -- OFF (base only)
        set_cfg(3, x"0D"); set_addr(3, wa(16#00004000#));   -- TOR, R|X (no W)
        settle;

        -- Entry 0's lower bound really is 0.
        dchk("P1.tor0.base0",   '0', '1', '0', 16#00000000#, '1');
        dchk("P1.tor0.inside",  '0', '1', '0', 16#00000FFC#, '1');
        -- The boundary belongs to the NEXT region, not this one.
        dchk("P1.tor1.deny",    '0', '1', '0', 16#00001000#, '0');
        dchk("P1.tor1.deny.hi", '0', '1', '0', 16#00001FFC#, '0');
        -- A matched but UNLOCKED entry never constrains M.
        dchk("P1.tor1.M",       '1', '1', '0', 16#00001000#, '1');
        -- The hole between 0x2000 and 0x3000: no entry matches.
        dchk("P1.hole.U",       '0', '1', '0', 16#00002000#, '0');
        dchk("P1.hole.M",       '1', '1', '0', 16#00002000#, '1');
        -- OFF-PREDECESSOR TOR BASE: e3's region starts at e2's pmpaddr VALUE.
        dchk("P1.tor3.base",    '0', '1', '0', 16#00003000#, '1');
        dchk("P1.tor3.top",     '0', '1', '0', 16#00003FFC#, '1');
        dchk("P1.tor3.above",   '0', '1', '0', 16#00004000#, '0');
        dchk("P1.tor3.below",   '0', '1', '0', 16#00002FFC#, '0');
        -- e3 is R|X, not W.
        dchk("P1.tor3.write",   '0', '0', '1', 16#00003000#, '0');
        fchk("P1.tor3.fetch",   '0',           16#00003000#, '1');

        -- P2: NA4, exact word equality only; e0 is NA4 R|W at 0x8000.
        clear_bank; settle;
        set_cfg(0, x"13"); set_addr(0, wa(16#00008000#));   -- NA4, R|W (no X)
        settle;
        dchk("P2.na4.hit",      '0', '1', '0', 16#00008000#, '1');
        dchk("P2.na4.hit.wr",   '0', '0', '1', 16#00008000#, '1');
        dchk("P2.na4.next",     '0', '1', '0', 16#00008004#, '0');
        dchk("P2.na4.prev",     '0', '1', '0', 16#00007FFC#, '0');
        -- Word granularity: every byte of the word is the same word address.
        dchk("P2.na4.byte3",    '0', '1', '0', 16#00008003#, '1');
        -- X is clear, so a fetch of the very same word is denied.
        fchk("P2.na4.fetch",    '0',           16#00008000#, '0');

        -- P3: NAPOT size decode at 8 B, 16 B, 4 KB and the all-ones full span.
        clear_bank; settle;
        set_cfg(0, x"1F");                                  -- NAPOT, R|W|X
        set_addr(0, napot(16#00010000#, 8));                -- 8 bytes
        settle;
        dchk("P3.n8.lo",        '0', '1', '0', 16#00010000#, '1');
        dchk("P3.n8.hi",        '0', '1', '0', 16#00010004#, '1');
        dchk("P3.n8.over",      '0', '1', '0', 16#00010008#, '0');
        dchk("P3.n8.under",     '0', '1', '0', 16#0000FFFC#, '0');

        set_addr(0, napot(16#00010000#, 16));               -- 16 bytes
        settle;
        dchk("P3.n16.lo",       '0', '1', '0', 16#00010000#, '1');
        dchk("P3.n16.hi",       '0', '1', '0', 16#0001000C#, '1');
        dchk("P3.n16.over",     '0', '1', '0', 16#00010010#, '0');
        dchk("P3.n16.under",    '0', '1', '0', 16#0000FFFC#, '0');

        set_addr(0, napot(16#00020000#, 4096));             -- 4 KB
        settle;
        dchk("P3.n4k.lo",       '0', '1', '0', 16#00020000#, '1');
        dchk("P3.n4k.mid",      '0', '1', '0', 16#00020800#, '1');
        dchk("P3.n4k.hi",       '0', '1', '0', 16#00020FFC#, '1');
        dchk("P3.n4k.over",     '0', '1', '0', 16#00021000#, '0');
        dchk("P3.n4k.under",    '0', '1', '0', 16#0001FFFC#, '0');

        set_addr(0, NAPOT_ALL);                             -- full span
        settle;
        dchk("P3.nall.zero",    '0', '1', '0', 16#00000000#, '1');
        dchk("P3.nall.mid",     '0', '1', '0', 16#40000000#, '1');
        fchk("P3.nall.fetch",   '0',           16#00008000#, '1');

        report "=== pmp_unit_tb: phases P0-P3 done ===";

        -- P4a: the LOWEST-numbered match decides ALONE, so e1 (full-span RWX) must not rescue e0's deny over 4 KB at 0x30000.
        clear_bank; settle;
        set_cfg(0, x"18"); set_addr(0, napot(16#00030000#, 4096));  -- NAPOT, ---
        set_cfg(1, x"1F"); set_addr(1, NAPOT_ALL);                  -- NAPOT, RWX
        settle;
        dchk("P4a.inside.deny", '0', '1', '0', 16#00030000#, '0');
        dchk("P4a.inside.top",  '0', '1', '0', 16#00030FFC#, '0');
        fchk("P4a.inside.fetch",'0',           16#00030000#, '0');
        -- Outside e0, e1 is the lowest match and grants.
        dchk("P4a.outside",     '0', '1', '0', 16#00040000#, '1');

        -- P4b: the mirror case, so e1 (full-span deny-all) must not revoke e0's NA4 R|W grant at 0x50000.
        clear_bank; settle;
        set_cfg(0, x"13"); set_addr(0, wa(16#00050000#));           -- NA4, R|W
        set_cfg(1, x"18"); set_addr(1, NAPOT_ALL);                  -- NAPOT, ---
        settle;
        dchk("P4b.hit.grant",   '0', '1', '0', 16#00050000#, '1');
        dchk("P4b.hit.write",   '0', '0', '1', 16#00050000#, '1');
        -- One word away e0 no longer matches, so the deny-all entry rules.
        dchk("P4b.next.deny",   '0', '1', '0', 16#00050004#, '0');

        -- P5: M-mode and the LOCK bit, on the SAME region unlocked then locked.
        -- Unlocked, M is not constrained at all; locked, the entry enforces on M exactly as on U.
        clear_bank; settle;
        set_cfg(0, x"18"); set_addr(0, napot(16#00060000#, 4096));  -- NAPOT, --- , L=0
        settle;
        dchk("P5.unlocked.M",   '1', '1', '0', 16#00060000#, '1');
        dchk("P5.unlocked.U",   '0', '1', '0', 16#00060000#, '0');
        fchk("P5.unlocked.Mf",  '1',           16#00060000#, '1');

        set_cfg(0, x"98");                                          -- L=1, NAPOT, ---
        settle;
        dchk("P5.locked.M",     '1', '1', '0', 16#00060000#, '0');
        dchk("P5.locked.Mw",    '1', '0', '1', 16#00060000#, '0');
        fchk("P5.locked.Mf",    '1',           16#00060000#, '0');
        dchk("P5.locked.U",     '0', '1', '0', 16#00060000#, '0');
        -- A LOCKED entry constrains only its OWN region; no match still grants M.
        dchk("P5.locked.Mout",  '1', '1', '0', 16#00070000#, '1');

        -- A LOCKED entry WITH permissions grants M through the permission path.
        set_cfg(0, x"99");                                          -- L=1, NAPOT, R
        settle;
        dchk("P5.lockedR.Mr",   '1', '1', '0', 16#00060000#, '1');
        dchk("P5.lockedR.Mw",   '1', '0', '1', 16#00060000#, '0');

        -- P6: R / W / X selectivity, on a locked full-span entry so BOTH privileges take the permission path.
        -- d_read = d_write = '1' is the LR/SC/AMO shape, which needs R AND W.
        clear_bank; settle;
        set_addr(0, NAPOT_ALL);
        set_cfg(0, x"99");                                          -- L=1, NAPOT, R only
        settle;
        dchk("P6.R.read",       '0', '1', '0', 16#00008000#, '1');
        dchk("P6.R.write",      '0', '0', '1', 16#00008000#, '0');
        dchk("P6.R.amo",        '0', '1', '1', 16#00008000#, '0');
        fchk("P6.R.fetch",      '0',           16#00008000#, '0');

        set_cfg(0, x"9B");                                          -- L=1, NAPOT, R|W
        settle;
        dchk("P6.RW.read",      '0', '1', '0', 16#00008000#, '1');
        dchk("P6.RW.write",     '0', '0', '1', 16#00008000#, '1');
        dchk("P6.RW.amo",       '0', '1', '1', 16#00008000#, '1');
        fchk("P6.RW.fetch",     '0',           16#00008000#, '0');

        set_cfg(0, x"9C");                                          -- L=1, NAPOT, X only
        settle;
        dchk("P6.X.read",       '0', '1', '0', 16#00008000#, '0');
        dchk("P6.X.write",      '0', '0', '1', 16#00008000#, '0');
        fchk("P6.X.fetch",      '0',           16#00008000#, '1');
        fchk("P6.X.fetchM",     '1',           16#00008000#, '1');

        set_cfg(0, x"9F");                                          -- L=1, NAPOT, R|W|X
        settle;
        dchk("P6.RWX.amo",      '0', '1', '1', 16#00008000#, '1');
        fchk("P6.RWX.fetch",    '0',           16#00008000#, '1');

        report "=== pmp_unit_tb: phases P4-P6 done ===";

        -- P7: entries 8 and 12 are LIVE on dut16 and DEAD on dut8 (its check loop never reaches them), so the identical bank grants U on dut16 and denies U on dut8.
        clear_bank; settle;
        set_cfg(8, x"1F"); set_addr(8, NAPOT_ALL);                  -- NAPOT full span, RWX
        settle;
        dchk ("P7.e8.dut16.U",  '0', '1', '0', 16#00008000#, '1');
        dchk8("P7.e8.dut8.U",   '0', '1', '0', 16#00008000#, '0');
        dchk8("P7.e8.dut8.M",   '1', '1', '0', 16#00008000#, '1');

        clear_bank; settle;
        set_cfg(12, x"1F"); set_addr(12, NAPOT_ALL);
        settle;
        dchk ("P7.e12.dut16.U", '0', '1', '0', 16#00008000#, '1');
        dchk8("P7.e12.dut8.U",  '0', '1', '0', 16#00008000#, '0');

        -- A LOW entry is live on both shapes, which proves dut8 is not simply dead.
        clear_bank; settle;
        set_cfg(0, x"1F"); set_addr(0, NAPOT_ALL);
        settle;
        dchk ("P7.e0.dut16.U",  '0', '1', '0', 16#00008000#, '1');
        dchk8("P7.e0.dut8.U",   '0', '1', '0', 16#00008000#, '1');

        -- P8: with ENABLE_PMP = false BOTH grants are constant '1', even against a bank that denies U everything.
        -- Also in U-mode with an empty bank: the no-match-U-denies rule must not exist there either.
        clear_bank; settle;
        set_cfg(0, x"98"); set_addr(0, NAPOT_ALL);                  -- L=1, NAPOT, ---
        settle;
        offchk("P8.denyall.U", '0', '1', '1', 16#00008000#);
        offchk("P8.denyall.M", '1', '1', '1', 16#00008000#);

        clear_bank; settle;
        offchk("P8.empty.U",   '0', '1', '0', 16#00008000#);
        offchk("P8.empty.M",   '1', '0', '1', 16#00008000#);

        -- Publish the tallies and report the verdict.
        errors <= errs;
        checks <= nchk;
        settle;

        report "=== pmp_unit_tb summary: " & integer'image(nchk) &
               " checks, " & integer'image(errs) & " failures ===";
        if errs = 0 then
            report "ALL CHECKS PASSED";
        else
            report "PMP UNIT PROOF FAILED" severity error;
        end if;

        wait;
    end process;

end tb;
