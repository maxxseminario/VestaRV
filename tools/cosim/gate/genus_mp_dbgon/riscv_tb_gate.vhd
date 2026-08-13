
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;
use ieee.numeric_std.all;
library work;
use work.macros.all;  
use work.constants.all;
use work.MemoryMap.all;
use work.tb_defs.all;


entity riscv_tb is
    generic (
        -- M12: the tile-TCM preload (HART_RAM0_INIT) is retired — every hart
        -- boots from the shared ROM like silicon (the gate ROM macro holds the
        -- real M12 bootrom); tiles load through the bootrom's msip loader
        -- mailboxes. The only gate-flow deposit left is the shared-macro
        -- zero-init (make_ram_deposit.py).
        TEST_FILE : string(1 to 29) := "../rcf/xxxrv32ui-p-simple.rcf"
    );
end riscv_tb;

architecture behavioral of riscv_tb is
    component MCU
        port (
            
            -- Resetn Pad
            resetn_in	: in	std_logic;	-- '0' <= resetn, '1' <= system running
            resetn_out	: out	std_logic;	-- Don't care
            resetn_dir	: out	std_logic;	-- Must be set to input mode
            resetn_ren	: out	std_logic;	-- Set to enable pullup resistor

            --GPIO0 Connections (SPI0, CLKHFXT, CLKLFXT)
            prt1_in		    : in	std_logic_vector(7 downto 0);
            prt1_out		: out	std_logic_vector(7 downto 0);
            prt1_dir		: out	std_logic_vector(7 downto 0);
            prt1_ren		: out	std_logic_vector(7 downto 0);

            --GPIO1 Connections (SPI1, UART0, UART1)
            prt2_in		    : in	std_logic_vector(7 downto 0);
            prt2_out		: out	std_logic_vector(7 downto 0);
            prt2_dir		: out	std_logic_vector(7 downto 0);
            prt2_ren		: out	std_logic_vector(7 downto 0);

            --GPIO2 Connections (TIMER0, TIMER1)
            prt3_in		    : in	std_logic_vector(7 downto 0);
            prt3_out		: out	std_logic_vector(7 downto 0);
            prt3_dir		: out	std_logic_vector(7 downto 0);
            prt3_ren		: out	std_logic_vector(7 downto 0);

            --GPIO3 Connections (TBD)
            prt4_in		    : in	std_logic_vector(7 downto 0);
            prt4_out		: out	std_logic_vector(7 downto 0);
            prt4_dir		: out	std_logic_vector(7 downto 0);
            prt4_ren		: out	std_logic_vector(7 downto 0);

            --GPIO4 Connections (Mission B: QSPI + I3C alternate functions)
            prt5_in		    : in	std_logic_vector(7 downto 0);
            prt5_out		: out	std_logic_vector(7 downto 0);
            prt5_dir		: out	std_logic_vector(7 downto 0);
            prt5_ren		: out	std_logic_vector(7 downto 0);

            --GPIO5 Connections (Mission B: NFC digital-AFE alternate functions)
            prt6_in		    : in	std_logic_vector(7 downto 0);
            prt6_out		: out	std_logic_vector(7 downto 0);
            prt6_dir		: out	std_logic_vector(7 downto 0);
            prt6_ren		: out	std_logic_vector(7 downto 0);

            -- WOUND CONFIG (digperiphs Stage 2): the digital-only wound MCU
            -- entity has NO AFE/bias/DSADC/SARADC ports -- the whole analog
            -- port group of the legacy genus_mp tb component is DELETED here
            -- to match module MCU in genus/out/MCU_WOUND.genus.v.

            -- Test Port
            a0  : out std_logic_vector(31 downto 0);

            -- M3b: per-hart pass/fail observation (a0 of the 3 private-memory harts)
            a0_1 : out std_logic_vector(31 downto 0);
            a0_2 : out std_logic_vector(31 downto 0);
            a0_3 : out std_logic_vector(31 downto 0);

            -- =================================================================
            -- D5 DD16 GATE LEG -- THE DEBUG-ON PORT GROUP, AND WHY IT IS HERE.
            --
            -- This is the genus_mp_dbgon PRIVATE COPY of riscv_tb_gate.vhd.
            -- genus_mp/riscv_tb_gate.vhd is NOT touched by any of this: the
            -- debug-OFF netlist's module MCU ends at a0_3 and matches the
            -- component exactly, which is why the standing gate flow has never
            -- needed these lines.
            --
            -- d5_spec section 6 asked to prefer FORCING the Verilog top's
            -- unconnected JTAG nets over editing this file.  MEASURED FIRST,
            -- and the answer is that there is nothing to force:
            --
            --   xmelab: *E,CFEPLM: Foreign module port tck of mode in must be
            --   associated with port/signal of entity/component MCU
            --
            -- ...once per unassociated INPUT (tck, tms, tdi, trstn,
            -- dmi_req_valid, dmi_req_op, dmi_req_addr, dmi_req_data), and
            -- elaboration exits status 1.  Unassociated OUTPUTS are only a
            -- warning (*W,CUFEPC, for tdo and the four dmi_rsp_*), so the
            -- asymmetry is the whole story: a mixed-language VHDL component
            -- may leave a foreign module's outputs dangling and may NOT leave
            -- its inputs dangling.  The M7 question therefore never reaches
            -- the "can a force get there" stage -- there is no elaborated
            -- design to force into.
            --
            -- Declaring them here is strictly better than forcing would have
            -- been, and not merely a fallback: the five JTAG pins become
            -- ordinary VHDL std_logic signals at the testbench top, so
            -- dbg_tap.tcl drives them with the SAME 'x' literals it uses in
            -- the behavioural arm (TAP_PFX ":"), and the behavioural control
            -- and the gate leg differ in the DUT alone.
            --
            -- The raw DMI slave port is TIED IDLE below.  dbg_gateidc drives
            -- the TAP, and a second master on the DM would change what is
            -- being measured (the instruments' own warning about injecting DMI
            -- traffic beside a live session).
            -- =================================================================
            dmi_req_valid : in  std_logic;
            dmi_req_op    : in  std_logic_vector(1 downto 0);
            dmi_req_addr  : in  std_logic_vector(6 downto 0);
            dmi_req_data  : in  std_logic_vector(31 downto 0);
            dmi_req_ready : out std_logic;
            dmi_rsp_valid : out std_logic;
            dmi_rsp_data  : out std_logic_vector(31 downto 0);
            dmi_rsp_op    : out std_logic_vector(1 downto 0);

            tck   : in  std_logic;
            tms   : in  std_logic;
            tdi   : in  std_logic;
            tdo   : out std_logic;
            trstn : in  std_logic

        );
