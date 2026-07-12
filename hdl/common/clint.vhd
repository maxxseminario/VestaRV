-- =============================================================================
-- clint.vhd  (M5b)
-- =============================================================================
-- Minimal real CLINT for the 4-hart MCU_MP: per-hart software interrupts
-- (msip, the IPI mechanism) + a shared 64-bit mtime with per-hart mtimecmp
-- (timer interrupts). Replaces nothing: the M5a soft-CLINT mailboxes in the
-- shared RAM stay as-is (they gate the regression); this block adds REAL
-- interrupt delivery so parked harts can SLEEP/WFI instead of poll.
--
-- PLACEMENT: second slave behind mp_arbiter in the shared window (region 4),
-- at 0x11000-0x11FFF (word-address bits 11:10 = "01"; the shared RAM keeps
-- 0x10000-0x103FF). All four harts reach it through their existing shared-
-- window master ports -- no new interconnect. Runs on the free-running mclk
-- (same clock as the arbiter and every vesta's irq_handler -> no CDC).
--
-- REGISTER MAP (byte address = block base + 4*word; only addr(ADDR_W-1:0)
-- decoded, so the block aliases every 2**ADDR_W words through its page).
-- A1 N-HART FORMULA (Argus generalization; see ~/vesta_docs/argus): with
--   MTIME_W = roundup16(4*NHARTS)/4   (mtime word index)
--   CMP_W   = MTIME_W + 4             (first mtimecmp word index)
--   word 0..NHARTS-1      : msip[h], bit 0 (1 = raise IPI to hart h, 0 = clear)
--   word MTIME_W/+1       : mtime lo/hi (free-running +1 per mclk; writable,
--                           a write to either lane-merges that half)
--   word MTIME_W+2..CMP_W-1 : reserved (read 0)
--   word CMP_W+2h         : mtimecmp[h] lo  } mtip(h) = (mtime >= mtimecmp[h]),
--   word CMP_W+2h+1       : mtimecmp[h] hi  } registered. Resets ALL-ONES -> mtip=0.
-- At NHARTS=4 / ADDR_W=4 this reproduces the original M5b layout EXACTLY
-- (msip words 0-3, mtime 4/5, reserved 6/7, mtimecmp 8+2h/9+2h, aliasing
-- every 16 words) -- proven byte-identical decode, the Castalia shape.
-- ADDR_W must satisfy 2**ADDR_W >= CMP_W + 2*NHARTS (asserted below);
-- the chip generator (platform/common/python/mcu_vhd.py) computes it.
--
-- IRQ OUTPUTS: msip(h)/mtip(h) are level signals into hart h's irq_vector
-- (slots IRQB_CLINT_MSIP / IRQB_CLINT_MTIP, MemoryMap.vhd). The ISR clears
-- the level by writing msip[h]=0 / advancing mtimecmp[h] BEFORE iret, or the
-- irq_handler re-triggers.
--
-- BUS CONTRACT (matches mp_arbiter's slave model / the behavioral shared RAM):
-- active-high en, 4 active-high byte-lane strobes we (already resv_unit-gated
-- in MCU.vhd -- a suppressed SC write must not touch the CLINT either), 1-cycle
-- registered read: address at cycle T, rdata valid at T+1. Writes lane-merge.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity clint is
    generic (
        NHARTS : natural := 4;
        -- word-address width; must cover the whole register file (see the
        -- formula in the header). 4 = the Castalia NHARTS=4 shape.
        ADDR_W : natural := 4
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; enables active-high)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(ADDR_W-1 downto 0);   -- word offset within block
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);

        -- per-hart level interrupts
        msip   : out std_logic_vector(NHARTS-1 downto 0);
        mtip   : out std_logic_vector(NHARTS-1 downto 0)
    );
end entity;

