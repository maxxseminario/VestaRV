library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ===========================================================================
-- DMA: configurable multi-channel single-shot DMA controller with peripheral
-- pacing + CRC16-CDMA2000 ride-along. Base 0x6800 (mutex-page sub-slot 8).
-- Two peripherals fused: an arbiter SLAVE (register file on gated ClkMem,
-- D4-xcollapse-clean like RTC/PWM/OW) and an arbiter MASTER (the transfer
-- engine on free-running clk = MCLK, slice 4 of arb_*). Zero pins. TWO IRQs:
-- irq_done (combined channels-done, vector 118), irq_err (vector 119).
-- FROZEN design: ~/vesta_docs/digperiphs/dma_design.md (decisions D1-D21,
-- orchestrator adjudications A1-A19 -- ALL BINDING; An overrides any
-- conflicting Dn prose). Peripheral #7 of the digital-peripherals program.
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary reduce,
-- no reading of out ports). Every process infers exactly ONE edge of ONE
-- clock; every synchronizer is single-edge (Genus VHDL-601 discipline). NO
-- falling_edge of anything (specifically NOT of EnMemPeriph). NO clock gates,
-- NO generated clocks (the engine is a plain FSM + counters on clk).
--
-- ------------------------------------------------------------------------
-- D1 -- ONE clock family. The master-port FSM, the per-channel SRC/DST/LEN
-- working counters, the RR+priority picker, the CRC datapath, the pacing
-- edge-detectors, the sticky W1C flags (CHnDONE/CHnERR), BUSY/ACTIVECH and
-- the IRQ combiner all ride free-running `clk` (= MCLK at integration). The
-- register file (CR/CFG/SRC/DST/LEN/CRC stores, the launch/W1C toggles, the
-- registered read mux) rides gated `ClkMem`. The engine CANNOT ride ClkMem
-- (which ticks only during a bus access) -- it must advance autonomously
-- while the bus is idle. At integration clk and ClkMem are the SAME physical
-- mclk net (RTC A2 / PWM D1 precedent) so there is NO metastability CDC
-- between the engine and the arbiter (mclk<->mclk, exactly like the harts).
-- The ONLY true CDC is the three trigger inputs (2-FF synced, D9). Every
-- ClkMem<->clk hand-off below is a toggle or a held/quasi-static level, kept
-- standalone-honest so the block is correct even under a bench clk/ClkMem
-- skew.
--
-- MASTER-PORT HANDSHAKE (D2 + A1, the VERBATIM arb_lat_master.txn contract):
--   raise m_req with m_we/m_addr/m_wdata stable -> HOLD all stable through the
--   m_done cycle -> capture m_rdata ON the m_done cycle -> drop m_req via an
--   acked flop ONE clk AFTER m_done -> >=1 arbiter-observed m_req-low cycle
--   before any re-request (the need_release / WAIT-FOR-RELEASE contract; a
--   continuously-high m_req across two words is an M5a stale ghost that
--   corrupts the arbiter IDLE pick). Boundary depth 0 (the DMA lives inside
--   MCU fabric on mclk, NOT behind a tile boundary). FSM (single rising-clk
--   process, distinct states, NO counters):
--     M_IDLE   -- pick next serviceable channel (D7); deny-guard (D12) is
--                 evaluated HERE, the cycle BEFORE m_req; a denied read never
--                 asserts m_req.
--     M_RD_REQ -- m_req='1', m_we="0000", m_addr=src_word; wait m_done. On the
--                 m_done edge: data_hold<=m_rdata, fold CRC (D14) -> M_RD_CAP.
--     M_RD_CAP -- the ONE stale-req cycle (m_req still '1'); drop m_req.
--     M_RD_GAP -- m_req='0' for exactly 1 observed-low cycle.
--     M_WR_REQ -- m_req='1', m_we="1111", m_addr=dst_word, m_wdata=data_hold.
--     M_WR_CAP -- stale-req cycle; drop m_req.
--     M_WR_GAP -- 1 observed-low cycle; advance ptr/LEN (D11); LEN=0 -> CHnDONE
--                 + drop busy (D16); if the paced source needs a flag clear
--                 (D10) launch M_CLR, else -> M_IDLE. (Reused for the M_CLR
--                 write's own CAP/GAP via in_clr.)
--     M_CLR    -- (paced only) one WRITE txn W1C-ing the source data-ready flag
--                 (QSPI0 RXFULL every word / NFC0 frame ack at LEN=0), same
--                 verbatim handshake; completes through M_WR_CAP/M_WR_GAP.
--   A1 cycle accounting: m_done sampled at the edge ENDING the DATA cycle,
--   m_rdata captured AT that edge; CAP = the ONE stale-req cycle; req drops at
--   CAP->GAP; each GAP is exactly 1 observed-low cycle at depth 0 --
--   cycle-identical to arb_lat_master.txn (+2 re-request).
--
-- M_CLR ADDRESS DERIVATION (D10; Fable R3 correction of the first cut): the
-- source SR word to W1C is the channel's SRC 256B peripheral window base plus
-- a PER-SOURCE SR slot offset -- the two paced W1C sources do NOT share one:
--     QSPI (TRIG=2): QSPI.vhd SLOT_SR = 5 (+0x14)  -> m_addr = src(16:8)&"000101"
--                    (slot 1 there is SLOT_CMD, whose lane-0 write LAUNCHES a
--                    transaction -- the original one-formula "+0x04" cut would
--                    have fired spurious QSPI commands)
--     NFC  (TRIG=3): NFC.vhd  SLOT_SR = 1 (+0x04)  -> m_addr = src(16:8)&"000001"
-- Verified against QSPI.vhd:50-55 (SLOT_* constants) and NFC.vhd:90-97. The
-- clear write drives m_wdata = 0x00000004 (ONLY SR bit 2 set; W1C-per-bit
-- clears nothing else -- A11).
--
-- DENY TABLE (D12 + A5, read-only guard; generated READ word address checked
-- the cycle before m_req; a hit sets CHnERR + aborts the channel, no txn):
--   * mutex sub-slot window: byte 0x6000-0x60FF (src_work(16:8)="001100000")
--     -- the WHOLE window (A5: NMUTEX=16 aliases within it, deny it all); a
--     read is an atomic sh_master-attributed mutex CLAIM.
--   * irq_router CLAIM word: byte 0x7800 EXACTLY (word 0x1E00,
--     src_word="001111000000000") -- a read is an atomic lowest-ID claim.
--     PENDL/M/U, INSVCL/M/U and the HhEN rows are side-effect-free and NOT
--     denied (A5).
-- Write-side side effects (mutex release / router COMPLETE via a DST) are a
-- SOFTWARE contract this phase (A13) -- NOT guarded in hardware.
--
-- ERROR MODEL (D13 + A18, reject-at-GO, A16): CHnERR (W1C) sets on (a) a deny
-- hit (D12, mid-flight abort); or at GO on (b) LEN=0; (c) SRC or DST
-- misaligned (bits 1:0 /= "00"); (d) SRC or DST out-of-window (byte >= 0x20000
-- i.e. bits 31:17 /= 0); (e) SRC or DST in the TCM HOLE 0x8000-0xBFFF (bits
-- 16:14 = "010", A18 -- tile-private space excluded from every sh_sel). A
-- reject-at-GO channel never runs (busy never rises); a deny hit aborts
-- mid-flight; irq_err asserts if ERRIE=1. Abort (D15/A15) sets NEITHER
-- CHnDONE nor CHnERR.
--
-- A8 IE-GATE DRIVER CONTRACT (integration, informational): the trigger taps
-- carry the source peripheral's EXISTING IE-gated irq_* level (trig_uart0_rc
-- <- irq_uart0_rc, trig_qspi0_rxf <- QSPI0 irq_rxf, trig_nfc0_rxf <- NFC0
-- irq_rxf -- NONE export a raw flag port). So pacing REQUIRES the source's IE
-- bit set (UCR_CIE / QSPIxIE.RXFIE / NFCxIE RXFIE); routing that vector to a
-- hart is independent and optional (an enabled-but-unrouted source pending in
-- the router is benign). The D10 flag-clear sequences are unchanged (the IE
-- gate is transparent to them).
--
-- CDC CROSSING INVENTORY (matches the design-doc table crossing-for-crossing;
-- the ONLY true metastability CDC is #1-3, the trigger inputs):
--   1. trig_uart0_rc  mclk(UART idx13) -> clk : 2-FF + rising-edge (D9).
--   2. trig_qspi0_rxf smclk/clk_baud    -> clk : 2-FF + rising-edge (D9) async.
--   3. trig_nfc0_rxf  smclk(NFC)         -> clk : 2-FF + rising-edge (D9) async.
--   4. go_tgl/abort_tgl ClkMem -> clk : toggle + edge-detect (D8/D15); single
--      mclk family at integration (PWM D2).
--   5. clr_done_tgl/clr_err_tgl (W1C) ClkMem -> clk : toggle + edge-detect,
--      cleared in the flag's own clk process, SET WINS over CLEAR (D16).
--   6. crc_wr_tgl (seed commit) ClkMem -> clk : toggle + edge-detect, loads
--      crc_acc (RTC write-commit idiom -- one owner of crc_acc, the clk FSM).
--   7. BUSY/ACTIVECH/CHnDONE/CHnERR/DMA0CRC/LEN clk -> ClkMem : held levels
--      sampled by the registered read mux (D4).
--   8. busy(ch) clk -> ClkMem : 2-FF busy_sync, the launch-suppress qualifier.
--   9. master port m_* <-> arb_*(4) : NOT a CDC (same free-running mclk,
--      depth-0 registered handshake, D2).
--
-- Register map (D5; base 0x6800, slot n @ 0x6800 + 4n, off MABPart(7:2);
-- 4-channel SUPERSET, absent channels (ch>=NCH) read 0 / ignore writes, D6):
--   0  DMA0CR  : [0]DMAEN [4:1]CHnGO(w1 self-clearing, rd0) [8:5]CHnABORT(w1
--                self-clearing, rd0) [12]DONEIE [13]ERRIE, rest rsvd rd0.
--   1  DMA0SR  : [0]BUSY ro [4:1]CHnDONE W1C [8:5]CHnERR W1C [11:9]ACTIVECH ro.
--   2..5   CH0 {SRC,DST,LEN,CFG};  6..9 CH1; 10..13 CH2; 14..17 CH3.
--     DMA0CnSRC/DST rw byte addr [16:0] (word-aligned); full written value
--       read back. DMA0CnLEN rw words, reads CURRENT REMAINING (the working
--       counter; 0 until the first GO). DMA0CnCFG: [0]SINC [1]DINC [5:2]TRIG
--       (0 mem2mem/1 UART0-RC/2 QSPI0-RXFULL/3 NFC0-frame) [6]PRIO [7]CRCEN.
--   18 DMA0CRC : rw [15:0] CRC16-CDMA2000 accumulator, reset 0xFFFF (seed via
--                write before GO, result read after DONE; engine folds in clk).
--   19 DMA0DESC: reserved -- reads 0, writes ignored. Slots >=20 read 0.
-- ===========================================================================

entity DMA is
    generic (
        NCH : natural := 4;   -- channel count, {2,4} (D6)
        AW  : natural := 15   -- master-port word-address width (SH_AW; D19)
    );
    port (
        clk         : in  std_logic;                     -- free-running MCLK at integration (D1):
                                                         -- master-port FSM, channel engine, CRC,
                                                         -- pacing sync, sticky flags, IRQ combiner
        resetn      : in  std_logic;                     -- chip reset, active-low (async)

        -- register-file slave port (RTC/PWM/OW house idiom, D4)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);

        -- arbiter MASTER port (slice 4 of arb_*; D2/D3, depth 0)
        m_req       : out std_logic;                     -- held through m_done, dropped via acked flop
        m_we        : out std_logic_vector(3 downto 0);  -- active-HIGH lanes; "0000" = read
        m_addr      : out std_logic_vector(AW-1 downto 0);-- word address = byte_ptr(16:2), zero-extended to AW
        m_wdata     : out std_logic_vector(31 downto 0);
        m_gnt       : in  std_logic;                     -- observed only (handshake waits on m_done)
        m_done      : in  std_logic;                     -- 1-cycle completion; m_rdata valid here
        m_rdata     : in  std_logic_vector(31 downto 0);

        -- pacing triggers (data-ready LEVELS; tie '0' when the source is absent, D9/D10/A8)
        trig_uart0_rc  : in std_logic := '0';            -- UART0 RCIF via irq_uart0_rc (live, idx 13)
        trig_qspi0_rxf : in std_logic := '0';            -- QSPI0 RXFULL via irq_rxf (knob-gated)
        trig_nfc0_rxf  : in std_logic := '0';            -- NFC0 payload-ready via irq_rxf (knob-gated)

        -- interrupts (M19 PLIC-lite levels into irq_router)
        irq_done    : out std_logic;                     -- combined channels-done (vector 118)
        irq_err     : out std_logic;                     -- error (vector 119)

        -- EVFAB taps (event fabric, event_fabric_spec.md 2026-07-24).
        -- task_go: one-clk fabric pulses (T0/T1 wire bits 0/1); consumed at the
        -- SAME arm site as go_pulse -> reject-at-GO, busy suppression and
        -- pacing arm behave IDENTICALLY to a register GO (frozen D8/D13
        -- semantics). DMAEN is re-applied at the tap (the ClkMem-side wdata(0)
        -- qualifier does not see task GOs). busy_any/BUSY covers a task GO the
        -- same cycle it arrives (no blind window vs the register path's
        -- go_pending). evt_done/evt_err: registered one-clk pulses at the
        -- flags' SET sites (pre-IE; abort sets NEITHER, by D15 design).
        -- ch_busy: per-channel engaged levels for the fabric's OVR input.
        task_go     : in  std_logic_vector(3 downto 0) := (others => '0');
        evt_done    : out std_logic_vector(3 downto 0); -- EV10/EV11 wire bits 0/1
        evt_err     : out std_logic;                     -- EV12 (combined set sites)
        ch_busy     : out std_logic_vector(3 downto 0)  -- fabric task_busy taps
    );
