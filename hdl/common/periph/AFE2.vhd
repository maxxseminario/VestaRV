-- VestaRV: AFE site controller
-- Register file for the 50 anatop_pixel control bits and the SAR conversion sequencer; one instance per site at 0x6C00 + 0x100*site.
-- Native arbiter slave (afe_stub shape), single mclk domain, s_master gated to OWNER_HART or MGMT_HART: a denied read returns 0, a denied write is dropped. Reads never mutate state; the result FIFO pops on a write-1 to SR.DRDY.
-- Converter: f_sar = f_mclk / (2*(CLKDIV+1)), one conversion 16 + SAMPLESTEP ticks. Above 20 MHz is uncharacterised, and the capture timing assumes the macro holds its data bus for at least 2 mclk after READY.
-- Sites sharing CLKDIV sample together: CR.SYNC pulses trig_out, MCU.vhd ORs the four trig_out lines into every trig_in, and CR.SYNCEN starts on it.
-- ctl is 1.0 V CMOS; the 1.0 V to 2.5 V level shifters live inside anatop_quad.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Word offsets, field ranges, implemented-bit and reset tables: generated from
-- hdl/common/regs/rdl/afe2.rdl; analyse afe2_regs_pkg.vhd before this file.
use work.afe2_regs_pkg.all;

entity AFE2 is
    generic (
        SITE         : natural := 0;     -- site index 0..3 (documentation and assertions only)
        OWNER_HART   : natural := 0;     -- hart that, with MGMT_HART, may access this site
        MGMT_HART    : natural := 0;     -- the management hart
        QUIET_CYCLES : natural := 128    -- mclk cycles between SARADC_rst release and the first accepted start
    );
    port (
        clk      : in  std_logic;                        -- free-running mclk
        resetn   : in  std_logic;

        -- Native arbiter slave port.
        en       : in  std_logic;
        we       : in  std_logic_vector(3 downto 0);
        addr     : in  std_logic_vector(5 downto 0);     -- word offset within the 256 B sub-slot
        wdata    : in  std_logic_vector(31 downto 0);
        master   : in  std_logic_vector;                 -- arbiter s_master, unconstrained
        rdata    : out std_logic_vector(31 downto 0);    -- registered: address at T, data at T+1

        irq      : out std_logic;                        -- level: (DRDY and DRDYIE) or ((OVF or TO) and ERRIE)

        -- Simultaneous-sample trigger, shared across the four sites.
        trig_out : out std_logic;                        -- one-mclk pulse on a CR.SYNC write
        trig_in  : in  std_logic;                        -- OR of every site's trig_out

        -- Analog macro, 1.0 V CMOS.
        ctl      : out std_logic_vector(49 downto 0);
        sar_clk  : out std_logic;
        sar_rst  : out std_logic;                        -- active high, reset value 1
        sar_rdy  : in  std_logic;
        sar_d    : in  std_logic_vector(9 downto 0)
    );
end entity;

