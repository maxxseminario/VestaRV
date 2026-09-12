-- VestaRV: hardware mutex bank
-- One-instruction cross-hart mutual exclusion, atomic because mp_arbiter serializes whole transactions. A READ of mutex[i] returns 0 and claims it for the reading master (owner := master+1) if free, else returns the holder's hartid+1 and leaves it undisturbed; a WRITE of 0 releases, owner-unqualified so a supervisory hart can force-release a dead hart's mutex; a nonzero WRITE is ignored, so ownership can never be forged.
-- Software acquires with `lw t0, (MUTEXi)` (t0 = 0 means you hold it), releases with `sw x0, (MUTEXi)`, and spins with hartid-scaled backoff. The locks are ADVISORY, since stall-until-release would be a deadlock generator.
-- Never LR/SC or AMO a mutex address: a reservation-failed SC arrives with its lanes suppressed by resv_unit and is indistinguishable from a claim-read.
-- Bus: active-high one-cycle en strobe, four active-high byte-lane strobes we (resv-gated in MCU.vhd), read registered one mclk after the strobe, free-running mclk. `master` is the arbiter's granted-master index, valid whenever en is strobed, and it is what makes the claim-read attributable.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library work;
use work.Constants.all;   -- word, word_array, the one shared array-of-word type
-- Word offsets, field ranges, resets and the periph_regs tables: generated from hdl/common/regs/rdl/mutex_bank.rdl.
-- The tables are FUNCTIONS of NMUTEX and MW, not constants, because the register set is: see hdl/common/regs/REGFILE.md.
use work.mutex_bank_regs_pkg.all;

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

    -- The bank IS one periph_regs instance: NMUTEX identical words whose only
    -- implemented bits are the owner marker, MW downto 0. See
    -- hdl/common/regs/REGFILE.md. Owner 0 = free, else hartid+1; hartid is at
    -- most 2**MW - 1, so hartid+1 always fits MW+1 bits (4 at the Castalia
    -- default). What is left in this file is the claim rule and the bus polarity.
    constant NW         : natural := NWORDS(NMUTEX, MW);
    subtype  reg_arr_t is word_array(0 to NW-1);
    -- The owner field's mask, out of the package's own IMPL table. Every word
    -- carries the same one, so row 0 is the whole statement.
    constant OWNER_MASK : word := IMPL(NMUTEX, MW)(0);
    constant OWNER_FREE : std_logic_vector(MW downto 0) := (others => '0');
    -- A write of 0 releases and a nonzero write is IGNORED, whatever its lanes,
    -- so every word takes the whole 32 bits from any enabled lane and the
    -- nonzero case is refused through wr_inhibit rather than masked.
    constant ALL_WIDE   : std_logic_vector(0 to NW-1) := (others => '1');

    signal regs_q     : reg_arr_t;   -- the owner words
    signal hw_we_s    : reg_arr_t;   -- the claim: hardware writes the reading master's marker
    signal hw_wdata_s : reg_arr_t;
    signal rd_hit_s   : std_logic_vector(0 to NW-1);   -- this word, read, this cycle
    signal inhib_s    : std_logic_vector(0 to NW-1);   -- a nonzero write is not a write
    signal own_new    : word;                          -- master + 1, the claimant's marker
    signal en_n       : std_logic;                     -- the module's select and lanes are ACTIVE LOW
    signal wen_n      : std_logic_vector(3 downto 0);
    signal mab        : std_logic_vector(7 downto 2);  -- the AW-bit word offset in the module's 6-bit slot

begin

    -- Elaboration-time checks, no hardware: the addr slice must alias the bank EXACTLY, since an idx beyond NMUTEX-1 would fall off the owner array, and the bank must fit the module's 64-word slot.
    assert 2**AW = NMUTEX
        report "mutex_bank: NMUTEX must equal 2**AW (exact word alias)"
        severity failure;
    assert AW <= 6
        report "mutex_bank: the bank outgrows periph_regs' 64-word slot"
        severity failure;

    -- The module's bus is active low; this block's, an arbiter slave's, is active high.
    en_n  <= not en;
    wen_n <= not we;
    mab_ext: process(addr)
    begin
        mab <= (others => '0');
        mab(AW+1 downto 2) <= addr;
    end process;

    -- A nonzero write forges an owner, so it is refused OUTRIGHT rather than
    -- masked: wr_inhibit makes the access neither a write nor an arm of the word.
    -- The qualifier is live bus state, which is exactly what the port is for.
    inhib_s <= (others => '0') when wdata = x"00000000" else (others => '1');

    -- The claimant's marker. The arbiter's granted-master index is what makes a
    -- claim-read attributable, and it is valid whenever en is strobed.
    own_new <= conv_std_logic_vector(conv_integer(master) + 1, 32);

    -- Claim-read: atomic return-old-and-claim in ONE transaction, the arbiter's
    -- serialization being the atomicity. periph_regs registers the read from the
    -- storage it holds BEFORE this hook lands, so the returned word is still the
    -- pre-transaction owner, which is what "0 means it is now yours" rests on.
    -- One mux, one comparator and one demux, as the hand-written decode had.
    claim_proc: process(rd_hit_s, regs_q, own_new, addr)
        variable idx : integer range 0 to NMUTEX-1;
    begin
        hw_we_s    <= (others => (others => '0'));
        hw_wdata_s <= (others => own_new);
        idx := conv_integer(addr);
        if rd_hit_s(idx) = '1' and regs_q(idx)(MW downto 0) = OWNER_FREE then
            hw_we_s(idx) <= OWNER_MASK;
        end if;
    end process;

    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NW,
            RSTVAL      => RSTVAL(NMUTEX, MW),
            IMPL        => IMPL(NMUTEX, MW),
            W1C         => W1C(NMUTEX, MW),
            WOSET       => WOSET(NMUTEX, MW),
            WOT         => WOT(NMUTEX, MW),
            PULSE       => PULSE(NMUTEX, MW),
            RCLR        => RCLR(NMUTEX, MW),
            HWOWN       => HWOWN(NMUTEX, MW),
            WIDEWR      => ALL_WIDE)
        port map (
            ClkMem      => clk,
            resetn      => resetn,
            EnMemPeriph => en_n,
            WEn         => wen_n,
            MABPart     => mab,
            wdata       => wdata,
            rdata_out   => rdata,
            regs        => regs_q,
            wr_inhibit  => inhib_s,
            hw_we       => hw_we_s,
            hw_wdata    => hw_wdata_s,
            acc_hit     => open,
            rd_hit      => rd_hit_s,
            wr_hit      => open,
            rd_strobe   => open,
            wr_strobe   => open,
            wr_pulse    => open,
            w1c_hit     => open,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

end architecture;
