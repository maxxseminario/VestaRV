-- =============================================================================
-- mutex_bank.vhd  (M7c — LOCKING v2)
-- =============================================================================
-- HARDWARE MUTEX BANK: 1-instruction cross-hart mutual exclusion, atomic FOR
-- FREE because the mp_arbiter serializes whole transactions — no LR/SC loop,
-- no cross-hart-AMO dependence.
--
--   READ  mutex[i] : atomic RETURN-OLD-AND-CLAIM. Returns 0 if the mutex was
--                    free — and the SAME transaction claims it for the reading
--                    master (owner := master+1). Returns owner (hartid+1) if
--                    held; a claim-read of a held mutex does NOT disturb it
--                    (re-reading your own mutex returns your own marker).
--   WRITE 0        : release (owner := 0). Deliberately UNQUALIFIED by owner
--                    so a supervisory hart can force-release a dead hart's
--                    mutex; correct software only releases what it holds.
--   WRITE nonzero  : ignored (no way to forge ownership).
--
-- Software contract: `lw t0, (MUTEXi)` — t0 == 0 means you now hold it (spin
-- with backoff otherwise, hartid-scaled per the M4c livelock rule); release
-- with `sw x0, (MUTEXi)`. NEVER LR/SC a mutex address: a reservation-failed
-- SC arrives here with its lanes suppressed by resv_unit and would be
-- indistinguishable from a claim-read. These are ADVISORY locks — nothing is
-- bus-enforced (no core bus-error path exists; stall-until-release would be
-- a deadlock generator by design decision).
--
-- PLACEMENT: page-3 slot 0 = 0x13000-0x130FF (GPIO0's legacy slot number —
-- free forever, GPIO0 is never shared). NMUTEX=16 word-mapped mutexes at
-- 0x13000 + 4*i; only addr(3:0) is decoded, so the bank aliases every 16
-- words through its 256B slot.
--
-- BUS CONTRACT (same as clint.vhd / irq_router.vhd): active-high en one-cycle
-- strobe, 4 active-high byte-lane strobes we (resv-GATED in MCU.vhd), 1-cycle
-- registered read (address at cycle T, rdata valid at T+1), free-running
-- mclk. The one extra input is `master` — the arbiter's granted-master index
-- (mp_arbiter s_master), valid whenever en is strobed; it is what makes the
-- claim-read attributable, and it is the ONLY reason the arbiter exports it.
-- All mutexes reset FREE -> the block is a provable NO-OP until software
-- reads a mutex word.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mutex_bank is
    generic (
        NMUTEX : natural := 16    -- one 256B slot's worth of word-mapped mutexes
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; enables active-high, we resv-gated)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);   -- word offset within slot
        wdata  : in  std_logic_vector(31 downto 0);
        master : in  std_logic_vector(1 downto 0);   -- granted master (arbiter)
        rdata  : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of mutex_bank is

    -- owner per mutex: 0 = free, else hartid+1 (fits 3 bits for 4 harts)
    type owner_t is array(0 to NMUTEX-1) of std_logic_vector(2 downto 0);
    signal owner     : owner_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

begin

    rdata <= rdata_reg;

    mutex_proc: process(clk, resetn)
        variable idx : integer range 0 to NMUTEX-1;
    begin
        if resetn = '0' then
            owner     <= (others => (others => '0'));  -- all free: NO-OP
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                idx := conv_integer(addr);

                -- registered read: ALWAYS returns the pre-transaction owner
                -- (0 = "was free, and this read just claimed it for you")
                rdata_reg              <= (others => '0');
                rdata_reg(2 downto 0)  <= owner(idx);

                if we = "0000" then
                    -- claim-read: atomic return-old-and-claim in ONE txn —
                    -- the arbiter's serialization is the atomicity
                    if owner(idx) = "000" then
                        owner(idx) <= ('0' & master) + 1;
                    end if;
                elsif wdata = x"00000000" then
                    -- release (unqualified — see header); nonzero writes are
                    -- ignored so ownership can never be forged
                    owner(idx) <= "000";
                end if;
            end if;
        end if;
    end process;

end architecture;
