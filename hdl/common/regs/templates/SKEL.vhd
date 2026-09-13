-- VestaRV: skeleton peripheral
-- The smallest block on the house register bus: one periph_regs instance carrying
-- skel_regs_pkg's tables, and a datapath that is one counter. GO arrives on wr_pulse, DONE is
-- a flop this file owns and clears on w1c_hit, BUSY is a live level read back through hw_rd.
-- clk_mem must free-run for a block that consumes wr_pulse with STROBE_HOLD false; where
-- clk_mem is gated by en_mem the hooks are acc_hit / wr_hit instead (hdl/common/regs/REGFILE.md).

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.Constants.all;
use work.skel_regs_pkg.all;

entity SKEL is
    port (
        clk_mem     : in  std_logic;                      -- register-bus clock
        resetn      : in  std_logic;                      -- asynchronous, active low
        en_mem      : in  std_logic;                      -- select, active low
        wen         : in  std_logic_vector(3 downto 0);   -- byte lanes, active low
        addr_periph : in  std_logic_vector(7 downto 2);   -- word slot
        write_data  : in  std_logic_vector(31 downto 0);
        read_data   : out std_logic_vector(31 downto 0);
        irq         : out std_logic                       -- DONE, unmasked
    );
end SKEL;

architecture rtl of SKEL is

    constant PASS_CYCLES : natural := 4;   -- clk_mem edges one pass takes

    signal regs_q  : reg_arr_t;   -- the stored words: SKELxCR.EN and SKELxDR
    signal hw_rd_s : reg_arr_t;   -- read source for the bits this block owns
    signal pulse_s : reg_arr_t;   -- PULSE bits written 1
    signal w1c_s   : reg_arr_t;   -- W1C bits written 1
    signal en_s    : std_logic;
    signal go_s    : std_logic;
    signal busy_q  : std_logic;
    signal done_q  : std_logic;
    signal cnt     : natural range 0 to PASS_CYCLES;

begin

    en_s <= regs_q(SLOT_CR)(EN_LSB);
    go_s <= pulse_s(SLOT_CR)(GO_LSB);

    -- Neither SKELxSR bit is stored in periph_regs, so both are read through hw_rd.
    hw_rd_s <= (SLOT_SR => (DONE_LSB => done_q, BUSY_LSB => busy_q, others => '0'),
                others  => (others => '0'));

    -- One pass per GO. The software clear is applied before the hardware set, so a
    -- completion coincident with a write-1-to-clear still leaves DONE set.
    pass_proc: process(clk_mem, resetn)
    begin
        if resetn = '0' then
            busy_q <= '0';
            done_q <= '0';
            cnt    <= 0;
        elsif rising_edge(clk_mem) then
            if w1c_s(SLOT_SR)(DONE_LSB) = '1' then
                done_q <= '0';
            end if;
            if go_s = '1' and en_s = '1' then
                busy_q <= '1';
                cnt    <= PASS_CYCLES;
            elsif busy_q = '1' then
                if cnt = 0 then
                    busy_q <= '0';
                    done_q <= '1';
                else
                    cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;

    irq <= done_q;

    u_regs: entity work.periph_regs
        generic map (
            NWORDS => NWORDS, RSTVAL => RSTVAL, IMPL => IMPL, W1C => W1C,
            WOSET => WOSET, WOT => WOT, PULSE => PULSE, RCLR => RCLR, HWOWN => HWOWN)
        port map (
            ClkMem      => clk_mem,
            resetn      => resetn,
            EnMemPeriph => en_mem,
            WEn         => wen,
            MABPart     => addr_periph,
            wdata       => write_data,
            rdata_out   => read_data,
            regs        => regs_q,
            hw_rd       => hw_rd_s,
            -- Every other hook (acc_hit, rd_hit/wr_hit, the registered strobes,
            -- woset_hit, wot_hit, rd_clr) is an unassociated output: this block
            -- needs none of them. REGFILE.md's "Which hook" table says which to take.
            wr_pulse    => pulse_s,
            w1c_hit     => w1c_s);

end rtl;
