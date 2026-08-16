-- jtag_dtm.vhd: the JTAG TAP and Debug Transport Module, one per chip at assembly level beside the Debug Module and never inside a tile.
-- A 16-state IEEE 1149.1 TAP, a 5-bit IR, four DRs (IDCODE, dtmcs, the 41-bit dmi, BYPASS), the sticky/dmireset machine, and the TCK-to-mclk crossing that turns one DR scan into one DMI transaction.
-- Contract: any unsupported IR selects BYPASS; dtmcs.dmistat is driven and sticky for FAILED as well as BUSY; dtmcs.idle is truthful; an Update-DR of dmi is ignored while dmistat is nonzero; dmihardreset resets TCK-side DTM state but does not force Test-Logic-Reset.
-- TRSTn resets the whole TCK-side DTM, while Test-Logic-Reset resets only the FSM and IR: dmireset exists precisely to clear the sticky flag.
-- ENABLE_DEBUG defaults false and folds the block away; every JTAG input defaults '0' and trstn '0' holds the TAP in reset, so an unconnected DTM is inert and issues nothing.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity jtag_dtm is
    generic (
        -- Fail-safe OFF at every declaration site.
        ENABLE_DEBUG : boolean := false;
        -- JTAG IDCODE, selected per chip by the generator (Castalia 0x1CA57EEF, Argus 0x1A265EEF: version 1, partnum, manufid 0x777, LSB 1).
        -- The declaration default is deliberately an invalid code, so a build that forgot to pass the real value announces itself instead of impersonating a chip.
        IDCODE       : std_logic_vector(31 downto 0) := x"00000001";
        -- dtmcs.idle [14:12], in TCK cycles: 7 covers the worst DMI latency as long as TCK stays at or below about 7 MHz against a 24 MHz mclk.
        -- A faster TCK or heavy arbiter contention can still return BUSY; that is not an error, the sticky-busy, dmireset, re-issue path handles it.
        IDLE_CYCLES  : natural range 0 to 7 := 0
    );
    port (
        -- ---- the five JTAG pins (TCK domain) -----------------------------
        -- Inputs carry defaults so an instantiation that leaves them unconnected stays legal and inert.
        tck   : in  std_logic := '0';
        tms   : in  std_logic := '0';
        tdi   : in  std_logic := '0';
        tdo   : out std_logic;
        trstn : in  std_logic := '0';   -- ASYNC, active low. '0' = TAP in reset

        -- ---- system side (mclk domain) -----------------------------------
        clk    : in  std_logic;                    -- free-running mclk
        resetn : in  std_logic;                    -- system reset: mclk SIDE ONLY

        -- ---- DMI master: drives the Debug Module's DMI port --------------
        dmi_req_valid : out std_logic;
        dmi_req_op    : out std_logic_vector(1 downto 0);   -- 01=read 10=write
        dmi_req_addr  : out std_logic_vector(6 downto 0);
        dmi_req_data  : out std_logic_vector(31 downto 0);
        dmi_req_ready : in  std_logic := '0';
        dmi_rsp_valid : in  std_logic := '0';
        dmi_rsp_data  : in  std_logic_vector(31 downto 0) := (others => '0');
        dmi_rsp_op    : in  std_logic_vector(1 downto 0) := "00"   -- 00=ok 10=failed
    );
end entity;

