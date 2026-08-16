library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- OneWire: Dallas/Maxim 1-Wire master, one open-drain DQ pin, one combined IRQ, register base 0x6700.
-- Link-layer primitives off a programmable time base: reset plus presence, write-bit, read-bit, write-byte, read-byte; ROM search and CRC-8 stay in firmware.
-- Standard and overdrive speeds; strong-pullup is a register stub only, so DQ is released high and never driven high.
-- All protocol logic (time base, slot FSM, DQ synchronizer, sticky flags, IRQ combiner) rides the free-running clk; the register file rides the gated ClkMem.
-- Every hand-off between the two is a toggle or a quasi-static level, and EnMemPeriph is an active-low qualifying LEVEL, never a clock or an edge.

entity OneWire is
    port (
        clk         : in  std_logic;                     -- free-running fast reference, MCLK at integration; hosts the time base, slot FSM, DQ sync, flags and IRQ combiner
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_ow      : out std_logic;                     -- combined TC/error IRQ
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier, never a clock
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);
        OW_DQ_IN    : in  std_logic;                     -- DQ pad input, 2-FF synced in clk; PURE DATA, never a clock
        OW_DQ_OUT   : out std_logic;                     -- fixed '0' (open-drain)
        OW_DQ_DIR   : out std_logic                      -- '1' drives DQ low, '0' releases Hi-Z
    );
end OneWire;

