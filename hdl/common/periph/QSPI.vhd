-- VestaRV: quad-SPI controller
-- One transaction at a time, CS0 only; a write to CMD is the sole transaction trigger.
-- Transfer FSM is IDLE, CMD, ADDR, DUMMY, DATA, DONE, with zero-length phases skipped by construction.
-- The bus side is one work.periph_regs instance driven by qspi_regs_pkg's tables (hdl/common/regs/REGFILE.md); the two-chained-ClkGate baud divider and the serial core are what is left here.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
-- Word slots, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/qspi.rdl.
use work.qspi_regs_pkg.all;


entity QSPI is
    port (
        clk         : in  std_logic;   -- smclk-domain serial core clock
        resetn      : in  std_logic;
        irq_tc      : out std_logic;
        irq_rxf     : out std_logic;
        ClkMem      : in  std_logic;
        EnMemPeriph : in  std_logic;
        WEn         : in  std_logic_vector(3 downto 0);
        MABPart     : in  std_logic_vector(7 downto 2);
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);
        sck_out     : out std_logic;
        sck_dir     : out std_logic;
        cs_out      : out std_logic;   -- active-low chip select (CS0 only in MVP)
        cs_dir      : out std_logic;
        io_in       : in  std_logic_vector(3 downto 0);
        io_out      : out std_logic_vector(3 downto 0);
        io_dir      : out std_logic_vector(3 downto 0)
    );
end QSPI;

