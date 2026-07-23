library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- TrngRoEnsemble.vhd -- GENUS/GATE FLOWS ONLY. This file carries DELIBERATE
-- combinational ring-oscillator feedback loops (D6) -- it DELTA-LOOPS a
-- behavioral simulator (zero-time oscillation -> the 1-MINUTE RULE fires the
-- hard way). NEVER put this file in a behavioral cell list; NEVER co-list it
-- with TrngRoEnsemble_sim.vhd (which carries the OTHER architecture of this
-- same entity) in the same list -- see the warning comment at both cell-list
-- entries (A5). The behavioral flow compiles TrngRoEnsemble_sim.vhd instead.
--
-- FROZEN design: ~/vesta_docs/digperiphs/trng_design.md, D3/D6 + the
-- ADJUDICATION RULINGS (2: trng_inv/trng_nand wrapper realization; 4: NRO
-- knob + ROSEL semantics) -- BINDING. Peripheral of the digital-peripherals
-- program (TRNG0, base 0x6900, vector 121).
--
-- -V200X only: NO VHDL-2008. This file is never elaborated/simulated in the
-- behavioral flow -- ONLY analyzed (xmvhdl, no elaborate/run) as a syntax/
-- semantic smoke, and otherwise reserved for the future Genus synthesis
-- stage (own genus/tcl/TRNG.genus.tcl, out of scope this session). If this
-- file is EVER accidentally elaborated+run and the sim spins (100% xmsim CPU,
-- frozen sim time), `pkill -9 xmsim` immediately -- this is expected, not a
-- bug, and is exactly the failure mode D6 exists to keep out of the
-- behavioral suite.
--
-- Ruling 2 (RO cell realization): two tiny wrapper entities, `trng_inv` (one
-- inverter) and `trng_nand` (one 2-input NAND), instantiated structurally to
-- build each ring. The wrapper form keeps foundry std-cell names OUT of this
-- PUBLIC repo (the PDK-artifact rule) -- Genus dont_touch/preserve attributes
-- attach at the wrapper-INSTANCE level (+ hierarchy preserve on u_ro) in the
-- genus tcl, not in this file. GATE BAR (ruling 2): a post-synthesis netlist
-- census must count exactly sum_i(RING_STAGES(i)-1) preserved trng_inv
-- instances (the inverters) PLUS NRO preserved trng_nand instances (one
-- enable-NAND per ring) -- silent ring collapse is the failure this bar
-- exists to catch.
--
-- Ring topology (D6): each ring i is an ODD-length loop of RING_STAGES(i)
-- total inverting stages -- ONE of which is the enable NAND (parking the
-- ring at a known level when `enable`='0', the clean-reset / power lever),
-- the remaining RING_STAGES(i)-1 are plain inverters. Odd total inversions
-- is what makes the loop oscillate (an even count would settle into a
-- bistable ring latch instead) -- this is why the stage counts below are all
-- odd (pairwise-coprime primes, so the NRO rings beat at independent, non-
-- commensurate frequencies): {13,17,19,23,29,31,37,41} (ruling 4 CONFIRMED;
-- NRO=4 uses the first four). Loop wiring per ring: NAND(enable, net(S-1))
-- -> net(0) -> inv -> net(1) -> inv -> ... -> net(S-1) (feeds back into the
-- NAND's second input). `ro_out(i)` taps net(S-1).
--
-- XOR-ensemble-then-sample (D6/D7): the NRO ring taps are XOR-reduced,
-- MASKED by `sel` per ruling 4's ROSEL semantics, into the single `ro_raw`
-- bit the TRNG core 2-FF synchronizes (D7) -- the mask affects only which
-- ring OUTPUTS contribute to the XOR; every ring still oscillates (and
-- burns power) whenever the single shared `enable` is high, independent of
-- `sel` (ruling 4: "a deliberate all-rings-off stuck source... is reached by
-- forcing ro_raw, not by a ROSEL encoding" -- ROSEL=0000 must default to
-- ALL rings, never to a stuck source).
--   ROSEL=0000        => ring_mask = all-ones (every ring contributes).
--   ROSEL/=0000, NRO=8 => bit k of sel enables ring PAIR {2k,2k+1}.
--   ROSEL/=0000, NRO=4 => bit k of sel enables ring k DIRECTLY.
--
-- Genus/SDC notes (own genus tcl, out of scope this session; recorded here
-- per the design doc's Gate Closure section so the intent travels with the
-- RTL): set_dont_touch/preserve on u_ro + every trng_inv/trng_nand instance;
-- set_disable_timing on each ring's loop-closing (feedback) arc, documenting
-- the deliberate broken loop instead of leaving it to Genus's automatic
-- loop-breaker; set_false_path from every u_ro/ro_raw net into the TRNG
-- core's 2-FF synchronizer D pin (the async metastable capture is timed only
-- by the 2-FF sync itself); NO create_clock on any RO net (pure data, D7).
-- ===========================================================================

