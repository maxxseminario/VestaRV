/* =============================================================================
   mutex_bank.vhd
   =============================================================================
   Hardware mutex bank: 1-instruction cross-hart mutual exclusion, atomic because mp_arbiter serializes whole transactions.
     READ  mutex[i] : returns 0 and claims it for the reading master (owner := master+1) if free, else returns the holder's hartid+1 and leaves it undisturbed.
     WRITE 0        : release, owner-unqualified so a supervisory hart can force-release a dead hart's mutex.
     WRITE nonzero  : ignored, so ownership can never be forged.
   Software acquires with `lw t0, (MUTEXi)` (t0 = 0 means you hold it), releases with `sw x0, (MUTEXi)`, and spins with hartid-scaled backoff; the locks are ADVISORY, since stall-until-release would be a deadlock generator.
   Never LR/SC or AMO a mutex address: a reservation-failed SC arrives with its lanes suppressed by resv_unit and is indistinguishable from a claim-read.
   Bus contract: active-high one-cycle en strobe, 4 active-high byte-lane strobes we (resv-gated in MCU.vhd), read registered one mclk after the strobe, free-running mclk.
   `master` is the arbiter's granted-master index, valid whenever en is strobed, and it is what makes the claim-read attributable.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mutex_bank is
    generic (
        NMUTEX : natural := 16;   -- word-mapped mutexes (16 = one slot pitch)
        -- Decoded word-address width (2**AW must equal NMUTEX) and the arbiter's granted-master width (must match mp_arbiter's MW).
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

    -- Elaboration-time check, no hardware: the addr slice must alias the bank EXACTLY, since an idx beyond NMUTEX-1 would fall off the owner array.
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
