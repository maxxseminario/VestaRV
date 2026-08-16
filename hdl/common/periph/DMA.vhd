library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

/* ===========================================================================
   DMA: configurable multi-channel single-shot DMA controller with peripheral pacing and a CRC16-CDMA2000 ride-along, at base 0x6800. Zero pins.
   Two peripherals fused: an arbiter SLAVE (the register file, on gated ClkMem) and an arbiter MASTER (the transfer engine, on free-running clk = MCLK, slice 4 of arb_*).
   The engine CANNOT ride ClkMem, which ticks only during a bus access: it must advance autonomously while the bus is idle.
   clk and ClkMem are the SAME mclk net at integration, so the only true metastability CDC is the three trigger inputs; every other ClkMem-to-clk hand-off is a toggle or a held quasi-static level, so the block stays correct even under a bench clk/ClkMem skew.
   -V200X only (no VHDL-2008); every process infers exactly ONE edge of ONE clock, there are no clock gates or generated clocks, and nothing ever uses falling_edge of EnMemPeriph.
   =========================================================================== */

/* MASTER-PORT HANDSHAKE, binding: raise m_req with m_we/m_addr/m_wdata stable, HOLD all of them through the m_done cycle, capture m_rdata ON the m_done cycle, then drop m_req via an acked flop ONE clk after m_done.
   At least one arbiter-observed m_req-low cycle must pass before any re-request; a continuously-high m_req across two words is a stale ghost that corrupts the arbiter IDLE pick.
   Boundary depth 0: the DMA lives inside MCU fabric on mclk, not behind a tile boundary. */

-- ERROR MODEL: CHnERR (W1C) sets on a deny hit (mid-flight abort), or at GO on LEN=0, SRC/DST misaligned (bits 1:0 /= "00"), SRC/DST out of window (byte 0x20000 or above, bits 31:17 /= 0), or SRC/DST inside the tile-private TCM hole 0x8000-0xBFFF (bits 16:14 = "010").
-- A reject-at-GO channel never runs (busy never rises); irq_err asserts if ERRIE=1; an abort sets NEITHER CHnDONE nor CHnERR.

/* Register map: base 0x6800, slot n at 0x6800 + 4n, decoded off MABPart(7:2).
   The map is the 4-channel SUPERSET; absent channels (ch>=NCH) read 0 and ignore writes.
     0  DMA0CR  : [0]DMAEN [4:1]CHnGO(w1 self-clearing, rd0) [8:5]CHnABORT(w1
                  self-clearing, rd0) [12]DONEIE [13]ERRIE, rest rsvd rd0.
     1  DMA0SR  : [0]BUSY ro [4:1]CHnDONE W1C [8:5]CHnERR W1C [11:9]ACTIVECH ro.
     2..5   CH0 {SRC,DST,LEN,CFG};  6..9 CH1; 10..13 CH2; 14..17 CH3.
       DMA0CnSRC/DST rw byte addr [16:0] (word-aligned), full written value
         read back. DMA0CnLEN rw words, reads CURRENT REMAINING (the working
         counter, 0 until the first GO). DMA0CnCFG: [0]SINC [1]DINC [5:2]TRIG
         (0 mem2mem/1 UART0-RC/2 QSPI0-RXFULL/3 NFC0-frame) [6]PRIO [7]CRCEN.
     18 DMA0CRC : rw [15:0] CRC16-CDMA2000 accumulator, reset 0xFFFF (seed by
                  write before GO, result read after DONE; the engine folds it in clk).
     19 DMA0DESC: reserved, reads 0 and writes ignored. Slots >=20 read 0.
   =========================================================================== */