entity TrngRoEnsemble is
    generic ( NRO : natural := 8 );   -- ring-oscillator count (D6). {4,8} proven (D15).
    port (
        enable : in  std_logic;                     -- '1' lets ALL rings oscillate (shared,
                                                     --   ruling 4); '0' parks every ring (D6)
        sel    : in  std_logic_vector(3 downto 0);   -- XOR-reduction contribution mask (ruling 4)
        sclk   : in  std_logic;                     -- IGNORED here (the rings are async, D6);
                                                     --   used only by the sim arch's LFSR model
        ro_raw : out std_logic                      -- XOR of the enabled/masked ring outputs
    );
end entity TrngRoEnsemble;

-- ---------------------------------------------------------------------------
-- Wrapper gates (ruling 2). Each carries exactly ONE real gate's worth of
-- logic; Genus maps the wrapper body to one library cell and the
-- dont_touch/preserve attributes (applied at the wrapper-instance level in
-- the genus tcl) keep that mapping from being optimized away.
-- ---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity trng_inv is
    port (
        a : in  std_logic;
        y : out std_logic
    );
end entity trng_inv;

library ieee;
use ieee.std_logic_1164.all;

architecture rtl of trng_inv is
begin
    y <= not a;
end architecture rtl;

library ieee;
use ieee.std_logic_1164.all;

entity trng_nand is
    port (
        a : in  std_logic;
        b : in  std_logic;
        y : out std_logic
    );
end entity trng_nand;

library ieee;
use ieee.std_logic_1164.all;

architecture rtl of trng_nand is
begin
    y <= a nand b;
end architecture rtl;

-- ---------------------------------------------------------------------------
-- architecture rtl of TrngRoEnsemble -- the REAL ring ensemble.
-- ---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

architecture rtl of TrngRoEnsemble is

    -- Per-ring total stage count (D6/ruling 4, indices 0..7; NRO=4 uses the
    -- first four). Each S includes the one enable NAND + (S-1) inverters.
    type stage_arr_t is array (0 to 7) of natural;
    constant RING_STAGES : stage_arr_t := (13, 17, 19, 23, 29, 31, 37, 41);

    signal ro_out    : std_logic_vector(NRO - 1 downto 0);   -- per-ring raw tap
    signal ring_mask : std_logic_vector(NRO - 1 downto 0);   -- ruling-4 XOR contribution mask
    signal masked    : std_logic_vector(NRO - 1 downto 0);   -- ro_out AND ring_mask
    signal all_zero_sel : std_logic;

begin

    all_zero_sel <= '1' when sel = "0000" else '0';

    -- ---------------- ring_mask (ruling 4 ROSEL semantics) -----------------
    gen_mask_nro8: if NRO = 8 generate
        gen_mi8: for k in 0 to 3 generate
            ring_mask(2 * k)     <= '1' when all_zero_sel = '1' else sel(k);
            ring_mask(2 * k + 1) <= '1' when all_zero_sel = '1' else sel(k);
        end generate gen_mi8;
    end generate gen_mask_nro8;

    gen_mask_nro4: if NRO = 4 generate
        gen_mi4: for k in 0 to 3 generate
            ring_mask(k) <= '1' when all_zero_sel = '1' else sel(k);
        end generate gen_mi4;
    end generate gen_mask_nro4;

    -- ---------------- NRO rings, each an odd-length inverter+NAND loop -----
    gen_ring: for i in 0 to NRO - 1 generate
        signal stage_net : std_logic_vector(0 to RING_STAGES(i) - 1);
    begin
        -- enable NAND: closes the loop, parks the ring when enable='0' (D6).
        nand0: entity work.trng_nand
            port map (
                a => enable,
                b => stage_net(RING_STAGES(i) - 1),
                y => stage_net(0)
            );

        -- (RING_STAGES(i)-1) plain inverters completing the odd-length loop.
        gen_inv: for j in 0 to RING_STAGES(i) - 2 generate
            invj: entity work.trng_inv
                port map (
                    a => stage_net(j),
                    y => stage_net(j + 1)
                );
        end generate gen_inv;

        ro_out(i) <= stage_net(RING_STAGES(i) - 1);
    end generate gen_ring;

    -- ---------------- XOR-ensemble, masked (D6/D7) -------------------------
    gen_masked: for i in 0 to NRO - 1 generate
        masked(i) <= ro_out(i) and ring_mask(i);
    end generate gen_masked;

    gen_xor8: if NRO = 8 generate
        ro_raw <= masked(0) xor masked(1) xor masked(2) xor masked(3) xor
                  masked(4) xor masked(5) xor masked(6) xor masked(7);
    end generate gen_xor8;

    gen_xor4: if NRO = 4 generate
        ro_raw <= masked(0) xor masked(1) xor masked(2) xor masked(3);
    end generate gen_xor4;

end architecture rtl;
