-------------------------------------------------------------------------------
-- DMA_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the DMA controller peripheral.
-- The DUT is declared as a COMPONENT, not an entity instantiation, so the bench compiles standalone before DMA.vhd exists; default binding resolves it once DMA.vhd is in the work library.
-- Uses periph_tb_pkg (scoreboard + register-bus BFM), dma_bfm_pkg (slot/CR/SR/CFG constants, packers, deny/hole addresses, the independent CRC reference, bounded SR polls) and the local dma_arb_model.
-- ONE clock family: clk hosts the transfer engine, master-port FSM, CRC and pacing sync, and ClkMem is that same clock gated by the bus select.
-- Checker independence: reference dest words and CRC come from what the bench programmed or poked, never from a DUT internal, and the modeled M_CLR targets (QSPI0SR 0x4C14, NFC0SR 0x6204) are a DUT-vs-bench contract.
-------------------------------------------------------------------------------

-- =============================================================================
-- dma_arb_model : cycle-accurate mp_arbiter-plus-shared-slave model, with the modeled RAM, pacing windows and a master-port protocol monitor.
-- 3-edge IDLE/LATCH/DATA shape, and wait-for-release: a served master is masked until its req is observed low, so a req held across two words is never re-served.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;
use work.dma_bfm_pkg.all;

entity dma_arb_model is
    generic (
        AW        : natural := 15;
        RAM_WORDS : natural := 16#5000#;
        RAISE     : natural := 3            -- cycles to (re)raise a ready level
    );
    port (
        clk     : in  std_logic;
        resetn  : in  std_logic;
        -- DUT master port (from DMA slice 4)
        m_req   : in  std_logic;
        m_we    : in  std_logic_vector(3 downto 0);
        m_addr  : in  std_logic_vector(AW-1 downto 0);
        m_wdata : in  std_logic_vector(31 downto 0);
        m_gnt   : out std_logic;
        m_done  : out std_logic;
        m_rdata : out std_logic_vector(31 downto 0);
        -- modeled data-ready trigger LEVELS (to the DUT trig_* inputs)
        trig_uart : out std_logic;
        trig_qspi : out std_logic;
        trig_nfc  : out std_logic;
        -- pacing control (from stim): 1-cycle pulse (re)starts a source stream
        arm_uart  : in  std_logic;
        arm_qspi  : in  std_logic;
        arm_nfc   : in  std_logic;
        -- backdoor RAM access (from stim): poke to init src; bd_rdata to peek dst
        bd_addr   : in  std_logic_vector(AW-1 downto 0);
        bd_poke   : in  std_logic;
        bd_wdata  : in  std_logic_vector(31 downto 0);
        bd_rdata  : out std_logic_vector(31 downto 0);
        -- observation (all checker-independent model state)
        prot_err       : out std_logic;
        denied_hits    : out natural;   -- READ accesses seen to a deny word (>0 = DUT failed to suppress)
        uart_reads     : out natural;   -- UART RX reads since last arm_uart
        nfc_reads      : out natural;   -- NFC DATA reads since last arm_nfc
        qspi_sr_obs    : out std_logic_vector(7 downto 0);   -- modeled QSPI SR
        qspi_clr_wdata : out std_logic_vector(31 downto 0)   -- last write to QSPI SR
    );
end entity dma_arb_model;

architecture model of dma_arb_model is

    type state_t is (A_IDLE, A_LATCH, A_DATA);
    signal state : state_t := A_IDLE;

    -- latched access presented to the slave
    signal a_addr  : std_logic_vector(AW-1 downto 0) := (others => '0');
    signal a_we    : std_logic_vector(3 downto 0)    := (others => '0');
    signal a_wdata : std_logic_vector(31 downto 0)   := (others => '0');
    signal s_rdata : std_logic_vector(31 downto 0)   := (others => '0');
    signal need_release : std_logic := '0';
    signal gnt_i, done_i : std_logic := '0';

    -- modeled shared RAM (single driver = the model process; bd_rdata reads it)
    type ram_t is array(0 to RAM_WORDS-1) of std_logic_vector(31 downto 0);
    signal mem : ram_t := (others => (others => '0'));

    -- modeled pacing sources
    signal uart_ready, qspi_ready, nfc_ready : std_logic := '0';
    signal uart_byte  : unsigned(7 downto 0) := (others => '0');
    signal qspi_val   : unsigned(7 downto 0) := (others => '0');
    signal uart_rl, qspi_rl, nfc_rl : natural := 0;
    signal nfc_idx    : natural := 0;
    signal qspi_sr_i  : std_logic_vector(7 downto 0) := DMA_QSPI_SR_OTHER;
    signal qspi_clr_i : std_logic_vector(31 downto 0) := (others => '0');

    signal denied_i    : natural := 0;
    signal uart_rd_cnt : natural := 0;
    signal nfc_rd_cnt  : natural := 0;
    signal prot_i      : std_logic := '0';

    -- fixed word indices of the modeled windows / deny addresses
    constant UART_RX_W  : natural := dma_word_idx(DMA_UART_RX_BYTE);
    constant QSPI_RX_W  : natural := dma_word_idx(DMA_QSPI_RX_BYTE);
    constant QSPI_SR_W  : natural := dma_word_idx(DMA_QSPI_SR_BYTE);
    constant NFC_DATA_W : natural := dma_word_idx(DMA_NFC_DATA_BYTE);
    constant NFC_SR_W   : natural := dma_word_idx(DMA_NFC_SR_BYTE);
    constant MUTEX_LO_W : natural := dma_word_idx(DMA_MUTEX_LO_BYTE);
    constant MUTEX_HI_W : natural := dma_word_idx(DMA_MUTEX_HI_BYTE);
    constant ROUTER_W   : natural := dma_word_idx(DMA_ROUTER_CLAIM);

    function is_deny_read(idx : natural; we : std_logic_vector(3 downto 0)) return boolean is
    begin
        if we /= "0000" then return false; end if;   -- the guard blocks READS only
        if idx >= MUTEX_LO_W and idx <= MUTEX_HI_W then return true; end if;
        if idx = ROUTER_W then return true; end if;
        return false;
    end function;

