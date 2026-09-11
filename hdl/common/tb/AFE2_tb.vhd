/* -----------------------------------------------------------------------------
   AFE2_tb.vhd: self-checking bench for hdl/common/periph/AFE2.vhd, two sites on one 40 MHz mclk.
   The converter is a behavioural model of the anatop_pixel_adc protocol, from SIM_STATUS 2.4 and the firmware contract section 4: one bit trial per falling edge of SARADC_clk, twelve falling edges per conversion (clear, sample, ten trials), READY raised right after the twelfth and held 100 ns, the raw bus valid only inside READY with bit 9 inverted (all ones outside it), and a 2 us quiet after reset release.
   Checks: reset state, register read/write and the ctl bit map, the ownership gate, single conversion (12 falling edges, 50 ns period, code, tag), continuous mode and the FIFO, overflow, both interrupts, the simultaneous trigger across two sites, the READY timeout, the swap engine, CLKDIV, and EN = 0 abort.
   Verdict: the periph_tb_pkg scoreboard banner, ALL CHECKS PASSED.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.periph_tb_pkg.all;

entity AFE2_tb is
end entity;

architecture sim of AFE2_tb is

    constant T_MCLK : time := 25 ns;     -- 40 MHz
    constant NSITE  : natural := 2;

    type slv32_arr is array(natural range <>) of std_logic_vector(31 downto 0);
    type slv50_arr is array(natural range <>) of std_logic_vector(49 downto 0);
    type slv10_arr is array(natural range <>) of std_logic_vector(9 downto 0);
    type slv6_arr  is array(natural range <>) of std_logic_vector(5 downto 0);
    type slv4_arr  is array(natural range <>) of std_logic_vector(3 downto 0);
    type sl_arr    is array(natural range <>) of std_logic;
    type int_arr   is array(natural range <>) of integer;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    -- Bus, one set per site (the arbiter presents one master index to every slave).
    signal en     : sl_arr(0 to NSITE-1) := (others => '0');
    signal we     : slv4_arr(0 to NSITE-1) := (others => (others => '0'));
    signal addr   : slv6_arr(0 to NSITE-1) := (others => (others => '0'));
    signal wdata  : slv32_arr(0 to NSITE-1) := (others => (others => '0'));
    signal rdata  : slv32_arr(0 to NSITE-1);
    signal master : std_logic_vector(2 downto 0) := "000";

    signal irq      : sl_arr(0 to NSITE-1);
    signal trig_out : sl_arr(0 to NSITE-1);
    signal trig_in  : std_logic;
    signal ctl      : slv50_arr(0 to NSITE-1);
    signal sar_clk  : sl_arr(0 to NSITE-1);
    signal sar_rst  : sl_arr(0 to NSITE-1);
    signal sar_rdy  : sl_arr(0 to NSITE-1) := (others => '0');
    signal sar_d    : slv10_arr(0 to NSITE-1) := (others => (others => '1'));

    -- Model controls.
    signal vin       : int_arr(0 to NSITE-1) := (0 => 351, 1 => 666);   -- the code the converter returns
    signal rdy_mask  : sl_arr(0 to NSITE-1) := (others => '1');          -- '0' suppresses READY (timeout test)
    signal fe_count  : int_arr(0 to NSITE-1) := (others => 0);           -- falling edges since reset release
    signal ap_count  : int_arr(0 to NSITE-1) := (others => 0);           -- apertures (sample falling edges)

    shared variable sb : scoreboard;

    constant W_CR : natural := 0;  constant W_SR : natural := 1;  constant W_DATA : natural := 2;
    constant W_TIA : natural := 3; constant W_DACVP : natural := 4; constant W_DACVCM : natural := 5;
    constant W_BIAS : natural := 6; constant W_MUX : natural := 7; constant W_SWAP : natural := 8;

    procedure wr(signal c : in std_logic; signal e : out std_logic; signal w : out std_logic_vector(3 downto 0);
                 signal a : out std_logic_vector(5 downto 0); signal d : out std_logic_vector(31 downto 0);
                 slot : natural; data : std_logic_vector(31 downto 0)) is
    begin
        wait until c = '0';
        e <= '1'; w <= "1111"; a <= std_logic_vector(to_unsigned(slot, 6)); d <= data;
        wait until c = '1';
        wait until c = '0';
        e <= '0'; w <= "0000";
    end procedure;

    procedure rd(signal c : in std_logic; signal e : out std_logic; signal w : out std_logic_vector(3 downto 0);
                 signal a : out std_logic_vector(5 downto 0); signal q : in std_logic_vector(31 downto 0);
                 slot : natural; data : out std_logic_vector(31 downto 0)) is
    begin
        wait until c = '0';
        e <= '1'; w <= "0000"; a <= std_logic_vector(to_unsigned(slot, 6));
        wait until c = '1';
        wait until c = '0';
        e <= '0';
        data := q;
    end procedure;

    function u32(v : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, 32));
    end function;

begin

    clk <= not clk after T_MCLK / 2;
    trig_in <= trig_out(0) or trig_out(1);

    g_dut : for h in 0 to NSITE-1 generate
        dut : entity work.AFE2
            generic map (SITE => h, OWNER_HART => h + 1, MGMT_HART => 0, QUIET_CYCLES => 128)
            port map (
                clk => clk, resetn => resetn,
                en => en(h), we => we(h), addr => addr(h), wdata => wdata(h), master => master, rdata => rdata(h),
                irq => irq(h), trig_out => trig_out(h), trig_in => trig_in,
                ctl => ctl(h), sar_clk => sar_clk(h), sar_rst => sar_rst(h), sar_rdy => sar_rdy(h), sar_d => sar_d(h));

        -- Converter model: one trial per falling edge, READY after the twelfth, bus valid only inside READY.
        model : process
            variable n     : integer := 0;
            variable code  : integer := 0;
            variable t_rel : time := 0 ns;
        begin
            sar_rdy(h) <= '0';
            sar_d(h)   <= (others => '1');
            wait until sar_rst(h) = '0';
            t_rel := now;
            n := 0;
            loop
                wait until falling_edge(sar_clk(h)) or sar_rst(h) = '1';
                if sar_rst(h) = '1' then
                    exit;
                end if;
                assert now - t_rel >= 2 us
                    report "model: trigger clock before 2 us of quiet after reset release" severity error;
                fe_count(h) <= fe_count(h) + 1;
                n := n + 1;
                if n = 2 then
                    code := vin(h);                       -- aperture: the input is sampled at the sample falling edge
                    ap_count(h) <= ap_count(h) + 1;
                elsif n = 12 then
                    n := 0;
                    if rdy_mask(h) = '1' then
                        wait for 1 ns;
                        sar_d(h)   <= std_logic_vector(to_unsigned(code, 10) xor "1000000000");
                        sar_rdy(h) <= '1';
                        wait for 100 ns;
                        sar_rdy(h) <= '0';
                        sar_d(h)   <= (others => '1');
                    end if;
                end if;
            end loop;
        end process;
    end generate;

    stim : process
        variable d, d2 : std_logic_vector(31 downto 0);
        variable fe0, fe1 : integer;
        variable t0, t1, t2 : time;
        variable k : integer;
        variable vpx : std_logic_vector(11 downto 0);
    begin
        master <= "000";
        wait for 100 ns;
        resetn <= '1';
        wait for 100 ns;

        -- 1. Reset state.
        sb.check_bit("reset: SARADC_rst = 1 on site 0", sar_rst(0), '1');
        sb.check_bit("reset: SARADC_rst = 1 on site 1", sar_rst(1), '1');
        sb.check_bit("reset: SARADC_clk low", sar_clk(0), '0');
        -- ATP_SEL (ctl 3:0) resets to 0xF: parks the site off the shared test pads.
        sb.check_slv("reset: ctl zero except ATP_SEL = 0xF", ctl(0), (49 downto 4 => '0') & x"F");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_MUX, d);
        sb.check_slv("reset: MUX = 0xF0 (ATPSEL parked)", d, x"000000F0");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_CR, d);
        sb.check_slv("reset: CR = 0x700 (SAMPLESTEP 7)", d, x"00000700");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("reset: SR = 0", d, x"00000000");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_slv("reset: DATA = 0 (empty, VALID clear)", d, x"00000000");
        sb.check_bit("reset: irq low", irq(0), '0');

        -- 2. Register read/write and the ctl bit map.
        wr(clk, en(0), we(0), addr(0), wdata(0), W_TIA,    x"FFFFFFFF");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_DACVP,  x"00001ABC");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_DACVCM, x"00000801");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_BIAS,   x"00000025");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_MUX,    x"000000A5");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SWAP,   x"0003F123");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_TIA, d);
        sb.check_slv("TIA readback masked to 10 bits", d, x"000003FF");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DACVP, d);
        sb.check_slv("DACVP readback", d, x"00001ABC");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DACVCM, d);
        sb.check_slv("DACVCM readback", d, x"00000801");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_BIAS, d);
        sb.check_slv("BIAS readback", d, x"00000025");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_MUX, d);
        sb.check_slv("MUX readback", d, x"000000A5");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SWAP, d);
        sb.check_slv("SWAP readback masked", d, x"00030123");
        rd(clk, en(0), we(0), addr(0), rdata(0), 9, d);
        sb.check_slv("word 9 reads 0", d, x"00000000");
        rd(clk, en(0), we(0), addr(0), rdata(0), 63, d);
        sb.check_slv("word 63 reads 0", d, x"00000000");
        sb.check_slv("ctl ResEn = TIA[5:0]",      ctl(0)(49 downto 44), "111111");
        sb.check_slv("ctl ThEn = TIA[9:6]",       ctl(0)(43 downto 40), "1111");
        sb.check_slv("ctl A_Dac_Vp = DACVP[11:0]", ctl(0)(39 downto 28), x"ABC");
        sb.check_bit("ctl En_Dac_Vp = DACVP[12]",  ctl(0)(27), '1');
        sb.check_slv("ctl A_Dac_Vcm = DACVCM[11:0]", ctl(0)(26 downto 15), x"801");
        sb.check_bit("ctl En_Dac_Vcm = DACVCM[12]", ctl(0)(14), '0');
        sb.check_slv("ctl Bias_Adj = BIAS[5:0]",  ctl(0)(13 downto 8), "100101");
        sb.check_slv("ctl SARADC_SEL = MUX[3:0]", ctl(0)(7 downto 4), x"5");
        sb.check_slv("ctl ATP_SEL = MUX[7:4]",    ctl(0)(3 downto 0), x"A");
        -- Byte lane 1 alone.
        wait until clk = '0';
        en(0) <= '1'; we(0) <= "0010"; addr(0) <= std_logic_vector(to_unsigned(W_DACVP, 6)); wdata(0) <= x"00000000";
        wait until clk = '1'; wait until clk = '0'; en(0) <= '0'; we(0) <= "0000";
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DACVP, d);
        sb.check_slv("lane-1 write leaves lane 0", d, x"000000BC");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_DACVP, x"00001ABC");

        -- 3. Ownership gate: hart 2 is not site 0's owner (hart 1) nor the management hart.
        master <= "010";
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DACVP, d);
        sb.check_slv("denied read returns 0", d, x"00000000");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_DACVP, x"00000000");
        master <= "001";
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DACVP, d);
        sb.check_slv("denied write dropped; owner hart 1 reads", d, x"00001ABC");
        master <= "000";

        -- 4. Single conversion on site 0.
        wr(clk, en(0), we(0), addr(0), wdata(0), W_MUX, x"00000002");        -- SARADC_SEL = 2 for the tag
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000701");         -- EN
        wait for 2 * T_MCLK;                                                  -- sar_rst is registered behind CR
        sb.check_bit("EN releases SARADC_rst", sar_rst(0), '0');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000705");         -- START too early: ignored
        wait for 500 ns;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("start before REL ignored (SR = 0)", d, x"00000000");
        wait for 3 us;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("REL set after the quiet period", d, x"00000008");
        fe0 := fe_count(0);
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000705");         -- START
        wait until sar_clk(0) = '1';
        t0 := now;
        wait until sar_clk(0) = '0';
        sb.check_true("clear pulse is one 50 ns tick at CLKDIV = 0", (now - t0) = 50 ns);
        wait until sar_clk(0) = '1';
        sb.check_true("sample pulse starts one tick after clear", (now - t0) = 100 ns);
        t0 := now;
        wait until sar_clk(0) = '0';
        sb.check_true("sample pulse is 1 + SAMPLESTEP = 8 ticks", (now - t0) = 400 ns);
        t0 := now;
        wait until sar_clk(0) = '1';
        sb.check_true("first conversion pulse one tick after the aperture", (now - t0) = 50 ns);
        t0 := now;
        wait until sar_clk(0) = '0';
        wait until sar_clk(0) = '1';
        sb.check_true("conversion pulse period 50 ns", (now - t0) = 50 ns);
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("BUSY during the conversion", d(0), '1');
        wait until irq(0) = '1' for 5 us;
        sb.check_bit("irq low without DRDYIE", irq(0), '0');
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("single: DRDY set, BUSY clear, CNT = 1, REL", d, x"0000010A");
        sb.check_true("single: 12 falling edges per conversion", fe_count(0) - fe0 = 12);
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_slv("single: DATA = VALID + SEL 2 + code 351", d, x"0000895F");
        sb.check_slv("single: code field = 351 (bit 9 corrected)", d(9 downto 0), std_logic_vector(to_unsigned(351, 10)));
        sb.check_slv("single: SEL tag = 2", d(13 downto 10), x"2");
        sb.check_bit("single: VALID", d(15), '1');
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d2);
        sb.check_slv("DATA read has no side effect", d2, d);
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");         -- pop
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("pop clears DRDY, CNT = 0", d, x"00000008");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_slv("DATA empty after pop", d, x"00000000");

        -- 5. Continuous mode, FIFO, DRDY interrupt.
        vin(0) <= 100;
        fe0 := fe_count(0);
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000727");         -- EN CONT START DRDYIE
        wait until irq(0) = '1' for 5 us;
        sb.check_bit("cont: irq on first result", irq(0), '1');
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_slv("cont: first code 100", d(9 downto 0), std_logic_vector(to_unsigned(100, 10)));
        vin(0) <= 200;
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        sb.check_bit("cont: irq drops when the FIFO empties", irq(0), '0');
        wait for 2.5 us;                                                      -- two more conversions land
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_true("cont: CNT = 2 after two unread conversions", d(11 downto 8) = x"2");
        sb.check_bit("cont: BUSY in continuous mode", d(0), '1');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000721");         -- CONT off: finish the current pattern
        wait for 2 us;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("cont: BUSY clear after CONT cleared", d(0), '0');
        k := to_integer(unsigned(d(11 downto 8)));
        sb.check_true("cont: 2..4 results queued", k >= 2 and k <= 4);
        sb.check_true("cont: 12 falling edges per conversion sustained", (fe_count(0) - fe0) mod 12 = 0);
        for i in 1 to k loop
            rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
            sb.check_bit("cont: queued entry valid", d(15), '1');
            wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        end loop;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("cont: FIFO drained", d, x"00000008");

        -- 6. Overflow and the error interrupt.
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000747");         -- EN CONT START ERRIE
        wait for 7 us;                                                        -- > 5 conversions, nothing popped
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("ovf: OVF set on capture into a full FIFO", d(2), '1');
        sb.check_true("ovf: CNT = 4", d(11 downto 8) = x"4");
        sb.check_bit("ovf: irq via ERRIE", irq(0), '1');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000741");         -- CONT off
        wait for 2 us;
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000004");         -- W1C OVF
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("ovf: W1C clears OVF", d(2), '0');
        sb.check_bit("ovf: irq drops", irq(0), '0');
        for i in 1 to 4 loop
            wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        end loop;
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");         -- pop on empty: no effect
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("ovf: drained, pop on empty harmless", d, x"00000008");

        -- 7. Simultaneous trigger across two sites: hart 0 writes SYNC on site 0, both have SYNCEN.
        wr(clk, en(1), we(1), addr(1), wdata(1), W_CR, x"00000711");         -- site 1: EN SYNCEN
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000711");         -- site 0: EN SYNCEN
        wait for 4 us;                                                        -- site 1's quiet period
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000719");         -- SYNC
        wait until sar_clk(0) = '1' or sar_clk(1) = '1' for 1 us;
        t1 := now;
        sb.check_true("sync: both trigger clocks rise on the same edge",
            sar_clk(0) = '1' and sar_clk(1) = '1');
        wait for 3 us;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        rd(clk, en(1), we(1), addr(1), rdata(1), W_SR, d2);
        sb.check_bit("sync: site 0 has a result", d(1), '1');
        sb.check_bit("sync: site 1 has a result", d2(1), '1');
        rd(clk, en(1), we(1), addr(1), rdata(1), W_DATA, d2);
        sb.check_slv("sync: site 1 code 666", d2(9 downto 0), std_logic_vector(to_unsigned(666, 10)));
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        wr(clk, en(1), we(1), addr(1), wdata(1), W_SR, x"00000002");
        -- A site without SYNCEN ignores the trigger.
        wr(clk, en(1), we(1), addr(1), wdata(1), W_CR, x"00000701");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000719");
        wait for 3 us;
        rd(clk, en(1), we(1), addr(1), rdata(1), W_SR, d2);
        sb.check_slv("sync: site 1 without SYNCEN idle", d2, x"00000008");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");

        -- 8. READY timeout.
        rdy_mask(0) <= '0';
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000745");         -- EN START ERRIE
        wait for 60 us;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("timeout: TO set with READY absent", d(4), '1');
        sb.check_bit("timeout: no DRDY", d(1), '0');
        sb.check_bit("timeout: irq via ERRIE", irq(0), '1');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000010");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_slv("timeout: W1C clears TO", d, x"00000008");
        rdy_mask(0) <= '1';

        -- 9. Swap engine: PERIOD = 1 -> A_Dac_Vp alternates every two conversions; the tag records the phase.
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SWAP, x"00010123");       -- VP2 = 0x123, PERIOD = 1
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000783");         -- EN CONT SWAPEN (+ START below)
        sb.check_slv("swap: idle phase drives DACVP.VP", ctl(0)(39 downto 28), x"ABC");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000787");         -- START
        wait for 6 us;                                                        -- ~5 conversions
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000781");         -- CONT off
        wait for 2 us;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        k := to_integer(unsigned(d(11 downto 8)));
        sb.check_true("swap: results queued", k >= 4);
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_bit("swap: conversion 0 tagged phase 0", d(14), '0');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_bit("swap: conversion 1 tagged phase 0", d(14), '0');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_bit("swap: conversion 2 tagged phase 1", d(14), '1');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        rd(clk, en(0), we(0), addr(0), rdata(0), W_DATA, d);
        sb.check_bit("swap: conversion 3 tagged phase 1", d(14), '1');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000701");         -- SWAPEN off
        wait for 100 ns;
        sb.check_slv("swap: SWAPEN off restores DACVP.VP", ctl(0)(39 downto 28), x"ABC");
        for i in 1 to 4 loop
            wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");
        end loop;

        -- 10. CLKDIV = 1: 100 ns trigger period, still 12 falling edges.
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00001701");         -- CLKDIV 1
        fe0 := fe_count(0);
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00001705");         -- START
        wait until sar_clk(0) = '1';
        t0 := now;
        wait until sar_clk(0) = '0';
        sb.check_true("CLKDIV = 1: clear pulse 100 ns", (now - t0) = 100 ns);
        wait until sar_clk(0) = '1';                                          -- sample
        wait until sar_clk(0) = '0';
        wait until sar_clk(0) = '1';                                          -- first conversion pulse
        t0 := now;
        wait until sar_clk(0) = '0';
        wait until sar_clk(0) = '1';
        sb.check_true("CLKDIV = 1: conversion pulse period 100 ns", (now - t0) = 100 ns);
        wait for 5 us;
        sb.check_true("CLKDIV = 1: 12 falling edges", fe_count(0) - fe0 = 12);
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("CLKDIV = 1: result", d(1), '1');
        wr(clk, en(0), we(0), addr(0), wdata(0), W_SR, x"00000002");

        -- 11. EN = 0 aborts: SARADC_rst back to 1, BUSY clear, REL clear.
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000707");         -- EN CONT START
        wait for 2 us;
        wr(clk, en(0), we(0), addr(0), wdata(0), W_CR, x"00000700");         -- EN off
        wait for 100 ns;
        sb.check_bit("EN = 0: SARADC_rst = 1", sar_rst(0), '1');
        sb.check_bit("EN = 0: SARADC_clk low", sar_clk(0), '0');
        wait for 2 us;
        rd(clk, en(0), we(0), addr(0), rdata(0), W_SR, d);
        sb.check_bit("EN = 0: BUSY clear", d(0), '0');
        sb.check_bit("EN = 0: REL clear", d(3), '0');

        sb.report_summary("AFE2_TB");
        wait;
    end process;

end architecture;
