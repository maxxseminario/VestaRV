-------------------------------------------------------------------------------
-- trng_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the TRNG peripheral testbench (tb/TRNG_tb.vhd).
-- TRNG.vhd is written against the FROZEN design
-- (~/vesta_docs/digperiphs/trng_design.md, D1-D16 + the ADJUDICATION RULINGS)
-- this bench targets; the slot/CR/SR/HT field positions below are LOCAL to
-- this bench (mirrors onewire_bfm_pkg.vhd / rtc_bfm_pkg.vhd / i2ct_bfm_pkg.vhd),
-- NOT shared MemoryMap.vhd constants (TRNG0 lives at 0x6900; MemoryMap.vhd has
-- no TRNG0 slot constants until the generator knob peripherals.trng is on --
-- the chipgen integration hasn't landed yet, per the task scope note).
--
-- CHECKER INDEPENDENCE (the task's binding instruction, and the OneWire/I2CT
-- lesson): this package provides ONLY bus-level register plumbing, register-
-- map constants, bounded SR polls, and the SEED/TAPS constants + a pure
-- single-step Galois LFSR function that reproduce
-- hdl/common/periph/TrngRoEnsemble_sim.vhd's deterministic model EXACTLY --
-- SAME seed, SAME taps, SAME sel-perturbation formula -- kept as TB-owned
-- constants, NEVER read from the DUT or from TrngRoEnsemble_sim.vhd itself.
-- If either the sim arch's SEED/TAPS or the sel-perturbation formula ever
-- changes, this package's copies must change WITH it (a single named place --
-- see TRNG_CONST_SEED/TRNG_CONST_TAPS below) or the checker-independence
-- contract silently breaks (a stale reference model that no longer matches
-- would still "work" by accident only if nobody changed the stub -- flagged
-- here so a future stub change is never silently forgotten).
--
-- The actual cycle-accurate reference REPLAY (the 2-FF sync + decimator +
-- 32-bit assembler + D9 consume/pending mirror) is NOT a pure function here
-- -- it needs live signals ticking on the bench's own `clk`, so it lives as a
-- background process directly in TRNG_tb.vhd (declared alongside the DUT),
-- built from the constants/functions in this package. That process NEVER
-- reads any DUT-internal signal (dr_word, word_valid, asm_reg, ...) -- only
-- the bench's OWN shadow copies of what it commanded (EN/ROSEL/DECIM) plus
-- the shared `clk`/`resetn`, and its own record of when it issued a
-- qualifying TRNG0DR read.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package trng_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc D5) -------------------
    constant TRNG_SLOT_CR : natural := 0;   -- rw: EN/DRDYIE/ALMIE/ROSEL/DECIM
    constant TRNG_SLOT_SR : natural := 1;   -- mixed: DRDY/RUN ro + ALMF W1C
    constant TRNG_SLOT_DR : natural := 2;   -- ro: entropy word, READ-CONSUMES (D9)
    constant TRNG_SLOT_HT : natural := 3;   -- rw/ro: RCTC (rw) + RUNLEN (ro diagnostic)

    -- ---- TRNG0CR bit positions (design doc D5, slot 0) ---------------------
    constant TRNG_CR_EN        : natural := 0;
    constant TRNG_CR_DRDYIE    : natural := 1;
    constant TRNG_CR_ALMIE     : natural := 2;
    constant TRNG_CR_ROSEL_LO  : natural := 4;   -- [7:4]
    constant TRNG_CR_DECIM_LO  : natural := 8;   -- [11:8]

    -- ---- TRNG0SR bit positions (design doc D5, slot 1) ---------------------
    constant TRNG_SR_DRDY : natural := 0;   -- r  (D9 blind-window-corrected)
    constant TRNG_SR_ALMF : natural := 1;   -- w1c
    constant TRNG_SR_RUN  : natural := 2;   -- r

    -- ---- TRNG0HT field positions (design doc D5, slot 3) -------------------
    constant TRNG_HT_RCTC_LO   : natural := 0;    -- [7:0] rw
    constant TRNG_HT_RUNLEN_LO : natural := 16;   -- [21:16] ro diagnostic

    -- guard bound for the SR/DRDY polls (shirq ~20000-iteration precedent);
    -- each poll iteration is one bus_read (~1 clk), trips well inside the
    -- 100 ms-class tb watchdog.
    constant TRNG_POLL_GUARD : natural := 20000;

    -- ---- sim-RO reference constants (MUST match TrngRoEnsemble_sim.vhd) ---
    -- Independent copies, per the checker-independence header note above --
    -- NEVER read from the DUT/sim-stub file itself.
    constant TRNG_REF_SEED : std_logic_vector(31 downto 0) := x"ACE1ACE1";
    constant TRNG_REF_TAPS : std_logic_vector(31 downto 0) := x"A3000000";

    -- Build a full 12-bit-relevant TRNG0CR word (D5 field layout; bits 31:12
    -- reserved, left 0).
    function trng_mk_cr(en, drdyie, almie : std_logic;
                        rosel : std_logic_vector(3 downto 0);
                        decim : std_logic_vector(3 downto 0))
        return std_logic_vector;

    -- One Galois LFSR step, reproducing TrngRoEnsemble_sim's recurrence
    -- exactly (pure function -- used by the TB's reference-replay process to
    -- seed itself; the process advances the SAME way once per clk edge).
    function trng_ref_lfsr_step(state : std_logic_vector(31 downto 0))
        return std_logic_vector;

    -- The sel-perturbed seed the sim arch holds at while enable='0'.
    function trng_seed_perturbed(sel : std_logic_vector(3 downto 0))
        return std_logic_vector;

    -- Bounded poll of a single TRNG0SR flag bit until it reads exp_val.
    procedure trng_wait_flag(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             bit_idx          : in    natural;
                             exp_val          : in    std_logic;
                             done_ok          : out   boolean);

    -- Bounded poll of TRNG0SR.DRDY (bit 0) until it reads '1'.
    procedure trng_wait_drdy(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             done_ok          : out   boolean);

end package trng_bfm_pkg;


package body trng_bfm_pkg is

    function trng_mk_cr(en, drdyie, almie : std_logic;
                        rosel : std_logic_vector(3 downto 0);
                        decim : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(TRNG_CR_EN)     := en;
        v(TRNG_CR_DRDYIE) := drdyie;
        v(TRNG_CR_ALMIE)  := almie;
        v(TRNG_CR_ROSEL_LO + 3 downto TRNG_CR_ROSEL_LO) := rosel;
        v(TRNG_CR_DECIM_LO + 3 downto TRNG_CR_DECIM_LO) := decim;
        return v;
    end function;

    function trng_ref_lfsr_step(state : std_logic_vector(31 downto 0))
        return std_logic_vector is
    begin
        if state(0) = '1' then
            return ('0' & state(31 downto 1)) xor TRNG_REF_TAPS;
        else
            return '0' & state(31 downto 1);
        end if;
    end function;

    function trng_seed_perturbed(sel : std_logic_vector(3 downto 0))
        return std_logic_vector is
    begin
        return TRNG_REF_SEED xor (x"0000000" & sel);
    end function;

    procedure trng_wait_flag(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             bit_idx          : in    natural;
                             exp_val          : in    std_logic;
                             done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, TRNG_SLOT_SR, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > TRNG_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

    procedure trng_wait_drdy(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             done_ok          : out   boolean) is
    begin
        trng_wait_flag(clk, b, read_data, TRNG_SR_DRDY, '1', done_ok);
    end procedure;

end package body trng_bfm_pkg;