architecture rtl of jtag_dtm is

    -- ---- TAP states, the standard IEEE 1149.1 graph.
    -- Kept as an integer range so the state register is four flops and the transition table is one lookup.
    constant ST_TLR        : integer := 0;
    constant ST_RTI        : integer := 1;
    constant ST_SEL_DR     : integer := 2;
    constant ST_CAPTURE_DR : integer := 3;
    constant ST_SHIFT_DR   : integer := 4;
    constant ST_EXIT1_DR   : integer := 5;
    constant ST_PAUSE_DR   : integer := 6;
    constant ST_EXIT2_DR   : integer := 7;
    constant ST_UPDATE_DR  : integer := 8;
    constant ST_SEL_IR     : integer := 9;
    constant ST_CAPTURE_IR : integer := 10;
    constant ST_SHIFT_IR   : integer := 11;
    constant ST_EXIT1_IR   : integer := 12;
    constant ST_PAUSE_IR   : integer := 13;
    constant ST_EXIT2_IR   : integer := 14;
    constant ST_UPDATE_IR  : integer := 15;

    -- next[state][tms].
    type tap_next_t is array (0 to 15, 0 to 1) of integer range 0 to 15;
    constant TAP_NEXT : tap_next_t := (
        (1, 0),   (1, 2),   (3, 9),    (4, 5),
        (4, 5),   (6, 8),   (6, 7),    (4, 8),
        (1, 2),   (10, 0),  (11, 12),  (11, 12),
        (13, 15), (13, 14), (11, 15),  (1, 2));

    -- ---- IR, 5 bits: the debugger configs all use -irlen 5.
    constant IR_IDCODE : std_logic_vector(4 downto 0) := "00001";  -- 0x01, reset value
    constant IR_DTMCS  : std_logic_vector(4 downto 0) := "10000";  -- 0x10
    constant IR_DMI    : std_logic_vector(4 downto 0) := "10001";  -- 0x11
    constant IR_BYPASS : std_logic_vector(4 downto 0) := "11111";  -- 0x1F

    -- Selected DR: every unsupported opcode maps to BYPASS.
    constant SEL_IDCODE : integer := 0;
    constant SEL_DTMCS  : integer := 1;
    constant SEL_DMI    : integer := 2;
    constant SEL_BYPASS : integer := 3;

    -- ---- dmi DR geometry: op[1:0], data[33:2], address[40:34], so 41 bits = abits 7 + 34.
    constant DR_HI : integer := 40;
    constant OP_NOP     : std_logic_vector(1 downto 0) := "00";
    constant OP_FAILED  : std_logic_vector(1 downto 0) := "10";
    -- dmistat / captured-op encodings
    constant ST_NONE   : std_logic_vector(1 downto 0) := "00";
    constant ST_FAILED : std_logic_vector(1 downto 0) := "10";
    constant ST_BUSY   : std_logic_vector(1 downto 0) := "11";

    constant IDLE_SLV : std_logic_vector(2 downto 0) :=
        conv_std_logic_vector(IDLE_CYCLES, 3);

    -- ---- TCK domain (reset ONLY by trstn) -----------------------------
    signal tap_state : integer range 0 to 15;
    signal ir_r      : std_logic_vector(4 downto 0);   -- latched IR
    signal ir_sh     : std_logic_vector(4 downto 0);   -- IR shift register
    signal dr        : std_logic_vector(DR_HI downto 0);  -- shared DR shifter
    signal sticky    : std_logic_vector(1 downto 0);   -- dtmcs.dmistat
    signal pending   : std_logic;                      -- a request is in flight
    signal req_tgl   : std_logic;
    signal req_hold  : std_logic_vector(DR_HI downto 0);
    signal shadow    : std_logic_vector(DR_HI downto 0);  -- the DMI result
    signal rsp_s1, rsp_s2, rsp_s3 : std_logic;
    signal tdo_r     : std_logic;                      -- updated on TCK FALLING

    -- ---- mclk domain (reset by system resetn) -------------------------
    signal req_s1, req_s2, req_s3 : std_logic;
    signal rst_guard : std_logic_vector(2 downto 0);
    signal m_state   : integer range 0 to 2;
    constant M_IDLE : integer := 0;
    constant M_REQ  : integer := 1;
    constant M_RSP  : integer := 2;
    signal req_vld_r  : std_logic;
    signal rsp_op_h   : std_logic_vector(1 downto 0);
    signal rsp_data_h : std_logic_vector(31 downto 0);
    signal rsp_tgl    : std_logic;

    -- combinational
    signal sel     : integer range 0 to 3;
    signal dtmcs_w : std_logic_vector(31 downto 0);

    function ir_decode(ir : std_logic_vector(4 downto 0)) return integer is
    begin
        if ir = IR_IDCODE then
            return SEL_IDCODE;
        elsif ir = IR_DTMCS then
            return SEL_DTMCS;
        elsif ir = IR_DMI then
            return SEL_DMI;
        else
            return SEL_BYPASS;   -- BYPASS *and* every unsupported opcode
        end if;
    end function;

