library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity SYSTEM is
    generic (
        -- Number of IRQ lines
        NUM_IRQS         : natural := 32
    );
    port (
        -- Clock Inputs 
        clk_lfxt_in     : in  std_logic;
        clk_hfxt_in     : in  std_logic;
        clk_dco0_in     : in  std_logic;
        clk_dco1_in     : in  std_logic;

        -- Reset Inputs
        resetn_in       : in  std_logic;
        resetn_por      : in  std_logic;
        resetn_sys      : out std_logic;

        -- Interrupt Signals
        irq             : in  std_logic_vector(NUM_IRQS -1 downto 0); 
        isr_ret         : in  std_logic;
        irq_en          : out std_logic_vector(NUM_IRQS -1 downto 0);
        irq_priority    : out std_logic_vector(NUM_IRQS -1 downto 0);
        irq_recursion_en : out std_logic;
        irq_sys_wdt     : out std_logic;

        -- Memory Bus
        clk_mem         : in  std_logic;
        en_mem          : in  std_logic;
        wen             : in  std_logic_vector(3 downto 0);
        addr_periph     : in  std_logic_vector(7 downto 2);
        write_data      : in  std_logic_vector(31 downto 0);
        read_data       : out std_logic_vector(31 downto 0);

        -- Clock Outputs
        mclk_out        : out std_logic;
        smclk_out       : out std_logic;
        clk_lfxt_out    : out std_logic;
        clk_hfxt_out    : out std_logic;

        -- DCO Signals 
        en_dco0_out        : out std_logic;
        DCO0_BIAS           : out std_logic_vector(11 downto 0);
        en_dco1_out        : out std_logic;
        DCO1_BIAS           : out std_logic_vector(11 downto 0);

        --Memory Power 
        -- PGEN_rom        : out std_logic; -- '0' rom on, '1' rom off
        PGEN_mem        : out std_logic_vector(2 downto 0) -- '0' ram on, '1' ram off

    );
end SYSTEM;

