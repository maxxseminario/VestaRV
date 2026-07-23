library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- TrngRoEnsemble_sim.vhd -- BEHAVIORAL FLOWS ONLY. NEVER co-list this file
-- with TrngRoEnsemble.vhd in the same cell list (D6/A5): TrngRoEnsemble.vhd
-- carries the REAL `rtl` architecture (deliberate combinational ring-
-- oscillator loops) which DELTA-LOOPS a behavioral simulator (zero-time
-- oscillation -> the 1-MINUTE RULE fires the hard way). This file supplies a
-- second, independent architecture of the SAME entity -- a deterministic
-- 32-bit Galois LFSR that advances on rising `sclk` -- for use ONLY in
-- xcelium/periph_test/behavioral (and the standalone dev scratch sim in this
-- session). Genus/gate cell lists must compile TrngRoEnsemble.vhd instead and
-- must NEVER see this file.
--
-- FROZEN design: ~/vesta_docs/digperiphs/trng_design.md, D3/D6/D7 + the
-- ADJUDICATION RULINGS (5: explicit binding in the TB) -- BINDING. Peripheral
-- of the digital-peripherals program (TRNG0, base 0x6900, vector 121).
--
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary
-- reduce). Every process infers exactly ONE edge of ONE clock (Genus
-- VHDL-601 discipline) -- this file's process is level-gated by `enable`
-- (a deliberate async-reset-like level, matching "enable=0 parks the ring at
-- a known level" for the real rtl arch) plus rising `sclk`.
--
-- Determinism contract (checker independence, D6 bench plan): the SAME
-- seed/tap/perturbation function is reproduced, TB-owned, in
-- tb/trng_bfm_pkg.vhd's independent reference replay -- that package NEVER
-- reads this file, and this file is NEVER read back by the bench beyond the
-- documented hierarchical `force dut.u_ro.ro_raw` override used for G5 (health
-- alarm / stuck-run testing).
--
-- Entity (D3, FROZEN -- identical to the entity in TrngRoEnsemble.vhd):
--   enable : gates the model. While '0', the LFSR is HELD at a sel-perturbed
--            constant seed (deterministic restart point -- every EN-rising
--            transition begins the SAME sequence for a given `sel`, so the
--            bench's independent replay only needs to know the seed function
--            and the sel value at the moment EN rose).
--   sel    : perturbs the seed (XORed into the low nibble) at the moment the
--            model is held/reset by enable='0'; held constant thereafter for
--            that run (matches the design doc's "sel-perturbed" framing and
--            gives G4 a clean wiring/forwarding check: a NEW sel only takes
--            effect the next time enable drops then rises again).
--   sclk   : the TRNG's own `clk`, routed through `ro_sclk` at integration
--            (D3) -- the model advances the LFSR one step per rising sclk
--            edge while enable='1'.
--   ro_raw : LFSR bit 0 of the CURRENT state (combinational tap, not the
--            next-state value) -- 2-FF synchronized by TRNG.vhd (D7) before
--            any use, exactly like the real rtl arch's XOR-ensembled bit.
-- ===========================================================================

entity TrngRoEnsemble is
    generic ( NRO : natural := 8 );   -- ring-oscillator count (D6). {4,8} proven (D15).
    port (
        enable : in  std_logic;                     -- gate the model (sim) / gate the rings (real)
        sel    : in  std_logic_vector(3 downto 0);   -- perturbs the LFSR seed (sim); ring
                                                     --   contribution mask (real, D6 ruling 4)
        sclk   : in  std_logic;                     -- advances the LFSR on rising sclk (sim);
                                                     --   IGNORED by the real rtl arch (async rings)
        ro_raw : out std_logic                      -- LFSR tap (sim) / XOR-ensembled ring bit (real)
    );
end entity TrngRoEnsemble;

architecture sim of TrngRoEnsemble is

    -- Deterministic maximal-length-class 32-bit Galois LFSR. TAPS/SEED are
    -- arbitrary but FIXED (never derived from any TRNG.vhd/generator state);
    -- the exact same constants are reproduced in trng_bfm_pkg.vhd's reference
    -- replay -- change BOTH together or the checker-independence contract breaks.
    constant SEED : std_logic_vector(31 downto 0) := x"ACE1ACE1";
    constant TAPS : std_logic_vector(31 downto 0) := x"A3000000";

    signal lfsr : std_logic_vector(31 downto 0) := SEED;

begin

    -- NO combinational loop: this is a plain Galois LFSR, register-only state.
    -- Level-gated by `enable` (deliberately async-reset-like, mirroring the
    -- real ring's "enable=0 parks at a known level"), advanced on rising
    -- sclk only while enable='1'. Single edge (rising sclk) discipline is
    -- preserved -- the enable branch never itself contains a clock edge.
    lfsr_proc: process(enable, sclk)
    begin
        if enable = '0' then
            lfsr <= SEED xor (x"0000000" & sel);   -- sel perturbs the low nibble (D6)
        elsif rising_edge(sclk) then
            if lfsr(0) = '1' then
                lfsr <= ('0' & lfsr(31 downto 1)) xor TAPS;
            else
                lfsr <= '0' & lfsr(31 downto 1);
            end if;
        end if;
    end process lfsr_proc;

    ro_raw <= lfsr(0);

end architecture sim;
