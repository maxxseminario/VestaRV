-- VestaRV: I2C target
-- Hardware-autonomous I2C slave, one instance I2CT0 at base 0x6A00, sharing the SDA0/SCL0 pad planes with I2C0 through a wired-AND DIR merge.
-- 7-bit address match with mask wildcard and general call, byte-at-a-time RX/TX with ready/empty status, optional clock stretching, START/STOP/repeated-START/NACK framing flags and a stuck-SCL watchdog.
-- Two open-drain pins, DIR only: the MCU ties SDA/SCL OUT to '0', so DIR '1' pulls the line low and '0' releases it, and the lines are never driven high.
-- Two combined IRQs, each (status AND enable) and never latched: vector 122 address/error, vector 123 tx-ready/rx-full.
-- One clock family: the whole engine is mclk-synchronous, SDA_IN/SCL_IN are pure data through 2-FF syncs, and nothing uses falling_edge.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
-- Word slots, field ranges, resets and implemented-bit masks, and the periph_regs
-- tables the bus side is an instance of: generated from hdl/common/regs/rdl/i2ctarget.rdl.
use work.i2ctarget_regs_pkg.all;


entity I2CTarget is
    port (
        clk         : in  std_logic;                     -- free-running MCLK at integration.
                                                         -- Hosts the whole target FSM, the SDA/SCL 2-FF synchronizers, the sticky W1C flags, BUSY/TM, the watchdog and the IRQ combiners.
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_ae      : out std_logic;                     -- address/error IRQ, vector 122 (status AND enable)
        irq_data    : out std_logic;                     -- tx-ready/rx-full IRQ, vector 123 (status AND enable)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier, NEVER a clock
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read, no bridge
        SDA_IN      : in  std_logic;                     -- SDA pad input, 2-FF synced in clk; PURE DATA
        SDA_DIR     : out std_logic;                     -- '1' drives SDA low (an ACK or a '0' data bit), '0' releases to Hi-Z; NEVER driven high
        SCL_IN      : in  std_logic;                     -- SCL pad input, 2-FF synced in clk; PURE DATA
        SCL_DIR     : out std_logic;                     -- '1' holds SCL low (clock stretch), '0' releases

        -- Event-fabric tap (P-mode producer EV14): a registered one-clk pulse at the amf set site, i.e. an address match including a general call, taken before the interrupt enable.
        evt_amf     : out std_logic
    );
end I2CTarget;

