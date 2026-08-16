/* =============================================================================
   debug_module.vhd: the chip's Debug Module, one per chip at assembly level, always-on mclk domain, never inside a tile.
   DMI register file, per-hart run control, abstract access-register commands, a 2-word program buffer with an implicit third word, and halt groups.
   It is an mp_arbiter master because an abstract command is CODE the halted hart executes out of the shared window; a tile's TCM is unreachable from the shared bus.
   No DTM/TAP, no triggers, no System Bus Access: sbcs reads all-zeros ("no system bus"), 0x39-0x3F answer failed, and memory access is progbuf lw/sw through the hart.
   ENABLE_DEBUG false folds the whole block: no master requests, no halt requests, dmi_req_ready low, no reachable flops.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity debug_module is
    generic (
        -- Fail-safe OFF at every declaration site.
        ENABLE_DEBUG : boolean := false;
        -- Hart count, wired from the generator like clint/irq_router; there is no NHARTS constant in MemoryMap.vhd and the DM must not invent one.
        NHARTS       : natural := 4;
        -- Shared-window word-address width (MCU's SH_AW). word = byte(16:2).
        SH_AW        : natural := 15;
        -- The claimed band, as BYTE addresses; generics so a bench can re-aim the whole block.
        DATA0_ADDR   : std_logic_vector(31 downto 0) := x"00010680";
        FLAGS_ADDR   : std_logic_vector(31 downto 0) := x"00010700";
        ENTRY_ADDR   : std_logic_vector(31 downto 0) := x"00010780"
    );
    port (
        clk    : in  std_logic;                       -- free-running mclk
        resetn : in  std_logic;

        -- ---- DMI (the DTM drives this port unchanged) --------------------
        -- Every INPUT is defaulted so an MCU that does not connect them stays legal.
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
        -- unavail(h): the hart exists but the DM cannot reach it, driven at the instantiation site from isolation/reset state (hart 0 included, its boot gate can hold it in reset).
        -- Defaulted all-zeros so an unconnected instance reports every hart available rather than every hart missing.
        hart_unavail : in  std_logic_vector(NHARTS-1 downto 0) := (others => '0');

        -- ---- shared-bus MASTER port (one mp_arbiter master slice) --------
        -- Same shape and protocol as DMA.vhd's; m_we is 4 ACTIVE-HIGH byte-lane strobes ("0000" = read).
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

    /* ------------------------------------------------------------------
       Layout constants, WORD addresses (the arbiter's unit), all derived from the generics so a re-aimed block stays self-consistent.
       ------------------------------------------------------------------ */
    -- Byte address to shared-window word address.
    function w(a : std_logic_vector(31 downto 0)) return integer is
    begin
        return conv_integer(a(SH_AW+1 downto 2));
    end function;

    constant W_DATA0    : integer := w(DATA0_ADDR);          -- 0x10680
    constant W_PROGBUF0 : integer := w(DATA0_ADDR) + 1;      -- 0x10684
    constant W_PROGBUF1 : integer := w(DATA0_ADDR) + 2;      -- 0x10688
    constant W_IMPLICIT : integer := w(DATA0_ADDR) + 3;      -- 0x1068C
    -- The program-buffer stubs, in the DM-reserved band 0x10690-0x106FC and clear of MIRROR0/MIRROR1 at 0x106F0 and 0x106F4: PB_ENTER is 3 words and PB_LEAVE is 11, so the pair occupies 0x10690-0x106C4.
    -- PBSTUB_WORDS is the ONE number S_EPI streams from; keep it in step with the two arrays, nothing else checks the arithmetic.
    constant W_PBSTUB   : integer := w(DATA0_ADDR) + 4;      -- 0x10690
    constant W_PB_LEAVE : integer := W_PBSTUB + 3;           -- 0x1069C
    constant PBSTUB_WORDS : integer := 14;                   -- 3 + 11
    constant W_FLAGS0   : integer := w(FLAGS_ADDR);          -- 0x10700
    constant W_ENTRY    : integer := w(ENTRY_ADDR);          -- 0x10780
    -- Entry page word layout: 0..39 trampoline, 40..47 abstract body, 48..56 epilogue, 57..63 spare.
    -- The trampoline's length is the coupling: its dispatch ends in `jal x0, _start + 4*TRAMP_WORDS`, so W_ABST is not a free choice and the length is written ONCE here.
    constant TRAMP_WORDS: integer := 40;
    constant W_ABST     : integer := W_ENTRY + TRAMP_WORDS;  -- 0x10820
    constant W_EPILOG   : integer := W_ENTRY + 48;           -- 0x10840

    -- The band the mutex-page guard checks against: everything the DM may ever touch lies in [W_DATA0 .. W_ENTRY+63].
    constant W_BAND_LO  : integer := W_DATA0;
    constant W_BAND_HI  : integer := W_ENTRY + 63;

    /* ------------------------------------------------------------------
       FLAGS[h] handshake tokens, single-writer-per-state: the DM writes GO and RESUME, the hart writes HALTED and DONE; changing them without changing dbg_trampoline.S breaks the handshake.
       Small positive immediates, and BIT 2 IS SET IN EXACTLY THE TWO VALUES A RE-ENTRY CAN SEE (GO, DONE) and clear in the two a first entry can see (0, RESUME), which is how the trampoline repairs its dscratch save with one `andi`.
       ------------------------------------------------------------------ */
    constant TOK_HALTED : integer := 1;
    constant TOK_RESUME : integer := 2;
    constant TOK_GO     : integer := 4;
    constant TOK_DONE   : integer := 12;
    -- The PROGRAM-BUFFER completion token, and BIT 2 CLEAR is the whole trick: it takes the trampoline's FIRST-ENTRY path, so the tentative dscratch save of s0/s1 stands instead of being repaired from the mirror.
    -- That adopts the values the program buffer left, with no new branch and without changing a trampoline word.
    constant TOK_PBDONE : integer := 8;

    /* ------------------------------------------------------------------
       DMI register addresses (debug_defines.h).
       ------------------------------------------------------------------ */
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
    constant A_SBCS      : std_logic_vector(6 downto 0) := "0111000";  -- 0x38
    constant A_HALTSUM0  : std_logic_vector(6 downto 0) := "1000000";  -- 0x40

    constant OP_OK   : std_logic_vector(1 downto 0) := "00";
    constant OP_FAIL : std_logic_vector(1 downto 0) := "10";

    -- cmderr enum
    constant ERR_NONE    : std_logic_vector(2 downto 0) := "000";
    constant ERR_BUSY    : std_logic_vector(2 downto 0) := "001";
    constant ERR_NOTSUP  : std_logic_vector(2 downto 0) := "010";
    constant ERR_EXCEPT  : std_logic_vector(2 downto 0) := "011";
    constant ERR_HALTRES : std_logic_vector(2 downto 0) := "100";
    constant ERR_OTHER   : std_logic_vector(2 downto 0) := "111";

    -- ~65k mclk at 24 MHz is ~2.7 ms: inside the 100 ms testbench watchdog and far longer than any real abstract sequence.
    constant POLL_LIMIT : integer := 65535;

    /* ------------------------------------------------------------------
       DM register file
       ------------------------------------------------------------------ */
    signal dmactive   : std_logic;
    signal haltreq_r  : std_logic;                       -- dmcontrol[31]
    signal hartsel_r  : std_logic_vector(9 downto 0);    -- hartsello, WARL
    signal rsthalt_r  : std_logic_vector(NHARTS-1 downto 0);
    signal resumeack_r: std_logic_vector(NHARTS-1 downto 0);
    signal havereset_r: std_logic_vector(NHARTS-1 downto 0);
    signal cmderr_r   : std_logic_vector(2 downto 0);
    signal busy_r     : std_logic;
    -- halt groups: 3 bits per hart gives 8 groups, group 0 = "no group" = reset value.
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

    /* ------------------------------------------------------------------
       Master engine
       ------------------------------------------------------------------ */
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

    /* ------------------------------------------------------------------
       Sequencer
       ------------------------------------------------------------------ */
    type s_state_t is (S_IDLE,
                       S_PROXY,        -- a data0/progbuf DMI access in flight
                       S_PROXY_RSP,
                       -- THE PLANT: stream the constant TRAMP table to W_ENTRY+0..39.
                       -- No return-state flop is needed: a plant owed to a TOK_HALTED wait always has busy_r = '1' (command path) or res_busy = '1' (queued-resume path), and the eager dmactive-rise plant always has both '0'.
                       S_TRAMP,
                       S_EPI,          -- write the constant epilogue (once)
                       S_BODY,         -- write the synthesized abstract body
                       S_IMPL,         -- write the implicit progbuf word
                       S_GO,           -- write TOK_GO into FLAGS[h]
                       S_POLL,         -- read FLAGS[h] until DONE / not GO
                       S_FIN,          -- retire the command: clear busy, back to S_IDLE
                       -- THE HANDOFF WAIT: the DM must OBSERVE FLAGS[h] = TOK_HALTED before it writes GO or RESUME.
                       -- dbg_halted rises a dozen shared accesses before the trampoline stores TOK_HALTED, so a DM that writes the token on `halted` has its write overwritten by the hart and the hart then polls forever.
                       S_WAITH,
                       S_RESUME,       -- write TOK_RESUME into FLAGS[h]
                       -- HOLD THE ENGINE UNTIL THE DISPATCHED RESUME IS TAKEN: res_busy must survive the token write and clear on the hart's halted falling edge.
                       -- Clearing it on the write lets S_IDLE re-arm the SAME resume, which fires a spurious second resume and pins mst_free low for the full POLL_LIMIT after every resume.
                       S_RESWAIT);
    signal s_state : s_state_t;
    signal step    : integer range 0 to 63;
    -- Write-once latch for the epilogue; it JOINS the clear taken when dmactive falls to 0, so a dmactive toggle is a complete recovery of everything the DM owns in the page.
    -- Cost: the first abstract command after a toggle takes the S_EPI path again (9 extra master writes, ~45 mclk) instead of going straight to S_IMPL.
    signal epi_done: std_logic;
    -- The two plant-owed bits stay separate because the two triggers are serviced at different moments; one bit cannot represent both without making the on-halt plant eager.
    signal tramp_arm : std_logic;   -- dmactive rose: plant NOW, from S_IDLE
    signal tramp_halt: std_logic;   -- a hart halted: plant before its TOK_HALTED
    signal cmd_r   : std_logic_vector(31 downto 0);   -- the accepted `command` word
    signal cmd_hart: integer range 0 to 1023;         -- the hart it was aimed at, latched at accept

    -- DMI front end
    signal rsp_valid_r : std_logic;
    signal rsp_data_r  : std_logic_vector(31 downto 0);
    signal rsp_op_r    : std_logic_vector(1 downto 0);
    signal ready_r     : std_logic;
    signal mst_free    : std_logic;
    -- ONE ACCEPT PER ASSERTION OF dmi_req_valid, enforced by a TIMER (`rsp_hold = 0 and rsp_arm = '0'` on the accept below), not by observing valid low: ready_r pulses one cycle at the capture, rsp_arm blocks the next, rsp_hold blocks the following RSP_HOLD_CYCLES.
    -- So a master must drop valid within 9 mclk of the acknowledge or it earns a duplicate accept, which is why the DTM's mclk-side master is a one-shot retiring on ready; 7 mclk (~292 ns) also holds the response far longer than any master's sampling interval and far shorter than any inter-transaction gap.
    constant RSP_HOLD_CYCLES : integer := 7;
    signal rsp_hold    : integer range 0 to RSP_HOLD_CYCLES;
    -- The response is ARMED at capture and ASSERTED ONE CYCLE LATER, so rsp_data/rsp_op are settled before rsp_valid rises.
    -- Without the separation a finely sampling master catches rsp_valid while the answer is still being computed and reads the PREVIOUS transaction's data.
    signal rsp_arm     : std_logic;
    signal pend_wr     : std_logic;   -- the accepted access was a write, so the proxy answers zeros
    -- The hart a resume was aimed at, latched so S_RESUME cannot be re-pointed by a hartsel write that lands while the FLAGS store is still in flight.
    signal res_hart    : integer range 0 to 1023;
    -- A queued resume: resumereq is write-1-to-request and must never be silently dropped because the master engine is busy, so it is latched and serviced when the engine frees.
    -- res_busy stops the queue re-triggering the flow while one is already in progress.
    signal res_busy    : std_logic;
    -- what S_WAITH runs on to next: '1' for the command path (S_GO), '0' for the resume path (S_RESUME)
    signal waith_go    : std_logic;
    -- S_POLL bound: a hart that never reports (wedged trampoline, unplanted entry page) must fail the command inside the tb watchdog rather than pin `busy` forever.
    signal poll_to     : integer range 0 to POLL_LIMIT;

    /* ------------------------------------------------------------------
       RV32I instruction synthesis: everything the DM emits is built here, nothing is a magic hex literal at a use site.
       x8 = s0, x9 = s1 are the trampoline's saved scratch pair (dscratch0/1).
       ------------------------------------------------------------------ */
    constant R_S0 : integer := 8;
    constant R_S1 : integer := 9;
    constant CSR_DSCRATCH0 : integer := 16#7B2#;
    constant CSR_DSCRATCH1 : integer := 16#7B3#;
    constant CSR_MHARTID   : integer := 16#F14#;

    -- Unsigned field packers for the instruction encoders below.
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
    -- ebreak, the 32-bit encoding (the entry page is norvc).
    constant I_EBREAK : std_logic_vector(31 downto 0) := x"00100073";

    -- The base the trampoline and the emitted code address everything from: `lui s0/s1, HI20` gives 0x00010000, so every DM word below 0x10800 is reachable with a 12-bit unsigned load/store displacement.
    constant HI20     : integer := conv_integer(DATA0_ADDR(31 downto 12));
    constant OFF_BASE : integer := conv_integer(DATA0_ADDR(31 downto 12)) * 4096;
    constant O_DATA0  : integer := conv_integer(DATA0_ADDR) - OFF_BASE;
    constant O_FLAGS  : integer := conv_integer(FLAGS_ADDR) - OFF_BASE;
    -- The session mirrors, owned by the trampoline everywhere except an abstract WRITE to s0/s1, where the DM authors the new dscratch value and must update the mirror too.
    -- Without that, a debugger's register write is reverted by the next re-entry repair, because MIRROR was captured at dispatch before the body ran.
    constant O_MIRROR0: integer := 16#6F0#;
    constant O_MIRROR1: integer := 16#6F4#;

    /* ------------------------------------------------------------------
       THE EPILOGUE, constant, reached from the abstract body (postexec = 0) or from the implicit third progbuf word (postexec = 1); it arrives with s0/s1 clobbered, so it recomputes &FLAGS[h] from mhartid, stores TOK_DONE, restores the pair from dscratch0/1 and ends in `ebreak` (which re-enters the trampoline; dpc/dcsr survive).
       THE ORDER IS THE WHOLE POINT: TOK_DONE is stored BEFORE the ebreak, so an exception anywhere earlier leaves the token at TOK_GO and the DM reports cmderr = EXCEPTION instead of success.
       ------------------------------------------------------------------ */
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

    -- The implicit third program-buffer word (impebreak = 1), a jump to the epilogue rather than a bare ebreak so a postexec sequence still stores its DONE token.
    -- "Implicit ebreak" is what the debugger sees; the epilogue's own ebreak is what actually terminates.
    constant I_IMPLICIT : std_logic_vector(31 downto 0) :=
        i_jal(0, (W_PB_LEAVE - W_IMPLICIT) * 4);

    /* ------------------------------------------------------------------
       THE TWO PROGRAM-BUFFER STUBS, in the DM-reserved band at 0x10690 because the entry page has only ten free words left in two non-adjacent runs, and everything below 0x10800 stays reachable from a `lui 0x10` base with a 12-bit displacement.
       ------------------------------------------------------------------ */
    -- PB_ENTER restores the debugger's s0/s1 before the program buffer runs; it is reached from the abstract body's TAIL, so a `transfer+postexec` command's freshly written dscratch is what gets restored.
    -- Without it the program buffer runs on whatever scratch the DM's own body happened to leave in s0/s1.
    constant PB_ENTER : word_arr(0 to 2) := (
        0 => i_csrr(R_S0, CSR_DSCRATCH0),
        1 => i_csrr(R_S1, CSR_DSCRATCH1),
        2 => i_jal (0, (W_PROGBUF0 - (W_PBSTUB + 2)) * 4));

    -- PB_LEAVE adopts what the program buffer computed, then publishes PBDONE; it must NOT fall into EPILOGUE, which would restore s0/s1 from dscratch and overwrite the program buffer's results.
    -- THE ORDER IS LOAD-BEARING: it saves into dscratch FIRST and marks SECOND, because computing &FLAGS[h] clobbers the very pair it exists to preserve, and it must restore that pair before its ebreak or the trampoline's tentative re-entry save captures the clobbered values.
    constant PB_LEAVE : word_arr(0 to 10) := (
        0 => i_csrw(CSR_DSCRATCH0, R_S0),     -- adopt s0
        1 => i_csrw(CSR_DSCRATCH1, R_S1),     -- adopt s1  (now free to clobber)
        2 => i_csrr(R_S1, CSR_MHARTID),
        3 => i_slli(R_S1, R_S1, 2),
        4 => i_lui (R_S0, HI20),
        5 => i_add (R_S0, R_S0, R_S1),        -- s0 = &FLAGS[h]
        6 => i_addi(R_S1, 0, TOK_PBDONE),
        7 => i_sw  (R_S1, R_S0, O_FLAGS),
        8 => i_csrr(R_S1, CSR_DSCRATCH1),     -- put the adopted pair BACK in
        9 => i_csrr(R_S0, CSR_DSCRATCH0),     --   the arch regs before ebreak
       10 => I_EBREAK);

    -- A debugger's own 32-bit ebreak in the program buffer would terminate without passing the epilogue, so no DONE token is stored and a completed command reports EXCEPTION.
    -- These are its per-slot replacements: both must land on the SAME absolute word (W_PB_LEAVE), so their offsets differ by the 4 bytes between the two slots.
    constant I_PB0_JAL : std_logic_vector(31 downto 0) :=
        i_jal(0, (W_PB_LEAVE - W_PROGBUF0) * 4);
    constant I_PB1_JAL : std_logic_vector(31 downto 0) :=
        i_jal(0, (W_PB_LEAVE - W_PROGBUF1) * 4);

    /* ------------------------------------------------------------------
       THE TRAMPOLINE: the entry code every halted hart executes, held as a constant instruction table and streamed to W_ENTRY+0..39 by S_TRAMP.
       It is a word-for-word COPY of the artifact built from software/dbg_trampoline/dbg_trampoline.S and `tools/cosim/check_dbg_trampoline.py` gates the two, so never hand-edit either side: change the .S, rebuild, paste the new words here, and prove the checker exits 0.
       POSITION-DEPENDENT: it is linked at 0x00010780, addresses FLAGS, the mirrors and the abstract area with absolute `lui`/displacement pairs, and word 31's `j` is the coupling to W_ABST, so an instance that re-aims DATA0_ADDR/ENTRY_ADDR must rebuild it for the new aim.
       ------------------------------------------------------------------ */
    constant TRAMP : word_arr(0 to TRAMP_WORDS-1) := (
        --  entry: save the scratch pair tentatively
         0 => x"7B241073",   -- csrw   dscratch0, s0
         1 => x"7B349073",   -- csrw   dscratch1, s1
        --  s0 = &FLAGS[mhartid]
         2 => x"F14024F3",   -- csrr   s1, mhartid
         3 => x"00249493",   -- slli   s1, s1, 2
         4 => x"00010437",   -- lui    s0, 0x10
         5 => x"00940433",   -- add    s0, s0, s1
        --  bit 2 of FLAGS[h] set means this is a RE-ENTRY (GO or DONE)
         6 => x"70042483",   -- lw     s1, 1792(s0)      # FLAGS[h]
         7 => x"0044F493",   -- andi   s1, s1, 4
         8 => x"00048E63",   -- beqz   s1, halted
        --  re-entry repair: put the ORIGINAL pair back from the mirrors
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

    -- The abstract command body, re-synthesized combinationally from `command`.
    signal body_w : word_arr(0 to 7);

begin

    /* ==================================================================
       KNOB-OFF FOLD: everything below lives inside gen_dm, and this arm ties every output to its fail-safe value so a knob-OFF instantiation carries no state at all.
       ================================================================== */
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
        -- OUT-OF-RANGE hartsel selects a NONEXISTENT hart and is REPORTED as such, never clamped: a debugger's hart-count discovery probe writes all-ones and expects anynonexistent back, which a clamp makes impossible.
        sel_idx    <= conv_integer(hartsel_r);
        sel_exists <= '1' when sel_idx < NHARTS else '0';
        -- sel_safe exists because VHDL's `and` is NOT short-circuit: indexing hart_unavail with an unqualified sel_idx faults out of range the moment a debugger probes hartsel with all-ones.
        sel_safe   <= sel_idx when sel_idx < NHARTS else 0;
        sel_unavail <= hart_unavail(sel_safe) and sel_exists;
        -- DM-visible state precedence: nonexistent, then unavail, then halted, then running.
        -- unavail is consulted BEFORE halted so a clamped-'0' dbg_halted from a power-gated tile can never read as either "halted" or "running".
        sel_halted  <= sel_exists and not sel_unavail and dbg_halted(sel_safe);
        sel_running <= sel_exists and not sel_unavail and not dbg_halted(sel_safe);

        -- ---- THE RE-ARMED HALT WIRE ---------------------------------
        -- THE SELECTED-HART ARM MUST **OR** THE GROUP TERM, never replace it: replacing makes a pending group halt vanish for as long as the debugger keeps that hart selected with haltreq low, which is a silent selection-dependent drop.
        gen_hw: for h in 0 to NHARTS-1 generate
            want_halt(h) <= ((haltreq_r and dmactive) or grp_pend(h))
                            when (h = sel_idx) else grp_pend(h);
        end generate;
        -- The re-armed halt level: assert until the hart halts, release for the whole halted interval so the core's entry mask clears, and re-assert on resume while the debugger still wants it halted.
        gen_hq: for h in 0 to NHARTS-1 generate
            dbg_haltreq(h) <= want_halt(h) and not dbg_halted(h);
        end generate;
        dbg_resethaltreq <= rsthalt_r;

        -- ---- master engine ------------------------------------------
        m_req   <= m_req_r;
        m_we    <= m_we_r;
        m_addr  <= m_addr_r;
        m_wdata <= m_wd_r;

        -- One shared-bus transaction at a time, sequenced to the wait-for-release contract.
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
                    -- MS_IDLE: wait for the sequencer's start pulse, then launch the request.
                    when MS_IDLE =>
                        if m_start = '1' then
                            -- THE MUTEX-PAGE GUARD: the DM must never issue a transaction outside its own claimed band.
                            -- A read of the mutex page CLAIMS a mutex for whatever s_master reports, and the DM's master index is a non-hart value that mutex_bank, the router CLAIM and the stub ownership gates all read as a hart index.
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
                    -- MS_REQ: HOLD everything stable through the done cycle, and capture rdata ON it.
                    when MS_REQ =>
                        if m_done = '1' then
                            m_rd_r  <= m_rdata;
                            m_state <= MS_CAP;
                        end if;
                    -- MS_CAP: drop req exactly ONE clk after done (the acked flop).
                    when MS_CAP =>
                        m_req_r <= '0';
                        m_state <= MS_GAP;
                    -- MS_GAP: one arbiter-OBSERVED req-low cycle before the next request.
                    -- Without it the arbiter's wait-for-release never clears and the DM is starved.
                    when MS_GAP =>
                        m_ack   <= '1';
                        m_state <= MS_IDLE;
                end case;
            end if;
        end process;

        /* ---- the abstract body, synthesized from `command` ------------
           The trampoline already saves s0/s1 into dscratch0/1, so the body may use both freely and needs no save/restore of its own.
           A request for s0 or s1 themselves is serviced through the dscratch copy, so the debugger sees the interrupted value and not the trampoline's working value. */
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
            -- With postexec set, the body tail jumps to the program buffer, whose implicit third word jumps on to the epilogue; otherwise it goes straight to the epilogue.
            if cmd_r(18) = '1' then
                tail := i_jal(0, (W_PBSTUB - (W_ABST + 4)) * 4);
            else
                tail := i_jal(0, (W_EPILOG   - (W_ABST + 4)) * 4);
            end if;
            if cmd_r(17) = '0' then
                -- transfer = 0: postexec only.
                -- (`when/else` inside a process is VHDL-2008 and this tree compiles -V200X, so use an if.)
                if cmd_r(18) = '1' then
                    body_w(0) <= i_jal(0, (W_PBSTUB - W_ABST) * 4);
                else
                    body_w(0) <= i_jal(0, (W_EPILOG - W_ABST) * 4);
                end if;
            elsif cmd_r(16) = '0' then
                -- transfer, write = 0: read the register into data0.
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
                -- transfer, write = 1: write data0 into the register.
                if isgpr and n = R_S0 then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (R_S0, R_S1, O_DATA0);
                    body_w(2) <= i_csrw(CSR_DSCRATCH0, R_S0);
                    body_w(3) <= i_sw  (R_S0, R_S1, O_MIRROR0);
                elsif isgpr and n = R_S1 then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (R_S0, R_S1, O_DATA0);
                    body_w(2) <= i_csrw(CSR_DSCRATCH1, R_S0);
                    body_w(3) <= i_sw  (R_S0, R_S1, O_MIRROR1);
                elsif isgpr then
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (n, R_S1, O_DATA0);
                    body_w(2) <= i_addi(0, 0, 0);
                    body_w(3) <= i_addi(0, 0, 0);
                else
                    body_w(0) <= i_lui (R_S1, HI20);
                    body_w(1) <= i_lw  (R_S0, R_S1, O_DATA0);
                    body_w(2) <= i_csrw(regno, R_S0);
                    body_w(3) <= i_addi(0, 0, 0);
                end if;
                body_w(4) <= tail;
            end if;
        end process;

        /* ---- the DMI front end + the command sequencer ---------------
           READY IS AN ACKNOWLEDGE AND IT IDLES LOW, raised the cycle a request is CAPTURED: an idle-high ready loses requests from masters that drop valid a few ns after seeing it, and the symptom is the PREVIOUS transaction's data rather than an error.
           ready is NOT held low for the whole abstract command, which runs in the background behind `busy` so a debugger can poll abstractcs.busy; a DMI access needing the single-owner master engine while the sequencer holds it gets cmderr = BUSY instead of an interleaved transaction. */
        mst_free      <= '1' when s_state = S_IDLE else '0';
        dmi_req_ready <= ready_r;
        dmi_rsp_valid <= rsp_valid_r;
        dmi_rsp_data  <= rsp_data_r;
        dmi_rsp_op    <= rsp_op_r;

        -- The DM register file, the DMI accept/response timing and the command sequencer, all in one clocked process.
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
                    -- A hart that HALTS clears its group-broadcast request and, if it was the one we asked to resume, closes the resume.
                    if dbg_halted(i) = '1' and halted_d(i) = '0' then
                        grp_pend(i) <= '0';
                        -- A new halt OWES a plant but does not take one here: the bit is consumed on the way into S_WAITH, so the stream runs inside a busy window the debugger already owns.
                        tramp_halt <= '1';
                        -- HALT GROUPS: when any member of a non-zero group halts, every OTHER member is asked to halt too.
                        -- One re-armed pulse each; grp_pend is cleared by that hart's own halt, above.
                        if grp_r(i) /= "000" then
                            for j in 0 to NHARTS-1 loop
                                -- ...but ONLY to a member that is not ALREADY halted: grp_pend is cleared by its hart's own halted RISING edge, so a request raised at an already-halted hart is never consumed.
                                -- It would sit there and re-halt that hart the moment the debugger resumes it, and the group condition is already satisfied by a halted member, so the request is vacuous.
                                if j /= i and grp_r(j) = grp_r(i)
                                   and dbg_halted(j) = '0' then
                                    grp_pend(j) <= '1';
                                end if;
                            end loop;
                        end if;
                    end if;
                    -- resumeack is a LEVEL, not a pulse: it sets on the halted FALLING edge attributable to a resumereq and stays set until the next resumereq write.
                    if dbg_halted(i) = '0' and halted_d(i) = '1'
                       and resume_pend(i) = '1' then
                        resumeack_r(i) <= '1';
                        resume_pend(i) <= '0';
                        res_busy       <= '0';
                    end if;
                end loop;

                /* ==========================================================
                   the sequencer
                   ========================================================== */
                case s_state is

                    -- S_IDLE: nothing in flight, so take an owed eager plant or a queued resume.
                    when S_IDLE =>
                        -- THE EAGER PLANT, taken first; a queued resume is not dropped, only delayed, because the DM returns to S_IDLE and picks it up on the next visit.
                        -- tramp_arm is cleared by S_TRAMP itself and not here, so a command accepted in the same cycle (which overrides s_state further down this process) DEFERS the plant instead of losing it.
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
                                    -- RESET THE BOUND ON ARM: poll_to is shared by S_WAITH, S_POLL and S_RESWAIT and is otherwise zeroed only on the command path, so a resume would arm S_WAITH at or near POLL_LIMIT and time out before the hart can publish TOK_HALTED.
                                    poll_to  <= 0;
                                    -- THE LAZY PLANT: this arm is one of exactly two entries into the TOK_HALTED wait, and the re-stream must precede both.
                                    if tramp_halt = '1' then
                                        s_state <= S_TRAMP;
                                    else
                                        s_state <= S_WAITH;
                                    end if;
                                end if;
                            end loop;
                        end if;

                    -- ---- data0 / progbuf proxy read or write -----------
                    -- S_PROXY: wait for the backing-word transaction to retire.
                    when S_PROXY =>
                        if m_ack = '1' then
                            s_state <= S_PROXY_RSP;
                        end if;
                    -- S_PROXY_RSP: answer the DMI access, with read data for a read and zeros for a write.
                    when S_PROXY_RSP =>
                        rsp_arm     <= '1';
                        rsp_op_r    <= OP_OK;
                        if pend_wr = '1' then
                            rsp_data_r <= (others => '0');
                        else
                            rsp_data_r <= m_rd_r;
                        end if;
                        s_state <= S_IDLE;

                    -- ---- stream the trampoline into the entry page ----
                    -- Structurally S_EPI with a longer table and a computed exit: same `step`, same m_go_*/m_start handshake, same one-word-per-m_ack cadence.
                    when S_TRAMP =>
                        if m_ack = '1' or step = 0 then
                            if step <= TRAMP_WORDS-1 then
                                if step = 0 then
                                    -- BOTH owed-bits clear as the stream STARTS, not as it finishes, so a hart that halts during the stream keeps its own claim on a later plant.
                                    -- That is the direction that cannot lose one: such a hart may fetch stale words, spin on the exception re-entry, and be repaired by the next plant.
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
                                -- Where to go back: these two are the signature of a plant that was owed to a TOK_HALTED wait.
                                if busy_r = '1' or res_busy = '1' then
                                    s_state <= S_WAITH;
                                else
                                    s_state <= S_IDLE;
                                end if;
                            end if;
                        end if;

                    -- ---- abstract command: write the epilogue once ----
                    -- Streams EPILOGUE(0 to 8) and then the two program-buffer stubs, one word per m_ack.
                    when S_EPI =>
                        if m_ack = '1' or step = 0 then
                            if step <= 8 then
                                m_go_we <= "1111";
                                m_go_a  <= W_EPILOG + step;
                                m_go_d  <= EPILOGUE(step);
                                m_start <= '1';
                                step    <= step + 1;
                            elsif step <= 8 + PBSTUB_WORDS then
                                -- The two program-buffer stubs ride the SAME stream rather than a state of their own; `step` is already `range 0 to 63` and the combined count fits.
                                m_go_we <= "1111";
                                if step <= 11 then
                                    m_go_a <= W_PBSTUB + (step - 9);
                                    m_go_d <= PB_ENTER(step - 9);
                                else
                                    m_go_a <= W_PB_LEAVE + (step - 12);
                                    m_go_d <= PB_LEAVE(step - 12);
                                end if;
                                m_start <= '1';
                                step    <= step + 1;
                            else
                                epi_done <= '1';
                                step     <= 0;
                                s_state  <= S_IMPL;
                            end if;
                        end if;

                    -- S_IMPL: write the implicit third program-buffer word, the jump into PB_LEAVE.
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

                    -- S_BODY: stream the eight synthesized abstract-body words into the entry page.
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
                                -- THE LAZY PLANT, the other entry into the TOK_HALTED wait; it sits here rather than at the command accept so the stream runs inside the busy window this command already owns.
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
                            -- Bounded: fail the command rather than hang.
                            if waith_go = '1' then
                                cmderr_r <= ERR_OTHER;
                                s_state  <= S_FIN;
                            else
                                -- CLEAR THE PEND ON THE RESUME-PATH TIMEOUT TOO, as S_RESWAIT's timeout does: otherwise S_IDLE's arm condition is still true, the wait re-arms forever and mst_free never rises again.
                                -- The drop is bounded and VISIBLE, since resumeack stays 0 and a debugger polling dmstatus sees the resume did not happen.
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

                    -- S_GO: dispatch the body by writing TOK_GO into the target hart's FLAGS word.
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
                        -- Read FLAGS[h] back until the hart reports: TOK_DONE means the sequence ran to its end.
                        -- TOK_HALTED instead, written by the trampoline on re-entry, means the sequence did NOT reach its epilogue, i.e. it took an exception.
                        if poll_to < POLL_LIMIT then
                            poll_to <= poll_to + 1;
                        end if;
                        if m_ack = '1' then
                            if m_rd_r = conv_std_logic_vector(TOK_DONE, 32) then
                                cmderr_r <= ERR_NONE;
                                s_state  <= S_FIN;
                            elsif m_rd_r = conv_std_logic_vector(TOK_PBDONE, 32) then
                                -- A PROGRAM-BUFFER completion, accepted exactly where DONE is and nowhere else, and as transient as DONE.
                                cmderr_r <= ERR_NONE;
                                s_state  <= S_FIN;
                            elsif m_rd_r = conv_std_logic_vector(TOK_HALTED, 32) then
                                cmderr_r <= ERR_EXCEPT;
                                s_state  <= S_FIN;
                            else
                                step <= 0;
                            end if;
                        elsif poll_to >= POLL_LIMIT then
                            -- The hart never reported; bounded, so the command fails instead of hanging.
                            cmderr_r <= ERR_OTHER;
                            s_state  <= S_FIN;
                        elsif step = 0 then
                            m_go_we <= "0000";
                            m_go_a  <= W_FLAGS0 + cmd_hart;
                            m_go_d  <= (others => '0');
                            m_start <= '1';
                            step    <= 1;
                        end if;

                    -- S_FIN: the command is over, whatever cmderr says. Drop busy and idle.
                    when S_FIN =>
                        busy_r  <= '0';
                        step    <= 0;
                        s_state <= S_IDLE;

                    -- S_RESUME: write TOK_RESUME into the target hart's FLAGS word.
                    when S_RESUME =>
                        if m_ack = '1' then
                            -- res_busy STAYS SET until the resume is taken; see S_RESWAIT.
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
                        -- The resume has been DISPATCHED; hold the engine until resume_pend(res_hart) falls, which the bookkeeping above does on the attributable halted FALLING edge.
                        -- An edge detector, so a resume immediately followed by a re-halt cannot be missed the way a level test of dbg_halted could; bounded, so a hart that never leaves debug mode fails the request instead of wedging the DM.
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

                /* ==========================================================
                   DMI request acceptance: ONE REQUEST IN FLIGHT, ACK-STYLE HANDSHAKE, ready_r idling low and pulsing for exactly one cycle on the cycle the request is CAPTURED, with rsp_hold/rsp_arm as the re-capture lockout.
                   S_TRAMP JOINS S_PROXY/S_PROXY_RSP IN THE EXCLUSION: the plant is a bounded atomic multi-word operation owning the master engine, so the DM simply does not raise `ready` while it runs and the master waits.
                   Without that exclusion the attach-time plant answers the debugger's first abstract command with cmderr = BUSY, and because cmderr is STICKY and `command` writes are ignored while it is set, one such answer disables abstract commands for the whole session.
                   ========================================================== */
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

                    -- Default: answer NEXT cycle, then hold for RSP_HOLD_CYCLES.
                    rsp_arm     <= '1';
                    rsp_op_r    <= OP_OK;

                    -- dmcontrol (0x10): dmactive, haltreq, hartsel, resumereq, ackhavereset, set/clrresethaltreq.
                    if a = A_DMCONTROL then
                        if wr then
                            dmactive  <= d(0);
                            if d(0) = '0' then
                                -- dmactive low resets the DM's own state but NOT the harts (ndmreset is read-zero WARL).
                                haltreq_r   <= '0';
                                rsthalt_r   <= (others => '0');
                                grp_pend    <= (others => '0');
                                resume_pend <= (others => '0');
                                busy_r      <= '0';
                                cmderr_r    <= ERR_NONE;
                                -- The plant-owed bits and the epilogue's write-once latch all clear here, so a dmactive toggle really does re-plant everything the DM owns in the page.
                                tramp_arm   <= '0';
                                tramp_halt  <= '0';
                                epi_done    <= '0';
                            else
                                -- THE RISE, and only the rise: every dmstatus poll writes dmcontrol with dmactive set, so a plant armed on the LEVEL would re-arm forever and pin the master engine.
                                if dmactive = '0' then
                                    tramp_arm <= '1';
                                end if;
                                haltreq_r <= d(31);
                                hartsel_r <= d(25 downto 16);
                                hs := conv_integer(d(25 downto 16));
                                -- resumereq is write-1-to-request and only means anything for a HALTED, existing, available hart.
                                -- NESTED ifs, not one `and` chain: VHDL does not short-circuit, so `hs < NHARTS and dbg_halted(hs)` indexes out of range on the all-ones hartsel probe.
                                if hs < NHARTS then
                                    if d(30) = '1' and dbg_halted(hs) = '1'
                                       and hart_unavail(hs) = '0' then
                                        -- QUEUE it, never refuse and never drop it; the sequencer picks it up from S_IDLE.
                                        resume_pend(hs) <= '1';
                                        resumeack_r(hs) <= '0';
                                    end if;
                                    -- ackhavereset clears the selected hart's havereset bit.
                                    if d(28) = '1' then
                                        havereset_r(hs) <= '0';
                                    end if;
                                end if;
                                -- setresethaltreq / clrresethaltreq; the wire exists, so dmstatus reports hasresethaltreq = 1.
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

                    -- dmstatus (0x11): read-only status of the selected hart plus the DM's own capability bits.
                    elsif a = A_DMSTATUS then
                        -- version = 3 (debug spec 1.0).
                        rsp(3 downto 0) := "0011";
                        rsp(7)  := '1';                 -- authenticated
                        rsp(5)  := '1';                 -- hasresethaltreq
                        rsp(22) := '1';                 -- impebreak
                        -- With hasel dropped, both bits of every any/all pair mirror the selected hart, and BOTH must be driven or OpenOCD misreads them.
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
                        /* ==================================================
                           hartinfo (0x12): THE NULL CLAIM, all four fields zero (nscratch, dataaccess, datasize, dataaddr), which says "no scratch registers and no shadowed data region, use the program buffer" and is the only path this design has.
                           dataaddr MUST NOT advertise DATA0_ADDR: the field is 12 bits and sign-extended, so 0x10680 would be published as 0x680, a resolvable wrong address inside the read-only boot ROM.
                           Clearing dataaccess is what makes that unreachable, since a debugger consumes dataaddr only when dataaccess is 1; the DM's own master engine still targets DATA0_ADDR, it simply does not advertise it.
                           ================================================== */
                        rsp_data_r <= (others => '0');

                    -- haltsum0 (0x40): one bit per hart, set when that hart is halted and reachable.
                    elsif a = A_HALTSUM0 then
                        -- One 32-bit register covers every supported hart count.
                        for i in 0 to NHARTS-1 loop
                            rsp(i) := dbg_halted(i) and not hart_unavail(i);
                        end loop;
                        rsp_data_r <= rsp;

                    elsif a = A_HALTSUM1 then
                        -- haltsum1 (0x13) reads zero with SUCCESS: a debugger probes it and must not see a failed transaction.
                        rsp_data_r <= (others => '0');

                    elsif a = A_SBCS then
                        /* ==================================================
                           sbcs (0x38): READ-ZERO-SUCCESS, WRITES IGNORED-SUCCESS, and both halves are load-bearing.
                           A debugger reads this address once per hart during examination and a FAILED read aborts examination outright, while it writes sbcs to clear sberror and a failed write is one more gratuitous sticky transport event.
                           Zeros are the honest answer, not a placation: sbversion 0, sbasize 0 and every sbaccess width bit clear is the debug spec's own encoding for "no system bus access"; 0x39-0x3F remain unimplemented and answer `failed`.
                           ================================================== */
                        rsp_data_r <= (others => '0');

                    -- abstractcs (0x16): progbufsize, datacount, busy and the sticky cmderr.
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

                    -- abstractauto (0x18) is not implemented and reads zero.
                    elsif a = A_ABSTAUTO then
                        rsp_data_r <= (others => '0');      -- read-zero

                    -- dmcs2 (0x32): the halt-group assignment of the selected hart.
                    elsif a = A_DMCS2 then
                        if wr then
                            -- hgselect = 0 (harts) only; hgwrite commits the group of the SELECTED hart. grouptype 0.
                            if d(0) = '0' and d(1) = '1' and sel_idx < NHARTS then
                                grp_r(sel_idx) <= d(4 downto 2);
                            end if;
                        else
                            if sel_idx < NHARTS then
                                rsp(6 downto 2) := "00" & grp_r(sel_idx);
                            end if;
                            rsp_data_r <= rsp;
                        end if;

                    -- command (0x17): accept and launch one abstract command.
                    elsif a = A_COMMAND then
                        if wr then
                            -- NO ABSTRACT COMMAND STARTS WHILE cmderr IS SET, and this guard goes FIRST: a write arriving busy with a standing error must not overwrite the diagnosis with BUSY, and is a no-op anyway.
                            -- Ignored means IGNORED: no start, no cmderr change, no new error; the debugger clears the standing one with the abstractcs W1C and writes `command` again.
                            if cmderr_r /= ERR_NONE then
                                null;
                            elsif busy_r = '1' then
                                cmderr_r <= ERR_BUSY;
                            elsif d(31 downto 24) /= x"00" then
                                -- cmdtype 2 (access memory) answers NOT_SUPPORTED, so the debugger falls back to progbuf lw/sw through the hart, which is this design's memory path.
                                cmderr_r <= ERR_NOTSUP;
                            elsif d(22 downto 20) /= "010" then
                                cmderr_r <= ERR_NOTSUP;     -- aarsize /= 32 bit
                            elsif sel_halted = '0' then
                                cmderr_r <= ERR_HALTRES;
                            elsif mst_free = '0' then
                                cmderr_r <= ERR_BUSY;
                            else
                                -- The command WRITE completes NOW (ready stays high); the command itself runs in the background behind `busy`, which is what the debugger polls.
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

                    -- data0 (0x04) and progbuf0/1 (0x20/0x21): PROXIED to the backing word through a master access.
                    elsif a = A_DATA0 or a = A_PROGBUF0 or a = A_PROGBUF1 then
                        -- Multi-cycle: ready is a REGISTERED one-cycle pulse that has already fired for this request, the accept guard above excludes S_PROXY and S_PROXY_RSP so no further request is taken, and the response is issued by S_PROXY_RSP.
                        if mst_free = '0' then
                            -- Touching data0/progbuf while the master engine is busy is an error the debug spec names: report cmderr = BUSY, answer the DMI access now, and never interleave a second master transaction.
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
                                -- A debugger's own 32-bit ebreak becomes the position-correct jump to the epilogue: progbuf0/1 PROXY WRITES only, EXACT 32-bit encoding only, and the substituted word is what a readback returns, since no shadow of the original is kept.
                                -- This does not touch the exception detector: a program that genuinely traps still never reaches the epilogue and still reports EXCEPTION.
                                if a = A_PROGBUF0 and d = I_EBREAK then
                                    m_go_d <= I_PB0_JAL;
                                elsif a = A_PROGBUF1 and d = I_EBREAK then
                                    m_go_d <= I_PB1_JAL;
                                else
                                    m_go_d <= d;
                                end if;
                            else
                                m_go_we <= "0000";
                                m_go_d  <= (others => '0');
                            end if;
                            m_start <= '1';
                            s_state <= S_PROXY;
                        end if;

                    else
                        -- Unimplemented DMI address: answer `failed`.
                        rsp_op_r   <= OP_FAIL;
                        rsp_data_r <= (others => '0');
                    end if;
                end if;
            end if;
        end process;

    end generate;

end architecture;