architecture rtl of SYSTEM is

    -- Registers 
    signal SYS_CLK_CR         : std_logic_vector(8 downto 0);
    signal SYS_CLK_DIV_CR     : std_logic_vector(5 downto 0);
    signal SYS_BLOCK_PWR      : std_logic_vector(2 downto 0);
    signal SYS_CRC_DATA       : std_logic_vector(7 downto 0);
    signal SYS_CRC_STATE      : std_logic_vector(15 downto 0);
    signal SYS_IRQ_EN         : std_logic_vector(NUM_IRQS -1 downto 0);
    signal SYS_IRQ_PRI        : std_logic_vector(NUM_IRQS -1 downto 0); -- Defines low or high priority. 0 = low, 1 = high
    signal SYS_WDT_CR         : std_logic_vector(7 downto 0);
    signal SYS_WDT_SR         : std_logic_vector(1 downto 0);
    signal SYS_WDT_VAL        : std_logic_vector(23 downto 0);
    signal SYS_IRQ_CR         : std_logic_vector(1 downto 0);
    -- signal DCO0_BIAS          : std_logic_vector(11 downto 0);
    -- signal DCO1_BIAS          : std_logic_vector(11 downto 0);
    -- signal SYS_IRQ           : std_logic_vector(NUM_IRQS -1 downto 0); -- End of interrupt signals '1' interrupt pending '0' interrupt complete / no interrupt

    -- SYS_CLK_CR
    signal smclk_off          : std_logic;
    signal clk_hfxt_off       : std_logic;
    signal clk_lfxt_off       : std_logic;
    signal smclk_sel          : std_logic_vector(1 downto 0);
    signal mclk_sel           : std_logic_vector(1 downto 0);
    signal dco0_on           : std_logic; 
    signal dco1_on           : std_logic;

    --SYS_CLK_DIV_CR
    signal mclk_div           : std_logic_vector(2 downto 0);
    signal smclk_div          : std_logic_vector(2 downto 0);

    --SYS_BLOCK_PWR
    signal rom_off            : std_logic;
    signal ram_off            : std_logic_vector(1 downto 0);

    --SYS_WDT_CR
    signal wdt_en             : std_logic;
    signal wdt_ie             : std_logic;
    signal wdt_cdiv           : std_logic_vector(3 downto 0); --mclk divider for wdt
    signal wdt_hwrst          : std_logic;

    -- SYS_WDT_SR
    signal wdt_rf             : std_logic;
    signal wdt_if             : std_logic;

    -- SYS_IRQ_CR
    signal irq_gen           : std_logic; -- Glocal IRQ enable

    -- =============================================================================
    -- Memory Interface Signals
    -- =============================================================================
    signal en_addr_periph     : natural range 0 to 63;

    -- Core Signal Declarations 
    signal resetn_sync        : std_logic;
    signal mclk_undiv         : std_logic;
    signal smclk_undiv        : std_logic;
    signal mclk_divider       : std_logic_vector(6 downto 0);
    signal smclk_divider      : std_logic_vector(6 downto 0);
    signal mclk               : std_logic;
    signal smclk              : std_logic;
    signal clk_dco0            : std_logic;
    signal clk_dco1            : std_logic;

    signal en_clk_lfxt        : std_logic;
    signal en_clk_hfxt        : std_logic;
    signal en_clk_dco0        : std_logic;
    signal en_clk_dco1        : std_logic;
    signal clk_lfxt           : std_logic;
    signal clk_hfxt           : std_logic;

    signal sel_hfxt_as_mclk   : std_logic;
    signal sel_lfxt_as_mclk   : std_logic;
    signal sel_hfxt_as_smclk  : std_logic;
    signal sel_lfxt_as_smclk  : std_logic;
    signal sel_dco0_as_mclk  : std_logic;
    signal sel_dco1_as_mclk  : std_logic;
    signal sel_dco0_as_smclk  : std_logic;
    signal sel_dco1_as_smclk  : std_logic;

    -- CRC Sigs
    signal crc_prev           : std_logic_vector(15 downto 0);
    signal first_crc_flag     : std_logic;

    -- WDT Signals 
    signal resetn_wdt         : std_logic;
    -- signal count              : std_logic_vector(23 downto 0); -- Unified counter
    signal en_clk_wdt         : std_logic;
    signal clk_wdt            : std_logic;
    signal wdt_trigger        : std_logic;
    signal wdt_interrupt_ret  : std_logic;

    signal clr_wdt            : std_logic;
    signal clk_unlock         : std_logic;
    signal unlock             : std_logic;
    signal unlocked           : std_logic;
    signal unlock_timer       : std_logic_vector(5 downto 0);

    signal clr_wdt_rf         : std_logic;
    signal clr_wdt_if         : std_logic;
    signal smclk_en_out       : std_logic_vector(7 downto 0);