architecture behavioral of QSPI is

    -- DONE is a one clk_baud-edge tail state giving TCIF/RXFULL/QSPIxRX a clean simultaneous settle edge before BUSY drops.
    -- BUSY is state /= IDLE, so DONE still reads busy.
    type QState_t is (ST_IDLE, ST_CMD, ST_ADDR, ST_DUMMY, ST_DATA, ST_DONE);
    signal state : QState_t;

    -- Lane-width encoding: 00 = 1-bit, 01 = 2-bit, 10 = 4-bit, 11 reserved and treated as 1-bit.
    function width_bits(w : std_logic_vector(1 downto 0)) return natural is
    begin
        case w is
            when "01"   => return 2;
            when "10"   => return 4;
            when others => return 1; -- "00" and reserved "11"
        end case;
    end function;

    -- DLEN encoding: 00 = no data phase, 01 = 8-bit, 10 = 16-bit, 11 = 32-bit.
    function dlen_bits_f(d : std_logic_vector(1 downto 0)) return natural is
    begin
        case d is
            when "01"   => return 8;
            when "10"   => return 16;
            when "11"   => return 32;
            when others => return 0; -- "00" no data phase
        end case;
    end function;

    -- Next active phase after leaving from_st, skipping any zero-length phase by construction.
    -- Pure function over the LATCHED transaction fields, never the live CR, so a mid-transaction CR/CMD write cannot redirect an in-flight transaction.
    function next_phase(awid       : std_logic_vector(1 downto 0);
                         dummy_val : natural;
                         dlen      : std_logic_vector(1 downto 0);
                         from_st   : QState_t) return QState_t is
    begin
        if from_st = ST_CMD then
            if awid = "01" or awid = "10" then
                return ST_ADDR;
            end if;
        end if;
        if from_st = ST_CMD or from_st = ST_ADDR then
            if dummy_val > 0 then
                return ST_DUMMY;
            end if;
        end if;
        if dlen /= "00" then
            return ST_DATA;
        end if;
        return ST_DONE;
    end function;

    -- Register file. QSPIxCR, QSPIxCMD, QSPIxADR and QSPIxTX are periph_regs
    -- storage, read out of regs_q; QSPIxRX and QSPIxSR hold no flop there,
    -- because the serial core owns the data word and the flags.
    signal regs_q   : reg_arr_t;                        -- the stored words
    signal hw_rd_s  : reg_arr_t;                        -- read source for RX and SR
    signal w1c_s    : reg_arr_t;                        -- a 1 written to a QSPIxSR flag
    signal acc_s    : std_logic_vector(0 to NWORDS-1);  -- combinational: this slot is addressed now
    signal sr_rd    : std_logic_vector(31 downto 0);    -- assembled SR read word
    signal rx_rd    : std_logic_vector(31 downto 0);    -- assembled RX read word

    signal QSPIxRX  : std_logic_vector(31 downto 0);
    signal QSPIxSR  : std_logic_vector(3 downto 0);  -- [0]BUSY [1]TXEIF [2]RXFULL [3]TCIF

    -- Registered-read pre-latch: falling_edge(EnMemPeriph) latches the INVERTED value of every register with volatile bits, and the read process un-inverts it on the next rising_edge(ClkMem).
    -- Only SR and RX are volatile (BUSY/flags, and RX's serial-core-written data); CR/CMD/ADR/TX are plain software registers read straight out of the write-side register.
    signal QSPIxSR_ltch : std_logic_vector(3 downto 0);
    signal QSPIxRX_ltch : std_logic_vector(31 downto 0);

    -- QSPIxCR bit-field taps, live and combinational.
    signal q_en    : std_logic;
    signal q_cmdw  : std_logic_vector(1 downto 0);
    signal q_adrw  : std_logic_vector(1 downto 0);
    signal q_datw  : std_logic_vector(1 downto 0);
    signal q_cpol  : std_logic;
    signal q_cpha  : std_logic;
    signal q_awid  : std_logic_vector(1 downto 0);
    signal q_dummy : std_logic_vector(4 downto 0);
    -- q_cssel (CR[18:16]) is reserved: only CS0 exists, the firmware contract is "write 0", and the field is captured in QSPIxCR for readback but never consumed.
    signal q_br    : std_logic_vector(7 downto 0);
    signal q_tcie  : std_logic;
    signal q_rxfie : std_logic;

    -- Write-side clear pulses: each is asserted for one ClkMem edge on a qualifying write and retired on resetn='0' or EnMemPeriph='1', so a one-cycle pulse never straddles two selections.
    -- qspi_launch instead retires on clr_qspi_launch, set by the clk_baud-domain FSM once it accepts the launch.
    signal clr_txeif    : std_logic;
    signal clr_rxfull   : std_logic;
    signal clr_tcif     : std_logic;
    signal qspi_launch  : std_logic;
    signal clr_qspi_launch : std_logic;

    -- Status flip-flops: set by the serial-core FSM, W1C-cleared via clr_*.
    signal txeif_flag  : std_logic;
    signal rxfull_flag : std_logic;
    signal tcif_flag   : std_logic;
    signal busy        : std_logic;

    -- Baud-rate divider: two chained ClkGates fed from `not clk`; that edge family is deliberate, do not change it. Baud is SMCLK/(2*(1+BR)).
    signal en_clk_baud_src : std_logic;
    signal clk_baud_src    : std_logic;
    signal en_clk_baud     : std_logic;
    signal clk_baud        : std_logic;
    signal baud_counter    : std_logic_vector(7 downto 0);

    -- Serial core, clk_baud domain.
    signal sck      : std_logic;
    -- edge_cnt counts clk_baud EDGES, two per bit-group, i.e. one full SCK cycle, so a 32-bit single-width phase is 64 edges.
    -- Never fold drive and sample onto one edge; that halves the count and breaks the SCK timing.
    signal edge_cnt : natural range 0 to 64;
    signal t_sreg   : std_logic_vector(31 downto 0); -- CMD/ADDR/DATA-write shift-out reg
    signal rx_sreg  : std_logic_vector(31 downto 0); -- DATA-read shift-in accumulator

    -- Transaction-local fields (widths, AWID, DUMMY, DIR, DLEN, cmd byte, address) latched at launch, so mid-transaction CR/CMD/ADR writes cannot corrupt an in-flight transfer.
    -- QSPIxTX is deliberately NOT latched: the DATA phase reads it live.
    signal t_cmdw      : std_logic_vector(1 downto 0);
    signal t_adrw      : std_logic_vector(1 downto 0);
    signal t_datw      : std_logic_vector(1 downto 0);
    signal t_awid      : std_logic_vector(1 downto 0);
    signal t_dummy_val : natural range 0 to 31;
    signal t_dlen      : std_logic_vector(1 downto 0);
    signal t_dir       : std_logic;
    signal t_cmd       : std_logic_vector(7 downto 0);
    signal t_addr      : std_logic_vector(31 downto 0);

begin

    -- Signal routing ---------------------
    -- Control-register field taps off the stored QSPIxCR word. The ranges are
    -- qspi_regs_pkg's, so no bit literal in this file describes a register.
    q_en    <= regs_q(SLOT_CR)(QSPIEN_LSB);
    q_cmdw  <= regs_q(SLOT_CR)(QSPICMDW_MSB  downto QSPICMDW_LSB);
    q_adrw  <= regs_q(SLOT_CR)(QSPIADRW_MSB  downto QSPIADRW_LSB);
    q_datw  <= regs_q(SLOT_CR)(QSPIDATW_MSB  downto QSPIDATW_LSB);
    q_cpol  <= regs_q(SLOT_CR)(QSPICPOL_LSB);
    q_cpha  <= regs_q(SLOT_CR)(QSPICPHA_LSB);
    q_awid  <= regs_q(SLOT_CR)(QSPIAWID_MSB  downto QSPIAWID_LSB);
    q_dummy <= regs_q(SLOT_CR)(QSPIDUMMY_MSB downto QSPIDUMMY_LSB);
    -- QSPICSSEL is reserved and ignored in the MVP (CS0 only); it is stored for readback.
    q_br    <= regs_q(SLOT_CR)(QSPIBR_MSB downto QSPIBR_LSB);
    q_tcie  <= regs_q(SLOT_CR)(QSPITCIE_LSB);
    q_rxfie <= regs_q(SLOT_CR)(QSPIRXFIE_LSB);

    QSPIxSR(QSPIBUSY_LSB)   <= busy;
    QSPIxSR(QSPITXEIF_LSB)  <= txeif_flag;
    QSPIxSR(QSPIRXFULL_LSB) <= rxfull_flag;
    QSPIxSR(QSPITCIF_LSB)   <= tcif_flag;

    busy <= '0' when state = ST_IDLE else '1';

    -- SCK idles at the live CPOL while the block is reset or disabled: the flop
    -- resets to a constant (a non-constant in an asynchronous reset branch is not
    -- synthesizable) and the pad follows CPOL through this mux until the first
    -- clk_baud edge in ST_IDLE loads it.
    sck_out <= q_cpol when (resetn = '0' or q_en = '0') else sck;
    sck_dir <= '1'; -- SCK is always an output
    cs_dir  <= '1'; -- CS is always an output
    cs_out  <= '0' when state /= ST_IDLE else '1'; -- low only while a transaction is active

    -- Each irq_* is status AND enable, combinational and never latched.
    irq_tc  <= tcif_flag  and q_tcie;
    irq_rxf <= rxfull_flag and q_rxfie;

    -- Baud clock gating: qspi_en and either busy or the launch pulse, because the launch must spin the baud clock up BEFORE busy itself transitions.
    en_clk_baud_src <= q_en and (busy or qspi_launch);

    --End signal routing ---------------------

    -- First of the two chained ClkGates: the gated source clock the reload counter runs on.
    cg_clk_baud_src: entity work.ClkGate
        port map (
            ClkIn   => not clk,
            En      => en_clk_baud_src,
            ClkOut  => clk_baud_src
        );

    -- Baud reload counter: free-runs from q_br down to zero while the gated source clock ticks.
    baud_cntr_proc: process(clk_baud_src, resetn, q_en)
    begin
        if resetn = '0' or q_en = '0' then
            baud_counter <= (others => '0');
        elsif rising_edge(clk_baud_src) then
            if baud_counter = "00000000" then
                baud_counter <= q_br;
            else
                baud_counter <= baud_counter - 1;
            end if;
        end if;
    end process;

    en_clk_baud <= '1' when baud_counter = "00000000" and en_clk_baud_src = '1' else '0';
    cg_clk_baud: entity work.ClkGate
        port map (
            ClkIn   => not clk,
            En      => en_clk_baud,
            ClkOut  => clk_baud
        );

    -- Pre-latch the volatile registers inverted; the read process un-inverts them.
    reg_sync: process(EnMemPeriph, QSPIxRX, QSPIxSR)
    begin
        if falling_edge(EnMemPeriph) then
            QSPIxRX_ltch <= not QSPIxRX;
            QSPIxSR_ltch <= not QSPIxSR;
        end if;
    end process;

    -- The words this block owns rather than stores: the status snapshot and the
    -- receive word, both re-inverted out of the pre-latch above.
    sr_rd <= (31 downto QSPIxSR_ltch'high + 1 => '0') & (not QSPIxSR_ltch);
    rx_rd <= not QSPIxRX_ltch;

    hw_rd_s <= (SLOT_RX => rx_rd,
                SLOT_SR => sr_rd,
                others  => (others => '0'));

    -- STROBE_HOLD: the three SR clears reach the level-sensitive tail clears of
    -- fsm_proc, in the clk_baud domain, so they must be held for the whole
    -- selection rather than pulsed for one ClkMem cycle. That is byte for byte
    -- what the hand-written clr_* pulses were: set on the ClkMem edge of the
    -- write, retired on resetn = '0' or EnMemPeriph = '1'.
    -- No RDTHRU and no WIDEWR: QSPIxRX and QSPIxSR hold no IMPL bit, so they
    -- read hw_rd without having to be named, and every other word merges per lane.
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
            STROBE_HOLD => true)
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
            w1c_hit     => w1c_s,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    -- The three write-1-to-clear flags, as held levels into the asynchronous
    -- clears in fsm_proc. BUSY is hardware-driven and outside W1C, so a 1
    -- written to it reaches nothing, exactly as before.
    clr_txeif  <= w1c_s(SLOT_SR)(QSPITXEIF_LSB);
    clr_rxfull <= w1c_s(SLOT_SR)(QSPIRXFULL_LSB);
    clr_tcif   <= w1c_s(SLOT_SR)(QSPITCIF_LSB);

    -- The SOLE transaction trigger: a lane-0 write to QSPIxCMD. periph_regs
    -- captures the register content whatever happens; the launch is suppressed
    -- (a no-op, no corruption) when QSPIEN = 0 or BUSY = 1.
    -- It takes the COMBINATIONAL acc_hit and qualifies it with its own WEn(0),
    -- exactly as the raw decode did, so the launch still lands on the edge the
    -- write does. qspi_launch retires on clr_qspi_launch, set by the clk_baud
    -- FSM once it accepts the launch, and not on deselect.
    launch_proc: process(resetn, ClkMem, clr_qspi_launch)
    begin
        if rising_edge(ClkMem) then
            if acc_s(SLOT_CMD) = '1' and WEn(0) = '0'
               and q_en = '1' and busy = '0' then
                qspi_launch <= '1';
            end if;
        end if;

        if resetn = '0' or clr_qspi_launch = '1' then
            qspi_launch <= '0';
        end if;
    end process;

    -- QSPI serial core, clk_baud domain. CDC: qspi_launch is set in the ClkMem domain and read directly here, with no 2-FF synchronizer.
    -- Safe because it is a registered held level, not a single-cycle glitch, and retires only when clr_qspi_launch acks it, so a metastable sample delays launch by one clk_baud edge instead of corrupting state.
    fsm_proc: process(resetn, clk_baud, q_en, qspi_launch, clr_txeif, clr_rxfull, clr_tcif, q_cpol)
        variable w : natural;

        -- Shared "leaving a phase" transition: picks the next phase from the LATCHED fields and does that phase's entry setup on the same clk_baud edge as the outgoing phase's last transfer.
        procedure fold_from(from_st : in QState_t) is
            variable np : QState_t;
        begin
            np := next_phase(t_awid, t_dummy_val, t_dlen, from_st);
            case np is
                when ST_ADDR =>
                    if t_awid = "01" then
                        t_sreg   <= t_addr(23 downto 0) & x"00";
                        edge_cnt <= 2 * (24 / width_bits(t_adrw));
                    else -- t_awid = "10" (32-bit); "00"/"11" never reach ST_ADDR
                        t_sreg   <= t_addr;
                        edge_cnt <= 2 * (32 / width_bits(t_adrw));
                    end if;
                    state <= ST_ADDR;
                when ST_DUMMY =>
                    -- DUMMY counts full SCK cycles, so 2 clk_baud edges per counted cycle.
                    edge_cnt <= 2 * t_dummy_val;
                    state    <= ST_DUMMY;
                when ST_DATA =>
                    if t_dir = '0' then
                        -- WRITE: QSPIxTX is read LIVE here, deliberately not latched at launch like the CMD/ADDR fields.
                        -- MSB-first with no byte swap: the low DLEN bits of the 32-bit register are the significant field.
                        case t_dlen is
                            when "01"   => t_sreg <= regs_q(SLOT_TX)(7 downto 0) & x"000000";
                            when "10"   => t_sreg <= regs_q(SLOT_TX)(15 downto 0) & x"0000";
                            when others => t_sreg <= regs_q(SLOT_TX); -- "11" (32-bit)
                        end case;
                    else
                        rx_sreg <= (others => '0');
                    end if;
                    edge_cnt <= 2 * (dlen_bits_f(t_dlen) / width_bits(t_datw));
                    state    <= ST_DATA;
                when others => -- ST_DONE: no address, dummy or data phase remained
                    tcif_flag <= '1';
                    state     <= ST_DONE;
            end case;
        end procedure;

    begin
        if resetn = '0' or q_en = '0' then
            state         <= ST_IDLE;
            edge_cnt      <= 0;
            sck           <= '0';
            clr_qspi_launch <= '0';
        elsif rising_edge(clk_baud) then
            clr_qspi_launch <= '0';

            case state is
                -- Idle: wait for a launch pulse, then latch the transaction and enter CMD.
                when ST_IDLE =>
                    sck <= q_cpol; -- track live CPOL while idle
                    if qspi_launch = '1' then
                        txeif_flag      <= '1'; -- TXEIF is set as the FSM leaves IDLE, i.e. the launch was accepted
                        clr_qspi_launch <= '1';
                        if q_cpha = '1' then
                            -- CPHA=1 pre-toggle, once per transaction.
                            sck <= not q_cpol;
                        end if;
                        -- Latch the CR/CMD-derived transaction fields: widths, AWID, DUMMY, DIR, DLEN, cmd byte, address.
                        t_cmdw      <= q_cmdw;
                        t_adrw      <= q_adrw;
                        t_datw      <= q_datw;
                        t_awid      <= q_awid;
                        t_dummy_val <= slv2uint(q_dummy);
                        t_dlen      <= regs_q(SLOT_CMD)(QSPIDLEN_MSB downto QSPIDLEN_LSB);
                        t_dir       <= regs_q(SLOT_CMD)(QSPIDIR_LSB);
                        t_cmd       <= regs_q(SLOT_CMD)(QSPICMD_MSB downto QSPICMD_LSB);
                        t_addr      <= regs_q(SLOT_ADR);
                        -- CMD phase is never zero-length: always entered first.
                        t_sreg      <= regs_q(SLOT_CMD)(QSPICMD_MSB downto QSPICMD_LSB) & x"000000";
                        edge_cnt    <= 2 * (8 / width_bits(q_cmdw));
                        state       <= ST_CMD;
                    end if;

                -- Command phase: shift the opcode out at CMD width.
                -- Each bit-group takes one FULL SCK cycle, i.e. two clk_baud edges with sck toggling every edge; with the CPHA pre-toggle folded in at launch the SAMPLE edge is always the EVEN edge_cnt and the DRIVE edge the ODD one, and the final edge_cnt=1 drive edge folds into the next phase.
                when ST_CMD =>
                    sck <= not sck;
                    if edge_cnt = 1 then
                        fold_from(ST_CMD);
                    else
                        edge_cnt <= edge_cnt - 1;
                        if (edge_cnt mod 2) = 1 then   -- drive edge: advance output
                            w := width_bits(t_cmdw);
                            case w is
                                when 2      => t_sreg <= t_sreg(29 downto 0) & "00";
                                when 4      => t_sreg <= t_sreg(27 downto 0) & "0000";
                                when others => t_sreg <= t_sreg(30 downto 0) & '0';
                            end case;
                        end if;
                    end if;

                -- Address phase: shift the 24- or 32-bit address out at ADDR width.
                when ST_ADDR =>
                    sck <= not sck;
                    if edge_cnt = 1 then
                        fold_from(ST_ADDR);
                    else
                        edge_cnt <= edge_cnt - 1;
                        if (edge_cnt mod 2) = 1 then   -- drive edge: advance output
                            w := width_bits(t_adrw);
                            case w is
                                when 2      => t_sreg <= t_sreg(29 downto 0) & "00";
                                when 4      => t_sreg <= t_sreg(27 downto 0) & "0000";
                                when others => t_sreg <= t_sreg(30 downto 0) & '0';
                            end case;
                        end if;
                    end if;

                -- Dummy phase: turnaround cycles between the address and read data.
                when ST_DUMMY =>
                    -- The bus is released for the whole dummy phase while sck still toggles: no sample or drive work, just 2*DUMMY edges to burn.
                    -- DUMMY_CYCLES=0 with a dual or quad READ leaves no turnaround and is firmware misuse.
                    sck <= not sck;
                    if edge_cnt = 1 then
                        fold_from(ST_DUMMY);
                    else
                        edge_cnt <= edge_cnt - 1;
                    end if;

                -- Data phase: shift the write word out, or accumulate the read word in.
                when ST_DATA =>
                    sck <= not sck;
                    w := width_bits(t_datw);
                    if edge_cnt = 1 then
                        -- Final drive edge of the data phase: rx_sreg already holds every sampled bit, the last sample having happened at edge_cnt=2.
                        -- Latch QSPIxRX and the flags together so RXFULL and TCIF settle on the same edge.
                        if t_dir = '1' then
                            QSPIxRX     <= rx_sreg;
                            rxfull_flag <= '1';
                        end if;
                        tcif_flag <= '1';
                        state     <= ST_DONE;
                    else
                        edge_cnt <= edge_cnt - 1;
                        if (edge_cnt mod 2) = 0 then
                            -- Sample edge: capture read data; writes hold their output.
                            if t_dir = '1' then
                                case w is
                                    when 2      => rx_sreg <= rx_sreg(29 downto 0) & io_in(1 downto 0);
                                    when 4      => rx_sreg <= rx_sreg(27 downto 0) & io_in(3 downto 0);
                                    when others => rx_sreg <= rx_sreg(30 downto 0) & io_in(1);
                                end case;
                            end if;
                        else
                            -- Drive edge: advance the write output; reads stay released.
                            if t_dir = '0' then
                                case w is
                                    when 2      => t_sreg <= t_sreg(29 downto 0) & "00";
                                    when 4      => t_sreg <= t_sreg(27 downto 0) & "0000";
                                    when others => t_sreg <= t_sreg(30 downto 0) & '0';
                                end case;
                            end if;
                        end if;
                    end if;

                -- Done: one tail edge with BUSY still high, then back to idle and CS released.
                when ST_DONE =>
                    state <= ST_IDLE;
                    sck   <= q_cpol;

            end case;
        end if;

        -- QSPIxRX has no write-side reset and the FSM only ever ASSIGNS it, so it must be reset here or its readback is 'X' until the first READ completes.
        -- Reset only and deliberately not q_en=0: disabling the peripheral does not wipe data.
        if resetn = '0' then
            QSPIxRX <= (others => '0');
        end if;

        -- Status flag W1C application, a level-sensitive tail clear.
        -- QSPIEN=0 deliberately does NOT clear these flags: only reset and an explicit W1C write clear them.
        if resetn = '0' or clr_txeif = '1' then
            txeif_flag <= '0';
        end if;
        if resetn = '0' or clr_rxfull = '1' then
            rxfull_flag <= '0';
        end if;
        if resetn = '0' or clr_tcif = '1' then
            tcif_flag <= '0';
        end if;
    end process;

    -- IO lane drive and direction mux, combinational. Single-width phases always drive IO0 and always read IO1, the MISO position, regardless of DATA DIR; IO2/IO3 stay driven high (WP# and HOLD# deasserted) whenever they are not carrying data.
    -- Dual and quad phases drive io_dir(width-1:0) while driving (CMD, ADDR, DATA-WRITE) and release everything during DUMMY and DATA-READ; the mux is combinational off state and the latched fields, so it flips on the same edge the state does, with no hidden turnaround cycle.
    io_mux: process(state, t_cmdw, t_adrw, t_datw, t_dir, t_sreg)
        variable w : natural;
    begin
        io_out <= (others => '0');
        io_dir <= (others => '0'); -- default: released (IDLE, DUMMY, DONE)

        case state is
            when ST_CMD =>
                w := width_bits(t_cmdw);
                if w = 1 then
                    io_dir <= "1101"; -- IO3,IO2 driven high; IO1 input; IO0 drives
                    io_out(0) <= t_sreg(31);
                    io_out(2) <= '1';
                    io_out(3) <= '1';
                elsif w = 2 then
                    io_dir <= "1111";
                    io_out(1 downto 0) <= t_sreg(31 downto 30);
                    io_out(3 downto 2) <= "11"; -- WP# and HOLD# deasserted; dual does not use IO2/IO3
                else -- w = 4
                    io_dir <= "1111";
                    io_out(3 downto 0) <= t_sreg(31 downto 28);
                end if;

            when ST_ADDR =>
                w := width_bits(t_adrw);
                if w = 1 then
                    io_dir <= "1101";
                    io_out(0) <= t_sreg(31);
                    io_out(2) <= '1';
                    io_out(3) <= '1';
                elsif w = 2 then
                    io_dir <= "1111";
                    io_out(1 downto 0) <= t_sreg(31 downto 30);
                    io_out(3 downto 2) <= "11";
                else
                    io_dir <= "1111";
                    io_out(3 downto 0) <= t_sreg(31 downto 28);
                end if;

            when ST_DATA =>
                w := width_bits(t_datw);
                if t_dir = '0' then -- WRITE: same drive rules as CMD/ADDR
                    if w = 1 then
                        io_dir <= "1101";
                        io_out(0) <= t_sreg(31);
                        io_out(2) <= '1';
                        io_out(3) <= '1';
                    elsif w = 2 then
                        io_dir <= "1111";
                        io_out(1 downto 0) <= t_sreg(31 downto 30);
                        io_out(3 downto 2) <= "11";
                    else
                        io_dir <= "1111";
                        io_out(3 downto 0) <= t_sreg(31 downto 28);
                    end if;
                else -- READ
                    if w = 1 then
                        -- Single-width read: IO0 stays the driving line, held low since there is nothing meaningful to send, IO1 stays the input/MISO position, IO2 and IO3 are deasserted high.
                        io_dir <= "1101";
                        io_out(0) <= '0';
                        io_out(2) <= '1';
                        io_out(3) <= '1';
                    else
                        io_dir <= (others => '0'); -- dual/quad READ: fully released
                    end if;
                end if;

            when others => -- ST_IDLE, ST_DUMMY, ST_DONE: bus released
                null;
        end case;
    end process;

end behavioral;
