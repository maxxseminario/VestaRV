-- VestaRV: CLINT
-- Per-hart software interrupts (msip) and a shared 64-bit mtime with per-hart mtimecmp, for NHARTS harts. Slave behind mp_arbiter in the shared window, on the free-running mclk, so there is no clock-domain crossing.
-- Bus: active-high en, four active-high byte lanes on we, address at cycle T and rdata at T+1, writes lane-merge. Only addr(ADDR_W-1:0) decodes, so the page aliases every 2**ADDR_W words.
-- msip(h) and mtip(h) are levels into hart h's irq_vector: an ISR must write msip[h] = 0 or advance mtimecmp[h] before iret, or the interrupt re-triggers.
-- Word map: 0..NHARTS-1 = msip[h] bit 0; MTIME_W and +1 = mtime lo/hi, free-running and writable; CMP_W+2h and +1 = mtimecmp[h] lo/hi, reset all-ones so mtip starts low.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library work;
use work.Constants.all;   -- word, word_array, the one shared array-of-word type
-- Word offsets, field ranges, resets and the periph_regs tables: generated from hdl/common/regs/rdl/clint.rdl.
-- The tables are FUNCTIONS of NHARTS, MTIME_W and CMP_W, not constants, because the register set is: see hdl/common/regs/REGFILE.md.
use work.clint_regs_pkg.all;

