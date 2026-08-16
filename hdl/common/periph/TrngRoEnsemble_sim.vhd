library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- TrngRoEnsemble_sim.vhd: behavioral flows only, and NEVER co-listed with TrngRoEnsemble.vhd, which carries the real `rtl` architecture of the same entity.
-- That architecture's combinational ring-oscillator loops delta-loop a behavioral simulator into zero-time oscillation, so behavioral runs bind this deterministic 32-bit Galois LFSR model instead.
-- Genus and gate cell lists must compile TrngRoEnsemble.vhd and must never see this file.
-- The entity is identical to TrngRoEnsemble.vhd's; the peripheral is TRNG0, base 0x6900, vector 121.
-- Compile is -V200X, no VHDL-2008, and the one process infers exactly one edge of one clock.
-- ===========================================================================

entity TrngRoEnsemble is
    generic ( NRO : natural := 8 );   -- ring-oscillator count; 4 and 8 are the proven values
    port (
        enable : in  std_logic;                     -- while '0' the LFSR holds the sel-perturbed seed, so every rise restarts the same sequence; gates the rings in the real arch
        sel    : in  std_logic_vector(3 downto 0);   -- perturbs the LFSR seed here, and a new value takes effect only after enable drops and rises again; ring
                                                     --   contribution mask in the real arch
        sclk   : in  std_logic;                     -- advances the LFSR one step per rising edge while enable is '1';
                                                     --   IGNORED by the real rtl arch, whose rings are async
        ro_raw : out std_logic                      -- bit 0 of the CURRENT LFSR state, 2-FF synchronized in TRNG.vhd; XOR-ensembled ring bit in the real arch
    );
end entity TrngRoEnsemble;

architecture sim of TrngRoEnsemble is

    -- TAPS and SEED are arbitrary but fixed, never derived from any TRNG.vhd or generator state.
    -- tb/trng_bfm_pkg.vhd reproduces the same seed, taps and perturbation in its independent replay: change both together or the bench stops being an independent checker.
    constant SEED : std_logic_vector(31 downto 0) := x"ACE1ACE1";
    constant TAPS : std_logic_vector(31 downto 0) := x"A3000000";

    signal lfsr : std_logic_vector(31 downto 0) := SEED;

begin

    -- No combinational loop: a plain Galois LFSR with register-only state, advancing on rising sclk only while enable is '1'.
    -- The enable level acts as an async reset, mirroring the real ring parking at a known level, and never contains a clock edge of its own.
    lfsr_proc: process(enable, sclk)
    begin
        if enable = '0' then
            lfsr <= SEED xor (x"0000000" & sel);   -- sel perturbs the low nibble
        elsif rising_edge(sclk) then
            -- Galois step: shift right, and fold in the taps when the bit shifted out is set.
            if lfsr(0) = '1' then
                lfsr <= ('0' & lfsr(31 downto 1)) xor TAPS;
            else
                lfsr <= '0' & lfsr(31 downto 1);
            end if;
        end if;
    end process lfsr_proc;

    -- Current-state tap, synchronized downstream in TRNG.vhd.
    ro_raw <= lfsr(0);

end architecture sim;