architecture behavioral of OneWire is

    -- Word-slot map, slot n at 0x6700 + 4n, decoded off MABPart(7:2):
    --   0 OW0CR  : [0]OWEN [1]ODS [2]SPUEN (reserved stub) [3]TCIE [4]ERRIE, 31:5 reserved
    --   1 OW0CMD : [2:0]OP [8]BITVAL; a lane-0 write always captures and launches unless OWEN=0 or BUSY=1
    --   2 OW0TX  : [7:0] next write byte, the WRBYTE source; a write never launches
    --   3 OW0RX  : [7:0] last RDBYTE, [0] last RDBIT, side-effect-free read
    --   4 OW0DIV : [15:0] time-base divisor, one tick every OW0DIV+1 clk cycles
    --   5 OW0SR  : [0]BUSY ro [1]TCIF W1C [2]PRES ro [3]NOPRES W1C [4]SHORT W1C
    --   6 OW0SPU : reserved, reads 0 and ignores writes; slots >=7 read 0
    constant SLOT_CR  : natural := 0;
    constant SLOT_CMD : natural := 1;
    constant SLOT_TX  : natural := 2;
    constant SLOT_RX  : natural := 3;
    constant SLOT_DIV : natural := 4;
    constant SLOT_SR  : natural := 5;
    constant SLOT_SPU : natural := 6;

    -- OW0CMD OP encoding; any other code is reserved and does nothing.
    constant OP_RESET  : std_logic_vector(2 downto 0) := "000";
    constant OP_WRBIT  : std_logic_vector(2 downto 0) := "001";
    constant OP_RDBIT  : std_logic_vector(2 downto 0) := "010";
    constant OP_WRBYTE : std_logic_vector(2 downto 0) := "011";
    constant OP_RDBYTE : std_logic_vector(2 downto 0) := "100";

    -- Slot timing in 0.5 us ticks; nominal OW0DIV=11 at 24 MHz gives 12 clk cycles per tick.
    --   symbol  STD ticks (us)   OD ticks (us)
    --   tRSTL   960  (480us)     96  (48us)
    --   tPRES   140  (70us)      18  (9us)
    --   tRSTH   960  (480us)     96  (48us)
    --   tW1L    12   (6us)       2   (1us)
    --   tW0L    120  (60us)      16  (8us)
    --   tSLOT   140  (70us)      20  (10us)
    --   tRL     12   (6us)       2   (1us)
    --   tMSR    26   (13us)      3   (1.5us)  OD is 3, not 4: 4 ticks would sample exactly at the 2us tRDV edge
    --   tREC    4    (2us)       4   (2us)
    -- Reset slot = tRSTL low, release, presence sampled tPRES later, then tRSTH high; write/read slot = drive low, release to tSLOT, then tREC.
    -- SHORT is checked at end-of-recovery and wins: a bus still low there sets SHORT and suppresses NOPRES, which is unevaluable on a stuck bus.
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
    constant OW_OD_TMSR  : natural := 3;   -- deliberately not 4: see the table
    constant OW_OD_TREC  : natural := 4;

    -- Slot/protocol FSM states.
    type t_ow_state is (OW_IDLE, R_LOW, R_REL, R_SAMPLE, R_HIGH,
                         W_LOW, W_REL, W_REC,
                         RD_LOW, RD_REL, RD_SAMPLE, RD_FILL, RD_REC,
                         OW_DONE);
    signal ow_state : t_ow_state;

    -- Register-file storage (ClkMem domain).
    signal ow_cr        : std_logic_vector(4 downto 0);   -- OWEN/ODS/SPUEN/TCIE/ERRIE
    signal ow_cmd_op    : std_logic_vector(2 downto 0);   -- CMD readback: last-written OP
    signal ow_cmd_bitval: std_logic;                      -- CMD readback: last-written BITVAL
    signal ow_tx        : std_logic_vector(7 downto 0);   -- OW0TX
    signal ow_div       : std_logic_vector(15 downto 0);  -- OW0DIV
    signal desc_op      : std_logic_vector(2 downto 0);   -- launch descriptor: OP
    signal desc_bitval  : std_logic;                      -- launch descriptor: BITVAL
    signal desc_ods     : std_logic;                      -- launch descriptor: ODS
    signal desc_tx      : std_logic_vector(7 downto 0);   -- launch descriptor: TX byte
    signal launch_tgl   : std_logic;                      -- launch request toggle
    signal clr_tcif_tgl  : std_logic;                     -- W1C TCIF request toggle
    signal clr_nopres_tgl: std_logic;                     -- W1C NOPRES request toggle
    signal clr_short_tgl : std_logic;                     -- W1C SHORT request toggle
    signal ow_slot       : natural range 0 to 63;         -- decoded word slot

    -- busy_sync: the one crossing with a real 2-FF (clk into ClkMem).
    signal busy_c1, busy_c2 : std_logic;
    signal busy_sync        : std_logic;

    -- clk-domain CDC: toggle syncs plus edge detect.
    signal lnch_c1, lnch_c2, lnch_prev             : std_logic;
    signal clrtcif_c1, clrtcif_c2, clrtcif_prev     : std_logic;
    signal clrnopres_c1, clrnopres_c2, clrnopres_prev : std_logic;
    signal clrshort_c1, clrshort_c2, clrshort_prev  : std_logic;
    signal dq_s1, dq_s2 : std_logic;                      -- DQ 2-FF sync
    signal dq_sync      : std_logic;
    signal launch_pulse, clr_tcif_pulse, clr_nopres_pulse, clr_short_pulse : std_logic;
    signal launch_pending : std_logic;                    -- covers the SR.BUSY assert window

    -- Time base (clk domain).
    signal div_cnt : std_logic_vector(15 downto 0);
    signal tick    : std_logic;

    -- FSM datapath (clk domain).
    signal phase_cnt : natural range 0 to 4095;   -- headroom over the longest phase, 960 ticks
    signal bit_idx    : natural range 0 to 7;
    signal bit_total  : natural range 0 to 8;
    signal latched_op     : std_logic_vector(2 downto 0);
    signal latched_bitval : std_logic;
    signal latched_ods    : std_logic;
    signal latched_tx     : std_logic_vector(7 downto 0);
    signal rx_shift       : std_logic_vector(7 downto 0);
    signal wr_bit_val      : std_logic;   -- bit being written THIS iteration (comb)
    signal dq_drive_low    : std_logic;   -- registered FSM pad-drive output
    signal busy             : std_logic;
    signal tcif_flag, pres_flag, nopres_flag, short_flag : std_logic;
    signal nopres_pending   : std_logic;  -- RESET-only tentative NOPRES, overridden by SHORT