end DMA;

architecture behavioral of DMA is

    -- ---- CRC16-CDMA2000 combinational cell (poly 0xC857, D14) --------------
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

    -- ---- superset array types (4-channel map; NCH gates engine/read, D6) --
    type slv32_arr is array(0 to 3) of std_logic_vector(31 downto 0);
    type slv17_arr is array(0 to 3) of std_logic_vector(16 downto 0);
    type slv8_arr  is array(0 to 3) of std_logic_vector(7 downto 0);
    type sl_arr    is array(0 to 3) of std_logic;

    -- ---- B4 master-port FSM states (D2/A1) --------------------------------
    type t_dma_state is (M_IDLE, M_RD_REQ, M_RD_CAP, M_RD_GAP,
                         M_WR_REQ, M_WR_CAP, M_WR_GAP, M_CLR);
    signal dstate : t_dma_state;

    -- ---- B1 register-file storage (ClkMem domain) -------------------------
    signal dmaen       : std_logic;                       -- DMA0CR[0]
    signal doneie      : std_logic;                       -- DMA0CR[12]
    signal errie       : std_logic;                       -- DMA0CR[13]
    signal src_reg     : slv32_arr;                        -- programmed SRC (full readback)
    signal dst_reg     : slv32_arr;                        -- programmed DST (full readback)
    signal len_reg     : slv32_arr;                        -- programmed LEN seed
    signal cfg_reg     : slv8_arr;                         -- CFG store
    signal crc_seed_reg: std_logic_vector(15 downto 0);    -- DMA0CRC seed store (ClkMem)
    signal go_tgl      : sl_arr;                           -- D8 launch request toggles
    signal abort_tgl   : sl_arr;                           -- D15 abort request toggles
    signal clr_done_tgl: sl_arr;                           -- D16 W1C CHnDONE toggles
    signal clr_err_tgl : sl_arr;                           -- D16 W1C CHnERR toggles
    signal crc_wr_tgl  : std_logic;                        -- DMA0CRC seed-commit toggle
    signal dma_slot    : natural range 0 to 63;            -- decoded word slot

    -- ---- B8 busy 2-FF into ClkMem (launch suppress, D8) -------------------
    signal busy_c1, busy_c2 : sl_arr;
    signal busy_sync        : sl_arr;

    -- ---- B2/B3 clk-domain CDC: toggle syncs + trigger syncs ---------------
    signal go_c1, go_c2, go_prev       : sl_arr;           -- D8 go_tgl sync + edge
    signal ab_c1, ab_c2, ab_prev       : sl_arr;           -- D15 abort_tgl sync + edge
    signal cd_c1, cd_c2, cd_prev       : sl_arr;           -- D16 W1C done sync + edge
    signal ce_c1, ce_c2, ce_prev       : sl_arr;           -- D16 W1C err sync + edge
    signal crcw_c1, crcw_c2, crcw_prev : std_logic;        -- crc seed commit sync + edge
    signal tu1, tu2, tu_prev           : std_logic;        -- D9 UART trigger 2-FF + edge
    signal tq1, tq2, tq_prev           : std_logic;        -- D9 QSPI trigger 2-FF + edge
    signal tn1, tn2, tn_prev           : std_logic;        -- D9 NFC  trigger 2-FF + edge
    signal go_pulse, abort_pulse       : sl_arr;           -- one-clk launch/abort pulses
    signal clr_done_pulse, clr_err_pulse : sl_arr;         -- one-clk W1C pulses
    signal crc_wr_pulse                : std_logic;        -- one-clk seed-commit pulse
    signal go_pending                  : sl_arr;           -- D8 same-cycle BUSY cover
    signal evt_uart, evt_qspi, evt_nfc : std_logic;        -- one-clk trigger events

    -- ---- B4 engine working state (clk domain) -----------------------------
    signal src_work : slv17_arr;                           -- 17-bit byte working SRC ptr
    signal dst_work : slv17_arr;                           -- 17-bit byte working DST ptr
    signal len_work : slv32_arr;                           -- remaining LEN (words) -- SR readback
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
    signal rr_ptr    : natural range 0 to 3;               -- D7 round-robin pointer
    signal activech  : std_logic_vector(2 downto 0);       -- SR.ACTIVECH (0 when idle)
    signal in_clr    : std_logic;                          -- M_CLR-write routing flag (CAP/GAP reuse)
    signal data_hold : std_logic_vector(31 downto 0);      -- read->write word hold
    signal crc_acc   : std_logic_vector(15 downto 0);      -- DMA0CRC accumulator (clk owner)

    -- ---- B4 registered master-port outputs --------------------------------
    signal m_req_r   : std_logic;
    signal m_we_r    : std_logic_vector(3 downto 0);
    -- CPR3/R3: the DMA's OWN address space is fixed at 17 bits (byte pointers
    -- 0x00000-0x1FFFF: shared ROM, the peripheral window and the bulk RAM),
    -- which is what every check and slice below is written against, and which
    -- is still exactly the region a DMA has any business in. The MASTER PORT is
    -- AW = SH_AW bits wide, and SH_AW became 16 on the orchestrator configs
    -- (the read-only TCM apertures live at 0x20000+, deliberately out of the
    -- DMA's reach). So the register stays 15 bits and the port is ZERO-EXTENDED
    -- on the way out. Before this the register was declared AW-wide and every
    -- assignment fed it a 15-bit value -- fine at AW=15, a shape mismatch that
    -- kills the sim at the first descriptor fetch at AW=16 (measured: TRASMM at
    -- DMA.vhd:688 on config/penta_wound.json).
    signal m_addr_r  : std_logic_vector(14 downto 0);
    -- NULL RANGE when AW = 15, so the concatenation below is the identity and
    -- every pre-CPR3 configuration is bit-identical.
    constant M_ADDR_PAD : std_logic_vector(AW-1 downto 15) := (others => '0');
    signal m_wdata_r : std_logic_vector(31 downto 0);

    -- ---- B5 CRC chain (four chained combinational CRC16, D14) --------------
    signal crc1, crc2, crc3, crc4 : std_logic_vector(15 downto 0);

    -- ---- B6 combinational status / IRQ ------------------------------------
    signal busy_any, done_any, err_any : std_logic;

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode (EnMemPeriph-qualified LEVEL, D4; never an edge).
    dma_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- master-port registered outputs (D2 depth-0 slice-4).
    m_req   <= m_req_r;
    m_we    <= m_we_r;
    m_addr  <= M_ADDR_PAD & m_addr_r;
    m_wdata <= m_wdata_r;

    -- BUSY same-cycle (D8/D16): any channel busy OR any GO pending (go_pending
    -- asserts the instant the CHnGO write lands, clears when the engine has
    -- observed the launch) -- no assert blind window for a write-then-poll.
    busy_any <= (busy(0) or go_pending(0) or task_go_eff(0))
             or (busy(1) or go_pending(1) or task_go_eff(1))
             or (busy(2) or go_pending(2) or task_go_eff(2))
             or (busy(3) or go_pending(3) or task_go_eff(3));

    -- combined done/err (ch>=NCH flags never driven -> read 0, D6).
    done_any <= done_flag(0) or done_flag(1) or done_flag(2) or done_flag(3);
    err_any  <= err_flag(0)  or err_flag(1)  or err_flag(2)  or err_flag(3);

    -- irq_done/irq_err = (status and enable), combinational, never latched (D17).
    irq_done <= done_any and doneie;
    irq_err  <= err_any  and errie;

    -- B5 CRC chain: fold the READ word bytes b0->b3 (little-endian first, D14);
    -- CrcOld starts from crc_acc, crc4 is registered on the M_RD_REQ->M_RD_CAP
    -- (done) edge for CRCEN channels. Combinational, driven from m_rdata (valid
    -- on the done cycle) so the folded word matches the captured data_hold.
    u_crc0: CRC16 port map (DataIn => m_rdata(7  downto 0),  CrcOld => crc_acc, CrcOut => crc1);
    u_crc1: CRC16 port map (DataIn => m_rdata(15 downto 8),  CrcOld => crc1,    CrcOut => crc2);
    u_crc2: CRC16 port map (DataIn => m_rdata(23 downto 16), CrcOld => crc2,    CrcOut => crc3);
    u_crc3: CRC16 port map (DataIn => m_rdata(31 downto 24), CrcOld => crc3,    CrcOut => crc4);

    -- ------------------------- B1: register write (ClkMem, D4/D5/D8) ----------
    -- Rising ClkMem, EnMemPeriph='0' qualified. CR/SR/CRC and per-channel
    -- writes are lane-0 qualified (WEn(0)='0' -- a normal word/low store asserts
    -- lane 0). A CHnGO=1 in DMA0CR flips go_tgl(ch) UNLESS DMAEN=0 or the channel
    -- is already busy (busy_sync, D8) -- the descriptor (SRC/DST/LEN/CFG stores)
    -- is quasi-static and sampled by the clk engine on the go edge. CHnABORT=1
    -- flips abort_tgl(ch) unconditionally (D15). SR lane-0 W1C writes flip the
    -- clr_*_tgl toggles (D16). DMA0CRC stages the seed + flips crc_wr_tgl (D14).
    -- ch>=NCH writes are dropped (D6). Reset via resetn (bus domain).
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
                                -- CHnGO[4:1]: launch suppressed on DMAEN=0 or busy (D8)
                                if wdata(1 + ch) = '1' and wdata(0) = '1'
                                   and busy_sync(ch) = '0' then
                                    go_tgl(ch) <= not go_tgl(ch);
                                end if;
                                -- CHnABORT[8:5]: orderly-stop request (D15)
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
                    -- DMA0CRC seed: stage + flip commit toggle (RTC write-commit)
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

    -- ------------------------- B1: register read (ClkMem, D4/D6) --------------
    -- Registered read mux on rising ClkMem over data ALREADY in the mclk domain
    -- (register stores + clk-domain flags/counters). No pre-latch, no bridge.
    -- CHnGO/CHnABORT read 0 (self-clearing commands). LEN reads the WORKING
    -- remaining counter (len_work). ch>=NCH channel slots read 0 (D6). Slots
    -- >=20 and DESC read 0.
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

    -- ------------------------- B8: busy 2-FF into ClkMem (D8) -----------------
    -- Per-channel engine busy synchronized into ClkMem -- the launch-suppress
    -- qualifier in reg_write (a GO to a busy channel must not flip go_tgl).
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

    -- ------------------------- B2/B3: clk-domain CDC (D8/D9/D15/D16) ----------
    -- 2-FF + edge-detect every ClkMem->clk toggle (go/abort/W1C done/W1C err/
    -- crc seed commit); 2-FF + rising-edge every trigger input (the ONLY true
    -- metastability CDC). Single edge (rising clk) only. Reset via resetn.
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

    -- EVFAB task GO: DMAEN re-applied clk-side (quasi-static level, crosses
    -- bare per D4) -- a task GO with DMAEN=0 is completely inert, matching the
    -- register path's ClkMem-side wdata(0) suppression.
    task_gates: for i in 0 to 3 generate
        task_go_eff(i) <= task_go(i) and dmaen;
        ch_busy(i)     <= busy(i) or go_pending(i) or task_go_eff(i);
        evt_done(i)    <= evt_done_p(i);   -- element-wise: sl_arr vs slv port
    end generate;
    evt_err  <= evt_err_p;

    -- one-clk edge pulses (toggle: any change; trigger: RISING only, D9).
    go_edges: for i in 0 to 3 generate
        go_pulse(i)       <= '1' when (go_c2(i) /= go_prev(i)) else '0';
        abort_pulse(i)    <= '1' when (ab_c2(i) /= ab_prev(i)) else '0';
        clr_done_pulse(i) <= '1' when (cd_c2(i) /= cd_prev(i)) else '0';
        clr_err_pulse(i)  <= '1' when (ce_c2(i) /= ce_prev(i)) else '0';
        -- D8 same-cycle BUSY cover: raw ClkMem toggle vs deepest clk-synced
        -- stage -- high from the CHnGO write until the engine consumes it.
        go_pending(i)     <= '1' when (go_tgl(i) /= go_prev(i)) else '0';
    end generate;
    crc_wr_pulse <= '1' when (crcw_c2 /= crcw_prev) else '0';
    evt_uart <= '1' when (tu2 = '1' and tu_prev = '0') else '0';
    evt_qspi <= '1' when (tq2 = '1' and tq_prev = '0') else '0';
    evt_nfc  <= '1' when (tn2 = '1' and tn_prev = '0') else '0';

    -- ------------------------- B4/B5/B6: channel engine + master FSM (clk) -----
    -- Single rising-clk process (D2/A1). Owns: the SRC/DST/LEN working counters,
    -- the RR+PRIO picker, the verbatim master-port handshake, the deny-guard, the
    -- reject-at-GO error setter, the paced-source M_CLR, the CRC accumulator
    -- (crc_acc, single owner), and the sticky CHnDONE/CHnERR flags (W1C clears
    -- applied first, engine SETs override -> SET WINS, D16). NO counters for the
    -- GAPs -- distinct states. Reset via resetn.
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

            -- (a) W1C flag clears (default; engine SETs below override -> SET wins)
            for ch in 0 to 3 loop
                if clr_done_pulse(ch) = '1' then done_flag(ch) <= '0'; end if;
                if clr_err_pulse(ch)  = '1' then err_flag(ch)  <= '0'; end if;
            end loop;

            -- EVFAB event pulses: default-cleared every cycle, set ONLY at the
            -- done/err SET sites below -> registered one-clk pulses, pre-IE.
            evt_done_p <= (others => '0');
            evt_err_p  <= '0';

            -- (b) DMA0CRC seed commit (RTC write-commit; crc_acc single owner)
            if crc_wr_pulse = '1' then
                crc_acc <= crc_seed_reg;
            end if;

            -- (c) paced event -> pace_go set; abort request latch (per channel)
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

            -- (d) GO arm / reject-at-GO (D8/D13/A18): sample the programmed
            -- stores on the go edge (quasi-static, data-before-flag).
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
                        evt_err_p    <= '1';               -- EVFAB EV12 set site
                    elsif busy(ch) = '0' then
                        -- Fable R2 fix: exact clk-domain re-launch suppression.
                        -- The ClkMem-side busy_sync qualifier has a 2-gated-edge
                        -- blind window; a GO landing inside it must NOT reload
                        -- the working registers of an in-flight channel.
                        busy(ch)      <= '1';
                        src_work(ch)  <= src_reg(ch)(16 downto 0);
                        dst_work(ch)  <= dst_reg(ch)(16 downto 0);
                        len_work(ch)  <= len_reg(ch);
                        cfg_work(ch)  <= cfg_reg(ch);
                        -- Fable R1 fix: a data-ready LEVEL already high at GO
                        -- produces no new rising edge — arm pace_go from the
                        -- CURRENT synced level so a pre-GO pending word/frame
                        -- is serviced immediately (edge-detect covers the rest).
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

            -- (e) master-port FSM (verbatim handshake, A1 cycle accounting)
            case dstate is

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
                        -- deny-guard (D12/A5): mutex window OR router CLAIM word
                        deny := (src_work(selv)(16 downto 8) = "001100000")
                                or (sword = "001111000000000");
                        if deny then
                            err_flag(selv) <= '1';
                            evt_err_p      <= '1';        -- EVFAB EV12 set site
                            busy(selv)     <= '0';        -- abort channel (D12)
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

                when M_WR_REQ =>
                    if m_done = '1' then
                        dstate <= M_WR_CAP;
                    end if;

                when M_WR_CAP =>
                    m_req_r <= '0';                            -- acked flop drop
                    dstate  <= M_WR_GAP;

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
                            busy(cur_ch)      <= '0';         -- stop, no done (D15/A15)
                            abort_req(cur_ch) <= '0';
                            dstate <= M_IDLE;
                        else
                            lenzero := (newlen = X"00000000");
                            if lenzero then
                                done_flag(cur_ch)  <= '1';
                                busy(cur_ch)       <= '0';
                                evt_done_p(cur_ch) <= '1';  -- EVFAB EV10/11 set site
                            end if;
                            trg     := cfg_work(cur_ch)(5 downto 2);
                            needclr := (trg = "0010") or (trg = "0011" and lenzero);
                            if needclr then
                                m_req_r   <= '1';
                                m_we_r    <= "1111";
                                -- Fable R3 fix: the SR slot DIFFERS per source —
                                -- QSPI SLOT_SR = 5 (+0x14; slot 1 is CMD, whose
                                -- lane-0 write LAUNCHES a transaction!), NFC
                                -- SLOT_SR = 1 (+0x04). Verified against
                                -- QSPI.vhd:50-55 / NFC.vhd:90-97.
                                if trg = "0010" then
                                    m_addr_r <= src_work(cur_ch)(16 downto 8) & "000101";
                                else
                                    m_addr_r <= src_work(cur_ch)(16 downto 8) & "000001";
                                end if;
                                m_wdata_r <= X"00000004";     -- W1C SR bit 2 only (A11)
                                in_clr    <= '1';
                                dstate    <= M_CLR;
                            else
                                dstate <= M_IDLE;
                            end if;
                        end if;
                    end if;

                when M_CLR =>
                    if m_done = '1' then
                        dstate <= M_WR_CAP;                    -- reuse CAP/GAP (in_clr routes)
                    end if;

                when others =>
                    dstate <= M_IDLE;

            end case;
        end if;
    end process;

end behavioral;
