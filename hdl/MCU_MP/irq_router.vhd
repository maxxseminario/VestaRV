-- =============================================================================
-- irq_router.vhd  (M7a)
-- =============================================================================
-- Tile IRQ fan-out: per-hart peripheral-IRQ ENABLE registers, programmable by
-- ANY hart through the shared window. Before M7a, peripheral IRQs terminated
-- exclusively in hart 0's SYSTEM/irq_en; the tiles (harts 1-3) had only the
-- two hardwired CLINT slots (83 msip / 84 mtip). This block gives software a
-- way to ROUTE any peripheral's level IRQ to whichever hart currently owns
-- that peripheral: the deglitched irq vector fans out to every tile, and each
-- tile ANDs it with ITS row of this register bank (OR'd with its hardwired
-- CLINT slots) — see hart_tile.vhd.
--
-- PLACEMENT: fourth slave behind mp_arbiter in the shared window (region 4),
-- in the 0x13000 page at SLOT 9 = 0x13900-0x139FF. The 0x13000-0x13FFF page
-- is carved into 16 x 256B slots (slot = word-address bits 9:6) that MIRROR
-- the legacy 0x4000 peripheral page's slot numbering; slot 9 is SYSTEM0's
-- slot there, and this is the MP system-control block — the mnemonic is
-- intentional. Slots 0-8/10-15 are for the M7b+ shared peripherals.
--
-- REGISTER MAP (byte address = 0x13900 + 4*word; only addr(3:0) decoded, so
-- the block aliases every 16 words through its 256B slot):
--   word 4h+0 : HhENL = irq_en[31:0]   for hart h   (h = 0..3)
--   word 4h+1 : HhENM = irq_en[63:32]  for hart h
--   word 4h+2 : HhENU = irq_en[84:64]  for hart h   (bits 20:0; CONTIGUOUS
--               packing in BOTH directions — deliberately NOT SYSTEM0's
--               SYS_IRQ_ENU write-packing quirk)
--   word 4h+3 : reserved (reads 0)
-- All registers reset to 0 = everything masked -> block is a provable NO-OP
-- until software routes something. Row 0 exists for symmetry/debug but is
-- NOT wired to hart 0 in MCU.vhd (hart 0's enables come from SYSTEM0, the
-- management monarch, as ever).
--
-- The CLINT slots (83/84) are writable here like any other bit, but the tile
-- ORs its hardwired enables over them, so they cannot be masked — only
-- redundantly re-enabled.
--
-- BUS CONTRACT (same as clint.vhd / the behavioral shared RAM): active-high
-- en one-cycle strobe, 4 active-high byte-lane strobes we (resv_unit-gated in
-- MCU.vhd — a suppressed SC write must not touch this block either), 1-cycle
-- registered read: address at cycle T, rdata valid at T+1. Writes lane-merge.
-- Runs on the free-running mclk — same domain as every vesta's irq_handler,
-- so a routed IRQ can wake a hart whose gated clk_cpu is OFF.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity irq_router is
    generic (
        NHARTS   : natural := 4;
        NUM_IRQS : natural := 85
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; enables active-high)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);   -- word offset within slot
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);

        -- per-hart IRQ enables, flattened (hart h = bits
        -- [(h+1)*NUM_IRQS-1 : h*NUM_IRQS]); feed each tile's irq_en_ext
        irq_en_out : out std_logic_vector(NHARTS*NUM_IRQS-1 downto 0)
    );
end entity;

architecture behav of irq_router is

    -- storage as 3 words per hart (L/M/U); U only NUM_IRQS-64 bits live
    type en_words_t is array(0 to NHARTS*3-1) of std_logic_vector(31 downto 0);
    signal en_words  : en_words_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

    function lane_merge(cur   : std_logic_vector(31 downto 0);
                        wd    : std_logic_vector(31 downto 0);
                        lanes : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable r : std_logic_vector(31 downto 0);
    begin
        r := cur;
        for l in 0 to 3 loop
            if lanes(l) = '1' then
                r((l+1)*8-1 downto l*8) := wd((l+1)*8-1 downto l*8);
            end if;
        end loop;
        return r;
    end function;

begin

    rdata <= rdata_reg;

    -- flatten the register bank onto the per-hart enable buses (upper-word
    -- bits above NUM_IRQS-1 simply have no consumer)
    gen_fanout: for h in 0 to NHARTS-1 generate
        gen_bits: for b in 0 to NUM_IRQS-1 generate
            irq_en_out(h*NUM_IRQS + b) <= en_words(h*3 + b/32)(b mod 32);
        end generate;
    end generate;

    router_proc: process(clk, resetn)
        variable widx : integer range 0 to 15;
        variable hidx : integer range 0 to NHARTS-1;
        variable wsub : integer range 0 to 3;
        variable rd   : std_logic_vector(31 downto 0);
    begin
        if resetn = '0' then
            en_words  <= (others => (others => '0'));  -- all masked: NO-OP
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                widx := conv_integer(addr);
                hidx := widx / 4;
                wsub := widx mod 4;
                rd   := (others => '0');

                -- ---- read mux (registered; valid next cycle, arbiter DATA) --
                if wsub /= 3 then
                    rd := en_words(hidx*3 + wsub);
                end if;
                rdata_reg <= rd;

                -- ---- lane-merged writes -------------------------------------
                if we /= "0000" and wsub /= 3 then
                    en_words(hidx*3 + wsub) <=
                        lane_merge(en_words(hidx*3 + wsub), wdata, we);
                end if;
            end if;
        end if;
    end process;

end architecture;