begin

    -- ---- outputs (continuous) ---------------------------------------------
    m_gnt   <= gnt_i;
    m_done  <= done_i;
    m_rdata <= s_rdata;
    trig_uart <= uart_ready;
    trig_qspi <= qspi_ready;
    trig_nfc  <= nfc_ready;
    bd_rdata  <= mem(to_integer(unsigned(bd_addr)) mod RAM_WORDS);
    prot_err  <= prot_i;
    denied_hits    <= denied_i;
    uart_reads     <= uart_rd_cnt;
    nfc_reads      <= nfc_rd_cnt;
    qspi_sr_obs    <= (qspi_sr_i(7 downto 3) & qspi_ready & qspi_sr_i(1 downto 0));  -- bit 2 = rxfull
    qspi_clr_wdata <= qspi_clr_i;

    -- =======================================================================
    -- Arbiter FSM plus slave (RAM + pacing windows), backdoor, and pacing counters.
    -- This single rising-clk process is the sole driver of mem: DUT writes and backdoor pokes both flow through here.
    -- =======================================================================
    proc: process(clk, resetn)
        variable idx : natural;
    begin
        if resetn = '0' then
            state <= A_IDLE;
            gnt_i <= '0'; done_i <= '0';
            need_release <= '0';
            s_rdata <= (others => '0');
            uart_ready <= '0'; qspi_ready <= '0'; nfc_ready <= '0';
            uart_rl <= 0; qspi_rl <= 0; nfc_rl <= 0;
            uart_byte <= (others => '0'); qspi_val <= (others => '0');
            nfc_idx <= 0; qspi_sr_i <= DMA_QSPI_SR_OTHER;
            qspi_clr_i <= (others => '0');
            denied_i <= 0; uart_rd_cnt <= 0; nfc_rd_cnt <= 0;
        elsif rising_edge(clk) then
            done_i <= '0';   -- one-cycle strobe default

            ---------------------------------------------------------------
            -- backdoor poke (stim drives bd_* while the DUT is idle)
            ---------------------------------------------------------------
            if bd_poke = '1' then
                mem(to_integer(unsigned(bd_addr)) mod RAM_WORDS) <= bd_wdata;
            end if;

            ---------------------------------------------------------------
            -- pacing re-raise countdowns + arm (re)starts
            ---------------------------------------------------------------
            if uart_rl = 1 then uart_ready <= '1'; uart_rl <= 0;
            elsif uart_rl > 1 then uart_rl <= uart_rl - 1; end if;
            if qspi_rl = 1 then qspi_ready <= '1'; qspi_rl <= 0;
            elsif qspi_rl > 1 then qspi_rl <= qspi_rl - 1; end if;
            if nfc_rl = 1 then nfc_ready <= '1'; nfc_rl <= 0;
            elsif nfc_rl > 1 then nfc_rl <= nfc_rl - 1; end if;

            if arm_uart = '1' then
                uart_ready <= '0'; uart_byte <= to_unsigned(DMA_UART_SEED, 8);
                uart_rl <= RAISE; uart_rd_cnt <= 0;
            end if;
            if arm_qspi = '1' then
                qspi_ready <= '0'; qspi_val <= to_unsigned(DMA_QSPI_SEED, 8);
                qspi_rl <= RAISE;
            end if;
            if arm_nfc = '1' then
                nfc_ready <= '0'; nfc_idx <= 0; nfc_rl <= RAISE; nfc_rd_cnt <= 0;
            end if;

            ---------------------------------------------------------------
            -- need_release: a served master is eligible again only once its req is OBSERVED low.
            ---------------------------------------------------------------
            if m_req = '0' then
                need_release <= '0';
            end if;

            ---------------------------------------------------------------
            -- arbiter FSM (single master), IDLE/LATCH/DATA shape
            ---------------------------------------------------------------
            case state is
                when A_IDLE =>
                    -- wait for a request from an unmasked master, then accept it
                    gnt_i <= '0';
                    if m_req = '1' and need_release = '0' then
                        -- accept: latch the access this edge
                        a_addr  <= m_addr;
                        a_we    <= m_we;
                        a_wdata <= m_wdata;
                        gnt_i   <= '1';
                        state   <= A_LATCH;
                    end if;

                when A_LATCH =>
                    -- slave registers the access; s_rdata is valid in DATA
                    gnt_i <= '1';
                    idx := to_integer(unsigned(a_addr)) mod RAM_WORDS;
                    if a_we = "0000" then
                        ---- READ ---------------------------------------------
                        if to_integer(unsigned(a_addr)) = UART_RX_W then
                            s_rdata <= x"000000" & std_logic_vector(uart_byte);
                            uart_ready <= '0';                 -- read-to-clear
                            uart_byte  <= uart_byte + 1;
                            uart_rl    <= RAISE;               -- re-arm next byte
                            uart_rd_cnt <= uart_rd_cnt + 1;
                        elsif to_integer(unsigned(a_addr)) = QSPI_RX_W then
                            s_rdata <= x"000000" & std_logic_vector(qspi_val);  -- side-effect-free read
                        elsif to_integer(unsigned(a_addr)) = NFC_DATA_W then
                            s_rdata <= std_logic_vector(to_unsigned(DMA_NFC_BASE + nfc_idx, 32));
                            nfc_idx <= nfc_idx + 1;            -- IDX auto-advance
                            nfc_rd_cnt <= nfc_rd_cnt + 1;
                        else
                            s_rdata <= mem(idx);
                            if is_deny_read(to_integer(unsigned(a_addr)), a_we) then
                                denied_i <= denied_i + 1;      -- DUT should have suppressed!
                            end if;
                        end if;
                    else
                        ---- WRITE (byte-lane merged) --------------------------
                        if to_integer(unsigned(a_addr)) = QSPI_SR_W then
                            qspi_clr_i <= a_wdata;             -- record the M_CLR value
                            if a_wdata(2) = '1' then           -- W1C bit 2 only
                                qspi_ready <= '0';
                                qspi_val   <= qspi_val + 1;    -- next sample
                                qspi_rl    <= RAISE;           -- re-arm RXFULL
                            end if;
                        elsif to_integer(unsigned(a_addr)) = NFC_SR_W then
                            if a_wdata(2) = '1' then
                                nfc_ready <= '0';              -- frame ack
                            end if;
                        else
                            for l in 0 to 3 loop
                                if a_we(l) = '1' then
                                    mem(idx)((l+1)*8-1 downto l*8) <= a_wdata((l+1)*8-1 downto l*8);
                                end if;
                            end loop;
                        end if;
                    end if;
                    state <= A_DATA;

                when A_DATA =>
                    done_i <= '1';                 -- complete (m_rdata valid this cycle)
                    gnt_i  <= '0';
                    need_release <= '1';           -- mask stale req until observed low
                    state <= A_IDLE;
            end case;
        end if;
    end process proc;

    -- =======================================================================
    -- PROTOCOL MONITOR: fails the bench on a master-port handshake violation.
    --   (a) m_req observed low >=1 cycle between txns; (b) payload stable while m_req is high through m_done; (c) m_req never drops before its m_done.
    -- =======================================================================
    monitor: process(clk, resetn)
        variable prev_req  : std_logic := '0';
        variable hold_addr : std_logic_vector(AW-1 downto 0);
        variable hold_we   : std_logic_vector(3 downto 0);
        variable hold_wd   : std_logic_vector(31 downto 0);
        variable done_seen : boolean := false;
        variable post_done : natural := 0;   -- cycles req held after its done
    begin
        if resetn = '0' then
            prev_req := '0'; done_seen := false; post_done := 0;
        elsif rising_edge(clk) then
            if m_req = '1' and prev_req = '0' then
                -- A rising edge of req starts a new txn, the '0' cycle just passed satisfies the observed-low gap, so capture the payload for the stability check.
                hold_addr := m_addr; hold_we := m_we; hold_wd := m_wdata;
                done_seen := false; post_done := 0;
            elsif m_req = '1' and prev_req = '1' then
                -- (b) payload must be stable across the whole req-high window
                if m_addr /= hold_addr or m_we /= hold_we or m_wdata /= hold_wd then
                    prot_i <= '1';
                    report "DMA_ARB_MODEL PROTOCOL VIOLATION: m_addr/m_we/m_wdata "
                        & "changed while m_req held high (mid-txn payload change)"
                        severity error;
                end if;
                if done_seen then
                    post_done := post_done + 1;
                    if post_done > 4 then
                        -- (a) stale req held across words: a ghost request the arbiter's IDLE pick would mis-serve.
                        prot_i <= '1';
                        report "DMA_ARB_MODEL PROTOCOL VIOLATION: m_req not "
                            & "released within 4 cycles after m_done (stale req "
                            & "held across words -- wait-for-release breach)"
                            severity error;
                    end if;
                end if;
            elsif m_req = '0' and prev_req = '1' then
                -- (c) req dropped: legal ONLY after this txn's done was seen
                if not done_seen then
                    prot_i <= '1';
                    report "DMA_ARB_MODEL PROTOCOL VIOLATION: m_req dropped "
                        & "BEFORE m_done (truncated handshake / mid-txn abort)"
                        severity error;
                end if;
            end if;

            if done_i = '1' then
                done_seen := true;
            end if;
            prev_req := m_req;
        end if;
    end process monitor;

end architecture model;


-- =============================================================================
-- DMA_tb : the standalone self-checking testbench top
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.dma_bfm_pkg.all;

entity DMA_tb is
end entity DMA_tb;