end component;

    -- D5 DD16: the five JTAG pins as testbench-top signals.  The NAMES are
    -- load-bearing: dbg_tap.tcl builds its paths as "${TAP_PFX}tck" and the
    -- runner sets TAP_PFX to ":", so these must be called exactly tck/tms/
    -- tdi/tdo/trstn at this level.  trstn starts at '0' (the TAP held in
    -- asynchronous reset) so the gate leg meets the same initial condition the
    -- behavioural arm meets, and tap_init is what releases it -- the
    -- dbg_gateidc.tcl:88-93 lesson, which cost its author a run and would
    -- otherwise cost this leg one too.
    signal tck   : std_logic := '0';
    signal tms   : std_logic := '1';
    signal tdi   : std_logic := '0';
    signal tdo   : std_logic;
    signal trstn : std_logic := '0';

    -- The raw DMI slave, tied idle (see the component comment).
    signal dmi_req_valid : std_logic := '0';
    signal dmi_req_op    : std_logic_vector(1 downto 0)  := "00";
    signal dmi_req_addr  : std_logic_vector(6 downto 0)  := (others => '0');
    signal dmi_req_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal dmi_req_ready : std_logic;
    signal dmi_rsp_valid : std_logic;
    signal dmi_rsp_data  : std_logic_vector(31 downto 0);
    signal dmi_rsp_op    : std_logic_vector(1 downto 0);


    -- Constants
    constant CLK_PERIOD : time := 40 ns;
    constant clk_hfxt_delay : time := (0.5 sec) / 24000000;	-- 24 MHz
    constant clk_lfxt_delay : time := (0.5 sec) / 32768;	-- 32.768 kHz
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;
    -- Watchdog: a test that never writes CAFEBABE/DEADBEEF to a0 (e.g. traps on an
    -- unimplemented instruction and spins) is failed when this fires. Longest known
    -- legit passing test is ~13.7 ms sim-time, so 100 ms gives ~7x headroom while
    -- failing tests give up ~100x sooner than the old 10 s value.
    constant SIMULATION_TIMEOUT : time := 100000 us;
    
    -- Test control addresses
    constant FAIL_LABEL : std_logic_vector(31 downto 0) := x"DEADBEEF"; -- fail label
    constant PASS_LABEL : std_logic_vector(31 downto 0) := x"CAFEBABE"; -- pass label

    
    -- Pad Signals 
    signal resetn_pad : std_logic; -- Active low reset pad
    signal prt1 : std_logic_vector(7 downto 0); -- Port 1 Signal
    signal prt2 : std_logic_vector(7 downto 0); -- Port 2 Signal
    signal prt3 : std_logic_vector(7 downto 0); -- Port 3 Signal
    signal prt4 : std_logic_vector(7 downto 0); -- Port 4 Signal

    signal prt2_filtered : std_logic_vector(7 downto 0);

    -- Flash Memory - SPI Slave 
    component serial_flash is
        generic (
            ProgramAddress         : natural;
            RamSizeBytes           : natural;
            SwapBytesIn32BitWord   : boolean
        );
        port ( 
            CSb     : in  std_logic;
            SPCLK   : in  std_logic;
            MOSI    : in  std_logic;
            MISO    : out std_logic;
            mem_reset : in std_logic; --NOTE: not an actual flash mem input, used for testing only
            awake    : out std_logic; -- For testing only, indicates the flash is awake
            RAM_FILE_PATH          : in string
        );
    end component;

    -- Testbench signals
    signal clk, resetn : std_logic := '1';
    signal a0 : std_logic_vector(31 downto 0);
    -- M3b/M12: a0 of the 3 tile harts (boot from the shared ROM and park in WFI)
    signal a0_1, a0_2, a0_3 : std_logic_vector(31 downto 0);
    signal spi_flash_din_sig, spi_flash_addr_sig : std_logic_vector(31 downto 0);

    signal clk_hfxt : std_logic;
    signal clk_lfxt : std_logic;

    -- Simulation control
    signal stop_clock : boolean := false;
    signal simulation_timeout_flag : boolean := true;

    signal a0_reached_fail : boolean := false;
    signal a0_reached_pass : boolean := false;
    -- M3b: latched pass/fail for private-memory harts 1-3
    signal h1_pass, h2_pass, h3_pass : boolean := false;
    signal h1_fail, h2_fail, h3_fail : boolean := false;
    signal flash_awake : std_logic := '0';

    --RAM Memory Load Signals 
    signal load_ram : boolean := false;
    signal load_ram_sig : std_logic;
    signal ram_file_name : string(1 to 29) := TEST_FILE;

    -- SPI Flash Signals 
    signal load_data    : std_logic := '1';
    signal spi_din      : std_logic_vector(31 downto 0);
    signal spi_dout     : std_logic_vector(31 downto 0);
    signal spi_we       : std_logic := '0';
    signal spi_re       :  std_logic := '0';
    signal spi_busy     :  std_logic := '0';
    signal spi_cs       : std_logic := '1';
    signal spi_clk      :  std_logic := '0';
    signal spi_mosi     :  std_logic; 
    signal spi_miso     :  std_logic;
    signal flash_word: std_logic_vector(31 downto 0);
    signal flash_done : std_logic;

    -- Port Signals 
    signal prt1_in : std_logic_vector(7 downto 0);
    signal prt1_out : std_logic_vector(7 downto 0);
    signal prt1_dir : std_logic_vector(7 downto 0);
    signal prt1_ren : std_logic_vector(7 downto 0);
    signal prt2_in : std_logic_vector(7 downto 0);
    signal prt2_out : std_logic_vector(7 downto 0);
    signal prt2_dir : std_logic_vector(7 downto 0);
    signal prt2_ren : std_logic_vector(7 downto 0);
    signal prt3_in : std_logic_vector(7 downto 0);
    signal prt3_out : std_logic_vector(7 downto 0);
    signal prt3_dir : std_logic_vector(7 downto 0);
    signal prt3_ren : std_logic_vector(7 downto 0);
    signal prt4_in : std_logic_vector(7 downto 0);
    signal prt4_out : std_logic_vector(7 downto 0);
    signal prt4_dir : std_logic_vector(7 downto 0);
    signal prt4_ren : std_logic_vector(7 downto 0);
    -- Mission B: GPIO4/GPIO5 (prt5/prt6), inputs driven benign-idle below
    signal prt5_in : std_logic_vector(7 downto 0);
    signal prt5_out : std_logic_vector(7 downto 0);
    signal prt5_dir : std_logic_vector(7 downto 0);
    signal prt5_ren : std_logic_vector(7 downto 0);
    signal prt6_in : std_logic_vector(7 downto 0);
    signal prt6_out : std_logic_vector(7 downto 0);
    signal prt6_dir : std_logic_vector(7 downto 0);
    signal prt6_ren : std_logic_vector(7 downto 0);

    signal resetn_out : std_logic;
    signal resetn_dir : std_logic;
    signal resetn_ren : std_logic;
    signal resetn_in : std_logic;

    signal gpio2_test : std_logic := '0'; -- high if the current test is a gpio test
    signal gpio1_test : std_logic := '0'; -- high if the current test is a gpio1 test
    signal spi_test : std_logic := '0'; -- high if the current test is a spi test
    signal uart_test : std_logic := '0'; -- high if the current test is a uart test
    signal timer_test : std_logic := '0'; -- high if the current test is a timer test
    signal spifem_test : std_logic := '0'; -- high if the current test is a spifm test


    signal gpio0_drv_sig: std_logic_vector(7 downto 0);
    signal gpio0_oe_sig: std_logic_vector(7 downto 0);
    signal gpio1_drv_sig: std_logic_vector(7 downto 0);
    signal gpio1_oe_sig: std_logic_vector(7 downto 0);
    signal gpio2_drv_sig: std_logic_vector(7 downto 0);
    signal gpio2_oe_sig: std_logic_vector(7 downto 0);
    signal gpio3_drv_sig: std_logic_vector(7 downto 0);
    signal gpio3_oe_sig: std_logic_vector(7 downto 0);


    signal boot_done_flag : std_logic;
    signal boot_mode : std_logic; -- '1' = boot from flash, '0' = boot into forth mode TODO: Invert this
    signal cs_flash : std_logic;


    -- AFE Connections
    signal afe_dac_bias :  std_logic;
    signal use_dac_glb_bias :  std_logic;
    signal en_bias_buf  :  std_logic;
    signal en_bias_gen  :  std_logic;

    -- Biasing Signals
    signal BIAS_ADJ    : std_logic_vector(5 downto 0);
    signal BIAS_DBP    : std_logic_vector(13 downto 0);
    signal BIAS_DBN    : std_logic_vector(13 downto 0);
    signal BIAS_DBPC   : std_logic_vector(13 downto 0);
    signal BIAS_DBNC   : std_logic_vector(13 downto 0);
    signal BIAS_TC_POT    : std_logic_vector(5 downto 0);
    signal BIAS_LC_POT : std_logic_vector(5 downto 0);
    signal BIAS_TIA_G_POT: std_logic_vector(16 downto 0);
    signal BIAS_DSADC_VCM : std_logic_vector(13 downto 0);
    signal BIAS_REV_POT: std_logic_vector(13 downto 0);
    signal BIAS_TC_DSADC : std_logic_vector(5 downto 0);
    signal BIAS_LC_DSADC : std_logic_vector(5 downto 0);
    signal BIAS_RIN_DSADC : std_logic_vector(5 downto 0);
    signal BIAS_RFB_DSADC : std_logic_vector(5 downto 0);

    -- DSADC Output signals
    signal dsadc_conv_done : std_logic;
    signal dsadc_en       : std_logic;
    signal dsadc_clk      : std_logic;
    signal dsadc_switch    : std_logic_vector(2 downto 0);
    signal dac_en_pot      : std_logic;
    signal adc_ext_in      : std_logic;
    signal adc_sel         : std_logic;
    signal atp_en         : std_logic;
    signal atp_sel        : std_logic;

    -- ADC Output signals 
    signal saradc_rdy   : std_logic;
    signal saradc_rst   : std_logic;
    signal saradc_data  : std_logic_vector(9 downto 0);
    signal saradc_clk   : std_logic;

    
    begin

    -- Select if '1' for Loading Program from Flash, or '0' for RV4TH mode 
    boot_mode <= '1';

    -- Signal Routing for SPI Flash
    spi_clk     <=  prt1(pnum_gpio0_spi_clk);
    spi_cs      <=  prt1(pnum_gpio0_cs_flash);
    spi_mosi    <=  prt1(pnum_gpio0_mosi);


    -- Mission B: GPIO4/GPIO5 pad inputs benign-idle (matches the generated
    -- behavioral riscv_tb.vhd; nothing in the gate smoke drives P5/P6).
    prt5_in <= (others => '0');
    prt6_in <= (others => '0');

    -- ROOT-3 (X-collapse root cause, 2026-07-20): weak idle-HIGH pulls on
    -- every UART-RX-capable pad — a real board never floats an enabled
    -- UART's RX (idle = mark). An undriven ('Z') RX pad reads X; the RX
    -- start-detect samples that X into rx_in_progress, which feeds the BAUD
    -- CLOCK-GATE ENABLE combinationally (UART.vhd:197 en_baud_clk_src) — an
    -- X enable at an smclk edge X-es the gated clock and collapses the whole
    -- chip (proven via first-X VCD: cgu_baud_clk_src ECK first). Behavioral
    -- sim is immune (VHDL '=' with X returns false), which is why only the
    -- gate flow died. 'H' is weak — any real test driver overrides it,
    -- exactly like a board pull-up (afselv2 still drives P4.5 strongly).
    prt2(5) <= 'H';  -- RX0 home (P2.5)
    prt2(7) <= 'H';  -- RX1 home (P2.7)
    prt3(1) <= 'H';  -- RX1 AF1  (P3.1)
    prt3(5) <= 'H';  -- RX0 AF1  (P3.5)
    prt4(5) <= 'H';  -- RX0 v2   (P4.5)

    dut: MCU
    port map (
    
        -- Reset Pad
        resetn_in	=> resetn_in,
		resetn_out	=> resetn_out,
		resetn_dir	=> resetn_dir,
		resetn_ren	=> resetn_ren,

        prt1_in		=> prt1_in,
        prt1_out	=> prt1_out,
        prt1_dir	=> prt1_dir,
        prt1_ren	=> prt1_ren,

        prt2_in		=> prt2_in,
        prt2_out	=> prt2_out,
        prt2_dir	=> prt2_dir,
        prt2_ren	=> prt2_ren,
        
        prt3_in		=> prt3_in,
        prt3_out	=> prt3_out,
        prt3_dir	=> prt3_dir,
        prt3_ren	=> prt3_ren, 

        prt4_in		=> prt4_in,
        prt4_out	=> prt4_out,
        prt4_dir	=> prt4_dir,
        prt4_ren	=> prt4_ren,

        prt5_in		=> prt5_in,
        prt5_out	=> prt5_out,
        prt5_dir	=> prt5_dir,
        prt5_ren	=> prt5_ren,

        prt6_in		=> prt6_in,
        prt6_out	=> prt6_out,
        prt6_dir	=> prt6_dir,
        prt6_ren	=> prt6_ren,

        -- WOUND CONFIG: no AFE/bias/DSADC/SARADC ports on the wound MCU
        -- (analog port-map group deleted to match the netlist; the tb-side
        -- signals stay declared above, undriven/unused).

        -- Test Port
        a0          => a0,

        -- M3b: private-memory harts 1-3
        a0_1        => a0_1,
        a0_2        => a0_2,
        a0_3        => a0_3,

        -- D5 DD16: the debug-on port group (see the component declaration).
        -- Every INPUT here is associated because xmelab hard-refuses otherwise;
        -- the outputs are associated too, so nothing is left to a *W,CUFEPC.
        dmi_req_valid => dmi_req_valid,
        dmi_req_op    => dmi_req_op,
        dmi_req_addr  => dmi_req_addr,
        dmi_req_data  => dmi_req_data,
        dmi_req_ready => dmi_req_ready,
        dmi_rsp_valid => dmi_rsp_valid,
        dmi_rsp_data  => dmi_rsp_data,
        dmi_rsp_op    => dmi_rsp_op,

        tck   => tck,
        tms   => tms,
        tdi   => tdi,
        tdo   => tdo,
        trstn => trstn
    );

    cs_flash <= spi_cs when boot_done_flag = '0' or spifem_test = '1'
                else '1';
    


    process(resetn, flash_awake)
    begin
        if (resetn = '0') then
            boot_done_flag <= '0';
        elsif falling_edge(flash_awake) then
            -- flash boot up done 
            boot_done_flag <= '1';
        end if;
    end process;
    
    spi_slave_flash: serial_flash
        generic map (
            ProgramAddress => 16#0000#,
            RamSizeBytes => 16#8100#,  -- RAM Size + 4 extra Flash Commands 
            SwapBytesIn32BitWord => false
        )
        port map (
            CSb => cs_flash,
            SPCLK => spi_clk,
            MOSI => spi_mosi,
            MISO => spi_miso,
            mem_reset => not resetn, 
            awake => flash_awake, -- For testing only, indicates the flash is awake
            RAM_FILE_PATH => ram_file_name
    );

    -- Pad Instantiations

    reset_pad: entity work.PDUW16SDGZ_G
		port map
		(
			I	=> resetn_out, 
			OEN	=> resetn_dir, 
			REN	=> resetn_ren, 
			PAD	=> resetn_pad,
			C	=> resetn_in
		);

    resetn_pad <= resetn;

	pad_prt1_gen: for i in 7 downto 0 generate
		pad_p1: entity work.PDUW16SDGZ_G
		port map
		(
			I	=> prt1_out(i),
			OEN	=> prt1_dir(i),
			REN	=> prt1_ren(i),
			PAD	=> prt1(i),
			C	=> prt1_in(i)
		);
	end generate;

    
    pad_prt2_gen: for i in 7 downto 0 generate
		pad_p2: entity work.PDUW16SDGZ_G
		port map
		(
			I	=> prt2_out(i),
			OEN	=> prt2_dir(i),
			REN	=> prt2_ren(i),
			PAD	=> prt2(i),
			C	=> prt2_in(i)
		);
	end generate;

    pad_prt3_gen: for i in 7 downto 0 generate
		pad_p2: entity work.PDUW16SDGZ_G
		port map
		(
			I	=> prt3_out(i),
			OEN	=> prt3_dir(i),
			REN	=> prt3_ren(i),
			PAD	=> prt3(i),
			C	=> prt3_in(i)
		);
	end generate;

    pad_prt4_gen: for i in 7 downto 0 generate
		pad_p2: entity work.PDUW16SDGZ_G
		port map
		(
			I	=> prt4_out(i),
			OEN	=> prt4_dir(i),
			REN	=> prt4_ren(i),
			PAD	=> prt4(i),
			C	=> prt4_in(i)
		);
	end generate;


	ProcClkHFXT: process
	begin
		clk_hfxt <= '0';
		wait for clk_hfxt_period / 2;
		clk_hfxt <= '1';
		wait for clk_hfxt_period / 2;
	end process;

	ProcClkLFXT: process
	begin
		clk_lfxt <= '0';
		wait for clk_lfxt_period / 2;
		clk_lfxt <= '1';
		wait for clk_lfxt_period / 2;
	end process;

    -- Timeout watchdog process
    timeout_watchdog: process
        begin
        wait for SIMULATION_TIMEOUT;
        if not (a0_reached_fail or a0_reached_pass) then
            simulation_timeout_flag <= true;
            report "SIMULATION TIMEOUT REACHED" severity failure;
        end if;
        wait;
    end process;

    -- Digital clock is hf clock
    clk <= clk_hfxt;


    Prt1(pnum_gpio0_hfxt) <= clk_hfxt;
    Prt1(pnum_gpio0_lfxt) <= clk_lfxt;

    -- SPI Short Connections for testing 
    -- Should potenitally provide shorts between GPIO0(3 downto 0) and GPIO1 (3 downto 0)
    spi_test <= '1' when contains_spi(ram_file_name) else '0';
    uart_test <= '1' when contains_uart(ram_file_name) else '0';
    timer_test <= '1' when contains_timer(ram_file_name) else '0';
    gpio2_test <= '1' when contains_gpio2(ram_file_name) else '0';
    gpio1_test <= '1' when contains_gpio1(ram_file_name) else '0';
    spifem_test <= '1' when contains_spifem(ram_file_name) else '0';
    
    -- M9b GATE-SIM FIX: 'Z' here reads back as X through the pad input buffer;
    -- GPIO0's input/IF comb samples that X and it detonates the whole clock
    -- tree at the first spurious GPIO0 bus-clock pulse (behavioral sims mask
    -- it via VHDL X-optimism). Drive a weak '1' (emulates the pad pull) when
    -- the flash is asleep.
    prt1(pnum_gpio0_miso) <= spi_miso when flash_awake = '1' else 'H';
    spi_short_proc: process(prt1, prt1_dir, prt2, prt2_dir, prt3, prt3_dir, flash_awake, spi_test, uart_test, timer_test)
    begin
        for i in 0 to 7 loop
            if flash_awake = '0' then
                if spi_test = '1' and i < 4 then
                    if prt1_dir(i) = '0' and prt2_dir(i) = '1' then
                        -- i is output, i is input: drive i with prt1(i)
                        gpio1_drv_sig(i) <= prt1(i);
                        gpio1_oe_sig(i)  <= '1';
                        gpio0_drv_sig(i)   <= 'Z';
                        gpio0_oe_sig(i)    <= '0';
                    elsif prt1_dir(i) = '1' and prt2_dir(i) = '0' then
                        -- i is input, i is output: drive i with prt1(i)
                        gpio0_drv_sig(i)   <= prt2(i);
                        gpio0_oe_sig(i)    <= '1';
                        gpio1_drv_sig(i) <= 'Z';
                        gpio1_oe_sig(i)  <= '0';
                    else
                        gpio0_drv_sig(i)   <= 'Z';
                        gpio0_oe_sig(i)    <= '0';     
                        gpio1_drv_sig(i) <= 'Z';
                        gpio1_oe_sig(i)  <= '0';
                    end if;
                else
                    gpio0_drv_sig(i)   <= 'Z';
                    gpio0_oe_sig(i)    <= '0';     
                    gpio1_drv_sig(i) <= 'Z';
                    gpio1_oe_sig(i)  <= '0';
                end if; 
            end if;
        end loop;

        -- UART Short Connections for testing (pins 4<->7 and 5<->6)
        if uart_test = '1' and flash_awake = '0' then
            -- P2.4 <-> P2.7
            if prt2_dir(4) = '0' and prt2_dir(7) = '1' then
                gpio1_drv_sig(7) <= prt2(4);
                gpio1_oe_sig(7)  <= '1';
                gpio1_drv_sig(4) <= 'Z';
                gpio1_oe_sig(4)  <= '0';
            elsif prt2_dir(4) = '1' and prt2_dir(7) = '0' then
                gpio1_drv_sig(4) <= prt2(7);
                gpio1_oe_sig(4)  <= '1';
                gpio1_drv_sig(7) <= 'Z';
                gpio1_oe_sig(7)  <= '0';
            else
                gpio1_drv_sig(4) <= 'Z';
                gpio1_oe_sig(4)  <= '0';
                gpio1_drv_sig(7) <= 'Z';
                gpio1_oe_sig(7)  <= '0';
            end if;

            -- P2.5 <-> P2.6
            if prt2_dir(5) = '0' and prt2_dir(6) = '1' then
                gpio1_drv_sig(6) <= prt2(5);
                gpio1_oe_sig(6)  <= '1';
                gpio1_drv_sig(5) <= 'Z';
                gpio1_oe_sig(5)  <= '0';
            elsif prt2_dir(5) = '1' and prt2_dir(6) = '0' then
                gpio1_drv_sig(5) <= prt2(6);
                gpio1_oe_sig(5)  <= '1';
                gpio1_drv_sig(6) <= 'Z';
                gpio1_oe_sig(6)  <= '0';
            else
                gpio1_drv_sig(5) <= 'Z';
                gpio1_oe_sig(5)  <= '0';
                gpio1_drv_sig(6) <= 'Z';
                gpio1_oe_sig(6)  <= '0';
            end if;
        end if;

        if timer_test = '1' and flash_awake = '0' then
            -- P2.X <-> P3.X
            for i in 0 to 7 loop
                if prt2_dir(i) = '1' and prt3_dir(i) = '0' then
                    gpio1_drv_sig(i) <= prt3(i);
                    gpio1_oe_sig(i)  <= '1';
                    gpio2_drv_sig(i) <= 'Z';
                    gpio2_oe_sig(i)  <= '0';
                elsif prt2_dir(i) = '0' and prt3_dir(i) = '1' then
                    gpio2_drv_sig(i) <= prt2(i);
                    gpio2_oe_sig(i)  <= '1';
                    gpio1_drv_sig(i) <= 'Z';
                    gpio1_oe_sig(i)  <= '0';
                else
                    gpio1_drv_sig(i) <= 'Z';
                    gpio1_oe_sig(i)  <= '0';
                    gpio2_drv_sig(i) <= 'Z';
                    gpio2_oe_sig(i)  <= '0';
                end if;
            end loop;
        end if;

        if gpio2_test = '1' and flash_awake = '0' then
            -- P3.X <-> P4.X
            for i in 0 to 7 loop
                if prt3_dir(i) = '1' and prt4_dir(i) = '0' then
                    gpio2_drv_sig(i) <= prt4(i);
                    gpio2_oe_sig(i)  <= '1';
                    gpio3_drv_sig(i) <= 'Z';
                    gpio3_oe_sig(i)  <= '0';
                elsif prt3_dir(i) = '0' and prt4_dir(i) = '1' then
                    gpio3_drv_sig(i) <= prt3(i);
                    gpio3_oe_sig(i)  <= '1';
                    gpio2_drv_sig(i) <= 'Z';
                    gpio2_oe_sig(i)  <= '0';
                else
                    gpio2_drv_sig(i) <= 'Z';
                    gpio2_oe_sig(i)  <= '0';
                    gpio3_drv_sig(i) <= 'Z';
                    gpio3_oe_sig(i)  <= '0';
                end if;
            end loop;
        end if;

        if gpio1_test = '1' and flash_awake = '0' then
            -- P3.X <-> P2.X
            for i in 0 to 7 loop
                if prt2_dir(i) = '1' and prt3_dir(i) = '0' then
                    gpio1_drv_sig(i) <= prt3(i);
                    gpio1_oe_sig(i)  <= '1';
                    gpio2_drv_sig(i) <= 'Z';
                    gpio2_oe_sig(i)  <= '0';
                elsif prt2_dir(i) = '0' and prt3_dir(i) = '1' then
                    gpio2_drv_sig(i) <= prt2(i);
                    gpio2_oe_sig(i)  <= '1';
                    gpio1_drv_sig(i) <= 'Z';
                    gpio1_oe_sig(i)  <= '0';
                else
                    gpio1_drv_sig(i) <= 'Z';
                    gpio1_oe_sig(i)  <= '0';
                    gpio2_drv_sig(i) <= 'Z';
                    gpio2_oe_sig(i)  <= '0';
                end if;
            end loop;
        end if;


    end process;

    -- Forth mode pin
    prt1(7) <= boot_mode when boot_done_flag = '0' else 'Z'; 

    -- Drive the ports based on the OE signals and test type
    prt2_conns: for i in 0 to 7 generate
        prt1(i) <=  gpio0_drv_sig(i) when gpio0_oe_sig(i) = '1' and spi_test = '1' else 'Z';
        prt2(i) <=  gpio1_drv_sig(i) when gpio1_oe_sig(i) = '1' and (spi_test = '1' or uart_test = '1' or timer_test = '1' or gpio1_test = '1') else 'Z';
        prt3(i) <=  gpio2_drv_sig(i) when gpio2_oe_sig(i) = '1' and (timer_test = '1' or gpio2_test = '1' or gpio1_test = '1') else 'Z';
        prt4(i) <=  gpio3_drv_sig(i) when gpio3_oe_sig(i) = '1' and (gpio2_test = '1') else 'Z';
    end generate;

    -- Main test sequence
    test_sequence: process
        variable file_exists : boolean;
    begin
        resetn <= '0';
        wait for 1 * CLK_PERIOD;
        resetn <= '1';

        check_file_exists(TEST_FILE, file_exists);
        if not file_exists then
            report "FATAL ERROR: Test file not found: " & TEST_FILE
                severity failure;
        end if;

        wait for 5*CLK_PERIOD;
        ram_file_name <= TEST_FILE;
        wait for CLK_PERIOD;
        resetn <= '0';
        report " New Test Loading Via SPI Flash ..." severity note;
        wait for 2.5*CLK_PERIOD;
        resetn <= '1';
        wait for CLK_PERIOD;

        report "Starting test: " & TEST_FILE severity note;

        wait until (a0_reached_fail or a0_reached_pass or simulation_timeout_flag);

        -- M12: report the tile harts (1-3). They boot from the SHARED ROM and
        -- park in WFI; ordinary single-hart tests leave them parked (never pass
        -- NOR fail — expected silence). Multi-hart tests ignite them via the
        -- bootrom loader mailboxes; a tile FAIL always fails the run.
        report "HART1 (tile) pass=" & boolean'image(h1_pass) &
               " fail=" & boolean'image(h1_fail) severity note;
        report "HART2 (tile) pass=" & boolean'image(h2_pass) &
               " fail=" & boolean'image(h2_fail) severity note;
        report "HART3 (tile) pass=" & boolean'image(h3_pass) &
               " fail=" & boolean'image(h3_fail) severity note;
        if h1_fail or h2_fail or h3_fail then
            report "M12: a tile hart FAILED" severity failure;
        elsif not (h1_pass and h2_pass and h3_pass) then
            report "M12 NOTE: tile hart(s) silent/parked (expected for single-hart tests)"
                severity note;
        else
            report "M12: all 3 tile harts PASSED (concurrent w/ hart 0)" severity note;
        end if;

        if a0_reached_pass then
            report "TEST PASSED - " & TEST_FILE severity note;
            report get_pass_logo severity failure;
        elsif a0_reached_fail then
            report "TEST FAILED - " & TEST_FILE severity failure;
        else
            report "TEST TIMED OUT - " & TEST_FILE severity failure;
        end if;

        wait;
    end process;

    -- Monitoring for pass/fail detection
    monitor_a0: process(resetn, clk)
    begin
        if resetn = '0' then
            a0_reached_pass <= false;
            a0_reached_fail <= false;
        elsif rising_edge(clk) then
            -- Check for pass condition
            if a0 = PASS_LABEL then
                a0_reached_pass <= true;
            end if; 
            -- Check for fail condition
            if a0 = FAIL_LABEL then
                a0_reached_fail <= true;
            end if;
        end if;
    end process;

    -- M3b/M12: monitor the 3 tile harts. Since M12 they boot from the shared
    -- ROM and park in WFI until ignited through the bootrom loader mailboxes.
    -- Latched so the end-of-test report can confirm pass AND catch any fail.
    monitor_harts: process(resetn, clk)
    begin
        if resetn = '0' then
            h1_pass <= false; h2_pass <= false; h3_pass <= false;
            h1_fail <= false; h2_fail <= false; h3_fail <= false;
        elsif rising_edge(clk) then
            if a0_1 = PASS_LABEL then h1_pass <= true; end if;
            if a0_2 = PASS_LABEL then h2_pass <= true; end if;
            if a0_3 = PASS_LABEL then h3_pass <= true; end if;
            if a0_1 = FAIL_LABEL then h1_fail <= true; end if;
            if a0_2 = FAIL_LABEL then h2_fail <= true; end if;
            if a0_3 = FAIL_LABEL then h3_fail <= true; end if;
        end if;
    end process;



end architecture behavioral;