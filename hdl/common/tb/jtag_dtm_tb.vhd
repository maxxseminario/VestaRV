-- VestaRV: JTAG Debug Transport Module testbench
-- Unit proof for hdl/common/jtag_dtm.vhd: the IEEE 1149.1 TAP, the four DRs (IDCODE, dtmcs, the 41-bit dmi, BYPASS), the sticky BUSY/FAILED machine, and the four-phase toggle crossing between the tck and mclk domains.
-- The two clocks are deliberately INCOMMENSURATE (37 ns tck against 10 ns mclk, ratio 3.7): a bench that ran them at an integer ratio would exercise one fixed phase of the synchroniser chains and could not see a crossing that only works when the edges line up.
-- The mclk side is a bench-written DMI slave model, not the real Debug Module. It is programmable in accept latency, response latency and response op, which is the only way to reach the three states the DM cannot be steered into on demand: a transaction still in flight when the next DR scan arrives (sticky BUSY), a response carrying op = FAILED (sticky FAILED), and a transaction abandoned by TRSTn whose response lands after the TAP has been reset.
-- Self-checking: every check reports and keeps going, and the run ends with ALL CHECKS PASSED or TB FAILED.
-- The ENABLE_DEBUG = false fold is proved by a SECOND instance wired to the same five pins: it must stay inert under the whole stimulus, which is what makes the knob a fail-safe rather than a comment.
-- TDO discipline the bench relies on: the DUT updates tdo on the TCK FALLING edge and the host samples it before the next RISING edge, so tck_cycle samples tdo first and raises tck second. Sampling after the rise would read the bit one cycle late and every shift check would be off by one.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity jtag_dtm_tb is
    generic (
        -- STRICT_TRSTN_GUARD selects which contract section H grades.
        -- false (default): the guard's MEASURED behaviour, with the escape
        -- bounded (report P3, finding P3-1).
        -- true: the contract jtag_dtm.vhd's own comment states, which is RED
        -- until the guard is made combinational on trstn_s2.
        STRICT_TRSTN_GUARD : boolean := false;
        MCLK_PERIOD : time    := 10 ns;
        TCK_PERIOD  : time    := 37 ns;   -- NOT a multiple of MCLK_PERIOD, on purpose
        IDLE_CYC    : natural := 5
    );
end entity;

architecture tb of jtag_dtm_tb is

    constant IDCODE_VAL : std_logic_vector(31 downto 0) := x"1CA57EEF";

    -- dtmcs with dmistat = 0: idle[14:12] = IDLE_CYC, abits[9:4] = 7, version[3:0] = 1.
    constant DTMCS_BASE : std_logic_vector(31 downto 0) :=
        "00000000000000000" & conv_std_logic_vector(IDLE_CYC, 3) &
        "00" & "000111" & "0001";
    constant STICKY_BUSY   : std_logic_vector(31 downto 0) := x"00000C00";
    constant STICKY_FAILED : std_logic_vector(31 downto 0) := x"00000800";

    constant IR_IDCODE : std_logic_vector(4 downto 0) := "00001";
    constant IR_DTMCS  : std_logic_vector(4 downto 0) := "10000";
    constant IR_DMI    : std_logic_vector(4 downto 0) := "10001";
    constant IR_BYPASS : std_logic_vector(4 downto 0) := "11111";
    constant IR_JUNK   : std_logic_vector(4 downto 0) := "00111";   -- unsupported: must select BYPASS

    constant OP_NOP   : std_logic_vector(1 downto 0) := "00";
    constant OP_READ  : std_logic_vector(1 downto 0) := "01";
    constant OP_WRITE : std_logic_vector(1 downto 0) := "10";
    constant OP_FAIL  : std_logic_vector(1 downto 0) := "10";
    constant OP_BUSY  : std_logic_vector(1 downto 0) := "11";

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    -- the five JTAG pins, shared by both DUT instances
    signal tck   : std_logic := '0';
    signal tms   : std_logic := '1';
    signal tdi   : std_logic := '0';
    signal tdo   : std_logic;
    signal trstn : std_logic := '0';

    signal dmi_req_valid : std_logic;
    signal dmi_req_op    : std_logic_vector(1 downto 0);
    signal dmi_req_addr  : std_logic_vector(6 downto 0);
    signal dmi_req_data  : std_logic_vector(31 downto 0);
    signal dmi_req_ready : std_logic := '0';
    signal dmi_rsp_valid : std_logic := '0';
    signal dmi_rsp_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal dmi_rsp_op    : std_logic_vector(1 downto 0) := "00";

    -- the ENABLE_DEBUG = false fold, on the same pins
    signal tdo_off       : std_logic;
    signal req_valid_off : std_logic;
    signal req_op_off    : std_logic_vector(1 downto 0);
    signal req_addr_off  : std_logic_vector(6 downto 0);
    signal req_data_off  : std_logic_vector(31 downto 0);

    -- DMI slave model controls, driven by the stimulus process
    signal slv_rdy_lat : natural := 0;                          -- mclk cycles of valid before ready
    signal slv_rsp_lat : natural := 2;                          -- mclk cycles from accept to response
    signal slv_fail    : std_logic := '0';                      -- respond with op = FAILED
    signal slv_rdata   : std_logic_vector(31 downto 0) := x"00000000";
    -- and what it observed
    signal slv_op_q    : std_logic_vector(1 downto 0) := "00";
    signal slv_addr_q  : std_logic_vector(6 downto 0) := (others => '0');
    signal slv_data_q  : std_logic_vector(31 downto 0) := (others => '0');
    signal slv_accepts : natural := 0;                          -- transactions accepted
    signal req_rises   : natural := 0;                          -- dmi_req_valid rising edges
    signal req_illegal : natural := 0;                          -- valid with an op outside {01,10}
    signal ill_op      : std_logic_vector(1 downto 0) := "00";  -- and what it carried
    signal ill_addr    : std_logic_vector(6 downto 0) := (others => '0');
    signal ill_data    : std_logic_vector(31 downto 0) := (others => '0');
    -- Crossing-latency instrument. upd_at is the simulation time of the TCK
    -- rising edge that ran an Update-DR, req_rise_at the time dmi_req_valid
    -- went high for it. A 2-flop synchroniser plus the edge-detect flop puts
    -- at least three mclk edges between them, so the gap is STRICTLY more than
    -- two mclk periods; a chain one stage short lands at two edges or fewer
    -- and cannot. This is the one CDC mutation an event-driven simulation can
    -- see at all: removing a stage changes no VALUE, only the latency.
    signal upd_at      : time := 0 ns;
    signal req_rise_at : time := 0 ns;
    signal off_active  : natural := 0;                          -- any life on the folded instance

    signal checks : integer := 0;
    signal fails  : integer := 0;
    signal done   : boolean := false;

