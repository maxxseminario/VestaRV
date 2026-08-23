/* =============================================================================
   dbg_module_tb.vhd
   =============================================================================
   Debug Module UNIT bench: it binds entity work.debug_module directly and grades abstractauto (0x18) and the dmstatus havereset lifecycle.
   The whole source closure is debug_module.vhd, so unlike the MCU-level dbg_dmi_tb this file needs no vendor macro, no boot image and no flash model, and it runs under GHDL.
   Two models stand in for the rest of the chip: a 128-word shared-window RAM on the master port, and a token-protocol hart that plays the trampoline's half of the FLAGS handshake.
   The hart model does NOT execute the synthesized abstract body; it publishes the tokens the Debug Module waits on and stamps a COMMAND COUNTER into data0, which is what makes "the command ran again" observable from the DMI side.
   PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity dbg_module_tb is
end entity;

architecture sim of dbg_module_tb is

    -- Two harts is the smallest count that separates "the selected hart" from "some other hart", which every per-hart check below needs.
    constant NH      : integer := 2;
    constant SH_AW_G : integer := 15;

    constant clk_period : time := (1 sec) / 24000000;   -- 24 MHz mclk

    /* The DUT's band, in the arbiter's word unit, recomputed here from the same byte addresses the generics carry.
       DATA0 sits at the bottom, FLAGS 32 words above it and the entry page 64 words above that, and the entry page is 64 words long.
       So the whole band is 128 words wide and the RAM model below is exactly that size, which turns a stray master address into an index fault rather than a silent aliased write. */
    constant W_DATA0  : integer := 16#10680# / 4;
    constant OFF_DATA0: integer := 0;
    constant OFF_FLAGS: integer := (16#10700# / 4) - W_DATA0;
    constant BAND_W   : integer := 128;

    -- FLAGS[h] handshake tokens; these are debug_module.vhd's own constants and the two files must agree exactly or the handshake never completes.
    constant TOK_HALTED : integer := 1;
    constant TOK_RESUME : integer := 2;
    constant TOK_GO     : integer := 4;
    constant TOK_DONE   : integer := 12;

    -- DMI register word addresses.
    constant A_DATA0     : integer := 16#04#;
    constant A_DMCONTROL : integer := 16#10#;
    constant A_DMSTATUS  : integer := 16#11#;
    constant A_ABSTRACTCS: integer := 16#16#;
    constant A_COMMAND   : integer := 16#17#;
    constant A_ABSTAUTO  : integer := 16#18#;
    constant A_PROGBUF0  : integer := 16#20#;
    constant A_PROGBUF1  : integer := 16#21#;

    constant OP_READ  : std_logic_vector(1 downto 0) := "01";
    constant OP_WRITE : std_logic_vector(1 downto 0) := "10";
    constant RSP_OK   : std_logic_vector(1 downto 0) := "00";

    -- abstractcs.cmderr encodings this bench expects.
    constant CMDERR_BUSY    : integer := 1;
    constant CMDERR_NOTSUP  : integer := 2;
    constant CMDERR_HALTRES : integer := 4;

    /* One legal access-register command: cmdtype 0, aarsize 2 (32 bit), transfer 1, write 0, regno 0x100A (x10).
       Nothing here depends on WHICH register it names, only that the word passes the DM's accept guards, because the hart model answers every command the same way. */
    constant CMD_READ_A0 : std_logic_vector(31 downto 0) := x"0022100A";

    -- The value the hart model stamps into data0, one higher per execution, so a debugger read tells the bench how many times the command has run.
    constant DATA_BASE : integer := 16#0A5E0000#;

    -- Budgets: bounded everywhere, because a bench that can hang promises evidence that never arrives.
    constant W_XACT : integer := 2000;   -- clk cycles per DMI phase
    constant N_BUSY : integer := 400;    -- abstractcs polls while busy

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal done   : boolean := false;
    signal fails  : integer := 0;
    signal checks : integer := 0;
    signal dmi_dead : boolean := false;

    -- The DMI port under test.
    signal dmi_req_valid : std_logic := '0';
    signal dmi_req_op    : std_logic_vector(1 downto 0) := "00";
    signal dmi_req_addr  : std_logic_vector(6 downto 0) := (others => '0');
    signal dmi_req_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal dmi_req_ready : std_logic;
    signal dmi_rsp_valid : std_logic;
    signal dmi_rsp_data  : std_logic_vector(31 downto 0);
    signal dmi_rsp_op    : std_logic_vector(1 downto 0);

    -- Per-hart run control.
    signal dbg_haltreq      : std_logic_vector(NH-1 downto 0);
    signal dbg_resethaltreq : std_logic_vector(NH-1 downto 0);
    signal dbg_halted       : std_logic_vector(NH-1 downto 0) := (others => '0');
    -- Driven by the bench: this is the "isolated or held in reset" wire the DM reads hart reset out of.
    signal hart_unavail     : std_logic_vector(NH-1 downto 0) := (others => '0');

    -- The shared-bus master port.
    signal m_req   : std_logic;
    signal m_we    : std_logic_vector(3 downto 0);
    signal m_addr  : std_logic_vector(SH_AW_G-1 downto 0);
    signal m_wdata : std_logic_vector(31 downto 0);
    signal m_gnt   : std_logic := '0';
    signal m_done  : std_logic := '0';
    signal m_rdata : std_logic_vector(31 downto 0) := (others => '0');

    -- How many times the hart model has executed a dispatched command; the bench grades autoexec against this.
    signal go_count : integer := 0;

begin

    clk_gen: process
    begin
        if done then wait; end if;
        clk <= '0'; wait for clk_period / 2;
        clk <= '1'; wait for clk_period / 2;
    end process;

    dut: entity work.debug_module
        generic map (
            ENABLE_DEBUG => true,
            NHARTS       => NH,
            SH_AW        => SH_AW_G,
            DATA0_ADDR   => x"00010680",
            FLAGS_ADDR   => x"00010700",
            ENTRY_ADDR   => x"00010780"
        )
        port map (
            clk    => clk,
            resetn => resetn,
            dmi_req_valid => dmi_req_valid,
            dmi_req_op    => dmi_req_op,
            dmi_req_addr  => dmi_req_addr,
            dmi_req_data  => dmi_req_data,
            dmi_req_ready => dmi_req_ready,
            dmi_rsp_valid => dmi_rsp_valid,
            dmi_rsp_data  => dmi_rsp_data,
            dmi_rsp_op    => dmi_rsp_op,
            dbg_haltreq      => dbg_haltreq,
            dbg_resethaltreq => dbg_resethaltreq,
            dbg_halted       => dbg_halted,
            hart_unavail     => hart_unavail,
            m_req   => m_req,
            m_we    => m_we,
            m_addr  => m_addr,
            m_wdata => m_wdata,
            m_gnt   => m_gnt,
            m_done  => m_done,
            m_rdata => m_rdata
        );

    /* ------------------------------------------------------------------
       THE REST OF THE CHIP, in one process because the RAM and the hart share the same storage.
       The bus half answers one master transaction per request with grant and done together, which is the fastest legal shape of the arbiter contract and the one that stresses the DM's own gap cycle.
       The hart half plays the trampoline's side of the FLAGS handshake: it publishes HALTED after entering debug mode, turns a GO into a DONE, re-enters after the DM has read that DONE, and clears itself on RESUME.
       Re-entry is triggered by the DM's OWN read of the DONE token rather than by a delay, so the bench cannot race the poll loop and cannot be tuned into passing.
       ------------------------------------------------------------------ */
    chip_model: process(clk, resetn)
        type mem_t is array (0 to BAND_W-1) of std_logic_vector(31 downto 0);
        type hstate_t is (H_RUN, H_ENTER, H_IDLE, H_EXEC, H_DONE, H_REENTER);
        type hstate_arr is array (0 to NH-1) of hstate_t;
        type hcnt_arr is array (0 to NH-1) of integer;
        variable mem    : mem_t;
        variable hs     : hstate_arr;
        variable hcnt   : hcnt_arr;
        variable served : boolean;
        variable off    : integer;
        variable n      : integer;
        -- Set for one pass when the DM reads a hart's FLAGS word and gets DONE back; that read is what licences the re-entry.
        variable donerd : std_logic_vector(NH-1 downto 0);
        -- The token entry and execution latencies, both far shorter than the DM's poll bound and both longer than one bus transaction.
        constant T_ENTER : integer := 20;
        constant T_EXEC  : integer := 20;
        constant T_REENT : integer := 20;
    begin
        if resetn = '0' then
            mem    := (others => (others => '0'));
            served := false;
            donerd := (others => '0');
            for i in 0 to NH-1 loop
                hs(i)   := H_RUN;
                hcnt(i) := 0;
            end loop;
            m_gnt      <= '0';
            m_done     <= '0';
            m_rdata    <= (others => '0');
            dbg_halted <= (others => '0');
            go_count   <= 0;
        elsif rising_edge(clk) then
            m_gnt  <= '0';
            m_done <= '0';
            donerd := (others => '0');

            -- ---- the shared-window RAM -------------------------------
            if m_req = '1' and not served then
                off := conv_integer(m_addr) - W_DATA0;
                assert off >= 0 and off < BAND_W
                    report "dbg_module_tb: master address outside the claimed "
                         & "debug band -- CHECK FAILED: master band"
                    severity failure;
                if m_we = "0000" then
                    m_rdata <= mem(off);
                    for i in 0 to NH-1 loop
                        if off = OFF_FLAGS + i
                           and mem(off) = conv_std_logic_vector(TOK_DONE, 32) then
                            donerd(i) := '1';
                        end if;
                    end loop;
                else
                    mem(off) := m_wdata;
                    m_rdata  <= (others => '0');
                end if;
                m_gnt  <= '1';
                m_done <= '1';
                served := true;
            elsif m_req = '0' then
                served := false;
            end if;

            -- ---- the token-protocol hart -----------------------------
            for i in 0 to NH-1 loop
                case hs(i) is
                    -- Running: a halt request is taken, and dbg_halted rises well BEFORE the token appears, which is the ordering the DM's handoff wait exists for.
                    when H_RUN =>
                        if dbg_haltreq(i) = '1' then
                            dbg_halted(i) <= '1';
                            hcnt(i) := T_ENTER;
                            hs(i)   := H_ENTER;
                        end if;
                    when H_ENTER =>
                        if hcnt(i) > 0 then
                            hcnt(i) := hcnt(i) - 1;
                        else
                            mem(OFF_FLAGS + i) := conv_std_logic_vector(TOK_HALTED, 32);
                            hs(i) := H_IDLE;
                        end if;
                    -- Parked in the trampoline's poll loop, waiting for the DM to dispatch something.
                    when H_IDLE =>
                        if mem(OFF_FLAGS + i) = conv_std_logic_vector(TOK_GO, 32) then
                            hcnt(i) := T_EXEC;
                            hs(i)   := H_EXEC;
                        elsif mem(OFF_FLAGS + i) = conv_std_logic_vector(TOK_RESUME, 32) then
                            mem(OFF_FLAGS + i) := (others => '0');
                            dbg_halted(i) <= '0';
                            hs(i) := H_RUN;
                        end if;
                    /* Executing: the counter stamp into data0 is this model's whole answer, and it is what makes a re-issued command visible to a debugger that can only read registers.
                       The stamp lands BEFORE the DONE token, mirroring the real epilogue's order, so a DM that reported success early would be caught by the data0 value rather than by the counter alone. */
                    when H_EXEC =>
                        if hcnt(i) > 0 then
                            hcnt(i) := hcnt(i) - 1;
                        else
                            n := go_count + 1;
                            go_count <= n;
                            mem(OFF_DATA0) := conv_std_logic_vector(DATA_BASE + n, 32);
                            mem(OFF_FLAGS + i) := conv_std_logic_vector(TOK_DONE, 32);
                            hs(i) := H_DONE;
                        end if;
                    when H_DONE =>
                        if donerd(i) = '1' then
                            hcnt(i) := T_REENT;
                            hs(i)   := H_REENTER;
                        end if;
                    -- The epilogue's ebreak re-enters the trampoline, which republishes HALTED; without this the DM's next handoff wait would never be satisfied.
                    when H_REENTER =>
                        if hcnt(i) > 0 then
                            hcnt(i) := hcnt(i) - 1;
                        else
                            mem(OFF_FLAGS + i) := conv_std_logic_vector(TOK_HALTED, 32);
                            hs(i) := H_IDLE;
                        end if;
                end case;
            end loop;
        end if;
    end process;

    -- A bench that can hang promises evidence that never arrives, so this is the belt for anything the per-loop bounds cannot see.
    watchdog: process
    begin
        wait for 50 ms;
        if not done then
            report "dbg_module_tb: WATCHDOG. CHECK FAILED: watchdog"
                severity note;
            report "dbg_module_tb: WATCHDOG" severity failure;
        end if;
        wait;
    end process;

    stim: process

        -- Grade one check, counting it either way.
        procedure chk(cond : boolean; msg : string) is
        begin
            checks <= checks + 1;
            if cond then
                report "CHECK ok: " & msg severity note;
            else
                -- Severity WARNING, not error: an error stops the run at the first failure, hiding whether the rest would have failed too.
                report "CHECK FAILED: " & msg severity warning;
                fails <= fails + 1;
            end if;
            wait for 0 ns;
        end procedure;

        -- ONE DMI transaction: valid is held until ready is sampled high, then the one-shot response is collected.
        procedure dmi_x(op    : in  std_logic_vector(1 downto 0);
                        addr  : in  integer;
                        wdata : in  std_logic_vector(31 downto 0);
                        rop   : out std_logic_vector(1 downto 0);
                        rdata : out std_logic_vector(31 downto 0)) is
            variable accepted : boolean := false;
            variable got      : boolean := false;
        begin
            if dmi_dead then
                rop := "11"; rdata := (others => '0');
                return;
            end if;
            wait until falling_edge(clk);
            dmi_req_addr  <= conv_std_logic_vector(addr, 7);
            dmi_req_data  <= wdata;
            dmi_req_op    <= op;
            dmi_req_valid <= '1';
            for i in 0 to W_XACT loop
                wait until falling_edge(clk);
                if dmi_req_ready = '1' then accepted := true; exit; end if;
            end loop;
            dmi_req_valid <= '0';
            dmi_req_op    <= "00";
            rop := "11"; rdata := (others => '0');
            if not accepted then
                report "DMI: no req_ready inside budget -- port latched DEAD"
                    severity warning;
                dmi_dead <= true;
                return;
            end if;
            for i in 0 to W_XACT loop
                wait until falling_edge(clk);
                if dmi_rsp_valid = '1' then
                    rop := dmi_rsp_op; rdata := dmi_rsp_data; got := true;
                    exit;
                end if;
            end loop;
            if not got then
                report "DMI: no rsp_valid inside budget" severity warning;
            end if;
        end procedure;

        procedure dmi_rd(addr : in integer; d : out std_logic_vector(31 downto 0);
                         rop : out std_logic_vector(1 downto 0)) is
            variable rr : std_logic_vector(1 downto 0);
            variable dd : std_logic_vector(31 downto 0);
        begin
            dmi_x(OP_READ, addr, (others => '0'), rr, dd);
            d := dd; rop := rr;
        end procedure;

        procedure dmi_wr(addr : in integer; d : in std_logic_vector(31 downto 0)) is
            variable rr : std_logic_vector(1 downto 0);
            variable dd : std_logic_vector(31 downto 0);
        begin
            dmi_x(OP_WRITE, addr, d, rr, dd);
        end procedure;

        -- Field extract from a DMI word.
        -- The temporary is THIRTY-ONE bits, not 32: conv_integer rejects a 32-bit argument outright, whatever its value.
        function fld(v : std_logic_vector(31 downto 0); hi, lo : integer) return integer is
            variable t : std_logic_vector(30 downto 0) := (others => '0');
        begin
            t(hi-lo downto 0) := v(hi downto lo);
            return conv_integer(t);
        end function;

        -- Build a dmcontrol write word; dmactive is always kept set, because clearing it resets the DM and must be a deliberate act.
        function dmcontrol_w(hartsel : integer; extra : std_logic_vector(31 downto 0))
                return std_logic_vector is
            variable v : std_logic_vector(31 downto 0);
        begin
            v := extra;
            v(25 downto 16) := conv_std_logic_vector(hartsel, 10);
            v(0) := '1';
            return v;
        end function;

        -- Spin on abstractcs.busy until the command retires, then hand back the whole word so the caller can read cmderr out of the same sample.
        procedure wait_busy(d : out std_logic_vector(31 downto 0)) is
            variable dd : std_logic_vector(31 downto 0);
            variable rr : std_logic_vector(1 downto 0);
        begin
            for i in 0 to N_BUSY loop
                dmi_rd(A_ABSTRACTCS, dd, rr);
                exit when fld(dd, 12, 12) = 0;
            end loop;
            d := dd;
        end procedure;

        -- Clear whatever cmderr is standing, so the next check starts from a known state.
        procedure clear_cmderr is
        begin
            dmi_wr(A_ABSTRACTCS, x"00000700");
        end procedure;

        variable d, d2 : std_logic_vector(31 downto 0);
        variable rop   : std_logic_vector(1 downto 0);
        variable g0, g1: integer;

    begin
        hart_unavail <= (others => '0');
        resetn <= '0';
        wait for clk_period * 10;
        resetn <= '1';
        wait for clk_period * 10;

        /* ==============================================================
           G1-G3: the havereset lifecycle out of reset, graded BEFORE anything else touches dmcontrol.
           ============================================================== */
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(rop = RSP_OK, "G1a: dmstatus read returns op = success");
        chk(fld(d, 19, 19) = 1 and fld(d, 18, 18) = 1,
            "G1b: hart 0 reports havereset out of reset, on BOTH the all "
            & "and any bit -- the harts really did just reset");
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 1 and fld(d, 18, 18) = 1,
            "G1c: ...and so does hart 1");

        -- ackhavereset is dmcontrol bit 28 and it acts on the hart selected by the SAME write.
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, x"10000000"));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0 and fld(d, 18, 18) = 0,
            "G2: ackhavereset clears the selected hart's havereset");
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 1 and fld(d, 18, 18) = 1,
            "G3: ...and ONLY that hart's -- hart 0 is untouched by an ack "
            & "aimed at hart 1");
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, x"10000000"));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0, "G3b: hart 0 acks too, so the board is clean");

        /* ==============================================================
           A: the abstractauto register shape.
           ============================================================== */
        dmi_rd(A_ABSTAUTO, d, rop);
        chk(rop = RSP_OK and d = x"00000000",
            "A1: abstractauto reads zero out of reset");
        dmi_wr(A_ABSTAUTO, x"FFFFFFFF");
        dmi_rd(A_ABSTAUTO, d, rop);
        chk(d = x"00030001",
            "A2: abstractauto is WARL to the implemented words only -- "
            & "autoexecdata bit 0 (datacount 1) and autoexecprogbuf bits "
            & "17:16 (progbufsize 2), everything else hardwired zero");
        dmi_wr(A_ABSTAUTO, x"00020000");
        dmi_rd(A_ABSTAUTO, d, rop);
        chk(d = x"00020000",
            "A3: the two progbuf bits are INDEPENDENT -- writing only bit 17 "
            & "reads back only bit 17, so A2 is not a stuck all-ones");
        dmi_wr(A_ABSTAUTO, x"00000000");
        dmi_rd(A_ABSTAUTO, d, rop);
        chk(d = x"00000000", "A4: abstractauto clears again");

        /* ==============================================================
           E1: with abstractauto armed but NO command ever accepted, an access must not run anything.
           The DM has nothing to re-issue, and reporting NOT_SUPPORTED is the visible answer; silently doing nothing would look identical to a broken trigger.
           ============================================================== */
        dmi_wr(A_ABSTAUTO, x"00000001");
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        wait_busy(d);
        chk(go_count = g0,
            "E1a: an autoexec access with no accepted command runs nothing");
        chk(fld(d, 10, 8) = CMDERR_NOTSUP,
            "E1b: ...and says so with cmderr = NOT_SUPPORTED");
        clear_cmderr;
        dmi_wr(A_ABSTAUTO, x"00000000");

        /* ==============================================================
           Bring hart 0 into debug mode and run one ordinary abstract command, which is the precondition for every autoexec check below.
           ============================================================== */
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, x"80000000"));   -- haltreq
        for i in 0 to N_BUSY loop
            dmi_rd(A_DMSTATUS, d, rop);
            exit when fld(d, 9, 9) = 1;
        end loop;
        chk(fld(d, 9, 9) = 1 and fld(d, 8, 8) = 1,
            "B0: hart 0 halts on haltreq -- the precondition for the "
            & "abstract commands below");
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));

        g0 := go_count;
        dmi_wr(A_COMMAND, CMD_READ_A0);
        wait_busy(d);
        chk(fld(d, 10, 8) = 0, "B1a: an ordinary abstract command reports cmderr = 0");
        chk(go_count = g0 + 1, "B1b: ...and the hart executed it exactly once");
        dmi_rd(A_DATA0, d, rop);
        chk(d = conv_std_logic_vector(DATA_BASE + go_count, 32),
            "B1c: ...and data0 carries what that execution left");

        -- The control that stops every later check passing on an accident: with abstractauto clear, reading data0 is just a read.
        /* EVERY "nothing happened" CHECK BELOW WAITS OUT abstractcs.busy FIRST.
           A re-issued command takes hundreds of clocks and the counter only moves at its end, so sampling go_count straight after the access would read "unchanged" whether the trigger fired or not, and the check would pass against RTL that fires when it must not.
           wait_busy costs nothing in the correct case: busy is already low, so it returns on its first poll. */
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        dmi_rd(A_DATA0, d, rop);
        wait_busy(d2);
        chk(go_count = g0,
            "B2: with abstractauto CLEAR, data0 reads trigger nothing -- the "
            & "trigger is the register and not the access");

        /* ==============================================================
           B3-B5: autoexecdata on data0, which is the burst-read idiom a debugger uses to pull memory out through the program buffer.
           ============================================================== */
        dmi_wr(A_ABSTAUTO, x"00000001");
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        chk(d = conv_std_logic_vector(DATA_BASE + g0, 32),
            "B3a: an autoexec data0 read returns the value the PREVIOUS "
            & "execution left, not the one the re-issue is about to write");
        wait_busy(d2);
        chk(fld(d2, 10, 8) = 0, "B3b: ...the re-issued command reports cmderr = 0");
        chk(go_count = g0 + 1,
            "B3c: ...and it really ran again -- exactly once more");
        dmi_rd(A_DATA0, d, rop);
        chk(d = conv_std_logic_vector(DATA_BASE + g0 + 1, 32),
            "B4a: the next autoexec read hands back what the re-issue wrote");
        wait_busy(d2);
        chk(go_count = g0 + 2, "B4b: ...and triggers the one after it");

        -- A WRITE arms it too; that is the burst-WRITE idiom, and a read-only trigger would break memory writes through the program buffer.
        g1 := go_count;
        dmi_wr(A_DATA0, x"DEADBEEF");
        wait_busy(d2);
        chk(go_count = g1 + 1,
            "B5: an autoexec data0 WRITE re-issues the command as well");

        dmi_wr(A_ABSTAUTO, x"00000000");
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        wait_busy(d2);
        chk(go_count = g0,
            "B6: clearing abstractauto disarms the trigger again");

        /* ==============================================================
           C: autoexecprogbuf, one bit per program-buffer word.
           ============================================================== */
        dmi_wr(A_ABSTAUTO, x"00010000");
        g0 := go_count;
        dmi_rd(A_PROGBUF0, d, rop);
        wait_busy(d2);
        chk(go_count = g0 + 1, "C1: a progbuf0 read with bit 16 set re-issues");
        g0 := go_count;
        dmi_wr(A_PROGBUF0, x"00000013");
        wait_busy(d2);
        chk(go_count = g0 + 1, "C2: a progbuf0 WRITE does too");
        g0 := go_count;
        dmi_rd(A_PROGBUF1, d, rop);
        wait_busy(d2);
        chk(go_count = g0,
            "C3: ...and progbuf1 does NOT, because its own bit is clear -- "
            & "the two words are armed separately");
        dmi_wr(A_ABSTAUTO, x"00020000");
        g0 := go_count;
        dmi_rd(A_PROGBUF1, d, rop);
        wait_busy(d2);
        chk(go_count = g0 + 1, "C4: bit 17 arms progbuf1, and only bit 17 does");
        dmi_wr(A_ABSTAUTO, x"00000000");

        /* ==============================================================
           D: what happens when the debugger touches these registers while a command is still running.
           ============================================================== */
        dmi_wr(A_ABSTAUTO, x"00000001");
        g0 := go_count;
        -- The re-issue is hundreds of cycles long, so the very next transaction lands inside the busy window.
        dmi_rd(A_DATA0, d, rop);
        dmi_wr(A_ABSTAUTO, x"00030001");
        dmi_rd(A_ABSTRACTCS, d, rop);
        chk(fld(d, 10, 8) = CMDERR_BUSY,
            "D1a: writing abstractauto while a command executes reports "
            & "cmderr = BUSY");
        wait_busy(d2);
        clear_cmderr;
        dmi_rd(A_ABSTAUTO, d, rop);
        chk(d = x"00000001",
            "D1b: ...and the write did NOT land -- the arming is unchanged");
        chk(go_count = g0 + 1,
            "D1c: ...and the refused write did not itself run a command");

        -- A data0 access while busy is an error the debug specification names, and it must NOT be counted as a trigger.
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        dmi_rd(A_DATA0, d, rop);
        wait_busy(d2);
        chk(fld(d2, 10, 8) = CMDERR_BUSY,
            "D2a: a data0 access while a command executes reports cmderr = BUSY");
        chk(go_count = g0 + 1,
            "D2b: ...and the refused access triggered NOTHING, so exactly one "
            & "command ran across the pair");

        /* ==============================================================
           E2: a standing cmderr suppresses the re-issue, because no abstract command starts while cmderr is set.
           ============================================================== */
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        wait_busy(d2);
        chk(go_count = g0,
            "E2: with cmderr standing, an autoexec access starts nothing");
        clear_cmderr;
        dmi_wr(A_ABSTAUTO, x"00000000");

        /* ==============================================================
           F: abstractauto is DM state, so the DM's own reset must clear it.
           ============================================================== */
        dmi_wr(A_ABSTAUTO, x"00030001");
        dmi_wr(A_DMCONTROL, x"00000000");        -- dmactive low: reset the DM
        wait for clk_period * 20;
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        dmi_rd(A_ABSTAUTO, d, rop);
        chk(d = x"00000000",
            "F1: cycling dmactive clears abstractauto -- a stale autoexec bit "
            & "surviving a DM reset would fire a stale command");
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0 and fld(d, 18, 18) = 0,
            "F2: ...and does NOT manufacture a havereset for a hart that "
            & "never reset, because this DM observes hart reset directly");

        /* ==============================================================
           G4-G8: a hart that resets while the debugger is attached.
           hart_unavail is "isolated or held in reset", and the power controller un-isolates before it un-resets, so the falling edge of that wire is the reset release.
           ============================================================== */
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, x"10000000"));   -- start clean on hart 1
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0, "G4a: hart 1 starts this leg with havereset clear");

        hart_unavail(1) <= '1';
        wait for clk_period * 20;
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 13, 13) = 1 and fld(d, 12, 12) = 1,
            "G4b: a hart held in reset reads unavailable");
        hart_unavail(1) <= '0';
        wait for clk_period * 20;
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 1 and fld(d, 18, 18) = 1,
            "G5a: a hart that LEAVES RESET mid-session reports havereset -- "
            & "the DM learns of the reset without a per-hart reset input");
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 1,
            "G5b: ...and it is a LEVEL that stands until acknowledged, not a "
            & "one-shot a polling debugger can miss");
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0,
            "G5c: ...and it is hart 1's alone -- hart 0 reports nothing");
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, x"10000000"));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0, "G5d: ...and the acknowledge clears it");

        -- A reset that happens while the DM is parked is exactly the one a re-attaching debugger cannot learn about any other way.
        dmi_wr(A_DMCONTROL, x"00000000");
        wait for clk_period * 20;
        hart_unavail(1) <= '1';
        wait for clk_period * 20;
        hart_unavail(1) <= '0';
        wait for clk_period * 20;
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 1 and fld(d, 18, 18) = 1,
            "G6: a reset taken while dmactive was LOW is still reported once "
            & "the debugger re-arms the DM");

        /* G7: the same-cycle race between the acknowledge and a new reset.
           The DM is idle and quiet here, so a request driven at a falling edge is captured at the very next rising edge; dropping hart_unavail at that same falling edge puts the reset release and the acknowledge in ONE cycle.
           The acknowledge answers a reset the debugger has already read out of dmstatus, so a newer one arriving in the same cycle must survive it. */
        wait for clk_period * 40;
        wait until falling_edge(clk);
        hart_unavail(1)  <= '1';
        wait for clk_period * 20;
        wait until falling_edge(clk);
        dmi_req_addr  <= conv_std_logic_vector(A_DMCONTROL, 7);
        dmi_req_data  <= dmcontrol_w(1, x"10000000");
        dmi_req_op    <= OP_WRITE;
        dmi_req_valid <= '1';
        hart_unavail(1) <= '0';
        wait until falling_edge(clk);
        chk(dmi_req_ready = '1',
            "G7a: the acknowledge was captured in the very cycle the hart "
            & "left reset -- the precondition that makes G7b a race and not "
            & "an ordering");
        dmi_req_valid <= '0';
        dmi_req_op    <= "00";
        wait for clk_period * 40;
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 1 and fld(d, 18, 18) = 1,
            "G7b: the reset WINS that race -- an acknowledge landing in the "
            & "same cycle must not swallow a reset the debugger has not seen");
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, x"10000000"));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 19, 19) = 0, "G7c: ...and a LATER acknowledge does clear it");

        /* ==============================================================
           H: the proxy path still behaves, which is the regression the autoexec arming rides on.
           ============================================================== */
        dmi_wr(A_DATA0, x"5EED0D2A");
        dmi_rd(A_DATA0, d, rop);
        chk(rop = RSP_OK and d = x"5EED0D2A",
            "H1a: data0 still round-trips through the proxy");
        dmi_wr(A_DATA0, x"A5A5F00D");
        dmi_rd(A_DATA0, d, rop);
        chk(d = x"A5A5F00D", "H1b: ...and a SECOND value, so H1a is no constant");

        /* ==============================================================
           I: the re-issue re-checks that the hart is STILL HALTED, which is the guard a burst left armed across a resume runs into.
           Done last, because it ends with hart 0 running.
           ============================================================== */
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, x"40000000"));   -- resumereq
        for i in 0 to N_BUSY loop
            dmi_rd(A_DMSTATUS, d, rop);
            exit when fld(d, 11, 11) = 1;
        end loop;
        chk(fld(d, 11, 11) = 1 and fld(d, 17, 17) = 1,
            "I1: hart 0 resumes and sets resumeack -- the precondition for I2");
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        wait for clk_period * 40;
        dmi_wr(A_ABSTAUTO, x"00000001");
        g0 := go_count;
        dmi_rd(A_DATA0, d, rop);
        wait_busy(d2);
        chk(go_count = g0,
            "I2a: an autoexec access aimed at a hart that has since RESUMED "
            & "runs nothing");
        chk(fld(d2, 10, 8) = CMDERR_HALTRES,
            "I2b: ...and reports cmderr = HALT_RESUME, the same answer a "
            & "`command` write would have got");
        clear_cmderr;
        dmi_wr(A_ABSTAUTO, x"00000000");

        wait for clk_period * 20;
        report "dbg_module_tb: " & integer'image(checks) & " checks, "
             & integer'image(fails) & " failed" severity note;
        if fails = 0 and checks > 0 and not dmi_dead then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECK FAILED: run summary" severity warning;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
