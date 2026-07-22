library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ===========================================================================
-- I2CTarget: hardware-autonomous I2C TARGET (slave) -- 7-bit address match +
-- mask wildcard + general call, byte-at-a-time RX/TX with ready/empty status,
-- clock stretching for lossless flow control, START/STOP/repeated-START/NACK
-- framing flags, and a stuck-SCL watchdog. Two open-drain pins (SDA/SCL,
-- DIR-only -- OUT tied '0' at MCU, no REN). Two combined IRQs: 122 = I2CT0_AE
-- (address/error), 123 = I2CT0_DATA (tx-ready/rx-full). One instance I2CT0.
-- Base 0x6A00. Shares the SDA0/SCL0 pad planes with I2C0 via a wired-AND DIR
-- merge (host-side loopback self-test).
-- FROZEN design: ~/vesta_docs/digperiphs/i2ct_design.md (decisions D1-D20,
-- Fable adjudication 2026-07-22 -- ALL BINDING). Structural template = the
-- 1-Wire master (OneWire.vhd): a fully mclk-synchronous, D4-clean engine --
-- 2-FF pad sync, edge detection by registered prev-sample compare, NO
-- falling_edge of anything, NO flop clocked by a bus pin. Semantic precedent =
-- I2C.vhd's slave engine (match+mask, general-call, stretch, direction/NACK/
-- overrun flags) -- its SCL-pad-clocked implementation is the BANNED
-- anti-pattern and is copied for NOTHING here. Peripheral of the digital-
-- peripherals program.
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary reduce,
-- no reading of out ports). Every process infers exactly ONE edge of ONE
-- clock; every synchronizer is single-edge (Genus VHDL-601 discipline). NO
-- falling_edge of anything, anywhere (specifically NOT of EnMemPeriph). NO
-- process sensitive to SDA_IN/SCL_IN -- they are PURE DATA through the 2-FF
-- syncs (the deliberate contrast with I2C.vhd's rising/falling_edge(SCL_IN)).
--
-- D1/D2 -- ONE clock family: the whole target FSM is mclk-synchronous. The
-- 2-FF SDA/SCL synchronizers, the edge detectors, START/STOP/repeated-START
-- detection, the bit shift registers, the address matcher, the RX/TX byte
-- engines, the clock-stretch driver, the sticky W1C flags, BUSY/TM, the
-- watchdog, and the IRQ combiners ALL ride the free-running `clk` (MCLK at
-- integration). The register file rides the gated `ClkMem` (the same mclk net
-- at integration -- not an independent domain). Every ClkMem<->clk hand-off is
-- a TOGGLE or a HELD/quasi-static LEVEL (kept standalone-honest per the RTC/OW
-- precedent). Edge detection = registered prev-sample compare on the
-- SYNCHRONIZED signals. NO second clock domain, NO async FIFO.
--
-- D4 -- all bus-facing capture is synchronous to ClkMem RISING edge,
-- EnMemPeriph-qualified as an active-low LEVEL only (address decode + write-
-- enable + read-mux gate) -- never a clock, never an edge, no
-- falling_edge(EnMemPeriph) pre-latch. The read mux REGISTERS on rising ClkMem
-- over data already coincident with the bus domain (D17) -- no combinational
-- read, no MCU-side bridge. Status -> IRQ is (flag AND enable) combinational,
-- never latched (D16). W1C status flags, RSVD reads 0, slots >=5 read 0.
--
-- CDC CROSSING INVENTORY (toggle / held-level only, no async FIFO):
--   1. TX LAUNCH  ClkMem->clk (D10): a lane-0 I2CTTX write captures the byte
--      into tx_byte and flips tx_load_tgl. clk 2-FFs tx_load_tgl, edge-detects
--      it, and on the edge co-samples the (quasi-static) tx_byte into tx_hold
--      + sets tx_loaded -- data-before-flag, no async FIFO (OW D8 idiom).
--   2. TXE COVER  ClkMem read (D10-cover, OneWire A6 class): tx_load_pending =
--      (tx_load_tgl /= deepest clk-synced stage), high from the I2CTTX write
--      until the FSM consumes the launch. SR-read TXE = TXE_clk AND NOT
--      tx_load_pending, so a poll right after an I2CTTX write never reads
--      stale-empty.
--   3. W1C  ClkMem->clk (D17): a lane-0 SR write of 1 to a W1C bit flips
--      clr_<flag>_tgl. clk 2-FFs + edge-detects each into a one-cycle clear
--      pulse, applied in the SAME process that owns the flag; SET WINS over a
--      coincident CLEAR (default-clear then case-set order -- RTC D10 / OW D12).
--   4. STATUS  clk->ClkMem (D17): all sticky flags + BUSY/TM/TXE are clk-domain
--      levels sampled DIRECTLY by the ClkMem read mux (coincident nets at
--      integration -- the RTC/OW busy-raw-read fix). The ClkMem registration IS
--      the synchronization. No pre-latch, no bridge (D4).
--   5. SDA/SCL  pad->clk (D6): SDA_IN/SCL_IN each 2-FF synchronized (two
--      independent chains) then prev-registered for edge detect. PURE DATA,
--      never a clock. Framing events qualified on SCL confirmed-high >=2
--      samples (the ~1-clk skew hazard guard).
--   6. CR fields  ClkMem->clk (D7): EN/GCEN/CSEN/SAD/SADM/WDTO are quasi-static
--      rw levels read DIRECTLY by the clk FSM/matcher/watchdog (coincident nets
--      at integration; the match is combinational, D7).
--   7. RESET (D18): resetn (chip async, active-low) applied DIRECTLY to both the
--      clk and ClkMem processes -- no reset synchronizer (clk and ClkMem are
--      the same mclk family, D1/D2; OneWire D14).
--   8. IRQ (D16): irq_ae = (AMF|GCF|OVF|NACKF|STOPF|RSTARTF|ERRF) and AEIE;
--      irq_data = (RXF|TXE) and DATAIE -- combinational, never latched.
--
-- Register map (D5; base 0x6A00, slot n @ 0x6A00 + 4n, decoded off
-- MABPart(7:2); slots >=5 read 0):
--   0 I2CTCR  : [0]EN [1]GCEN [2]CSEN [3]AEIE [4]DATAIE, [14:8]SAD[6:0],
--               [22:16]SADM[6:0]; rest reserved read 0.
--   1 I2CTSR  : [0]BUSY r [1]TM r [2]AMF W1C [3]GCF W1C [4]RXF W1C [5]TXE r
--               [6]OVF W1C [7]NACKF W1C [8]STOPF W1C [9]RSTARTF W1C
--               [10]ERRF W1C; 31:11 reserved read 0.
--   2 I2CTTX  : [7:0] next transmit byte; a lane-0 write loads the buffer
--               (sets tx_loaded, clears TXE, D10). Reads back last value.
--   3 I2CTRX  : [7:0] last received byte, side-effect-free read (D9).
--   4 I2CTWDG : [15:0] WDTO -- SCL-low watchdog timeout in units of 256 clk;
--               0 = disabled (D13, reset value -> default-off, identity-safe).
--
-- FSM (single FSM + a bit counter + a 2-bit ACK sub-phase):
--   T_IDLE     -> on START (D6): BUSY<=1, T_ADDR.
--   T_ADDR     -- shift 8 bits MSB-first; on bit 8, match (D7) -> T_ACK_ADDR
--                 (ACK) or T_IGNORE (silent, no ACK).
--   T_ACK_ADDR -- drive address ACK; trailing fall branch on TM: T_RX_DATA
--                 (host write) or T_TX_LOAD (host read).
--   T_RX_DATA  -- shift 8 bits; on bit 8, accept/NACK (D9) -> T_ACK_RX.
--   T_ACK_RX   -- drive RX ACK/NACK; deliver byte; trailing fall RX-stretch if
--                 CSEN & RXF, else T_RX_DATA (next byte).
--   T_TX_LOAD  -- if tx_loaded -> T_TX_DATA; else raise TXE, TX-stretch if
--                 CSEN, else send 0xFF (D10).
--   T_TX_DATA  -- shift out 8 bits MSB-first; -> T_TX_ACK.
--   T_TX_ACK   -- sample host ACK/NACK: NACK -> NACKF, wait STOP/Sr; ACK ->
--                 TXE / T_TX_LOAD.
--   T_IGNORE   -- address mismatch (or post-NACK read done): release, wait
--                 STOP / repeated-START.
--   Global (any state): STOP -> STOPF, BUSY<=0, release, T_IDLE; repeated-START
--   -> RSTARTF, release, T_ADDR (BUSY holds); watchdog expiry -> ERRF, BUSY<=0,
--   release, T_IDLE. EN=0 forces the FSM idle with SDA/SCL released,
--   flags/RX preserved.
-- ===========================================================================

entity I2CTarget is
    port (
        clk         : in  std_logic;                     -- free-running MCLK at integration (D2).
                                                         -- Hosts the whole target FSM, the SDA/SCL
                                                         -- 2-FF synchronizers, the sticky W1C flags,
                                                         -- BUSY/TM, the watchdog, and the IRQ combiners.
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_ae      : out std_logic;                     -- address/error IRQ, vector 122 (status AND enable)
        irq_data    : out std_logic;                     -- tx-ready/rx-full IRQ, vector 123 (status AND enable)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (D4: NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read (no bridge, D4)
        SDA_IN      : in  std_logic;                     -- SDA pad input; 2-FF synced in clk (D6). PURE DATA.
        SDA_DIR     : out std_logic;                     -- '1' drives SDA low (ACK / '0' data bit);
                                                         -- '0' releases Hi-Z. NEVER driven high (D8).
        SCL_IN      : in  std_logic;                     -- SCL pad input; 2-FF synced in clk (D6). PURE DATA.
        SCL_DIR     : out std_logic                      -- '1' holds SCL low (clock stretch, D11); '0' releases
    );
end I2CTarget;

architecture behavioral of I2CTarget is

    -- ---- word-slot map (frozen, D5) --------------------------------------
    constant SLOT_CR  : natural := 0;   -- I2CTCR
    constant SLOT_SR  : natural := 1;   -- I2CTSR
    constant SLOT_TX  : natural := 2;   -- I2CTTX
    constant SLOT_RX  : natural := 3;   -- I2CTRX
    constant SLOT_WDG : natural := 4;   -- I2CTWDG

    -- ---- B3 FSM states (D3/B3) -------------------------------------------
    type t_i2ct_state is (T_IDLE, T_ADDR, T_ACK_ADDR, T_RX_DATA, T_ACK_RX,
                          T_TX_LOAD, T_TX_DATA, T_TX_ACK, T_IGNORE);
    signal state : t_i2ct_state;

    -- ---- B1 register-file storage (ClkMem domain, D4/D5) -----------------
    signal cr_en     : std_logic;                        -- I2CTCR[0]
    signal cr_gcen   : std_logic;                        -- I2CTCR[1]
    signal cr_csen   : std_logic;                        -- I2CTCR[2]
    signal cr_aeie   : std_logic;                        -- I2CTCR[3]
    signal cr_dataie : std_logic;                        -- I2CTCR[4]
    signal cr_sad    : std_logic_vector(6 downto 0);     -- I2CTCR[14:8]
    signal cr_sadm   : std_logic_vector(6 downto 0);     -- I2CTCR[22:16]
    signal tx_byte   : std_logic_vector(7 downto 0);     -- I2CTTX readback + descriptor
    signal tx_load_tgl : std_logic;                      -- D10 TX launch toggle
    signal wdg       : std_logic_vector(15 downto 0);    -- I2CTWDG WDTO
    signal i2ct_slot : natural range 0 to 63;            -- decoded word slot
    -- W1C request toggles (ClkMem side, D17): one per W1C flag
    signal clr_amf_tgl     : std_logic;
    signal clr_gcf_tgl     : std_logic;
    signal clr_rxf_tgl     : std_logic;
    signal clr_ovf_tgl     : std_logic;
    signal clr_nackf_tgl   : std_logic;
    signal clr_stopf_tgl   : std_logic;
    signal clr_rstartf_tgl : std_logic;
    signal clr_errf_tgl    : std_logic;

    -- ---- B2 clk-domain sync / CDC (D6/D10/D17) ---------------------------
    signal sda_s1, sda_s2, sda_prev : std_logic;         -- D6 SDA 2-FF sync + prev
    signal scl_s1, scl_s2, scl_prev : std_logic;         -- D6 SCL 2-FF sync + prev
    signal sda_sync, scl_sync       : std_logic;         -- synchronized levels (= s2)
    signal scl_rise, scl_fall       : std_logic;         -- D6 SCL edges (comb)
    signal sda_rise, sda_fall       : std_logic;         -- D6 SDA edges (comb)
    signal start_evt, stop_evt      : std_logic;         -- D6 framing events (comb)
    signal txl_c1, txl_c2, txl_prev : std_logic;         -- D10 tx_load_tgl sync + edge
    signal tx_load_pulse            : std_logic;         -- D10 one-clk launch pulse (comb)
    signal tx_load_pending          : std_logic;         -- D10-cover: ClkMem-read TXE mask (comb)
    -- W1C toggle syncs (ClkMem->clk, 2-FF + prev, D17)
    signal camf_c1, camf_c2, camf_p         : std_logic;
    signal cgcf_c1, cgcf_c2, cgcf_p         : std_logic;
    signal crxf_c1, crxf_c2, crxf_p         : std_logic;
    signal covf_c1, covf_c2, covf_p         : std_logic;
    signal cnackf_c1, cnackf_c2, cnackf_p   : std_logic;
    signal cstopf_c1, cstopf_c2, cstopf_p   : std_logic;
    signal crstf_c1, crstf_c2, crstf_p      : std_logic;
    signal cerrf_c1, cerrf_c2, cerrf_p      : std_logic;
    -- per-flag one-clk clear pulses (comb)
    signal camf_pulse, cgcf_pulse, crxf_pulse, covf_pulse       : std_logic;
    signal cnackf_pulse, cstopf_pulse, crstf_pulse, cerrf_pulse : std_logic;

    -- ---- B3 FSM datapath (clk domain) ------------------------------------
    signal bit_cnt   : natural range 0 to 8;             -- bits shifted / presented
    signal ack_phase : natural range 0 to 3;             -- ACK-slot / stretch sub-phase
    signal shift     : std_logic_vector(7 downto 0);     -- MSB-first RX / address shift
    signal rx_data   : std_logic_vector(7 downto 0);     -- last received byte (I2CTRX)
    signal rx_accept : std_logic;                        -- ACK(1)/NACK(0) decision for T_ACK_RX
    signal tx_shift  : std_logic_vector(7 downto 0);     -- MSB-first TX shift
    signal tx_hold   : std_logic_vector(7 downto 0);     -- launch-captured TX byte (D10)
    signal tx_loaded : std_logic;                        -- clk-domain: a byte is staged (D10)
    signal tx_host_nack : std_logic;                     -- sampled host ACK/NACK in T_TX_ACK
    signal sda_drv   : std_logic;                        -- registered SDA drive-low enable (D8)
    signal scl_hold  : std_logic;                        -- registered SCL stretch enable (D11)
    signal busy      : std_logic;                        -- D12 bus busy (START..STOP)
    signal tm        : std_logic;                        -- D12 latched RnW (1 = target-transmitter)
    signal amf, gcf, rxf, ovf, nackf : std_logic;        -- D7/D9/D10 sticky W1C flags
    signal stopf, rstartf, errf      : std_logic;        -- D12/D13 sticky W1C flags
    signal tx_e_level : std_logic;                       -- D10 raw TXE (transmit-needs-data & !loaded)
    signal wdg_pre : std_logic_vector(7 downto 0);       -- D13 8-bit 256-clk prescale
    signal wdg_cnt : std_logic_vector(15 downto 0);      -- D13 16-bit SCL-low compare counter

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode (EnMemPeriph-qualified LEVEL, D4; never an edge).
    i2ct_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- pad drive (D8/D11/D19): open-drain, DIR-only; NEVER driven high. The MCU
    -- ties SDA0/SCL0 OUT to '0' and wired-AND-merges these DIR planes with I2C0.
    SDA_DIR <= sda_drv;
    SCL_DIR <= scl_hold;

    -- synchronized bus levels + edges (D6). PURE DATA, never a clock. Two
    -- independent 2-FF chains, so at a real SCL edge the sampled SDA/SCL phases
    -- can differ by 1 clk -- the framing qualifier below guards that hazard.
    sda_sync <= sda_s2;
    scl_sync <= scl_s2;
    scl_rise <= scl_sync and not scl_prev;
    scl_fall <= (not scl_sync) and scl_prev;
    sda_rise <= sda_sync and not sda_prev;
    sda_fall <= (not sda_sync) and sda_prev;
    -- START = SDA falls while SCL stably high (>=2 samples); STOP = SDA rises
    -- while SCL stably high (D6 hazard guard: a normal data transition moves SDA
    -- while SCL is LOW and can never masquerade as a framing event).
    start_evt <= '1' when (sda_fall = '1' and scl_sync = '1' and scl_prev = '1') else '0';
    stop_evt  <= '1' when (sda_rise = '1' and scl_sync = '1' and scl_prev = '1') else '0';

    -- D10 TX launch pulse: edge of the 2-FF-synced tx_load_tgl.
    tx_load_pulse <= '1' when (txl_c2 /= txl_prev) else '0';
    -- D10-cover (OneWire A6 class): RAW ClkMem-domain tx_load_tgl vs its deepest
    -- clk-synced stage (txl_prev). High from the I2CTTX write until the FSM
    -- consumes the launch, so a poll of TXE right after an I2CTTX write never
    -- reads stale-empty. Read by the ClkMem SR mux only.
    tx_load_pending <= '1' when (tx_load_tgl /= txl_prev) else '0';

    -- W1C one-clk clear pulses (edge of each 2-FF-synced clr toggle, D17).
    camf_pulse   <= '1' when (camf_c2   /= camf_p)   else '0';
    cgcf_pulse   <= '1' when (cgcf_c2   /= cgcf_p)   else '0';
    crxf_pulse   <= '1' when (crxf_c2   /= crxf_p)   else '0';
    covf_pulse   <= '1' when (covf_c2   /= covf_p)   else '0';
    cnackf_pulse <= '1' when (cnackf_c2 /= cnackf_p) else '0';
    cstopf_pulse <= '1' when (cstopf_c2 /= cstopf_p) else '0';
    crstf_pulse  <= '1' when (crstf_c2  /= crstf_p)  else '0';
    cerrf_pulse  <= '1' when (cerrf_c2  /= cerrf_p)  else '0';

    -- D10 raw TXE: high only in the transmit-needs-data phase with no byte
    -- staged. Read raw by the SR mux (with the D10-cover mask) and feeds
    -- irq_data. Pure clk-domain (state + tx_loaded).
    tx_e_level <= '1' when (state = T_TX_LOAD and tx_loaded = '0') else '0';

    -- D16 combined IRQs = (status and enable), combinational, never latched.
    -- AEIE/DATAIE are quasi-static ClkMem CR bits, read directly.
    irq_ae   <= (amf or gcf or ovf or nackf or stopf or rstartf or errf) and cr_aeie;
    irq_data <= (rxf or tx_e_level) and cr_dataie;

    -- ------------------------- B1: register write (ClkMem) --------------------
    -- Rising ClkMem, EnMemPeriph='0' qualified, lane-0 (WEn(0)='0') writes (D4).
    -- I2CTCR loads all fields on a lane-0 word write (the RTC/OW CR idiom; the
    -- bench packs CR as a full word). I2CTTX captures the byte AND flips
    -- tx_load_tgl (the TX launch, D10). SR lane-0 writes of 1 to a W1C bit flip
    -- the matching clr_<flag>_tgl (W1C-CDC, D17). Reset via resetn (bus domain).
    reg_write: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            cr_en     <= '0';
            cr_gcen   <= '0';
            cr_csen   <= '0';
            cr_aeie   <= '0';
            cr_dataie <= '0';
            cr_sad    <= (others => '0');
            cr_sadm   <= (others => '0');
            tx_byte   <= (others => '0');
            tx_load_tgl <= '0';
            wdg       <= (others => '0');
            clr_amf_tgl     <= '0';
            clr_gcf_tgl     <= '0';
            clr_rxf_tgl     <= '0';
            clr_ovf_tgl     <= '0';
            clr_nackf_tgl   <= '0';
            clr_stopf_tgl   <= '0';
            clr_rstartf_tgl <= '0';
            clr_errf_tgl    <= '0';
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case i2ct_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            cr_en     <= wdata(0);
                            cr_gcen   <= wdata(1);
                            cr_csen   <= wdata(2);
                            cr_aeie   <= wdata(3);
                            cr_dataie <= wdata(4);
                            cr_sad    <= wdata(14 downto 8);
                            cr_sadm   <= wdata(22 downto 16);
                        end if;
                    when SLOT_SR =>
                        -- W1C: writing 1 flips the clear toggle; BUSY(0)/TM(1)/
                        -- TXE(5) are read-only, ignored.
                        if WEn(0) = '0' then
                            if wdata(2)  = '1' then clr_amf_tgl     <= not clr_amf_tgl;     end if;
                            if wdata(3)  = '1' then clr_gcf_tgl     <= not clr_gcf_tgl;     end if;
                            if wdata(4)  = '1' then clr_rxf_tgl     <= not clr_rxf_tgl;     end if;
                            if wdata(6)  = '1' then clr_ovf_tgl     <= not clr_ovf_tgl;     end if;
                            if wdata(7)  = '1' then clr_nackf_tgl   <= not clr_nackf_tgl;   end if;
                            if wdata(8)  = '1' then clr_stopf_tgl   <= not clr_stopf_tgl;   end if;
                            if wdata(9)  = '1' then clr_rstartf_tgl <= not clr_rstartf_tgl; end if;
                            if wdata(10) = '1' then clr_errf_tgl    <= not clr_errf_tgl;    end if;
                        end if;
                    when SLOT_TX =>
                        -- I2CTTX write loads the buffer + LAUNCHES (D10): capture
                        -- the byte and flip tx_load_tgl (data-before-flag).
                        if WEn(0) = '0' then
                            tx_byte     <= wdata(7 downto 0);
                            tx_load_tgl <= not tx_load_tgl;
                        end if;
                    when SLOT_WDG =>
                        if WEn(0) = '0' then
                            wdg <= wdata(15 downto 0);
                        end if;
                    when others =>
                        null;   -- I2CTRX (slot 3) read-only; slots >=5 no effect
                end case;
            end if;
        end if;
    end process;

    -- ------------------------- B1: register read (ClkMem) ---------------------
    -- Registered read mux on rising ClkMem. The sticky flags + BUSY/TM/TXE are
    -- read RAW from the clk domain (coincident nets at integration -- the OW/RTC
    -- busy-raw-read discipline; the ClkMem registration IS the synchronization,
    -- D17). SR-read TXE applies the D10-cover (mask by tx_load_pending) so a poll
    -- immediately after an I2CTTX write never sees stale-empty. No pre-latch, no
    -- bridge (D4). Reserved bits read 0, slots >=5 read 0.
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case i2ct_slot is
                when SLOT_CR =>
                    rdata_out <= (31 downto 23 => '0') & cr_sadm & '0' & cr_sad &
                                 "000" & cr_dataie & cr_aeie & cr_csen & cr_gcen & cr_en;
                when SLOT_SR =>
                    rdata_out <= (31 downto 11 => '0') & errf & rstartf & stopf & nackf & ovf &
                                 (tx_e_level and not tx_load_pending) & rxf & gcf & amf & tm & busy;
                when SLOT_TX =>
                    rdata_out <= (31 downto 8 => '0') & tx_byte;
                when SLOT_RX =>
                    rdata_out <= (31 downto 8 => '0') & rx_data;
                when SLOT_WDG =>
                    rdata_out <= (31 downto 16 => '0') & wdg;
                when others =>
                    rdata_out <= (others => '0');   -- slots >=5 read 0
            end case;
        end if;
    end process;

    -- ------------------------- B2: clk-domain sync / CDC (D6/D10/D17) ----------
    -- Two independent SDA/SCL 2-FF synchronizers + one-clk prev copies for edge
    -- detect; 2-FF + prev of the tx_load_tgl launch toggle and of every W1C
    -- clr_<flag>_tgl. Single edge (rising clk) only. Reset via resetn. SDA/SCL
    -- are PURE DATA here -- never a clock (the deliberate contrast with I2C.vhd).
    bus_sync: process(resetn, clk)
    begin
        if resetn = '0' then
            sda_s1 <= '1'; sda_s2 <= '1'; sda_prev <= '1';   -- idle-high open-drain bus
            scl_s1 <= '1'; scl_s2 <= '1'; scl_prev <= '1';
            txl_c1 <= '0'; txl_c2 <= '0'; txl_prev <= '0';
            camf_c1 <= '0'; camf_c2 <= '0'; camf_p <= '0';
            cgcf_c1 <= '0'; cgcf_c2 <= '0'; cgcf_p <= '0';
            crxf_c1 <= '0'; crxf_c2 <= '0'; crxf_p <= '0';
            covf_c1 <= '0'; covf_c2 <= '0'; covf_p <= '0';
            cnackf_c1 <= '0'; cnackf_c2 <= '0'; cnackf_p <= '0';
            cstopf_c1 <= '0'; cstopf_c2 <= '0'; cstopf_p <= '0';
            crstf_c1 <= '0'; crstf_c2 <= '0'; crstf_p <= '0';
            cerrf_c1 <= '0'; cerrf_c2 <= '0'; cerrf_p <= '0';
        elsif rising_edge(clk) then
            -- D6 pad synchronizers + prev (edge detect off the SYNCHRONIZED nets)
            sda_s1 <= SDA_IN; sda_s2 <= sda_s1; sda_prev <= sda_s2;
            scl_s1 <= SCL_IN; scl_s2 <= scl_s1; scl_prev <= scl_s2;
            -- D10 TX launch toggle 2-FF + prev
            txl_c1 <= tx_load_tgl; txl_c2 <= txl_c1; txl_prev <= txl_c2;
            -- D17 W1C toggles 2-FF + prev
            camf_c1   <= clr_amf_tgl;     camf_c2   <= camf_c1;   camf_p   <= camf_c2;
            cgcf_c1   <= clr_gcf_tgl;     cgcf_c2   <= cgcf_c1;   cgcf_p   <= cgcf_c2;
            crxf_c1   <= clr_rxf_tgl;     crxf_c2   <= crxf_c1;   crxf_p   <= crxf_c2;
            covf_c1   <= clr_ovf_tgl;     covf_c2   <= covf_c1;   covf_p   <= covf_c2;
            cnackf_c1 <= clr_nackf_tgl;   cnackf_c2 <= cnackf_c1; cnackf_p <= cnackf_c2;
            cstopf_c1 <= clr_stopf_tgl;   cstopf_c2 <= cstopf_c1; cstopf_p <= cstopf_c2;
            crstf_c1  <= clr_rstartf_tgl; crstf_c2  <= crstf_c1;  crstf_p  <= crstf_c2;
            cerrf_c1  <= clr_errf_tgl;    cerrf_c2  <= cerrf_c1;  cerrf_p  <= cerrf_c2;
        end if;
    end process;

    -- ------------------------- B3: target FSM (clk, D7-D13) --------------------
    -- The whole autonomous target engine on the free-running clk: drives the
    -- REGISTERED sda_drv/scl_hold (never a combinational mux off a bus edge, D8),
    -- owns the sticky W1C flags, BUSY/TM, the shift registers, and the watchdog.
    -- The FSM only ever changes SDA AFTER scl_fall (SCL confirmed low through the
    -- sync, which lags the real edge) so it can never glitch a false START/STOP.
    -- Sample bits on scl_rise, drive on scl_fall. CR fields (EN/GCEN/CSEN/SAD/
    -- SADM) + WDTO are quasi-static ClkMem levels read directly (D1/D7).
    -- Set-wins ordering: the default W1C clears run FIRST, the FSM/framing SETs
    -- run LATER and override a coincident clear (RTC D10 / OW D12 discipline).
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
        elsif rising_edge(clk) then

            -- (1) W1C default clears (SET below wins over a coincident clear).
            if camf_pulse   = '1' then amf     <= '0'; end if;
            if cgcf_pulse   = '1' then gcf     <= '0'; end if;
            if crxf_pulse   = '1' then rxf     <= '0'; end if;
            if covf_pulse   = '1' then ovf     <= '0'; end if;
            if cnackf_pulse = '1' then nackf   <= '0'; end if;
            if cstopf_pulse = '1' then stopf   <= '0'; end if;
            if crstf_pulse  = '1' then rstartf <= '0'; end if;
            if cerrf_pulse  = '1' then errf    <= '0'; end if;

            -- (2) TX launch capture (D10): co-sample the quasi-static tx_byte
            -- into tx_hold on the launch edge and stage it. data-before-flag.
            if tx_load_pulse = '1' then
                tx_hold   <= tx_byte;
                tx_loaded <= '1';
            end if;

            if cr_en = '0' then
                -- EN=0 (D5/CR): FSM forced idle, SDA/SCL released; flags + RX
                -- preserved (W1C clears above still apply; a byte can still be
                -- W1C-cleared while disabled). tx_loaded/tm preserved.
                state     <= T_IDLE;
                busy      <= '0';
                sda_drv   <= '0';
                scl_hold   <= '0';
                ack_phase <= 0;
                wdg_pre   <= (others => '0');
                wdg_cnt   <= (others => '0');
            else

                -- (3) per-state FSM. Registered outputs HOLD between the edges
                -- that change them (no default assignment at the top -- a driven
                -- ACK must survive until its trailing fall).
                case state is

                    when T_IDLE =>
                        null;   -- wait for START (framing override below)

                    when T_ADDR =>
                        -- shift 8 bits MSB-first on scl_rise (I2C order, D4/D7)
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
                                    if gc then gcf <= '1'; end if;
                                    tm  <= rnw;   -- D12: latch direction
                                    state <= T_ACK_ADDR;
                                else
                                    -- no match: silent ignore, drive NO ACK (D7)
                                    sda_drv <= '0';
                                    scl_hold <= '0';
                                    state   <= T_IGNORE;
                                end if;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        end if;

                    when T_ACK_ADDR =>
                        -- drive the address ACK (D8): pull SDA low on the scl_fall
                        -- after bit 8; release + branch on the next scl_fall.
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
                        -- shift 8 bits MSB-first on scl_rise; accept/NACK on bit 8
                        if scl_rise = '1' then
                            full := shift(6 downto 0) & sda_sync;
                            shift <= full;
                            if bit_cnt = 7 then
                                bit_cnt   <= 0;
                                ack_phase <= 0;
                                if rxf = '0' then
                                    -- buffer free: ACK, latch, set RXF (D9)
                                    rx_data   <= full;
                                    rxf       <= '1';
                                    rx_accept <= '1';
                                else
                                    -- buffer full: auto-NACK-on-full, OVF (D9)
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
                        -- drive RX ACK/NACK (D8/D9); on the trailing fall, hold
                        -- the RX stretch (D11) if CSEN & byte still unread, else
                        -- proceed to the next byte.
                        if ack_phase = 2 then
                            -- RX stretch wait (D11): release SCL once RXF clears
                            -- (firmware read + W1C). Synchronous release is fine.
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
                        -- SCL-low wait state (not edge-gated, D10): present the
                        -- staged byte as soon as one is available; otherwise raise
                        -- TXE (tx_e_level) and, with CSEN, hold the TX stretch.
                        if tx_loaded = '1' then
                            sda_drv   <= not tx_hold(7);          -- present bit 7
                            tx_shift  <= tx_hold(6 downto 0) & '0';
                            tx_loaded <= '0';
                            scl_hold   <= '0';                     -- drop any stretch
                            bit_cnt   <= 1;                       -- bit 7 presented
                            state     <= T_TX_DATA;
                        else
                            if cr_csen = '1' then
                                scl_hold <= '1';                   -- TX stretch (D11)
                            else
                                -- no stretch: transmit 0xFF, SDA released (D10)
                                sda_drv  <= '0';
                                tx_shift <= "11111110";
                                bit_cnt  <= 1;
                                state    <= T_TX_DATA;
                            end if;
                        end if;

                    when T_TX_DATA =>
                        -- shift out the remaining bits MSB-first on scl_fall; the
                        -- host samples each on scl_rise. After 8 bits, release for
                        -- the host ACK/NACK slot.
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
                        -- sample the host ACK/NACK on the 9th scl_rise (D10); on
                        -- the trailing fall, continue (ACK) or wait STOP/Sr (NACK).
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
                        null;   -- address mismatch / read done: wait STOP or Sr

                    when others =>
                        state <= T_IDLE;

                end case;

                -- (4) framing overrides (D6/D12) -- run AFTER the case so a
                -- START/STOP/Sr at ANY bus phase wins. Any framing event releases
                -- SDA_DIR and drops the stretch so the target never holds the bus
                -- across a boundary. STOP and START are mutually exclusive (SDA
                -- cannot both rise and fall in one cycle).
                if stop_evt = '1' then
                    stopf     <= '1';
                    busy      <= '0';
                    sda_drv   <= '0';
                    scl_hold   <= '0';
                    ack_phase <= 0;
                    state     <= T_IDLE;   -- a STOP mid-byte discards the partial
                end if;
                if start_evt = '1' then
                    -- START while BUSY = repeated-START (re-address, BUSY holds);
                    -- START while idle = initial START (D6/D12).
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

                -- (5) watchdog (D13): count SCL-low duration while BUSY in units
                -- of 256 clk; reset when not BUSY or SCL not low; WDTO=0 disables.
                -- On expiry: ERRF, drop BUSY, release, T_IDLE (overrides the FSM).
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
