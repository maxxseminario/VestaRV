library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- TrngRoEnsemble.vhd: the ring-oscillator entropy source of TRNG0 (base 0x6900, vector 121), for GENUS AND GATE FLOWS ONLY.
-- Its DELIBERATE combinational ring feedback DELTA-LOOPS a behavioral simulator (zero-time oscillation), so never put this file in a behavioral cell list and never co-list it with TrngRoEnsemble_sim.vhd, which carries the OTHER architecture of this same entity.
-- The behavioral flow compiles TrngRoEnsemble_sim.vhd and only ANALYZES this file (-V200X, no VHDL-2008) as a syntax smoke; if it is ever elaborated and run the sim spins at 100% CPU with frozen sim time and needs an immediate `pkill -9 xmsim`.
-- Each ring is built structurally from the trng_inv/trng_nand wrappers so foundry std-cell names stay out of this repo; dont_touch/preserve, set_disable_timing on each loop-closing arc, set_false_path into the TRNG core's 2-FF synchronizer and the absence of create_clock on any RO net all live in the TRNG genus tcl.
-- GATE BAR: a post-synthesis netlist census must count exactly sum_i(RING_STAGES(i)-1) preserved trng_inv instances plus NRO preserved trng_nand instances, which is what catches a silent ring collapse.
-- ===========================================================================

entity TrngRoEnsemble is
    generic ( NRO : natural := 8 );   -- ring-oscillator count; only 4 and 8 are supported
    port (
        enable : in  std_logic;                     -- '1' lets ALL rings oscillate (one shared enable); '0' parks every ring
        sel    : in  std_logic_vector(3 downto 0);   -- XOR-reduction contribution mask
        sclk   : in  std_logic;                     -- IGNORED here (the rings are async); used only by the sim architecture's LFSR model
        ro_raw : out std_logic                      -- XOR of the enabled/masked ring outputs
    );
end entity TrngRoEnsemble;

-- ---------------------------------------------------------------------------
-- Wrapper gates, each carrying exactly ONE real gate's worth of logic so Genus maps each body to one library cell.
-- The dont_touch/preserve attributes applied to the wrapper instances in the genus tcl keep that mapping from being optimized away.
-- ---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- One inverter: the plain ring stage.
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

-- One 2-input NAND: the ring's enable stage and loop closer.
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
-- architecture rtl of TrngRoEnsemble: the REAL ring ensemble.
-- ---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

architecture rtl of TrngRoEnsemble is

    -- Per-ring total stage count, indices 0..7 (NRO=4 uses the first four): one enable NAND plus (S-1) inverters.
    -- The counts must stay ODD, or the loop settles as a bistable ring latch instead of oscillating, and pairwise-coprime so the rings beat at non-commensurate frequencies.
    type stage_arr_t is array (0 to 7) of natural;
    constant RING_STAGES : stage_arr_t := (13, 17, 19, 23, 29, 31, 37, 41);

    signal ro_out    : std_logic_vector(NRO - 1 downto 0);   -- per-ring raw tap
    signal ring_mask : std_logic_vector(NRO - 1 downto 0);   -- ruling-4 XOR contribution mask
    signal masked    : std_logic_vector(NRO - 1 downto 0);   -- ro_out AND ring_mask
    signal all_zero_sel : std_logic;

begin

    -- ROSEL=0000 is the default-to-ALL-rings encoding, never a stuck source: an all-rings-off source is made by forcing ro_raw instead.
    all_zero_sel <= '1' when sel = "0000" else '0';

    -- ---------------- ring_mask: ROSEL contribution semantics ---------------
    -- The mask only picks which ring OUTPUTS join the XOR; every ring still oscillates, and burns power, whenever the shared enable is high.

    -- NRO=8: each sel bit enables one ring PAIR {2k, 2k+1}.
    gen_mask_nro8: if NRO = 8 generate
        gen_mi8: for k in 0 to 3 generate
            ring_mask(2 * k)     <= '1' when all_zero_sel = '1' else sel(k);
            ring_mask(2 * k + 1) <= '1' when all_zero_sel = '1' else sel(k);
        end generate gen_mi8;
    end generate gen_mask_nro8;

    -- NRO=4: each sel bit enables one ring directly.
    gen_mask_nro4: if NRO = 4 generate
        gen_mi4: for k in 0 to 3 generate
            ring_mask(k) <= '1' when all_zero_sel = '1' else sel(k);
        end generate gen_mi4;
    end generate gen_mask_nro4;

    -- ---------------- NRO rings, each an odd-length inverter+NAND loop -----
    gen_ring: for i in 0 to NRO - 1 generate
        signal stage_net : std_logic_vector(0 to RING_STAGES(i) - 1);
    begin
        -- enable NAND: closes the loop and parks the ring when enable='0'.
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

        -- Ring tap: the last net, which is also the NAND's feedback input.
        ro_out(i) <= stage_net(RING_STAGES(i) - 1);
    end generate gen_ring;

    -- ---------------- XOR ensemble, masked: this is ro_raw, the async bit the TRNG core 2-FF synchronizes ----
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