begin

    -- Slot decode, qualified by the EnMemPeriph level only.
    ow_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- Bit written this iteration: WRBIT uses latched_bitval, WRBYTE shifts latched_tx out LSB-first via bit_idx.
    wr_bit_val <= latched_bitval when latched_op = OP_WRBIT else latched_tx(bit_idx);

    -- Status and enable, combinational and never latched; TCIE/ERRIE are quasi-static CR bits read directly.
    irq_ow <= (tcif_flag and ow_cr(3)) or ((nopres_flag or short_flag) and ow_cr(4));

    -- Open-drain pad drive: DQ is pulled low or released, never driven high.
    OW_DQ_OUT <= '0';
    OW_DQ_DIR <= dq_drive_low;

    -- Register write: rising ClkMem, EnMemPeriph='0', lane 0 (WEn(0)='0') only.
    -- OW0CMD always captures the descriptor but only flips launch_tgl when OWEN=1 and busy_sync=0; SR writes of 1 flip the W1C clear toggles.
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
                            -- Content is always captured, launch or no launch.
                            desc_op       <= wdata(2 downto 0);
                            desc_bitval   <= wdata(8);
                            desc_ods      <= ow_cr(1);   -- current ODS at write time
                            desc_tx       <= ow_tx;      -- current TX byte at write time
                            ow_cmd_op     <= wdata(2 downto 0);
                            ow_cmd_bitval <= wdata(8);
                            -- Launch suppressed on OWEN=0 or BUSY=1.
                            if ow_cr(0) = '1' and busy_sync = '0' then
                                launch_tgl <= not launch_tgl;
                            end if;
                        end if;
                    when SLOT_TX =>
                        if WEn(0) = '0' then
                            ow_tx <= wdata(7 downto 0);   -- a TX write never launches
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

    -- Registered read mux on rising ClkMem; status bits are clk-domain quasi-static levels sampled directly, with no pre-latch or bridge.
    -- SR.BUSY must read the RAW clk-domain busy level, not busy_sync: the gated ClkMem supplies the very edges that shift busy in, so a busy_sync read right after a launch returns a stale 0.
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
                    rdata_out <= (others => '0');   -- SPU slot 6 and slots >=7 read 0
            end case;
        end if;
    end process;

    -- BUSY 2-FF sync into ClkMem; used only to qualify launches.
    busy_sync_proc: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            busy_c1 <= '0'; busy_c2 <= '0';
        elsif rising_edge(ClkMem) then
            busy_c1 <= busy; busy_c2 <= busy_c1;
        end if;
    end process;
    busy_sync <= busy_c2;

    -- 2-FF plus edge detect turns launch_tgl into launch_pulse and each clr_*_tgl into a one-cycle clear pulse; OW_DQ_IN is 2-FF synced into dq_sync as pure data.
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
    -- Launch-side pending: the raw launch toggle against its deepest synced stage, high from the CMD write until the FSM consumes the launch.
    -- It closes the SR.BUSY assert window, so firmware may poll for BUSY-clear immediately after writing OW0CMD.
    launch_pending   <= '1' when (launch_tgl /= lnch_prev) else '0';
    clr_tcif_pulse   <= '1' when (clrtcif_c2 /= clrtcif_prev) else '0';
    clr_nopres_pulse <= '1' when (clrnopres_c2 /= clrnopres_prev) else '0';
    clr_short_pulse  <= '1' when (clrshort_c2 /= clrshort_prev) else '0';
    dq_sync <= dq_s2;

    -- Time base: a free-running reload down-counter giving a one-cycle tick every OW0DIV+1 clk cycles.
    -- Counter-compare only, no clock gate and no generated clock; ow_div is read directly as a quasi-static level.
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

    -- Slot/protocol FSM: a tick-counted sequencer selecting the timing table by latched_ods.
    -- SAMPLE, DONE and IDLE dispatch are single-cycle; every timed phase advances only on a tick pulse.
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

            -- Target tick count for the current state, selected by latched_ods and, in the write phases, by the bit being written.
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

            -- W1C clears run first so a coincident set below overrides them: the later sequential assignment wins.
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
                                null;   -- reserved OP: no bus activity, no BUSY, no TCIF
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
                            -- End-of-recovery SHORT check; SHORT wins and suppresses NOPRES.
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
                    rx_shift(bit_idx) <= dq_sync;   -- LSB-first assembly
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