architecture behav of clint is

    -- A1 layout formula (header): mtime lo at MTIME_W, mtimecmp[0] lo at
    -- CMP_W. At NHARTS=4 these are 4 and 8 -- the original M5b layout.
    constant MTIME_W : natural := ((4*NHARTS + 15) / 16) * 4;
    constant CMP_W   : natural := MTIME_W + 4;

    type cmp_t is array(0 to NHARTS-1) of std_logic_vector(63 downto 0);

    signal msip_reg  : std_logic_vector(NHARTS-1 downto 0);
    signal mtime     : std_logic_vector(63 downto 0);
    signal mtimecmp  : cmp_t;
    signal mtip_reg  : std_logic_vector(NHARTS-1 downto 0);
    signal rdata_reg : std_logic_vector(31 downto 0);

    -- lane-merge helper result
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

    -- the address port must reach every register of the parameterized layout
    assert 2**ADDR_W >= CMP_W + 2*NHARTS
        report "clint: ADDR_W too small for NHARTS (see the layout formula)"
        severity failure;

    msip  <= msip_reg;
    mtip  <= mtip_reg;
    rdata <= rdata_reg;

    clint_proc: process(clk, resetn)
        variable widx   : integer range 0 to 2**ADDR_W - 1;
        variable hidx   : integer range 0 to NHARTS-1;
        variable rd     : std_logic_vector(31 downto 0);
        variable mtime_next : std_logic_vector(63 downto 0);
    begin
        if resetn = '0' then
            msip_reg  <= (others => '0');
            mtime     <= (others => '0');
            mtimecmp  <= (others => (others => '1'));  -- all-ones: mtip quiet
            mtip_reg  <= (others => '0');
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            -- mtime free-runs; a same-cycle write wins (below)
            mtime_next := mtime + 1;

            if en = '1' then
                widx := conv_integer(addr);
                rd   := (others => '0');

                -- ---- read mux (registered; valid next cycle, arbiter DATA) --
                if widx < NHARTS then                                -- msip[h]
                    rd(0) := msip_reg(widx);
                elsif widx = MTIME_W then                            -- mtime lo
                    rd := mtime(31 downto 0);
                elsif widx = MTIME_W + 1 then                        -- mtime hi
                    rd := mtime(63 downto 32);
                elsif widx >= CMP_W and widx < CMP_W + 2*NHARTS then -- mtimecmp
                    hidx := (widx - CMP_W) / 2;
                    if (widx mod 2) = 0 then
                        rd := mtimecmp(hidx)(31 downto 0);
                    else
                        rd := mtimecmp(hidx)(63 downto 32);
                    end if;
                end if;
                rdata_reg <= rd;

                -- ---- lane-merged writes --------------------------------------
                if we /= "0000" then
                    if widx < NHARTS then
                        if we(0) = '1' then          -- msip is bit 0 (lane 0)
                            msip_reg(widx) <= wdata(0);
                        end if;
                    elsif widx = MTIME_W then
                        mtime_next(31 downto 0) :=
                            lane_merge(mtime(31 downto 0), wdata, we);
                    elsif widx = MTIME_W + 1 then
                        mtime_next(63 downto 32) :=
                            lane_merge(mtime(63 downto 32), wdata, we);
                    elsif widx >= CMP_W and widx < CMP_W + 2*NHARTS then
                        hidx := (widx - CMP_W) / 2;
                        if (widx mod 2) = 0 then
                            mtimecmp(hidx)(31 downto 0) <=
                                lane_merge(mtimecmp(hidx)(31 downto 0), wdata, we);
                        else
                            mtimecmp(hidx)(63 downto 32) <=
                                lane_merge(mtimecmp(hidx)(63 downto 32), wdata, we);
                        end if;
                    end if;
                end if;
            end if;

            mtime <= mtime_next;

            -- ---- registered timer compares (level mtip) ----------------------
            for h in 0 to NHARTS-1 loop
                if mtime >= mtimecmp(h) then
                    mtip_reg(h) <= '1';
                else
                    mtip_reg(h) <= '0';
                end if;
            end loop;
        end if;
    end process;

end architecture;
