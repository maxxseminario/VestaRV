-- rv4th_tb: boots the MCU into the ROM Forth interpreter and exercises it over UART0.
-- ProcMainTest sends each Forth command, ProcReceiveFromTX grades the reply, and the two run in lockstep through SentSync/ReceivedSync.
-- BOOT (P1.7) is held low to select ROM Forth; the run passes when no check reports an error.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.macros.all;  
use work.constants.all;
use work.MemoryMap.all;
use work.tb_defs.all;
use work.TestBenchLibrary.all;

entity rv4th_tb is
end rv4th_tb;

architecture behavior of rv4th_tb is
    
    -- Clock parameters
    constant clk_hfxt_delay : time := (0.5 sec) / 24000000;	-- 24 MHz
    constant clk_lfxt_delay : time := (0.5 sec) / 32768;	-- 32.768 kHz
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;

    -- UART parameters
    constant baudratePeriodROM : time := (1 sec) / 115200;
    constant StringTotalLength	: natural := 500;

    -- Clocks
    signal clk_hfxt : std_logic := '0';
    signal clk_lfxt : std_logic := '0';

    -- Pad signals, weakly pulled low so undriven pads read a defined level.
    signal resetn_pad : std_logic := '1'; -- Active low reset pad
    signal prt1 : std_logic_vector(7 downto 0) := (others => 'L'); -- Port 1 Signal
    signal prt2 : std_logic_vector(7 downto 0) := (others => 'L'); -- Port 2 Signal
    signal prt3 : std_logic_vector(7 downto 0) := (others => 'L'); -- Port 3 Signal
    signal prt4 : std_logic_vector(7 downto 0) := (others => 'L'); -- Port 4 Signal

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

    -- AFE Connections
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
    signal dsadc_conv_done : std_logic := '0';
    signal dsadc_en       : std_logic;
    signal dsadc_clk      : std_logic;
    signal dsadc_switch    : std_logic_vector(2 downto 0);
    signal adc_ext_in      : std_logic;
    signal adc_sel         : std_logic;
    signal atp_en         : std_logic;
    signal atp_sel        : std_logic;

    -- ADC Output signals 
    signal saradc_rdy   : std_logic := '0';
    signal saradc_rst   : std_logic;
    signal saradc_data  : std_logic_vector(9 downto 0) := (others => '0');
    signal saradc_clk   : std_logic;

    signal a0 : std_logic_vector(31 downto 0);

    -- UART helper signals
    signal TXing		: std_logic := '0';	-- '1' when MCU is sending data over UART, '0' otherwise
    signal RXing		: std_logic := '0';	-- '1' when MCU is receiving data over UART, '0' otherwise
    signal TXStr		: string(1 to StringTotalLength) := (others => nul);	-- Data sent from the MCU UART
    signal ReceivedSync	: std_logic := '0';	-- Notifies other processes that the testbench received some string from the MCU
    signal SentSync		: std_logic := '0';	-- Notifies other processes that the testbench finished sending some string to the MCU

    signal AllTestsPassed	: boolean := true;

    -- Pad aliases
    signal CS_FLASH		: std_logic;	        -- P1.0
    signal MISO0		: std_logic := '0';	    -- P1.1
    signal MOSI0		: std_logic;	        -- P1.2
    signal SCK0			: std_logic;	        -- P1.3
    signal TRAP			: std_logic;	        -- P1.6
    signal BOOT			: std_logic := '0';	    -- P1.7 (0 for Forth mode)

    signal TX0			: std_logic;	        -- P2.4
    signal RX0			: std_logic := '1';	    -- P2.5 (idle high)

    component MCU
        port (
            -- Resetn Pad
            resetn_in	: in	std_logic;
            resetn_out	: out	std_logic;
            resetn_dir	: out	std_logic;
            resetn_ren	: out	std_logic;

            --GPIO0 Connections
            prt1_in		    : in	std_logic_vector(7 downto 0);
            prt1_out		: out	std_logic_vector(7 downto 0);
            prt1_dir		: out	std_logic_vector(7 downto 0);
            prt1_ren		: out	std_logic_vector(7 downto 0);

            --GPIO1 Connections
            prt2_in		    : in	std_logic_vector(7 downto 0);
            prt2_out		: out	std_logic_vector(7 downto 0);
            prt2_dir		: out	std_logic_vector(7 downto 0);
            prt2_ren		: out	std_logic_vector(7 downto 0);

            --GPIO2 Connections
            prt3_in		    : in	std_logic_vector(7 downto 0);
            prt3_out		: out	std_logic_vector(7 downto 0);
            prt3_dir		: out	std_logic_vector(7 downto 0);
            prt3_ren		: out	std_logic_vector(7 downto 0);

            --GPIO3 Connections
            prt4_in		    : in	std_logic_vector(7 downto 0);
            prt4_out		: out	std_logic_vector(7 downto 0);
            prt4_dir		: out	std_logic_vector(7 downto 0);
            prt4_ren		: out	std_logic_vector(7 downto 0);

            -- AFE Connections
            use_dac_glb_bias : out std_logic;
            en_bias_buf  : out std_logic;
            en_bias_gen  : out std_logic;

            -- Biasing Connections
            BIAS_ADJ		: out	std_logic_vector(5 downto 0);	
            BIAS_DBP		: out	std_logic_vector(13 downto 0);
            BIAS_DBN		: out	std_logic_vector(13 downto 0);
            BIAS_DBPC		: out	std_logic_vector(13 downto 0);
            BIAS_DBNC		: out	std_logic_vector(13 downto 0);
            BIAS_TC_POT     : out   std_logic_vector(5 downto 0);
            BIAS_LC_POT     : out   std_logic_vector(5 downto 0);
            BIAS_TIA_G_POT  : out   std_logic_vector(16 downto 0); 
            BIAS_REV_POT    : out   std_logic_vector(13 downto 0);
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
    
begin

    -- 24 MHz crystal oscillator driven onto the HFXT pad.
    ProcClkHFXT: process
    begin
        clk_hfxt <= '0';
        wait for clk_hfxt_period / 2;
        clk_hfxt <= '1';
        wait for clk_hfxt_period / 2;
    end process;

    -- 32.768 kHz crystal oscillator driven onto the LFXT pad.
    ProcClkLFXT: process
    begin
        clk_lfxt <= '0';
        wait for clk_lfxt_period / 2;
        clk_lfxt <= '1';
        wait for clk_lfxt_period / 2;
    end process;

    -- Clock pad routing.
    prt1(pnum_gpio0_hfxt) <= clk_hfxt;
    prt1(pnum_gpio0_lfxt) <= clk_lfxt;
    
    -- Boot pin routing.
    prt1(pnum_gpio0_boot) <= BOOT;  -- Always '0' for Forth mode
    
    -- GPIO0 routing
    CS_FLASH <= prt1(pnum_gpio0_cs_flash);
    prt1(pnum_gpio0_miso) <= MISO0;
    MOSI0 <= prt1(pnum_gpio0_mosi);
    SCK0 <= prt1(pnum_gpio0_spi_clk);
    TRAP <= prt1(pnum_gpio0_trap);

    -- UART0 routing
    TX0 <= prt2(pnum_gpio1_tx0);
    prt2(pnum_gpio1_rx0) <= RX0;

    -- Receives UART data from the MCU and grades every expected response in order.
    -- It runs in lockstep with ProcMainTest through ReceivedSync and SentSync.
    ProcReceiveFromTX: process
        variable str : string(1 to StringTotalLength) := (others => nul);
        variable len : natural;
    begin
        -- Test 1.1: Boot message
        len := 21;  -- length of the boot banner
        UartReceiveStringFromTX(baudratePeriodROM, len, TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        
        if str(1 to len) = "myshkin rv4th-rom!" & lf & lf & ">" then
            report "MCU has booted to the forth prompt correctly. Received: " & str(1 to len);
        else
            report "Error: received incorrect boot string from MCU: " & str(1 to len) severity error;
            AllTestsPassed <= false;
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Test 1.2a: First write command response
        UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 16) = "123 0x04C00 !" & lf & lf & ">" then
            report "First write command response correct: " & str(1 to 16);
        else
            report "Error: incorrect first write response: " & str(1 to 16) severity error;
            AllTestsPassed <= false;
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Test 1.2b: second write command response, DISABLED (0x04D00).
        -- UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        -- TXStr <= str;
        -- wait for clk_hfxt_period;
        -- if str(1 to 16) = "124 0x04D00 !" & lf & lf & ">" then
        --     report "Second write command response correct: " & str(1 to 16);
        -- else
        --     report "Error: incorrect second write response: " & str(1 to 16) severity error;
        --     AllTestsPassed <= false;
        -- end if;
        -- ReceivedSync <= '1';
        -- wait for clk_hfxt_period;
        -- ReceivedSync <= '0';

        -- Test 1.2c: First read command response
        UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 18) = "0x04C00 @ ." & lf & "123 " & lf & ">" then
            report "First read command response correct: " & str(1 to 18);
        else
            report "Error: incorrect first read response: " & str(1 to 18) severity error;
            AllTestsPassed <= false;
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Test 1.2d: second read command response, DISABLED (0x04D00).
        -- UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        -- TXStr <= str;
        -- wait for clk_hfxt_period;
        -- if str(1 to 18) = "0x04B00 @ ." & lf & "124 " & lf & ">" then
        --     report "Second read command response correct: " & str(1 to 18);
        -- else
        --     report "Error: incorrect second read response: " & str(1 to 18) severity error;
        --     AllTestsPassed <= false;
        -- end if;
        -- ReceivedSync <= '1';
        -- wait for clk_hfxt_period;
        -- ReceivedSync <= '0';

        -- Test 1.3: Clock frequency response
        wait for 100 ms;
        UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        report "Measured MCLK frequency: " & str(1 to 50);  -- Show first 50 chars
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Test 1.4: Multiply command response
        len := 27;
        UartReceiveStringFromTX(baudratePeriodROM, len, TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 27) = "-500 75689 * ." & lf & "-37844500 " & lf & ">" then
            report "Multiply command response correct: " & str(1 to 27);
        else
            report "Error: incorrect multiply response: " & str(1 to 27) severity error;
            AllTestsPassed <= false;
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Test 1.5a: echo of writing `jal x0, 0` (0x0000006F, a one-instruction infinite loop) to 0x8200.
        -- Expected echo is "0x6F 0x8200 !" (13 chars) plus lf, lf and ">", 16 in total.
        len := 16;
        UartReceiveStringFromTX(baudratePeriodROM, len, TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 16) = "0x6F 0x8200 !" & lf & lf & ">" then
            report "RAM-write instruction stored correctly: " & str(1 to 16);
        else
            report "Error: incorrect RAM-write response: " & str(1 to 16) severity error;
            AllTestsPassed <= false;
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Test 1.5b: `0x8200 call0` echoes 12 chars plus lf and nothing more, because the CPU jumps to the RAM loop and never re-enters the Forth prompt.
        -- Receive a fixed 13 chars here: waiting for a `>` would hang.
        len := 13;
        UartReceiveStringFromTX(baudratePeriodROM, len, TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 13) = "0x8200 call0" & lf then
            report "call0 command echoed correctly; CPU should now be looping in RAM at 0x8200: " & str(1 to 13);
        else
            report "Error: incorrect call0 echo: " & str(1 to 13) severity error;
            AllTestsPassed <= false;
        end if;
        -- Let the CPU sit in its RAM loop, then confirm silence; further output would mean call0 fell through and the interpreter is still running.
        wait for 2 ms;
        if TXing = '1' then
            report "Error: MCU is still transmitting after call0; CPU did not jump to RAM" severity error;
            AllTestsPassed <= false;
        else
            report "MCU silent after call0 -- CPU jumped to RAM as expected.";
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        -- Final verdict.
        if AllTestsPassed then
            report "===== ALL FORTH TESTS PASSED =====" severity note;
        else
            report "===== SOME TESTS FAILED =====" severity error;
        end if;

        wait;
    end process;

    -- Main test control: selects ROM Forth boot, runs the reset sequence, then sends each Forth command and waits for the receiver to grade the reply.
    ProcMainTest: process
    begin
        -- Set boot mode to Forth (ROM)
        BOOT <= '0';  -- '0' = ROM forth, '1' = SPI flash
        
        -- Initialize signals
        RX0 <= '1';  -- UART idle high
        
        -- Reset sequence
        resetn_pad <= '1';
        wait for 1 us;
        wait until rising_edge(clk_hfxt);
        wait for clk_hfxt_delay / 2.3;
        resetn_pad <= '0';  -- Assert reset
        wait for 100 us;
        wait until rising_edge(clk_hfxt);
        wait for clk_hfxt_delay / 2.3;
        resetn_pad <= '1';  -- Release reset

        -- Test 1.1: Boot test
        report "Test 1.1: Check MCU boots to Forth prompt";
        wait until ReceivedSync = '1';
        wait for 3 ms;  -- Allow Forth to initialize

        -- Test 1.2: Memory write/read test
        report "Test 1.2: Memory write and read test";
        
        report "Sending first write command: 123 0x04C00 !";
        UartSendStrToRX(baudratePeriodROM, RX0, RXing, "123 0x04C00 !" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "Sending second write command: 124 0x04D00 ! (DISABLED)";
        -- UartSendStrToRX(baudratePeriodROM, RX0, RXing, "124 0x04D00 !" & lf);
        -- SentSync <= '1';
        -- wait for clk_hfxt_period;
        -- SentSync <= '0';
        -- wait until ReceivedSync = '1';

        report "Sending first read command: 0x04C00 @ .";
        UartSendStrToRX(baudratePeriodROM, RX0, RXing, "0x04C00 @ ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "Sending second read command: 0x04D00 @ . (DISABLED)";
        -- UartSendStrToRX(baudratePeriodROM, RX0, RXing, "0x04D00 @ ." & lf);
        -- SentSync <= '1';
        -- wait for clk_hfxt_period;
        -- SentSync <= '0';
        -- wait until ReceivedSync = '1';

        -- Test 1.3: Clock frequency test
        report "Test 1.3: Get MCLK frequency";
        UartSendStrToRX(baudratePeriodROM, RX0, RXing, "3 1 clk ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';
        wait for 5 ms;

        -- Test 1.4: Arithmetic test
        report "Test 1.4: Multiply command test";
        UartSendStrToRX(baudratePeriodROM, RX0, RXing, "-500 75689 * ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        -- Test 1.5: RAM upload then jump.
        -- 1.5a writes `jal x0, 0` (0x0000006F, an infinite loop) to 0x8200; 1.5b jumps to it via `call0`, which leaves the Forth prompt for good.
        report "Test 1.5a: Store `jal x0, 0` (0x6F) at 0x8200";
        UartSendStrToRX(baudratePeriodROM, RX0, RXing, "0x6F 0x8200 !" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "Test 1.5b: Jump to 0x8200 via call0";
        UartSendStrToRX(baudratePeriodROM, RX0, RXing, "0x8200 call0" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "===== All test commands sent =====" severity error;
        
        wait;
    end process;

    -- MCU instantiation
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

    -- Pad Instantiations
    reset_pad: entity work.PDUW16SDGZ_G
    port map (
        I	=> resetn_out,
        OEN	=> resetn_dir,
        REN	=> resetn_ren,
        PAD	=> resetn_pad,
        C	=> resetn_in
    );

    pad_prt1_gen: for i in 7 downto 0 generate
        pad_p1: entity work.PDUW16SDGZ_G
        port map (
            I	=> prt1_out(i),
            OEN	=> prt1_dir(i),
            REN	=> prt1_ren(i),
            PAD	=> prt1(i),
            C	=> prt1_in(i)
        );
    end generate;

    pad_prt2_gen: for i in 7 downto 0 generate
        pad_p2: entity work.PDUW16SDGZ_G
        port map (
            I	=> prt2_out(i),
            OEN	=> prt2_dir(i),
            REN	=> prt2_ren(i),
            PAD	=> prt2(i),
            C	=> prt2_in(i)
        );
    end generate;

    pad_prt3_gen: for i in 7 downto 0 generate
        pad_p3: entity work.PDUW16SDGZ_G
        port map (
            I	=> prt3_out(i),
            OEN	=> prt3_dir(i),
            REN	=> prt3_ren(i),
            PAD	=> prt3(i),
            C	=> prt3_in(i)
        );
    end generate;

    pad_prt4_gen: for i in 7 downto 0 generate
        pad_p4: entity work.PDUW16SDGZ_G
        port map (
            I	=> prt4_out(i),
            OEN	=> prt4_dir(i),
            REN	=> prt4_ren(i),
            PAD	=> prt4(i),
            C	=> prt4_in(i)
        );
    end generate;

end behavior;

