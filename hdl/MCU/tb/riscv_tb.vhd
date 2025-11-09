
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

            -- AFE Connections
            use_dac_glb_bias : out std_logic;
            -- afe_dac_bias : out std_logic;  -- renamed from use_dac_glb_bias to avoid confusion with DAC global bias
            en_bias_buf  : out std_logic;
            en_bias_gen  : out std_logic;

            -- Biasing Connections
            BIAS_ADJ		: out	std_logic_vector(5 downto 0);	
            BIAS_DBP		: out	std_logic_vector(13 downto 0);
            BIAS_DBN		: out	std_logic_vector(13 downto 0);
            BIAS_DBPC		: out	std_logic_vector(13 downto 0);
            BIAS_DBNC		: out	std_logic_vector(13 downto 0);

            -- Potentiostat Biases
            BIAS_TC_POT     : out   std_logic_vector(5 downto 0);
            BIAS_LC_POT     : out   std_logic_vector(5 downto 0);
            BIAS_TIA_G_POT  : out   std_logic_vector(16 downto 0); 
            BIAS_REV_POT    : out   std_logic_vector(13 downto 0);

            -- DSADC Biases
            BIAS_TC_DSADC  : out   std_logic_vector(5 downto 0);
            BIAS_LC_DSADC  : out   std_logic_vector(5 downto 0);
            BIAS_RIN_DSADC : out   std_logic_vector(5 downto 0);
            BIAS_RFB_DSADC : out   std_logic_vector(5 downto 0);
            BIAS_DSADC_VCM : out   std_logic_vector(13 downto 0);

            -- DSADC Connections
            dsadc_conv_done : in std_logic;
            dsadc_en        : out std_logic;
            dsadc_clk       : out std_logic;
            dsadc_switch    : out std_logic_vector(2 downto 0);
            dac_en_pot      : out std_logic;
            adc_ext_in      : out std_logic;
            atp_en          : out std_logic;
            atp_sel         : out std_logic;
            adc_sel         : out std_logic;

            -- SARADC Connections
            saradc_clk      : out std_logic;
            saradc_rdy      : in std_logic;
            saradc_rst      : out std_logic;
            saradc_data     : in std_logic_vector(9 downto 0); 

            -- Test Port
            a0  : out std_logic_vector(31 downto 0) 

        );
end component;


    -- Constants
    constant CLK_PERIOD : time := 40 ns;
    constant clk_hfxt_delay : time := (0.5 sec) / 24000000;	-- 24 MHz
    constant clk_lfxt_delay : time := (0.5 sec) / 32768;	-- 32.768 kHz
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;
    constant SIMULATION_TIMEOUT : time := 10000000 us;
    
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
    signal spi_flash_din_sig, spi_flash_addr_sig : std_logic_vector(31 downto 0);

    signal clk_hfxt : std_logic;
    signal clk_lfxt : std_logic;

    -- Simulation control
    signal stop_clock : boolean := false;
    signal simulation_timeout_flag : boolean := true;

    signal a0_reached_fail : boolean := false;
    signal a0_reached_pass : boolean := false;
    signal flash_awake : std_logic := '0';

    --RAM Memory Load Signals 
    signal load_ram : boolean := false;
    signal load_ram_sig : std_logic;
    signal ram_file_name : string(1 to 29) := "../rcf/xxxrv32ui-p-simple.rcf";
    signal current_test : integer := 0;

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

        -- AFE Connections
        use_dac_glb_bias => use_dac_glb_bias,
        -- afe_dac_bias => afe_dac_bias,
        en_bias_buf  => en_bias_buf,
        en_bias_gen  => en_bias_gen,

        -- Biasing Connections
        BIAS_ADJ    => BIAS_ADJ,
        BIAS_DBP    => BIAS_DBP,
        BIAS_DBN    => BIAS_DBN,
        BIAS_DBPC   => BIAS_DBPC,
        BIAS_DBNC   => BIAS_DBNC,
        BIAS_TC_POT    => BIAS_TC_POT,
        BIAS_LC_POT => BIAS_LC_POT,
        BIAS_TIA_G_POT=> BIAS_TIA_G_POT,
        BIAS_REV_POT=> BIAS_REV_POT,
        BIAS_TC_DSADC => BIAS_TC_DSADC,
        BIAS_LC_DSADC => BIAS_LC_DSADC,
        BIAS_RIN_DSADC => BIAS_RIN_DSADC,
        BIAS_RFB_DSADC => BIAS_RFB_DSADC,
        BIAS_DSADC_VCM => BIAS_DSADC_VCM,

        -- DSADC Connections
        dsadc_conv_done => dsadc_conv_done,
        dsadc_en        => dsadc_en,
        dsadc_clk       => dsadc_clk,
        dsadc_switch    => dsadc_switch,
        dac_en_pot      => dac_en_pot,
        adc_ext_in      => adc_ext_in,
        atp_en          => atp_en,
        atp_sel         => atp_sel,
        adc_sel         => adc_sel,

        -- SARADC Connections
        saradc_clk      => saradc_clk,
        saradc_rdy      => saradc_rdy,
        saradc_rst      => saradc_rst,
        saradc_data     => saradc_data,


        -- Test Port
        a0          => a0
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
    
    prt1(pnum_gpio0_miso) <= spi_miso when flash_awake = '1' else 'Z';
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
        variable current_file : string(1 to 29);
    begin
        -- Reset MCU at begining of test 
        resetn <= '0';
        -- wait for 1.25* CLK_PERIOD;
        wait for 1 * CLK_PERIOD;
        resetn <= '1';

        for i in test_files'range loop

            current_file := (others => nul); 
            for j in test_files(i)'range loop
                if j <= current_file'length then
                    current_file(j) := test_files(i)(j);
                end if;
            end loop;

            --Delay for visual clarity of setting up filename before rising edge of reset
            wait for 5*CLK_PERIOD;

            ram_file_name <= current_file;
            wait for CLK_PERIOD;
            resetn <= '0';
            report " New Test Loading Via SPI Flash ..."  severity note;
            wait for 2.5*CLK_PERIOD;
            resetn <= '1';
            wait for CLK_PERIOD;


            report "Starting test " & integer'image(i) & " with file: " & 
                current_file severity note;
            
            -- Phase 2: Wait for test completion
            wait until (a0_reached_fail or a0_reached_pass or simulation_timeout_flag);
            
            -- Phase 3: Evaluate results
            if a0_reached_pass then
                report "************************ TEST PASSED - " & 
                    current_file severity note;
                
            elsif a0_reached_fail then
                report "TEST FAILED - " &
                    current_file severity failure;
            else
                report "TEST TIMED OUT - " &
                    current_file severity failure;
            end if;
            
        -- Delay before next test
            wait for 10*CLK_PERIOD; --NOTE: May need to reset here

        end loop;

        
        --All tests have complelted
        report get_pass_logo severity failure;
        -- Phase 4: Stop simulation
        stop_clock <= true;
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



end architecture behavioral;