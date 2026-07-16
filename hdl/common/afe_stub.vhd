-- =============================================================================
-- afe_stub.vhd  (CQ2a — AFE / EIS digital register stub)
-- =============================================================================
-- DIGITAL REGISTER STUB for a Castalia-Quad analog front-end (AFE) site or the
-- shared EIS engine. A plain registered-read arbiter-slave register file (16
-- words = one 64 B sub-slot) that stands in for the real analog IP until it
-- arrives — it holds the control/DAC-pattern/TIA-gain/switch-matrix/ADC
-- control+data/status placeholders plus a write-1-to-clear interrupt-flag word,
-- and drives one level interrupt from that flag word.
--
-- OWNERSHIP GATE (the whole point of instantiating it per site): every access
-- is qualified against the arbiter's granted-master index (mp_arbiter s_master,
-- the mutex-bank / CLAIM precedent). An AFE for hart h answers only when
-- s_master = h OR s_master = 0 (hart 0 is the management hart and reaches every
-- site); the EIS engine is instantiated with OWNER_HART = 0, so its gate
-- collapses to s_master = 0 only. A DENIED read returns 0 and a DENIED write is
-- dropped — NO bus error, NO stall, NO arbiter-contract change (the gate lives
-- entirely inside this slave shim). The gate keys off s_master alone; there is
-- no cross-hart data leakage and no way to forge ownership.
--
-- REGISTER MAP (word offset in the 16-word / 64 B sub-slot; only addr(3:0)
-- decoded, so the block aliases every 16 words within its sub-slot):
--   +0x0 CTRL   RW  control. As a TEST HOOK standing in for the (absent)
--                   analog event, a write with wdata bit 0 = 1 SOFT-SETS
--                   IF bit 0 — this is how the level interrupt path is
--                   exercised until the analog IP drives real events.
--   +0x1 DACPAT RW  DAC pattern control placeholder
--   +0x2 TIA    RW  TIA gain-range placeholder
--   +0x3 SWM    RW  switch-matrix / analog-mux config placeholder
--   +0x4 ADCC   RW  ADC control placeholder
--   +0x5 ADCD   RW  ADC data placeholder
--   +0x6 STAT   RW  status placeholder
--   +0x7 IF     W1C interrupt-flag word: a set bit drives irq high (level);
--                   writing a 1 to a bit CLEARS it. READ is side-effect-free.
--   +0x8..0xF  RW  scratch / reserved (plain storage)
--
-- BUS CONTRACT (same as clint.vhd / mutex_bank.vhd / pwr_ctrl.vhd): active-high
-- en one-cycle strobe, 4 active-high byte-lane strobes we (resv-GATED in
-- MCU.vhd — a suppressed SC write must not touch a register either), 1-cycle
-- REGISTERED read (address at cycle T, rdata valid at T+1 — no combinational
-- read, so no i2c_rdata_bridge latch is needed), free-running mclk. `master` is
-- the arbiter's granted-master index (UNCONSTRAINED so one entity serves any
-- s_master width — Castalia MW=2, Argus MW=5). All registers reset to 0, so the
-- block is a provable NO-OP (irq low, reads 0) until software writes it.
--
-- SIDE-EFFECT-FREE READS: reads never mutate state, so it is safe (though
-- pointless) to LR/SC or AMO an AFE address — but keep AFE reads side-effect-
-- free (W1C flags only) so that stays true, exactly as the mutex-bank rule
-- warns for the opposite case.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity afe_stub is
    generic (
        -- Hart that (together with hart 0) may access this block. EIS uses 0,
        -- which makes the gate hart-0-only.
        OWNER_HART : natural := 0;
        -- Word registers (16 = one 64 B sub-slot). addr is 4 bits.
        NREG       : natural := 16
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; en active-high, we resv-gated)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);      -- word offset within the sub-slot
        wdata  : in  std_logic_vector(31 downto 0);
        master : in  std_logic_vector;                  -- arbiter s_master (unconstrained width)
        rdata  : out std_logic_vector(31 downto 0);

        -- level interrupt: high while any IF bit is set
        irq    : out std_logic
    );
end entity;

architecture behav of afe_stub is

    constant W_CTRL : natural := 0;   -- control (soft-set test hook)
    constant W_IF   : natural := 7;   -- interrupt-flag word (W1C, drives irq)
    constant ZERO32 : std_logic_vector(31 downto 0) := (others => '0');

    type reg_arr_t is array(0 to NREG-1) of std_logic_vector(31 downto 0);
    signal regs      : reg_arr_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

begin

    -- elaboration-time coverage: addr(3:0) must alias the register file exactly
    assert NREG = 16
        report "afe_stub: NREG must be 16 (addr is 4 bits, one 64 B sub-slot)"
        severity failure;

    rdata <= rdata_reg;
    irq   <= '1' when regs(W_IF) /= ZERO32 else '0';

    afe_proc: process(clk, resetn)
        variable idx   : integer range 0 to NREG-1;
        variable allow : boolean;
    begin
        if resetn = '0' then
            regs      <= (others => (others => '0'));  -- all zero: NO-OP, irq low
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                -- ownership gate keyed off the arbiter's granted-master index
                allow := (conv_integer(master) = OWNER_HART)
                         or (conv_integer(master) = 0);
                idx := conv_integer(addr);

                if allow then
                    -- 1-cycle registered read (pre-write value; side-effect-free)
                    rdata_reg <= regs(idx);

                    if we /= "0000" then
                        if idx = W_IF then
                            -- interrupt-flag word: write-1-to-clear per bit/lane
                            for l in 0 to 3 loop
                                if we(l) = '1' then
                                    for b in 0 to 7 loop
                                        if wdata(l*8 + b) = '1' then
                                            regs(W_IF)(l*8 + b) <= '0';
                                        end if;
                                    end loop;
                                end if;
                            end loop;
                        else
                            -- plain lane-merged R/W storage
                            for l in 0 to 3 loop
                                if we(l) = '1' then
                                    regs(idx)(l*8 + 7 downto l*8) <= wdata(l*8 + 7 downto l*8);
                                end if;
                            end loop;
                            -- CTRL test hook: soft-set IF(0) (stands in for the
                            -- analog event until the real IP drives it)
                            if idx = W_CTRL and we(0) = '1' and wdata(0) = '1' then
                                regs(W_IF)(0) <= '1';
                            end if;
                        end if;
                    end if;
                else
                    -- denied: read returns 0, write dropped (no reg change)
                    rdata_reg <= (others => '0');
                end if;
            end if;
        end if;
    end process;

end architecture;
