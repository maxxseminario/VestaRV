-- VestaRV: system controller
-- Clock, reset, CRC and watchdog monarchy: selects and divides mclk/smclk from LFXT, HFXT and the two DCOs, owns resetn_sys, trims the DCO bias, and gates the memory banks.
-- Gating a memory bank loses its contents; there is no retention, so running software must keep its stack and payload bank on.
-- IRQ routing and masking live in the irq_router rows at 0x7000, not here: the SYS_IRQ_EN/PRI/CR slots are reserved, writes ignored and reads 0.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
-- Word offsets, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/system.rdl, which replaces the work.MemoryMap clause (both would make every slot name an ambiguous homograph).
use work.system_regs_pkg.all;

entity SYSTEM is
    -- SYSTEM owns the clock, reset, CRC and watchdog monarchy; ALL peripheral IRQ routing and masking lives in the irq_router's per-hart rows at 0x7000.
    -- The SYS_IRQ_EN/PRI/CR slots are therefore reserved here: writes are ignored and reads return 0.
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

        -- Interrupt signals: the WDT is the only source SYSTEM raises.
        -- The WDT level into the deglitch chain (source 0 = IRQB_SYS_WDT): wdt_if AND wdt_ie, cleared by the WDT_SR write-1-to-clear.
        irq_sys_wdt     : out std_logic;
        -- wdt_irq_routed: source 0 is enabled in SOME hart's router row, which arms the reset-on-undeliverable path.
        -- wdt_irq_complete: 1-mclk COMPLETE(0) pulse, the WDT end-of-interrupt, no matter WHICH hart serviced it.
        wdt_irq_routed   : in  std_logic := '0';
        wdt_irq_complete : in  std_logic := '0';

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

        -- Memory power gating, one bit per block: 0 = ROM, 1 = hart 0 TCM (RAM0), 2 = npuram (RAM1), 6:3 = shared bulk-RAM banks shbank0-3; any further banks stay hardwired ON at the MCU level.
        -- CONTENTS ARE LOST when a bank is gated (there is no retention), so running software must keep its stack and payload bank ON.
        PGEN_mem        : out std_logic_vector(6 downto 0) -- '0' mem on, '1' mem off

    );
end SYSTEM;