architecture rtl of AFE2 is

    -- IMPL is the implemented-bit mask per stored word; unimplemented bits hold no
    -- flop and read 0. CR.START and CR.SYNC are pulses, so AFExCR_IMPL clears them
    -- and AFExCR_SINGLEPULSE names them. RSTVAL carries MUX.ATPSEL = 0xF because
    -- the anatop_quad ATP grant is NOT(AND4(ATP_SEL)): 0xF parks every site off
    -- the shared test pads at reset.

    signal regs      : reg_arr_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

    -- CR fields.
    signal cr_en, cr_cont, cr_syncen, cr_drdyie, cr_errie, cr_swapen : std_logic;
    signal samplestep : unsigned(3 downto 0);
    signal clkdiv     : unsigned(3 downto 0);
    signal start_w   : std_logic;                        -- one-cycle strobe from a CR START write

    -- Release and sequencer.
    signal quiet_cnt : unsigned(7 downto 0);
    signal rel       : std_logic;
    signal run       : std_logic;
    signal hcnt      : unsigned(3 downto 0);             -- mclk cycles into the current half tick
    signal half      : std_logic;                        -- '0' first half of the tick, '1' second half
    signal t         : unsigned(4 downto 0);             -- tick index 0 .. 15+SAMPLESTEP
    signal sar_clk_r : std_logic;
    signal sar_rst_r : std_logic;
    signal trig_r    : std_logic;

    -- Capture and timeout.
    signal rdy_q1, rdy_q2 : std_logic;
    signal pending   : std_logic;
    signal sel_ap    : std_logic_vector(3 downto 0);
    signal ph_ap     : std_logic;
    signal to_cnt    : unsigned(10 downto 0);            -- READY timeout: 2048 mclk after the aperture, longer than two conversions at any CLKDIV/SAMPLESTEP
    signal ovf_f, to_f : std_logic;

    -- Result FIFO, four entries: code(9:0), sel(13:10), phase(14).
    constant FIFO_DEPTH : natural := 4;
    type fifo_t is array(0 to FIFO_DEPTH-1) of std_logic_vector(14 downto 0);
    signal fifo   : fifo_t;
    signal wp, rp : unsigned(1 downto 0);
    signal count  : unsigned(3 downto 0);

    -- Swap engine.
    signal swap_cnt   : unsigned(15 downto 0);
    signal swap_phase : std_logic;

    signal vp_eff : std_logic_vector(11 downto 0);
    signal nonempty : std_logic;

    function tick_level(tt : unsigned(4 downto 0); hh : std_logic; ss : unsigned(3 downto 0)) return std_logic is
        variable ti : integer := to_integer(tt);
        variable si : integer := to_integer(ss);
    begin
        if ti = 1 then return '1'; end if;                            -- clear
        if ti >= 3 and ti <= 3 + si then return '1'; end if;          -- sample; its falling edge is the aperture
        if ti >= 5 + si and ti <= 14 + si then return not hh; end if; -- ten conversion pulses after one low tick
        return '0';
    end function;