entity clint is
    generic (
        NHARTS : natural := 4;
        -- Word-address width; 2**ADDR_W must cover the whole register file (asserted below)
        ADDR_W : natural := 4
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- Slave port behind mp_arbiter; enables are active-high
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

    -- Word indices of mtime lo and of mtimecmp[0] lo, sized to clear the msip array
    constant MTIME_W : natural := ((4*NHARTS + 15) / 16) * 4;
    constant CMP_W   : natural := MTIME_W + 4;

    -- The whole register file is one periph_regs instance carrying the tables
    -- clint_regs_pkg builds from the three constants above; see
    -- hdl/common/regs/REGFILE.md. msip, mtime and mtimecmp are all plain software
    -- storage, so what is left in this file is the mtime tick and the compares.
    constant NW : natural := NWORDS(NHARTS, MTIME_W, CMP_W);
    subtype  reg_arr_t is word_array(0 to NW-1);

    signal regs_q     : reg_arr_t;   -- msip, mtime lo/hi, mtimecmp lo/hi
    signal hw_we_s    : reg_arr_t;   -- the mtime tick, on the two mtime words only
    signal hw_wdata_s : reg_arr_t;
    signal wr_hit_s   : std_logic_vector(0 to NW-1);   -- a lane write landing this cycle

    signal mtime      : std_logic_vector(63 downto 0);   -- the two stored halves, joined
    signal mtime_next : std_logic_vector(63 downto 0);
    signal mtime_wr   : std_logic;   -- a write is landing on either mtime word
    signal mtip_reg   : std_logic_vector(NHARTS-1 downto 0);

    signal en_n       : std_logic;                     -- the module's select and lanes are ACTIVE LOW
    signal wen_n      : std_logic_vector(3 downto 0);
    signal mab        : std_logic_vector(7 downto 2);  -- the ADDR_W-bit word offset in the module's 6-bit slot

begin

    -- The address port must reach every register of the parameterized layout
    assert 2**ADDR_W >= CMP_W + 2*NHARTS
        report "clint: ADDR_W too small for NHARTS (see the layout formula)"
        severity failure;
    -- periph_regs decodes a 64-word slot (MABPart is six bits), so the layout has
    -- to fit one. CMP_W + 2*NHARTS crosses 64 at NHARTS = 21; every shipped
    -- configuration is at or below 18 (argus), where the file is 60 words.
    assert CMP_W + 2*NHARTS <= 64
        report "clint: the register file outgrows periph_regs' 64-word slot (NHARTS > 20)"
        severity failure;

    -- The module's bus is active low; this block's, an arbiter slave's, is active high.
    en_n  <= not en;
    wen_n <= not we;
    mab_ext: process(addr)
    begin
        mab <= (others => '0');
        mab(ADDR_W+1 downto 2) <= addr;
    end process;

    msip_out: for h in 0 to NHARTS-1 generate
        msip(h) <= regs_q(MSIP0_WORD + h)(CLINTMSIPH0_LSB);
    end generate;
    mtip  <= mtip_reg;

    -- ---- mtime: a free-running 64-bit counter whose two halves are stored words.
    -- The tick is a hardware hook, and periph_regs resolves a lane write BEFORE
    -- the hook only while the hook is off, so the tick is SUPPRESSED on the cycle
    -- a write lands on either half. That is the original rule: a write defines the
    -- whole 64-bit value for that cycle and costs one tick, and the untouched half
    -- does not increment either, so no carry can be lost or duplicated.
    -- The increment is NOT pre-folded into the write: with mtime_next
    -- pre-incremented, a write to the lo word kept the carry the increment had
    -- already pushed into hi, and a write to hi discarded the carry the lo
    -- increment produced. Both are 2^-32-per-write faults on a monotonic clock,
    -- worth 2^32 ticks each.
    mtime      <= regs_q(MTIME_W + 1) & regs_q(MTIME_W);
    mtime_next <= mtime + 1;
    mtime_wr   <= wr_hit_s(MTIME_W) or wr_hit_s(MTIME_W + 1);

    tick_proc: process(mtime_wr, mtime_next)
    begin
        hw_we_s    <= (others => (others => '0'));
        hw_wdata_s <= (others => (others => '0'));
        hw_wdata_s(MTIME_W)     <= mtime_next(31 downto 0);
        hw_wdata_s(MTIME_W + 1) <= mtime_next(63 downto 32);
        if mtime_wr = '0' then
            hw_we_s(MTIME_W)     <= (others => '1');
            hw_we_s(MTIME_W + 1) <= (others => '1');
        end if;
    end process;

    -- ---- Registered 64-bit timer compares driving the mtip levels ----
    cmp_proc: process(clk, resetn)
    begin
        if resetn = '0' then
            mtip_reg <= (others => '0');
        elsif rising_edge(clk) then
            for h in 0 to NHARTS-1 loop
                if mtime >= (regs_q(CMP_W + 2*h + 1) & regs_q(CMP_W + 2*h)) then
                    mtip_reg(h) <= '1';
                else
                    mtip_reg(h) <= '0';
                end if;
            end loop;
        end if;
    end process;

    -- ---- The register file: the word decode, the byte-lane merge and the
    -- registered read, from the tables clint_regs_pkg builds out of the layout.
    -- The mtime and mtimecmp word offsets are MTIME_W and CMP_W, this file's own
    -- layout constants and the .rdl's parameters: they are a function of NHARTS,
    -- so the package cannot carry a <REG>_WORD constant for them and does not.
    -- mtimecmp resets all-ones so mtip starts low; that is the RSTVAL row, not a
    -- reset branch here.
    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NW,
            RSTVAL      => RSTVAL(NHARTS, MTIME_W, CMP_W),
            IMPL        => IMPL(NHARTS, MTIME_W, CMP_W),
            W1C         => W1C(NHARTS, MTIME_W, CMP_W),
            WOSET       => WOSET(NHARTS, MTIME_W, CMP_W),
            WOT         => WOT(NHARTS, MTIME_W, CMP_W),
            PULSE       => PULSE(NHARTS, MTIME_W, CMP_W),
            RCLR        => RCLR(NHARTS, MTIME_W, CMP_W),
            HWOWN       => HWOWN(NHARTS, MTIME_W, CMP_W))
        port map (
            ClkMem      => clk,
            resetn      => resetn,
            EnMemPeriph => en_n,
            WEn         => wen_n,
            MABPart     => mab,
            wdata       => wdata,
            rdata_out   => rdata,
            regs        => regs_q,
            hw_we       => hw_we_s,
            hw_wdata    => hw_wdata_s,
            acc_hit     => open,
            rd_hit      => open,
            wr_hit      => wr_hit_s,
            rd_strobe   => open,
            wr_strobe   => open,
            wr_pulse    => open,
            w1c_hit     => open,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

end architecture;
