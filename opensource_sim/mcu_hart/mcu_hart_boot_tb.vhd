/* mcu_hart_boot_tb: boots the SINGLE-HART MCU (config/mcu_hart.json) out of the real mask-ROM image and grades the boot banner it prints on UART0.
   It is rv4th_tb reduced to its first check, against an MCU whose entity has no a0_1..a0_N-1 ports because the chip has no tile harts.
   BOOT (P1.7) is held low, which selects the ROM-resident Forth monitor, so the run needs no SPI flash image and nothing but the ROM is executed.
   WHAT A PASS PROVES, which is the reason this bench exists rather than an elaboration: reset release, the boot fetch from the shared ROM through the one-master arbiter, the tile's adddec and TCM (the monitor's stack lives there), the SYSTEM block's clock tree, and UART0 -- on a chip built with numHarts = 1. */
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.macros.all;
use work.constants.all;
use work.MemoryMap.all;
use work.tb_defs.all;
use work.TestBenchLibrary.all;

entity mcu_hart_boot_tb is
end mcu_hart_boot_tb;

architecture behavior of mcu_hart_boot_tb is

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

    -- Hart 0's a0, the chip's only one. The monitor is graded over UART0, not through it.
    signal a0 : std_logic_vector(31 downto 0);

    -- UART helper signals
    signal TXing		: std_logic := '0';	-- '1' when MCU is sending data over UART, '0' otherwise
    signal TXStr		: string(1 to StringTotalLength) := (others => nul);	-- Data sent from the MCU UART

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

    /* The single-hart MCU's entity, which is the point of this bench.
       At numHarts = 1 there are no a0_1..a0_N-1 ports, so a bench written for the five-hart chip cannot bind this component and this one cannot bind that chip. */
    component MCU
        port (

            -- Resetn Pad
            resetn_in	: in	std_logic;
            resetn_out	: out	std_logic;
            resetn_dir	: out	std_logic;
            resetn_ren	: out	std_logic;

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

    /* The verdict.
       The bench waits for exactly the 21 characters of the ROM's boot banner and prompt, so a chip that never boots hangs here and is stopped by the run's stop time with no banner printed. */
    ProcReceiveFromTX: process
        variable str : string(1 to StringTotalLength) := (others => nul);
        variable len : natural;
    begin
        len := 21;  -- length of the boot banner
        UartReceiveStringFromTX(baudratePeriodROM, len, TX0, TXing, str);
        TXStr <= str;
        wait for clk_hfxt_period;

        if str(1 to len) = "myshkin rv4th-rom!" & lf & lf & ">" then
            report "Single-hart MCU booted to the Forth prompt. Received: " & str(1 to len);
        else
            report "Error: received incorrect boot string from MCU: " & str(1 to len) severity error;
            AllTestsPassed <= false;
        end if;

        wait for 10 * clk_hfxt_period;
        if AllTestsPassed then
            report "===== MCU_HART BOOT PASSED =====";
        else
            report "===== MCU_HART BOOT FAILED =====" severity error;
        end if;
        wait;
    end process;

    -- Reset sequence, identical to rv4th_tb's.
    ProcMainTest: process
    begin
        BOOT <= '0';  -- '0' = ROM forth, '1' = SPI flash
        RX0 <= '1';   -- UART idle high

        resetn_pad <= '1';
        wait for 1 us;
        wait until rising_edge(clk_hfxt);
        wait for clk_hfxt_delay / 2.3;
        resetn_pad <= '0';  -- Assert reset
        wait for 100 us;
        wait until rising_edge(clk_hfxt);
        wait for clk_hfxt_delay / 2.3;
        resetn_pad <= '1';  -- Release reset

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
        a0          => a0
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