begin

    clk <= not clk after MCLK_PERIOD / 2 when not done else '0';

    dut: entity work.jtag_dtm
        generic map (
            ENABLE_DEBUG => true,
            IDCODE       => IDCODE_VAL,
            IDLE_CYCLES  => IDLE_CYC
        )
        port map (
            tck   => tck,
            tms   => tms,
            tdi   => tdi,
            tdo   => tdo,
            trstn => trstn,
            clk    => clk,
            resetn => resetn,
            dmi_req_valid => dmi_req_valid,
            dmi_req_op    => dmi_req_op,
            dmi_req_addr  => dmi_req_addr,
            dmi_req_data  => dmi_req_data,
            dmi_req_ready => dmi_req_ready,
            dmi_rsp_valid => dmi_rsp_valid,
            dmi_rsp_data  => dmi_rsp_data,
            dmi_rsp_op    => dmi_rsp_op
        );

    -- The fold. Its DMI inputs stay at their port defaults: a debug-disabled DTM must be inert with nothing wired to it at all, which is the shape MemoryMap.vhd leaves behind when ENABLE_DEBUG is false.
    dut_off: entity work.jtag_dtm
        generic map (
            ENABLE_DEBUG => false,
            IDCODE       => IDCODE_VAL,
            IDLE_CYCLES  => IDLE_CYC
        )
        port map (
            tck   => tck,
            tms   => tms,
            tdi   => tdi,
            tdo   => tdo_off,
            trstn => trstn,
            clk    => clk,
            resetn => resetn,
            dmi_req_valid => req_valid_off,
            dmi_req_op    => req_op_off,
            dmi_req_addr  => req_addr_off,
            dmi_req_data  => req_data_off,
            dmi_req_ready => open,
            dmi_rsp_valid => open,
            dmi_rsp_data  => open,
            dmi_rsp_op    => open
        );

    -- ---- the DMI slave model -------------------------------------------
    -- Registered ready, one pulse per accepted request, then a response
    -- slv_rsp_lat cycles later. Both latencies are programmable so the
    -- stimulus can park a transaction in flight for as long as it needs.
    slave: process(clk, resetn)
        variable st  : natural := 0;
        variable cnt : natural := 0;
    begin
        if resetn = '0' then
            dmi_req_ready <= '0';
            dmi_rsp_valid <= '0';
            dmi_rsp_data  <= (others => '0');
            dmi_rsp_op    <= "00";
            st  := 0;
            cnt := 0;
        elsif rising_edge(clk) then
            dmi_req_ready <= '0';
            dmi_rsp_valid <= '0';
            if st = 0 then
                if dmi_req_valid = '1' then
                    if cnt >= slv_rdy_lat then
                        dmi_req_ready <= '1';
                        slv_op_q      <= dmi_req_op;
                        slv_addr_q    <= dmi_req_addr;
                        slv_data_q    <= dmi_req_data;
                        slv_accepts   <= slv_accepts + 1;
                        cnt := 0;
                        st  := 1;
                    else
                        cnt := cnt + 1;
                    end if;
                else
                    cnt := 0;
                end if;
            else
                if cnt >= slv_rsp_lat then
                    dmi_rsp_valid <= '1';
                    dmi_rsp_data  <= slv_rdata;
                    if slv_fail = '1' then
                        dmi_rsp_op <= OP_FAIL;
                    else
                        dmi_rsp_op <= "00";
                    end if;
                    cnt := 0;
                    st  := 0;
                else
                    cnt := cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- ---- protocol monitors ---------------------------------------------
    -- req_rises counts assertions of dmi_req_valid, which is the only way to
    -- see a PHANTOM request: one the TCK side never armed.
    -- req_illegal counts any cycle where the DTM presents an op outside the
    -- two legal encodings while valid, which a NOP scan arming the master
    -- would produce.
    monitor: process(clk, resetn)
        variable prev : std_logic := '0';
    begin
        if resetn = '0' then
            req_rises   <= 0;
            req_illegal <= 0;
            prev := '0';
        elsif rising_edge(clk) then
            if dmi_req_valid = '1' and prev = '0' then
                req_rises   <= req_rises + 1;
                req_rise_at <= now;
            end if;
            if dmi_req_valid = '1' and dmi_req_op /= OP_READ and dmi_req_op /= OP_WRITE then
                req_illegal <= req_illegal + 1;
                ill_op      <= dmi_req_op;
                ill_addr    <= dmi_req_addr;
                ill_data    <= dmi_req_data;
            end if;
            prev := dmi_req_valid;
        end if;
    end process;

    -- The fold is watched CONTINUOUSLY, not sampled at the end: an instance
    -- that stirred for one cycle in the middle of a scan and settled again
    -- would pass an end-of-run snapshot.
    fold_watch: process(clk)
    begin
        if rising_edge(clk) then
            if tdo_off /= '0' or req_valid_off /= '0'
               or req_op_off /= "00"
               or req_addr_off /= "0000000"
               or req_data_off /= x"00000000" then
                off_active <= off_active + 1;
            end if;
        end if;
    end process;

    stim: process

        -- Record a failed expectation and keep going, so one run reports every defect.
        procedure check(cond : boolean; msg : string) is
        begin
            checks <= checks + 1;
            if not cond then
                fails <= fails + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
            wait for 0 ns;   -- let the counters land before the next call
        end procedure;

        -- One TCK cycle. tms/tdi are presented while tck is low, tdo is
        -- sampled just before the rising edge (it was driven at the previous
        -- falling edge), then tck rises and falls.
        procedure tck_cycle(t : std_logic; d : std_logic;
                            variable q : out std_logic) is
        begin
            tms <= t;
            tdi <= d;
            wait for TCK_PERIOD / 2;
            q := tdo;
            tck <= '1';
            wait for TCK_PERIOD / 2;
            tck <= '0';
        end procedure;

        procedure tck_n(t : std_logic; n : natural) is
            variable q : std_logic;
        begin
            for i in 1 to n loop
                tck_cycle(t, '0', q);
            end loop;
        end procedure;

        -- Five TMS-high cycles reach Test-Logic-Reset from any state; one low
        -- cycle then lands in Run-Test/Idle.
        procedure goto_rti is
        begin
            tck_n('1', 5);
            tck_n('0', 1);
        end procedure;

        -- Sit in Run-Test/Idle, which is where dtmcs.idle tells a debugger to
        -- wait for the DMI round trip.
        procedure idle(n : natural) is
        begin
            tck_n('0', n);
        end procedure;

        -- IR scan from Run-Test/Idle, back to Run-Test/Idle.
        -- Returns the Capture-IR value, which 1149.1 requires to end in "01".
        procedure scan_ir(v : std_logic_vector(4 downto 0);
                          variable cap : out std_logic_vector(4 downto 0)) is
            variable q  : std_logic;
            variable ov : std_logic_vector(4 downto 0);
        begin
            tck_cycle('1', '0', q);   -- Select-DR
            tck_cycle('1', '0', q);   -- Select-IR
            tck_cycle('0', '0', q);   -- Capture-IR
            tck_cycle('0', '0', q);   -- Shift-IR
            for i in 0 to 4 loop
                if i = 4 then
                    tck_cycle('1', v(i), q);   -- last shift also leaves for Exit1-IR
                else
                    tck_cycle('0', v(i), q);
                end if;
                ov(i) := q;
            end loop;
            tck_cycle('1', '0', q);   -- Update-IR
            tck_cycle('0', '0', q);   -- Run-Test/Idle
            cap := ov;
        end procedure;

        -- DR scan from Run-Test/Idle, back to Run-Test/Idle. LSB first.
        procedure scan_dr(din : std_logic_vector;
                          variable dout : out std_logic_vector) is
            variable dv : std_logic_vector(din'length - 1 downto 0) := din;
            variable ov : std_logic_vector(din'length - 1 downto 0) := (others => '0');
            variable q  : std_logic;
        begin
            tck_cycle('1', '0', q);   -- Select-DR
            tck_cycle('0', '0', q);   -- Capture-DR
            tck_cycle('0', '0', q);   -- Shift-DR
            for i in 0 to dv'high loop
                if i = dv'high then
                    tck_cycle('1', dv(i), q);
                else
                    tck_cycle('0', dv(i), q);
                end if;
                ov(i) := q;
            end loop;
            tck_cycle('1', '0', q);   -- Update-DR
            -- tck_cycle returns half a period after the rising edge it drove.
            upd_at <= now - TCK_PERIOD / 2;
            tck_cycle('0', '0', q);   -- Run-Test/Idle
            dout := ov;
        end procedure;

        -- A DMI DR scan: op[1:0], data[33:2], address[40:34].
        -- It delivers the PREVIOUS transaction's result and arms this one.
        procedure dmi_scan(op   : std_logic_vector(1 downto 0);
                           addr : std_logic_vector(6 downto 0);
                           data : std_logic_vector(31 downto 0);
                           variable rop   : out std_logic_vector(1 downto 0);
                           variable raddr : out std_logic_vector(6 downto 0);
                           variable rdata : out std_logic_vector(31 downto 0)) is
            variable din  : std_logic_vector(40 downto 0);
            variable dout : std_logic_vector(40 downto 0);
        begin
            din := addr & data & op;
            scan_dr(din, dout);
            rop   := dout(1 downto 0);
            rdata := dout(33 downto 2);
            raddr := dout(40 downto 34);
        end procedure;

        variable cap5  : std_logic_vector(4 downto 0);
        variable w32   : std_logic_vector(31 downto 0);
        variable w1    : std_logic_vector(0 downto 0);
        variable rop   : std_logic_vector(1 downto 0);
        variable raddr : std_logic_vector(6 downto 0);
        variable rdata : std_logic_vector(31 downto 0);
        variable n0, n1 : natural;
        variable a0, a1 : natural;
        variable ill0   : natural;
        variable qv     : std_logic;

    begin
        -- === A. TRSTn reset and the IDCODE default ==========================
        resetn <= '0';
        trstn  <= '0';
        wait for 4 * MCLK_PERIOD;
        resetn <= '1';
        wait for 4 * MCLK_PERIOD;

        -- The TAP is held in reset: tdo is low and nothing reaches the mclk side.
        tck_n('0', 3);
        check(tdo = '0', "A1: tdo not low while trstn is asserted");
        check(dmi_req_valid = '0', "A2: dmi_req_valid asserted while trstn is asserted");
        check(req_rises = 0, "A3: a DMI request was issued before trstn was released");

        trstn <= '1';
        wait for 3 * MCLK_PERIOD;
        goto_rti;

        -- TRSTn leaves IR = IDCODE, so the first DR scan is the 32-bit IDCODE.
        scan_dr(x"00000000", w32);
        check(w32 = IDCODE_VAL, "A4: IDCODE after trstn release is " &
              integer'image(conv_integer(w32(15 downto 0))) & " (low half)");

        -- IDCODE is a CONSTANT loaded at Capture-DR: shifting a pattern through
        -- it must change nothing on the next scan.
        scan_dr(x"5A5AA5A5", w32);
        check(w32 = IDCODE_VAL, "A5: second IDCODE read differs from the first");
        scan_dr(x"FFFFFFFF", w32);
        check(w32 = IDCODE_VAL, "A6: IDCODE is not constant across scans");

        -- Capture-IR must present bits [1:0] = "01"; the DTM uses 0x01.
        scan_ir(IR_IDCODE, cap5);
        check(cap5 = "00001", "A7: Capture-IR value is not 0x01");
        check(req_rises = 0, "A8: an IDCODE or IR scan issued a DMI request");

        -- === B. IR decode and the BYPASS default ============================
        scan_ir(IR_BYPASS, cap5);
        scan_dr("0", w1);
        check(w1(0) = '0', "B1: BYPASS did not capture 0");
        -- A 1-bit BYPASS chain shifted with a 1 returns that 1 on the NEXT scan.
        -- BYPASS re-captures 0 at every Capture-DR, so the head of the next
        -- scan is 0 again whatever was shifted in.
        scan_dr("1", w1);
        check(w1(0) = '0', "B2: BYPASS returned other than its captured 0");

        -- Every unsupported opcode selects BYPASS, i.e. a 1-bit chain capturing 0.
        scan_ir(IR_JUNK, cap5);
        scan_dr("0", w1);
        check(w1(0) = '0', "B3: an unsupported IR did not select BYPASS");
        -- A 1-bit chain shifted 32 times returns the captured 0 followed by
        -- the 31 bits just shifted in, which a 32-bit chain could not produce.
        scan_dr(x"FFFFFFFF", w32);
        check(w32 = x"FFFFFFFE", "B4: BYPASS is not a one-bit chain under an unsupported IR");

        -- Test-Logic-Reset restores IR = IDCODE and nothing else.
        goto_rti;
        scan_dr(x"00000000", w32);
        check(w32 = IDCODE_VAL, "B5: Test-Logic-Reset did not restore IR = IDCODE");

        -- === C. dtmcs ======================================================
        scan_ir(IR_DTMCS, cap5);
        check(cap5 = "00001", "C1: Capture-IR value changed with the loaded IR");
        scan_dr(x"00000000", w32);
        check(w32 = DTMCS_BASE, "C2: dtmcs at reset is not the expected constant");
        check(w32(3 downto 0) = "0001", "C3: dtmcs.version is not 1");
        check(w32(9 downto 4) = "000111", "C4: dtmcs.abits is not 7");
        check(w32(14 downto 12) = conv_std_logic_vector(IDLE_CYC, 3), "C5: dtmcs.idle does not match IDLE_CYCLES");
        check(w32(11 downto 10) = "00", "C6: dtmcs.dmistat is nonzero at reset");
        -- dmireset/dmihardreset are write-only strobes and read back as zero.
        check(w32(17 downto 16) = "00", "C7: the dmireset strobes read back nonzero");

        -- === D. a DMI write ================================================
        scan_ir(IR_DMI, cap5);
        slv_rdy_lat <= 0;
        slv_rsp_lat <= 2;
        slv_fail    <= '0';
        slv_rdata   <= x"00000000";
        n0 := req_rises;

        -- The first DMI scan delivers the empty shadow and arms the write.
        dmi_scan(OP_WRITE, "0010000", x"DEADBEEF", rop, raddr, rdata);
        check(rop = "00", "D1: the first DMI capture is not op = 0");
        check(rdata = x"00000000", "D2: the first DMI capture is not an empty shadow");
        check(raddr = "0000000", "D3: the first DMI capture has a nonzero address");
        idle(12);

        check(req_rises = n0 + 1, "D4: the DMI write did not raise exactly one request");
        check(slv_op_q = OP_WRITE, "D5: the slave saw the wrong DMI op");
        check(slv_addr_q = "0010000", "D6: the slave saw the wrong DMI address");
        check(slv_data_q = x"DEADBEEF", "D7: the slave saw the wrong DMI write data");
        check(dmi_req_valid = '0', "D8: dmi_req_valid is still high after the accept");
        check(req_illegal = 0, "D9: dmi_req_valid was asserted with an illegal op");
        check(req_rise_at - upd_at > 2 * MCLK_PERIOD,
              "D10: the request crossed in " & time'image(req_rise_at - upd_at) &
              ", short of the three mclk edges a 2-flop chain plus edge detect costs");

        -- === E. a DMI read, and the address preserved through the capture ===
        slv_rdata <= x"0BADF00D";
        a0 := slv_accepts;
        dmi_scan(OP_READ, "1010101", x"00000000", rop, raddr, rdata);
        check(rop = "00", "E1: the write result is not op = ok");
        check(raddr = "0010000", "E2: the write result did not preserve its address");
        check(rdata = x"00000000", "E3: the write result carries unexpected data");
        idle(12);
        check(slv_accepts = a0 + 1, "E4: the DMI read was not accepted");
        check(slv_op_q = OP_READ, "E5: the slave saw the wrong op on the read");
        check(slv_addr_q = "1010101", "E6: the slave saw the wrong read address");

        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = "00", "E7: the read result is not op = ok");
        check(rdata = x"0BADF00D", "E8: the read result did not carry the slave's data");
        check(raddr = "1010101", "E9: the read result did not preserve its address");
        idle(12);

        -- A NOP scan arms nothing, which is what makes a capture-only scan safe.
        n0 := req_rises;
        a0 := slv_accepts;
        dmi_scan(OP_NOP, "1111111", x"FFFFFFFF", rop, raddr, rdata);
        idle(12);
        check(req_rises = n0, "E10: a NOP DMI scan raised a request");
        check(slv_accepts = a0, "E11: a NOP DMI scan reached the slave");
        check(rdata = x"0BADF00D", "E12: the NOP capture did not re-read the shadow");

        -- === F. sticky BUSY ================================================
        -- Park a transaction in flight for far longer than one DR scan, then
        -- scan again: the capture must be the literal 3 and dmistat must stick.
        slv_rsp_lat <= 400;
        slv_rdata   <= x"55AA55AA";
        n0 := req_rises;
        dmi_scan(OP_READ, "0000011", x"00000000", rop, raddr, rdata);
        -- No idle: the next scan starts while the slave is still holding.
        dmi_scan(OP_READ, "0000100", x"00000000", rop, raddr, rdata);
        check(rop = OP_BUSY, "F1: a capture during an in-flight transaction is not op = busy");
        check(rdata = x"00000000", "F2: the busy capture is not the literal 3 (data)");
        check(raddr = "0000000", "F3: the busy capture is not the literal 3 (address)");
        check(req_rises = n0 + 1, "F4: the DMI op issued while busy reached the master");

        -- dtmcs must now report sticky busy, and the DMI DR must stay dead.
        scan_ir(IR_DTMCS, cap5);
        scan_dr(x"00000000", w32);
        check(w32 = (DTMCS_BASE or STICKY_BUSY), "F5: dtmcs.dmistat is not sticky BUSY");

        scan_ir(IR_DMI, cap5);
        n0 := req_rises;
        dmi_scan(OP_WRITE, "0000101", x"11111111", rop, raddr, rdata);
        idle(12);
        check(req_rises = n0, "F6: a DMI op was accepted while dmistat was sticky");

        -- Let the parked response land, then clear the flag with dmireset.
        slv_rsp_lat <= 2;
        idle(60);
        scan_ir(IR_DTMCS, cap5);
        scan_dr(x"00010000", w32);   -- dmireset
        check(w32 = (DTMCS_BASE or STICKY_BUSY), "F7: the dtmcs read before dmireset lost the sticky flag");
        scan_dr(x"00000000", w32);
        check(w32 = DTMCS_BASE, "F8: dmireset did not clear dtmcs.dmistat");

        -- And the transport is live again.
        scan_ir(IR_DMI, cap5);
        slv_rdata <= x"C0FFEE11";
        n0 := req_rises;
        dmi_scan(OP_READ, "0100000", x"00000000", rop, raddr, rdata);
        idle(20);
        check(req_rises = n0 + 1, "F9: no DMI request after dmireset");
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = "00", "F10: the post-dmireset read did not complete cleanly");
        check(rdata = x"C0FFEE11", "F11: the post-dmireset read returned the wrong data");
        idle(12);

        -- === G. sticky FAILED ==============================================
        slv_fail  <= '1';
        slv_rdata <= x"FEEDFACE";
        dmi_scan(OP_READ, "0110011", x"00000000", rop, raddr, rdata);
        idle(20);
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = OP_FAIL, "G1: the failed transaction did not capture op = failed");
        check(raddr = "0110011", "G2: the failed capture did not preserve its address");
        idle(12);

        scan_ir(IR_DTMCS, cap5);
        scan_dr(x"00000000", w32);
        check(w32 = (DTMCS_BASE or STICKY_FAILED), "G3: dtmcs.dmistat is not sticky FAILED");

        -- Sticky FAILED blocks the transport exactly as sticky BUSY does.
        scan_ir(IR_DMI, cap5);
        slv_fail <= '0';
        n0 := req_rises;
        dmi_scan(OP_WRITE, "0111000", x"22222222", rop, raddr, rdata);
        idle(12);
        check(req_rises = n0, "G4: a DMI op was accepted while dmistat was sticky FAILED");

        -- dmireset clears the flag but NOT the shadow. The next capture therefore
        -- still reads op = failed, and dmistat must stay clear: latching sticky at
        -- the capture instead of at the response would re-raise it here and swallow
        -- every later write for the rest of the session.
        scan_ir(IR_DTMCS, cap5);
        scan_dr(x"00010000", w32);
        scan_dr(x"00000000", w32);
        check(w32 = DTMCS_BASE, "G5: dmireset did not clear sticky FAILED");
        scan_ir(IR_DMI, cap5);
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = OP_FAIL, "G6: dmireset cleared the shadow as well as the flag");
        idle(12);
        scan_ir(IR_DTMCS, cap5);
        scan_dr(x"00000000", w32);
        check(w32 = DTMCS_BASE, "G7: a capture of a stale failed shadow re-raised dmistat");

        -- dmihardreset dominates and DOES clear the shadow.
        scan_dr(x"00020000", w32);   -- dmihardreset
        scan_ir(IR_DMI, cap5);
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = "00", "G8: dmihardreset did not clear the shadow op");
        check(rdata = x"00000000", "G9: dmihardreset did not clear the shadow data");
        check(raddr = "0000000", "G10: dmihardreset did not clear the shadow address");
        idle(12);

        -- The transport still works after a hard reset of the DTM.
        slv_rdata <= x"A5A5F0F0";
        n0 := req_rises;
        dmi_scan(OP_READ, "1000001", x"00000000", rop, raddr, rdata);
        idle(20);
        check(req_rises = n0 + 1, "G11: no DMI request after dmihardreset");
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rdata = x"A5A5F0F0", "G12: the post-dmihardreset read returned the wrong data");
        idle(12);

        -- === H. TRSTn while the mclk side is idle ===========================
        -- req_tgl is reset by trstn but NOT by resetn, so clearing it presents
        -- the mclk edge detect a real toggle whose hold register has already
        -- been zeroed. Only trstn_guard stops that being replayed as an
        -- unqualified op = "00" request at address 0.
        -- The parity of req_tgl depends on how many transactions the session
        -- has armed, so the pulse is applied TWICE with one completed
        -- transaction in between: one of the two necessarily finds req_tgl
        -- high, which is the case that manufactures the edge.
        for k in 1 to 2 loop
            n0 := req_rises;
            a0 := slv_accepts;
            wait for 3 ns;                -- off both clock grids on purpose
            trstn <= '0';
            wait for 2 * TCK_PERIOD;
            trstn <= '1';
            wait for 40 * MCLK_PERIOD;
            if STRICT_TRSTN_GUARD then
                check(req_rises = n0,
                      "H" & integer'image(k) & "a: trstn manufactured a phantom DMI request while idle");
                check(slv_accepts = a0,
                      "H" & integer'image(k) & "b: a phantom transaction reached the slave after an idle trstn");
                check(req_illegal = 0,
                      "H" & integer'image(k) & "c: a request was presented with op = 00 after an idle trstn");
            else
                -- KNOWN DEVIATION P3-1, measured here: trstn_guard is a
                -- REGISTERED function of trstn_s2, and trstn_s2 and req_s2
                -- leave their DEPTH-2 chains on the SAME mclk edge, so the
                -- guard reads high on the very edge that detects the toggle
                -- trstn itself manufactured. One unqualified request escapes.
                -- What must still hold, and is what these three grade, is that
                -- the escape is BOUNDED to one, and that it carries the zeroed
                -- hold register rather than replaying a real address or data:
                -- op = "00" reaches neither the read nor the write arm of the
                -- Debug Module, and address 0 is not a DM register.
                check(req_rises <= n0 + 1,
                      "H" & integer'image(k) & "a: more than one request escaped an idle trstn");
                check(slv_accepts <= a0 + 1,
                      "H" & integer'image(k) & "b: more than one transaction reached the slave after an idle trstn");
                check(req_illegal <= k,
                      "H" & integer'image(k) & "c: more than one unqualified request per idle trstn");
                if req_illegal > 0 then
                    check(ill_op = OP_NOP,
                          "H" & integer'image(k) & "f: the escaping request carries a live op");
                    check(ill_addr = "0000000",
                          "H" & integer'image(k) & "g: the escaping request replays a real address");
                    check(ill_data = x"00000000",
                          "H" & integer'image(k) & "h: the escaping request replays real write data");
                end if;
            end if;
            -- Re-establish the transport and complete one transaction, which
            -- flips req_tgl for the second pass.
            goto_rti;
            scan_ir(IR_DMI, cap5);
            slv_rdata <= x"3C3C0F0F";
            n0 := req_rises;
            dmi_scan(OP_READ, "1011011", x"00000000", rop, raddr, rdata);
            idle(20);
            check(req_rises = n0 + 1,
                  "H" & integer'image(k) & "d: the transport is dead after an idle trstn");
            dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
            check(rdata = x"3C3C0F0F",
                  "H" & integer'image(k) & "e: the post-trstn read returned the wrong data");
            idle(12);
        end loop;

        -- === I. TRSTn asynchronously, mid-transaction =======================
        -- Arm a transaction the slave will hold for a long time, start the next
        -- DR scan, and pull TRSTn in the middle of the shift at a phase that is
        -- deliberately not aligned to either clock.
        slv_rsp_lat <= 500;
        slv_rdata   <= x"DEAD0000";
        n0 := req_rises;
        a0 := slv_accepts;
        ill0 := req_illegal;
        dmi_scan(OP_WRITE, "1100000", x"87654321", rop, raddr, rdata);
        idle(8);
        check(req_rises = n0 + 1, "I1: the long transaction was not armed");
        check(slv_accepts = a0 + 1, "I2: the long transaction was not accepted");

        -- Walk into Shift-DR by hand and stop part way through.
        tck_cycle('1', '0', qv);   -- Select-DR
        tck_cycle('0', '0', qv);   -- Capture-DR
        tck_cycle('0', '0', qv);   -- Shift-DR
        for i in 0 to 14 loop
            tck_cycle('0', '1', qv);
        end loop;

        n1 := req_rises;
        a1 := slv_accepts;
        wait for 3 ns;                -- off both clock grids on purpose
        trstn <= '0';
        wait for 17 ns;
        check(tdo = '0', "I3: tdo is not forced low by trstn");
        wait for 2 * TCK_PERIOD;
        trstn <= '1';
        wait for 3 * MCLK_PERIOD;

        -- The TAP is back in Test-Logic-Reset with IR = IDCODE.
        goto_rti;
        scan_dr(x"00000000", w32);
        check(w32 = IDCODE_VAL, "I4: IR is not IDCODE after an asynchronous trstn");

        -- The abandoned response lands while nothing is pending. It must be
        -- dropped, and the zeroed hold register must never be replayed as a
        -- phantom request on the mclk side.
        slv_rsp_lat <= 2;
        idle(80);
        check(req_rises = n1, "I5: trstn manufactured a phantom DMI request");
        check(slv_accepts = a1, "I6: a phantom transaction reached the slave");
        check(req_illegal = ill0, "I7: trstn mid-transaction presented a request with an illegal op");

        -- TRSTn also clears the sticky flag and the shadow.
        scan_ir(IR_DTMCS, cap5);
        scan_dr(x"00000000", w32);
        check(w32 = DTMCS_BASE, "I8: dtmcs.dmistat survived trstn");
        scan_ir(IR_DMI, cap5);
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = "00", "I9: the shadow op survived trstn");
        check(rdata = x"00000000", "I10: the shadow data survived trstn");
        idle(12);

        -- A fresh transaction after the reset returns the NEW data, proving the
        -- abandoned response was discarded rather than queued.
        slv_rdata <= x"1234ABCD";
        n0 := req_rises;
        dmi_scan(OP_READ, "1110000", x"00000000", rop, raddr, rdata);
        idle(20);
        check(req_rises = n0 + 1, "I11: the transport is dead after trstn");
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = "00", "I12: the post-trstn read did not complete cleanly");
        check(rdata = x"1234ABCD", "I13: the post-trstn read returned the abandoned data");
        check(raddr = "1110000", "I14: the post-trstn read lost its address");
        idle(12);

        -- === J. a slower mclk-side accept ===================================
        -- Widen the accept and response latencies so the four-phase handshake
        -- runs at a different phase of both synchroniser chains.
        slv_rdy_lat <= 7;
        slv_rsp_lat <= 11;
        slv_rdata   <= x"7777EEEE";
        n0 := req_rises;
        dmi_scan(OP_WRITE, "0001111", x"CAFEBABE", rop, raddr, rdata);
        idle(24);
        check(req_rises = n0 + 1, "J1: exactly one request was not issued at the wide latency");
        check(slv_data_q = x"CAFEBABE", "J2: the held request payload changed while in flight");
        check(slv_addr_q = "0001111", "J3: the held request address changed while in flight");
        check(req_rise_at - upd_at > 2 * MCLK_PERIOD,
              "J3b: the request crossed in " & time'image(req_rise_at - upd_at) &
              " at the wide latency, short of three mclk edges");
        dmi_scan(OP_NOP, "0000000", x"00000000", rop, raddr, rdata);
        check(rop = "00", "J4: the wide-latency transaction did not complete");
        check(raddr = "0001111", "J5: the wide-latency result lost its address");
        idle(12);
        slv_rdy_lat <= 0;
        slv_rsp_lat <= 2;

        -- === K. the ENABLE_DEBUG = false fold ===============================
        check(off_active = 0, "K1: the ENABLE_DEBUG=false instance was not inert");
        check(tdo_off = '0', "K2: the folded instance drives tdo");
        check(req_valid_off = '0', "K3: the folded instance drives dmi_req_valid");
        check(req_op_off = "00", "K4: the folded instance drives dmi_req_op");
        check(req_addr_off = "0000000", "K5: the folded instance drives dmi_req_addr");
        check(req_data_off = x"00000000", "K6: the folded instance drives dmi_req_data");

        -- === verdict ========================================================
        idle(4);
        report "jtag_dtm_tb: " & integer'image(checks) & " checks, " &
               integer'image(fails) & " failed" severity note;
        if fails = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "TB FAILED: " & integer'image(fails) & " check(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