entity DMA is
    generic (
        NCH : natural := 4;   -- channel count, {2,4}
        AW  : natural := 15   -- master-port word-address width (SH_AW)
    );
    port (
        clk         : in  std_logic;                     -- free-running MCLK, clocking the master-port FSM,
                                                         -- channel engine, CRC, pacing sync, sticky flags
                                                         -- and IRQ combiner
        resetn      : in  std_logic;                     -- chip reset, active-low (async)

        -- register-file slave port
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);

        -- arbiter MASTER port (slice 4 of arb_*, depth 0)
        m_req       : out std_logic;                     -- held through m_done, dropped via acked flop
        m_we        : out std_logic_vector(3 downto 0);  -- active-HIGH lanes; "0000" = read
        m_addr      : out std_logic_vector(AW-1 downto 0);-- word address = byte_ptr(16:2), zero-extended to AW
        m_wdata     : out std_logic_vector(31 downto 0);
        m_gnt       : in  std_logic;                     -- observed only (handshake waits on m_done)
        m_done      : in  std_logic;                     -- 1-cycle completion; m_rdata valid here
        m_rdata     : in  std_logic_vector(31 downto 0);

        -- Pacing triggers: data-ready LEVELS, tie '0' when the source is absent.
        -- These taps carry the source's IE-gated irq_* level, so pacing REQUIRES the source's IE bit set; routing that vector to a hart is independent and optional.
        trig_uart0_rc  : in std_logic := '0';            -- UART0 RCIF via irq_uart0_rc (live, idx 13)
        trig_qspi0_rxf : in std_logic := '0';            -- QSPI0 RXFULL via irq_rxf (knob-gated)
        trig_nfc0_rxf  : in std_logic := '0';            -- NFC0 payload-ready via irq_rxf (knob-gated)

        -- interrupt levels into irq_router
        irq_done    : out std_logic;                     -- combined channels-done (vector 118)
        irq_err     : out std_logic;                     -- error (vector 119)

        -- EVFAB taps. task_go: one-clk fabric pulses consumed at the SAME arm site as go_pulse, so reject-at-GO, busy suppression and pacing arm identically to a register GO; DMAEN is re-applied at the tap because the ClkMem-side wdata(0) qualifier cannot see task GOs.
        -- evt_done/evt_err are registered one-clk pulses at the flags' SET sites, pre-IE, and an abort sets neither; ch_busy exports per-channel engaged levels for the fabric's OVR input.
        task_go     : in  std_logic_vector(3 downto 0) := (others => '0');
        evt_done    : out std_logic_vector(3 downto 0);
        evt_err     : out std_logic;                     -- combined error set sites
        ch_busy     : out std_logic_vector(3 downto 0)  -- fabric task_busy taps
    );
end DMA;