begin

    rdata    <= rdata_reg;
    sar_clk  <= sar_clk_r;
    sar_rst  <= sar_rst_r;
    trig_out <= trig_r;

    cr_en      <= regs(W_CR)(AFEEN_LSB);
    cr_cont    <= regs(W_CR)(AFECONT_LSB);
    cr_syncen  <= regs(W_CR)(AFESYNCEN_LSB);
    cr_drdyie  <= regs(W_CR)(AFEDRDYIE_LSB);
    cr_errie   <= regs(W_CR)(AFEERRIE_LSB);
    cr_swapen  <= regs(W_CR)(AFESWAPEN_LSB);
    samplestep <= unsigned(regs(W_CR)(AFESAMPLESTEP_MSB downto AFESAMPLESTEP_LSB));
    clkdiv     <= unsigned(regs(W_CR)(AFECLKDIV_MSB downto AFECLKDIV_LSB));

    nonempty <= '1' when count /= 0 else '0';
    irq <= (nonempty and cr_drdyie) or ((ovf_f or to_f) and cr_errie);

    -- Control bits, symbol order.
    vp_eff <= regs(W_SWAP)(AFEVP2_MSB downto AFEVP2_LSB) when (cr_swapen = '1' and swap_phase = '1')
              else regs(W_DACVP)(AFEVP_MSB downto AFEVP_LSB);
    ctl(49 downto 44) <= regs(W_TIA)(AFERESEN_MSB downto AFERESEN_LSB);
    ctl(43 downto 40) <= regs(W_TIA)(AFETHEN_MSB downto AFETHEN_LSB);
    ctl(39 downto 28) <= vp_eff;
    ctl(27)           <= regs(W_DACVP)(AFEVPEN_LSB);
    ctl(26 downto 15) <= regs(W_DACVCM)(AFEVCM_MSB downto AFEVCM_LSB);
    ctl(14)           <= regs(W_DACVCM)(AFEVCMEN_LSB);
    ctl(13 downto 8)  <= regs(W_BIAS)(AFEBIASADJ_MSB downto AFEBIASADJ_LSB);
    ctl(7 downto 4)   <= regs(W_MUX)(AFEADCSEL_MSB downto AFEADCSEL_LSB);
    ctl(3 downto 0)   <= regs(W_MUX)(AFEATPSEL_MSB downto AFEATPSEL_LSB);

    -- Register file: ownership gate, registered read, lane-merged writes, W1 strobes.
    bus_proc : process(clk, resetn)
        variable idx   : integer range 0 to 63;
        variable allow : boolean;
        variable head  : std_logic_vector(14 downto 0);
    begin
        if resetn = '0' then
            regs      <= RSTVAL;
            rdata_reg <= (others => '0');
            start_w   <= '0';
            trig_r    <= '0';
        elsif rising_edge(clk) then
            start_w <= '0';
            trig_r  <= '0';
            if en = '1' then
                allow := (to_integer(unsigned(master)) = OWNER_HART)
                         or (to_integer(unsigned(master)) = MGMT_HART);
                idx := to_integer(unsigned(addr));
                if allow then
                    -- Registered read of the pre-write value.
                    case idx is
                        when W_SR =>
                            rdata_reg <= (others => '0');
                            rdata_reg(AFEBUSY_LSB) <= run;
                            rdata_reg(AFEDRDY_LSB) <= nonempty;
                            rdata_reg(AFEOVF_LSB)  <= ovf_f;
                            rdata_reg(AFEREL_LSB)  <= rel;
                            rdata_reg(AFETO_LSB)   <= to_f;
                            rdata_reg(AFECNT_MSB downto AFECNT_LSB) <= std_logic_vector(count);
                        when W_DATA =>
                            head := fifo(to_integer(rp));
                            rdata_reg <= (others => '0');
                            if nonempty = '1' then
                                rdata_reg(AFEPHTAG_MSB downto AFECODE_LSB) <= head;
                                rdata_reg(AFEVALID_LSB) <= '1';
                            end if;
                        when others =>
                            if idx < NSTORED then
                                rdata_reg <= regs(idx);
                            else
                                rdata_reg <= (others => '0');
                            end if;
                    end case;
                    -- Writes.
                    if we /= "0000" and idx < NSTORED and idx /= W_SR and idx /= W_DATA then
                        for l in 0 to 3 loop
                            if we(l) = '1' then
                                regs(idx)(l*8+7 downto l*8) <= wdata(l*8+7 downto l*8) and IMPL(idx)(l*8+7 downto l*8);
                            end if;
                        end loop;
                        if idx = W_CR and we(0) = '1' then
                            start_w <= wdata(AFESTART_LSB);
                            trig_r  <= wdata(AFESYNC_LSB);
                        end if;
                    end if;
                else
                    rdata_reg <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- Sequencer, capture, FIFO and flags.
    seq_proc : process(clk, resetn)
        variable idx     : integer range 0 to 63;
        variable allow   : boolean;
        variable sr_wr   : boolean;
        variable tick_end : boolean;
        variable p_last  : unsigned(4 downto 0);
        variable start_ok : boolean;
    begin
        if resetn = '0' then
            quiet_cnt  <= (others => '0');
            rel        <= '0';
            run        <= '0';
            hcnt       <= (others => '0');
            half       <= '0';
            t          <= (others => '0');
            sar_clk_r  <= '0';
            sar_rst_r  <= '1';
            rdy_q1     <= '0';
            rdy_q2     <= '0';
            pending    <= '0';
            sel_ap     <= (others => '0');
            ph_ap      <= '0';
            to_cnt     <= (others => '0');
            ovf_f      <= '0';
            to_f       <= '0';
            fifo       <= (others => (others => '0'));
            wp         <= (others => '0');
            rp         <= (others => '0');
            count      <= (others => '0');
            swap_cnt   <= (others => '0');
            swap_phase <= '0';
        elsif rising_edge(clk) then
            -- SR write strobes (pop, W1C), under the same ownership gate as the register file.
            sr_wr := false;
            if en = '1' and we(0) = '1' then
                allow := (to_integer(unsigned(master)) = OWNER_HART)
                         or (to_integer(unsigned(master)) = MGMT_HART);
                idx := to_integer(unsigned(addr));
                sr_wr := allow and (idx = W_SR);
            end if;
            if sr_wr and wdata(AFEOVF_LSB) = '1' then ovf_f <= '0'; end if;
            if sr_wr and wdata(AFETO_LSB)  = '1' then to_f  <= '0'; end if;

            -- Release: SARADC_rst follows not EN; a start is accepted QUIET_CYCLES after release.
            sar_rst_r <= not cr_en;
            if cr_en = '0' then
                quiet_cnt <= (others => '0');
                rel       <= '0';
                run       <= '0';
                t         <= (others => '0');
                hcnt      <= (others => '0');
                half      <= '0';
                pending   <= '0';
                swap_phase <= '0';
                swap_cnt  <= (others => '0');
            elsif rel = '0' then
                if quiet_cnt = QUIET_CYCLES - 1 then
                    rel <= '1';
                else
                    quiet_cnt <= quiet_cnt + 1;
                end if;
            end if;

            -- Start.
            start_ok := (cr_en = '1') and (rel = '1') and (run = '0');
            if start_ok and (start_w = '1' or (trig_in = '1' and cr_syncen = '1')) then
                run  <= '1';
                t    <= (others => '0');
                hcnt <= (others => '0');
                half <= '0';
                swap_cnt   <= (others => '0');
                swap_phase <= '0';
            end if;

            -- Tick generator.
            tick_end := false;
            p_last := to_unsigned(15, 5) + resize(samplestep, 5);
            if run = '1' then
                if hcnt = clkdiv then
                    hcnt <= (others => '0');
                    half <= not half;
                    if half = '1' then
                        tick_end := true;
                        if t = p_last then
                            t <= (others => '0');
                            if cr_cont = '0' then
                                run <= '0';
                            end if;
                            -- Swap engine: a conversion boundary.
                            if cr_swapen = '1' and cr_cont = '1' then
                                if swap_cnt = unsigned(regs(W_SWAP)(31 downto 16)) then
                                    swap_cnt   <= (others => '0');
                                    swap_phase <= not swap_phase;
                                else
                                    swap_cnt <= swap_cnt + 1;
                                end if;
                            end if;
                        else
                            t <= t + 1;
                        end if;
                    end if;
                else
                    hcnt <= hcnt + 1;
                end if;
                sar_clk_r <= tick_level(t, half, samplestep);
            else
                sar_clk_r <= '0';
            end if;

            -- Aperture: the falling edge of the sample pulse. Tag the conversion; a still-pending one was missed.
            if tick_end and t = to_unsigned(3, 5) + resize(samplestep, 5) then
                if pending = '1' then
                    to_f <= '1';
                end if;
                pending <= '1';
                sel_ap  <= regs(W_MUX)(3 downto 0);
                ph_ap   <= swap_phase;
                to_cnt  <= (others => '0');
            elsif pending = '1' then
                -- Timeout: 2048 mclk after the aperture (the slowest conversion, CLKDIV = SAMPLESTEP = 15, is 992 mclk).
                if to_cnt = 2047 then
                    pending <= '0';
                    to_f    <= '1';
                else
                    to_cnt <= to_cnt + 1;
                end if;
            end if;

            -- READY capture and FIFO.
            rdy_q1 <= sar_rdy;
            rdy_q2 <= rdy_q1;
            if rdy_q1 = '1' and rdy_q2 = '0' and pending = '1' then
                pending <= '0';
                if count = FIFO_DEPTH then
                    ovf_f <= '1';
                else
                    fifo(to_integer(wp)) <= ph_ap & sel_ap & (sar_d xor "1000000000");
                    wp <= wp + 1;
                    if not (sr_wr and wdata(1) = '1' and count /= 0) then
                        count <= count + 1;
                    end if;
                end if;
            elsif sr_wr and wdata(1) = '1' and count /= 0 then
                count <= count - 1;
            end if;
            if sr_wr and wdata(1) = '1' and count /= 0 then
                rp <= rp + 1;
            end if;
        end if;
    end process;

end architecture;
