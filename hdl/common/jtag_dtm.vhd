-- =============================================================================
-- jtag_dtm.vhd  (D3)
-- =============================================================================
-- THE JTAG TAP AND THE DEBUG TRANSPORT MODULE. One per chip, ASSEMBLY level,
-- beside dm0 -- never inside a tile (d3_cdc_spec 7). Frozen contract:
-- ~/vesta_docs/d_series/d3_spec.md 1-2 and d3_cdc_spec.md 1-4 as amended by
-- R-D3-4(2); the DMI port it drives is d2_spec 2, frozen at D2 and NOT moved.
--
-- WHAT IT IS AND IS NOT AT D3.
--   IS : the 16-state IEEE 1149.1 TAP, a 5-bit IR, the four DRs (IDCODE,
--        dtmcs, the 41-bit dmi, BYPASS), the sticky/dmireset machine, and the
--        TCK<->mclk crossing that turns a DR scan into ONE DMI transaction on
--        the Debug Module's frozen port.
--   NOT: pads (D3 wires them at netlist level only; the physical cut is the
--        close-of-programme re-cut), a debug ROM (D4), OpenOCD/gdb (D5),
--        System Bus Access (never -- there is no raw-memory DMI path here BY
--        DESIGN), and any behaviour change to the DM itself.
--
-- SPIKE IS THE REFERENCE (riscv/jtag_dtm.{h,cc}), and every DEVIATION FROM IT
-- IS DELIBERATE AND NAMED:
--   1. An UNSUPPORTED IR selects BYPASS. Spike leaves dr/dr_length stale from
--      the previous capture, which makes the length of the selected chain
--      depend on history. (d3_spec 1)
--   2. dtmcs.dmistat IS DRIVEN, sticky, and includes sticky FAILED (2) as well
--      as sticky BUSY (3). Spike's dtmcs is a constant 0x71 and never reports
--      either; a real debugger reads dmistat to decide whether to issue
--      dmireset. (d3_cdc_spec 4)
--   3. dtmcs.idle IS TRUTHFUL (see THE idle DERIVATION below). Spike advertises
--      0 while enforcing a hidden RTI requirement -- the one behaviour the CDC
--      spec explicitly says not to copy.
--   4. While dmistat is NONZERO -- EITHER sticky flavour -- an Update-DR of dmi
--      is IGNORED. Spike gates on busy_stuck only. The debug spec's own
--      contract (no DMI transactions until dmireset after a sticky error) is
--      the authority here. (R-D3-4(2a))
--   5. dmihardreset does NOT force the TAP to Test-Logic-Reset. It resets the
--      TCK-side DTM state (sticky, shadow, in-flight bookkeeping); TLR stays
--      reachable through TMS/TRSTn, which the debugger already controls.
--      (R-D3-4(2b)). The DMI result SHADOW's reset value is DEFINED all-zeros,
--      so a Capture-DR of dmi straight after dmihardreset returns 41'b0.
--   6. TRSTn resets the WHOLE TCK-side DTM (Spike's reset(): FSM, IR, sticky,
--      shadow, in-flight). TEST-LOGIC-RESET resets only the FSM and IR --
--      it does NOT clear the sticky flag or the shadow, which is exactly why
--      dmireset exists (Spike semantics, d3_cdc_spec 3).
--
-- THE CROSSING, and why it is shaped like the UART and not like a FIFO.
-- The mandated idiom is hdl/common/periph/UART.vhd flags_cdc_proc (:478-538)
-- with its ACK half (:640-657): ONE source toggle, the payload written on the
-- same source edge and then HELD while that toggle is in flight, and a THREE
-- flop destination chain (2-FF synchroniser + a third flop for edge detect).
-- The written prohibition on per-bit bus synchronisers is SYSTEM.vhd:442-457.
-- debug_module.vhd and mp_arbiter.vhd contain ZERO CDC structures today: this
-- file is the first crossing anywhere near them, so the idiom is copied rather
-- than invented.
--   TCK -> mclk (request): Update-DR of a dmi scan with op /= NOP loads the
--     41-bit REQUEST HOLD register (addr, data, op -- TCK domain) and flips
--     req_tgl. The mclk side syncs, detects the edge, and presents the held
--     payload to the DM.
--   mclk -> TCK (response): dmi_rsp_valid latches rsp_op/rsp_data into a
--     34-bit HOLD register (mclk domain) and flips rsp_tgl. The TCK side syncs,
--     detects the edge, and updates the DMI result shadow.
--
-- ***** THE ONE-SHOT CLAUSE (d3_cdc_spec 2 -- REQUIRED, spec level) *****
-- The mclk-side master asserts dmi_req_valid, holds it ONLY until
-- dmi_req_ready is observed, and deasserts the cycle after. It NEVER
-- re-asserts for the same request. This is not stylistic. The Debug Module's
-- re-capture lockout is a TIMER -- `rsp_hold = 0 and rsp_arm = '0'`
-- (debug_module.vhd, the accept guard) -- and the window RE-OPENS 9 mclk after
-- a capture. A DD4-idiomatic master that held the request level until its
-- response came back would hold it far longer than that (the response has to
-- cross a 3-flop chain into the TCK domain) and would earn a SECOND, DUPLICATE
-- accept of the same request: two responses for one request, sliding every
-- later request/response pair by one. The symptom is not a wrong answer, it is
-- the PREVIOUS answer. valid is high for exactly two mclk here (presented, then
-- retired on the registered ready) -- seven cycles inside the window.
--
-- ***** THE idle DERIVATION (d3_cdc_spec 4 wants the VALUE stated) *****
-- Latency from the Update-DR that arms a request to the earliest Capture-DR
-- that can see its result, in TCK cycles:
--     t_visible = 3 TCK (this file's response synchroniser: 2-FF + edge flop)
--               + ceil(t_DM / T_TCK)
--     t_DM      = 3..4 mclk (request synchroniser + edge detect)
--               + 1 (registered valid) + 1..2 (DM accept; ready_r is
--               REGISTERED, not combinational) + 2 (DM arms the response one
--               cycle before asserting it) + 1 (latch + rsp_tgl)
--               = 8..10 mclk for a register access, plus the shared-window
--               master read for the three PROXIED addresses (data0, progbuf0,
--               progbuf1) -- tens of mclk through mp_arbiter.
-- A debugger's own navigation puts its Capture-DR at Update + idle + 3 TCK
-- cycles (Update-DR -> Run-Test/Idle, `idle` cycles, then -> Select-DR ->
-- Capture-DR), so the requirement is idle >= ceil(t_DM / T_TCK).
-- STATED ASSUMPTION: T_TCK >= 140 ns (TCK <= 7.14 MHz) against mclk 41.667 ns
-- (24 MHz). Register access 10 mclk = 417 ns -> 3 cycles; proxied access
-- <= 20 mclk = 833 ns -> 6 cycles. IDLE_CYCLES is therefore 7 -- one cycle of
-- margin over the worst class, and the maximum the 3-bit field can express, so
-- rounding up costs nothing but debugger throughput.
-- AT A FASTER TCK, OR UNDER HEAVY ARBITER CONTENTION, BUSY CAN STILL HAPPEN.
-- That is not an error condition: the sticky-busy -> dmireset -> re-issue path
-- is fully functional and instrumented, and `idle` is a MINIMUM recommendation,
-- not a guarantee the hardware enforces.
--
-- ***** THE PAYLOAD-STABILITY ASSUMPTION, stated rather than discovered *****
-- The mclk side reads the request payload out of the TCK-domain hold register
-- (that IS the held-payload idiom; a second copy on the mclk side would cost
-- 41 more flops for no coverage). The hold register is written only at an
-- arming Update-DR, so it is stable for as long as one DMI transaction takes.
-- The ONE sequence that could overwrite it while the DM still has the previous
-- request is: arm, then ABANDON (dmireset / dmihardreset / TRSTn), then arm
-- again before the abandoned transaction has finished. The shortest TCK-side
-- path between those two Update-DRs is an IR scan plus a 32- or 41-bit DR scan
-- plus navigation -- >= 45 TCK cycles, >= 6.3 us at the assumed rate -- against
-- a DM transaction of at most tens of mclk (~1 us). The margin is a factor of
-- several, and it is written here because it is an ASSUMPTION and not a proof.
--
-- ***** WHY THE mclk SIDE CARRIES A RESET-RECOVERY GUARD *****
-- req_tgl lives in the TCK domain and is NOT reset by system resetn (a debugger
-- must stay attached across a chip reset -- the halt-on-reset story). Its mclk
-- synchroniser IS reset by resetn, to zeros. So if req_tgl happens to be '1'
-- when resetn releases, the chain fills with ones and the edge detector sees a
-- transition that never happened -- manufacturing ONE PHANTOM DMI REQUEST,
-- replaying whatever the hold register still contains, at every system reset
-- while a debugger is attached. rst_guard suppresses edge detection until the
-- chain holds three real samples. Three flops, and they buy a defect class.
--
-- FAIL-SAFE POLARITY (rule 15; policed by check_entity_defaults.py).
-- ENABLE_DEBUG defaults false and folds the whole block away. Every JTAG input
-- defaults '0' -- and trstn '0' means the TAP is HELD IN RESET, so an
-- unconnected or unbonded DTM is INERT: it issues nothing, and the OR-merge at
-- the MCU sees a permanently-zero valid. The IDCODE generic defaults to
-- 0x00000001 -- version 0, partnum 0, manufid 0, with only the 1149.1-mandatory
-- LSB set: obviously invalid, so a build that forgot to pass the real value
-- announces itself instead of impersonating a chip.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity jtag_dtm is
    generic (
        -- Fail-safe OFF at every declaration site (rule 15).
        ENABLE_DEBUG : boolean := false;
        -- JTAG IDCODE. The per-chip values are USER decisions (R-DD4(1)):
        -- Castalia 0x1CA57EEF, Argus 0x1A265EEF -- version 1, partnum
        -- 0xCA57/0xA265, manufid 0x777 (the Spike-precedent deliberately
        -- invalid JEP106 code, honest for a non-commercial chip), LSB 1.
        -- The generator selects by chip identity; this DECLARATION default is
        -- the fail-safe one described in the header.
        IDCODE       : std_logic_vector(31 downto 0) := x"00000001";
        -- dtmcs.idle [14:12], in TCK cycles. See THE idle DERIVATION above.
        IDLE_CYCLES  : natural range 0 to 7 := 0
    );
    port (
        -- ---- the five JTAG pins (TCK domain) -----------------------------
        -- Defaulted like the D2 DMI port so every existing instantiation --
        -- riscv_tb's COMPONENT, the chip_top netlists, the gate flows --
        -- stays legal with no edits (d2_probe finding 12, reused on purpose).
        tck   : in  std_logic := '0';
        tms   : in  std_logic := '0';
        tdi   : in  std_logic := '0';
        tdo   : out std_logic;
        trstn : in  std_logic := '0';   -- ASYNC, active low. '0' = TAP in reset

        -- ---- system side (mclk domain) -----------------------------------
        clk    : in  std_logic;                    -- free-running mclk
        resetn : in  std_logic;                    -- system reset: mclk SIDE ONLY

        -- ---- DMI master: drives debug_module's frozen D2 port ------------
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

    -- ---- TAP states. Spike's enum order (jtag_dtm.h:8-25), which is the
    -- standard IEEE 1149.1 graph. Kept as an integer range so the state
    -- register is four flops and the transition table is one lookup.
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

    -- next[state][tms]. Transcribed from Spike jtag_dtm.cc:60-77.
    type tap_next_t is array (0 to 15, 0 to 1) of integer range 0 to 15;
    constant TAP_NEXT : tap_next_t := (
        (1, 0),   (1, 2),   (3, 9),    (4, 5),
        (4, 5),   (6, 8),   (6, 7),    (4, 8),
        (1, 2),   (10, 0),  (11, 12),  (11, 12),
        (13, 15), (13, 14), (11, 15),  (1, 2));

    -- ---- IR (5 bits; every OpenOCD config in tools/debug/ says -irlen 5)
    constant IR_IDCODE : std_logic_vector(4 downto 0) := "00001";  -- 0x01, reset value
    constant IR_DTMCS  : std_logic_vector(4 downto 0) := "10000";  -- 0x10
    constant IR_DMI    : std_logic_vector(4 downto 0) := "10001";  -- 0x11
    constant IR_BYPASS : std_logic_vector(4 downto 0) := "11111";  -- 0x1F

    -- Selected DR. Deviation 1: EVERY unsupported opcode maps to BYPASS.
    constant SEL_IDCODE : integer := 0;
    constant SEL_DTMCS  : integer := 1;
    constant SEL_DMI    : integer := 2;
    constant SEL_BYPASS : integer := 3;

    -- ---- dmi DR geometry: op[1:0], data[33:2], address[40:34].
    -- 41 = abits 7 + 34, which is Spike's arithmetic and the frozen port's.
    constant DR_HI : integer := 40;
    constant OP_NOP     : std_logic_vector(1 downto 0) := "00";
    constant OP_FAILED  : std_logic_vector(1 downto 0) := "10";
    -- dmistat / captured-op encodings (Spike's status enum)
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

    -- ==================================================================
    -- KNOB-OFF FOLD. Everything below lives inside gen_dtm; the else arm
    -- ties every output to its fail-safe value so a knob-OFF instantiation
    -- (which the generator never emits, but a hand instantiation might)
    -- carries no state at all and cannot reach the Debug Module.
    -- ==================================================================
    gen_dtm_off: if not ENABLE_DEBUG generate
        tdo           <= '0';
        dmi_req_valid <= '0';
        dmi_req_op    <= (others => '0');
        dmi_req_addr  <= (others => '0');
        dmi_req_data  <= (others => '0');
    end generate;

    gen_dtm: if ENABLE_DEBUG generate

        sel <= ir_decode(ir_r);

        -- dtmcs. version[3:0] = 1 (0.13 and 1.0), abits[9:4] = 7 -> the base
        -- value 0x71 that Spike hard-codes; dmistat[11:10] and idle[14:12] are
        -- the two fields this design drives and Spike does not. dmireset (16)
        -- and dmihardreset (17) are WRITE-ONLY strobes decoded at Update-DR and
        -- read back as zero -- zero flops, which is why they are not registers.
        dtmcs_w(31 downto 15) <= (others => '0');
        dtmcs_w(14 downto 12) <= IDLE_SLV;
        dtmcs_w(11 downto 10) <= sticky;
        dtmcs_w(9 downto 4)   <= "000111";
        dtmcs_w(3 downto 0)   <= "0001";

        -- ==============================================================
        -- THE TAP. One process, TCK rising, asynchronously reset by TRSTn.
        -- Ordering inside it follows Spike (jtag_dtm.cc:79-131): the SHIFT
        -- uses the state the TAP is in BEFORE the edge, then the state
        -- advances, then the entry action of the state just entered runs.
        -- Capture-DR/Update-DR/Capture-IR/Update-IR/TLR are entry actions
        -- here where Spike runs them on the following falling edge; the two
        -- are indistinguishable from the pins (nothing samples between the
        -- two edges except TDO, which has its own falling-edge flop) and the
        -- earlier form gives the crossing half a TCK cycle more.
        -- ==============================================================
        tap_proc: process(tck, trstn)
            variable tmsi : integer range 0 to 1;
            variable nxt  : integer range 0 to 15;
        begin
            if trstn = '0' then
                -- DEVIATION 6: TRSTn is Spike's reset() -- the WHOLE TCK-side
                -- DTM, not just the FSM. Clearing `pending` here is also the
                -- DISCARD mechanism (see the response block): an outstanding
                -- transaction completes on the mclk side and its response is
                -- dropped on arrival, so the toggle chains stay phase
                -- coherent and the DTM is immediately re-usable.
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

                -- ---- response crossing: 2-FF synchroniser + edge detect ---
                -- The payload (rsp_op_h/rsp_data_h) is HELD in the mclk domain
                -- and sampled here at the detected edge -- never synchronised
                -- per bit (SYSTEM.vhd:442-457's prohibition).
                -- THE `pending` QUALIFIER IS THE DISCARD MECHANISM. A response
                -- to a transaction that has been abandoned (dmireset,
                -- dmihardreset, TRSTn) arrives with pending = '0' and is
                -- dropped; the same qualifier absorbs the phantom edge that a
                -- TRSTn-reset synchroniser chain manufactures when rsp_tgl
                -- happens to be '1' at the time.
                rsp_s1 <= rsp_tgl;
                rsp_s2 <= rsp_s1;
                rsp_s3 <= rsp_s2;
                if (rsp_s2 /= rsp_s3) and pending = '1' then
                    -- Address bits PRESERVED from the request (d3_cdc_spec 2's
                    -- Capture-DR clause: the captured word carries the previous
                    -- op's address verbatim).
                    shadow(DR_HI downto 34) <= req_hold(DR_HI downto 34);
                    shadow(33 downto 2)     <= rsp_data_h;
                    shadow(1 downto 0)      <= rsp_op_h;
                    pending                 <= '0';
                    -- ***** STICKY FAILED IS LATCHED HERE, AT THE RESPONSE'S
                    -- ARRIVAL -- NOT AT THE CAPTURE THAT DELIVERS IT. *****
                    -- MEASURED, and it is the difference between a recoverable
                    -- DTM and a permanently wedged one. The shadow KEEPS its
                    -- op until the next response overwrites it, and dmireset
                    -- deliberately does not clear the shadow (d3_cdc_spec 3:
                    -- only dmihardreset does). So a capture-time latch
                    -- re-raises dmistat from the STALE failed op on the very
                    -- next dmi scan -- and because that scan's own Capture-DR
                    -- runs BEFORE its Update-DR, the uniform sticky gate then
                    -- drops the request the debugger was trying to issue. One
                    -- failed address would silently swallow every subsequent
                    -- DMI write for the rest of the session, with dmireset
                    -- unable to break the loop. That is exactly what the
                    -- acceptance set caught (dbg_conf replayed over the TAP:
                    -- every write from K12 onward dropped while the same list
                    -- passed 38/38 over the raw port).
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
                        -- IDCODE / dtmcs: a 32-bit chain inside the shared
                        -- shifter, so TDI is injected at bit 31 and the
                        -- measured length is 32 (dbg_tapconf G8/G9).
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
                    -- TLR sets IR = IDCODE AND NOTHING ELSE (Spike
                    -- jtag_dtm.cc:104-106). It does NOT clear the sticky flag
                    -- or the shadow -- dmireset exists precisely for that.
                    ir_r <= IR_IDCODE;

                elsif nxt = ST_CAPTURE_IR then
                    -- 1149.1 mandates bits [1:0] = "01" in the Capture-IR
                    -- value; 0x01 satisfies it and is also the harmless IR.
                    ir_sh <= "00001";

                elsif nxt = ST_UPDATE_IR then
                    ir_r <= ir_sh;

                elsif nxt = ST_CAPTURE_DR then
                    if sel = SEL_IDCODE then
                        -- CONSTANT, loaded at Capture-DR: zero storage, so
                        -- shifting anything through it changes nothing.
                        dr <= "000000000" & IDCODE;
                    elsif sel = SEL_DTMCS then
                        dr <= "000000000" & dtmcs_w;
                    elsif sel = SEL_DMI then
                        if pending = '1' or sticky = ST_BUSY then
                            -- THE WHOLE 41-BIT DR IS LITERAL 3 -- address 0,
                            -- data 0, op = busy. It is NOT "the previous
                            -- result with op = busy" (Spike jtag_dtm.cc:145-147)
                            -- and the capture is what MAKES the flag sticky.
                            dr     <= (1 => '1', 0 => '1', others => '0');
                            sticky <= ST_BUSY;
                        else
                            -- The previous op's result, address preserved.
                            -- NOTE what this arm does NOT do: it does not
                            -- touch dmistat. Sticky BUSY is a capture-time
                            -- discovery and is raised above; sticky FAILED is
                            -- raised where the failure is LEARNED, in the
                            -- response block -- see the essay there for the
                            -- wedge that the other ordering produces.
                            -- A capture is still able to READ a failed result
                            -- as FAILED (op = 2) while dmistat already says 2:
                            -- the literal-3 substitution above is gated on
                            -- in-flight or sticky BUSY, never on sticky FAILED.
                            dr <= shadow;
                        end if;
                    else
                        dr <= (others => '0');   -- BYPASS captures 0
                    end if;

                elsif nxt = ST_UPDATE_DR then
                    if sel = SEL_DTMCS then
                        -- Write-only strobes. dmihardreset dominates and adds
                        -- the shadow clear; NEITHER resets the Debug Module,
                        -- and (DEVIATION 5) neither forces Test-Logic-Reset.
                        if dr(17) = '1' then
                            sticky  <= ST_NONE;
                            pending <= '0';
                            shadow  <= (others => '0');
                        elsif dr(16) = '1' then
                            -- dmireset clears the sticky flag AND ABANDONS the
                            -- outstanding transaction (d3_spec 2) -- the same
                            -- discard the response block enforces.
                            sticky  <= ST_NONE;
                            pending <= '0';
                        end if;

                    elsif sel = SEL_DMI then
                        if dr(1 downto 0) /= OP_NOP then
                            -- A NOP scan NEVER arms anything (d3_spec 2), which
                            -- is what makes a capture-only scan safe.
                            if sticky /= ST_NONE then
                                null;   -- DEVIATION 4: dropped while sticky
                            elsif pending = '1' then
                                -- An access while a transaction is in flight is
                                -- dropped and RAISES sticky busy -- the debug
                                -- spec's own answer, and the only way the
                                -- debugger can learn its scan was lost.
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

        -- TDO changes on the TCK FALLING edge, LSB first (d3_spec 1). Held
        -- between shift states rather than forced low: a JTAG chain wants TDO
        -- quiet, not toggling, outside its own shift window.
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

        -- ==============================================================
        -- THE mclk SIDE. Request synchroniser, the ONE-SHOT master, and the
        -- response hold. Reset by SYSTEM resetn -- the DM's own domain, and
        -- deliberately NOT the TAP's: a debugger must be attachable while the
        -- chip is held in reset (d3_cdc_spec 3, the halt-on-reset story).
        -- ==============================================================
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

                if m_state = M_IDLE then
                    if rst_guard(2) = '1' and (req_s2 /= req_s3) then
                        req_vld_r <= '1';
                        m_state   <= M_REQ;
                    end if;
                elsif m_state = M_REQ then
                    -- THE ONE-SHOT CLAUSE. ready is a REGISTERED one-cycle
                    -- acknowledge (debug_module.vhd: dmi_req_ready <= ready_r),
                    -- so it is sampled the cycle AFTER valid is presented and
                    -- valid retires the cycle after that -- two cycles high,
                    -- seven inside the DM's 9-cycle re-capture window.
                    if dmi_req_ready = '1' then
                        req_vld_r <= '0';
                        m_state   <= M_RSP;
                    end if;
                else
                    if dmi_rsp_valid = '1' then
                        rsp_op_h   <= dmi_rsp_op;
                        rsp_data_h <= dmi_rsp_data;
                        rsp_tgl    <= not rsp_tgl;
                        m_state    <= M_IDLE;
                    end if;
                end if;
            end if;
        end process;

        -- The request payload is driven straight out of the TCK-domain hold
        -- register: HELD while its toggle is in flight, sampled by the DM only
        -- after the edge has been synchronised. This is the idiom, not a
        -- shortcut -- see THE PAYLOAD-STABILITY ASSUMPTION in the header.
        dmi_req_valid <= req_vld_r;
        dmi_req_op    <= req_hold(1 downto 0);
        dmi_req_data  <= req_hold(33 downto 2);
        dmi_req_addr  <= req_hold(DR_HI downto 34);

    end generate;

end architecture;