architecture rtl of SYSTEM is

    -- Registers 
    signal SYS_CLK_CR         : std_logic_vector(8 downto 0);
    signal SYS_CLK_DIV_CR     : std_logic_vector(5 downto 0);
    signal SYS_BLOCK_PWR      : std_logic_vector(6 downto 0);  -- 6:3 = shbank0-3 off
    signal SYS_CRC_DATA       : std_logic_vector(7 downto 0);
    signal SYS_CRC_STATE      : std_logic_vector(15 downto 0);
    -- No SYS_IRQ_EN / SYS_IRQ_PRI / SYS_IRQ_CR registers: the irq_router rows own routing and masking chip-wide, and priority is fixed lowest-ID.
    signal SYS_WDT_CR         : std_logic_vector(7 downto 0);
    signal SYS_WDT_SR         : std_logic_vector(1 downto 0);
    signal SYS_WDT_VAL        : std_logic_vector(23 downto 0);

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
    signal shb_off            : std_logic_vector(3 downto 0);  -- shbank0-3 off

    --SYS_WDT_CR
    signal wdt_en             : std_logic;
    signal wdt_ie             : std_logic;
    signal wdt_cdiv           : std_logic_vector(3 downto 0); --mclk divider for wdt
    signal wdt_hwrst          : std_logic;

    -- SYS_WDT_SR
    signal wdt_rf             : std_logic;
    signal wdt_if             : std_logic;

    -- Memory Interface Signals
    -- The bus side is one periph_regs instance driven by system_regs_pkg's SPARSE
    -- tables: eleven registers over eighteen words, with the seven retired
    -- SYS_IRQ slots emitted as all-zero _reserved_ rows that store nothing and
    -- read 0. See hdl/common/regs/REGFILE.md.
    signal regs_q             : reg_arr_t;                       -- the stored words
    signal hw_rd_s            : reg_arr_t;                       -- the read source for the words this module does not store
    signal w1c_s              : reg_arr_t;                       -- a 1 written to a WDT_SR flag
    signal acc_s              : std_logic_vector(0 to NWORDS-1); -- combinational: this slot is addressed now
    signal wr_str             : std_logic_vector(0 to NWORDS-1);
    signal wr_inh             : std_logic_vector(0 to NWORDS-1); -- per word: refuse the write

    -- Zero-extend a register field to a bus word.
    function pad(v : std_logic_vector) return word is
        variable r : word := (others => '0');
    begin
        r(v'length - 1 downto 0) := v;
        return r;
    end function;

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
    signal wdt_rst_cond       : std_logic;
    signal wdt_rst_req        : std_logic;
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
    -- The six stored registers are periph_regs' storage; every field slice below
    -- is the package's, so no bit literal in this file describes a register.
    SYS_CLK_CR     <= regs_q(RegSlotSYS_CLK_CR)(SYS_CLK_CR'range);
    SYS_CLK_DIV_CR <= regs_q(RegSlotSYS_CLK_DIV_CR)(SYS_CLK_DIV_CR'range);
    SYS_BLOCK_PWR  <= regs_q(RegSlotSYS_BLOCK_PWR)(SYS_BLOCK_PWR'range);
    SYS_CRC_DATA   <= regs_q(RegSlotSYS_CRC_DATA)(SYS_CRC_DATA'range);
    SYS_WDT_CR     <= regs_q(RegSlotSYS_WDT_CR)(SYS_WDT_CR'range);
    DCO0_BIAS      <= regs_q(RegSlotDCO0_BIAS)(SYSDCO0BIAS_MSB downto SYSDCO0BIAS_LSB);
    DCO1_BIAS      <= regs_q(RegSlotDCO1_BIAS)(SYSDCO1BIAS_MSB downto SYSDCO1BIAS_LSB);

    dco1_on       <= SYS_CLK_CR(DCO1ON_LSB);
    dco0_on       <= SYS_CLK_CR(DCO0ON_LSB);
    clk_hfxt_off  <= SYS_CLK_CR(HFXTOFF_LSB);
    clk_lfxt_off  <= SYS_CLK_CR(LFXTOFF_LSB);
    smclk_off     <= SYS_CLK_CR(SMCLKOFF_LSB);
    smclk_sel     <= SYS_CLK_CR(SMCLKSEL_MSB downto SMCLKSEL_LSB);
    mclk_sel      <= SYS_CLK_CR(MCLKSEL_MSB downto MCLKSEL_LSB);

    smclk_div     <= SYS_CLK_DIV_CR(SYSSMCLKDIV_MSB downto SYSSMCLKDIV_LSB);
    mclk_div      <= SYS_CLK_DIV_CR(SYSMCLKDIV_MSB downto SYSMCLKDIV_LSB);

    ram_off       <= SYS_BLOCK_PWR(SYSRAM1OFF_MSB downto SYSRAM0OFF_LSB);
    rom_off       <= SYS_BLOCK_PWR(SYSROMOFF_LSB);
    shb_off       <= SYS_BLOCK_PWR(SYSSHB3OFF_MSB downto SYSSHB0OFF_LSB);  -- shared bulk-RAM banks

    wdt_en        <= SYS_WDT_CR(SYSWDTEN_LSB);
    wdt_cdiv      <= SYS_WDT_CR(SYSWDTCDIV_MSB downto SYSWDTCDIV_LSB);
    wdt_ie        <= SYS_WDT_CR(SYSWDTIE_LSB);
    wdt_hwrst     <= SYS_WDT_CR(SYSWDTHWRST_LSB);

    SYS_WDT_SR    <= (
        SYSWDTRF_LSB => wdt_rf,
        SYSWDTIF_LSB => wdt_if
    );

    -- Assign Outputs 
    clk_lfxt_out    <= clk_lfxt;
    clk_hfxt_out    <= clk_hfxt;


    -- Two-stage release of the system reset: any of POR, a WDT reset or the WDT hardware-reset bit forces it low asynchronously.
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



    -- Watchdog timer


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
            -- Detect a rising edge on the selected counter bit, which is the WDT event.
            -- wdt_bit_prev must still hold the PREVIOUS sample at this compare: refresh it first and prev equals current, so the edge never fires.
            if wdt_bit_prev = '0' and SYS_WDT_VAL(slv2uint(wdt_cdiv)) = '1' then
                -- Set interrupt flag on WDT timeout
                wdt_if <= '1';

                -- Generate the trigger pulse if interrupts are enabled; delivery masking is the router row's job, not SYSTEM's.
                if wdt_ie = '1' then
                    wdt_trigger <= '1';
                end if;
            else
                -- Clear trigger after one cycle (pulse)
                wdt_trigger <= '0';
            end if;

            -- Store state of the watched bit for the next edge's comparison
            wdt_bit_prev := SYS_WDT_VAL(slv2uint(wdt_cdiv));

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



    -- The WDT end-of-interrupt is the irq_router's COMPLETE(0) pulse, an mclk-domain strobe from WHICHEVER hart completed the WDT claim.
    -- Qualified by wdt_if (the pending LEVEL), not by the trigger pulse.
    wdt_eoi_proc: process(resetn_sys, mclk)
    begin
        if resetn_sys = '0' then
            wdt_interrupt_ret <= '0';
        elsif rising_edge(mclk) then
            if wdt_irq_complete = '1' and wdt_if = '1' then
                wdt_interrupt_ret <= '1';
            end if;
        end if;
    end process;

    -- The WDT reset fires when the timeout interrupt is undeliverable ANYWHERE (interrupts off or no router row enables source 0), or after its end-of-interrupt.
    wdt_rst_cond <= '1' when wdt_en = '1' and wdt_trigger = '1' and
                    (wdt_ie = '0' or wdt_irq_routed = '0' or
                    (wdt_ie = '1' and wdt_interrupt_ret = '1'))
                    else '0';

    -- The request is REGISTERED before it becomes resetn_wdt, so the reset is one mclk wide.
    -- Driven combinationally it closed a loop through resetn_sys onto wdt_trigger's asynchronous clear and collapsed to a few gate delays, and the flag below was clocked by that runt.
    -- resetn_por, not resetn_sys, resets this flop: the reset it requests must not retire the request.
    wdt_rst_req_proc: process(resetn_por, mclk)
    begin
        if resetn_por = '0' then
            wdt_rst_req <= '0';
        elsif rising_edge(mclk) then
            wdt_rst_req <= wdt_rst_cond;
        end if;
    end process;

    resetn_wdt <= not wdt_rst_req;

    -- WDT reset flag: set on mclk while the request stands, cleared by POR or a WDT_SR write-1-to-clear.
    -- Setting it again while the same request stands is idempotent, so no edge detector is needed.
    wdt_rf_proc: process(resetn_por, clr_wdt_rf, mclk)
    begin
        if resetn_por = '0' or clr_wdt_rf = '1' then
            wdt_rf <= '0';
        elsif rising_edge(mclk) then
            if wdt_rst_req = '1' then
                wdt_rf <= '1';
            end if;
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

    -- After unlocking the WDT you have 64 mclk cycles to do something.
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

    -- smclk_divider increments on the FALLING edge of smclk_undiv so the divider outputs never toggle at the instant smclk_div (written on a rising mclk edge) changes the mux selector; do not move it to the rising edge.
    -- smclk_div crosses into the switched clock, and ClockMuxGlitchFree's per-slice DFF chain plus its break-before-make interlock IS the synchronizer: a 2-FF sync would be wrong, since the bus could pass incoherent intermediate codes and the destination is the very clock being switched, and clocks are only reconfigured while the smclk peripherals are quiesced.

    -- Free-running ripple divider feeding the smclk divider mux; held cleared when smclk is off or undivided.
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

    -- Free-running ripple divider feeding the mclk divider mux.
    mclk_div_proc: process(resetn_sys, mclk_undiv, mclk_div)
    begin
        -- TODO: Implement a sort of timer that will disable mclk_divider if not needed (some time after mclk_div goes to 0)
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
    PGEN_mem <= shb_off & ram_off & rom_off;  -- 6:3 = shbank0-3

    -- WDT interrupt level = pending flag AND interrupt mode, cleared by the WDT_SR write-1-to-clear as the ISR's clear-at-the-peripheral step.
    -- It stays masked chip-wide until software routes source 0 in an irq_router row.
    irq_sys_wdt <= wdt_if and wdt_ie;

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

    -- Memory-Mapped Register Interface
    -- One periph_regs instance replaces the slot decode, the byte-lane write case,
    -- the write-1-to-clear arm and the registered read mux. The tables are
    -- SPARSE: words 5-11, the retired SYS_IRQ_EN/PRI/CR slots, are all-zero
    -- _reserved_ rows, which is the `when others` arm this deletes.
    --
    -- Two per-word write qualifiers the description cannot state:
    --   FULLWR on WDT_PASS, because a password compared a byte at a time is a
    --   password guessed a byte at a time;
    --   wr_inhibit on WDT_CR, because its write is live state -- it lands only
    --   inside the 64-cycle window a correct password opens.
    --
    -- STROBE_HOLD is TRUE: unlock, clr_wdt and the two flag clears are level
    -- inputs to processes on clk_wdt and clk_unlock and must last the whole
    -- select window, which is what `if en_mem = '1' then <strobe> <= '0'` said.
    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NWORDS,
            RSTVAL      => RSTVAL,
            IMPL        => IMPL,
            W1C         => W1C,
            WOSET       => WOSET,
            WOT         => WOT,
            PULSE       => PULSE,
            RCLR        => RCLR,
            HWOWN       => HWOWN,
            -- CRC_STATE is sw=rw storage whose READ is the CRC engine's output.
            -- WDT_PASS is sw=w, so IMPL already gives it no storage and no read;
            -- its row is kept because RDTHRU is where this file states the intent.
            RDTHRU      => "000010000000100000",
            FULLWR      => "000000000000100000",
            STROBE_HOLD => true)
        port map (
            ClkMem      => clk_mem,
            resetn      => resetn_sys,
            EnMemPeriph => en_mem,
            WEn         => wen,
            MABPart     => addr_periph,
            wdata       => write_data,
            rdata_out   => read_data,
            regs        => regs_q,
            wr_inhibit  => wr_inh,
            hw_rd       => hw_rd_s,
            acc_hit     => acc_s,
            rd_strobe   => open,
            wr_strobe   => wr_str,
            wr_pulse    => open,
            w1c_hit     => w1c_s,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    -- The four words whose read value is not this module's storage. WDT_PASS is
    -- absent on purpose: it reads 0, which an RDTHRU word with no hw_rd row does.
    hw_rd_s <= (RegSlotSYS_CRC_STATE => pad(SYS_CRC_STATE),
                RegSlotSYS_WDT_SR    => pad(SYS_WDT_SR),
                RegSlotSYS_WDT_VAL   => pad(SYS_WDT_VAL),
                others               => (others => '0'));

    -- WDT_CR takes a write only while the unlock window is open.
    wr_inh <= (RegSlotSYS_WDT_CR => not unlocked, others => '0');

    -- The two passwords. wr_strobe is already qualified on the full-word write by
    -- FULLWR above, and write_data holds for the select window, so this level is
    -- exactly the flop the case arm used to set and deselect used to clear.
    unlock  <= '1' when wr_str(RegSlotSYS_WDT_PASS) = '1'
                    and write_data = WDT_UNLCK_PASSWD else '0';
    clr_wdt <= '1' when wr_str(RegSlotSYS_WDT_PASS) = '1'
                    and write_data = WDT_CLR_PASSWD   else '0';

    -- The two status flags are hardware's, so their flops stay with the hardware
    -- that sets them and periph_regs only reports the written 1.
    clr_wdt_rf <= w1c_s(RegSlotSYS_WDT_SR)(SYSWDTRF_LSB);
    clr_wdt_if <= w1c_s(RegSlotSYS_WDT_SR)(SYSWDTIF_LSB);

    -- The CRC chain: a data-byte write advances it, a state write restarts it.
    -- Both are write side effects on the ENGINE, not on storage, so they take the
    -- unregistered hook with their own lanes, exactly as the case arms did.
    crc_proc: process(resetn_sys, clk_mem)
    begin
        if resetn_sys = '0' then
            crc_prev        <= (others => '1');
            -- Reset is the 0xFFFF seed write the documented sequence opens with, so
            -- the flag resets SET: the first byte after reset folds against crc_prev
            -- and not against the reset CRCDATA of 0x00, which the running arm would
            -- otherwise drag in.
            first_crc_flag  <= '1';
        elsif rising_edge(clk_mem) then
            -- Feeding a data byte advances the CRC. On the FIRST byte after a seed
            -- write crc_prev already holds the seed, so it is HELD: the running arm
            -- would fold in the previous CRCDATA byte, which is not part of this
            -- message. Every later byte takes the running arm.
            if acc_s(RegSlotSYS_CRC_DATA) = '1' and wen(0) = '0' then
                if first_crc_flag = '0' then
                    crc_prev <= SYS_CRC_STATE;
                end if;
                first_crc_flag <= '0';
            end if;
            -- Writing the state seeds the CRC for the next data byte.
            if acc_s(RegSlotSYS_CRC_STATE) = '1' then
                if wen(0) = '0' then
                    crc_prev(7 downto 0) <= write_data(7 downto 0);
                    first_crc_flag <= '1';
                end if;
                if wen(1) = '0' then
                    crc_prev(15 downto 8) <= write_data(15 downto 8);
                    first_crc_flag <= '1';
                end if;
            end if;
        end if;
    end process;

end rtl;