architecture behavioral of DMA is

    -- ---- CRC16-CDMA2000 combinational cell (poly 0xC857) -------------------
    component CRC16
        generic (
            POLYNOMIAL : std_logic_vector(15 downto 0) := X"C857"
        );
        port (
            DataIn : in  std_logic_vector(7 downto 0);
            CrcOld : in  std_logic_vector(15 downto 0);
            CrcOut : out std_logic_vector(15 downto 0)
        );
    end component;

    -- ---- superset array types (4-channel map; NCH gates engine and read) ---
    type slv32_arr is array(0 to 3) of std_logic_vector(31 downto 0);
    type slv17_arr is array(0 to 3) of std_logic_vector(16 downto 0);
    type slv8_arr  is array(0 to 3) of std_logic_vector(7 downto 0);
    type sl_arr    is array(0 to 3) of std_logic;

    -- ---- master-port FSM states: REQ holds the txn, CAP is the one stale-req cycle, GAP is the one observed-low cycle. No counters, distinct states instead.
    type t_dma_state is (M_IDLE, M_RD_REQ, M_RD_CAP, M_RD_GAP,
                         M_WR_REQ, M_WR_CAP, M_WR_GAP, M_CLR);
    signal dstate : t_dma_state;

    -- ---- register-file storage (ClkMem domain) ----------------------------
    signal dmaen       : std_logic;                       -- DMA0CR[0]
    signal doneie      : std_logic;                       -- DMA0CR[12]
    signal errie       : std_logic;                       -- DMA0CR[13]
    signal src_reg     : slv32_arr;                        -- programmed SRC (full readback)
    signal dst_reg     : slv32_arr;                        -- programmed DST (full readback)
    signal len_reg     : slv32_arr;                        -- programmed LEN seed
    signal cfg_reg     : slv8_arr;                         -- CFG store
    signal crc_seed_reg: std_logic_vector(15 downto 0);    -- DMA0CRC seed store (ClkMem)
    signal go_tgl      : sl_arr;                           -- launch request toggles
    signal abort_tgl   : sl_arr;                           -- abort request toggles
    signal clr_done_tgl: sl_arr;                           -- W1C CHnDONE toggles
    signal clr_err_tgl : sl_arr;                           -- W1C CHnERR toggles
    signal crc_wr_tgl  : std_logic;                        -- DMA0CRC seed-commit toggle
    signal dma_slot    : natural range 0 to 63;            -- decoded word slot

    -- ---- busy 2-FF into ClkMem (launch suppress) --------------------------
    signal busy_c1, busy_c2 : sl_arr;
    signal busy_sync        : sl_arr;

    -- ---- clk-domain CDC: toggle syncs + trigger syncs ---------------------
    signal go_c1, go_c2, go_prev       : sl_arr;           -- go_tgl sync + edge
    signal ab_c1, ab_c2, ab_prev       : sl_arr;           -- abort_tgl sync + edge
    signal cd_c1, cd_c2, cd_prev       : sl_arr;           -- W1C done sync + edge
    signal ce_c1, ce_c2, ce_prev       : sl_arr;           -- W1C err sync + edge
    signal crcw_c1, crcw_c2, crcw_prev : std_logic;        -- crc seed commit sync + edge
    signal tu1, tu2, tu_prev           : std_logic;        -- UART trigger 2-FF + edge
    signal tq1, tq2, tq_prev           : std_logic;        -- QSPI trigger 2-FF + edge
    signal tn1, tn2, tn_prev           : std_logic;        -- NFC  trigger 2-FF + edge
    signal go_pulse, abort_pulse       : sl_arr;           -- one-clk launch/abort pulses
    signal clr_done_pulse, clr_err_pulse : sl_arr;         -- one-clk W1C pulses
    signal crc_wr_pulse                : std_logic;        -- one-clk seed-commit pulse
    signal go_pending                  : sl_arr;           -- same-cycle BUSY cover
    signal evt_uart, evt_qspi, evt_nfc : std_logic;        -- one-clk trigger events

    -- ---- engine working state (clk domain) --------------------------------
    signal src_work : slv17_arr;                           -- 17-bit byte working SRC ptr
    signal dst_work : slv17_arr;                           -- 17-bit byte working DST ptr
    signal len_work : slv32_arr;                           -- remaining LEN in words, the SR readback
    signal cfg_work : slv8_arr;                            -- latched CFG (SINC/DINC/TRIG/PRIO/CRCEN)
    signal busy      : sl_arr;                             -- per-channel armed+busy (clk)
    signal pace_go   : sl_arr;                             -- paced event authorization
    signal abort_req : sl_arr;                             -- latched abort request
    signal done_flag : sl_arr;                             -- CHnDONE sticky (clk)
    signal err_flag  : sl_arr;                             -- CHnERR sticky (clk)
    signal task_go_eff : sl_arr;                           -- EVFAB task GO, DMAEN-gated (comb)
    signal evt_done_p  : sl_arr;                           -- EVFAB one-clk done pulses (reg)
    signal evt_err_p   : std_logic;                        -- EVFAB one-clk err pulse (reg)
    signal cur_ch    : natural range 0 to 3;               -- channel being serviced this txn
    signal rr_ptr    : natural range 0 to 3;               -- round-robin pointer
    signal activech  : std_logic_vector(2 downto 0);       -- SR.ACTIVECH (0 when idle)
    signal in_clr    : std_logic;                          -- M_CLR-write routing flag (CAP/GAP reuse)
    signal data_hold : std_logic_vector(31 downto 0);      -- word held between the read and the write
    signal crc_acc   : std_logic_vector(15 downto 0);      -- DMA0CRC accumulator (clk owner)

    -- ---- registered master-port outputs -----------------------------------
    signal m_req_r   : std_logic;
    signal m_we_r    : std_logic_vector(3 downto 0);
    -- The DMA's own address space is fixed at 17 bits (byte 0x00000-0x1FFFF: shared ROM, the peripheral window and the bulk RAM), which is what every check and slice below is written against.
    -- Keep this register 15 bits and zero-extend it onto the AW-wide port: declaring it AW-wide while the assignments feed 15-bit values is a shape mismatch that kills the sim at AW=16.
    signal m_addr_r  : std_logic_vector(14 downto 0);
    -- NULL RANGE when AW = 15, so the concatenation below is the identity.
    constant M_ADDR_PAD : std_logic_vector(AW-1 downto 15) := (others => '0');
    signal m_wdata_r : std_logic_vector(31 downto 0);

    -- ---- CRC chain (four chained combinational CRC16) ---------------------
    signal crc1, crc2, crc3, crc4 : std_logic_vector(15 downto 0);

    -- ---- combinational status / IRQ ---------------------------------------
    signal busy_any, done_any, err_any : std_logic;

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode: an EnMemPeriph-qualified LEVEL, never an edge.
    dma_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- master-port registered outputs (depth-0 slice 4)
    m_req   <= m_req_r;
    m_we    <= m_we_r;
    m_addr  <= M_ADDR_PAD & m_addr_r;
    m_wdata <= m_wdata_r;

    -- BUSY same-cycle: any channel busy OR any GO pending.
    -- go_pending asserts the instant the CHnGO write lands and clears once the engine has observed the launch, so a write-then-poll has no blind window.
    busy_any <= (busy(0) or go_pending(0) or task_go_eff(0))
             or (busy(1) or go_pending(1) or task_go_eff(1))
             or (busy(2) or go_pending(2) or task_go_eff(2))
             or (busy(3) or go_pending(3) or task_go_eff(3));

    -- combined done/err (flags for ch>=NCH are never driven and read 0)
    done_any <= done_flag(0) or done_flag(1) or done_flag(2) or done_flag(3);
    err_any  <= err_flag(0)  or err_flag(1)  or err_flag(2)  or err_flag(3);

    -- irq_done/irq_err = status AND enable, combinational, never latched.
    irq_done <= done_any and doneie;
    irq_err  <= err_any  and errie;

    -- CRC chain: fold the READ word bytes b0 through b3, little-endian first, starting from crc_acc; crc4 is registered on the done edge for CRCEN channels.
    -- The chain is combinational off m_rdata, which is valid on the done cycle, so the folded word matches the captured data_hold.
    u_crc0: CRC16 port map (DataIn => m_rdata(7  downto 0),  CrcOld => crc_acc, CrcOut => crc1);
    u_crc1: CRC16 port map (DataIn => m_rdata(15 downto 8),  CrcOld => crc1,    CrcOut => crc2);
    u_crc2: CRC16 port map (DataIn => m_rdata(23 downto 16), CrcOld => crc2,    CrcOut => crc3);
    u_crc3: CRC16 port map (DataIn => m_rdata(31 downto 24), CrcOld => crc3,    CrcOut => crc4);

    /* ------------------------- register write (ClkMem) ------------------------
       Rising ClkMem, qualified by EnMemPeriph='0'; every write is lane-0 qualified, since a normal word or low store asserts lane 0.
       CHnGO flips go_tgl(ch) unless DMAEN=0 or the channel is already busy; CHnABORT, the SR W1C bits and the CRC seed commit flip their own toggles, and writes to ch>=NCH are dropped. */
    reg_write: process(resetn, ClkMem)
        variable ch  : integer;
        variable fld : integer;
    begin
        if resetn = '0' then
            dmaen        <= '0';
            doneie       <= '0';
            errie        <= '0';
            src_reg      <= (others => (others => '0'));
            dst_reg      <= (others => (others => '0'));
            len_reg      <= (others => (others => '0'));
            cfg_reg      <= (others => (others => '0'));
            crc_seed_reg <= X"FFFF";
            go_tgl       <= (others => '0');
            abort_tgl    <= (others => '0');
            clr_done_tgl <= (others => '0');
            clr_err_tgl  <= (others => '0');
            crc_wr_tgl   <= '0';
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                if dma_slot = 0 then
                    -- DMA0CR (lane-0 qualified; bits up to 13 read under a word store)
                    if WEn(0) = '0' then
                        dmaen  <= wdata(0);
                        doneie <= wdata(12);
                        errie  <= wdata(13);
                        for ch in 0 to 3 loop
                            if ch < NCH then
                                -- CHnGO[4:1]: launch suppressed on DMAEN=0 or busy
                                if wdata(1 + ch) = '1' and wdata(0) = '1'
                                   and busy_sync(ch) = '0' then
                                    go_tgl(ch) <= not go_tgl(ch);
                                end if;
                                -- CHnABORT[8:5]: orderly-stop request
                                if wdata(5 + ch) = '1' then
                                    abort_tgl(ch) <= not abort_tgl(ch);
                                end if;
                            end if;
                        end loop;
                    end if;
                elsif dma_slot = 1 then
                    -- DMA0SR W1C: CHnDONE[4:1], CHnERR[8:5]; BUSY/ACTIVECH ro.
                    if WEn(0) = '0' then
                        for ch in 0 to 3 loop
                            if ch < NCH then
                                if wdata(1 + ch) = '1' then
                                    clr_done_tgl(ch) <= not clr_done_tgl(ch);
                                end if;
                                if wdata(5 + ch) = '1' then
                                    clr_err_tgl(ch) <= not clr_err_tgl(ch);
                                end if;
                            end if;
                        end loop;
                    end if;
                elsif dma_slot >= 2 and dma_slot <= 17 then
                    -- per-channel {SRC,DST,LEN,CFG} stores (full word, lane-0 qual)
                    ch  := (dma_slot - 2) / 4;
                    fld := (dma_slot - 2) mod 4;
                    if ch < NCH and WEn(0) = '0' then
                        case fld is
                            when 0      => src_reg(ch) <= wdata;
                            when 1      => dst_reg(ch) <= wdata;
                            when 2      => len_reg(ch) <= wdata;
                            when others => cfg_reg(ch) <= wdata(7 downto 0);
                        end case;
                    end if;
                elsif dma_slot = 18 then
                    -- DMA0CRC seed: stage the value and flip the commit toggle
                    if WEn(0) = '0' then
                        crc_seed_reg <= wdata(15 downto 0);
                        crc_wr_tgl   <= not crc_wr_tgl;
                    end if;
                else
                    null;   -- DESC (slot 19) writes ignored; slots >=20 no effect
                end if;
            end if;
        end if;
    end process;

    /* ------------------------- register read (ClkMem) -------------------------
       Registered read mux on rising ClkMem over data already in the mclk domain: no pre-latch, no bridge.
       CHnGO/CHnABORT read 0 (self-clearing commands), LEN reads the WORKING remaining counter, and channel slots for ch>=NCH, DESC and slots >=20 read 0. */
    reg_read: process(ClkMem)
        variable ch  : integer;
        variable fld : integer;
    begin
        if rising_edge(ClkMem) then
            if dma_slot = 0 then
                rdata_out <= (31 downto 14 => '0') & errie & doneie
                             & "00000000000" & dmaen;
            elsif dma_slot = 1 then
                rdata_out <= (31 downto 12 => '0') & activech
                             & err_flag(3) & err_flag(2) & err_flag(1) & err_flag(0)
                             & done_flag(3) & done_flag(2) & done_flag(1) & done_flag(0)
                             & busy_any;
            elsif dma_slot >= 2 and dma_slot <= 17 then
                ch  := (dma_slot - 2) / 4;
                fld := (dma_slot - 2) mod 4;
                if ch < NCH then
                    case fld is
                        when 0      => rdata_out <= src_reg(ch);
                        when 1      => rdata_out <= dst_reg(ch);
                        when 2      => rdata_out <= len_work(ch);
                        when others => rdata_out <= (31 downto 8 => '0') & cfg_reg(ch);
                    end case;
                else
                    rdata_out <= (others => '0');
                end if;
            elsif dma_slot = 18 then
                rdata_out <= (31 downto 16 => '0') & crc_acc;
            else
                rdata_out <= (others => '0');   -- DESC (19) and slots >=20 read 0
            end if;
        end if;
    end process;

    -- ------------------------- busy 2-FF into ClkMem --------------------------
    -- Per-channel engine busy synchronized into ClkMem: the launch-suppress qualifier in reg_write, since a GO to a busy channel must not flip go_tgl.
    busy_sync_proc: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            busy_c1 <= (others => '0');
            busy_c2 <= (others => '0');
        elsif rising_edge(ClkMem) then
            busy_c1 <= busy;
            busy_c2 <= busy_c1;
        end if;
    end process;
    busy_sync <= busy_c2;

    /* ------------------------- clk-domain CDC ---------------------------------
       2-FF plus edge-detect on every ClkMem toggle crossing into clk (go, abort, W1C done, W1C err, crc seed commit).
       2-FF plus rising-edge on every trigger input, the ONLY true metastability CDC here. */
    clk_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            go_c1 <= (others => '0'); go_c2 <= (others => '0'); go_prev <= (others => '0');
            ab_c1 <= (others => '0'); ab_c2 <= (others => '0'); ab_prev <= (others => '0');
            cd_c1 <= (others => '0'); cd_c2 <= (others => '0'); cd_prev <= (others => '0');
            ce_c1 <= (others => '0'); ce_c2 <= (others => '0'); ce_prev <= (others => '0');
            crcw_c1 <= '0'; crcw_c2 <= '0'; crcw_prev <= '0';
            tu1 <= '0'; tu2 <= '0'; tu_prev <= '0';
            tq1 <= '0'; tq2 <= '0'; tq_prev <= '0';
            tn1 <= '0'; tn2 <= '0'; tn_prev <= '0';
        elsif rising_edge(clk) then
            go_c1 <= go_tgl;       go_c2 <= go_c1;       go_prev <= go_c2;
            ab_c1 <= abort_tgl;    ab_c2 <= ab_c1;       ab_prev <= ab_c2;
            cd_c1 <= clr_done_tgl; cd_c2 <= cd_c1;       cd_prev <= cd_c2;
            ce_c1 <= clr_err_tgl;  ce_c2 <= ce_c1;       ce_prev <= ce_c2;
            crcw_c1 <= crc_wr_tgl; crcw_c2 <= crcw_c1;   crcw_prev <= crcw_c2;
            tu1 <= trig_uart0_rc;  tu2 <= tu1;           tu_prev <= tu2;
            tq1 <= trig_qspi0_rxf; tq2 <= tq1;           tq_prev <= tq2;
            tn1 <= trig_nfc0_rxf;  tn2 <= tn1;           tn_prev <= tn2;
        end if;
    end process;

    -- EVFAB task GO: DMAEN is re-applied clk-side, since it is a quasi-static level that crosses bare.
    -- A task GO with DMAEN=0 is completely inert, matching the register path's ClkMem-side suppression.
    task_gates: for i in 0 to 3 generate
        task_go_eff(i) <= task_go(i) and dmaen;
        ch_busy(i)     <= busy(i) or go_pending(i) or task_go_eff(i);
        evt_done(i)    <= evt_done_p(i);   -- element-wise: sl_arr vs slv port
    end generate;
    evt_err  <= evt_err_p;

    -- One-clk edge pulses: any change on a toggle, RISING only on a trigger.
    go_edges: for i in 0 to 3 generate
        go_pulse(i)       <= '1' when (go_c2(i) /= go_prev(i)) else '0';
        abort_pulse(i)    <= '1' when (ab_c2(i) /= ab_prev(i)) else '0';
        clr_done_pulse(i) <= '1' when (cd_c2(i) /= cd_prev(i)) else '0';
        clr_err_pulse(i)  <= '1' when (ce_c2(i) /= ce_prev(i)) else '0';
        -- Same-cycle BUSY cover: raw ClkMem toggle against the deepest clk-synced stage, high from the CHnGO write until the engine consumes it.
        go_pending(i)     <= '1' when (go_tgl(i) /= go_prev(i)) else '0';
    end generate;
    crc_wr_pulse <= '1' when (crcw_c2 /= crcw_prev) else '0';
    evt_uart <= '1' when (tu2 = '1' and tu_prev = '0') else '0';
    evt_qspi <= '1' when (tq2 = '1' and tq_prev = '0') else '0';
    evt_nfc  <= '1' when (tn2 = '1' and tn_prev = '0') else '0';

    /* ------------------------- channel engine + master FSM (clk) --------------
       One rising-clk process owning the SRC/DST/LEN working counters, the round-robin plus priority picker, the master-port handshake, the deny-guard, the reject-at-GO error setter, the paced-source M_CLR, crc_acc (single owner) and the sticky CHnDONE/CHnERR flags.
       W1C clears are applied first and the engine's SETs override them, so SET WINS over CLEAR. */
    engine: process(resetn, clk)
        variable selv    : integer range 0 to 3;
        variable idx     : integer range 0 to 3;
        variable found   : boolean;
        variable serv    : boolean;
        variable prbit   : std_logic;
        variable trg     : std_logic_vector(3 downto 0);
        variable sword   : std_logic_vector(14 downto 0);
        variable deny    : boolean;
        variable newlen  : std_logic_vector(31 downto 0);
        variable lenzero : boolean;
        variable needclr : boolean;
    begin
        if resetn = '0' then
            dstate    <= M_IDLE;
            src_work  <= (others => (others => '0'));
            dst_work  <= (others => (others => '0'));
            len_work  <= (others => (others => '0'));
            cfg_work  <= (others => (others => '0'));
            busy      <= (others => '0');
            pace_go   <= (others => '0');
            abort_req <= (others => '0');
            done_flag <= (others => '0');
            err_flag  <= (others => '0');
            cur_ch    <= 0;
            rr_ptr    <= 0;
            evt_done_p <= (others => '0');
            evt_err_p  <= '0';
            activech  <= "000";
            in_clr    <= '0';
            data_hold <= (others => '0');
            crc_acc   <= X"FFFF";
            m_req_r   <= '0';
            m_we_r    <= "0000";
            m_addr_r  <= (others => '0');
            m_wdata_r <= (others => '0');
        elsif rising_edge(clk) then

            -- (a) W1C flag clears; the engine SETs below override them, so SET wins
            for ch in 0 to 3 loop
                if clr_done_pulse(ch) = '1' then done_flag(ch) <= '0'; end if;
                if clr_err_pulse(ch)  = '1' then err_flag(ch)  <= '0'; end if;
            end loop;

            -- EVFAB event pulses: default-cleared every cycle and set ONLY at the done/err SET sites below, giving registered one-clk pulses.
            evt_done_p <= (others => '0');
            evt_err_p  <= '0';

            -- (b) DMA0CRC seed commit; this process is crc_acc's only driver
            if crc_wr_pulse = '1' then
                crc_acc <= crc_seed_reg;
            end if;

            -- (c) a paced event sets pace_go; abort requests are latched, per channel
            for ch in 0 to 3 loop
                if ch < NCH then
                    if busy(ch) = '1' then
                        case cfg_work(ch)(5 downto 2) is
                            when "0001" => if evt_uart = '1' then pace_go(ch) <= '1'; end if;
                            when "0010" => if evt_qspi = '1' then pace_go(ch) <= '1'; end if;
                            when "0011" => if evt_nfc  = '1' then pace_go(ch) <= '1'; end if;
                            when others => null;
                        end case;
                    end if;
                    if abort_pulse(ch) = '1' and busy(ch) = '1' then
                        abort_req(ch) <= '1';
                    end if;
                end if;
            end loop;

            -- (d) GO arm and reject-at-GO: sample the quasi-static programmed stores on the go edge, data before flag.
            for ch in 0 to 3 loop
                if ch < NCH and (go_pulse(ch) = '1' or task_go_eff(ch) = '1') then
                    if (len_reg(ch) = X"00000000")
                       or (src_reg(ch)(1 downto 0) /= "00")
                       or (dst_reg(ch)(1 downto 0) /= "00")
                       or (src_reg(ch)(31 downto 17) /= "000000000000000")
                       or (dst_reg(ch)(31 downto 17) /= "000000000000000")
                       or (src_reg(ch)(16 downto 14) = "010")
                       or (dst_reg(ch)(16 downto 14) = "010") then
                        err_flag(ch) <= '1';               -- channel never runs
                        evt_err_p    <= '1';               -- EVFAB error set site
                    elsif busy(ch) = '0' then
                        -- Keep this clk-domain busy test: the ClkMem-side busy_sync qualifier has a 2-gated-edge blind window, and a GO landing inside it must not reload an in-flight channel's working registers.
                        busy(ch)      <= '1';
                        src_work(ch)  <= src_reg(ch)(16 downto 0);
                        dst_work(ch)  <= dst_reg(ch)(16 downto 0);
                        len_work(ch)  <= len_reg(ch);
                        cfg_work(ch)  <= cfg_reg(ch);
                        -- A data-ready LEVEL already high at GO produces no new rising edge, so arm pace_go from the CURRENT synced level; edge-detect covers the rest.
                        case cfg_reg(ch)(5 downto 2) is
                            when "0001" => pace_go(ch) <= tu2;
                            when "0010" => pace_go(ch) <= tq2;
                            when "0011" => pace_go(ch) <= tn2;
                            when others => pace_go(ch) <= '0';
                        end case;
                        abort_req(ch) <= '0';
                    end if;
                end if;
            end loop;

            -- (e) master-port FSM
            case dstate is

                -- pick the next serviceable channel; the deny-guard is evaluated HERE, the cycle before m_req, so a denied read never asserts m_req
                when M_IDLE =>
                    m_req_r  <= '0';
                    activech <= "000";
                    in_clr   <= '0';
                    -- between-txn abort: stop immediately (no CHnDONE, no CHnERR)
                    for ch in 0 to 3 loop
                        if ch < NCH and busy(ch) = '1' and abort_req(ch) = '1' then
                            busy(ch)      <= '0';
                            abort_req(ch) <= '0';
                        end if;
                    end loop;
                    -- pick: strict PRIO=1 before PRIO=0, RR within class past rr_ptr
                    found := false; selv := 0;
                    for pr in 1 downto 0 loop
                        for k in 1 to 4 loop
                            if k <= NCH then
                                idx   := (rr_ptr + k) mod NCH;
                                trg   := cfg_work(idx)(5 downto 2);
                                prbit := cfg_work(idx)(6);
                                serv  := (busy(idx) = '1') and (abort_req(idx) = '0')
                                         and ((trg = "0000") or (pace_go(idx) = '1'));
                                if (not found) and serv
                                   and (((prbit = '1') and (pr = 1))
                                        or ((prbit = '0') and (pr = 0))) then
                                    selv  := idx;
                                    found := true;
                                end if;
                            end if;
                        end loop;
                    end loop;
                    if found then
                        rr_ptr <= selv;
                        sword  := src_work(selv)(16 downto 2);
                        -- Deny-guard on the READ address: the WHOLE mutex sub-slot window at byte 0x6000-0x60FF (its 16 mutexes alias within it) and the irq_router CLAIM word at byte 0x7800 exactly, both of which have atomic read side effects.
                        -- Everything else in the router page is side-effect-free; write-side side effects are a software contract, not guarded here.
                        deny := (src_work(selv)(16 downto 8) = "001100000")
                                or (sword = "001111000000000");
                        if deny then
                            err_flag(selv) <= '1';
                            evt_err_p      <= '1';        -- EVFAB error set site
                            busy(selv)     <= '0';        -- abort the channel
                        else
                            trg := cfg_work(selv)(5 downto 2);
                            if trg = "0001" or trg = "0010" then
                                pace_go(selv) <= '0';     -- one word per event
                            end if;
                            cur_ch   <= selv;
                            activech <= conv_std_logic_vector(selv, 3);
                            m_req_r  <= '1';
                            m_we_r   <= "0000";
                            m_addr_r <= sword;
                            dstate   <= M_RD_REQ;
                        end if;
                    end if;

                -- read txn in flight: capture the word and fold its CRC on the done cycle
                when M_RD_REQ =>
                    if m_done = '1' then
                        data_hold <= m_rdata;
                        if cfg_work(cur_ch)(7) = '1' then     -- CRCEN
                            crc_acc <= crc4;
                        end if;
                        dstate <= M_RD_CAP;
                    end if;

                when M_RD_CAP =>
                    m_req_r <= '0';                            -- acked flop drop
                    dstate  <= M_RD_GAP;

                -- the observed-low cycle: abort here, or issue the paired write
                when M_RD_GAP =>
                    if abort_req(cur_ch) = '1' then
                        busy(cur_ch)      <= '0';             -- read txn done, stop (no done)
                        abort_req(cur_ch) <= '0';
                        dstate <= M_IDLE;
                    else
                        m_req_r   <= '1';
                        m_we_r    <= "1111";
                        m_addr_r  <= dst_work(cur_ch)(16 downto 2);
                        m_wdata_r <= data_hold;
                        dstate    <= M_WR_REQ;
                    end if;

                -- write txn in flight
                when M_WR_REQ =>
                    if m_done = '1' then
                        dstate <= M_WR_CAP;
                    end if;

                when M_WR_CAP =>
                    m_req_r <= '0';                            -- acked flop drop
                    dstate  <= M_WR_GAP;

                -- observed-low cycle after a write: retire the word, or close out the M_CLR write
                when M_WR_GAP =>
                    if in_clr = '1' then
                        in_clr <= '0';                        -- M_CLR write's gap
                        dstate <= M_IDLE;
                    else
                        if cfg_work(cur_ch)(0) = '1' then      -- SINC
                            src_work(cur_ch) <= src_work(cur_ch) + 4;
                        end if;
                        if cfg_work(cur_ch)(1) = '1' then      -- DINC
                            dst_work(cur_ch) <= dst_work(cur_ch) + 4;
                        end if;
                        newlen := len_work(cur_ch) - 1;
                        len_work(cur_ch) <= newlen;
                        if abort_req(cur_ch) = '1' then
                            busy(cur_ch)      <= '0';         -- stop, no done flag
                            abort_req(cur_ch) <= '0';
                            dstate <= M_IDLE;
                        else
                            lenzero := (newlen = X"00000000");
                            if lenzero then
                                done_flag(cur_ch)  <= '1';
                                busy(cur_ch)       <= '0';
                                evt_done_p(cur_ch) <= '1';  -- EVFAB done set site
                            end if;
                            trg     := cfg_work(cur_ch)(5 downto 2);
                            needclr := (trg = "0010") or (trg = "0011" and lenzero);
                            if needclr then
                                m_req_r   <= '1';
                                m_we_r    <= "1111";
                                -- The SR slot DIFFERS per source: QSPI SLOT_SR = 5 (+0x14), NFC SLOT_SR = 1 (+0x04).
                                -- Do not collapse these to one offset: QSPI slot 1 is CMD, whose lane-0 write LAUNCHES a transaction.
                                if trg = "0010" then
                                    m_addr_r <= src_work(cur_ch)(16 downto 8) & "000101";
                                else
                                    m_addr_r <= src_work(cur_ch)(16 downto 8) & "000001";
                                end if;
                                m_wdata_r <= X"00000004";     -- W1C SR bit 2 only, clearing nothing else
                                in_clr    <= '1';
                                dstate    <= M_CLR;
                            else
                                dstate <= M_IDLE;
                            end if;
                        end if;
                    end if;

                -- paced-source flag clear in flight: one write W1C-ing the source's data-ready flag (QSPI0 RXFULL every word, NFC0 frame ack at LEN=0)
                when M_CLR =>
                    if m_done = '1' then
                        dstate <= M_WR_CAP;                    -- reuse CAP/GAP (in_clr routes)
                    end if;

                -- unreachable, kept so the state register always recovers
                when others =>
                    dstate <= M_IDLE;

            end case;
        end if;
    end process;

end behavioral;
