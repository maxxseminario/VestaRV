-- =============================================================================
-- debug_module.vhd  (D2)
-- =============================================================================
-- THE DEBUG MODULE. One per chip, assembly level, always-on mclk domain, never
-- inside a tile. Frozen contract: ~/vesta_docs/d_series/d2_spec.md 2-5, as
-- amended by R-D2-2; run-control wire reconciliation R-D1-2(1b)/R-D2-1(6);
-- shared-window debug entry R-DD3/R-DD12.
--
-- WHAT IT IS AND IS NOT AT D2.
--   IS : a DMI-addressed debug module -- run control (halt/resume/halt-on-reset),
--        dmstatus truth-telling against PWRCTRL, abstract access-register
--        commands, a 2-word program buffer with an implicit third word, halt
--        groups, hartsel/haltsum at N=4 AND N=18, and -- since D4 -- the
--        SELF-PLANT of the 40-word entry trampoline (the TRAMP table and
--        S_TRAMP below; d4_spec 1, R-DD5 option B).  There is no debug ROM
--        macro and there never will be: 24 of the entry page's 64 words are
--        DM-written at runtime and MUST stay writable (d4_probe C1).
--   NOT: DTM/TAP/pads (D3 drives this same port unchanged -- that is why the
--        port is frozen now), triggers (D6), gdb (D5),
--        System Bus Access (R-DD2: never this programme -- there is no
--        raw-memory DMI path here BY DESIGN; memory access is progbuf lw/sw
--        through the hart, which is DD5's answer).
--
-- WHY THE DM IS AN ARBITER MASTER, and why that is not optional.
-- A tile's TCM is UNREACHABLE from the shared bus (d2_probe P5, four proofs):
-- hart_tile's every bus port is outbound, the TCM macro's only client is its
-- own core, and the arbiter's slave map has no TCM page. An abstract
-- access-register is a CODE-EXECUTION mechanism -- Spike's own debug_module.cc
-- synthesises instructions and lets the halted hart execute them -- so the DM
-- must be able to PLACE INSTRUCTIONS WHERE THE TARGET HART FETCHES THEM and to
-- READ BACK what the hart stored. The shared bulk RAM is the only such place,
-- so the DM is a master on mp_arbiter, exactly as DMA0 is (generate.py's dma
-- schema doc is the precedent for the fabric widening).
--
-- THE MASTER-PORT CONTRACT IS COPIED VERBATIM FROM DMA.vhd, and it is not
-- decoration: mp_arbiter runs WAIT-FOR-RELEASE (mp_arbiter.vhd's `need_release`
-- -- a served master stays masked until its req is OBSERVED low). A master that
-- holds req continuously across two words is an M5a stale ghost and gets
-- starved. So: raise m_req with m_we/m_addr/m_wdata stable -> HOLD all stable
-- through the m_done cycle -> capture m_rdata ON the m_done cycle -> drop m_req
-- via an acked flop ONE clk AFTER m_done -> guarantee >= 1 arbiter-observed
-- m_req-low cycle. MS_CAP and MS_GAP below are the states that manufacture it.
--
-- THE MUTEX-PAGE GUARD, likewise copied from DMA.vhd:81-84 and NOT optional.
-- A read of the mutex bank (0x6000-0x6FFF) has a SIDE EFFECT: it atomically
-- claims the mutex for whoever the arbiter says is reading. The DM appears at
-- s_master as index numHarts (or numHarts+1 beside the DMA) -- a NON-HART
-- value that mutex_bank, irq_router's CLAIM and the afe_stub ownership gate all
-- interpret as a hart index. The DM therefore never issues a transaction
-- outside its own claimed band, and a computed address outside it is a FATAL
-- assertion rather than a silent stray claim.
--
-- CLAIMED SHARED BAND (CLAUDE.md ledger, d2_spec 1; claim /= use):
--   0x10680           DATA0     -- hartinfo.dataaddr, the abstract data word
--   0x10684           PROGBUF0  -- DMI-proxied
--   0x10688           PROGBUF1  -- DMI-proxied
--   0x1068C           IMPLICIT  -- the third progbuf word (impebreak = 1);
--                                  DM-written `jal x0, EPILOGUE`
--   0x10690-0x106EC   reserved for DM use (v2)
--   0x106F0/0x106F4   MIRROR0/MIRROR1 -- the halted session's saved s0/s1.
--                                  Written and read by the TRAMPOLINE, never
--                                  by the DM; see dbg_trampoline.S. They are
--                                  what makes an exception inside an abstract
--                                  command survivable.
--   0x10700 + 4h      FLAGS[h]  -- the per-hart DM<->hart handshake word
--   0x10780 + 4n      the entry page, 64 words:
--                       n =  0..39  TRAMPOLINE  (DM-PLANTED since D4 -- the
--                                   constant TRAMP table below, streamed by
--                                   S_TRAMP; see THE PLANT further down)
--                       n = 40..47  ABSTRACT BODY   (DM-written per command)
--                       n = 48..56  EPILOGUE        (DM-written once)
--                       n = 57..63  spare (v2)
-- EVERY DM-WRITTEN *DATA* WORD IS BELOW 0x10800, i.e. inside the bootrom's
-- zero range (it zeroes 0x10000-0x107FF at every boot), so the
-- write-before-read contract holds without the DM initialising anything. The
-- only words at or above 0x10800 are the trampoline's own tail (words 32..39)
-- and the EPILOGUE, both pure CODE the DM writes before anything can read them
-- -- exactly the rule R-D2-2(3) attached to the enlarged page.
--
-- THE HANDSHAKE, and why the hart polls rather than the DM interrupting it.
-- A halted hart runs the trampoline, which parks in a backed-off poll of its
-- own FLAGS[h] word. The DM drives that word:
--   FLAGS = TOK_GO      -> run the abstract body, then the epilogue
--   FLAGS = TOK_RESUME  -> restore s0/s1 and `dret`
-- and the trampoline writes back TOK_HALTED on entry and TOK_DONE from the
-- epilogue. THE DONE TOKEN IS THE EXCEPTION DETECTOR: the epilogue stores it
-- BEFORE its terminating `ebreak`, so a synchronous exception anywhere in the
-- body or the program buffer re-enters the trampoline (F-D2-0's core rider)
-- with the token still reading TOK_GO -- which is how `cmderr` becomes
-- EXCEPTION with the hart still halted and NOT wedged. There is no new core
-- signal for it and there does not need to be.
-- The SECOND half of that story lives in the trampoline, not here, and it was
-- a measured defect (J3's A10, 2026-08-06): the exception re-entry re-runs the
-- trampoline's entry save with the FAULTING code's s0/s1, so without a repair
-- it destroys the debugger's own registers and every command after the
-- exception returns garbage. The trampoline now mirrors the saved pair at
-- dispatch and puts it back on re-entry, keyed off FLAGS[h]'s bit 2. The DM is
-- deliberately ignorant of the mirror -- it never reads or writes those two
-- words -- so nothing here depends on it beyond the token encoding below.
--
-- THE PLANT (D4, d4_spec 1; USER decision DD13 = R-DD5 option B).
-- Before D4 the entry page was populated by a tcl `force` in every debug
-- harness -- a testbench fiction with no silicon counterpart, and the DM could
-- not have written it even if it wanted to, because a forced word is read-only.
-- The DM now plants the 40-word trampoline itself, out of the constant TRAMP
-- table below, through THE SAME master engine and the SAME `step`/`m_go_*`
-- idiom that already streams EPILOGUE(0 to 8) in S_EPI. Nothing about the
-- mechanism is new; only the table is bigger and the trigger is different.
--
-- TWO TRIGGERS, and they are deliberately serviced differently:
--
--   (1) dmactive 0 -> 1  -- an EAGER plant, taken from S_IDLE the moment the
--       rise is seen. It has to be eager: at attach no hart need ever halt and
--       no command need ever be written, so there is no later event to hang it
--       on, and `setresethaltreq` can halt a hart at a reset release the DM
--       does not schedule. It is a rise, NOT every dmcontrol write -- every
--       status poll writes dmcontrol, and re-planting on each would leave the
--       master engine permanently busy.
--
--   (2) any hart's dbg_halted RISING EDGE -- a LAZY plant, taken immediately
--       before the DM would WAIT ON that hart's TOK_HALTED, i.e. on the way
--       into S_WAITH from either of its two entries (the abstract-command path
--       out of S_BODY, and the queued-resume arm in S_IDLE). d4_spec 1.2 states
--       the requirement as an ORDERING -- "re-streams the trampoline BEFORE
--       consuming that hart's TOK_HALTED (before any S_WAITH wait on it, before
--       any GO/RESUME write)" -- and this is that ordering, discharged at the
--       last possible moment rather than the first.
--       WHY LAZY AND NOT EAGER, measured 2026-08-07 before this code existed:
--       a plant is ~40 arbiter round trips, and while it runs the sequencer is
--       not S_IDLE, which is a busy window. Today's busy windows answer a
--       data0/progbuf proxy access with rsp_data = 0x00000000, rsp_op = OK and
--       cmderr = BUSY, and a `command` write with cmderr = BUSY (measured, both
--       with busy_r = '1' and with busy_r = '0' on the resume path). An eager
--       on-halt plant therefore drops a fresh ~13 us busy window directly on
--       top of the first thing every debugger does after a halt. Servicing it
--       on the way into S_WAITH puts the whole stream INSIDE the busy window
--       the command already owns, so the plant adds no DMI-visible window at
--       all on the halt path -- and it still precedes the token wait, which is
--       the only thing the clause asks for.
--
-- SELF-HEALING, which is why DD13 chose the on-halt variant. A hart that halts
-- into a corrupted page takes an illegal-instruction exception, re-enters at
-- DEBUG_ENTRY_ADDR through the F-D2-0 rider and spins with ZERO retires. It
-- cannot publish TOK_HALTED, so a DM that planted only AFTER seeing the token
-- would deadlock. Planting first breaks that: the page is repaired, the next
-- re-entry executes real code, and the debugger gets its answer with no DMI
-- action beyond the halt it already asked for. Re-streaming identical content
-- under a hart already executing from the page is harmless by identity.
--
-- THE PLANT-OWED STATE CLEARS ON dmactive -> 0 (the d4_probe C4 named edit), so
-- toggling dmactive is a real re-plant and not a no-op. `epi_done` JOINS that
-- clear -- see its declaration for the reasoning and the priced consequence.
--
-- IT IS NOT SYSTEM BUS ACCESS (R-DD2 boundary, stated so it need not be
-- re-argued). The content is fixed at synthesis, the addresses are fixed at
-- synthesis, no DMI register exposes an arbitrary address or an arbitrary data
-- path to memory, and every plant write lies inside [W_BAND_LO, W_BAND_HI] and
-- is checked by the same mutex-page assertion as every other DM transaction.
--
-- WIRE CONTRACT (R-D1-2(1b) reconciled by R-D2-1(6)/R-D2-2(5)). D1's core
-- collapses a HELD dbg_haltreq to exactly one entry (wait-for-release,
-- release-wins, raw-port clear, free-running clk). So the DM drives each
-- dbg_haltreq(h) as a RE-ARMED level:
--        haltreq_wire(h) = want(h) AND NOT halted(h)
-- One expression, and every required behaviour falls out of it: it asserts
-- until the hart halts, deasserts for the whole halted interval (which is what
-- lets the core's mask clear), and RE-ASSERTS the moment the hart resumes while
-- the debugger still wants it halted -- a fresh edge, a fresh entry. That is
-- R-D2-2(5)'s DEFINED semantics: a resumereq under a held haltreq makes the
-- hart resume (resumeack sets) and then re-halt with no further DMI write. The
-- core flop stays as belt and is NOT modified.
--
-- FAIL-SAFE POLARITY. Every generic defaults to the OFF/harmless value and
-- ENABLE_DEBUG defaults false (rule 15; policed by check_entity_defaults.py).
-- With ENABLE_DEBUG false the whole block folds: no master requests, no halt
-- requests, dmi_req_ready low, no flops that any downstream cone can reach.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity debug_module is
    generic (
        -- Fail-safe OFF at every declaration site (rule 15).
        ENABLE_DEBUG : boolean := false;
        -- Hart count. The clint/irq_router idiom -- N flows from the
        -- generator's numHarts, never from a MemoryMap constant (there is no
        -- NHARTS constant in MemoryMap.vhd and the DM must not invent one).
        NHARTS       : natural := 4;
        -- Shared-window word-address width (MCU's SH_AW). word = byte(16:2).
        SH_AW        : natural := 15;
        -- The claimed band, as BYTE addresses. Defaults are the d2_spec 1
        -- values; they are generics so a bench can re-aim the whole block the
        -- way dbg_iface_tb re-aims DEBUG_ENTRY_ADDR.
        DATA0_ADDR   : std_logic_vector(31 downto 0) := x"00010680";
        FLAGS_ADDR   : std_logic_vector(31 downto 0) := x"00010700";
        ENTRY_ADDR   : std_logic_vector(31 downto 0) := x"00010780"
    );
    port (
        clk    : in  std_logic;                       -- free-running mclk
        resetn : in  std_logic;

        -- ---- DMI (frozen at D2; D3's DTM drives this unchanged) ----------
        -- Every INPUT is defaulted so an MCU that does not connect them stays
        -- legal -- the same trick D1 used on the three tile ports, reused on
        -- purpose (d2_probe finding 12).
        dmi_req_valid : in  std_logic := '0';
        dmi_req_op    : in  std_logic_vector(1 downto 0) := "00";  -- 01=read 10=write
        dmi_req_addr  : in  std_logic_vector(6 downto 0) := (others => '0');
        dmi_req_data  : in  std_logic_vector(31 downto 0) := (others => '0');
        dmi_req_ready : out std_logic;
        dmi_rsp_valid : out std_logic;
        dmi_rsp_data  : out std_logic_vector(31 downto 0);
        dmi_rsp_op    : out std_logic_vector(1 downto 0);          -- 00=ok 10=failed 11=busy

        -- ---- per-hart run control (to/from the tiles) --------------------
        dbg_haltreq      : out std_logic_vector(NHARTS-1 downto 0);
        dbg_resethaltreq : out std_logic_vector(NHARTS-1 downto 0);
        dbg_halted       : in  std_logic_vector(NHARTS-1 downto 0) := (others => '0');
        -- unavail(h): the hart exists but the DM cannot reach it. Computed at
        -- the instantiation site from the power-control state that already
        -- exists there (d2_spec 5): pd_iso_en(h) or not tile_rstn(h) for
        -- h >= 1, and `not hart0_rstn` for hart 0 -- hart 0 is NOT immune, the
        -- DP-S3 boot gate can hold it in reset. Defaulted all-zeros so an
        -- unconnected instance reports every hart available rather than every
        -- hart missing.
        hart_unavail : in  std_logic_vector(NHARTS-1 downto 0) := (others => '0');

        -- ---- shared-bus MASTER port (one mp_arbiter master slice) --------
        -- Same shape and same protocol as DMA.vhd's. m_we is 4 ACTIVE-HIGH
        -- byte-lane strobes ("0000" = read), matching mp_arbiter's master side.
        m_req   : out std_logic;
        m_we    : out std_logic_vector(3 downto 0);
        m_addr  : out std_logic_vector(SH_AW-1 downto 0);
        m_wdata : out std_logic_vector(31 downto 0);
        m_gnt   : in  std_logic := '0';
        m_done  : in  std_logic := '0';
        m_rdata : in  std_logic_vector(31 downto 0) := (others => '0')
    );
end entity;

architecture rtl of debug_module is

    -- ------------------------------------------------------------------
    -- Layout constants, all derived from the generics so a re-aimed block
    -- stays self-consistent. WORD addresses (the arbiter's unit).
    -- ------------------------------------------------------------------
    function w(a : std_logic_vector(31 downto 0)) return integer is
    begin
        return conv_integer(a(SH_AW+1 downto 2));
    end function;

    constant W_DATA0    : integer := w(DATA0_ADDR);          -- 0x10680
    constant W_PROGBUF0 : integer := w(DATA0_ADDR) + 1;      -- 0x10684
    constant W_PROGBUF1 : integer := w(DATA0_ADDR) + 2;      -- 0x10688
    constant W_IMPLICIT : integer := w(DATA0_ADDR) + 3;      -- 0x1068C
    constant W_FLAGS0   : integer := w(FLAGS_ADDR);          -- 0x10700
    constant W_ENTRY    : integer := w(ENTRY_ADDR);          -- 0x10780
    -- THE TRAMPOLINE'S OWN LENGTH IS THE COUPLING. It occupies words 0..39
    -- since it gained the session-mirror repair for the F-D2-0 exception
    -- re-entry (software/dbg_trampoline/dbg_trampoline.S, 2026-08-06), and its
    -- dispatch ends in `jal x0, _start + 4*40`, so W_ABST is 40 and not a free
    -- choice. Changing either without the other silently jumps into the wrong
    -- code; the .S header and the Makefile both say so.
    -- ...so the length is written ONCE and W_ABST is derived from it. Before
    -- D4 the 40 lived in this expression and again in the .S and again in the
    -- Makefile; the table below makes it a fourth site, so it is named here and
    -- the other three are mechanised against it by check_dbg_trampoline.py.
    constant TRAMP_WORDS: integer := 40;
    constant W_ABST     : integer := W_ENTRY + TRAMP_WORDS;  -- 0x10820
    constant W_EPILOG   : integer := W_ENTRY + 48;           -- 0x10840

    -- The band the mutex-page guard checks against: everything the DM may
    -- ever touch lies in [W_DATA0 .. W_ENTRY+63].
    constant W_BAND_LO  : integer := W_DATA0;
    constant W_BAND_HI  : integer := W_ENTRY + 63;

    -- ------------------------------------------------------------------
    -- FLAGS[] tokens. Implementer latitude (d2_spec 1), single-writer-per-
    -- state: the DM writes GO and RESUME, the hart writes HALTED and DONE.
    -- No instrument encodes these values -- everything is checked through DMI
    -- responses and through architectural effects the victim itself reports.
    -- Chosen as small positive immediates so the trampoline can compare them
    -- with `addi` against x0 and needs no second scratch register, and so that
    -- BIT 2 IS SET IN EXACTLY THE TWO VALUES FLAGS CAN HOLD WHEN THE HART
    -- RE-ENTERS THE TRAMPOLINE -- GO (an exception before the epilogue) and
    -- DONE (the epilogue's own ebreak) -- and clear in the two it can hold at a
    -- FIRST entry, 0 (the bootrom's zeroing) and RESUME (left by the previous
    -- session; the hart cannot leave debug mode by any other route). That one
    -- bit is what lets the trampoline repair its own dscratch save on a
    -- re-entry with a single `andi` and no second scratch register. Changing
    -- these values without changing dbg_trampoline.S breaks the handshake.
    -- ------------------------------------------------------------------
    constant TOK_HALTED : integer := 1;
    constant TOK_RESUME : integer := 2;
    constant TOK_GO     : integer := 4;
    constant TOK_DONE   : integer := 12;

    -- ------------------------------------------------------------------
    -- DMI register addresses (debug_defines.h; d2_probe P6 quoted them).
    -- ------------------------------------------------------------------
    constant A_DATA0     : std_logic_vector(6 downto 0) := "0000100";  -- 0x04
    constant A_DMCONTROL : std_logic_vector(6 downto 0) := "0010000";  -- 0x10
    constant A_DMSTATUS  : std_logic_vector(6 downto 0) := "0010001";  -- 0x11
    constant A_HARTINFO  : std_logic_vector(6 downto 0) := "0010010";  -- 0x12
    constant A_HALTSUM1  : std_logic_vector(6 downto 0) := "0010011";  -- 0x13
    constant A_ABSTRACTCS: std_logic_vector(6 downto 0) := "0010110";  -- 0x16
    constant A_COMMAND   : std_logic_vector(6 downto 0) := "0010111";  -- 0x17
    constant A_ABSTAUTO  : std_logic_vector(6 downto 0) := "0011000";  -- 0x18
    constant A_PROGBUF0  : std_logic_vector(6 downto 0) := "0100000";  -- 0x20
    constant A_PROGBUF1  : std_logic_vector(6 downto 0) := "0100001";  -- 0x21
    constant A_DMCS2     : std_logic_vector(6 downto 0) := "0110010";  -- 0x32
    constant A_HALTSUM0  : std_logic_vector(6 downto 0) := "1000000";  -- 0x40

    constant OP_OK   : std_logic_vector(1 downto 0) := "00";
    constant OP_FAIL : std_logic_vector(1 downto 0) := "10";

    -- cmderr enum (d2_spec 3)
    constant ERR_NONE    : std_logic_vector(2 downto 0) := "000";
    constant ERR_BUSY    : std_logic_vector(2 downto 0) := "001";
    constant ERR_NOTSUP  : std_logic_vector(2 downto 0) := "010";
    constant ERR_EXCEPT  : std_logic_vector(2 downto 0) := "011";
    constant ERR_HALTRES : std_logic_vector(2 downto 0) := "100";
    constant ERR_OTHER   : std_logic_vector(2 downto 0) := "111";

    -- ~65k mclk at 24 MHz is ~2.7 ms, comfortably inside the 100 ms testbench
    -- watchdog and far longer than any real abstract sequence (a few hundred
    -- mclk including the hart's own shared fetches).
    constant POLL_LIMIT : integer := 65535;

    -- ------------------------------------------------------------------
    -- DM register file
    -- ------------------------------------------------------------------
    signal dmactive   : std_logic;
    signal haltreq_r  : std_logic;                       -- dmcontrol[31]
    signal hartsel_r  : std_logic_vector(9 downto 0);    -- hartsello, WARL
    signal rsthalt_r  : std_logic_vector(NHARTS-1 downto 0);
    signal resumeack_r: std_logic_vector(NHARTS-1 downto 0);
    signal havereset_r: std_logic_vector(NHARTS-1 downto 0);
    signal cmderr_r   : std_logic_vector(2 downto 0);
    signal busy_r     : std_logic;
    -- halt groups: 3 bits per hart => 8 groups, group 0 = "no group" = reset.
    type grp_t is array (0 to NHARTS-1) of std_logic_vector(2 downto 0);
    signal grp_r      : grp_t;
    signal grp_pend   : std_logic_vector(NHARTS-1 downto 0);

    -- selected-hart decode
    signal sel_idx    : integer range 0 to 1023;
    signal sel_safe   : integer range 0 to 1023;
    signal sel_exists : std_logic;
    signal sel_unavail: std_logic;
    signal sel_halted : std_logic;
    signal sel_running: std_logic;

    -- edge detect on halted, for resumeack / havereset / halt groups
    signal halted_d   : std_logic_vector(NHARTS-1 downto 0);
    signal want_halt  : std_logic_vector(NHARTS-1 downto 0);
    signal resume_pend: std_logic_vector(NHARTS-1 downto 0);

    -- ------------------------------------------------------------------
    -- Master engine
    -- ------------------------------------------------------------------
    type m_state_t is (MS_IDLE, MS_REQ, MS_CAP, MS_GAP);
    signal m_state  : m_state_t;
    signal m_req_r  : std_logic;
    signal m_we_r   : std_logic_vector(3 downto 0);
    signal m_addr_r : std_logic_vector(SH_AW-1 downto 0);
    signal m_wd_r   : std_logic_vector(31 downto 0);
    signal m_rd_r   : std_logic_vector(31 downto 0);
    signal m_start  : std_logic;   -- pulse from the sequencer
    signal m_ack    : std_logic;   -- pulse back: transaction retired
    signal m_go_we  : std_logic_vector(3 downto 0);
    signal m_go_a   : integer range 0 to 2**20-1;
    signal m_go_d   : std_logic_vector(31 downto 0);

    -- ------------------------------------------------------------------
    -- Sequencer
    -- ------------------------------------------------------------------
    type s_state_t is (S_IDLE,
                       S_PROXY,        -- a data0/progbuf DMI access in flight
                       S_PROXY_RSP,
                       -- THE PLANT (D4). Streams the constant TRAMP table to
                       -- W_ENTRY+0..39. Entered from three places and it knows
                       -- where to go back WITHOUT a return-state flop: a plant
                       -- that was owed to a TOK_HALTED wait is always entered
                       -- with busy_r = '1' (the command path) or res_busy = '1'
                       -- (the queued-resume path), and the eager dmactive-rise
                       -- plant is by construction entered from an S_IDLE where
                       -- both are '0' -- a command cannot have started (its
                       -- accept requires mst_free, i.e. S_IDLE) and no resume
                       -- flow can be in progress (every path that clears
                       -- res_busy returns to S_IDLE in the same cycle).
                       S_TRAMP,
                       S_EPI,          -- write the constant epilogue (once)
                       S_BODY,         -- write the synthesized abstract body
                       S_IMPL,         -- write the implicit progbuf word
                       S_GO,           -- FLAGS[h] <- TOK_GO
                       S_POLL,         -- read FLAGS[h] until DONE / not GO
                       S_FIN,
                       -- THE HANDOFF WAIT. The DM must OBSERVE FLAGS[h] =
                       -- TOK_HALTED before it writes GO or RESUME.
                       -- WHY: dmstatus.halted follows `debug_mode`, which sets
                       -- at DBG_SV -- but the trampoline needs a dozen more
                       -- shared accesses to reach its own `sw TOK_HALTED`. A DM
                       -- that writes the token as soon as it sees `halted` has
                       -- its write OVERWRITTEN by the hart moments later, and
                       -- the hart then polls forever. That is a single-writer-
                       -- per-state violation at the handoff, and it is
                       -- invisible whenever the hart has been halted for a
                       -- while -- which is why the plain resume (J2's H6)
                       -- passed while the back-to-back one (R2) did not.
                       S_WAITH,
                       S_RESUME,       -- FLAGS[h] <- TOK_RESUME
                       -- HOLD THE ENGINE UNTIL THE DISPATCHED RESUME IS TAKEN.
                       -- MEASURED DEFECT, 2026-08-06 (found by the J4 timeline
                       -- probe, seen to fail and to pass): S_RESUME used to
                       -- clear res_busy on the token WRITE, while resume_pend
                       -- is only cleared on the hart's halted FALLING edge --
                       -- so in the window between the two (the three shared
                       -- instructions the trampoline needs to reach its `dret`)
                       -- S_IDLE's arm condition was true AGAIN and re-armed the
                       -- SAME resume, parking the DM in S_WAITH for the full
                       -- POLL_LIMIT. Two consequences, both measured: a hart
                       -- that halted again inside that window (halt group,
                       -- re-armed haltreq) had the stale S_WAITH observe its
                       -- TOK_HALTED and fire a SPURIOUS, DMI-unrequested
                       -- resume; and `mst_free` (S_IDLE only) stayed low for
                       -- 2.75 ms after EVERY resume, so every data0/progbuf
                       -- proxy read answered 0 with cmderr = BUSY.
                       S_RESWAIT);
    signal s_state : s_state_t;
    signal step    : integer range 0 to 63;
    -- WRITE-ONCE for the epilogue, and it now JOINS the dmactive -> 0 clear
    -- (d4_spec 1.3 leaves the choice to the implementer and requires it to be
    -- stated and its consequence measured). Chosen so that a dmactive toggle is
    -- a COMPLETE recovery of everything the DM owns in the page rather than a
    -- partial one: the trampoline would be re-planted and the epilogue would
    -- not, which is the more surprising of the two behaviours and the harder
    -- one to diagnose from a debugger. It is also the fail-safe direction
    -- (rule 15) -- the cost of being wrong is nine shared writes, and the cost
    -- of the other choice is an unrecoverable epilogue. PRICED CONSEQUENCE: the
    -- FIRST abstract command after any dmactive toggle now takes the S_EPI path
    -- again (9 extra master writes, ~45 mclk) instead of going straight to
    -- S_IMPL. Measured green by dbg_trprep's R6, which exists for this clause.
    signal epi_done: std_logic;
    -- THE TWO PLANT-OWED BITS (D4). See THE PLANT in the header for why the two
    -- triggers are not merged into one: they are serviced at different moments,
    -- so one bit cannot represent both without making the on-halt plant eager.
    signal tramp_arm : std_logic;   -- dmactive rose: plant NOW, from S_IDLE
    signal tramp_halt: std_logic;   -- a hart halted: plant before its TOK_HALTED
    signal cmd_r   : std_logic_vector(31 downto 0);
    signal cmd_hart: integer range 0 to 1023;

    -- DMI front end
    signal rsp_valid_r : std_logic;
    signal rsp_data_r  : std_logic_vector(31 downto 0);
    signal rsp_op_r    : std_logic_vector(1 downto 0);
    signal ready_r     : std_logic;
    signal mst_free    : std_logic;
    -- ONE ACCEPT PER ASSERTION OF dmi_req_valid.  MEASURED before this existed:
    -- both BFMs raise req_valid and HOLD it until they sample req_ready high
    -- (their documented shape, and the legal one under R-D2-2(7)), so a DM that
    -- simply accepts on `valid and ready` accepts the SAME request on every
    -- cycle ready stays high -- issuing several responses for one request and
    -- sliding the master's request/response pairing by one for the rest of the
    -- run.  The symptom is not a wrong answer, it is the PREVIOUS answer, which
    -- is far worse to read.
    -- WHAT ACTUALLY IMPLEMENTS THE LOCKOUT, corrected at D3 (d3_spec 3; the
    -- text this replaces described an observed-low discipline through a signal
    -- name THAT DOES NOT EXIST IN THIS FILE).  The guard is a TIMER:
    -- `rsp_hold = 0 and rsp_arm = '0'` on the accept below.  ready_r pulses for
    -- one cycle at the capture; rsp_arm blocks the next cycle; rsp_hold blocks
    -- the following RSP_HOLD_CYCLES.  So the accept window RE-OPENS 9 mclk
    -- after a capture, and NOTHING here depends on dmi_req_valid having been
    -- seen low.  A master that holds valid high for >= 9 mclk after the
    -- acknowledge therefore earns a DUPLICATE ACCEPT of the same request --
    -- which is precisely why d3_cdc_spec 2 makes the DTM's mclk-side master a
    -- ONE-SHOT that retires on ready (jtag_dtm.vhd), and why both tcl and VHDL
    -- BFMs drop valid the instant they sample the acknowledge.
    -- How long the response is HELD. See the ready/rsp comment below: the
    -- masters that drive this port sample at 10 ns against an mclk period of
    -- 41.667 ns and drop their request the instant they see the acknowledge, so
    -- a one-cycle response pulse is a race they lose about as often as they win.
    -- 7 mclk (~292 ns) is far longer than any master's sampling interval and far
    -- shorter than any inter-transaction gap, and it doubles as the re-capture
    -- lockout that stops ONE held assertion of valid producing TWO accepts.
    constant RSP_HOLD_CYCLES : integer := 7;
    signal rsp_hold    : integer range 0 to RSP_HOLD_CYCLES;
    -- The response is ARMED at capture and ASSERTED ONE CYCLE LATER, so
    -- rsp_data/rsp_op are provably settled before rsp_valid ever rises.
    -- Without the separation a master sampling finely enough catches rsp_valid
    -- in the same cycle the answer is still being computed and reads the
    -- PREVIOUS transaction's data -- measured, and it surfaces as a plausible
    -- wrong value rather than as a protocol error, which is the worse failure.
    signal rsp_arm     : std_logic;
    signal pend_wr     : std_logic;
    -- The hart a resume was aimed at, latched so S_RESUME cannot be re-pointed
    -- by a hartsel write that lands while the FLAGS store is still in flight.
    signal res_hart    : integer range 0 to 1023;
    -- A queued resume. R-D2-5(2): a DM that silently DROPS resumereq because
    -- its master engine is busy is wrong against the W1 semantics of spec 4
    -- regardless of any instrument, so the request is latched and serviced
    -- when the engine frees. res_busy stops the queue re-triggering the flow
    -- while one is already in progress.
    signal res_busy    : std_logic;
    -- what S_WAITH runs on to next
    signal waith_go    : std_logic;
    -- S_POLL bound. A hart that never reports (a wedged trampoline, an
    -- unplanted entry page) must not pin `busy` forever -- an instrument would
    -- hang instead of failing, and a bounded retry that trips inside the tb
    -- watchdog is the house rule.
    signal poll_to     : integer range 0 to POLL_LIMIT;

    -- ------------------------------------------------------------------
    -- RV32I instruction synthesis. Everything the DM emits is built here;
    -- nothing is a magic hex literal at a use site.
    -- x8 = s0, x9 = s1 are the trampoline's saved scratch pair (dscratch0/1).
    -- ------------------------------------------------------------------
    constant R_S0 : integer := 8;
    constant R_S1 : integer := 9;
    constant CSR_DSCRATCH0 : integer := 16#7B2#;
    constant CSR_DSCRATCH1 : integer := 16#7B3#;
    constant CSR_MHARTID   : integer := 16#F14#;

    function u5(n : integer) return std_logic_vector is
    begin
        return conv_std_logic_vector(n, 5);
    end function;
    function u12(n : integer) return std_logic_vector is
    begin
        return conv_std_logic_vector(n, 12);
    end function;
    function u20(n : integer) return std_logic_vector is
    begin
        return conv_std_logic_vector(n, 20);
    end function;

    -- lui rd, imm20
    function i_lui(rd : integer; imm20 : integer) return std_logic_vector is
    begin
        return u20(imm20) & u5(rd) & "0110111";
    end function;
    -- addi rd, rs1, imm12
    function i_addi(rd, rs1, imm : integer) return std_logic_vector is
    begin
        return u12(imm) & u5(rs1) & "000" & u5(rd) & "0010011";
    end function;
    -- slli rd, rs1, sh
    function i_slli(rd, rs1, sh : integer) return std_logic_vector is
    begin
        return "0000000" & u5(sh) & u5(rs1) & "001" & u5(rd) & "0010011";
    end function;
    -- add rd, rs1, rs2
    function i_add(rd, rs1, rs2 : integer) return std_logic_vector is
    begin
        return "0000000" & u5(rs2) & u5(rs1) & "000" & u5(rd) & "0110011";
    end function;
    -- lw rd, off(rs1)
    function i_lw(rd, rs1, off : integer) return std_logic_vector is
    begin
        return u12(off) & u5(rs1) & "010" & u5(rd) & "0000011";
    end function;
    -- sw rs2, off(rs1)
    function i_sw(rs2, rs1, off : integer) return std_logic_vector is
        variable o : std_logic_vector(11 downto 0) := u12(off);
    begin
        return o(11 downto 5) & u5(rs2) & u5(rs1) & "010" & o(4 downto 0) & "0100011";
    end function;
    -- beq rs1, rs2, off (byte offset, must be even)
    function i_beq(rs1, rs2, off : integer) return std_logic_vector is
        variable o : std_logic_vector(12 downto 0) := conv_std_logic_vector(off, 13);
    begin
        return o(12) & o(10 downto 5) & u5(rs2) & u5(rs1) & "000"
             & o(4 downto 1) & o(11) & "1100011";
    end function;
    -- jal rd, off (byte offset)
    function i_jal(rd, off : integer) return std_logic_vector is
        variable o : std_logic_vector(20 downto 0) := conv_std_logic_vector(off, 21);
    begin
        return o(20) & o(10 downto 1) & o(11) & o(19 downto 12) & u5(rd) & "1101111";
    end function;
    -- csrrs rd, csr, x0   (= csrr rd, csr)
    function i_csrr(rd, csr : integer) return std_logic_vector is
    begin
        return u12(csr) & u5(0) & "010" & u5(rd) & "1110011";
    end function;
    -- csrrw x0, csr, rs1  (= csrw csr, rs1)
    function i_csrw(csr, rs1 : integer) return std_logic_vector is
    begin
        return u12(csr) & u5(rs1) & "001" & u5(0) & "1110011";
    end function;
    constant I_EBREAK : std_logic_vector(31 downto 0) := x"00100073";

    -- The base the trampoline and the emitted code address everything from:
    -- lui s0/s1, HI20 gives 0x00010000, and every DM word below 0x10800 is
    -- then reachable with a 12-bit unsigned load/store displacement.
    constant HI20     : integer := conv_integer(DATA0_ADDR(31 downto 12));
    constant OFF_BASE : integer := conv_integer(DATA0_ADDR(31 downto 12)) * 4096;
    constant O_DATA0  : integer := conv_integer(DATA0_ADDR) - OFF_BASE;
    constant O_FLAGS  : integer := conv_integer(FLAGS_ADDR) - OFF_BASE;

    -- ------------------------------------------------------------------
    -- THE EPILOGUE, constant. Reached from the abstract body (directly, when
    -- postexec = 0) or from the implicit third progbuf word (when postexec =
    -- 1). It arrives with s0/s1 clobbered, so it recomputes &FLAGS[h] from
    -- mhartid, stores TOK_DONE, restores the pair from dscratch0/1 and ends in
    -- `ebreak` -- which re-enters the trampoline (D1: dpc/dcsr survive).
    -- THE ORDER IS THE WHOLE POINT: TOK_DONE is stored BEFORE the ebreak, so
    -- an exception anywhere earlier leaves the token at TOK_GO and the DM
    -- reports cmderr = EXCEPTION instead of success.
    -- ------------------------------------------------------------------
    type word_arr is array (natural range <>) of std_logic_vector(31 downto 0);
    constant EPILOGUE : word_arr(0 to 8) := (
        0 => i_csrr(R_S0, CSR_MHARTID),
        1 => i_slli(R_S0, R_S0, 2),
        2 => i_lui (R_S1, HI20),
        3 => i_add (R_S0, R_S0, R_S1),
        4 => i_addi(R_S1, 0, TOK_DONE),
        5 => i_sw  (R_S1, R_S0, O_FLAGS),
        6 => i_csrr(R_S1, CSR_DSCRATCH1),
        7 => i_csrr(R_S0, CSR_DSCRATCH0),
        8 => I_EBREAK);

    -- The implicit third program-buffer word (impebreak = 1). It is a jump to
    -- the epilogue rather than a bare ebreak, so that a postexec sequence
    -- still stores its DONE token: "implicit ebreak" is what the DEBUGGER
    -- sees, and the epilogue's own ebreak is what actually terminates.
    constant I_IMPLICIT : std_logic_vector(31 downto 0) :=
        i_jal(0, (W_EPILOG - W_IMPLICIT) * 4);

    -- ------------------------------------------------------------------
    -- THE TRAMPOLINE (D4). The entry code every halted hart executes, held as
    -- a constant instruction table and streamed to W_ENTRY+0..39 by S_TRAMP.
    --
    -- THIS TABLE IS A COPY, AND THE COPY IS MECHANISED, NOT TRUSTED. The
    -- original is software/dbg_trampoline/dbg_trampoline.S, built to
    -- bin/dbg_trampoline.words; the words below are that artifact, word for
    -- word. Two sources of truth for the same 40 words is a defect waiting to
    -- happen, so `tools/cosim/check_dbg_trampoline.py` compares them and is a
    -- standing gate. DO NOT hand-edit either side: change the .S, rebuild
    -- (`make -C software/dbg_trampoline`), paste the new words here, and prove
    -- the checker exits 0. The content did NOT change at D4 and a change to it
    -- is out of D4's scope entirely (d4_spec 4).
    --
    -- NOT synthesized from the i_* encoders above, deliberately. Those encoders
    -- exist so the DM's OWN emitted code has no magic hex; this table is not
    -- the DM's code, it is a compiled artifact that a separate toolchain owns,
    -- and re-deriving it here would create a THIRD spelling of it whose
    -- agreement with the ELF nobody checks. The disassembly is carried as
    -- comments so the table stays readable; the checker is what makes it true.
    --
    -- POSITION-DEPENDENT. It was linked at 0x00010780 and addresses FLAGS, the
    -- mirrors and the abstract area with absolute `lui`/displacement pairs, and
    -- word 31's `j` is the coupling to W_ABST = W_ENTRY + TRAMP_WORDS. An
    -- instance that re-aims DATA0_ADDR/ENTRY_ADDR (dbg_iface_tb does) must
    -- rebuild the trampoline for the new aim -- exactly as the tcl force it
    -- replaces always had to.
    -- ------------------------------------------------------------------
    constant TRAMP : word_arr(0 to TRAMP_WORDS-1) := (
        --  entry: save the scratch pair tentatively
         0 => x"7B241073",   -- csrw   dscratch0, s0
         1 => x"7B349073",   -- csrw   dscratch1, s1
        --  s0 = &FLAGS[mhartid]
         2 => x"F14024F3",   -- csrr   s1, mhartid
         3 => x"00249493",   -- slli   s1, s1, 2
         4 => x"00010437",   -- lui    s0, 0x10
         5 => x"00940433",   -- add    s0, s0, s1
        --  bit 2 of FLAGS[h] set <=> this is a RE-ENTRY (GO or DONE)
         6 => x"70042483",   -- lw     s1, 1792(s0)      # FLAGS[h]
         7 => x"0044F493",   -- andi   s1, s1, 4
         8 => x"00048E63",   -- beqz   s1, halted
        --  re-entry repair: put the ORIGINAL pair back from the mirrors (A10)
         9 => x"000104B7",   -- lui    s1, 0x10
        10 => x"6F04A483",   -- lw     s1, 1776(s1)      # MIRROR0
        11 => x"7B249073",   -- csrw   dscratch0, s1
        12 => x"000104B7",   -- lui    s1, 0x10
        13 => x"6F44A483",   -- lw     s1, 1780(s1)      # MIRROR1
        14 => x"7B349073",   -- csrw   dscratch1, s1
        --  halted: publish TOK_HALTED.  THE DM WAITS ON THIS WORD (S_WAITH).
        15 => x"00100493",   -- li     s1, 1             # TOK_HALTED
        16 => x"70942023",   -- sw     s1, 1792(s0)
        --  poll: dispatch on the DM's token, with a register backoff
        17 => x"70042483",   -- lw     s1, 1792(s0)
        18 => x"FFC48493",   -- addi   s1, s1, -4        # TOK_GO?
        19 => x"00048E63",   -- beqz   s1, dbg_go
        20 => x"00248493",   -- addi   s1, s1, 2         # TOK_RESUME?
        21 => x"02048663",   -- beqz   s1, dbg_resume
        22 => x"04000493",   -- li     s1, 64
        23 => x"FFF48493",   -- backoff: addi s1, s1, -1
        24 => x"FE049EE3",   -- bnez   s1, backoff
        25 => x"FE1FF06F",   -- j      poll
        --  dbg_go: mirror the saved pair, then jump to the abstract body
        26 => x"000104B7",   -- lui    s1, 0x10
        27 => x"7B202473",   -- csrr   s0, dscratch0
        28 => x"6E84A823",   -- sw     s0, 1776(s1)      # MIRROR0
        29 => x"7B302473",   -- csrr   s0, dscratch1
        30 => x"6E84AA23",   -- sw     s0, 1780(s1)      # MIRROR1
        31 => x"0240006F",   -- j      W_ABST            # = _start + 4*40
        --  dbg_resume: restore the pair and leave debug mode
        32 => x"7B3024F3",   -- csrr   s1, dscratch1
        33 => x"7B202473",   -- csrr   s0, dscratch0
        34 => x"7B200073",   -- dret
        --  pad to exactly TRAMP_WORDS
        35 => x"00000013",   -- nop
        36 => x"00000013",   -- nop
        37 => x"00000013",   -- nop
        38 => x"00000013",   -- nop
        39 => x"00000013");  -- nop

    signal body_w : word_arr(0 to 7);

begin

    -- ==================================================================
    -- KNOB-OFF FOLD. Everything below lives inside gen_dm; the else arm
    -- ties every output to its fail-safe value so a knob-OFF instantiation
    -- (which the generator never emits, but a hand instantiation might)
    -- carries no state at all.
    -- ==================================================================
    gen_dm_off: if not ENABLE_DEBUG generate
        dmi_req_ready    <= '0';
        dmi_rsp_valid    <= '0';
        dmi_rsp_data     <= (others => '0');
        dmi_rsp_op       <= OP_FAIL;
        dbg_haltreq      <= (others => '0');
        dbg_resethaltreq <= (others => '0');
        m_req            <= '0';
        m_we             <= (others => '0');
        m_addr           <= (others => '0');
        m_wdata          <= (others => '0');
    end generate;

    gen_dm: if ENABLE_DEBUG generate

        -- ---- selected-hart decode ------------------------------------
        -- OUT-OF-RANGE hartsel selects a NONEXISTENT hart and is REPORTED as
        -- such. Spike CLAMPS to nprocs()-1 (debug_module.cc:1046) and that is
        -- the one reference behaviour d2_spec 3 forbids copying: a debugger's
        -- hart-count discovery probe writes all-ones and reads back
        -- anynonexistent, which a clamp makes impossible.
        sel_idx    <= conv_integer(hartsel_r);
        sel_exists <= '1' when sel_idx < NHARTS else '0';
        -- sel_safe exists because VHDL's `and` is NOT short-circuit: writing
        -- `sel_idx < NHARTS and hart_unavail(sel_idx) = '1'` evaluates the
        -- index unconditionally and is an out-of-range fault the moment a
        -- debugger probes hartsel with all-ones -- which is exactly the
        -- discovery probe NONEXISTENT exists to serve.
        sel_safe   <= sel_idx when sel_idx < NHARTS else 0;
        sel_unavail <= hart_unavail(sel_safe) and sel_exists;
        -- DM-visible state precedence, d2_spec 5: nonexistent -> unavail ->
        -- halted -> running. unavail is consulted BEFORE halted precisely so
        -- that a clamped-'0' dbg_halted from a power-gated tile can never read
        -- as either "halted" or "running".
        sel_halted  <= sel_exists and not sel_unavail and dbg_halted(sel_safe);
        sel_running <= sel_exists and not sel_unavail and not dbg_halted(sel_safe);

        -- ---- THE RE-ARMED HALT WIRE ---------------------------------
        -- See the header. One expression; the re-halt-on-resume-under-held-
        -- haltreq behaviour is a consequence of it, not a state machine.
        -- THE SELECTED-HART ARM **ORS** THE GROUP TERM, it does not replace it
        -- (review finding R1, R-D2-8(1)). The earlier form
        --     (haltreq_r and dmactive) when h = sel_idx else grp_pend(h)
        -- made a pending group halt VANISH the moment the debugger selected
        -- that hart with haltreq low -- and selecting a member to look at it is
        -- exactly what a debugger does after a group broadcast fires. The
        -- pending request is still latched in grp_pend(h) (it is only cleared
        -- by that hart's own halted rising edge), so the halt was lost for as
        -- long as the selection held and then re-appeared: a silent, selection-
        -- dependent drop. ORing keeps the two requests independent, which is
        -- what they are. Zero flops -- still one combinational expression.
        gen_hw: for h in 0 to NHARTS-1 generate
            want_halt(h) <= ((haltreq_r and dmactive) or grp_pend(h))
                            when (h = sel_idx) else grp_pend(h);
        end generate;
        gen_hq: for h in 0 to NHARTS-1 generate
            dbg_haltreq(h) <= want_halt(h) and not dbg_halted(h);
        end generate;
        dbg_resethaltreq <= rsthalt_r;

        -- ---- master engine (the DMA contract) ------------------------
        m_req   <= m_req_r;
        m_we    <= m_we_r;
        m_addr  <= m_addr_r;
        m_wdata <= m_wd_r;

        master_proc: process(clk, resetn)
        begin
            if resetn = '0' then
                m_state  <= MS_IDLE;
                m_req_r  <= '0';
                m_we_r   <= (others => '0');
                m_addr_r <= (others => '0');
                m_wd_r   <= (others => '0');
                m_rd_r   <= (others => '0');
                m_ack    <= '0';
            elsif rising_edge(clk) then
                m_ack <= '0';
                case m_state is
                    when MS_IDLE =>
                        if m_start = '1' then
                            -- THE MUTEX-PAGE GUARD (DMA.vhd:81-84's idea). The
                            -- DM must never issue a transaction outside its own
                            -- claimed band: a read of the mutex page CLAIMS a
                            -- mutex for whatever s_master reports, and the DM's
                            -- master index is not a hart.
                            assert (m_go_a >= W_BAND_LO and m_go_a <= W_BAND_HI)
                                report "debug_module: master address outside the "
                                     & "claimed debug band -- ABORTING THE "
                                     & "SIMULATION (mutex-page guard). A DM "
                                     & "transaction outside [W_BAND_LO, "
                                     & "W_BAND_HI] can CLAIM A MUTEX under a "
                                     & "non-hart s_master, so this is a design "
                                     & "error and not a recoverable condition: "
                                     & "severity failure stops the run here, it "
                                     & "does not refuse the transaction."
                                severity failure;
                            m_we_r   <= m_go_we;
                            m_addr_r <= conv_std_logic_vector(m_go_a, SH_AW);
                            m_wd_r   <= m_go_d;
                            m_req_r  <= '1';
                            m_state  <= MS_REQ;
                        end if;
                    when MS_REQ =>
                        -- HOLD everything stable through the done cycle, and
                        -- capture rdata ON it.
                        if m_done = '1' then
                            m_rd_r  <= m_rdata;
                            m_state <= MS_CAP;
                        end if;
                    when MS_CAP =>
                        -- Drop req exactly ONE clk after done (the acked flop).
                        m_req_r <= '0';
                        m_state <= MS_GAP;
                    when MS_GAP =>
                        -- One arbiter-OBSERVED req-low cycle before the next
                        -- request. Without this the arbiter's need_release
                        -- never clears and the DM is starved (M5a ghost txn).
                        m_ack   <= '1';
                        m_state <= MS_IDLE;
                end case;
            end if;
        end process;

        -- ---- the abstract body, synthesized from `command` ------------
        -- Spike's shape (debug_module.cc:748-886) adapted to VestaRV's
        -- trampoline, which already owns dscratch0/1. Because s0/s1 are
        -- already saved there, the body may use both freely and needs no
        -- save/restore of its own; a request for s0 or s1 themselves is
        -- serviced through the dscratch copy so the debugger sees the
        -- interrupted value, not the trampoline's working value.
        body_proc: process(cmd_r)
            variable regno : integer;
            variable isgpr : boolean;
            variable n     : integer;
            variable tail  : std_logic_vector(31 downto 0);
        begin
            for i in 0 to 7 loop
                body_w(i) <= i_addi(0, 0, 0);        -- nop padding
            end loop;
            regno := conv_integer(cmd_r(15 downto 0));
            isgpr := (regno >= 16#1000# and regno <= 16#101F#);
            n     := regno - 16#1000#;
            -- postexec -> jump to the program buffer, whose implicit third
            -- word jumps on to the epilogue; else straight to the epilogue.
            if cmd_r(18) = '1' then
                tail := i_jal(0, (W_PROGBUF0 - (W_ABST + 4)) * 4);
            else
                tail := i_jal(0, (W_EPILOG   - (W_ABST + 4)) * 4);
            end if;
            if cmd_r(17) = '0' then
                -- transfer = 0: postexec only. (`when/else` inside a process is
                -- VHDL-2008 and this tree compiles -V200X, so it is an if.)
                if cmd_r(18) = '1' then
                    body_w(0) <= i_jal(0, (W_PROGBUF0 - W_ABST) * 4);
                else
                    body_w(0) <= i_jal(0, (W_EPILOG - W_ABST) * 4);
                end if;
            elsif cmd_r(16) = '0' then
                -- READ reg -> data0
                if isgpr and n = R_S0 then
                    body_w(0) <= i_csrr(R_S0, CSR_DSCRATCH0);
                    body_w(1) <= i_lui (R_S1, HI20);
                    body_w(2) <= i_sw  (R_S0, R_S1, O_DATA0);
                elsif isgpr and n = R_S1 then
                    body_w(0) <= i_csrr(R_S0, CSR_DSCRATCH1);
                    body_w(1) <= i_lui (R_S1, HI20);
                    body_w(2) <= i_sw  (R_S0, R_S1, O_DATA0);
                elsif isgpr then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_sw  (n, R_S1, O_DATA0);
                    body_w(2) <= i_addi(0, 0, 0);
                else
                    body_w(0) <= i_csrr(R_S0, regno);
                    body_w(1) <= i_lui (R_S1, HI20);
                    body_w(2) <= i_sw  (R_S0, R_S1, O_DATA0);
                end if;
                body_w(3) <= i_addi(0, 0, 0);
                body_w(4) <= tail;
            else
                -- WRITE data0 -> reg
                if isgpr and n = R_S0 then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (R_S0, R_S1, O_DATA0);
                    body_w(2) <= i_csrw(CSR_DSCRATCH0, R_S0);
                elsif isgpr and n = R_S1 then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (R_S0, R_S1, O_DATA0);
                    body_w(2) <= i_csrw(CSR_DSCRATCH1, R_S0);
                elsif isgpr then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (n, R_S1, O_DATA0);
                    body_w(2) <= i_addi(0, 0, 0);
                else
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (R_S0, R_S1, O_DATA0);
                    body_w(2) <= i_csrw(regno, R_S0);
                end if;
                body_w(3) <= i_addi(0, 0, 0);
                body_w(4) <= tail;
            end if;
        end process;

        -- ---- the DMI front end + the command sequencer ---------------
        -- READY IS AN ACKNOWLEDGE, AND IT IDLES LOW. R-D2-2(7) PERMITS an
        -- idle-high ready; it does not require one, and an idle-high ready is
        -- unusable against the masters that actually drive this port. MEASURED:
        -- both BFMs raise req_valid, poll every 10 ns until they SEE req_ready
        -- high, and drop req_valid immediately on seeing it. mclk's period is
        -- 41.667 ns, so against an idle-high ready the master takes its request
        -- down ~10 ns after raising it -- usually before any rising edge falls
        -- inside the window -- and the request is simply never sampled. The
        -- observed symptom was XACT_NO_RSP on some transactions and, worse, the
        -- PREVIOUS transaction's data on the rest.
        -- Idling low and raising ready the cycle a request is CAPTURED satisfies
        -- the same ruling ("a request transfers on the cycle valid and ready")
        -- and works for both master shapes: a master that holds valid until it
        -- sees ready, and one that drops it the moment it does.
        -- NOTE ready is NOT held low for the whole abstract command: the command
        -- runs in the background behind `busy`, because a debugger MUST be able
        -- to poll abstractcs.busy while it is in flight.
        -- The master engine has ONE owner at a time. A DMI access that needs
        -- it while the sequencer already does gets cmderr = BUSY rather than
        -- a silently interleaved transaction -- which is also the debug spec's
        -- own answer for touching data0/progbuf while an abstract command runs.
        mst_free      <= '1' when s_state = S_IDLE else '0';
        dmi_req_ready <= ready_r;
        dmi_rsp_valid <= rsp_valid_r;
        dmi_rsp_data  <= rsp_data_r;
        dmi_rsp_op    <= rsp_op_r;

        main_proc: process(clk, resetn)
            variable a   : std_logic_vector(6 downto 0);
            variable d   : std_logic_vector(31 downto 0);
            variable wr  : boolean;
            variable rd  : boolean;
            variable hs  : integer;
            variable g   : std_logic_vector(2 downto 0);
            variable rsp : std_logic_vector(31 downto 0);
        begin
            if resetn = '0' then
                dmactive    <= '0';
                haltreq_r   <= '0';
                hartsel_r   <= (others => '0');
                rsthalt_r   <= (others => '0');
                resumeack_r <= (others => '0');
                havereset_r <= (others => '1');   -- every hart has just reset
                cmderr_r    <= ERR_NONE;
                busy_r      <= '0';
                grp_pend    <= (others => '0');
                halted_d    <= (others => '0');
                resume_pend <= (others => '0');
                epi_done    <= '0';
                tramp_arm   <= '0';
                tramp_halt  <= '0';
                s_state     <= S_IDLE;
                step        <= 0;
                cmd_r       <= (others => '0');
                cmd_hart    <= 0;
                res_hart    <= 0;
                res_busy    <= '0';
                waith_go    <= '0';
                poll_to     <= 0;
                rsp_valid_r <= '0';
                rsp_data_r  <= (others => '0');
                rsp_op_r    <= OP_OK;
                pend_wr     <= '0';
                ready_r     <= '0';
                rsp_hold    <= 0;
                rsp_arm     <= '0';
                m_start     <= '0';
                m_go_we     <= (others => '0');
                m_go_a      <= 0;
                m_go_d      <= (others => '0');
                for i in 0 to NHARTS-1 loop
                    grp_r(i) <= (others => '0');
                end loop;
            elsif rising_edge(clk) then
                m_start  <= '0';
                ready_r  <= '0';          -- the acknowledge is a ONE-CYCLE pulse
                rsp_arm  <= '0';
                halted_d <= dbg_halted;
                if rsp_arm = '1' then
                    rsp_valid_r <= '1';
                    rsp_hold    <= RSP_HOLD_CYCLES;
                end if;
                if rsp_hold > 0 then
                    rsp_hold <= rsp_hold - 1;
                    if rsp_hold = 1 then
                        rsp_valid_r <= '0';
                    end if;
                end if;

                -- ---- per-hart edge bookkeeping -----------------------
                for i in 0 to NHARTS-1 loop
                    -- a hart that HALTS clears its group-broadcast request and
                    -- (if it was the one we asked to resume) closes the resume.
                    if dbg_halted(i) = '1' and halted_d(i) = '0' then
                        grp_pend(i) <= '0';
                        -- D4: a NEW halt owes a plant. It is not taken here --
                        -- see THE PLANT in the header for why an eager plant on
                        -- this edge would drop a busy window on top of the first
                        -- thing a debugger does. The bit is consumed on the way
                        -- into S_WAITH, which is the moment the ordering clause
                        -- actually names.
                        tramp_halt <= '1';
                        -- HALT GROUPS: when any member of a non-zero group
                        -- halts, every OTHER member is asked to halt too. One
                        -- re-armed pulse each -- grp_pend is cleared by that
                        -- hart's own halt, above.
                        if grp_r(i) /= "000" then
                            for j in 0 to NHARTS-1 loop
                                -- ...but ONLY to a member that is not ALREADY
                                -- halted. MEASURED DEFECT, 2026-08-06, and it
                                -- was masked by the S_RESWAIT one so the two
                                -- cancelled: `grp_pend` is cleared by its
                                -- hart's own halted RISING edge, so a request
                                -- raised at a hart that is already halted is
                                -- never consumed -- it sits there and RE-HALTS
                                -- that hart the moment the debugger resumes it
                                -- and hartsel moves elsewhere (want_halt falls
                                -- back to grp_pend for a non-selected hart).
                                -- The group condition "when any member halts,
                                -- every other member halts" is satisfied by a
                                -- hart that is already halted; the request is
                                -- vacuous and must not be latched.
                                if j /= i and grp_r(j) = grp_r(i)
                                   and dbg_halted(j) = '0' then
                                    grp_pend(j) <= '1';
                                end if;
                            end loop;
                        end if;
                    end if;
                    -- resumeack sets on the halted FALLING edge attributable to
                    -- a resumereq, and stays set until the next resumereq write
                    -- (d2_spec 4). It is a level, not a pulse: J2 reads it twice.
                    if dbg_halted(i) = '0' and halted_d(i) = '1'
                       and resume_pend(i) = '1' then
                        resumeack_r(i) <= '1';
                        resume_pend(i) <= '0';
                        res_busy       <= '0';
                    end if;
                end loop;

                -- ==========================================================
                -- the sequencer
                -- ==========================================================
                case s_state is

                    when S_IDLE =>
                        -- D4: THE EAGER PLANT, taken first. dmactive has just
                        -- risen and nothing else can be in flight in S_IDLE, so
                        -- there is no ordering question here -- a queued resume
                        -- is not dropped, only delayed by the stream (the
                        -- R-D2-5(2) prohibition is on silent DROPS, and this is
                        -- neither silent nor a drop: the DM returns to S_IDLE
                        -- and picks the resume up on the next visit).
                        -- tramp_arm is cleared by S_TRAMP itself and not here,
                        -- so that a command accepted in the very same cycle --
                        -- which overrides s_state further down this process --
                        -- DEFERS the plant instead of losing it. That race is
                        -- unreachable in practice (the accept that set dmactive
                        -- arms rsp_hold, which blocks the next accept for eight
                        -- cycles) but the cheap ordering is the honest one.
                        if tramp_arm = '1' and dmactive = '1' then
                            step    <= 0;
                            s_state <= S_TRAMP;
                        -- Service a queued resume for a hart that is halted.
                        elsif res_busy = '0' then
                            for i in 0 to NHARTS-1 loop
                                if resume_pend(i) = '1' and dbg_halted(i) = '1'
                                   and res_busy = '0' then
                                    res_hart <= i;
                                    res_busy <= '1';
                                    waith_go <= '0';
                                    step     <= 0;
                                    -- RESET THE BOUND ON ARM (review finding R2,
                                    -- R-D2-8(2)). poll_to is shared by S_WAITH,
                                    -- S_POLL and S_RESWAIT and is zeroed only on
                                    -- the COMMAND path (the A_COMMAND accept and
                                    -- S_GO). A resume arms S_WAITH with whatever
                                    -- the previous flow left behind -- at or near
                                    -- POLL_LIMIT after any completed command --
                                    -- and the wait then expires before the hart
                                    -- can possibly publish TOK_HALTED. Zero
                                    -- flops: poll_to already exists.
                                    poll_to  <= 0;
                                    -- D4: the LAZY plant. This arm is one of
                                    -- exactly two entries into the TOK_HALTED
                                    -- wait, and d4_spec 1.2 puts the re-stream
                                    -- ahead of both ("before any S_WAITH wait
                                    -- on it, before any GO/RESUME write").
                                    if tramp_halt = '1' then
                                        s_state <= S_TRAMP;
                                    else
                                        s_state <= S_WAITH;
                                    end if;
                                end if;
                            end loop;
                        end if;

                    -- ---- data0 / progbuf proxy read or write -----------
                    when S_PROXY =>
                        if m_ack = '1' then
                            s_state <= S_PROXY_RSP;
                        end if;
                    when S_PROXY_RSP =>
                        rsp_arm     <= '1';
                        rsp_op_r    <= OP_OK;
                        if pend_wr = '1' then
                            rsp_data_r <= (others => '0');
                        else
                            rsp_data_r <= m_rd_r;
                        end if;
                        s_state <= S_IDLE;

                    -- ---- D4: stream the trampoline into the entry page ----
                    -- Structurally S_EPI with a longer table and a computed
                    -- exit. Same `step`, same m_go_*/m_start handshake, same
                    -- one-word-per-m_ack cadence; `step` is already `range 0 to
                    -- 63` and 40 <= 63, so nothing widens.
                    when S_TRAMP =>
                        if m_ack = '1' or step = 0 then
                            if step <= TRAMP_WORDS-1 then
                                if step = 0 then
                                    -- BOTH owed-bits clear as the stream
                                    -- STARTS, not as it finishes. A hart that
                                    -- halts DURING the stream therefore keeps
                                    -- its own claim on a later plant, which is
                                    -- the direction that cannot lose one: the
                                    -- words it fetches while the stream is
                                    -- mid-flight may still be stale, and the
                                    -- F-D2-0 re-entry spin is what carries it
                                    -- to the next plant. (A hart that halts in
                                    -- this exact cycle loses the race by one
                                    -- clock and is covered by the same spin --
                                    -- the stream it is racing began at or after
                                    -- its own halt, so the page is repaired
                                    -- either way.)
                                    tramp_arm  <= '0';
                                    tramp_halt <= '0';
                                end if;
                                m_go_we <= "1111";
                                m_go_a  <= W_ENTRY + step;
                                m_go_d  <= TRAMP(step);
                                m_start <= '1';
                                step    <= step + 1;
                            else
                                step <= 0;
                                -- Where to go back. See S_TRAMP's declaration:
                                -- these two are the signature of a plant that
                                -- was owed to a TOK_HALTED wait.
                                if busy_r = '1' or res_busy = '1' then
                                    s_state <= S_WAITH;
                                else
                                    s_state <= S_IDLE;
                                end if;
                            end if;
                        end if;

                    -- ---- abstract command: write the epilogue once ----
                    when S_EPI =>
                        if m_ack = '1' or step = 0 then
                            if step <= 8 then
                                m_go_we <= "1111";
                                m_go_a  <= W_EPILOG + step;
                                m_go_d  <= EPILOGUE(step);
                                m_start <= '1';
                                step    <= step + 1;
                            else
                                epi_done <= '1';
                                step     <= 0;
                                s_state  <= S_IMPL;
                            end if;
                        end if;

                    when S_IMPL =>
                        if m_ack = '1' or step = 0 then
                            if step = 0 then
                                m_go_we <= "1111";
                                m_go_a  <= W_IMPLICIT;
                                m_go_d  <= I_IMPLICIT;
                                m_start <= '1';
                                step    <= 1;
                            else
                                step    <= 0;
                                s_state <= S_BODY;
                            end if;
                        end if;

                    when S_BODY =>
                        if m_ack = '1' or step = 0 then
                            if step <= 7 then
                                m_go_we <= "1111";
                                m_go_a  <= W_ABST + step;
                                m_go_d  <= body_w(step);
                                m_start <= '1';
                                step    <= step + 1;
                            else
                                step     <= 0;
                                waith_go <= '1';
                                -- D4: the LAZY plant, the other of the two
                                -- entries into the TOK_HALTED wait. It sits
                                -- here rather than at the command accept on
                                -- purpose: the whole stream then runs INSIDE
                                -- the busy window this command already owns,
                                -- so it costs the debugger no window of its
                                -- own. It is also after S_BODY and not before
                                -- it, so the abstract area (words 40..47) and
                                -- the trampoline (words 0..39) are written in
                                -- an order that leaves both correct -- they do
                                -- not overlap, but a reader should not have to
                                -- re-derive that.
                                if tramp_halt = '1' then
                                    s_state <= S_TRAMP;
                                else
                                    s_state <= S_WAITH;
                                end if;
                            end if;
                        end if;

                    when S_WAITH =>
                        -- Poll FLAGS[h] until the HART has published TOK_HALTED.
                        if poll_to < POLL_LIMIT then
                            poll_to <= poll_to + 1;
                        end if;
                        if m_ack = '1' then
                            if m_rd_r = conv_std_logic_vector(TOK_HALTED, 32) then
                                step <= 0;
                                if waith_go = '1' then
                                    s_state <= S_GO;
                                else
                                    s_state <= S_RESUME;
                                end if;
                            else
                                step <= 0;
                            end if;
                        elsif poll_to >= POLL_LIMIT then
                            -- bounded: fail the command rather than hang
                            if waith_go = '1' then
                                cmderr_r <= ERR_OTHER;
                                s_state  <= S_FIN;
                            else
                                -- CLEAR THE PEND ON THE RESUME-PATH TIMEOUT TOO
                                -- (review finding R3, R-D2-8(3)), exactly as
                                -- S_RESWAIT's timeout below already does.
                                -- Without it the DM returns to S_IDLE with
                                -- resume_pend(res_hart) still set and the hart
                                -- still halted -- which is S_IDLE's arm
                                -- condition -- so the wait re-arms forever and
                                -- mst_free never rises again: every data0/
                                -- progbuf proxy answers cmderr = BUSY from then
                                -- on. The drop is BOUNDED and VISIBLE
                                -- (resumeack stays 0, so a debugger polling
                                -- dmstatus sees the resume did not happen); it
                                -- is not the silent-drop class R-D2-5(2)
                                -- prohibits. Zero flops.
                                resume_pend(res_hart) <= '0';
                                res_busy <= '0';
                                s_state  <= S_IDLE;
                            end if;
                        elsif step = 0 then
                            m_go_we <= "0000";
                            if waith_go = '1' then
                                m_go_a <= W_FLAGS0 + cmd_hart;
                            else
                                m_go_a <= W_FLAGS0 + res_hart;
                            end if;
                            m_go_d  <= (others => '0');
                            m_start <= '1';
                            step    <= 1;
                        end if;

                    when S_GO =>
                        if m_ack = '1' or step = 0 then
                            if step = 0 then
                                m_go_we <= "1111";
                                m_go_a  <= W_FLAGS0 + cmd_hart;
                                m_go_d  <= conv_std_logic_vector(TOK_GO, 32);
                                m_start <= '1';
                                step    <= 1;
                            else
                                step    <= 0;
                                poll_to <= 0;
                                s_state <= S_POLL;
                            end if;
                        end if;

                    when S_POLL =>
                        -- Read FLAGS[h] back until the hart reports. TOK_DONE
                        -- = the sequence ran to its end. ANY OTHER value once
                        -- the hart is halted again and no longer GO -- i.e.
                        -- TOK_HALTED, written by the trampoline on re-entry --
                        -- means the sequence did NOT reach its epilogue, which
                        -- is exactly the F-D2-0 exception re-entry.
                        if poll_to < POLL_LIMIT then
                            poll_to <= poll_to + 1;
                        end if;
                        if m_ack = '1' then
                            if m_rd_r = conv_std_logic_vector(TOK_DONE, 32) then
                                cmderr_r <= ERR_NONE;
                                s_state  <= S_FIN;
                            elsif m_rd_r = conv_std_logic_vector(TOK_HALTED, 32) then
                                cmderr_r <= ERR_EXCEPT;
                                s_state  <= S_FIN;
                            else
                                step <= 0;
                            end if;
                        elsif poll_to >= POLL_LIMIT then
                            -- The hart never reported. Bounded, so an
                            -- instrument FAILS instead of hanging.
                            cmderr_r <= ERR_OTHER;
                            s_state  <= S_FIN;
                        elsif step = 0 then
                            m_go_we <= "0000";
                            m_go_a  <= W_FLAGS0 + cmd_hart;
                            m_go_d  <= (others => '0');
                            m_start <= '1';
                            step    <= 1;
                        end if;

                    when S_FIN =>
                        busy_r  <= '0';
                        step    <= 0;
                        s_state <= S_IDLE;

                    when S_RESUME =>
                        if m_ack = '1' then
                            -- res_busy STAYS SET: see S_RESWAIT's declaration.
                            poll_to <= 0;
                            step    <= 0;
                            s_state <= S_RESWAIT;
                        elsif step = 0 then
                            m_go_we <= "1111";
                            m_go_a  <= W_FLAGS0 + res_hart;
                            m_go_d  <= conv_std_logic_vector(TOK_RESUME, 32);
                            m_start <= '1';
                            step    <= 1;
                        end if;

                    when S_RESWAIT =>
                        -- The resume has been DISPATCHED; hold the engine until
                        -- it has been TAKEN. The exit condition is
                        -- resume_pend(res_hart) going low, which the per-hart
                        -- bookkeeping above does on the attributable halted
                        -- FALLING edge -- an edge detector, so a resume that is
                        -- immediately followed by a re-halt (the R-D2-2(5)
                        -- re-armed-wire case, where the hart runs for only a
                        -- handful of instructions) cannot be missed the way a
                        -- level test of dbg_halted could.
                        -- BOUNDED, like every other wait here: a hart that
                        -- never leaves debug mode must FAIL a debugger's
                        -- expectation, never wedge the DM.
                        if poll_to < POLL_LIMIT then
                            poll_to <= poll_to + 1;
                        end if;
                        if resume_pend(res_hart) = '0' then
                            res_busy <= '0';
                            s_state  <= S_IDLE;
                        elsif poll_to >= POLL_LIMIT then
                            resume_pend(res_hart) <= '0';
                            res_busy <= '0';
                            s_state  <= S_IDLE;
                        end if;
                end case;

                -- ==========================================================
                -- DMI request acceptance. ONE REQUEST IN FLIGHT, ACK-STYLE
                -- HANDSHAKE (R-D2-4(2), which SUPERSEDES R-D2-2(7)'s "ready may
                -- idle high" -- an idle-high ready loses the request against the
                -- masters that actually drive this port). ready_r idles LOW and
                -- pulses for exactly ONE cycle on the cycle the request is
                -- CAPTURED: one accept per assertion of dmi_req_valid, with
                -- rsp_hold / rsp_arm as the re-capture lockout. The response is
                -- armed here and asserted one cycle later, then held
                -- RSP_HOLD_CYCLES. See the ready/rsp commentary above the
                -- process for the measurements behind each of those three.
                --
                -- S_TRAMP JOINS S_PROXY/S_PROXY_RSP IN THE EXCLUSION, and this
                -- is a MEASURED correction, not a precaution (2026-08-07).
                -- The plant is an internal, bounded, ATOMIC multi-word
                -- operation that owns the master engine -- the same class as a
                -- proxy access, which is why the same answer applies: the DM
                -- simply does not raise `ready` while it runs, and the master
                -- waits. It is over in ~40 arbiter round trips (~13 us), far
                -- less than one JTAG DMI round trip.
                -- WHAT HAPPENS WITHOUT IT, measured on the existing D1/D2/D3
                -- instrument matrix: the attach-time plant fires on the first
                -- dmcontrol write, and a debugger that issues an abstract
                -- command a few microseconds later -- which is what every one
                -- of them does -- is told cmderr = BUSY for something it did
                -- nothing to deserve. cmderr is STICKY and `command` writes are
                -- ignored while it is set, so ONE such answer at attach
                -- silently disables every abstract command for the rest of the
                -- session: dbg_abs went 10-of-13 red, dbg_conf 5-of-38,
                -- dbg_prv 4-of-6. The control that named the cause is
                -- dbg_tapreplay, which runs dbg_conf's SAME 38 checks over the
                -- TAP and passed 38/38 -- slow transport, no collision.
                -- This does not redefine any busy semantic: the two windows
                -- that existed before D4 (busy_r = '1' under a command, and the
                -- resume path's S_WAITH with busy_r = '0') still answer exactly
                -- as they were measured to. The plant is simply not a
                -- DMI-visible window at all, which is what `ready` is for.
                -- ==========================================================
                if dmi_req_valid = '1' and rsp_hold = 0 and rsp_arm = '0'
                   and s_state /= S_PROXY and s_state /= S_PROXY_RSP
                   and s_state /= S_TRAMP then
                    ready_r  <= '1';       -- one-cycle acknowledge
                    a   := dmi_req_addr;
                    d   := dmi_req_data;
                    wr  := (dmi_req_op = "10");
                    rd  := (dmi_req_op = "01");
                    rsp := (others => '0');
                    -- `when/else` is VHDL-2008; -V200X wants the if.
                    if wr then
                        pend_wr <= '1';
                    else
                        pend_wr <= '0';
                    end if;

                    -- default: answer NEXT cycle, then hold for RSP_HOLD_CYCLES
                    rsp_arm     <= '1';
                    rsp_op_r    <= OP_OK;

                    if a = A_DMCONTROL then
                        if wr then
                            dmactive  <= d(0);
                            if d(0) = '0' then
                                -- dmactive low resets the DM's own state, per
                                -- the debug spec; it does NOT reset the harts
                                -- (ndmreset is read-zero WARL at D2).
                                haltreq_r   <= '0';
                                rsthalt_r   <= (others => '0');
                                grp_pend    <= (others => '0');
                                resume_pend <= (others => '0');
                                busy_r      <= '0';
                                cmderr_r    <= ERR_NONE;
                                -- D4 (the d4_probe C4 named edit). The
                                -- plant-owed bits and the epilogue's write-once
                                -- latch all clear here, so a dmactive toggle
                                -- really does re-plant everything the DM owns
                                -- in the page. Before D4 epi_done cleared ONLY
                                -- on resetn, which made "toggle dmactive to
                                -- recover" a no-op; see epi_done's declaration
                                -- for the priced consequence of adding it.
                                tramp_arm   <= '0';
                                tramp_halt  <= '0';
                                epi_done    <= '0';
                            else
                                -- THE RISE, and only the rise. Every dmstatus
                                -- poll writes dmcontrol with dmactive set, so a
                                -- plant armed on the LEVEL would re-arm forever
                                -- and pin the master engine.
                                if dmactive = '0' then
                                    tramp_arm <= '1';
                                end if;
                                haltreq_r <= d(31);
                                hartsel_r <= d(25 downto 16);
                                hs := conv_integer(d(25 downto 16));
                                -- resumereq is W1 and only means anything for a
                                -- HALTED, existing, available hart. NESTED ifs,
                                -- not one `and` chain: VHDL does not
                                -- short-circuit, so `hs < NHARTS and
                                -- dbg_halted(hs)` would index out of range on
                                -- the very probe (hartsel = all ones) that
                                -- NONEXISTENT exists to answer.
                                if hs < NHARTS then
                                    if d(30) = '1' and dbg_halted(hs) = '1'
                                       and hart_unavail(hs) = '0' then
                                        -- QUEUE it (R-D2-5(2)); the sequencer
                                        -- picks it up from S_IDLE. Never
                                        -- refused, never dropped.
                                        resume_pend(hs) <= '1';
                                        resumeack_r(hs) <= '0';
                                    end if;
                                    if d(28) = '1' then
                                        havereset_r(hs) <= '0';
                                    end if;
                                end if;
                                -- setresethaltreq / clrresethaltreq. NO Spike
                                -- reference exists for these (it implements
                                -- neither, and reports hasresethaltreq = 0);
                                -- spec text only, and VestaRV reports 1
                                -- because D1 shipped the wire.
                                if hs < NHARTS then
                                    if d(3) = '1' then
                                        rsthalt_r(hs) <= '1';
                                    elsif d(2) = '1' then
                                        rsthalt_r(hs) <= '0';
                                    end if;
                                end if;
                            end if;
                        else
                            rsp(0)  := dmactive;
                            rsp(31) := haltreq_r;
                            rsp(25 downto 16) := hartsel_r;
                            if sel_idx < NHARTS then
                                rsp(3) := rsthalt_r(sel_idx);
                            end if;
                            rsp_data_r <= rsp;
                        end if;

                    elsif a = A_DMSTATUS then
                        -- version = 3 (1.0). Spike reports 2 (0.13) and
                        -- d2_spec 3 forbids copying that.
                        rsp(3 downto 0) := "0011";
                        rsp(7)  := '1';                 -- authenticated
                        rsp(5)  := '1';                 -- hasresethaltreq
                        rsp(22) := '1';                 -- impebreak
                        -- With hasel dropped, both bits of every any/all pair
                        -- mirror the selected hart -- and BOTH must be driven
                        -- or OpenOCD misreads them.
                        rsp(9)  := sel_halted;   rsp(8)  := sel_halted;
                        rsp(11) := sel_running;  rsp(10) := sel_running;
                        rsp(13) := sel_unavail;  rsp(12) := sel_unavail;
                        rsp(15) := not sel_exists; rsp(14) := not sel_exists;
                        if sel_idx < NHARTS then
                            rsp(17) := resumeack_r(sel_idx);
                            rsp(16) := resumeack_r(sel_idx);
                            rsp(19) := havereset_r(sel_idx);
                            rsp(18) := havereset_r(sel_idx);
                        end if;
                        rsp_data_r <= rsp;

                    elsif a = A_HARTINFO then
                        rsp(11 downto 0)  := DATA0_ADDR(11 downto 0);  -- dataaddr
                        rsp(15 downto 12) := x"1";                     -- datasize
                        rsp(16)           := '1';                      -- dataaccess
                        rsp_data_r <= rsp;

                    elsif a = A_HALTSUM0 then
                        -- One 32-bit register covers both chips (4 <= 32,
                        -- 18 <= 32). Spike implements NEITHER haltsum, so this
                        -- is spec-text only (d2_probe P6/P10).
                        for i in 0 to NHARTS-1 loop
                            rsp(i) := dbg_halted(i) and not hart_unavail(i);
                        end loop;
                        rsp_data_r <= rsp;

                    elsif a = A_HALTSUM1 then
                        -- reads zero SUCCESS, stated in d2_spec 2 because a
                        -- debugger probes it and Spike answers `failed`.
                        rsp_data_r <= (others => '0');

                    elsif a = A_ABSTRACTCS then
                        if wr then
                            -- cmderr is W1C.
                            if d(10 downto 8) /= "000" then
                                cmderr_r <= cmderr_r and not d(10 downto 8);
                            end if;
                        else
                            rsp(28 downto 24) := "00010";   -- progbufsize = 2
                            rsp(3 downto 0)   := "0001";    -- datacount   = 1
                            rsp(12)           := busy_r;
                            rsp(10 downto 8)  := cmderr_r;
                            rsp_data_r <= rsp;
                        end if;

                    elsif a = A_ABSTAUTO then
                        rsp_data_r <= (others => '0');      -- read-zero

                    elsif a = A_DMCS2 then
                        if wr then
                            -- hgselect = 0 (harts) only; hgwrite commits the
                            -- group of the SELECTED hart. grouptype 0.
                            if d(0) = '0' and d(1) = '1' and sel_idx < NHARTS then
                                grp_r(sel_idx) <= d(4 downto 2);
                            end if;
                        else
                            if sel_idx < NHARTS then
                                rsp(6 downto 2) := "00" & grp_r(sel_idx);
                            end if;
                            rsp_data_r <= rsp;
                        end if;

                    elsif a = A_COMMAND then
                        if wr then
                            -- NO ABSTRACT COMMAND STARTS WHILE cmderr IS SET
                            -- (review finding R5, R-D2-8(5)). The debug spec's
                            -- `command` register text is three sentences, and
                            -- the last two decide this precedence:
                            --   "Writing this register while an abstract
                            --    command is executing causes cmderr to be set
                            --    to 1 (busy) IF IT IS 0."
                            --   "If cmderr is non-zero, writes to this register
                            --    are ignored."
                            -- Both point the same way, which is why the guard
                            -- goes FIRST and not after the busy check: the busy
                            -- rule is itself qualified by "if it is 0", so a
                            -- write that arrives busy AND with cmderr already
                            -- set must NOT overwrite the standing error with
                            -- BUSY, and the second sentence makes the whole
                            -- write a no-op anyway. With cmderr = 0 the busy
                            -- check below is reached unchanged and still answers
                            -- ERR_BUSY. Ignored means IGNORED: no start, no
                            -- cmderr change, no NEW error raised -- the debugger
                            -- clears the standing one with the abstractcs W1C
                            -- and writes `command` again. Before this guard, a
                            -- command written with a standing cmderr both ran
                            -- and CLEARED the error on the way past (the success
                            -- arm assigns ERR_NONE), destroying the diagnosis a
                            -- debugger had not yet read. Zero flops.
                            if cmderr_r /= ERR_NONE then
                                null;
                            elsif busy_r = '1' then
                                cmderr_r <= ERR_BUSY;
                            elsif d(31 downto 24) /= x"00" then
                                -- cmdtype 2 (access memory) -> NOT_SUPPORTED.
                                -- THAT IS DD5's memory answer: the debugger
                                -- falls back to progbuf lw/sw through the hart,
                                -- which exercises the real bus path.
                                cmderr_r <= ERR_NOTSUP;
                            elsif d(22 downto 20) /= "010" then
                                cmderr_r <= ERR_NOTSUP;     -- aarsize /= 32 bit
                            elsif sel_halted = '0' then
                                cmderr_r <= ERR_HALTRES;
                            elsif mst_free = '0' then
                                cmderr_r <= ERR_BUSY;
                            else
                                -- The command WRITE completes NOW (ready stays
                                -- high); the command itself runs in the
                                -- background behind `busy`, which is what the
                                -- debugger polls.
                                cmd_r    <= d;
                                cmd_hart <= sel_safe;
                                busy_r   <= '1';
                                cmderr_r <= ERR_NONE;
                                step     <= 0;
                                poll_to  <= 0;
                                if epi_done = '1' then
                                    s_state <= S_IMPL;
                                else
                                    s_state <= S_EPI;
                                end if;
                            end if;
                        else
                            rsp_data_r <= (others => '0');  -- command reads 0
                        end if;

                    elsif a = A_DATA0 or a = A_PROGBUF0 or a = A_PROGBUF1 then
                        -- PROXIED to the backing word through a master access.
                        -- Multi-cycle: ready is a REGISTERED one-cycle pulse
                        -- (dmi_req_ready <= ready_r) that has already fired for
                        -- this request, the accept guard above excludes S_PROXY
                        -- / S_PROXY_RSP so no further request is taken, and the
                        -- response is issued by S_PROXY_RSP.  (Corrected at D3,
                        -- d3_spec 3: this comment used to call ready
                        -- "combinational from s_state".  It never was.)
                        if mst_free = '0' then
                            -- Touching data0/progbuf while the master engine is
                            -- busy is an ERROR the debug spec already names:
                            -- report cmderr = BUSY, answer the DMI access now,
                            -- and never interleave a second master transaction.
                            cmderr_r   <= ERR_BUSY;
                            rsp_data_r <= (others => '0');
                        else
                            rsp_arm     <= '0';
                            rsp_valid_r <= '0';
                            rsp_hold    <= 0;
                            step        <= 0;
                            if a = A_DATA0 then
                                m_go_a <= W_DATA0;
                            elsif a = A_PROGBUF0 then
                                m_go_a <= W_PROGBUF0;
                            else
                                m_go_a <= W_PROGBUF1;
                            end if;
                            if wr then
                                m_go_we <= "1111";
                                m_go_d  <= d;
                            else
                                m_go_we <= "0000";
                                m_go_d  <= (others => '0');
                            end if;
                            m_start <= '1';
                            s_state <= S_PROXY;
                        end if;

                    else
                        -- Unimplemented DMI address -> failed (d2_spec 2).
                        rsp_op_r   <= OP_FAIL;
                        rsp_data_r <= (others => '0');
                    end if;
                end if;
            end if;
        end process;

    end generate;

end architecture;
