-- =============================================================================
-- afe_stub.vhd
-- =============================================================================
-- Digital register stub for one analog front-end (AFE) site or for the shared EIS engine: 16 words in one 64 B sub-slot, standing in for the analog IP.
-- Every access is qualified against the arbiter's granted-master index: an AFE for hart h answers only when s_master is h or MGMT_HART, and EIS is instantiated with OWNER_HART equal to MGMT_HART so its gate is management-hart-only.
-- A denied read returns 0 and a denied write is dropped: no bus error, no stall, no arbiter-contract change, and no way to forge ownership.
-- The bank is exactly four AFE sites plus EIS at any hart count, because there are four physical analog channels.
-- Reads never mutate state; keep them that way (W1C flags only) so LR/SC or AMO to an AFE address stays harmless.
--
-- Register map (word offset; only addr(3:0) is decoded, so the block aliases every 16 words within its sub-slot):
--   +0x0 CTRL   RW  control; a write with wdata bit 0 = 1 soft-sets IF bit 0, the test hook that exercises the interrupt path until the analog IP drives real events
--   +0x1 DACPAT RW  DAC pattern control placeholder
--   +0x2 TIA    RW  TIA gain-range placeholder
--   +0x3 SWM    RW  switch-matrix and analog-mux config placeholder
--   +0x4 ADCC   RW  ADC control placeholder
--   +0x5 ADCD   RW  ADC data placeholder
--   +0x6 STAT   RW  status placeholder
--   +0x7 IF     W1C interrupt-flag word: a set bit drives irq high, writing a 1 to a bit clears it, and reads are side-effect-free
--   +0x8..0xF  RW  scratch and reserved (plain storage)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity afe_stub is
    generic (
        -- Hart that, together with MGMT_HART, may access this block.
        OWNER_HART : natural := 0;
        -- The management hart, the one master that reaches every site.
        MGMT_HART  : natural := 0;
        -- Word registers: 16 of them, one 64 B sub-slot, so addr is 4 bits.
        NREG       : natural := 16
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- Slave port behind mp_arbiter: one-cycle active-high en, four active-high byte lanes.
        -- we is resv-gated in MCU.vhd, because a suppressed SC write must not touch a register either.
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);      -- word offset within the sub-slot
        wdata  : in  std_logic_vector(31 downto 0);
        master : in  std_logic_vector;                  -- arbiter s_master, unconstrained so one entity serves any master-index width
        rdata  : out std_logic_vector(31 downto 0);     -- registered read: address at T, rdata valid at T+1, so no read bridge is needed

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

    -- Elaboration-time check: addr(3:0) must alias the register file exactly.
    assert NREG = 16
        report "afe_stub: NREG must be 16 (addr is 4 bits, one 64 B sub-slot)"
        severity failure;

    rdata <= rdata_reg;

    -- Level interrupt: high while any flag bit is still set.
    irq   <= '1' when regs(W_IF) /= ZERO32 else '0';

    -- Single slave process: ownership gate, registered read, and lane-merged writes.
    afe_proc: process(clk, resetn)
        variable idx   : integer range 0 to NREG-1;
        variable allow : boolean;
    begin
        if resetn = '0' then
            regs      <= (others => (others => '0'));  -- all zero: the block is a no-op, irq low and reads 0, until software writes it
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if en = '1' then
                -- Ownership gate, keyed off the arbiter's granted-master index.
                allow := (conv_integer(master) = OWNER_HART)
                         or (conv_integer(master) = MGMT_HART);
                idx := conv_integer(addr);

                if allow then
                    -- One-cycle registered read of the pre-write value, side-effect-free.
                    rdata_reg <= regs(idx);

                    if we /= "0000" then
                        if idx = W_IF then
                            -- Interrupt-flag word: write-1-to-clear, per bit within each enabled lane.
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
                            -- Plain lane-merged read/write storage.
                            for l in 0 to 3 loop
                                if we(l) = '1' then
                                    regs(idx)(l*8 + 7 downto l*8) <= wdata(l*8 + 7 downto l*8);
                                end if;
                            end loop;
                            -- CTRL test hook: soft-set IF(0), standing in for the analog event.
                            if idx = W_CTRL and we(0) = '1' and wdata(0) = '1' then
                                regs(W_IF)(0) <= '1';
                            end if;
                        end if;
                    end if;
                else
                    -- Denied access: the read returns 0 and the write is dropped, leaving every register untouched.
                    rdata_reg <= (others => '0');
                end if;
            end if;
        end if;
    end process;

end architecture;
