/* rv4th_tb: boots the MCU into the ROM Forth interpreter and exercises it over UART0.
   ProcMainTest sends each Forth command, ProcReceiveFromTX grades the reply, and the two run in lockstep through SentSync/ReceivedSync.
   BOOT (P1.7) is held low to select ROM Forth; the run passes when no check reports an error. */
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

    -- GPIO4/GPIO5 have no package pads in this testbench.
    -- Their inputs are driven idle low below and their outputs are left unobserved.
    signal prt5_in  : std_logic_vector(7 downto 0);
    signal prt5_out : std_logic_vector(7 downto 0);
    signal prt5_dir : std_logic_vector(7 downto 0);
    signal prt5_ren : std_logic_vector(7 downto 0);

    signal prt6_in  : std_logic_vector(7 downto 0);
    signal prt6_out : std_logic_vector(7 downto 0);
    signal prt6_dir : std_logic_vector(7 downto 0);
    signal prt6_ren : std_logic_vector(7 downto 0);

    -- Per hart pass/fail observation, unused here.
    -- The Forth monitor runs on hart 0 and is graded over UART0, not through a0.
    signal a0_1 : std_logic_vector(31 downto 0);
    signal a0_2 : std_logic_vector(31 downto 0);
    signal a0_3 : std_logic_vector(31 downto 0);
    signal a0_4 : std_logic_vector(31 downto 0);

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
            resetn_in	: in	std_logic;	-- '0' = reset asserted, '1' = system running
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

            prt5_in		    : in	std_logic_vector(7 downto 0);
            prt5_out		: out	std_logic_vector(7 downto 0);
            prt5_dir		: out	std_logic_vector(7 downto 0);
            prt5_ren		: out	std_logic_vector(7 downto 0);

            prt6_in		    : in	std_logic_vector(7 downto 0);
            prt6_out		: out	std_logic_vector(7 downto 0);
            prt6_dir		: out	std_logic_vector(7 downto 0);
            prt6_ren		: out	std_logic_vector(7 downto 0);


            -- Test Port
            a0  : out std_logic_vector(31 downto 0);

            -- Per-hart pass/fail observation (a0 of the 4 private-memory harts)
            a0_1 : out std_logic_vector(31 downto 0);
            a0_2 : out std_logic_vector(31 downto 0);
            a0_3 : out std_logic_vector(31 downto 0);
            a0_4 : out std_logic_vector(31 downto 0)

        );
end component;
    
    /* Sends one command to the ROM monitor one character at a time, leaving the line idle for sixteen bit times between frames.
       The monitor's receive path is a polled loop that echoes each character as it takes it, and it has no flow control, so a line delivered back to back at 115200 baud loses characters.
       Measured on this testbench, "123 0x04C00 !" arrives as "123 0x0C00": two characters of thirteen are lost, identically before and after the 2026-08-23 .noinit repair, so it is a standing property of the ROM and not a regression.
       It is also not what an interactive terminal does, which is the mode this monitor is documented for, so the stimulus here is paced like a typist.
       Sending back to back instead is what kept every test after the boot banner from grading anything. */
    procedure UartSendCmdPaced
    (
        constant baudratePeriod : in    time;
        signal   RX             : out   std_logic;
        signal   RXing          : out   std_logic;
        variable Cmd            : in    string
    ) is
        variable ch : string(1 to 1);
    begin
        for i in Cmd'range loop
            ch(1) := Cmd(i);
            UartSendStrNToRX(baudratePeriod, 1, RX, RXing, ch);
            wait for baudratePeriod * 16;
        end loop;
    end procedure;


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

        /* Test 1.4b: a user-defined word.
           This is the test that measures the dictionary, which is what the 2026-08-23 .noinit repair shrank.
           `: sq dup * ;` writes into cmdList, progOpcodes and prog, and `7 sq .` then looks the word up, calls it through the address stack and returns. */
        UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 15) = ": sq dup * ;" & lf & lf & ">" then
            report "User word defined: " & str(1 to 15);
        else
            report "Error: incorrect definition response: " & str(1 to 15) severity error;
            AllTestsPassed <= false;
        end if;
        ReceivedSync <= '1';
        wait for clk_hfxt_period;
        ReceivedSync <= '0';

        UartReceiveStringFromTXUntil(baudratePeriodROM, '>', TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;
        if str(1 to 12) = "7 sq ." & lf & "49 " & lf & ">" then
            report "User word executed correctly: " & str(1 to 12);
        else
            report "Error: incorrect user-word result: " & str(1 to 12) severity error;
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
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "123 0x04C00 !" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "Sending second write command: 124 0x04D00 ! (DISABLED)";

        report "Sending first read command: 0x04C00 @ .";
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "0x04C00 @ ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "Sending second read command: 0x04D00 @ . (DISABLED)";

        -- Test 1.3: Clock frequency test
        report "Test 1.3: Get MCLK frequency";
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "3 1 clk ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';
        wait for 5 ms;

        -- Test 1.4: Arithmetic test
        report "Test 1.4: Multiply command test";
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "-500 75689 * ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        -- Test 1.4b: define a word and run it, exercising the dictionary.
        report "Test 1.4b: user-defined word";
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, ": sq dup * ;" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "7 sq ." & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        -- Test 1.5: RAM upload then jump.
        -- 1.5a writes `jal x0, 0` (0x0000006F, an infinite loop) to 0x8200; 1.5b jumps to it via `call0`, which leaves the Forth prompt for good.
        report "Test 1.5a: Store `jal x0, 0` (0x6F) at 0x8200";
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "0x6F 0x8200 !" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        report "Test 1.5b: Jump to 0x8200 via call0";
        UartSendCmdPaced(baudratePeriodROM, RX0, RXing, "0x8200 call0" & lf);
        SentSync <= '1';
        wait for clk_hfxt_period;
        SentSync <= '0';
        wait until ReceivedSync = '1';

        /* Let ProcReceiveFromTX reach its verdict before the stop below.
           It prints one clk_hfxt_period after raising ReceivedSync, which is the edge this process just resumed on.
           Without this wait the severity error stops the simulation first and the verdict is never printed. */
        wait for 10 * clk_hfxt_period;

        -- severity error is the stop, not a failure: xmsim breaks here.
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

        prt5_in		=> prt5_in,
        prt5_out	=> prt5_out,
        prt5_dir	=> prt5_dir,
        prt5_ren	=> prt5_ren,

        prt6_in		=> prt6_in,
        prt6_out	=> prt6_out,
        prt6_dir	=> prt6_dir,
        prt6_ren	=> prt6_ren,

        -- Test Port
        a0          => a0,

        -- Private-memory harts 1-4
        a0_1        => a0_1,
        a0_2        => a0_2,
        a0_3        => a0_3,
        a0_4        => a0_4
    );

    -- GPIO4/GPIO5 (prt5/prt6) have no package pads in this testbench.
    prt5_in <= (others => '0');
    prt6_in <= (others => '0');

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