begin

    -- Register Routing 

    dco1_on       <= SYS_CLK_CR(8);
    dco0_on       <= SYS_CLK_CR(7);
    clk_hfxt_off  <= SYS_CLK_CR(6);
    clk_lfxt_off  <= SYS_CLK_CR(5);
    smclk_off     <= SYS_CLK_CR(4);
    smclk_sel     <= SYS_CLK_CR(3 downto 2);
    mclk_sel      <= SYS_CLK_CR(1 downto 0);
   
    smclk_div     <= SYS_CLK_DIV_CR(5 downto 3);
    mclk_div      <= SYS_CLK_DIV_CR(2 downto 0);

    ram_off       <= SYS_BLOCK_PWR(2 downto 1);
    rom_off       <= SYS_BLOCK_PWR(0);

    wdt_en        <= SYS_WDT_CR(7);
    wdt_cdiv      <= SYS_WDT_CR(5 downto 2);
    wdt_ie        <= SYS_WDT_CR(1);
    wdt_hwrst     <= SYS_WDT_CR(0);

    irq_recursion_en    <= SYS_IRQ_CR(1);
    irq_gen             <= SYS_IRQ_CR(0);


    SYS_WDT_SR    <= (
        0 => wdt_rf, 
        1 => wdt_if
    );

    -- Assign Outputs 
    clk_lfxt_out    <= clk_lfxt;
    clk_hfxt_out    <= clk_hfxt;


    -- ===========================
    -- Synchronizers 
    -- ===========================
    sync_proc: process(resetn_por, resetn_wdt, mclk, wdt_hwrst)
    begin
        if resetn_por = '0' or resetn_wdt = '0' or wdt_hwrst = '1' then
            resetn_sync <= '0';
            resetn_sys <= '0';
        elsif falling_edge(mclk) then
            resetn_sync <= resetn_por;
            resetn_sys <= resetn_sync;
        end if;
    end process;



    -- ===========================
    -- Watchdog timer 
    -- ===========================


   -- Clock gating for power savings
    en_clk_wdt <= '1' when wdt_en = '1' or wdt_ie = '1' else '0';

    cg_wdt_clk: entity work.ClkGate
        port map (
            ClkIn   => mclk,
            En      => en_clk_wdt,
            ClkOut  => clk_wdt
        );

    -- Main WDT counter process with async clear
    wdt_counter_proc: process(clk_wdt, resetn_sys, clr_wdt)
    begin
        if resetn_sys = '0' or clr_wdt = '1' then
            -- Async clear/reset of counter
            SYS_WDT_VAL <= (others => '0');
        elsif rising_edge(clk_wdt) then
            if wdt_en = '1' then
                -- Increment counter when enabled
                SYS_WDT_VAL <= SYS_WDT_VAL + 1;
            else
                -- Keep counter at 0 when disabled
                SYS_WDT_VAL <= (others => '0');
            end if;
        end if;
    end process;

    -- WDT event detection and interrupt flag management
    wdt_event_proc: process(clk_wdt, resetn_sys)
        variable wdt_bit_prev : std_logic;
    begin
        if resetn_sys = '0' then
            wdt_if <= '0';
            wdt_trigger <= '0';
            wdt_bit_prev := '0';
        elsif rising_edge(clk_wdt) then
            -- Store previous state of the watched bit
            wdt_bit_prev := SYS_WDT_VAL(slv2uint(wdt_cdiv));
            
            -- Detect rising edge on the selected bit (WDT event)
            if wdt_bit_prev = '0' and SYS_WDT_VAL(slv2uint(wdt_cdiv)) = '1' then
                -- Set interrupt flag on WDT timeout
                wdt_if <= '1';
                
                -- Generate trigger pulse if interrupts are enabled
                if wdt_ie = '1' and irq_gen = '1' then
                    wdt_trigger <= '1';
                end if;
            else
                -- Clear trigger after one cycle (pulse)
                wdt_trigger <= '0';
            end if;
            
            -- Clear interrupt flag if requested
            if clr_wdt_if = '1' then
                wdt_if <= '0';
            end if;
            
            -- Clear everything if WDT is disabled
            if wdt_en = '0' then
                wdt_if <= '0';
                wdt_trigger <= '0';
                wdt_bit_prev := '0';
            end if;
        end if;
    end process;



    -- This is safe becuase since WDT is the highest priority interrupt, it cannot be interrupted - if wdt_trigger = '1' then the next isr ret signal is gauranteed to be for the wdt_isr. Once returned, we will perform a system reset.
    wdt_eoi_proc: process(resetn_sys, isr_ret)
    begin
        if resetn_sys = '0' then
            wdt_interrupt_ret <= '0';
        elsif falling_edge(isr_ret) and wdt_trigger = '1' then
            wdt_interrupt_ret <= '1';
        end if;
    end process;

    resetn_wdt <= '0' when wdt_en = '1' and wdt_trigger = '1' and 
                    (wdt_ie = '0' or SYS_IRQ_EN(IRQB_SYS_WDT) = '0' or 
                    (wdt_ie = '1' and wdt_interrupt_ret = '1')) 
                    else '1';

    -- wdt resetn flag process
    wdt_rf_proc: process(resetn_por, clr_wdt_rf, resetn_wdt)
    begin
        if resetn_por = '0' or clr_wdt_rf = '1' then
            wdt_rf <= '0';
        elsif falling_edge(resetn_wdt) then
            wdt_rf <= '1';
        end if;
    end process;

    --Password unlock mechanism
    unlocked <= '1' when unlock_timer /= "000000" else '0';
    cg_unlock: entity work.ClkGate
        port map
        (
            ClkIn   => mclk,
            En      => unlocked,
            ClkOut  => clk_unlock
        );

    -- After unlocking wdt, you have 64 mclk cycles to do something 
    process(resetn_sys, clk_unlock, unlock)
    begin
        if resetn_sys = '0' then
            unlock_timer <= (others => '0'); -- locked
        elsif unlock = '1' then
            unlock_timer <= (others => '1'); -- start countdown
        elsif rising_edge(clk_unlock) then
            unlock_timer <= unlock_timer - 1;
        end if;
    end process;



    -- Clock Management ------------------------------------------------

    -- TODO: Look at these signals
    en_clk_hfxt <= (not clk_hfxt_off) or (sel_hfxt_as_mclk) or (sel_hfxt_as_smclk);
    en_clk_lfxt <= (not clk_lfxt_off) or (sel_lfxt_as_smclk);
    en_clk_dco0 <= (dco0_on) or (sel_dco0_as_mclk) or (sel_dco0_as_smclk);
    en_clk_dco1 <= (dco1_on) or (sel_dco1_as_mclk) or (sel_dco1_as_smclk);
    en_dco0_out <= en_clk_dco0;
    en_dco1_out <= en_clk_dco1;

    -- Gating the four clock sources 
    cg_clk_hfxt: entity work.ClkGate
        port map
        (
            ClkIn   => clk_hfxt_in,
            En      => en_clk_hfxt,
            ClkOut  => clk_hfxt
        );

    cg_clk_lfxt: entity work.ClkGate
        port map
        (
            ClkIn   => clk_lfxt_in,
            En      => en_clk_lfxt,
            ClkOut  => clk_lfxt
        );

    cg_clk_dco0: entity work.ClkGate
        port map
        (
            ClkIn   => clk_dco0_in,
            En      => en_clk_dco0,
            ClkOut  => clk_dco0
        );

    cg_clk_dco1: entity work.ClkGate
        port map
        (
            ClkIn   => clk_dco1_in,
            En      => en_clk_dco1,
            ClkOut  => clk_dco1
        );


    

    --smclk mux and divider
    smclk_mux: entity work.ClockMuxGlitchFree
    generic map 
    (
        CLK_COUNT  => 4,
        SEL_WIDTH  => 2,
        CLK_DEFAULT => 0
    )
    port map
    (
        resetn     => resetn_sys,
        Sel        => smclk_sel,

        ClkIn(0)   => clk_hfxt,
        ClkIn(1)   => clk_lfxt,
        ClkIn(2)   => clk_dco0,
        ClkIn(3)   => clk_dco1,

        ClkEn(0)   => sel_hfxt_as_smclk,
        ClkEn(1)   => sel_lfxt_as_smclk,
        ClkEn(2)   => sel_dco0_as_smclk,
        ClkEn(3)   => sel_dco1_as_smclk,

        ClkOut     => smclk_undiv
    );

    -- NOTE: smclk_divider increments on falling_edge(smclk_undiv) to avoid timing issues
    -- when smclk_div changes on rising_edge (from address decoder). Since smclk_div is sampled by the clock mux
    -- and may change synchronously with smclk_undiv (when it's the same clock), using
    -- opposite clock edges prevents the selector from changing at the same instant the
    -- divider outputs toggle, reducing the likelihood of glitches or metastability.
    -- TODO: Consider adding proper synchronization of smclk_div before use in ClockMuxGlitchFree
    -- for maximum robustness, though the risk of failure with current implementation is slim.

    smclk_div_proc: process(resetn_sys, smclk_undiv, smclk_off, smclk_div)
    begin
        if resetn_sys = '0' or smclk_off = '1' or smclk_div = "000" then
            smclk_divider <= (others => '0');
        elsif falling_edge(smclk_undiv) then
            smclk_divider <= smclk_divider + 1;
        end if;
    end process;

    smclk_divider_mux: entity work.ClockMuxGlitchFree
    generic map
    (
        CLK_COUNT  => 8,
        SEL_WIDTH  => 3,
        CLK_DEFAULT => 0
    )
    port map
    (
        resetn     => resetn_sys,
        Sel        => smclk_div,

        ClkIn(0)   => smclk_undiv,         -- Divide by 1 (no division)
        ClkIn(1)   => smclk_divider(0),    -- Divide by 2
        ClkIn(2)   => smclk_divider(1),    -- Divide by 4
        ClkIn(3)   => smclk_divider(2),    -- Divide by 8
        ClkIn(4)   => smclk_divider(3),    -- Divide by 16
        ClkIn(5)   => smclk_divider(4),    -- Divide by 32
        ClkIn(6)   => smclk_divider(5),    -- Divide by 64
        ClkIn(7)   => smclk_divider(6),    -- Divide by 128

        ClkEn      => smclk_en_out, --TODO, put in status register or as interrupt

        ClkOut     => smclk
    );

    cg_smclk: entity work.ClkGate
        port map
        (
            ClkIn   => smclk,
            En      => not smclk_off,
            ClkOut  => smclk_out
        );

    -- mclk mux and divider 
    mclk_mux: entity work.ClockMuxGlitchFree
    generic map
    (
        CLK_COUNT  => 4,
        SEL_WIDTH  => 2,
        CLK_DEFAULT => 0
    )
    port map
    (
        resetn     => resetn_sys,
        Sel        => mclk_sel,

        ClkIn(0)   => clk_hfxt,
        ClkIn(1)   => smclk,
        ClkIn(2)   => clk_dco0,
        ClkIn(3)   => clk_dco1,

        ClkEn(0)   => sel_hfxt_as_mclk,
        ClkEn(1)   => open,
        ClkEn(2)   => sel_dco0_as_mclk,
        ClkEn(3)   => sel_dco1_as_mclk,

        ClkOut     => mclk_undiv
    );

    mclk_div_proc: process(resetn_sys, mclk_undiv, mclk_div)
    begin
        -- TODO: Implement a sort of timer that will disable mclk_divider if not needed (some time after mclk_div goes to 0)
        -- if resetn_sys = '0' or mclk_div = "000" then
        if resetn_sys = '0' then
            mclk_divider <= (others => '0');
        elsif rising_edge(mclk_undiv) then
            mclk_divider <= mclk_divider + 1;
        end if;
    end process;

    mclk_div_mux: entity work.ClockMuxGlitchFree
    generic map
    (
        CLK_COUNT  => 8,
        SEL_WIDTH  => 3,
        CLK_DEFAULT => 0
    )
    port map
    (
        resetn     => resetn_sys,
        Sel        => mclk_div,

        ClkIn(0)   => mclk_undiv,         -- Divide by 1 (no division)
        ClkIn(1)   => mclk_divider(0),    -- Divide by 2
        ClkIn(2)   => mclk_divider(1),    -- Divide by 4
        ClkIn(3)   => mclk_divider(2),    -- Divide by 8
        ClkIn(4)   => mclk_divider(3),    -- Divide by 16
        ClkIn(5)   => mclk_divider(4),    -- Divide by 32
        ClkIn(6)   => mclk_divider(5),    -- Divide by 64
        ClkIn(7)   => mclk_divider(6),    -- Divide by 128

        ClkEn      => open, 

        ClkOut     => mclk
    );

    mclk_out <= mclk;

    --Additional signal routing 
    -- PGEN_rom <= rom_off;
    PGEN_mem <= ram_off & rom_off;

    -- IRQ Signals 
    irq_en <= SYS_IRQ_EN when irq_gen = '1' else (others => '0');
    irq_priority <= SYS_IRQ_PRI;
    -- irq_sys <= wdt_if;
    irq_sys_wdt <= '0'; -- TODO: For now zero

    -- CRC Logic

    CRC0: entity work.CRC16
    generic map
    (
        POLYNOMIAL  => X"C857"
    )
    port map
    (
        DataIn      => SYS_CRC_DATA,
        CrcOld      => crc_prev,
        CrcOut      => SYS_CRC_STATE
    );

    -- =============================================================================
    -- Memory-Mapped Register Interface
    -- =============================================================================
    en_addr_periph <= slv2uint(addr_periph) when en_mem = '0' else 0;

    -- Register Write Process 
    reg_write_proc: process(resetn_sys, clk_mem, en_mem)
    begin
        if resetn_sys = '0' then
            crc_prev        <= (others => '1');
            first_crc_flag  <= '0';

            SYS_CLK_CR      <= (others => '0');
            SYS_CLK_DIV_CR  <= (others => '0');
            SYS_BLOCK_PWR   <= (others => '0'); 
            SYS_IRQ_EN      <= (others => '0'); 
            SYS_WDT_CR      <= (others => '0');
            SYS_IRQ_PRI     <= (others => '0');
            DCO0_BIAS       <= DCO0_BIAS_DEFAULT;
            DCO1_BIAS       <= DCO1_BIAS_DEFAULT;
            
        elsif rising_edge(clk_mem) then
            if en_mem = '0' then
                case en_addr_periph is
                   when RegSlotSYS_CLK_CR =>
                        if wen(0) = '0' then
                            SYS_CLK_CR(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_CLK_CR(SYS_CLK_CR'high downto 8) <= write_data(SYS_CLK_CR'high downto 8);
                        end if;
                    when RegSlotSYS_CLK_DIV_CR =>
                        if wen(0) = '0' then
                            SYS_CLK_DIV_CR(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when RegSlotSYS_BLOCK_PWR =>
                        if wen(0) = '0' then
                            SYS_BLOCK_PWR <= write_data(SYS_BLOCK_PWR'high downto 0);
                        end if;
                    when RegSlotSYS_CRC_DATA =>
                        if wen(0) = '0' then
                            SYS_CRC_DATA <= write_data(7 downto 0);
                            crc_prev <= (others => '1');
                            if first_crc_flag = '0' then
                                crc_prev <= SYS_CRC_STATE;
                            end if;
                            first_crc_flag <= '0';
                        end if;
                    when RegSlotSYS_CRC_STATE =>
                        if wen(0) = '0' then
                            crc_prev(7 downto 0) <= write_data(7 downto 0);
                            first_crc_flag <= '1';
                        end if;
                        if wen(1) = '0' then
                            crc_prev(15 downto 8) <= write_data(15 downto 8);
                            first_crc_flag <= '1';
                        end if;
                    when RegSlotSYS_IRQ_ENL =>
                        if wen(0) = '0' then
                            SYS_IRQ_EN(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_IRQ_EN(15 downto 8) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SYS_IRQ_EN(23 downto 16) <= write_data(23 downto 16);
                        end if;
                        if wen(3) = '0' then
                            SYS_IRQ_EN(31 downto 24) <= write_data(31 downto 24);
                        end if;
                    when RegSlotSYS_IRQ_ENM =>
                        if wen(0) = '0' then
                            SYS_IRQ_EN(39 downto 32) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_IRQ_EN(47 downto 40) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SYS_IRQ_EN(55 downto 48) <= write_data(23 downto 16);
                        end if;
                        if wen(3) = '0' then
                            SYS_IRQ_EN(63 downto 56) <= write_data(31 downto 24);
                        end if;
                    when RegSlotSYS_IRQ_ENU =>
                        if wen(0) = '0' then
                            SYS_IRQ_EN(71 downto 64) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_IRQ_EN(79 downto 72) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SYS_IRQ_EN(NUM_IRQS-1 downto 80) <= write_data(NUM_IRQS-64+7 downto 24);
                        end if;
                    when RegSlotSYS_IRQ_PRIL =>
                        if wen(0) = '0' then
                            SYS_IRQ_PRI(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_IRQ_PRI(15 downto 8) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SYS_IRQ_PRI(23 downto 16) <= write_data(23 downto 16);
                        end if;
                        if wen(3) = '0' then
                            SYS_IRQ_PRI(31 downto 24) <= write_data(31 downto 24);
                        end if;
                    when RegSlotSYS_IRQ_PRIM =>
                        if wen(0) = '0' then
                            SYS_IRQ_PRI(39 downto 32) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_IRQ_PRI(47 downto 40) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SYS_IRQ_PRI(55 downto 48) <= write_data(23 downto 16);
                        end if;
                        if wen(3) = '0' then
                            SYS_IRQ_PRI(63 downto 56) <= write_data(31 downto 24);
                        end if;
                    when RegSlotSYS_IRQ_PRIU =>
                        if wen(0) = '0' then
                            SYS_IRQ_PRI(71 downto 64) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SYS_IRQ_PRI(79 downto 72) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            SYS_IRQ_PRI(NUM_IRQS-1 downto 80) <= write_data(NUM_IRQS-64+7 downto 24);
                        end if;
                    when RegSlotSYS_IRQ_CR =>
                        if wen(0) = '0' then
                            SYS_IRQ_CR <= write_data(SYS_IRQ_CR'high downto SYS_IRQ_CR'low);
                        end if;
                    when RegSlotSYS_WDT_CR =>
                        if unlocked = '1' and wen(0) = '0' then
                            SYS_WDT_CR(SYS_WDT_CR'high downto 0) <= write_data(SYS_WDT_CR'high downto 0);
                        end if;
                    when RegSlotSYS_WDT_SR =>
                        -- Writing to SR clears flags
                        if wen(0) = '0' then
                            if write_data(0) = '1' then
                                clr_wdt_rf <= '1';
                            end if;
                            if write_data(1) = '1' then
                                clr_wdt_if <= '1';
                            end if;
                        end if;
                    when RegSlotSYS_WDT_PASS =>
                        if wen = "0000" then 
                            if write_data = WDT_UNLCK_PASSWD then
                                unlock <= '1';
                            end if;
                            if write_data = WDT_CLR_PASSWD then
                                clr_wdt <= '1';
                            end if;
                        end if;
                    when RegSlotDCO0_BIAS =>
                        if wen(0) = '0' then
                            DCO0_BIAS(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            DCO0_BIAS(DCO0_BIAS'high downto 8) <= write_data(DCO0_BIAS'high downto 8);
                        end if;
                    when RegSlotDCO1_BIAS =>
                        if wen(0) = '0' then
                            DCO1_BIAS(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            DCO1_BIAS(DCO1_BIAS'high downto 8) <= write_data(DCO1_BIAS'high downto 8);
                        end if;
                    when others =>
                        null;
                end case;
            end if;
        end if;

        if resetn_sys = '0' or en_mem = '1' then
            unlock <= '0';
            clr_wdt <= '0';
            clr_wdt_rf <= '0';
            clr_wdt_if <= '0';
        end if;
    end process;




    -- Register Read Process 
    -- TODO: Fix this process for register sizing 
    reg_read_proc: process(clk_mem)
    begin
        if rising_edge(clk_mem) then
            case en_addr_periph is
                when RegSlotSYS_CLK_CR =>
                    read_data <= (others => '0');
                    read_data(SYS_CLK_CR'high downto SYS_CLK_CR'low) <= SYS_CLK_CR;
                when RegSlotSYS_CLK_DIV_CR =>
                    read_data <= (others => '0');
                    read_data(SYS_CLK_DIV_CR'high downto SYS_CLK_DIV_CR'low) <= SYS_CLK_DIV_CR;
                when RegSlotSYS_BLOCK_PWR =>
                    read_data <= (others => '0');
                    read_data(SYS_BLOCK_PWR'high downto SYS_BLOCK_PWR'low) <= SYS_BLOCK_PWR;
                when RegSlotSYS_CRC_DATA =>
                    read_data <= (others => '0');
                    read_data(SYS_CRC_DATA'high downto SYS_CRC_DATA'low) <= SYS_CRC_DATA;
                when RegSlotSYS_CRC_STATE =>
                    read_data <= (others => '0');
                    read_data(SYS_CRC_STATE'high downto SYS_CRC_STATE'low) <= SYS_CRC_STATE;
                when RegSlotSYS_IRQ_ENL =>
                    read_data <= (others => '0');
                    read_data <= SYS_IRQ_EN(31 downto 0);
                when RegSlotSYS_IRQ_ENM =>
                    read_data <= (others => '0');
                    read_data <= SYS_IRQ_EN(63 downto 32);
                when RegSlotSYS_IRQ_ENU => --TODO: Check sizing 
                    read_data <= (others => '0');
                    read_data(NUM_IRQS-64-1 downto 0) <= SYS_IRQ_EN(NUM_IRQS-1 downto 64);
                when RegSlotSYS_IRQ_PRIL =>
                    read_data <= (others => '0');
                    read_data <= SYS_IRQ_PRI(31 downto 0);
                when RegSlotSYS_IRQ_PRIM =>
                    read_data <= (others => '0');
                    read_data <= SYS_IRQ_PRI(63 downto 32);
                when RegSlotSYS_IRQ_PRIU => --TODO: Check sizing
                    read_data <= (others => '0');
                    read_data(NUM_IRQS-64-1 downto 0) <= SYS_IRQ_PRI(NUM_IRQS-1 downto 64);
                when RegSlotSYS_IRQ_CR =>
                    read_data <= (others => '0');
                    read_data(SYS_IRQ_CR'high downto SYS_IRQ_CR'low) <= SYS_IRQ_CR;
                when RegSlotSYS_WDT_CR =>
                    read_data <= (others => '0');
                    read_data(SYS_WDT_CR'high downto SYS_WDT_CR'low) <= SYS_WDT_CR;
                when RegSlotSYS_WDT_SR =>
                    read_data <= (others => '0');
                    read_data(SYS_WDT_SR'high downto SYS_WDT_SR'low) <= SYS_WDT_SR;
                when RegSlotSYS_WDT_VAL =>
                    read_data <= (others => '0');
                    read_data(SYS_WDT_VAL'high downto SYS_WDT_VAL'low) <= SYS_WDT_VAL;
                when RegSlotDCO0_BIAS =>
                    read_data <= (others => '0');
                    read_data(DCO0_BIAS'high downto DCO0_BIAS'low) <= DCO0_BIAS;
                when RegSlotDCO1_BIAS =>
                    read_data <= (others => '0');
                    read_data(DCO1_BIAS'high downto DCO1_BIAS'low) <= DCO1_BIAS;
                when others =>
                    read_data <= (others => '0');
            end case;
        end if;
    end process;

end rtl;
