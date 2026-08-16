/* -----------------------------------------------------------------------------
   trng_bfm_pkg.vhd: bench-support helpers for the TRNG peripheral testbench: register-map constants, bus plumbing, bounded SR polls, the reference SEED and TAPS, and a pure single-step Galois LFSR function.
   Checker independence: TRNG_REF_SEED, TRNG_REF_TAPS and the sel-perturbation formula reproduce TrngRoEnsemble_sim.vhd's deterministic model exactly but are TB-owned copies, never read from the DUT, so any change to that stub must be mirrored here or the contract silently breaks.
   The cycle-accurate reference replay (2-FF sync, decimator, 32-bit assembler, consume-and-pending mirror) needs live signals, so it lives as a process in TRNG_tb.vhd that reads only the bench's own shadow copies of EN, ROSEL and DECIM, clk, resetn and its record of qualifying TRNG0DR reads, never a DUT internal such as dr_word, word_valid or asm_reg.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package trng_bfm_pkg is

    -- ---- Register word-slot map, LOCAL to this bench: TRNG0 lives at 0x6900 and MemoryMap.vhd carries no slot constants for it. ----
    constant TRNG_SLOT_CR : natural := 0;   -- rw: EN, DRDYIE, ALMIE, ROSEL, DECIM.
    constant TRNG_SLOT_SR : natural := 1;   -- Mixed: DRDY and RUN are ro, ALMF is write-1-to-clear.
    constant TRNG_SLOT_DR : natural := 2;   -- ro: the entropy word, and READING IT CONSUMES it.
    constant TRNG_SLOT_HT : natural := 3;   -- Mixed: RCTC is rw, RUNLEN is an ro diagnostic.

    -- ---- TRNG0CR bit positions, slot 0. ----------------------------------
    constant TRNG_CR_EN        : natural := 0;
    constant TRNG_CR_DRDYIE    : natural := 1;
    constant TRNG_CR_ALMIE     : natural := 2;
    constant TRNG_CR_ROSEL_LO  : natural := 4;   -- Field [7:4].
    constant TRNG_CR_DECIM_LO  : natural := 8;   -- Field [11:8].

    -- ---- TRNG0SR bit positions, slot 1. ----------------------------------
    constant TRNG_SR_DRDY : natural := 0;   -- Read-only, corrected for the consume blind window.
    constant TRNG_SR_ALMF : natural := 1;   -- Write-1-to-clear.
    constant TRNG_SR_RUN  : natural := 2;   -- Read-only.

    -- ---- TRNG0HT field positions, slot 3. --------------------------------
    constant TRNG_HT_RCTC_LO   : natural := 0;    -- Field [7:0], rw.
    constant TRNG_HT_RUNLEN_LO : natural := 16;   -- Field [21:16], ro diagnostic.

    -- Guard bound for the SR and DRDY polls: one bus_read per iteration, about one clk, so the bound trips well inside the tb watchdog.
    constant TRNG_POLL_GUARD : natural := 20000;

    -- ---- Sim-RO reference constants, which MUST match TrngRoEnsemble_sim.vhd. ---
    -- Independent copies, never read from the DUT or from the sim stub itself.
    constant TRNG_REF_SEED : std_logic_vector(31 downto 0) := x"ACE1ACE1";
    constant TRNG_REF_TAPS : std_logic_vector(31 downto 0) := x"A3000000";

    -- Build a TRNG0CR word in the field layout above, where bits 31:12 are reserved and left 0.
    function trng_mk_cr(en, drdyie, almie : std_logic;
                        rosel : std_logic_vector(3 downto 0);
                        decim : std_logic_vector(3 downto 0))
        return std_logic_vector;

    -- One Galois LFSR step, reproducing TrngRoEnsemble_sim's recurrence exactly.
    -- Pure: the reference-replay process seeds itself with it and then advances the SAME way once per clk edge.
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

    -- Place each control field at its bit position, leaving the reserved bits at 0.
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

    -- Shift right by one, and fold in the taps whenever the bit shifted out was set.
    function trng_ref_lfsr_step(state : std_logic_vector(31 downto 0))
        return std_logic_vector is
    begin
        if state(0) = '1' then
            return ('0' & state(31 downto 1)) xor TRNG_REF_TAPS;
        else
            return '0' & state(31 downto 1);
        end if;
    end function;

    -- The sel nibble is XORed into the low bits of the seed, matching the sim arch exactly.
    function trng_seed_perturbed(sel : std_logic_vector(3 downto 0))
        return std_logic_vector is
    begin
        return TRNG_REF_SEED xor (x"0000000" & sel);
    end function;

    -- Re-read TRNG0SR until the named bit matches, or until the guard bound expires.
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
            exit when guard > TRNG_POLL_GUARD;   -- Bounded, so the poll can never hang; done_ok stays false on timeout.
        end loop;
    end procedure;

    -- Convenience wrapper: the DRDY case of trng_wait_flag.
    procedure trng_wait_drdy(signal clk       : in    std_logic;
                             signal b         : inout periph_bus_t;
                             signal read_data : in    std_logic_vector(31 downto 0);
                             done_ok          : out   boolean) is
    begin
        trng_wait_flag(clk, b, read_data, TRNG_SR_DRDY, '1', done_ok);
    end procedure;

end package body trng_bfm_pkg;