begin

    -- Knob-off fold: the off arm ties every output to its fail-safe value, so a debug-disabled instance carries no state and cannot reach the Debug Module.
    gen_dtm_off: if not ENABLE_DEBUG generate
        tdo           <= '0';
        dmi_req_valid <= '0';
        dmi_req_op    <= (others => '0');
        dmi_req_addr  <= (others => '0');
        dmi_req_data  <= (others => '0');
    end generate;

    gen_dtm: if ENABLE_DEBUG generate

        sel <= ir_decode(ir_r);

        -- dtmcs: version[3:0] = 1 and abits[9:4] = 7 give the base 0x71, with dmistat[11:10] and idle[14:12] driven on top.
        -- dmireset (16) and dmihardreset (17) are write-only strobes decoded at Update-DR and read back as zero, so they hold no flops.
        dtmcs_w(31 downto 15) <= (others => '0');
        dtmcs_w(14 downto 12) <= IDLE_SLV;
        dtmcs_w(11 downto 10) <= sticky;
        dtmcs_w(9 downto 4)   <= "000111";
        dtmcs_w(3 downto 0)   <= "0001";

        -- The TAP: one process, TCK rising, asynchronously reset by TRSTn.
        -- Keep the ordering: shift with the state the TAP is in before the edge, then advance, then run the entry action of the state just entered.
        tap_proc: process(tck, trstn)
            variable tmsi : integer range 0 to 1;
            variable nxt  : integer range 0 to 15;
        begin
            if trstn = '0' then
                -- TRSTn resets the WHOLE TCK-side DTM, not just the FSM.
                -- Clearing `pending` here is the discard mechanism: an abandoned transaction still completes on the mclk side and its response is dropped on arrival, keeping the toggle chains phase coherent.
                tap_state <= ST_TLR;
                ir_r      <= IR_IDCODE;
                ir_sh     <= (others => '0');
                dr        <= (others => '0');
                sticky    <= ST_NONE;
                pending   <= '0';
                req_tgl   <= '0';
                req_hold  <= (others => '0');
                shadow    <= (others => '0');
                rsp_s1    <= '0';
                rsp_s2    <= '0';
                rsp_s3    <= '0';
            elsif rising_edge(tck) then

                -- ---- response crossing: 2-FF synchroniser plus edge detect ---
                -- The payload is HELD in the mclk domain and sampled at the detected edge; never synchronise a bus per bit.
                -- The `pending` qualifier drops responses to abandoned transactions and absorbs the phantom edge a TRSTn-reset chain manufactures when rsp_tgl is '1'.
                rsp_s1 <= rsp_tgl;
                rsp_s2 <= rsp_s1;
                rsp_s3 <= rsp_s2;
                if (rsp_s2 /= rsp_s3) and pending = '1' then
                    -- Address bits are preserved from the request: a captured word carries the previous op's address verbatim.
                    shadow(DR_HI downto 34) <= req_hold(DR_HI downto 34);
                    shadow(33 downto 2)     <= rsp_data_h;
                    shadow(1 downto 0)      <= rsp_op_h;
                    pending                 <= '0';
                    -- Sticky FAILED must be latched HERE, when the response arrives, never at the capture that delivers it.
                    -- The shadow keeps its op until the next response and dmireset does not clear it, so a capture-time latch would re-raise dmistat from the stale op and swallow every later DMI write for the rest of the session.
                    if rsp_op_h = OP_FAILED then
                        sticky <= ST_FAILED;
                    end if;
                end if;

                -- ---- shift, using the state the TAP is in NOW -------------
                if tap_state = ST_SHIFT_DR then
                    if sel = SEL_DMI then
                        dr <= tdi & dr(DR_HI downto 1);
                    elsif sel = SEL_BYPASS then
                        dr(0) <= tdi;
                    else
                        -- IDCODE / dtmcs: a 32-bit chain inside the shared shifter, so TDI is injected at bit 31 and the scan length is 32.
                        dr(31 downto 0) <= tdi & dr(31 downto 1);
                    end if;
                end if;
                if tap_state = ST_SHIFT_IR then
                    ir_sh <= tdi & ir_sh(4 downto 1);
                end if;

                -- ---- advance ---------------------------------------------
                tmsi := 0;
                if tms = '1' then
                    tmsi := 1;
                end if;
                nxt := TAP_NEXT(tap_state, tmsi);
                tap_state <= nxt;

                -- ---- entry actions of the state just entered --------------
                if nxt = ST_TLR then
                    -- Test-Logic-Reset sets IR = IDCODE and nothing else: it must not clear the sticky flag or the shadow, which is what dmireset is for.
                    ir_r <= IR_IDCODE;

                elsif nxt = ST_CAPTURE_IR then
                    -- 1149.1 mandates bits [1:0] = "01" in the Capture-IR value; 0x01 satisfies it and is also the harmless IR.
                    ir_sh <= "00001";

                elsif nxt = ST_UPDATE_IR then
                    -- Update-IR: the shifted value becomes the live IR.
                    ir_r <= ir_sh;

                elsif nxt = ST_CAPTURE_DR then
                    if sel = SEL_IDCODE then
                        -- CONSTANT, loaded at Capture-DR: zero storage, so shifting anything through it changes nothing.
                        dr <= "000000000" & IDCODE;
                    elsif sel = SEL_DTMCS then
                        dr <= "000000000" & dtmcs_w;
                    elsif sel = SEL_DMI then
                        if pending = '1' or sticky = ST_BUSY then
                            -- The whole 41-bit DR captures literal 3 (address 0, data 0, op = busy), not the previous result with op = busy, and the capture is what makes the flag sticky.
                            dr     <= (1 => '1', 0 => '1', others => '0');
                            sticky <= ST_BUSY;
                        else
                            -- The previous op's result, address preserved, and this arm must not touch dmistat.
                            -- A capture can still read a failed result as FAILED while dmistat already says 2: the literal-3 substitution above is gated on in-flight or sticky BUSY, never on sticky FAILED.
                            dr <= shadow;
                        end if;
                    else
                        dr <= (others => '0');   -- BYPASS captures 0
                    end if;

                elsif nxt = ST_UPDATE_DR then
                    if sel = SEL_DTMCS then
                        -- Write-only strobes: dmihardreset dominates and adds the shadow clear.
                        -- Neither resets the Debug Module and neither forces Test-Logic-Reset.
                        if dr(17) = '1' then
                            sticky  <= ST_NONE;
                            pending <= '0';
                            shadow  <= (others => '0');
                        elsif dr(16) = '1' then
                            -- dmireset clears the sticky flag and abandons the outstanding transaction, the same discard the response block enforces.
                            sticky  <= ST_NONE;
                            pending <= '0';
                        end if;

                    elsif sel = SEL_DMI then
                        if dr(1 downto 0) /= OP_NOP then
                            -- A NOP scan never arms anything, which is what makes a capture-only scan safe.
                            if sticky /= ST_NONE then
                                null;   -- dropped while dmistat is sticky
                            elsif pending = '1' then
                                -- An access while a transaction is in flight is dropped and raises sticky busy, which is the only way the debugger learns its scan was lost.
                                sticky <= ST_BUSY;
                            else
                                req_hold <= dr;
                                req_tgl  <= not req_tgl;
                                pending  <= '1';
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end process;

        -- TDO changes on the TCK falling edge, LSB first, and is held between shift states rather than forced low so the chain stays quiet outside its shift window.
        tdo_proc: process(tck, trstn)
        begin
            if trstn = '0' then
                tdo_r <= '0';
            elsif falling_edge(tck) then
                if tap_state = ST_SHIFT_DR then
                    tdo_r <= dr(0);
                elsif tap_state = ST_SHIFT_IR then
                    tdo_r <= ir_sh(0);
                end if;
            end if;
        end process;

        tdo <= tdo_r;

        -- The mclk side: request synchroniser, the one-shot master, and the response hold.
        -- Reset by system resetn and deliberately not by the TAP's, so a debugger stays attachable while the chip is held in reset.
        mst_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                req_s1     <= '0';
                req_s2     <= '0';
                req_s3     <= '0';
                rst_guard  <= (others => '0');
                m_state    <= M_IDLE;
                req_vld_r  <= '0';
                rsp_op_h   <= (others => '0');
                rsp_data_h <= (others => '0');
                rsp_tgl    <= '0';
            elsif rising_edge(clk) then
                req_s1 <= req_tgl;
                req_s2 <= req_s1;
                req_s3 <= req_s2;
                rst_guard <= rst_guard(1 downto 0) & '1';

                -- M_IDLE: wait for a real request edge, held off until rst_guard says the synchroniser holds three post-reset samples.
                -- Keep the guard: req_tgl is not reset by resetn, so a req_tgl of '1' at reset release would otherwise fake an edge and replay the hold register as a phantom DMI request.
                if m_state = M_IDLE then
                    if rst_guard(2) = '1' and (req_s2 /= req_s3) then
                        req_vld_r <= '1';
                        m_state   <= M_REQ;
                    end if;
                elsif m_state = M_REQ then
                    -- M_REQ is a ONE-SHOT: valid is held only until the registered ready is observed and never re-asserted for the same request.
                    -- Holding it longer earns a second, duplicate accept once the Debug Module's re-capture window reopens, which slides every later response back by one.
                    if dmi_req_ready = '1' then
                        req_vld_r <= '0';
                        m_state   <= M_RSP;
                    end if;
                else
                    -- M_RSP: latch the response payload and flip rsp_tgl for the TCK side.
                    if dmi_rsp_valid = '1' then
                        rsp_op_h   <= dmi_rsp_op;
                        rsp_data_h <= dmi_rsp_data;
                        rsp_tgl    <= not rsp_tgl;
                        m_state    <= M_IDLE;
                    end if;
                end if;
            end if;
        end process;

        -- The request payload is driven straight out of the TCK-domain hold register, held while its toggle is in flight and sampled only after the edge has been synchronised.
        -- Stability rests on the hold register being written only at an arming Update-DR, which is many TCK cycles apart even when a transaction is abandoned and re-armed.
        dmi_req_valid <= req_vld_r;
        dmi_req_op    <= req_hold(1 downto 0);
        dmi_req_data  <= req_hold(33 downto 2);
        dmi_req_addr  <= req_hold(DR_HI downto 34);

    end generate;

end architecture;