architecture sim of DMA_tb is

    constant PERIOD : time    := 20 ns;   -- clk / ClkMem reference (ONE clock family)
    constant AW     : natural := DMA_AW;  -- 15-bit master word address

    -- DUT declared as a component so the bench compiles standalone; the event-fabric taps are part of it so default binding sees the FULL entity port list.
    -- task_go carries the same all-zero default as the entity.
    component DMA is
        generic (
            NCH : natural := 4;
            AW  : natural := 15
        );
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);
            m_req       : out std_logic;
            m_we        : out std_logic_vector(3 downto 0);
            m_addr      : out std_logic_vector(AW-1 downto 0);
            m_wdata     : out std_logic_vector(31 downto 0);
            m_gnt       : in  std_logic;
            m_done      : in  std_logic;
            m_rdata     : in  std_logic_vector(31 downto 0);
            trig_uart0_rc  : in std_logic := '0';
            trig_qspi0_rxf : in std_logic := '0';
            trig_nfc0_rxf  : in std_logic := '0';
            irq_done    : out std_logic;
            irq_err     : out std_logic;
            task_go     : in  std_logic_vector(3 downto 0) := (others => '0');
            evt_done    : out std_logic_vector(3 downto 0);
            evt_err     : out std_logic;
            ch_busy     : out std_logic_vector(3 downto 0)
        );
    end component;

    -- work.CRC16 (the CRC16-CDMA2000 cell) is the INDEPENDENT reference: four chained instances fed bytes b0 through b3, seed 0xFFFF.
    component CRC16 is
        generic (POLYNOMIAL : std_logic_vector(15 downto 0) := x"C857");
        port (
            DataIn : in  std_logic_vector(7 downto 0);
            CrcOld : in  std_logic_vector(15 downto 0);
            CrcOut : out std_logic_vector(15 downto 0)
        );
    end component;

    -- clocks / reset
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- ==== DUT #1 (NCH=4) harness =========================================
    signal pbus  : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata : std_logic_vector(31 downto 0);
    signal m_req  : std_logic;
    signal m_we   : std_logic_vector(3 downto 0);
    signal m_addr : std_logic_vector(AW-1 downto 0);
    signal m_wda  : std_logic_vector(31 downto 0);
    signal m_gnt, m_done : std_logic;
    signal m_rda  : std_logic_vector(31 downto 0);
    signal trig_uart, trig_qspi, trig_nfc : std_logic;
    signal irq_done, irq_err : std_logic;
    signal arm_uart, arm_qspi, arm_nfc : std_logic := '0';
    signal bd_addr : std_logic_vector(AW-1 downto 0) := (others => '0');
    signal bd_poke : std_logic := '0';
    signal bd_wda  : std_logic_vector(31 downto 0) := (others => '0');
    signal bd_rda  : std_logic_vector(31 downto 0);
    signal prot_err : std_logic;
    signal denied_hits, uart_reads, nfc_reads : natural;
    signal qspi_sr_obs    : std_logic_vector(7 downto 0);
    signal qspi_clr_wdata : std_logic_vector(31 downto 0);

    -- ==== event-fabric taps ==============================================
    -- DUT#1 only: dut2 leaves these at the component default or open, since its group is register-shape only and needs no task-tap coverage.
    signal task_go  : std_logic_vector(3 downto 0) := "0000";  -- tb-driven, default 0000
    signal evt_done : std_logic_vector(3 downto 0);
    signal evt_err  : std_logic;
    signal ch_busy  : std_logic_vector(3 downto 0);

    -- ---- event-tap pulse/level monitor: pulse starts plus total-high samples for evt_done(3:0)/evt_err/ch_busy(3:0), windowed via evt_mon_clear.
    -- It samples only the exported ports, never a DUT internal, so the check stays independent.
    type nat_arr4 is array (0 to 3) of natural;
    signal evt_done_starts, evt_done_highs : nat_arr4 := (others => 0);
    signal evt_done_prev : std_logic_vector(3 downto 0) := (others => '0');
    signal evt_err_starts, evt_err_highs : natural := 0;
    signal evt_err_prev  : std_logic := '0';
    signal ch_busy_starts, ch_busy_highs : nat_arr4 := (others => 0);
    signal ch_busy_prev  : std_logic_vector(3 downto 0) := (others => '0');
    signal evt_mon_clear : std_logic := '0';

    -- ==== DUT #2 (NCH=2) harness =========================================
    signal pbus2  : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata2 : std_logic_vector(31 downto 0);
    signal m_req2  : std_logic;
    signal m_we2   : std_logic_vector(3 downto 0);
    signal m_addr2 : std_logic_vector(AW-1 downto 0);
    signal m_wda2  : std_logic_vector(31 downto 0);
    signal m_gnt2, m_done2 : std_logic;
    signal m_rda2  : std_logic_vector(31 downto 0);
    signal irq_done2, irq_err2 : std_logic;
    signal bd_addr2 : std_logic_vector(AW-1 downto 0) := (others => '0');
    signal bd_poke2 : std_logic := '0';
    signal bd_wda2  : std_logic_vector(31 downto 0) := (others => '0');
    signal bd_rda2  : std_logic_vector(31 downto 0);
    signal prot_err2 : std_logic;
    signal denied2, ureads2, nreads2 : natural;
    signal qsr2 : std_logic_vector(7 downto 0);
    signal qclr2 : std_logic_vector(31 downto 0);

    -- ==== CRC reference chain (four chained work.CRC16, fed bytes b0 through b3) ====
    signal crc_word : std_logic_vector(31 downto 0) := (others => '0');
    signal crc_seed : std_logic_vector(15 downto 0) := (others => '0');
    signal crc_s1, crc_s2, crc_s3, crc_res : std_logic_vector(15 downto 0);

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- Clock and gated register-bus clock: both DUTs share clk, and the gate opens on either DUT's bus select.
    -- Only one bus is active at a time in the single stim process, so the shared gate is safe.
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when (pbus.en_mem = '0' or pbus2.en_mem = '0') else '0';

    ----------------------------------------------------------------------------
    -- CRC reference: four chained work.CRC16 over bytes b0 through b3.
    -- crc_seed and crc_word are driven by the stim, crc_res is the folded result.
    ----------------------------------------------------------------------------
    c0: CRC16 port map (DataIn => crc_word(7  downto 0),  CrcOld => crc_seed, CrcOut => crc_s1);
    c1: CRC16 port map (DataIn => crc_word(15 downto 8),  CrcOld => crc_s1,   CrcOut => crc_s2);
    c2: CRC16 port map (DataIn => crc_word(23 downto 16), CrcOld => crc_s2,   CrcOut => crc_s3);
    c3: CRC16 port map (DataIn => crc_word(31 downto 24), CrcOld => crc_s3,   CrcOut => crc_res);

    ----------------------------------------------------------------------------
    -- Event-tap monitor: samples evt_done(3:0)/evt_err/ch_busy(3:0), to_X01-normalized per bit, on every clk rising edge.
    -- evt_mon_clear restarts the accumulators to open a new measurement window.
    ----------------------------------------------------------------------------
    evt_mon_proc : process(clk)
        variable d_lvl, b_lvl : std_logic_vector(3 downto 0);
        variable e_lvl        : std_logic;
    begin
        if rising_edge(clk) then
            for ch in 0 to 3 loop
                d_lvl(ch) := to_X01(evt_done(ch));
                b_lvl(ch) := to_X01(ch_busy(ch));
            end loop;
            e_lvl := to_X01(evt_err);
            if evt_mon_clear = '1' then
                for ch in 0 to 3 loop
                    evt_done_starts(ch) <= 0;
                    evt_done_highs(ch)  <= 0;
                    evt_done_prev(ch)   <= d_lvl(ch);
                    ch_busy_starts(ch)  <= 0;
                    ch_busy_highs(ch)   <= 0;
                    ch_busy_prev(ch)    <= b_lvl(ch);
                end loop;
                evt_err_starts <= 0;
                evt_err_highs  <= 0;
                evt_err_prev   <= e_lvl;
            else
                for ch in 0 to 3 loop
                    if d_lvl(ch) = '1' then
                        evt_done_highs(ch) <= evt_done_highs(ch) + 1;
                        if evt_done_prev(ch) /= '1' then
                            evt_done_starts(ch) <= evt_done_starts(ch) + 1;
                        end if;
                    end if;
                    evt_done_prev(ch) <= d_lvl(ch);
                    if b_lvl(ch) = '1' then
                        ch_busy_highs(ch) <= ch_busy_highs(ch) + 1;
                        if ch_busy_prev(ch) /= '1' then
                            ch_busy_starts(ch) <= ch_busy_starts(ch) + 1;
                        end if;
                    end if;
                    ch_busy_prev(ch) <= b_lvl(ch);
                end loop;
                if e_lvl = '1' then
                    evt_err_highs <= evt_err_highs + 1;
                    if evt_err_prev /= '1' then
                        evt_err_starts <= evt_err_starts + 1;
                    end if;
                end if;
                evt_err_prev <= e_lvl;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- DUT #1 (NCH=4) + its arbiter-side model
    ----------------------------------------------------------------------------
    dut : component DMA
        generic map (NCH => 4, AW => AW)
        port map (
            clk => clk, resetn => resetn,
            ClkMem => ClkMem, EnMemPeriph => pbus.en_mem,
            WEn => pbus.wen, MABPart => pbus.addr_periph,
            wdata => pbus.write_data, rdata_out => rdata,
            m_req => m_req, m_we => m_we, m_addr => m_addr, m_wdata => m_wda,
            m_gnt => m_gnt, m_done => m_done, m_rdata => m_rda,
            trig_uart0_rc => trig_uart, trig_qspi0_rxf => trig_qspi,
            trig_nfc0_rxf => trig_nfc,
            irq_done => irq_done, irq_err => irq_err,
            task_go => task_go, evt_done => evt_done, evt_err => evt_err,
            ch_busy => ch_busy
        );

    arb : entity work.dma_arb_model
        generic map (AW => AW)
        port map (
            clk => clk, resetn => resetn,
            m_req => m_req, m_we => m_we, m_addr => m_addr, m_wdata => m_wda,
            m_gnt => m_gnt, m_done => m_done, m_rdata => m_rda,
            trig_uart => trig_uart, trig_qspi => trig_qspi, trig_nfc => trig_nfc,
            arm_uart => arm_uart, arm_qspi => arm_qspi, arm_nfc => arm_nfc,
            bd_addr => bd_addr, bd_poke => bd_poke, bd_wdata => bd_wda,
            bd_rdata => bd_rda,
            prot_err => prot_err, denied_hits => denied_hits,
            uart_reads => uart_reads, nfc_reads => nfc_reads,
            qspi_sr_obs => qspi_sr_obs, qspi_clr_wdata => qspi_clr_wdata
        );

    ----------------------------------------------------------------------------
    -- DUT #2 (NCH=2) plus its arbiter-side model.
    -- Triggers are tied '0' because this instance only covers mem-to-mem and register shape; backdoor and bus come from the same stim.
    ----------------------------------------------------------------------------
    dut2 : component DMA
        generic map (NCH => 2, AW => AW)
        port map (
            clk => clk, resetn => resetn,
            ClkMem => ClkMem, EnMemPeriph => pbus2.en_mem,
            WEn => pbus2.wen, MABPart => pbus2.addr_periph,
            wdata => pbus2.write_data, rdata_out => rdata2,
            m_req => m_req2, m_we => m_we2, m_addr => m_addr2, m_wdata => m_wda2,
            m_gnt => m_gnt2, m_done => m_done2, m_rdata => m_rda2,
            trig_uart0_rc => '0', trig_qspi0_rxf => '0', trig_nfc0_rxf => '0',
            irq_done => irq_done2, irq_err => irq_err2,
            evt_done => open, evt_err => open, ch_busy => open
        );

    arb2 : entity work.dma_arb_model
        generic map (AW => AW)
        port map (
            clk => clk, resetn => resetn,
            m_req => m_req2, m_we => m_we2, m_addr => m_addr2, m_wdata => m_wda2,
            m_gnt => m_gnt2, m_done => m_done2, m_rdata => m_rda2,
            trig_uart => open, trig_qspi => open, trig_nfc => open,
            arm_uart => '0', arm_qspi => '0', arm_nfc => '0',
            bd_addr => bd_addr2, bd_poke => bd_poke2, bd_wdata => bd_wda2,
            bd_rdata => bd_rda2,
            prot_err => prot_err2, denied_hits => denied2,
            uart_reads => ureads2, nfc_reads => nreads2,
            qspi_sr_obs => qsr2, qspi_clr_wdata => qclr2
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    -- Expected sim time is well under 1 ms, so this fires only on a true hang.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   DMA_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw  : std_logic_vector(31 downto 0);
        variable got  : std_logic_vector(31 downto 0);
        variable ok   : boolean;
        variable acc  : std_logic_vector(15 downto 0);

        type wbuf_t is array(0 to 31) of std_logic_vector(31 downto 0);
        variable buf : wbuf_t;

        -- Byte-address buffer map: all RAM, in-window, aligned, clear of the peripheral/deny/hole regions, every word index < RAM_WORDS = 0x5000.
        constant SRCA : natural := 16#10000#;   constant DSTA : natural := 16#10400#;
        constant SRCB : natural := 16#10800#;   constant DSTB : natural := 16#10C00#;
        constant DSTC : natural := 16#11000#;
        constant DSTU : natural := 16#11400#;   constant DSTQ : natural := 16#11800#;
        constant DSTN : natural := 16#11C00#;
        constant SRR0 : natural := 16#12000#;   constant DRR0 : natural := 16#12400#;
        constant SRR1 : natural := 16#12800#;   constant DRR1 : natural := 16#12C00#;
        constant SRAB : natural := 16#13000#;   constant DRAB : natural := 16#13400#;
        constant LEGM : natural := 16#6100#;    constant LEGR : natural := 16#7804#;
        constant DLEG : natural := 16#13800#;
        constant DSTT : natural := 16#13C00#;   -- task-launched-copy dst (fresh, clear of DLEG)

        -- program a channel's {SRC,DST,LEN,CFG}
        procedure prog_ch(signal b : inout periph_bus_t;
                          ch : natural; src_b, dst_b, len : natural;
                          cfg : std_logic_vector(31 downto 0)) is
        begin
            bus_write(clk, b, dma_ch_slot(ch,0), std_logic_vector(to_unsigned(src_b,32)));
            bus_write(clk, b, dma_ch_slot(ch,1), std_logic_vector(to_unsigned(dst_b,32)));
            bus_write(clk, b, dma_ch_slot(ch,2), std_logic_vector(to_unsigned(len,32)));
            bus_write(clk, b, dma_ch_slot(ch,3), cfg);
        end procedure;

        -- persist DMAEN=1 (+ IE bits), no launch
        procedure dma_enable(signal b : inout periph_bus_t; doneie, errie : std_logic) is
        begin
            bus_write(clk, b, DMA_SLOT_CR, dma_mk_cr('1', "0000", "0000", doneie, errie));
        end procedure;

        -- launch (DMAEN=1 + go_mask + IE)
        procedure dma_go(signal b : inout periph_bus_t;
                         go_mask : std_logic_vector(3 downto 0); doneie, errie : std_logic) is
        begin
            bus_write(clk, b, DMA_SLOT_CR, dma_mk_cr('1', go_mask, "0000", doneie, errie));
        end procedure;

        -- W1C an SR mask, then let the clear toggle cross into clk
        procedure dma_w1c(signal b : inout periph_bus_t; mask : std_logic_vector(31 downto 0)) is
        begin
            bus_write(clk, b, DMA_SLOT_SR, mask);
            wait for 6 * PERIOD;
        end procedure;

        -- ---- event-tap helpers ---------------------------------------------

        -- Drive task_go(ch) high across EXACTLY one clk rising edge, then drop it back to '0'.
        procedure pulse_task_go(ch : natural) is
        begin
            wait until clk = '0';
            task_go(ch) <= '1';
            wait until clk = '1';
            wait until clk = '0';
            task_go(ch) <= '0';
        end procedure;

        -- Clear the event-tap monitor accumulators; call only outside a timing-critical window.
        procedure evt_mon_reset is
        begin
            wait until clk = '0';
            evt_mon_clear <= '1';
            wait until clk = '1';
            wait until clk = '0';
            evt_mon_clear <= '0';
        end procedure;

        -- backdoor RAM poke of DUT#1's model (one word)
        procedure ram_poke1(wa : natural; d : std_logic_vector(31 downto 0)) is
        begin
            wait until clk = '0';
            bd_addr <= std_logic_vector(to_unsigned(wa, AW));
            bd_wda  <= d; bd_poke <= '1';
            wait until clk = '1';
            wait until clk = '0';
            bd_poke <= '0';
        end procedure;

        -- backdoor RAM poke of DUT#2's model (one word)
        procedure ram_poke2(wa : natural; d : std_logic_vector(31 downto 0)) is
        begin
            wait until clk = '0';
            bd_addr2 <= std_logic_vector(to_unsigned(wa, AW));
            bd_wda2  <= d; bd_poke2 <= '1';
            wait until clk = '1';
            wait until clk = '0';
            bd_poke2 <= '0';
        end procedure;

        -- backdoor RAM peek of DUT#1's model (bd_rdata is combinational)
        procedure ram_peek1(wa : natural; d : out std_logic_vector(31 downto 0)) is
        begin
            bd_addr <= std_logic_vector(to_unsigned(wa, AW));
            wait for 2 * PERIOD;
            d := bd_rda;
        end procedure;

        -- backdoor RAM peek of DUT#2's model (bd_rdata is combinational)
        procedure ram_peek2(wa : natural; d : out std_logic_vector(31 downto 0)) is
        begin
            bd_addr2 <= std_logic_vector(to_unsigned(wa, AW));
            wait for 2 * PERIOD;
            d := bd_rda2;
        end procedure;

        -- fold a word into the CRC reference chain (four chained work.CRC16)
        procedure crc_fold(w : std_logic_vector(31 downto 0)) is
        begin
            crc_seed <= acc;
            crc_word <= w;
            wait for 2 * PERIOD;      -- settle the combinational chain
            acc := crc_res;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------
        resetn <= '0';
        pbus   <= PERIPH_BUS_IDLE;
        pbus2  <= PERIPH_BUS_IDLE;
        wait for 12 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 8 * PERIOD;

        ------------------------------------------------------------------
        -- GROUP G0: reset defaults
        ------------------------------------------------------------------
        report "=== GROUP G0: reset defaults ===" severity note;
        bus_read(clk, pbus, rdata, DMA_SLOT_CR, rdw);
        sb.check_slv("G0: DMA0CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_slv("G0: DMA0SR resets to 0 (BUSY/DONE/ERR/ACTIVECH)", rdw, x"00000000");
        for ch in 0 to 3 loop
            bus_read(clk, pbus, rdata, dma_ch_slot(ch,0), rdw);
            sb.check_slv("G0: CH SRC resets to 0", rdw, x"00000000");
            bus_read(clk, pbus, rdata, dma_ch_slot(ch,1), rdw);
            sb.check_slv("G0: CH DST resets to 0", rdw, x"00000000");
            bus_read(clk, pbus, rdata, dma_ch_slot(ch,2), rdw);
            sb.check_slv("G0: CH LEN resets to 0", rdw, x"00000000");
            bus_read(clk, pbus, rdata, dma_ch_slot(ch,3), rdw);
            sb.check_slv("G0: CH CFG resets to 0", rdw, x"00000000");
        end loop;
        bus_read(clk, pbus, rdata, DMA_SLOT_CRC, rdw);
        sb.check_slv("G0: DMA0CRC resets to 0xFFFF", rdw, x"0000FFFF");
        bus_read(clk, pbus, rdata, DMA_SLOT_DESC, rdw);
        sb.check_slv("G0: DMA0DESC (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata, 20, rdw);
        sb.check_slv("G0: slot 20 (>19) reads 0", rdw, x"00000000");
        sb.check_bit("G0: irq_done = 0 out of reset", to_X01(irq_done), '0');
        sb.check_bit("G0: irq_err  = 0 out of reset", to_X01(irq_err),  '0');
        sb.check_true("G0: protocol monitor clean out of reset", to_X01(prot_err) = '0');

        ------------------------------------------------------------------
        -- GROUP G1: mem-to-mem copy
        ------------------------------------------------------------------
        report "=== GROUP G1: mem-to-mem copy ===" severity note;
        for k in 0 to 3 loop
            buf(k) := x"A1B2C3" & std_logic_vector(to_unsigned(16#40# + k, 8));
            ram_poke1(dma_word_idx(SRCA) + k, buf(k));
        end loop;
        dma_enable(pbus, '1', '0');
        prog_ch(pbus, 0, SRCA, DSTA, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        -- same-cycle blind window: BUSY must read 1 immediately after GO
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G1: BUSY=1 same cycle as CH0 GO (D8 blind window)",
                     to_X01(rdw(DMA_SR_BUSY)), '1');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G1: BUSY clears (bounded)", ok);
        for k in 0 to 3 loop
            ram_peek1(dma_word_idx(DSTA) + k, got);
            sb.check_slv("G1: dst word matches src (mem-to-mem)", got, buf(k));
        end loop;
        bus_read(clk, pbus, rdata, dma_ch_slot(0,2), rdw);
        sb.check_slv("G1: CH0 LEN decremented to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G1: CH0DONE set at completion", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_bit("G1: irq_done asserts (CH0DONE & DONEIE)", to_X01(irq_done), '1');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G1: CH0DONE clears after W1C", to_X01(rdw(DMA_SR_DONE0)), '0');
        sb.check_bit("G1: irq_done drops after W1C CH0DONE", to_X01(irq_done), '0');

        ------------------------------------------------------------------
        -- GROUP G2: increment modes
        ------------------------------------------------------------------
        report "=== GROUP G2: increment modes ===" severity note;
        -- (a) SINC=1/DINC=1 is already covered by the block copy above.
        -- (b) SINC=0 is the fixed-src, peripheral-drain shape: every dst word equals src word 0.
        for k in 0 to 3 loop
            buf(k) := x"5000" & std_logic_vector(to_unsigned(k, 16));
            ram_poke1(dma_word_idx(SRCB) + k, buf(k));
        end loop;
        prog_ch(pbus, 0, SRCB, DSTB, 4, dma_mk_cfg('0','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G2: BUSY clears (SINC=0 fixed-src copy)", ok);
        for k in 0 to 3 loop
            ram_peek1(dma_word_idx(DSTB) + k, got);
            sb.check_slv("G2: SINC=0 -> every dst word = src[0]", got, buf(0));
        end loop;
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));
        -- (c) DINC=0 (fixed dst = fill shape): only dst word 0 written, = src last
        prog_ch(pbus, 0, SRCB, DSTC, 4, dma_mk_cfg('1','0', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G2: BUSY clears (DINC=0 fixed-dst copy)", ok);
        ram_peek1(dma_word_idx(DSTC), got);
        sb.check_slv("G2: DINC=0 -> fixed dst holds the LAST src word", got, buf(3));
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- GROUP G3: multi-channel round-robin + strict PRIO + ACTIVECH
        ------------------------------------------------------------------
        report "=== GROUP G3: multi-channel round-robin / PRIO ===" severity note;
        -- Part A: two SAME-priority mem-to-mem channels both complete correctly and neither starves, the round-robin fairness proof.
        for k in 0 to 5 loop
            buf(k) := x"3300" & std_logic_vector(to_unsigned(k, 16));
            ram_poke1(dma_word_idx(SRR0) + k, buf(k));
            ram_poke1(dma_word_idx(SRR1) + k, buf(k) xor x"0000FFFF");
        end loop;
        dma_enable(pbus, '1', '0');
        prog_ch(pbus, 0, SRR0, DRR0, 6, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        prog_ch(pbus, 1, SRR1, DRR1, 6, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0011", '1', '0');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G3: BUSY clears (two same-prio channels)", ok);
        for k in 0 to 5 loop
            ram_peek1(dma_word_idx(DRR0) + k, got);
            sb.check_slv("G3: CH0 dst correct (RR interleave)", got, buf(k));
            ram_peek1(dma_word_idx(DRR1) + k, got);
            sb.check_slv("G3: CH1 dst correct (RR interleave)", got, buf(k) xor x"0000FFFF");
        end loop;
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0 + 2**(DMA_SR_DONE0+1), 32)));

        -- Part B: strict 2-level PRIO, so CH0 PRIO=1 (LEN=10) must hold off CH1 PRIO=0 (LEN=3) completely while it drains.
        -- Both channels are continuously serviceable mem-to-mem, so CH1 LEN must stay 3 for as long as CH0 runs.
        for k in 0 to 9 loop
            buf(k) := x"AA00" & std_logic_vector(to_unsigned(k, 16));
            ram_poke1(dma_word_idx(SRR0) + k, buf(k));
        end loop;
        for k in 0 to 2 loop
            ram_poke1(dma_word_idx(SRR1) + k, x"BB00" & std_logic_vector(to_unsigned(k, 16)));
        end loop;
        prog_ch(pbus, 0, SRR0, DRR0, 10, dma_mk_cfg('1','1', DMA_TRIG_MEM, '1','0'));  -- PRIO=1
        prog_ch(pbus, 1, SRR1, DRR1, 3,  dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));  -- PRIO=0
        dma_go(pbus, "0011", '1', '0');
        -- wait until CH0 has started draining, then CH1 must be untouched
        ok := false;
        for i in 0 to 400 loop
            bus_read(clk, pbus, rdata, dma_ch_slot(0,2), rdw);
            if to_integer(unsigned(rdw)) < 10 and to_integer(unsigned(rdw)) > 0 then
                ok := true; exit;
            end if;
        end loop;
        sb.check_true("G3: CH0 (PRIO=1) is draining (bounded)", ok);
        bus_read(clk, pbus, rdata, dma_ch_slot(1,2), rdw);
        sb.check_slv("G3: CH1 (PRIO=0) held off -- LEN still 3 while CH0 runs", rdw, x"00000003");
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G3: BUSY clears (both PRIO channels finished)", ok);
        for k in 0 to 9 loop
            ram_peek1(dma_word_idx(DRR0) + k, got);
            sb.check_slv("G3: CH0 (PRIO=1) dst correct", got, buf(k));
        end loop;
        for k in 0 to 2 loop
            ram_peek1(dma_word_idx(DRR1) + k, got);
            sb.check_slv("G3: CH1 (PRIO=0) dst correct (ran after CH0)", got,
                         x"BB00" & std_logic_vector(to_unsigned(k, 16)));
        end loop;
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0 + 2**(DMA_SR_DONE0+1), 32)));
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_slv("G3: ACTIVECH reads 0 when idle", rdw(11 downto 9), "000");

        -- Part C: on a solo CH1 run ACTIVECH must read 1 while CH1 is serviced
        for k in 0 to 5 loop
            ram_poke1(dma_word_idx(SRR1) + k, x"C100" & std_logic_vector(to_unsigned(k, 16)));
        end loop;
        prog_ch(pbus, 1, SRR1, DRR1, 6, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0010", '1', '0');
        ok := false;
        for i in 0 to 200 loop
            bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
            if to_X01(rdw(DMA_SR_BUSY)) = '1' and rdw(11 downto 9) = "001" then
                ok := true; exit;
            end if;
        end loop;
        sb.check_true("G3: ACTIVECH = 1 during solo CH1 activity", ok);
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**(DMA_SR_DONE0+1), 32)));

        ------------------------------------------------------------------
        -- GROUP G4: pacing
        ------------------------------------------------------------------
        report "=== GROUP G4: pacing (UART / QSPI / NFC) ===" severity note;
        dma_enable(pbus, '1', '0');

        -- (a) UART0 RC: read-to-clear, ONE word per event, NO extra txn.
        prog_ch(pbus, 0, DMA_UART_RX_BYTE, DSTU, 4,
                dma_mk_cfg('0','1', DMA_TRIG_UART, '0','0'));   -- SINC=0 fixed src
        dma_go(pbus, "0001", '1', '0');
        wait until clk = '0'; arm_uart <= '1';
        wait until clk = '1'; wait until clk = '0'; arm_uart <= '0';
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G4-UART: BUSY clears (paced drain)", ok);
        for k in 0 to 3 loop
            ram_peek1(dma_word_idx(DSTU) + k, got);
            sb.check_slv("G4-UART: dst = seed+k byte-in-low-lane (A12)", got,
                         std_logic_vector(to_unsigned(DMA_UART_SEED + k, 32)));
        end loop;
        sb.check_true("G4-UART: exactly LEN reads (one word per event)", uart_reads = 4);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        -- (b) QSPI0 RXFULL: side-effect-free read + M_CLR W1C(bit 2) re-arm.
        prog_ch(pbus, 0, DMA_QSPI_RX_BYTE, DSTQ, 3,
                dma_mk_cfg('0','1', DMA_TRIG_QSPI, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        wait until clk = '0'; arm_qspi <= '1';
        wait until clk = '1'; wait until clk = '0'; arm_qspi <= '0';
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G4-QSPI: BUSY clears (paced drain + M_CLR)", ok);
        for k in 0 to 2 loop
            ram_peek1(dma_word_idx(DSTQ) + k, got);
            sb.check_slv("G4-QSPI: dst = seed+k (event-paced)", got,
                         std_logic_vector(to_unsigned(DMA_QSPI_SEED + k, 32)));
        end loop;
        sb.check_slv("G4-QSPI: M_CLR wrote ONLY bit 2 (W1C, A11)", qspi_clr_wdata, x"00000004");
        sb.check_slv("G4-QSPI: M_CLR disturbed no other SR bit (A11)", qspi_sr_obs and x"FB", x"0B");
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        -- (c) NFC0 payload-ready: ONE frame event drains LEN words + M_CLR ack.
        prog_ch(pbus, 0, DMA_NFC_DATA_BYTE, DSTN, 4,
                dma_mk_cfg('0','1', DMA_TRIG_NFC, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        wait until clk = '0'; arm_nfc <= '1';
        wait until clk = '1'; wait until clk = '0'; arm_nfc <= '0';
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G4-NFC: BUSY clears (frame-burst drain)", ok);
        for k in 0 to 3 loop
            ram_peek1(dma_word_idx(DSTN) + k, got);
            sb.check_slv("G4-NFC: dst = payload base+k (IDX auto-advance, A10)", got,
                         std_logic_vector(to_unsigned(DMA_NFC_BASE + k, 32)));
        end loop;
        sb.check_true("G4-NFC: one frame event drained exactly LEN words", nfc_reads = 4);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- GROUP G5: CRC ride-along
        ------------------------------------------------------------------
        report "=== GROUP G5: CRC ride-along ===" severity note;
        -- byte-asymmetric buffer so the b0 through b3 byte order is proven
        buf(0) := x"01020304"; buf(1) := x"A5B6C7D8";
        buf(2) := x"DEADBEEF"; buf(3) := x"0F1E2D3C";
        for k in 0 to 3 loop
            ram_poke1(dma_word_idx(SRCB) + k, buf(k));
        end loop;
        -- seed = 0xFFFF
        bus_write(clk, pbus, DMA_SLOT_CRC, x"0000FFFF");
        prog_ch(pbus, 0, SRCB, DSTB, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','1'));  -- CRCEN
        dma_go(pbus, "0001", '1', '0');
        acc := x"FFFF";
        for k in 0 to 3 loop crc_fold(buf(k)); end loop;   -- independent reference
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G5: BUSY clears (CRCEN copy)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_CRC, rdw);
        sb.check_slv("G5: DMA0CRC = independent CRC16-CDMA2000 ref (seed 0xFFFF, b0->b3)",
                     rdw(15 downto 0), acc);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));
        -- seed reprogram changes the result deterministically
        bus_write(clk, pbus, DMA_SLOT_CRC, x"00000000");
        prog_ch(pbus, 0, SRCB, DSTB, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','1'));
        dma_go(pbus, "0001", '1', '0');
        acc := x"0000";
        for k in 0 to 3 loop crc_fold(buf(k)); end loop;
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_CRC, rdw);
        sb.check_slv("G5: seed=0x0000 reprogram -> different, matching reference",
                     rdw(15 downto 0), acc);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- GROUP G6: deny-guard
        ------------------------------------------------------------------
        report "=== GROUP G6: deny-guard ===" severity note;
        dma_enable(pbus, '0', '1');   -- ERRIE=1
        -- (a) a read targeting the mutex window 0x6000 sets CHnERR and issues NO master txn
        prog_ch(pbus, 0, DMA_MUTEX_LO_BYTE, DLEG, 1,
                dma_mk_cfg('0','0', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G6: BUSY clears after deny abort (mutex)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G6: CH0ERR set on mutex-read deny", to_X01(rdw(DMA_SR_ERR0)), '1');
        sb.check_bit("G6: irq_err asserts (CH0ERR & ERRIE)", to_X01(irq_err), '1');
        sb.check_true("G6: NO master txn issued to a deny word (mutex)", denied_hits = 0);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));
        -- (b) a read targeting the router CLAIM word 0x7800 sets CHnERR and issues NO txn
        prog_ch(pbus, 0, DMA_ROUTER_CLAIM, DLEG, 1,
                dma_mk_cfg('0','0', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G6: BUSY clears after deny abort (router CLAIM)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G6: CH0ERR set on router-CLAIM-read deny", to_X01(rdw(DMA_SR_ERR0)), '1');
        sb.check_true("G6: NO master txn issued to a deny word (router)", denied_hits = 0);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));
        -- (c) legal read ONE WORD away proceeds (mutex+0x100, router CLAIM+4)
        ram_poke1(dma_word_idx(LEGM), x"600DBEEF");
        ram_poke1(dma_word_idx(LEGR), x"78041234");
        prog_ch(pbus, 0, LEGM, DLEG, 1, dma_mk_cfg('0','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        ram_peek1(dma_word_idx(DLEG), got);
        sb.check_slv("G6: legal read just past the mutex window proceeds", got, x"600DBEEF");
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G6: legal read sets CH0DONE (no error)", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_bit("G6: legal read did NOT set CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '0');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));
        prog_ch(pbus, 0, LEGR, DLEG, 1, dma_mk_cfg('0','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        ram_peek1(dma_word_idx(DLEG), got);
        sb.check_slv("G6: legal read one word past the router CLAIM proceeds", got, x"78041234");
        sb.check_true("G6: deny counter still 0 after all legal reads", denied_hits = 0);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- GROUP G7: error model, reject-at-GO
        ------------------------------------------------------------------
        report "=== GROUP G7: error model (reject-at-GO) ===" severity note;
        dma_enable(pbus, '0', '1');   -- ERRIE=1
        -- sentinel at DSTA to prove NO transfer happens on a rejected GO
        ram_poke1(dma_word_idx(DSTA), x"5EED5EED");

        -- (a) LEN=0 at GO
        prog_ch(pbus, 0, SRCA, DSTA, 0, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: LEN=0 GO -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');
        sb.check_bit("G7: LEN=0 GO -> irq_err (ERRIE=1)", to_X01(irq_err), '1');
        ram_peek1(dma_word_idx(DSTA), got);
        sb.check_slv("G7: LEN=0 GO -> NO transfer (dst sentinel intact)", got, x"5EED5EED");
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        -- (b) unaligned SRC (bits[1:0] != 0)
        prog_ch(pbus, 0, SRCA + 1, DSTA, 1, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: unaligned SRC -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        -- (c) unaligned DST
        prog_ch(pbus, 0, SRCA, DSTA + 2, 1, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: unaligned DST -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        -- (d) out-of-window SRC (>= 0x20000)
        prog_ch(pbus, 0, DMA_OOW_BYTE, DSTA, 1, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: out-of-window SRC (>=0x20000) -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        -- (e) TCM hole SRC (0x8000-0xBFFF)
        prog_ch(pbus, 0, DMA_TCM_LO_BYTE, DSTA, 1, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: TCM-hole SRC (0x8000, A18) -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        -- (f) TCM hole DST
        prog_ch(pbus, 0, SRCA, 16#9000#, 1, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '1');
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: TCM-hole DST (0x9000, A18) -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');

        -- (g) irq_err GATED by ERRIE: clear ERRIE, error stays pending but masked
        bus_write(clk, pbus, DMA_SLOT_CR, dma_mk_cr('1', "0000", "0000", '0', '0'));  -- ERRIE=0
        wait for 4 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G7: CH0ERR still pending under ERRIE=0", to_X01(rdw(DMA_SR_ERR0)), '1');
        sb.check_bit("G7: irq_err masked when ERRIE=0", to_X01(irq_err), '0');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        ------------------------------------------------------------------
        -- GROUP G8: abort.
        -- The in-flight txn must complete and m_req must never drop mid-txn; the arbiter protocol monitor proves it.
        ------------------------------------------------------------------
        report "=== GROUP G8: abort ===" severity note;
        for k in 0 to 15 loop
            ram_poke1(dma_word_idx(SRAB) + k, x"AB00" & std_logic_vector(to_unsigned(k, 16)));
        end loop;
        dma_enable(pbus, '1', '0');
        prog_ch(pbus, 0, SRAB, DRAB, 16, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        wait for 20 * PERIOD;   -- let a few words go
        -- request an orderly abort of CH0
        bus_write(clk, pbus, DMA_SLOT_CR, dma_mk_cr('1', "0000", "0001", '0', '0'));
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G8: BUSY drops after abort (bounded)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G8: aborted channel does NOT set CH0DONE", to_X01(rdw(DMA_SR_DONE0)), '0');
        sb.check_bit("G8: aborted channel does NOT set CH0ERR (A15)", to_X01(rdw(DMA_SR_ERR0)), '0');
        bus_read(clk, pbus, rdata, dma_ch_slot(0,2), rdw);
        sb.check_true("G8: LEN reflects a partial stop (0 < LEN < 16)",
                      to_integer(unsigned(rdw)) > 0 and to_integer(unsigned(rdw)) < 16);
        sb.check_bit("G8: handshake never truncated -- m_req never dropped mid-txn",
                     to_X01(prot_err), '0');

        ------------------------------------------------------------------
        -- GROUP G9: W1C + IRQ demux
        ------------------------------------------------------------------
        report "=== GROUP G9: W1C + IRQ demux ===" severity note;
        for k in 0 to 1 loop
            ram_poke1(dma_word_idx(SRCA) + k, x"9900" & std_logic_vector(to_unsigned(k, 16)));
        end loop;
        dma_enable(pbus, '1', '1');   -- DONEIE=1, ERRIE=1
        prog_ch(pbus, 0, SRCA, DSTA, 2, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));  -- completes
        prog_ch(pbus, 1, SRCA, DSTB, 0, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));  -- LEN=0 error
        dma_go(pbus, "0011", '1', '1');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        wait for 4 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G9: CH0DONE set", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_bit("G9: CH1ERR set", to_X01(rdw(DMA_SR_ERR0 + 1)), '1');
        sb.check_bit("G9: irq_done high (|CHnDONE & DONEIE)", to_X01(irq_done), '1');
        sb.check_bit("G9: irq_err high (|CHnERR & ERRIE)", to_X01(irq_err), '1');
        -- W1C CH0DONE only: irq_done drops, irq_err stays
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G9: W1C CH0DONE dropped only CH0DONE", to_X01(rdw(DMA_SR_DONE0)), '0');
        sb.check_bit("G9: CH1ERR still set after W1C CH0DONE", to_X01(rdw(DMA_SR_ERR0 + 1)), '1');
        sb.check_bit("G9: irq_done dropped, irq_err still high", to_X01(irq_done), '0');
        sb.check_bit("G9: irq_err still high", to_X01(irq_err), '1');
        -- W1C CH1ERR: irq_err drops
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**(DMA_SR_ERR0 + 1), 32)));
        sb.check_bit("G9: irq_err drops after W1C CH1ERR", to_X01(irq_err), '0');
        -- masking: cause CH0DONE with DONEIE=0, so the flag sets but irq_done stays 0
        bus_write(clk, pbus, DMA_SLOT_CR, dma_mk_cr('1', "0000", "0000", '0', '0'));  -- DONEIE=0
        prog_ch(pbus, 0, SRCA, DSTA, 2, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '0', '0');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        wait for 4 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G9: CH0DONE pending under DONEIE=0", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_bit("G9: irq_done masked when DONEIE=0", to_X01(irq_done), '0');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- GROUP G10: NCH=2 shape, run on the second DUT instance
        ------------------------------------------------------------------
        report "=== GROUP G10: NCH=2 shape (dut2) ===" severity note;
        -- CH2/CH3 slots ignore writes and read 0 (absent channels)
        bus_write(clk, pbus2, dma_ch_slot(2,0), x"DEADBEEF");
        bus_read(clk, pbus2, rdata2, dma_ch_slot(2,0), rdw);
        sb.check_slv("G10: NCH=2 CH2 SRC ignores writes / reads 0", rdw, x"00000000");
        bus_write(clk, pbus2, dma_ch_slot(3,3), x"12345678");
        bus_read(clk, pbus2, rdata2, dma_ch_slot(3,3), rdw);
        sb.check_slv("G10: NCH=2 CH3 CFG ignores writes / reads 0", rdw, x"00000000");
        bus_read(clk, pbus2, rdata2, dma_ch_slot(2,2), rdw);
        sb.check_slv("G10: NCH=2 CH2 LEN reads 0", rdw, x"00000000");
        -- CH0/CH1 behave identically to NCH=4: a mem-to-mem copy on each
        for k in 0 to 3 loop
            buf(k) := x"2C00" & std_logic_vector(to_unsigned(k, 16));
            ram_poke2(dma_word_idx(SRCA) + k, buf(k));
            ram_poke2(dma_word_idx(SRCB) + k, buf(k) xor x"12340000");
        end loop;
        dma_enable(pbus2, '1', '0');
        prog_ch(pbus2, 0, SRCA, DSTA, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        prog_ch(pbus2, 1, SRCB, DSTB, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus2, "0011", '1', '0');
        dma_wait_busy_clear(clk, pbus2, rdata2, ok);
        sb.check_true("G10: NCH=2 BUSY clears (CH0+CH1 copies)", ok);
        for k in 0 to 3 loop
            ram_peek2(dma_word_idx(DSTA) + k, got);
            sb.check_slv("G10: NCH=2 CH0 dst correct", got, buf(k));
            ram_peek2(dma_word_idx(DSTB) + k, got);
            sb.check_slv("G10: NCH=2 CH1 dst correct", got, buf(k) xor x"12340000");
        end loop;
        bus_read(clk, pbus2, rdata2, DMA_SLOT_SR, rdw);
        sb.check_bit("G10: NCH=2 CH0DONE set", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_bit("G10: NCH=2 CH1DONE set", to_X01(rdw(DMA_SR_DONE0 + 1)), '1');
        sb.check_bit("G10: NCH=2 CH2DONE reads 0 (absent)", to_X01(rdw(DMA_SR_DONE0 + 2)), '0');
        sb.check_bit("G10: NCH=2 CH3DONE reads 0 (absent)", to_X01(rdw(DMA_SR_DONE0 + 3)), '0');
        dma_w1c(pbus2, std_logic_vector(to_unsigned(2**DMA_SR_DONE0 + 2**(DMA_SR_DONE0+1), 32)));

        ------------------------------------------------------------------
        -- Final protocol audit (both models clean in a good run)
        ------------------------------------------------------------------
        sb.check_bit("FINAL: DUT#1 arbiter protocol monitor clean", to_X01(prot_err), '0');
        sb.check_bit("FINAL: DUT#2 arbiter protocol monitor clean", to_X01(prot_err2), '0');
        sb.check_true("FINAL: no deny-word master txn ever issued (DUT#1)", denied_hits = 0);
        sb.check_true("FINAL: no deny-word master txn ever issued (DUT#2)", denied2 = 0);

        ------------------------------------------------------------------
        -- GROUP G-EV: event-fabric taps.
        -- task_go is consumed at the SAME arm site as a register CHnGO, so reject-at-GO, busy suppression and pacing arm are identical, and DMAEN gates task GOs clk-side.
        -- evt_done and evt_err are registered one-clk pulses at the flags' SET sites (pre-IE, and abort sets neither); ch_busy is busy or go_pending or a gated task pulse.
        ------------------------------------------------------------------
        report "=== GROUP G-EV: EVFAB taps (task_go/evt_done/evt_err/ch_busy) ===" severity note;

        -- (a) and (b) indistinguishability plus BUSY same-cycle: the same mem-to-mem setup, but CH0 is launched by a one-clk task_go(0) pulse instead of a register CHnGO write.
        -- Re-poking the SRCA source values is idempotent.
        dma_enable(pbus, '1', '0');   -- DMAEN=1, DONEIE=1, ERRIE=0
        for k in 0 to 3 loop
            buf(k) := x"A1B2C3" & std_logic_vector(to_unsigned(16#40# + k, 8));
            ram_poke1(dma_word_idx(SRCA) + k, buf(k));
        end loop;
        prog_ch(pbus, 0, SRCA, DSTT, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        evt_mon_reset;
        pulse_task_go(0);
        -- (b) BUSY same-cycle: bus_read's own select/capture latency puts its data phase >=1 clk after the pulse, so BUSY must already read 1.
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV b: BUSY reads 1 immediately after task_go(0) (D8-identical same-cycle cover)",
                     to_X01(rdw(DMA_SR_BUSY)), '1');
        sb.check_true("G-EV b: ch_busy(0) was already high in the task_go(0) pulse cycle (monitor)",
                      ch_busy_highs(0) > 0);
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G-EV a: BUSY clears after the task-launched copy", ok);
        for k in 0 to 3 loop
            ram_peek1(dma_word_idx(DSTT) + k, got);
            sb.check_slv("G-EV a: task-launched copy dst matches the register-launched equivalent (G1 values)",
                         got, buf(k));
        end loop;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV a: CH0DONE sets for a task-launched copy", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_true("G-EV a: exactly one evt_done(0) pulse for the task-launched copy",
                      evt_done_starts(0) = 1);
        sb.check_true("G-EV a: that evt_done(0) pulse is exactly one clk wide",
                      evt_done_highs(0) = evt_done_starts(0));
        sb.check_true("G-EV a: ch_busy(0) rose exactly once (one contiguous engaged episode, no double-run)",
                      ch_busy_starts(0) = 1);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        -- (c) DMAEN=0: task_go(0) is completely inert because DMAEN is re-applied clk-side, so there is no arm, no busy blip, no flags and no evt pulses.
        bus_write(clk, pbus, DMA_SLOT_CR, dma_mk_cr('0', "0000", "0000", '0', '0'));   -- DMAEN=0
        wait for 4 * PERIOD;
        prog_ch(pbus, 0, SRCA, DSTT, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));   -- legal, irrelevant
        evt_mon_reset;
        pulse_task_go(0);
        wait for 12 * PERIOD;
        sb.check_true("G-EV c: ch_busy(0) never asserts on a task_go(0) pulse while DMAEN=0",
                      ch_busy_starts(0) = 0 and ch_busy_highs(0) = 0);
        sb.check_true("G-EV c: no evt_done(0) pulse while DMAEN=0", evt_done_starts(0) = 0);
        sb.check_true("G-EV c: no evt_err pulse while DMAEN=0", evt_err_starts = 0);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV c: BUSY stays 0 (task_go inert under DMAEN=0)", to_X01(rdw(DMA_SR_BUSY)), '0');
        sb.check_bit("G-EV c: CH0DONE stays 0 (no arm under DMAEN=0)", to_X01(rdw(DMA_SR_DONE0)), '0');
        sb.check_bit("G-EV c: CH0ERR stays 0 (no arm under DMAEN=0)", to_X01(rdw(DMA_SR_ERR0)), '0');

        -- (d) task GO to a BUSY channel: a mid-flight task_go(0) is a safe no-op because the busy(ch)='0' guard blocks the re-arm.
        -- The descriptor is still legal, so no reject-at-GO fires either and the copy simply finishes.
        dma_enable(pbus, '1', '1');   -- DMAEN=1, DONEIE=1, ERRIE=1 (catch a false CH0ERR too)
        for k in 0 to 15 loop
            buf(k) := x"3D00" & std_logic_vector(to_unsigned(k, 16));
            ram_poke1(dma_word_idx(SRAB) + k, buf(k));
        end loop;
        prog_ch(pbus, 0, SRAB, DRAB, 16, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '1');
        wait for 20 * PERIOD;   -- let a few words go
        evt_mon_reset;
        pulse_task_go(0);
        sb.check_true("G-EV d: ch_busy(0) already high at the mid-flight task_go(0) pulse",
                      ch_busy_highs(0) > 0);
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G-EV d: BUSY clears (mid-flight task pulse is a safe no-op)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV d: CH0DONE set (copy completed normally)", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_bit("G-EV d: CH0ERR stays 0 (mid-flight task pulse is not a reject-at-GO)",
                     to_X01(rdw(DMA_SR_ERR0)), '0');
        bus_read(clk, pbus, rdata, dma_ch_slot(0,2), rdw);
        sb.check_slv("G-EV d: CH0 LEN drained to 0 (no double-run restart)", rdw, x"00000000");
        for k in 0 to 15 loop
            ram_peek1(dma_word_idx(DRAB) + k, got);
            sb.check_slv("G-EV d: DRAB word correct after the mid-flight task pulse (no restart corruption)",
                         got, buf(k));
        end loop;
        sb.check_true("G-EV d: exactly one evt_done(0) pulse (no extra run fired)", evt_done_starts(0) = 1);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        -- (e) reject-at-GO via the tap: with LEN=0 a task_go(0) sets CH0ERR and one evt_err pulse, and the channel never runs.
        dma_enable(pbus, '0', '1');   -- DMAEN=1, DONEIE=0, ERRIE=1
        ram_poke1(dma_word_idx(DSTT), x"5EED5EED");   -- sentinel: proves no transfer happened
        prog_ch(pbus, 0, SRCA, DSTT, 0, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        evt_mon_reset;
        pulse_task_go(0);
        wait for 12 * PERIOD;
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV e: LEN=0 task_go(0) -> CH0ERR", to_X01(rdw(DMA_SR_ERR0)), '1');
        sb.check_bit("G-EV e: LEN=0 task_go(0) -> irq_err asserts (ERRIE=1)", to_X01(irq_err), '1');
        sb.check_bit("G-EV e: LEN=0 task_go(0) -> CH0DONE stays 0 (channel never runs)",
                     to_X01(rdw(DMA_SR_DONE0)), '0');
        sb.check_bit("G-EV e: LEN=0 task_go(0) -> BUSY never asserts", to_X01(rdw(DMA_SR_BUSY)), '0');
        ram_peek1(dma_word_idx(DSTT), got);
        sb.check_slv("G-EV e: LEN=0 task_go(0) -> NO transfer (dst sentinel intact)", got, x"5EED5EED");
        sb.check_true("G-EV e: exactly one evt_err pulse for the task reject-at-GO", evt_err_starts = 1);
        sb.check_true("G-EV e: that evt_err pulse is exactly one clk wide", evt_err_highs = evt_err_starts);
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_ERR0, 32)));

        -- (f) with DONEIE/ERRIE masked off a task-launched copy still produces its evt_done pulse, because the event taps sit ahead of the IE gating.
        -- irq_done stays low, since only the irq path is IE-gated.
        dma_enable(pbus, '0', '0');   -- DMAEN=1, DONEIE=0, ERRIE=0
        prog_ch(pbus, 0, SRCA, DSTT, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        evt_mon_reset;
        pulse_task_go(0);
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G-EV f: BUSY clears (task-launched copy under DONEIE=0/ERRIE=0)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV f: CH0DONE sets even though DONEIE=0 (status is unconditional)",
                     to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_true("G-EV f: evt_done(0) still pulses under DONEIE=0 (EVFAB tap is pre-IE)",
                      evt_done_starts(0) = 1);
        sb.check_bit("G-EV f: irq_done stays low under DONEIE=0 (only the irq path is IE-gated)",
                     to_X01(irq_done), '0');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        -- (g) register-path regression: the producer taps fire for a CPU-launched (register CHnGO) copy too, not only for task_go.
        evt_mon_reset;
        prog_ch(pbus, 0, SRCA, DSTT, 4, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '0');   -- DONEIE=1, which also proves irq_done still works
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        sb.check_true("G-EV g: BUSY clears (register-launched copy)", ok);
        bus_read(clk, pbus, rdata, DMA_SLOT_SR, rdw);
        sb.check_bit("G-EV g: CH0DONE set (register path)", to_X01(rdw(DMA_SR_DONE0)), '1');
        sb.check_true("G-EV g: evt_done(0) pulses once for a REGISTER CHnGO launch too (tap covers both paths)",
                      evt_done_starts(0) = 1);
        sb.check_bit("G-EV g: irq_done still asserts normally on the register path", to_X01(irq_done), '1');
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- GROUP G-NEG: negative control, mandatory and LAST.
        -- Exactly ONE deliberately-wrong expected value: a clean copy checked against a WRONG expected dst word.
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        -- Keep both values' bit 31 CLEAR: periph_tb_pkg's img() renders via to_integer(unsigned(v)) and overflows at >= 2**31.
        ram_poke1(dma_word_idx(SRCA), x"4A11AB1E");
        dma_enable(pbus, '1', '0');
        prog_ch(pbus, 0, SRCA, DSTA, 1, dma_mk_cfg('1','1', DMA_TRIG_MEM, '0','0'));
        dma_go(pbus, "0001", '1', '0');
        dma_wait_busy_clear(clk, pbus, rdata, ok);
        ram_peek1(dma_word_idx(DSTA), got);
        sb.check_slv("NEGATIVE CONTROL: wrong expected dst word (must FAIL)",
                     got, x"5EADC0DE");   -- real value is 0x4A11AB1E
        dma_w1c(pbus, std_logic_vector(to_unsigned(2**DMA_SR_DONE0, 32)));

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("DMA TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   DMA_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   DMA TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   DMA_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