architecture behavioral of I2CTarget is


    -- ---- FSM states (plus a bit counter and a 2-bit ACK sub-phase) --------
    type t_i2ct_state is (T_IDLE, T_ADDR, T_ACK_ADDR, T_RX_DATA, T_ACK_RX,
                          T_TX_LOAD, T_TX_DATA, T_TX_ACK, T_IGNORE);
    signal state : t_i2ct_state;

    /* ---- register file (ClkMem domain) -----------------------------------
       The bus side is one work.periph_regs instance driven by
       i2ctarget_regs_pkg's tables; see hdl/common/regs/REGFILE.md. The nine
       per-field flops this block used to keep are the IMPL bits of three stored
       words -- I2CTxCR, I2CTxTX and I2CTxWDG -- sliced back out below. I2CTxSR
       and I2CTxRX hold no flop there: the target FSM owns the flags and the
       receive byte, and they reach the read mux through hw_rd. */
    signal regs_q   : reg_arr_t;                         -- the stored words
    signal hw_rd_s  : reg_arr_t;                         -- read source for everything else
    signal acc_s    : std_logic_vector(0 to NWORDS-1);   -- combinational: this slot, now
    signal sr_rd    : std_logic_vector(31 downto 0);

    -- Field taps out of the stored words, quasi-static.
    signal cr_en     : std_logic;                        -- I2CTxCR.EN
    signal cr_gcen   : std_logic;                        -- I2CTxCR.GCEN
    signal cr_csen   : std_logic;                        -- I2CTxCR.CSEN
    signal cr_aeie   : std_logic;                        -- I2CTxCR.AEIE
    signal cr_dataie : std_logic;                        -- I2CTxCR.DATAIE
    signal cr_sad    : std_logic_vector(6 downto 0);     -- I2CTxCR.SAD
    signal cr_sadm   : std_logic_vector(6 downto 0);     -- I2CTxCR.SADM
    signal tx_byte   : std_logic_vector(7 downto 0);     -- I2CTxTX readback + descriptor
    signal wdg       : std_logic_vector(15 downto 0);    -- I2CTxWDG.WDTO
    signal tx_load_tgl : std_logic;                      -- TX launch toggle
    -- W1C request toggles (ClkMem side), one per W1C flag
    signal clr_amf_tgl     : std_logic;
    signal clr_gcf_tgl     : std_logic;
    signal clr_rxf_tgl     : std_logic;
    signal clr_ovf_tgl     : std_logic;
    signal clr_nackf_tgl   : std_logic;
    signal clr_stopf_tgl   : std_logic;
    signal clr_rstartf_tgl : std_logic;
    signal clr_errf_tgl    : std_logic;

    -- ---- clk-domain sync and CDC -----------------------------------------
    -- The chain flops live inside the work.sync instances below; only their
    -- outputs (*_s2 / *_c2) and the edge-detect copies are signals here.
    signal pad_d, pad_q             : std_logic_vector(1 downto 0); -- 1: SCL_IN, 0: SDA_IN
    signal sda_s2, sda_prev         : std_logic;         -- SDA sync out + prev
    signal scl_s2, scl_prev         : std_logic;         -- SCL sync out + prev
    signal sda_sync, scl_sync       : std_logic;         -- synchronized levels (= s2)
    signal scl_rise, scl_fall       : std_logic;         -- SCL edges (comb)
    signal sda_rise, sda_fall       : std_logic;         -- SDA edges (comb)
    signal start_evt, stop_evt      : std_logic;         -- framing events (comb)
    signal txl_c2                   : std_logic_vector(0 downto 0); -- q of u_sync_tx_load_tgl
    signal txl_prev                 : std_logic;         -- tx_load_tgl edge copy
    signal tx_load_pulse            : std_logic;         -- one-clk launch pulse (comb)
    signal tx_load_pending          : std_logic;         -- ClkMem-read TXE mask (comb)
    -- W1C toggle syncs (ClkMem into clk): eight independent lines, one WIDTH=8 chain
    signal clr_tgl_d, clr_tgl_q     : std_logic_vector(7 downto 0);
    signal camf_c2, camf_p         : std_logic;
    signal cgcf_c2, cgcf_p         : std_logic;
    signal crxf_c2, crxf_p         : std_logic;
    signal covf_c2, covf_p         : std_logic;
    signal cnackf_c2, cnackf_p     : std_logic;
    signal cstopf_c2, cstopf_p     : std_logic;
    signal crstf_c2, crstf_p       : std_logic;
    signal cerrf_c2, cerrf_p       : std_logic;
    -- per-flag one-clk clear pulses (comb)
    signal camf_pulse, cgcf_pulse, crxf_pulse, covf_pulse       : std_logic;
    signal cnackf_pulse, cstopf_pulse, crstf_pulse, cerrf_pulse : std_logic;

    -- ---- FSM datapath (clk domain) ---------------------------------------
    signal bit_cnt   : natural range 0 to 8;             -- bits shifted / presented
    signal ack_phase : natural range 0 to 3;             -- ACK-slot / stretch sub-phase
    signal shift     : std_logic_vector(7 downto 0);     -- MSB-first RX / address shift
    signal rx_data   : std_logic_vector(7 downto 0);     -- last received byte (I2CTRX)
    signal rx_accept : std_logic;                        -- ACK(1)/NACK(0) decision for T_ACK_RX
    signal tx_shift  : std_logic_vector(7 downto 0);     -- MSB-first TX shift
    signal tx_hold   : std_logic_vector(7 downto 0);     -- launch-captured TX byte
    signal tx_loaded : std_logic;                        -- clk-domain: a byte is staged
    signal tx_host_nack : std_logic;                     -- sampled host ACK/NACK in T_TX_ACK
    signal sda_drv   : std_logic;                        -- registered SDA drive-low enable
    signal scl_hold  : std_logic;                        -- registered SCL stretch enable
    signal busy      : std_logic;                        -- bus busy (START..STOP)
    signal tm        : std_logic;                        -- latched RnW (1 = target-transmitter)
    signal amf, gcf, rxf, ovf, nackf : std_logic;        -- sticky W1C flags
    signal stopf, rstartf, errf      : std_logic;        -- sticky W1C flags
    signal tx_e_level : std_logic;                       -- raw TXE (transmit-needs-data and not loaded)
    signal wdg_pre : std_logic_vector(7 downto 0);       -- 8-bit 256-clk prescale
    signal wdg_cnt : std_logic_vector(15 downto 0);      -- 16-bit SCL-low compare counter

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- Field taps out of the register file. The positions are
    -- i2ctarget_regs_pkg's, so no bit literal in this file describes a register.
    cr_en     <= regs_q(SLOT_CR)(I2CTEN_LSB);
    cr_gcen   <= regs_q(SLOT_CR)(I2CTGCEN_LSB);
    cr_csen   <= regs_q(SLOT_CR)(I2CTCSEN_LSB);
    cr_aeie   <= regs_q(SLOT_CR)(I2CTAEIE_LSB);
    cr_dataie <= regs_q(SLOT_CR)(I2CTDATAIE_LSB);
    cr_sad    <= regs_q(SLOT_CR)(I2CTSAD_MSB downto I2CTSAD_LSB);
    cr_sadm   <= regs_q(SLOT_CR)(I2CTSADM_MSB downto I2CTSADM_LSB);
    tx_byte   <= regs_q(SLOT_TX)(I2CTTX_MSB downto I2CTTX_LSB);
    wdg       <= regs_q(SLOT_WDG)(I2CTWDTO_MSB downto I2CTWDTO_LSB);

    -- Pad drive: open-drain, DIR-only, NEVER driven high.
    -- The MCU ties SDA0/SCL0 OUT to '0' and wired-AND-merges these DIR planes with I2C0.
    SDA_DIR <= sda_drv;
    SCL_DIR <= scl_hold;

    -- Synchronized bus levels and edges: PURE DATA, never a clock.
    -- Two independent 2-FF chains, so at a real SCL edge the sampled SDA and SCL phases can differ by 1 clk; the framing qualifier below guards that hazard.
    sda_sync <= sda_s2;
    scl_sync <= scl_s2;
    scl_rise <= scl_sync and not scl_prev;
    scl_fall <= (not scl_sync) and scl_prev;
    sda_rise <= sda_sync and not sda_prev;
    sda_fall <= (not sda_sync) and sda_prev;
    -- START = SDA falls while SCL is stably high (>=2 samples); STOP = SDA rises while SCL is stably high.
    -- Hazard guard: a normal data transition moves SDA while SCL is LOW, so it can never masquerade as a framing event.
    start_evt <= '1' when (sda_fall = '1' and scl_sync = '1' and scl_prev = '1') else '0';
    stop_evt  <= '1' when (sda_rise = '1' and scl_sync = '1' and scl_prev = '1') else '0';

    -- TX launch pulse: edge of the 2-FF-synced tx_load_tgl.
    tx_load_pulse <= '1' when (txl_c2(0) /= txl_prev) else '0';
    -- The RAW ClkMem-domain tx_load_tgl compared against its deepest clk-synced stage, so it is high from the I2CTTX write until the FSM consumes the launch.
    -- Read by the ClkMem SR mux only, where it masks TXE so a poll right after an I2CTTX write never reads stale-empty.
    tx_load_pending <= '1' when (tx_load_tgl /= txl_prev) else '0';

    -- W1C one-clk clear pulses: the edge of each 2-FF-synced clr toggle.
    camf_pulse   <= '1' when (camf_c2   /= camf_p)   else '0';
    cgcf_pulse   <= '1' when (cgcf_c2   /= cgcf_p)   else '0';
    crxf_pulse   <= '1' when (crxf_c2   /= crxf_p)   else '0';
    covf_pulse   <= '1' when (covf_c2   /= covf_p)   else '0';
    cnackf_pulse <= '1' when (cnackf_c2 /= cnackf_p) else '0';
    cstopf_pulse <= '1' when (cstopf_c2 /= cstopf_p) else '0';
    crstf_pulse  <= '1' when (crstf_c2  /= crstf_p)  else '0';
    cerrf_pulse  <= '1' when (cerrf_c2  /= cerrf_p)  else '0';

    -- Raw TXE: high only in the transmit-needs-data phase with no byte staged, derived in the clk domain from state and tx_loaded alone.
    -- Read by the SR mux behind the tx_load_pending mask, and fed raw to irq_data.
    tx_e_level <= '1' when (state = T_TX_LOAD and tx_loaded = '0') else '0';

    -- Combined IRQs = (status and enable), combinational and never latched.
    -- AEIE and DATAIE are quasi-static ClkMem CR bits, read directly.
    irq_ae   <= (amf or gcf or ovf or nackf or stopf or rstartf or errf) and cr_aeie;
    irq_data <= (rxf or tx_e_level) and cr_dataie;

    /* ------------------------- register file (ClkMem) -------------------------
       One periph_regs instance replaces the case decode, the byte-lane merge,
       the reset branch and the registered read mux.

       WIDEWR marks I2CTxCR and I2CTxWDG as the two words any enabled lane writes
       whole: the decode this replaces qualified every write on WEn(0) alone and
       then wrote SAD at bits 14:8 and SADM at 22:16, which reach lanes 1 and 2,
       and WDTO at 15:0, which reaches lane 1. I2CTxTX (bits 7:0) is inside lane
       0 either way. STROBE_HOLD is immaterial and left false, because this block
       uses no registered strobe; see reg_req below. */
    hw_rd_s <= (SLOT_SR => sr_rd,
                SLOT_RX => (31 downto I2CTRX_MSB + 1 => '0') & rx_data,
                others  => (others => '0'));

    /* I2CTxSR: the sticky flags plus BUSY/TM/TXE are read RAW from the clk
       domain and the module's read register IS their synchronization, so there
       is no pre-latch and no bridge. TXE is masked by tx_load_pending, so a poll
       immediately after an I2CTxTX write never sees stale-empty. */
    sr_rd <= (31 downto I2CTERRF_MSB + 1 => '0') & errf & rstartf & stopf & nackf & ovf &
             (tx_e_level and not tx_load_pending) & rxf & gcf & amf & tm & busy;

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
            WIDEWR      => "10001",
            STROBE_HOLD => false)
        port map (
            ClkMem      => ClkMem,
            resetn      => resetn,
            EnMemPeriph => EnMemPeriph,
            WEn         => WEn,
            MABPart     => MABPart,
            wdata       => wdata,
            rdata_out   => rdata_out,
            regs        => regs_q,
            hw_rd       => hw_rd_s,
            acc_hit     => acc_s,
            rd_strobe   => open,
            wr_strobe   => open,
            wr_pulse    => open,
            w1c_hit     => open,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    /* ------------------------- launch + W1C toggles (ClkMem) ------------------
       What is left of the old register-write process: an I2CTxTX write both
       loads the buffer (which periph_regs now holds) and LAUNCHES, and an SR
       write of 1 flips the matching clr_<flag>_tgl.

       Both take the COMBINATIONAL acc_hit and not the module's registered
       wr_strobe / w1c_hit, because ClkMem is gated by EnMemPeriph in this block:
       one bus access presents exactly ONE rising ClkMem edge, so a strobe flop
       SET on that edge is sampled a whole bus access late, and STROBE_HOLD =
       true retires it asynchronously at deselect before any edge can see it at
       all. acc_hit reproduces the old decode's condition exactly, so the launch
       still lands on the edge the write does. */
    reg_req: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            tx_load_tgl     <= '0';
            clr_amf_tgl     <= '0';
            clr_gcf_tgl     <= '0';
            clr_rxf_tgl     <= '0';
            clr_ovf_tgl     <= '0';
            clr_nackf_tgl   <= '0';
            clr_stopf_tgl   <= '0';
            clr_rstartf_tgl <= '0';
            clr_errf_tgl    <= '0';
        elsif rising_edge(ClkMem) then
            if acc_s(SLOT_TX) = '1' and WEn(0) = '0' then
                tx_load_tgl <= not tx_load_tgl;
            end if;
            if acc_s(SLOT_SR) = '1' and WEn(0) = '0' then
                -- W1C: BUSY (0), TM (1) and TXE (5) are read-only and ignored.
                if wdata(I2CTAMF_LSB)     = '1' then clr_amf_tgl     <= not clr_amf_tgl;     end if;
                if wdata(I2CTGCF_LSB)     = '1' then clr_gcf_tgl     <= not clr_gcf_tgl;     end if;
                if wdata(I2CTRXF_LSB)     = '1' then clr_rxf_tgl     <= not clr_rxf_tgl;     end if;
                if wdata(I2CTOVF_LSB)     = '1' then clr_ovf_tgl     <= not clr_ovf_tgl;     end if;
                if wdata(I2CTNACKF_LSB)   = '1' then clr_nackf_tgl   <= not clr_nackf_tgl;   end if;
                if wdata(I2CTSTOPF_LSB)   = '1' then clr_stopf_tgl   <= not clr_stopf_tgl;   end if;
                if wdata(I2CTRSTARTF_LSB) = '1' then clr_rstartf_tgl <= not clr_rstartf_tgl; end if;
                if wdata(I2CTERRF_LSB)    = '1' then clr_errf_tgl    <= not clr_errf_tgl;    end if;
            end if;
        end if;
    end process reg_req;

    /* ------------------------- clk-domain sync and CDC ------------------------
       Three work.sync chains: the SDA/SCL pads, the tx_load_tgl launch toggle and the eight W1C clr_<flag>_tgl toggles, each a bundle of INDEPENDENT single-bit lines and never a bus.
       The one-clk prev copies that turn a chain output into an edge stay in the process below: they are local edge detect, not part of the crossing.
       Single edge (rising clk) only, reset from resetn; SDA and SCL are PURE DATA here, never a clock. */
    pad_d <= SCL_IN & SDA_IN;

    -- Idle-high open-drain bus, so the chain resets to "11" and no false START appears out of reset.
    u_sync_sda_scl : entity work.sync
        generic map (WIDTH => 2, DEPTH => 2, RST_VAL => "11")
        port map (clk => clk, areset => resetn, d => pad_d, q => pad_q);

    sda_s2 <= pad_q(0);
    scl_s2 <= pad_q(1);

    u_sync_tx_load_tgl : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => clk, areset => resetn, d(0) => tx_load_tgl, q => txl_c2);

    clr_tgl_d <= clr_errf_tgl & clr_rstartf_tgl & clr_stopf_tgl & clr_nackf_tgl &
                 clr_ovf_tgl & clr_rxf_tgl & clr_gcf_tgl & clr_amf_tgl;

    u_sync_clr_tgl : entity work.sync
        generic map (WIDTH => 8, DEPTH => 2)
        port map (clk => clk, areset => resetn, d => clr_tgl_d, q => clr_tgl_q);

    camf_c2   <= clr_tgl_q(0);
    cgcf_c2   <= clr_tgl_q(1);
    crxf_c2   <= clr_tgl_q(2);
    covf_c2   <= clr_tgl_q(3);
    cnackf_c2 <= clr_tgl_q(4);
    cstopf_c2 <= clr_tgl_q(5);
    crstf_c2  <= clr_tgl_q(6);
    cerrf_c2  <= clr_tgl_q(7);

    bus_sync: process(resetn, clk)
    begin
        if resetn = '0' then
            sda_prev <= '1';   -- idle-high open-drain bus
            scl_prev <= '1';
            txl_prev <= '0';
            camf_p <= '0'; cgcf_p <= '0'; crxf_p <= '0'; covf_p <= '0';
            cnackf_p <= '0'; cstopf_p <= '0'; crstf_p <= '0'; cerrf_p <= '0';
        elsif rising_edge(clk) then
            -- prev copies of the SYNCHRONIZED nets, so edge detect never sees a raw pad.
            sda_prev <= sda_s2;
            scl_prev <= scl_s2;
            txl_prev <= txl_c2(0);
            camf_p   <= camf_c2;
            cgcf_p   <= cgcf_c2;
            crxf_p   <= crxf_c2;
            covf_p   <= covf_c2;
            cnackf_p <= cnackf_c2;
            cstopf_p <= cstopf_c2;
            crstf_p  <= crstf_c2;
            cerrf_p  <= cerrf_c2;
        end if;
    end process;

    /* ------------------------- target FSM (clk) -------------------------------
       The whole autonomous target engine on the free-running clk: it drives the REGISTERED sda_drv and scl_hold, never a combinational mux off a bus edge, owns the sticky W1C flags, BUSY/TM, the shift registers and the watchdog, and reads the quasi-static CR fields EN/GCEN/CSEN/SAD/SADM/WDTO directly.
       Bits are sampled on scl_rise and driven on scl_fall, and SDA only ever changes AFTER scl_fall with SCL confirmed low through the sync, so the FSM can never glitch a false START or STOP.
       Set-wins ordering: the default W1C clears run FIRST, and the FSM and framing SETs run later and override a coincident clear. */
    fsm: process(resetn, clk)
        variable full   : std_logic_vector(7 downto 0);
        variable addr7  : std_logic_vector(6 downto 0);
        variable rnw    : std_logic;
        variable match  : boolean;
        variable gc     : boolean;
    begin
        if resetn = '0' then
            state     <= T_IDLE;
            bit_cnt   <= 0;
            ack_phase <= 0;
            shift     <= (others => '0');
            rx_data   <= (others => '0');
            rx_accept <= '0';
            tx_shift  <= (others => '0');
            tx_hold   <= (others => '0');
            tx_loaded <= '0';
            tx_host_nack <= '0';
            sda_drv   <= '0';
            scl_hold   <= '0';
            busy      <= '0';
            tm        <= '0';
            amf       <= '0';
            gcf       <= '0';
            rxf       <= '0';
            ovf       <= '0';
            nackf     <= '0';
            stopf     <= '0';
            rstartf   <= '0';
            errf      <= '0';
            wdg_pre   <= (others => '0');
            wdg_cnt   <= (others => '0');
            evt_amf   <= '0';
        elsif rising_edge(clk) then

            -- Event-fabric tap: a registered one-clk pulse, default-cleared every cycle and set ONLY at the amf set site below.
            -- It fires on every address match, even when amf was already sticky-set, and cr_aeie never touches it.
            evt_amf <= '0';

            -- (1) W1C default clears (SET below wins over a coincident clear).
            if camf_pulse   = '1' then amf     <= '0'; end if;
            if cgcf_pulse   = '1' then gcf     <= '0'; end if;
            if crxf_pulse   = '1' then rxf     <= '0'; end if;
            if covf_pulse   = '1' then ovf     <= '0'; end if;
            if cnackf_pulse = '1' then nackf   <= '0'; end if;
            if cstopf_pulse = '1' then stopf   <= '0'; end if;
            if crstf_pulse  = '1' then rstartf <= '0'; end if;
            if cerrf_pulse  = '1' then errf    <= '0'; end if;

            -- (2) TX launch capture: co-sample the quasi-static tx_byte into tx_hold on the launch edge and stage it, data before flag.
            if tx_load_pulse = '1' then
                tx_hold   <= tx_byte;
                tx_loaded <= '1';
            end if;

            if cr_en = '0' then
                -- EN=0 forces the FSM idle with SDA and SCL released, preserving the flags, the RX byte, tx_loaded and tm.
                -- The W1C clears above still apply, so a flag can still be cleared while the target is disabled.
                state     <= T_IDLE;
                busy      <= '0';
                sda_drv   <= '0';
                scl_hold   <= '0';
                ack_phase <= 0;
                wdg_pre   <= (others => '0');
                wdg_cnt   <= (others => '0');
            else

                -- (3) per-state FSM.
                -- Registered outputs HOLD between the edges that change them, so there is no default assignment at the top: a driven ACK must survive until its trailing fall.
                case state is

                    when T_IDLE =>
                        null;   -- wait for START (framing override below)

                    when T_ADDR =>
                        -- Shift the 8 address bits MSB-first on scl_rise.
                        if scl_rise = '1' then
                            full := shift(6 downto 0) & sda_sync;
                            shift <= full;
                            if bit_cnt = 7 then
                                -- 8th bit complete: byte = {ADDR[6:0], RnW}
                                addr7 := full(7 downto 1);
                                rnw   := full(0);
                                match := ((not (addr7 xor cr_sad)) or cr_sadm) = "1111111";
                                gc    := (cr_gcen = '1') and (addr7 = "0000000") and (rnw = '0');
                                bit_cnt   <= 0;
                                ack_phase <= 0;
                                if match or gc then
                                    amf <= '1';
                                    evt_amf <= '1';   -- the event-fabric tap fires here
                                    if gc then gcf <= '1'; end if;
                                    tm  <= rnw;   -- latch the transfer direction
                                    state <= T_ACK_ADDR;
                                else
                                    -- no match: silent ignore, drive NO ACK
                                    sda_drv <= '0';
                                    scl_hold <= '0';
                                    state   <= T_IGNORE;
                                end if;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        end if;

                    when T_ACK_ADDR =>
                        -- Drive the address ACK: pull SDA low on the scl_fall after bit 8, then release and branch on the next scl_fall.
                        if scl_fall = '1' then
                            if ack_phase = 0 then
                                sda_drv   <= '1';   -- ACK = drive low
                                ack_phase <= 1;
                            else
                                sda_drv   <= '0';   -- release the ACK
                                ack_phase <= 0;
                                bit_cnt   <= 0;
                                if tm = '1' then
                                    state <= T_TX_LOAD;   -- host read
                                else
                                    state <= T_RX_DATA;   -- host write
                                end if;
                            end if;
                        end if;

                    when T_RX_DATA =>
                        -- Shift 8 data bits MSB-first on scl_rise, then accept or NACK on bit 8.
                        if scl_rise = '1' then
                            full := shift(6 downto 0) & sda_sync;
                            shift <= full;
                            if bit_cnt = 7 then
                                bit_cnt   <= 0;
                                ack_phase <= 0;
                                if rxf = '0' then
                                    -- buffer free: ACK, latch, set RXF
                                    rx_data   <= full;
                                    rxf       <= '1';
                                    rx_accept <= '1';
                                else
                                    -- buffer full: auto-NACK-on-full, OVF
                                    ovf       <= '1';
                                    nackf     <= '1';
                                    rx_accept <= '0';
                                end if;
                                state <= T_ACK_RX;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        end if;

                    when T_ACK_RX =>
                        -- Drive the RX ACK/NACK; on the trailing fall hold the RX stretch if CSEN is set and the byte is still unread, else proceed to the next byte.
                        if ack_phase = 2 then
                            -- RX stretch wait: release SCL once RXF clears, i.e. after the firmware read and its W1C.
                            if rxf = '0' then
                                scl_hold   <= '0';
                                ack_phase <= 0;
                                bit_cnt   <= 0;
                                state     <= T_RX_DATA;
                            end if;
                        elsif scl_fall = '1' then
                            if ack_phase = 0 then
                                sda_drv   <= rx_accept;   -- ACK(1)/NACK(0)
                                ack_phase <= 1;
                            else
                                sda_drv <= '0';           -- release
                                if cr_csen = '1' and rxf = '1' then
                                    scl_hold   <= '1';     -- assert RX stretch
                                    ack_phase <= 2;
                                else
                                    ack_phase <= 0;
                                    bit_cnt   <= 0;
                                    state     <= T_RX_DATA;
                                end if;
                            end if;
                        end if;

                    when T_TX_LOAD =>
                        -- SCL-low wait state, not edge-gated: present the staged byte as soon as one is available, otherwise raise TXE and, with CSEN set, hold the TX stretch.
                        if tx_loaded = '1' then
                            sda_drv   <= not tx_hold(7);          -- present bit 7
                            tx_shift  <= tx_hold(6 downto 0) & '0';
                            tx_loaded <= '0';
                            scl_hold   <= '0';                     -- drop any stretch
                            bit_cnt   <= 1;                       -- bit 7 presented
                            state     <= T_TX_DATA;
                        else
                            if cr_csen = '1' then
                                scl_hold <= '1';                   -- TX stretch
                            else
                                -- no stretch: transmit 0xFF, SDA released
                                sda_drv  <= '0';
                                tx_shift <= "11111110";
                                bit_cnt  <= 1;
                                state    <= T_TX_DATA;
                            end if;
                        end if;

                    when T_TX_DATA =>
                        -- shift out the remaining bits MSB-first on scl_fall; the host samples each one on scl_rise.
                        -- After 8 bits, release the line for the host ACK/NACK slot.
                        if scl_fall = '1' then
                            if bit_cnt = 8 then
                                sda_drv   <= '0';   -- release for host ACK
                                ack_phase <= 0;
                                state     <= T_TX_ACK;
                            else
                                sda_drv  <= not tx_shift(7);
                                tx_shift <= tx_shift(6 downto 0) & '0';
                                bit_cnt  <= bit_cnt + 1;
                            end if;
                        end if;

                    when T_TX_ACK =>
                        -- Sample the host ACK/NACK on the 9th scl_rise; on the trailing fall either continue (ACK) or wait for STOP or a repeated START (NACK).
                        if ack_phase = 0 then
                            if scl_rise = '1' then
                                if sda_sync = '1' then
                                    tx_host_nack <= '1';   -- host NACK: done reading
                                    nackf        <= '1';
                                else
                                    tx_host_nack <= '0';   -- host ACK: wants more
                                end if;
                                ack_phase <= 1;
                            end if;
                        else
                            if scl_fall = '1' then
                                ack_phase <= 0;
                                if tx_host_nack = '1' then
                                    state <= T_IGNORE;     -- release, wait STOP/Sr
                                else
                                    state <= T_TX_LOAD;    -- raise TXE / next byte
                                end if;
                            end if;
                        end if;

                    when T_IGNORE =>
                        null;   -- address mismatch or read done: wait for STOP or Sr

                    when others =>
                        state <= T_IDLE;   -- unreachable; recover to idle

                end case;

                -- (4) Framing overrides run AFTER the case, so a START, STOP or repeated START at ANY bus phase wins and releases SDA_DIR and the stretch: the target never holds the bus across a boundary.
                -- STOP and START are mutually exclusive: SDA cannot both rise and fall in one cycle.
                if stop_evt = '1' then
                    stopf     <= '1';
                    busy      <= '0';
                    sda_drv   <= '0';
                    scl_hold   <= '0';
                    ack_phase <= 0;
                    state     <= T_IDLE;   -- a STOP mid-byte discards the partial
                end if;
                if start_evt = '1' then
                    -- A START while BUSY is a repeated START, so re-address and hold BUSY.
                    -- A START while idle is an initial START.
                    if busy = '1' then
                        rstartf <= '1';
                    else
                        busy <= '1';
                    end if;
                    sda_drv   <= '0';
                    scl_hold   <= '0';
                    ack_phase <= 0;
                    bit_cnt   <= 0;
                    shift     <= (others => '0');
                    state     <= T_ADDR;
                end if;

                -- (5) Watchdog: count the SCL-low duration while BUSY, in units of 256 clk, resetting whenever BUSY is low or SCL is not low; WDTO=0 disables it.
                -- On expiry it sets ERRF, drops BUSY, releases the bus and forces T_IDLE, overriding the FSM.
                if busy = '0' or scl_sync = '1' then
                    wdg_pre <= (others => '0');
                    wdg_cnt <= (others => '0');
                elsif wdg /= "0000000000000000" then
                    if wdg_pre = "11111111" then
                        wdg_pre <= (others => '0');
                        if wdg_cnt = wdg then
                            errf      <= '1';
                            busy      <= '0';
                            sda_drv   <= '0';
                            scl_hold   <= '0';
                            ack_phase <= 0;
                            state     <= T_IDLE;
                            wdg_cnt   <= (others => '0');
                        else
                            wdg_cnt <= wdg_cnt + 1;
                        end if;
                    else
                        wdg_pre <= wdg_pre + 1;
                    end if;
                end if;

            end if;
        end if;
    end process;

end behavioral;
