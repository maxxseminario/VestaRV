-- =============================================================================
-- mutex_bank.vhd  (M7c, LOCKING v2)
-- =============================================================================
-- HARDWARE MUTEX BANK: 1-instruction cross-hart mutual exclusion.
-- Atomic for free, because the mp_arbiter serializes whole transactions: no LR/SC loop, no cross-hart-AMO dependence.
--
--   READ  mutex[i] : atomic RETURN-OLD-AND-CLAIM.
--                    Returns 0 if the mutex was free, and the SAME transaction claims it for the reading master (owner := master+1).
--                    Returns owner (hartid+1) if held; a claim-read of a held mutex does NOT disturb it, so re-reading your own mutex returns your own marker.
--   WRITE 0        : release (owner := 0).
--                    Deliberately UNQUALIFIED by owner so a supervisory hart can force-release a dead hart's mutex; correct software only releases what it holds.
--   WRITE nonzero  : ignored (no way to forge ownership).
--
-- Software contract: `lw t0, (MUTEXi)`, where t0 == 0 means you now hold it; otherwise spin with hartid-scaled backoff per the M4c livelock rule.
-- Release with `sw x0, (MUTEXi)`.
-- NEVER LR/SC a mutex address: a reservation-failed SC arrives here with its lanes suppressed by resv_unit and would be indistinguishable from a claim-read.
-- These are ADVISORY locks; nothing is bus-enforced (no core bus-error path exists, and stall-until-release would be a deadlock generator by design decision).
--
-- PLACEMENT: page-3 slot 0 = 0x13000-0x130FF, GPIO0's legacy slot number, free forever because GPIO0 is never shared.
-- NMUTEX=16 word-mapped mutexes at 0x13000 + 4*i; only addr(3:0) is decoded, so the bank aliases every 16 words through its 256B slot.
--
-- BUS CONTRACT (same as clint.vhd / irq_router.vhd): active-high en one-cycle strobe, 4 active-high byte-lane strobes we (resv-GATED in MCU.vhd), 1-cycle registered read (address at cycle T, rdata valid at T+1), free-running mclk.
-- The one extra input is `master`, the arbiter's granted-master index (mp_arbiter s_master), valid whenever en is strobed.
-- It is what makes the claim-read attributable, and it is the ONLY reason the arbiter exports it.
-- All mutexes reset FREE, so the block is a provable NO-OP until software reads a mutex word.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mutex_bank is
    generic (
        NMUTEX : natural := 16;   -- word-mapped mutexes (16 = one slot pitch)
        -- A2 (Argus): decoded word-address width (2**AW must cover NMUTEX) and the arbiter's s_master width (must match mp_arbiter's MW).
        -- Defaults are the Castalia 4-hart / 16-mutex shape.
        AW     : natural := 4;
        MW     : natural := 2
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; enables active-high, we resv-gated)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(AW-1 downto 0); -- word offset within the bank
        wdata  : in  std_logic_vector(31 downto 0);
        master : in  std_logic_vector(MW-1 downto 0); -- granted master (arbiter)
        rdata  : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of mutex_bank is

    -- Owner per mutex: 0 = free, else hartid+1.
    -- hartid is at most 2**MW - 1, so hartid+1 always fits MW+1 bits (3 bits at the Castalia default).
    type owner_t is array(0 to NMUTEX-1) of std_logic_vector(MW downto 0);
    constant OWNER_FREE : std_logic_vector(MW downto 0) := (others => '0');
    signal owner     : owner_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

begin

    -- A2 coverage assert (elaboration-time constant, no hardware).
    -- Equality is required, not just coverage: the addr slice must alias the bank exactly, since an idx beyond NMUTEX-1 would fall off the owner array.
    assert 2**AW = NMUTEX
        report "mutex_bank: NMUTEX must equal 2**AW (exact word alias)"
        severity failure;

    rdata <= rdata_reg;   -- registered read, valid one mclk after the strobe

    -- Single owner-array process: one strobed transaction per cycle, claim on read, release on write of 0.
    mutex_proc: process(clk, resetn)
        variable idx : integer range 0 to NMUTEX-1;
    begin
        if resetn = '0' then
            owner     <= (others => (others => '0'));  -- all mutexes free: the bank is a NO-OP until the first read
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                idx := conv_integer(addr);

                -- Registered read ALWAYS returns the pre-transaction owner, where 0 means "was free, and this read just claimed it for you".
                rdata_reg              <= (others => '0');
                rdata_reg(MW downto 0) <= owner(idx);

                if we = "0000" then
                    -- Claim-read: atomic return-old-and-claim in ONE transaction, the arbiter's serialization being the atomicity.
                    if owner(idx) = OWNER_FREE then
                        owner(idx) <= ('0' & master) + 1;
                    end if;
                elsif wdata = x"00000000" then
                    -- Release, owner-unqualified (see header); nonzero writes are ignored so ownership can never be forged.
                    owner(idx) <= OWNER_FREE;
                end if;
            end if;
        end if;
    end process;

end architecture;
