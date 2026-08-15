library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ===========================================================================
-- OneWire: Dallas/Maxim 1-Wire MASTER.
-- Link-layer primitives off a programmable time base: reset plus presence, write-bit, read-bit, write-byte, read-byte.
-- ROM search and CRC-8 stay in firmware over these bit primitives.
-- Standard and overdrive speeds; strong-pullup is a reserved register stub (no driven-high phase).
-- One open-drain DQ pin, one combined IRQ on vector 117, base 0x6700.
-- FROZEN design: ~/vesta_docs/digperiphs/onewire_design.md (decisions D1-D16, orchestrator adjudications A1-A5, ALL BINDING; A-rulings override any conflicting Dn text).
-- Peripheral #5 of the digital-peripherals program.
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary reduce, no reading of out ports).
-- Every process infers exactly ONE edge of ONE clock, and every synchronizer is single-edge (Genus VHDL-601 discipline).
-- NO falling_edge of anything, anywhere (specifically NOT of EnMemPeriph).
--
-- D1/D2, ONE clock family: all protocol logic (time base, slot FSM, DQ synchronizer, sticky W1C flags, PRES/BUSY, IRQ combiner) rides the free-running `clk`, wired to MCLK at integration.
-- No independent domain, no async-FIFO, no true CDC: every hand-off between ClkMem and clk is a TOGGLE or a HELD/quasi-static LEVEL (kept standalone-honest per the RTC precedent).
-- No clock gate anywhere: OW0DIV is a counter-compare tick generator, not a ClkGate.
-- `OW_DQ_IN` is 2-FF synchronized in `clk` and is PURE DATA: it never clocks a flop (D10, the deliberate contrast with I3C's SDA_IN, which clocked ibi_req directly and became a real SDC clock / Genus power-engine defect).
-- D4: all bus-facing capture is synchronous to the ClkMem RISING edge, EnMemPeriph-qualified as a LEVEL only (never a clock, never an edge), xcollapse-clean by construction with no falling_edge(EnMemPeriph) pre-latch.
--
-- CDC CROSSING INVENTORY (toggle / held-level only, no async FIFO):
--   1. LAUNCH, ClkMem into clk (D8): a lane-0 OW0CMD write ALWAYS captures {OP,BITVAL,ODS,OW0TX} into the desc_* descriptor and flips launch_tgl IF NOT (OWEN=0 or busy_sync=1).
--      clk 2-FFs launch_tgl, edge-detects it, and on the edge co-samples the (quasi-static) descriptor into latched_*: data before flag, no async FIFO.
--   2. BUSY, clk into ClkMem (D8): busy (the clk FSM level) is 2-FF synchronized into ClkMem as busy_sync, read by the launch-suppress logic AND the SR read mux.
--      That is the ONE crossing with a real 2-FF; everything else below is a direct quasi-static tap per D12.
--   3. W1C, ClkMem into clk (D12): a lane-0 SR write of 1 to TCIF/NOPRES/SHORT flips clr_*_tgl.
--      clk 2-FFs and edge-detects each into a one-cycle clear pulse, applied in the SAME process that owns the flag; SET WINS over a coincident CLEAR (RTC D10 discipline: the case-statement SET assignment executes AFTER the default CLEAR, so it overrides).
--   4. STATUS, clk into ClkMem (D12): TCIF/PRES/NOPRES/SHORT/RX are clk-domain quasi-static levels sampled DIRECTLY by the ClkMem read mux (coincident nets at integration, D1), the RTC almf_flag/tickf_flag precedent.
--   5. DQ, pad into clk (D10): OW_DQ_IN is 2-FF synchronized (dq_s1/dq_s2) into dq_sync, sampled at the frozen tick counts.
--      Pure data, never a clock.
--   6. DIV, ClkMem into clk (D6): OW0DIV is a plain rw register (no commit protocol); the clk-domain divider reads it directly (quasi-static level, coincident nets at integration, D1).
--   7. RESET (D14): resetn is the chip async reset, applied DIRECTLY to both the clk and ClkMem processes, so no reset synchronizer is needed (no truly-async always-on domain exists here, unlike the RTC's LFXT).
--   8. IRQ (D13): irq_ow = (TCIF and TCIE) or ((NOPRES or SHORT) and ERRIE), combinational, never latched; TCIE/ERRIE are quasi-static CR bits.
--
-- Register map (D5; base 0x6700, slot n at 0x6700 + 4n, off MABPart(7:2)):
--   0 OW0CR  : [0]OWEN [1]ODS [2]SPUEN(rsvd stub) [3]TCIE [4]ERRIE, 31:5 rsvd.
--   1 OW0CMD : lane-0 write LAUNCHES (D8). [2:0]OP [8]BITVAL, rest rsvd.
--              Content always captured; launch suppressed on OWEN=0/BUSY=1.
--   2 OW0TX  : [7:0] next write byte (WRBYTE source). Write never launches.
--   3 OW0RX  : [7:0] last RDBYTE / [0] last RDBIT, side-effect-free read.
--   4 OW0DIV : [15:0] time-base divisor; tick every OW0DIV+1 clk cycles.
--   5 OW0SR  : [0]BUSY ro [1]TCIF W1C [2]PRES ro [3]NOPRES W1C [4]SHORT W1C.
--   6 OW0SPU : reserved (D15): reads 0, writes ignored. Slots >=7 read 0.
--
-- TIME BASE (A1 BINDING: 0.5us tick, NOT the D7 draft's 1us tick, so every D7 count below is DOUBLED from the design doc's original table).
-- Nominal OW0DIV=11 at 24 MHz MCLK gives 12 clk cycles = 0.5us/tick.
--   symbol  STD ticks (us)   OD ticks (us)
--   tRSTL   960  (480us)     96  (48us)
--   tPRES   140  (70us)      18  (9us)
--   tRSTH   960  (480us)     96  (48us)
--   tW1L    12   (6us)       2   (1us)
--   tW0L    120  (60us)      16  (8us)
--   tSLOT   140  (70us)      20  (10us)
--   tRL     12   (6us)       2   (1us)
--   tMSR    26   (13us)      3   (1.5us)  A1 OVERRIDE, not a naive double
--                                            (a naive double of 2 ticks = 4
--                                            would land tRDV exactly AT the
--                                            Maxim OD 2us edge; A1 places the
--                                            OD read sample at 3 ticks =
--                                            1.5us, safely inside tRDV < 2us)
--   tREC    4    (2us)       4   (2us)
-- Reset slot = tRSTL low plus release, presence sampled tPRES after release, then tRSTH high (SHORT check at end).
-- Write/read slot = drive-low phase plus release to tSLOT, then tREC (SHORT check at end).
-- A5: SHORT WINS, so if the bus is still low at end-of-recovery during a RESET, SHORT sets and NOPRES is SUPPRESSED (presence is unevaluable on a stuck bus).
-- NOPRES commits only after a clean high release at end-of-recovery with no presence pulse seen.
--
-- Architecture (block summary, D3/B1-B4).
-- B1 register file (ClkMem): CR/CMD-launch-capture/TX/DIV stores, SR W1C toggles, registered read mux.
-- B2 CDC (clk): launch_tgl/clr_*_tgl 2-FF plus edge-detect, OW_DQ_IN 2-FF sync.
-- B3 time base (clk): OW0DIV reload down-counter producing a one-cycle tick, no clock gate.
-- B4 slot/protocol FSM (clk): tick-counted slot sequencer selecting the table above by latched ODS; drives dq_drive_low; samples dq_sync at tPRES/tMSR; produces PRES/NOPRES/SHORT/RX; BUSY while running; TCIF at completion.
-- Pad drive (D11, combinational): OW_DQ_OUT is fixed '0' and OW_DQ_DIR takes dq_drive_low (the registered FSM output), so DQ is NEVER driven high.
-- ===========================================================================

entity OneWire is
    port (
        clk         : in  std_logic;                     -- free-running fast reference, MCLK at integration (D2); hosts the OW0DIV time base, the slot FSM, the DQ synchronizer, the sticky W1C flags, BUSY/PRES, and the IRQ combiner (D1)
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_ow      : out std_logic;                     -- combined TC/error IRQ (vector 117)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (D4: NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);
        OW_DQ_IN    : in  std_logic;                     -- DQ pad input, 2-FF synced in clk (D10); PURE DATA, never a clock
        OW_DQ_OUT   : out std_logic;                     -- fixed '0' (open-drain, D11)
        OW_DQ_DIR   : out std_logic                      -- '1' drives DQ low, '0' releases Hi-Z
    );
end OneWire;

architecture behavioral of OneWire is

    -- ---- word-slot map (frozen, D5) --------------------------------------
    constant SLOT_CR  : natural := 0;
    constant SLOT_CMD : natural := 1;
    constant SLOT_TX  : natural := 2;
    constant SLOT_RX  : natural := 3;
    constant SLOT_DIV : natural := 4;
    constant SLOT_SR  : natural := 5;
    constant SLOT_SPU : natural := 6;

    -- ---- OP encoding (D9) -------------------------------------------------
    constant OP_RESET  : std_logic_vector(2 downto 0) := "000";
    constant OP_WRBIT  : std_logic_vector(2 downto 0) := "001";
    constant OP_RDBIT  : std_logic_vector(2 downto 0) := "010";
    constant OP_WRBYTE : std_logic_vector(2 downto 0) := "011";
    constant OP_RDBYTE : std_logic_vector(2 downto 0) := "100";

    -- ---- slot-timing table, half-us ticks (A1 BINDING; doubled D7) --------
    constant OW_STD_TRSTL : natural := 960;
    constant OW_STD_TPRES : natural := 140;
    constant OW_STD_TRSTH : natural := 960;
    constant OW_STD_TW1L  : natural := 12;
    constant OW_STD_TW0L  : natural := 120;
    constant OW_STD_TSLOT : natural := 140;
    constant OW_STD_TRL   : natural := 12;
    constant OW_STD_TMSR  : natural := 26;
    constant OW_STD_TREC  : natural := 4;

    constant OW_OD_TRSTL : natural := 96;
    constant OW_OD_TPRES : natural := 18;
    constant OW_OD_TRSTH : natural := 96;
    constant OW_OD_TW1L  : natural := 2;
    constant OW_OD_TW0L  : natural := 16;
    constant OW_OD_TSLOT : natural := 20;
    constant OW_OD_TRL   : natural := 2;
    constant OW_OD_TMSR  : natural := 3;   -- A1 override (not a naive double)
    constant OW_OD_TREC  : natural := 4;

    -- ---- B4 FSM states (D3/B4) --------------------------------------------
    type t_ow_state is (OW_IDLE, R_LOW, R_REL, R_SAMPLE, R_HIGH,
                         W_LOW, W_REL, W_REC,
                         RD_LOW, RD_REL, RD_SAMPLE, RD_FILL, RD_REC,
                         OW_DONE);
    signal ow_state : t_ow_state;

    -- ---- B1 register-file storage (ClkMem domain) --------------------------
    signal ow_cr        : std_logic_vector(4 downto 0);   -- OWEN/ODS/SPUEN/TCIE/ERRIE
    signal ow_cmd_op    : std_logic_vector(2 downto 0);   -- CMD readback: last-written OP
    signal ow_cmd_bitval: std_logic;                      -- CMD readback: last-written BITVAL
    signal ow_tx        : std_logic_vector(7 downto 0);   -- OW0TX
    signal ow_div       : std_logic_vector(15 downto 0);  -- OW0DIV
    signal desc_op      : std_logic_vector(2 downto 0);   -- D8 launch descriptor: OP
    signal desc_bitval  : std_logic;                      -- D8 launch descriptor: BITVAL
    signal desc_ods     : std_logic;                      -- D8 launch descriptor: ODS
    signal desc_tx      : std_logic_vector(7 downto 0);   -- D8 launch descriptor: TX byte
    signal launch_tgl   : std_logic;                      -- D8 launch request toggle
    signal clr_tcif_tgl  : std_logic;                     -- D12 W1C TCIF request toggle
    signal clr_nopres_tgl: std_logic;                     -- D12 W1C NOPRES request toggle
    signal clr_short_tgl : std_logic;                     -- D12 W1C SHORT request toggle
    signal ow_slot       : natural range 0 to 63;         -- decoded word slot

    -- ---- B2 busy_sync (ClkMem domain, real 2-FF, D8) -----------------------
    signal busy_c1, busy_c2 : std_logic;
    signal busy_sync        : std_logic;

    -- ---- B2 clk-domain CDC: toggle syncs + edge-detect (D8/D10/D12) --------
    signal lnch_c1, lnch_c2, lnch_prev             : std_logic;
    signal clrtcif_c1, clrtcif_c2, clrtcif_prev     : std_logic;
    signal clrnopres_c1, clrnopres_c2, clrnopres_prev : std_logic;
    signal clrshort_c1, clrshort_c2, clrshort_prev  : std_logic;
    signal dq_s1, dq_s2 : std_logic;                      -- D10 DQ 2-FF sync
    signal dq_sync      : std_logic;
    signal launch_pulse, clr_tcif_pulse, clr_nopres_pulse, clr_short_pulse : std_logic;
    signal launch_pending : std_logic;                    -- SR.BUSY assert cover (adjudication)

    -- ---- B3 time base (clk domain, D6) -------------------------------------
    signal div_cnt : std_logic_vector(15 downto 0);
    signal tick    : std_logic;

    -- ---- B4 FSM datapath (clk domain) ---------------------------------------
    signal phase_cnt : natural range 0 to 4095;   -- generous headroom over max 960 (D6)
    signal bit_idx    : natural range 0 to 7;
    signal bit_total  : natural range 0 to 8;
    signal latched_op     : std_logic_vector(2 downto 0);
    signal latched_bitval : std_logic;
    signal latched_ods    : std_logic;
    signal latched_tx     : std_logic_vector(7 downto 0);
    signal rx_shift       : std_logic_vector(7 downto 0);
    signal wr_bit_val      : std_logic;   -- bit being written THIS iteration (comb)
    signal dq_drive_low    : std_logic;   -- registered FSM pad-drive output (D11)
    signal busy             : std_logic;
    signal tcif_flag, pres_flag, nopres_flag, short_flag : std_logic;
    signal nopres_pending   : std_logic;  -- RESET-only: tentative NOPRES, A5 SHORT-wins

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode (EnMemPeriph-qualified LEVEL, D4; never an edge).
    ow_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- Write-bit value for THIS iteration: WRBIT uses latched_bitval, WRBYTE shifts latched_tx out LSB-first via bit_idx (D9).
    wr_bit_val <= latched_bitval when latched_op = OP_WRBIT else latched_tx(bit_idx);

    -- irq_ow = (status and enable), combinational, never latched (D13).
    -- TCIE/ERRIE are quasi-static ClkMem CR bits, read directly (D1 coincident nets, the RTC irq_rtc precedent).
    irq_ow <= (tcif_flag and ow_cr(3)) or ((nopres_flag or short_flag) and ow_cr(4));

    -- Pad drive (D11): fixed open-drain expression, NEVER driven high.
    OW_DQ_OUT <= '0';
    OW_DQ_DIR <= dq_drive_low;

    -- ------------------------- B1: register write (ClkMem) --------------------
    -- Rising ClkMem, EnMemPeriph='0' qualified, lane-0 (WEn(0)='0') writes only (D4/D8).
    -- OW0CMD ALWAYS captures the descriptor; the launch (toggle flip) is suppressed when OWEN=0 or busy_sync=1 (D8).
    -- OW0TX/OW0CR/OW0DIV writes never launch.
    -- SR lane-0 writes of 1 to TCIF/NOPRES/SHORT flip the clr_*_tgl toggles (W1C-CDC, D12).
    -- Reset via resetn (bus domain, D14).
    reg_write: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            ow_cr         <= (others => '0');
            ow_cmd_op     <= (others => '0');
            ow_cmd_bitval <= '0';
            ow_tx         <= (others => '0');
            ow_div        <= (others => '0');
            desc_op       <= (others => '0');
            desc_bitval   <= '0';
            desc_ods      <= '0';
            desc_tx       <= (others => '0');
            launch_tgl    <= '0';
            clr_tcif_tgl   <= '0';
            clr_nopres_tgl <= '0';
            clr_short_tgl  <= '0';
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case ow_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            ow_cr <= wdata(4 downto 0);   -- bits 31:5 reserved
                        end if;
                    when SLOT_CMD =>
                        if WEn(0) = '0' then
                            -- Content ALWAYS captured (D8).
                            desc_op       <= wdata(2 downto 0);
                            desc_bitval   <= wdata(8);
                            desc_ods      <= ow_cr(1);   -- current ODS at write time
                            desc_tx       <= ow_tx;      -- current TX byte at write time
                            ow_cmd_op     <= wdata(2 downto 0);
                            ow_cmd_bitval <= wdata(8);
                            -- Launch suppressed on OWEN=0 or BUSY=1 (D8).
                            if ow_cr(0) = '1' and busy_sync = '0' then
                                launch_tgl <= not launch_tgl;
                            end if;
                        end if;
                    when SLOT_TX =>
                        if WEn(0) = '0' then
                            ow_tx <= wdata(7 downto 0);   -- write never launches (D8)
                        end if;
                    when SLOT_DIV =>
                        if WEn(0) = '0' then
                            ow_div <= wdata(15 downto 0);
                        end if;
                    when SLOT_SR =>
                        -- W1C: writing 1 clears; BUSY(0)/PRES(2) are read-only, ignored.
                        if WEn(0) = '0' then
                            if wdata(1) = '1' then clr_tcif_tgl   <= not clr_tcif_tgl;   end if;
                            if wdata(3) = '1' then clr_nopres_tgl <= not clr_nopres_tgl; end if;
                            if wdata(4) = '1' then clr_short_tgl  <= not clr_short_tgl;  end if;
                        end if;
                    when others =>
                        null;   -- SPU (slot 6) writes ignored; slots >=7 no effect
                end case;
            end if;
        end if;
    end process;

    -- ------------------------- B1: register read (ClkMem) ---------------------
    -- Registered read mux on rising ClkMem.
    -- SR.BUSY reads the RAW clk-domain `busy` level (orchestrator adjudication, RTC-A5 class): busy_sync is 2-FF'd on the GATED ClkMem, so the first SR read after a launch supplies the very edges that shift busy in and captures a stale 0, a blind window that let the bench's busy-clear wait fall straight through.
    -- clk and ClkMem are the same electrical mclk family, so this registration IS the synchronization; busy_sync remains the launch-suppress qualifier in reg_write.
    -- Everything else is read per D12's quasi-static-net discipline (TCIF/PRES/NOPRES/SHORT/RX).
    -- No pre-latch, no bridge (D4).
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case ow_slot is
                when SLOT_CR =>
                    rdata_out <= (31 downto 5 => '0') & ow_cr;
                when SLOT_CMD =>
                    rdata_out <= (31 downto 9 => '0') & ow_cmd_bitval &
                                 (7 downto 3 => '0') & ow_cmd_op;
                when SLOT_TX =>
                    rdata_out <= (31 downto 8 => '0') & ow_tx;
                when SLOT_RX =>
                    rdata_out <= (31 downto 8 => '0') & rx_shift;
                when SLOT_DIV =>
                    rdata_out <= (31 downto 16 => '0') & ow_div;
                when SLOT_SR =>
                    rdata_out <= (31 downto 5 => '0') & short_flag & nopres_flag &
                                 pres_flag & tcif_flag & (busy or launch_pending);
                when others =>
                    rdata_out <= (others => '0');   -- SPU slot 6 and >=7 read 0
            end case;
        end if;
    end process;

    -- ------------------------- B2: BUSY 2-FF sync into ClkMem (D8) ------------
    busy_sync_proc: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            busy_c1 <= '0'; busy_c2 <= '0';
        elsif rising_edge(ClkMem) then
            busy_c1 <= busy; busy_c2 <= busy_c1;
        end if;
    end process;
    busy_sync <= busy_c2;

    -- ------------------------- B2: clk-domain CDC (D8/D10/D12) ----------------
    -- 2-FF plus edge-detect turns launch_tgl into launch_pulse, and each clr_*_tgl into a one-cycle clear pulse; a 2-FF sync turns OW_DQ_IN into dq_sync (pure data, D10).
    -- Single edge (rising clk) only, reset via resetn.
    clk_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            lnch_c1 <= '0'; lnch_c2 <= '0'; lnch_prev <= '0';
            clrtcif_c1 <= '0'; clrtcif_c2 <= '0'; clrtcif_prev <= '0';
            clrnopres_c1 <= '0'; clrnopres_c2 <= '0'; clrnopres_prev <= '0';
            clrshort_c1 <= '0'; clrshort_c2 <= '0'; clrshort_prev <= '0';
            dq_s1 <= '0'; dq_s2 <= '0';
        elsif rising_edge(clk) then
            lnch_c1 <= launch_tgl; lnch_c2 <= lnch_c1; lnch_prev <= lnch_c2;
            clrtcif_c1   <= clr_tcif_tgl;   clrtcif_c2   <= clrtcif_c1;   clrtcif_prev   <= clrtcif_c2;
            clrnopres_c1 <= clr_nopres_tgl; clrnopres_c2 <= clrnopres_c1; clrnopres_prev <= clrnopres_c2;
            clrshort_c1  <= clr_short_tgl;  clrshort_c2  <= clrshort_c1;  clrshort_prev  <= clrshort_c2;
            dq_s1 <= OW_DQ_IN; dq_s2 <= dq_s1;
        end if;
    end process;
    launch_pulse     <= '1' when (lnch_c2 /= lnch_prev) else '0';
    -- Launch-side pending (orchestrator adjudication, RTC-A5/D8-literal class): the RAW ClkMem-domain launch toggle against its deepest clk-synced stage.
    -- High from the launching CMD write until the FSM consumes the launch (the same edge busy rises), so SR.BUSY has NO assert blind window and firmware may poll BUSY-clear immediately after writing OW0CMD.
    launch_pending   <= '1' when (launch_tgl /= lnch_prev) else '0';
    clr_tcif_pulse   <= '1' when (clrtcif_c2 /= clrtcif_prev) else '0';
    clr_nopres_pulse <= '1' when (clrnopres_c2 /= clrnopres_prev) else '0';
    clr_short_pulse  <= '1' when (clrshort_c2 /= clrshort_prev) else '0';
    dq_sync <= dq_s2;

    -- ------------------------- B3: time base (clk, D6) -------------------------
    -- Free-running reload down-counter producing a one-cycle tick: counter-compare, NO clock gate, no generated clock.
    -- Tick period = OW0DIV+1 clk cycles.
    -- ow_div is a plain rw register, read directly (quasi-static, D1/D6).
    timebase: process(resetn, clk)
    begin
        if resetn = '0' then
            div_cnt <= (others => '0');
            tick    <= '0';
        elsif rising_edge(clk) then
            if div_cnt = "0000000000000000" then
                div_cnt <= ow_div;
                tick    <= '1';
            else
                div_cnt <= div_cnt - 1;
                tick    <= '0';
            end if;
        end if;
    end process;

    -- ------------------------- B4: slot / protocol FSM (clk, D7/D9/D11/D12) ---
    -- Tick-counted slot sequencer, selecting the frozen table by latched_ods.
    -- SAMPLE/DONE/IDLE-dispatch steps are single-cycle (unconditional, not tick-gated); every timed phase advances only on a tick pulse.
    fsm: process(resetn, clk)
        variable target : natural range 0 to 4095;
    begin
        if resetn = '0' then
            ow_state       <= OW_IDLE;
            phase_cnt      <= 0;
            bit_idx        <= 0;
            bit_total      <= 0;
            latched_op     <= (others => '0');
            latched_bitval <= '0';
            latched_ods    <= '0';
            latched_tx     <= (others => '0');
            rx_shift       <= (others => '0');
            dq_drive_low   <= '0';
            busy           <= '0';
            tcif_flag      <= '0';
            pres_flag      <= '0';
            nopres_flag    <= '0';
            short_flag     <= '0';
            nopres_pending <= '0';
        elsif rising_edge(clk) then

            -- Target tick count for the CURRENT state, selected by latched_ods and, for the write-drive phases, the bit being written this slot.
            if latched_ods = '0' then
                -- standard speed
                case ow_state is
                    when R_LOW   => target := OW_STD_TRSTL;
                    when R_REL   => target := OW_STD_TPRES;
                    when R_HIGH  => target := OW_STD_TRSTH;
                    when W_LOW   =>
                        if wr_bit_val = '1' then target := OW_STD_TW1L; else target := OW_STD_TW0L; end if;
                    when W_REL   =>
                        if wr_bit_val = '1' then target := OW_STD_TSLOT - OW_STD_TW1L;
                        else target := OW_STD_TSLOT - OW_STD_TW0L; end if;
                    when W_REC   => target := OW_STD_TREC;
                    when RD_LOW  => target := OW_STD_TRL;
                    when RD_REL  => target := OW_STD_TMSR - OW_STD_TRL;
                    when RD_FILL => target := OW_STD_TSLOT - OW_STD_TMSR;
                    when RD_REC  => target := OW_STD_TREC;
                    when others  => target := 1;
                end case;
            else
                -- overdrive speed
                case ow_state is
                    when R_LOW   => target := OW_OD_TRSTL;
                    when R_REL   => target := OW_OD_TPRES;
                    when R_HIGH  => target := OW_OD_TRSTH;
                    when W_LOW   =>
                        if wr_bit_val = '1' then target := OW_OD_TW1L; else target := OW_OD_TW0L; end if;
                    when W_REL   =>
                        if wr_bit_val = '1' then target := OW_OD_TSLOT - OW_OD_TW1L;
                        else target := OW_OD_TSLOT - OW_OD_TW0L; end if;
                    when W_REC   => target := OW_OD_TREC;
                    when RD_LOW  => target := OW_OD_TRL;
                    when RD_REL  => target := OW_OD_TMSR - OW_OD_TRL;
                    when RD_FILL => target := OW_OD_TSLOT - OW_OD_TMSR;
                    when RD_REC  => target := OW_OD_TREC;
                    when others  => target := 1;
                end case;
            end if;

            -- W1C clears run first; a coincident SET below OVERRIDES them (set wins, D12/RTC discipline: the later sequential assignment wins).
            if clr_tcif_pulse   = '1' then tcif_flag   <= '0'; end if;
            if clr_nopres_pulse = '1' then nopres_flag <= '0'; end if;
            if clr_short_pulse  = '1' then short_flag  <= '0'; end if;

            case ow_state is

                -- Idle: on a launch pulse, adopt the descriptor and dispatch on OP.
                when OW_IDLE =>
                    if launch_pulse = '1' then
                        latched_op     <= desc_op;
                        latched_bitval <= desc_bitval;
                        latched_ods    <= desc_ods;
                        latched_tx     <= desc_tx;
                        phase_cnt <= 0;
                        bit_idx   <= 0;
                        case desc_op is
                            when OP_RESET =>
                                busy <= '1'; dq_drive_low <= '1'; ow_state <= R_LOW;
                            when OP_WRBIT =>
                                busy <= '1'; bit_total <= 1; dq_drive_low <= '1'; ow_state <= W_LOW;
                            when OP_WRBYTE =>
                                busy <= '1'; bit_total <= 8; dq_drive_low <= '1'; ow_state <= W_LOW;
                            when OP_RDBIT =>
                                busy <= '1'; bit_total <= 1; dq_drive_low <= '1'; ow_state <= RD_LOW;
                            when OP_RDBYTE =>
                                busy <= '1'; bit_total <= 8; dq_drive_low <= '1'; ow_state <= RD_LOW;
                            when others =>
                                null;   -- reserved OP (D9): no bus activity, no BUSY, no TCIF
                        end case;
                    end if;

                -- ---------------- RESET leg --------------------------------
                -- Hold DQ low for tRSTL, then release.
                when R_LOW =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; dq_drive_low <= '0'; ow_state <= R_REL;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Released: wait tPRES before looking for the presence pulse.
                when R_REL =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; ow_state <= R_SAMPLE;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Single-cycle presence sample: DQ low means a device answered.
                when R_SAMPLE =>
                    if dq_sync = '0' then
                        pres_flag <= '1'; nopres_pending <= '0';
                    else
                        pres_flag <= '0'; nopres_pending <= '1';
                    end if;
                    phase_cnt <= 0; ow_state <= R_HIGH;

                -- Rest of the reset slot; the SHORT/NOPRES verdict lands at its end.
                when R_HIGH =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0;
                            -- End-of-recovery SHORT check; A5: SHORT wins and suppresses NOPRES.
                            if dq_sync = '0' then
                                short_flag <= '1';
                            elsif nopres_pending = '1' then
                                nopres_flag <= '1';
                            end if;
                            ow_state <= OW_DONE;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- ---------------- WRITE bit/byte leg -----------------------
                -- Drive low for tW1L or tW0L depending on the bit being written.
                when W_LOW =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; dq_drive_low <= '0'; ow_state <= W_REL;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Released for the rest of tSLOT.
                when W_REL =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; ow_state <= W_REC;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Recovery: SHORT check, then either the next bit or completion.
                when W_REC =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0;
                            if dq_sync = '0' then short_flag <= '1'; end if;
                            if bit_idx = bit_total - 1 then
                                ow_state <= OW_DONE;
                            else
                                bit_idx <= bit_idx + 1;
                                dq_drive_low <= '1';
                                ow_state <= W_LOW;
                            end if;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- ---------------- READ bit/byte leg --------------------------
                -- Initiate the read slot with a tRL low pulse, then release.
                when RD_LOW =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; dq_drive_low <= '0'; ow_state <= RD_REL;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Released: wait out the tMSR sample point.
                when RD_REL =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; ow_state <= RD_SAMPLE;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Single-cycle master-sample point at tMSR.
                when RD_SAMPLE =>
                    rx_shift(bit_idx) <= dq_sync;   -- LSB-first assembly (D9)
                    phase_cnt <= 0; ow_state <= RD_FILL;

                -- Fill the remainder of tSLOT after the sample.
                when RD_FILL =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0; ow_state <= RD_REC;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Recovery: SHORT check, then either the next bit or completion.
                when RD_REC =>
                    if tick = '1' then
                        if phase_cnt = target - 1 then
                            phase_cnt <= 0;
                            if dq_sync = '0' then short_flag <= '1'; end if;
                            if bit_idx = bit_total - 1 then
                                ow_state <= OW_DONE;
                            else
                                bit_idx <= bit_idx + 1;
                                dq_drive_low <= '1';
                                ow_state <= RD_LOW;
                            end if;
                        else phase_cnt <= phase_cnt + 1; end if;
                    end if;

                -- Completion: drop BUSY, set TCIF, release the pad.
                when OW_DONE =>
                    busy <= '0'; tcif_flag <= '1'; dq_drive_low <= '0';
                    ow_state <= OW_IDLE;

                -- Unreachable with the declared state type; recover to IDLE.
                when others =>
                    ow_state <= OW_IDLE;

            end case;
        end if;
    end process;

end behavioral;
