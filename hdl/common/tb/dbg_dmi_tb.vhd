-- =============================================================================
-- dbg_dmi_tb.vhd  (D2 acceptance instrument J1, BLIND-AUTHORED, 2026-08-05)
-- =============================================================================
-- THE DM REGISTER-MAP CONFORMANCE BENCH for the D2 frozen interface: it drives the d2_spec.md section 2 DMI port of a DEBUG-ON MCU and grades the section 3 register subset.
-- It is the D2 sibling of D1's dbg_iface_tb.vhd (I2) and inherits that file's contract exactly: it is the ONE instrument in the D2 set that NAMES the new interface in VHDL, so its FAIL leg at unimplemented HEAD is an ELABORATION ERROR rather than a verdict word, which is the two-part seen-to-FAIL protocol of d2_spec.md section 8.
--
-- BLINDNESS NOTE: written before any D2 RTL exists, against the frozen spec text only.
-- If it fails to elaborate, READ THE ERROR: that is the instrument working, not the instrument broken.
-- Do not "fix" it by deleting the names it asserts must exist.
--
-- ---------------------------------------------------------------------------
-- WHY AN MCU-LEVEL BENCH AND NOT A debug_module UNIT BENCH
--   d2_spec freezes the MCU-entity DMI port names (section 2, verbatim) and does NOT freeze debug_module's own port names.
--   An acceptance instrument may only depend on what the spec froze, so the DUT here is the MCU and the DM is reached exclusively through DMI.
--   That also means this bench tests the thing a D3 DTM will drive, unchanged, which is the stated point of designing the port once.
--
-- ---------------------------------------------------------------------------
-- WHAT IT ASSERTS, and why each assertion is not free
--   The conformance list of d2_spec section 8 first bullet, plus the pieces of section 3 that a debugger's very first transactions depend on.
--
--   C1-C4  dmstatus IDENTITY: version = 3 (1.0), authenticated = 1, hasresethaltreq = 1, impebreak = 1.
--          NONE of these can be taken from Spike: Spike reports version 2, implements no set/clrresethaltreq at all and reads hasresethaltreq 0 (d2_probe P6 deviations 1-2).
--          They are spec-text requirements and this is the only instrument that reads them.
--   C5     hartinfo dataaddr = 0x10680.
--          The DM's advertised data window must be the word d2_spec section 1 claims, or a debugger that believes hartinfo writes somewhere else in the shared band.
--   C6     abstractcs SHAPE: progbufsize = 2, datacount = 1, and both busy and cmderr clean before anything has been asked of it.
--   C7     hartsel WARL WIDTH: write all ten hartsello bits AND all ten hartselhi bits; only ceil(log2(NHARTS)) hartsello bits may stick and hartselhi must read zero.
--          A DM that implements all 20 bits passes every other check here and fails this one.
--   C8     NONEXISTENT, NOT CLAMP.
--          This is the check the "copy Spike" instinct fails: Spike CLAMPS a written hartsel to nprocs()-1 (debug_module.cc:1046), which makes an out-of-range selection look like the top hart.
--          d2_spec section 3 forbids the clamp because a debugger's hart-count discovery probe depends on nonexistent being reachable.
--          So with hartsel out of range, all/anynonexistent must BOTH be 1 and halted/running must both be 0; with hartsel = N-1 nonexistent must be 0.
--          The pair is the discrimination: a DM that hardwires nonexistent = 1 fails the second half.
--   C9     haltsum0 at DMI 0x40 reads SUCCESS and reads 0 while nothing is halted.
--          C19 below is what makes this an instrument rather than a tautology: haltsum0 is read again with a hart actually halted.
--   C10    haltsum1 at DMI 0x13 reads ZERO with op = SUCCESS.
--          d2_spec section 2 carves this out by name from the "unimplemented address returns failed" rule, precisely because a debugger probes it.
--   C11    An unimplemented DMI address DOES return failed.
--          C10 and C11 together are the pair; either alone is satisfiable by an accident.
--   C12    data0 proxy ROUND TRIP over DMI.
--          What this bench canNOT see is whether the proxy really touched shared 0x10680, since a VHDL bench has no window into the RAM model.
--          That half is dbgabsmp/dbg_abs.tcl's, which reads 0x10680 through the RAM model AND has the victim read it in band. Stated, not papered over.
--   C13    cmderr is W1C, IN BOTH DIRECTIONS.
--          Provoke a real error (a legal access-register command aimed at a hart that is RUNNING must set cmderr = HALT_RESUME = 4, d2_spec section 4), then write the cmderr field as ZERO and require it to be UNCHANGED, then write it as ones and require it to clear.
--          A read/write-normal cmderr passes the third step and fails the second, and a hardwired cmderr fails the first.
--   C14    abstractauto (0x18) reads zero (d2_spec section 3).
--   C15    dmcs2 group WARL: 8 groups, so writing the 5-bit group field all ones must read back 7, and group 0 must be the reset value.
--   C16-C21 THE LIVENESS HALF, and it is the half that makes C1-C15 mean something.
--          An expected-zero needs independent proof the instrument was live (method rule 5): every "reads 0" above is satisfied by a DM whose registers are all hardwired zero.
--          So a hart is actually HALTED through DMI here:
--            C16 hart 1 reads allrunning BEFORE (both pair bits driven)
--            C17 haltreq raises allhalted AND anyhalted within budget
--            C18 haltsum0 now has EXACTLY bit 1 set: nonzero, and in the right place
--            C19 selecting hart 2 shows it still running, so halting one hart did not halt the chip
--            C20 an access-memory command (cmdtype 2) on the HALTED hart returns NOT_SUPPORTED, DD5's memory answer, checked where HALT_RESUME cannot mask it
--            C21 aarsize = 3 on the HALTED hart returns NOT_SUPPORTED
--
-- WHAT IT DELIBERATELY DOES NOT ASSERT
--   RESUME, abstract register transfers, progbuf execution, postexec, the EXCEPTION cmderr, halt groups, dcsr.prv, and unavail.
--   Every one of those needs the D4-ROM-stand-in TRAMPOLINE planted at DEBUG_ENTRY_ADDR (d2_spec section 1), which is a testbench DEPOSIT and therefore a tcl act that a VHDL bench cannot do.
--   They are covered by the in-band instruments dbgdmimp / dbgabsmp / dbggrpmp / dbgprvmp / dbgdarkmp and their tcl harnesses.
--   Splitting it this way keeps this file short enough to review line by line, which is the only reason to trust a bench that grades itself.
--   It also asserts nothing about what the halted hart EXECUTES: with no trampoline planted, a halted hart fetches whatever the shared RAM holds at DEBUG_ENTRY_ADDR.
--   That is fine here, because dbg_halted is a STATE (D1's vesta.vhd assigns dbg_halted from debug_mode) so dmstatus and haltsum0 read correctly regardless, and it is why this bench never resumes anything.
--
-- ---------------------------------------------------------------------------
-- THE HANDSHAKE THIS BENCH ASSUMES, and the ONE spec ambiguity behind it
--   d2_spec section 2 gives req_valid/req_ready plus rsp_valid/rsp_op/rsp_data and says "one request in flight; rsp_valid one-shot per request".
--   It does NOT say whether req_ready may be asserted before req_valid.
--   This bench uses the form that is legal under BOTH readings: it raises req_valid and holds it until req_ready is sampled high, then drops it.
--   A DM that holds req_ready high unconditionally would accept only once anyway, because the "one request in flight" clause forbids accepting another while a response is outstanding.
--   If the implementer reads the handshake differently, this is the paragraph to argue with.
--
-- RUN IT:  xcelium/mp_test/run_dbg_dmi.sh
-- PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;
use work.MemoryMap.all;

entity dbg_dmi_tb is
    generic (
        -- Any real image: this bench never asserts anything about what hart 0 executes.
        -- It needs a booting chip, not a particular test.
        TEST_FILE : string(1 to 29) := "../rcf/xxxrv32ui-p-simple.rcf";
        -- NHARTS drives the WARL-width and NONEXISTENT arithmetic, so the same file grades Castalia (4) and Argus (18).
        -- The N=18 leg of d2_spec section 8 sets the generic NHARTS_G to 18 and changes nothing else.
        NHARTS_G  : integer := 4
    );
end entity;

architecture sim of dbg_dmi_tb is

    constant clk_hfxt_delay  : time := (0.5 sec) / 24000000;   -- 24 MHz mclk
    constant clk_lfxt_delay  : time := (0.5 sec) / 32768;      -- 32.768 kHz LFXT
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;

    -- DM register DMI word addresses (debug_defines.h, d2_spec section 3).
    constant A_DATA0      : integer := 16#04#;
    constant A_DMCONTROL  : integer := 16#10#;
    constant A_DMSTATUS   : integer := 16#11#;
    constant A_HARTINFO   : integer := 16#12#;
    constant A_HALTSUM1   : integer := 16#13#;
    constant A_ABSTRACTCS : integer := 16#16#;
    constant A_COMMAND    : integer := 16#17#;
    constant A_ABSTRACTAUTO : integer := 16#18#;
    constant A_DMCS2      : integer := 16#32#;
    constant A_HALTSUM0   : integer := 16#40#;
    -- Deliberately unallocated in d2_spec section 3's subset, so C11 can prove a failed response.
    constant A_UNIMPL     : integer := 16#1A#;

    -- DMI request opcodes and response codes.
    constant OP_READ  : std_logic_vector(1 downto 0) := "01";
    constant OP_WRITE : std_logic_vector(1 downto 0) := "10";
    constant RSP_SUCCESS : std_logic_vector(1 downto 0) := "00";
    constant RSP_FAILED  : std_logic_vector(1 downto 0) := "10";

    -- abstractcs.cmderr encodings this bench expects.
    constant CMDERR_NOTSUP     : integer := 2;
    constant CMDERR_HALTRESUME : integer := 4;

    -- Budgets, generous because DMI latency is unspecified at D2 and a tight budget would be a calibration, not a check (method rule 7): what is under test is "eventually" versus "never".
    -- But NOT unboundedly generous, and the reason is measured: a poll whose every iteration is itself a timing-out DMI transaction multiplies the two budgets together, and the first draft of this file took a 400-cycle answer and turned it into 100 ms of wall clock against an absent DM.
    -- So transactions are bounded in mclk cycles, POLLS are bounded in ITERATIONS, and a DMI port that never handshakes is latched DEAD after the first attempt so the rest of the run reports instead of grinding.
    constant W_XACT  : integer := 400;     -- mclk cycles per DMI phase (~17 us)
    constant N_HALT  : integer := 400;     -- dmstatus polls after haltreq
    constant N_BUSY  : integer := 200;     -- abstractcs polls while busy

    signal mclk    : std_logic;
    signal clk_lfxt: std_logic;
    signal resetn  : std_logic := '0';
    signal done    : boolean := false;   -- set when the stimulus process finishes
    signal fails   : integer := 0;       -- failed checks
    signal checks  : integer := 0;       -- checks attempted
    -- Latched the first time a DMI transaction gets no req_ready.
    -- Everything after that returns immediately: against an absent or wedged DM the run must REPORT, not grind (see the budget note above).
    signal dmi_dead : boolean := false;

    -- The frozen DMI port (d2_spec section 2).
    signal dmi_req_valid : std_logic := '0';
    signal dmi_req_op    : std_logic_vector(1 downto 0) := "00";
    signal dmi_req_addr  : std_logic_vector(6 downto 0) := (others => '0');
    signal dmi_req_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal dmi_req_ready : std_logic;
    signal dmi_rsp_valid : std_logic;
    signal dmi_rsp_data  : std_logic_vector(31 downto 0);
    signal dmi_rsp_op    : std_logic_vector(1 downto 0);

    -- Pads and chip plumbing: the riscv_tb shape, reduced to what boots.
    signal resetn_pad : std_logic;
    signal resetn_in, resetn_out, resetn_dir, resetn_ren : std_logic;
    signal prt1 : std_logic_vector(7 downto 0);
    signal prt1_in, prt1_out, prt1_dir, prt1_ren : std_logic_vector(7 downto 0);
    signal prt2_in, prt2_out, prt2_dir, prt2_ren : std_logic_vector(7 downto 0);
    signal prt3_in, prt3_out, prt3_dir, prt3_ren : std_logic_vector(7 downto 0);
    signal prt4_in, prt4_out, prt4_dir, prt4_ren : std_logic_vector(7 downto 0);
    signal prt5_in, prt5_out, prt5_dir, prt5_ren : std_logic_vector(7 downto 0);
    signal prt6_in, prt6_out, prt6_dir, prt6_ren : std_logic_vector(7 downto 0);
    signal a0, a0_1, a0_2, a0_3 : std_logic_vector(31 downto 0);

    signal spi_miso, flash_awake : std_logic;
    -- C0a's subject: latched the first time the bootrom actually drives the SPI flash.
    -- It is the one check in this file that says something about the CHIP rather than about the DM, and it is what tells a reader of a failing log whether the plumbing or the DM is at fault.
    signal boot_seen : boolean := false;
    signal boot_done_flag : std_logic := '0';
    signal cs_flash : std_logic;
    signal ram_file_name : string(1 to 29) := TEST_FILE;

    component serial_flash is
        generic (
            ProgramAddress       : natural;
            RamSizeBytes         : natural;
            SwapBytesIn32BitWord : boolean
        );
        port (
            CSb     : in  std_logic;
            SPCLK   : in  std_logic;
            MOSI    : in  std_logic;
            MISO    : out std_logic;
            mem_reset : in std_logic;
            awake   : out std_logic;
            RAM_FILE_PATH : in string
        );
    end component;

begin

    -- ---------------------------------------------------------------------
    -- Clocks, pads and flash, copied in SHAPE from riscv_tb.vhd and reduced to the boot path.
    -- GPIO1-5 inputs idle low (riscv_tb does the same for prt5/prt6); nothing in this bench uses them.
    -- ---------------------------------------------------------------------
    -- 24 MHz crystal oscillator stimulus.
    ProcClkHFXT: process
    begin
        if done then wait; end if;
        mclk <= '0'; wait for clk_hfxt_period / 2;
        mclk <= '1'; wait for clk_hfxt_period / 2;
    end process;

    -- 32.768 kHz crystal oscillator stimulus; the bootrom switches SMCLK onto it mid-boot.
    ProcClkLFXT: process
    begin
        if done then wait; end if;
        clk_lfxt <= '0'; wait for clk_lfxt_period / 2;
        clk_lfxt <= '1'; wait for clk_lfxt_period / 2;
    end process;

    resetn_pad <= resetn;
    reset_pad: entity work.PDUW16SDGZ_G
        port map (I => resetn_out, OEN => resetn_dir, REN => resetn_ren,
                  PAD => resetn_pad, C => resetn_in);

    pad_prt1_gen: for i in 7 downto 0 generate
        pad_p1: entity work.PDUW16SDGZ_G
            port map (I => prt1_out(i), OEN => prt1_dir(i), REN => prt1_ren(i),
                      PAD => prt1(i), C => prt1_in(i));
    end generate;

    prt1(pnum_gpio0_hfxt) <= mclk;
    prt1(pnum_gpio0_lfxt) <= clk_lfxt;
    prt1(pnum_gpio0_miso) <= spi_miso when flash_awake = '1' else 'Z';
    prt1(7)               <= '1' when boot_done_flag = '0' else 'Z';   -- boot from flash

    prt2_in <= (others => '0');
    prt3_in <= (others => '0');
    prt4_in <= (others => '0');
    prt5_in <= (others => '0');
    prt6_in <= (others => '0');

    -- Latch boot-complete when the flash model goes back to sleep, which releases the boot-source strap and the flash chip select.
    process(resetn, flash_awake)
    begin
        if resetn = '0' then
            boot_done_flag <= '0';
        elsif falling_edge(flash_awake) then
            boot_done_flag <= '1';
        end if;
    end process;

    cs_flash <= prt1(pnum_gpio0_cs_flash) when boot_done_flag = '0' else '1';

    -- C0a evidence: remember that the flash was ever addressed, i.e. that the chip really booted.
    boot_watch: process(mclk)
    begin
        if rising_edge(mclk) then
            if flash_awake = '1' then boot_seen <= true; end if;
        end if;
    end process;

    -- A BENCH THAT CAN HANG PROMISES EVIDENCE THAT CANNOT OCCUR (the D1 dbg_halt.tcl lesson, method rule 9), and the 1-minute rule makes a hung sim a wasted licence seat.
    -- Every loop above is bounded; this is the belt for anything the design does that those bounds cannot see.
    watchdog: process
    begin
        wait for 60 ms;
        if not done then
            report "dbg_dmi_tb: WATCHDOG -- the bench did not finish. "
                 & "CHECK FAILED: watchdog" severity note;
            report "dbg_dmi_tb: WATCHDOG" severity failure;
        end if;
        wait;
    end process;

    spi_slave_flash: serial_flash
        generic map (ProgramAddress => 16#0000#, RamSizeBytes => 16#8100#,
                     SwapBytesIn32BitWord => false)
        port map (CSb => cs_flash,
                  SPCLK => prt1(pnum_gpio0_spi_clk),
                  MOSI  => prt1(pnum_gpio0_mosi),
                  MISO  => spi_miso,
                  mem_reset => not resetn,
                  awake => flash_awake,
                  RAM_FILE_PATH => ram_file_name);

    -- ---------------------------------------------------------------------
    -- THE DUT, instantiated as entity work.MCU rather than through the riscv_tb COMPONENT, precisely so the DMI formals can be NAMED.
    -- That is what makes this file's FAIL leg an elaboration error.
    -- ---------------------------------------------------------------------
    dut: entity work.MCU
        port map (
            resetn_in => resetn_in, resetn_out => resetn_out,
            resetn_dir => resetn_dir, resetn_ren => resetn_ren,
            prt1_in => prt1_in, prt1_out => prt1_out, prt1_dir => prt1_dir, prt1_ren => prt1_ren,
            prt2_in => prt2_in, prt2_out => prt2_out, prt2_dir => prt2_dir, prt2_ren => prt2_ren,
            prt3_in => prt3_in, prt3_out => prt3_out, prt3_dir => prt3_dir, prt3_ren => prt3_ren,
            prt4_in => prt4_in, prt4_out => prt4_out, prt4_dir => prt4_dir, prt4_ren => prt4_ren,
            prt5_in => prt5_in, prt5_out => prt5_out, prt5_dir => prt5_dir, prt5_ren => prt5_ren,
            prt6_in => prt6_in, prt6_out => prt6_out, prt6_dir => prt6_dir, prt6_ren => prt6_ren,
            dmi_req_valid => dmi_req_valid,
            dmi_req_op    => dmi_req_op,
            dmi_req_addr  => dmi_req_addr,
            dmi_req_data  => dmi_req_data,
            dmi_req_ready => dmi_req_ready,
            dmi_rsp_valid => dmi_rsp_valid,
            dmi_rsp_data  => dmi_rsp_data,
            dmi_rsp_op    => dmi_rsp_op,
            a0 => a0, a0_1 => a0_1, a0_2 => a0_2, a0_3 => a0_3
        );

    -- ---------------------------------------------------------------------
    -- The stimulus and grading process: boot the chip, then walk C0a through C22.
    -- ---------------------------------------------------------------------
    stim: process

        -- Grade one check, counting it either way.
        procedure chk(cond : boolean; msg : string) is
        begin
            checks <= checks + 1;
            if cond then
                report "CHECK ok: " & msg severity note;
            else
                -- Severity WARNING, not error: Xcelium stops the run at the first error, and a bench that stops at the first failure can never tell you whether the rest would also have failed.
                report "CHECK FAILED: " & msg severity warning;
                fails <= fails + 1;
            end if;
            wait for 0 ns;
        end procedure;

        -- ONE DMI transaction; see the handshake note in the header.
        procedure dmi_x(op    : in  std_logic_vector(1 downto 0);
                        addr  : in  integer;
                        wdata : in  std_logic_vector(31 downto 0);
                        rop   : out std_logic_vector(1 downto 0);
                        rdata : out std_logic_vector(31 downto 0);
                        ok    : out boolean) is
            variable accepted : boolean := false;
            variable got      : boolean := false;
        begin
            -- Once the port is latched dead every further transaction fails immediately.
            if dmi_dead then
                rop   := "11";
                rdata := (others => '0');
                ok    := false;
                return;
            end if;
            wait until falling_edge(mclk);
            dmi_req_addr  <= conv_std_logic_vector(addr, 7);
            dmi_req_data  <= wdata;
            dmi_req_op    <= op;
            dmi_req_valid <= '1';
            -- Request phase: hold req_valid until the DM samples it with req_ready.
            for i in 0 to W_XACT loop
                wait until falling_edge(mclk);
                if dmi_req_ready = '1' then accepted := true; exit; end if;
            end loop;
            dmi_req_valid <= '0';
            dmi_req_op    <= "00";
            rop   := "11";
            rdata := (others => '0');
            if not accepted then
                report "DMI: no req_ready inside budget -- port latched DEAD"
                    severity warning;
                dmi_dead <= true;
                ok := false;
                return;
            end if;
            -- Response phase: rsp_valid is one-shot per request.
            for i in 0 to W_XACT loop
                wait until falling_edge(mclk);
                if dmi_rsp_valid = '1' then
                    rop   := dmi_rsp_op;
                    rdata := dmi_rsp_data;
                    got   := true;
                    exit;
                end if;
            end loop;
            if not got then
                report "DMI: no rsp_valid inside budget" severity warning;
            end if;
            ok := got;
        end procedure;

        -- Read one DMI register, returning data and the response op.
        procedure dmi_rd(addr : in integer; d : out std_logic_vector(31 downto 0);
                         rop : out std_logic_vector(1 downto 0)) is
            variable o : boolean;
            variable rr : std_logic_vector(1 downto 0);
            variable dd : std_logic_vector(31 downto 0);
        begin
            dmi_x(OP_READ, addr, (others => '0'), rr, dd, o);
            d := dd; rop := rr;
        end procedure;

        -- Write one DMI register; the response is not graded here.
        procedure dmi_wr(addr : in integer; d : in std_logic_vector(31 downto 0)) is
            variable o : boolean;
            variable rr : std_logic_vector(1 downto 0);
            variable dd : std_logic_vector(31 downto 0);
        begin
            dmi_x(OP_WRITE, addr, d, rr, dd, o);
        end procedure;

        -- Field extract from a DMI word.
        -- The temporary is THIRTY-ONE bits, not 32, and that is not a style choice: STD_LOGIC_UNSIGNED's conv_integer routes to STD_LOGIC_ARITH's UNSIGNED version, which raises "CONV_INTEGER argument too large" for ANY 32-bit argument regardless of its value.
        -- Measured here on the first control run, where it turned every field comparison into a warning flood.
        function fld(v : std_logic_vector(31 downto 0); hi, lo : integer) return integer is
            variable t : std_logic_vector(30 downto 0) := (others => '0');
        begin
            t(hi-lo downto 0) := v(hi downto lo);
            return conv_integer(t);
        end function;

        -- Build a dmcontrol write word: hartsello is dmcontrol[25:16], and dmactive (bit 0) is ALWAYS kept set.
        -- Clearing dmactive resets the DM, which must be a deliberate act and never a side effect of selecting a hart.
        function dmcontrol_w(hartsel : integer; extra : std_logic_vector(31 downto 0))
                return std_logic_vector is
            variable v : std_logic_vector(31 downto 0) := (others => '0');
            variable h : std_logic_vector(31 downto 0);
        begin
            h := conv_std_logic_vector(hartsel, 32);
            v(25 downto 16) := h(9 downto 0);
            return (v or extra or x"00000001");
        end function;

        -- ceil(log2(N)): the implemented hartsel width.
        function hartsel_w(n : integer) return integer is
            variable w : integer := 0;
            variable p : integer := 1;
        begin
            while p < n loop p := p * 2; w := w + 1; end loop;
            if w = 0 then w := 1; end if;
            return w;
        end function;

        variable d, d2 : std_logic_vector(31 downto 0);   -- DMI read data
        variable rop   : std_logic_vector(1 downto 0);    -- DMI response op
        variable halted_seen : boolean;                   -- C17: hart 1 reached the halted state
        variable w     : integer;                         -- implemented hartsel width
        variable expect_hs : integer;                     -- expected hartsello read-back

    begin
        report "dbg_dmi_tb: D2 DM register-map conformance bench starting" severity note;
        w := hartsel_w(NHARTS_G);

        -- Reset in the riscv_tb shape; the flash model needs the second pulse.
        resetn <= '0';
        wait for 40 * clk_hfxt_period;
        resetn <= '1';
        wait for 200 * clk_hfxt_period;
        resetn <= '0';
        wait for 4 * clk_hfxt_period;
        resetn <= '1';

        -- Wait for the chip to be OBSERVABLY alive rather than for a fixed time.
        -- Measured on the control run: 400 us was not enough, because the bootrom switches SMCLK to LFXT mid-boot, so the flash handshake lands well after that.
        -- Waiting on the EVENT instead of on a guess is method rule 7 at the smallest scale.
        for i in 0 to 400 loop
            exit when boot_seen;
            wait for 50 us;
        end loop;

        -- =============================================================
        -- C0a  THE CHIP BOOTED, independent of the DM entirely: it says the reset released, hart 0 fetched the ROM through the arbiter, programmed GPIO0 and drove the flash.
        -- Without it, a log full of DMI timeouts cannot distinguish "no DM" from "no chip".
        -- =============================================================
        chk(boot_seen,
            "C0a: the chip BOOTED -- the bootrom drove the SPI flash (this "
            & "check knows nothing about the DM)");

        -- =============================================================
        -- C1-C4  dmstatus identity, read with hart 0 selected.
        -- =============================================================
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(rop = RSP_SUCCESS, "C0: dmstatus read returns op = success");
        chk(fld(d, 3, 0) = 3,
            "C1: dmstatus.version = 3 (debug spec 1.0; Spike's 2 is the deviation)");
        chk(fld(d, 7, 7) = 1, "C2: dmstatus.authenticated = 1");
        chk(fld(d, 5, 5) = 1,
            "C3: dmstatus.hasresethaltreq = 1 (D1 shipped dbg_resethaltreq; "
            & "Spike reads 0 here and is NOT the reference)");
        chk(fld(d, 22, 22) = 1,
            "C4: dmstatus.impebreak = 1 (the third progbuf word, free)");

        -- =============================================================
        -- C5  hartinfo: the advertised data window
        -- =============================================================
        dmi_rd(A_HARTINFO, d, rop);
        chk(rop = RSP_SUCCESS, "C5a: hartinfo read returns op = success");
        chk(fld(d, 11, 0) = 16#680#,
            "C5b: hartinfo.dataaddr = 0x680 (the low 12 bits of 0x10680)");
        chk(fld(d, 16, 16) = 1, "C5c: hartinfo.dataaccess = 1 (memory-mapped)");
        chk(fld(d, 15, 12) = 1, "C5d: hartinfo.datasize = 1");

        -- =============================================================
        -- C6  abstractcs shape, clean before anything is asked
        -- =============================================================
        dmi_rd(A_ABSTRACTCS, d, rop);
        chk(rop = RSP_SUCCESS, "C6a: abstractcs read returns op = success");
        chk(fld(d, 28, 24) = 2, "C6b: abstractcs.progbufsize = 2");
        chk(fld(d, 3, 0) = 1,   "C6c: abstractcs.datacount = 1");
        chk(fld(d, 12, 12) = 0, "C6d: abstractcs.busy = 0 before any command");
        chk(fld(d, 10, 8) = 0,  "C6e: abstractcs.cmderr = 0 before any command");

        -- =============================================================
        -- C7  hartsel WARL width
        -- =============================================================
        -- Write all ten hartsello bits AND all ten hartselhi bits at once.
        -- 0x03FFFFC1 = hartsello[25:16] all ones, hartselhi[15:6] all ones and dmactive, with bits 1-5 left clear (writing set and clr resethaltreq together would be an ambiguous stimulus, not a stronger one).
        dmi_wr(A_DMCONTROL, x"03FFFFC1");
        dmi_rd(A_DMCONTROL, d, rop);
        -- R-D2-4(1): hartsello stores ALL TEN bits at BOTH N.
        -- The old masked-readback expectation was an INSTRUMENT DEFECT against the amended spec: at N=4 a 2-bit mask contradicts the NONEXISTENT clause outright, and a masked wide write silently selects a DIFFERENT EXISTING hart, the failure class the anti-clamp rationale condemns.
        expect_hs := 16#3FF#;
        chk(fld(d, 25, 16) = expect_hs,
            "C7a: hartsello stores ALL TEN bits at both N (no mask, no clamp)");
        chk(fld(d, 15, 6) = 0, "C7b: hartselhi reads zero on both chips");
        chk(fld(d, 1, 1) = 0,  "C7c: ndmreset reads zero (WARL, D2 residue)");
        chk(fld(d, 29, 29) = 0,"C7d: hartreset reads zero (WARL, D2 residue)");
        chk(fld(d, 26, 26) = 0,"C7e: hasel reads zero (dropped at D2)");

        -- =============================================================
        -- C8  NONEXISTENT, not clamp
        -- =============================================================
        -- Use the SMALLEST out-of-range value, not 0x3FF: NHARTS+1 is what a bit-masking implementation would fold onto a real hart (5 becomes 1 at N=4).
        -- 0x3FF cannot catch that; this can.
        dmi_wr(A_DMCONTROL, dmcontrol_w(NHARTS_G + 1, (others => '0')));
        dmi_rd(A_DMCONTROL, d2, rop);
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 14, 14) = 1 and fld(d, 15, 15) = 1
            and fld(d2, 25, 16) = (NHARTS_G + 1),
            "C8a: hartsel = NHARTS+1 reads back UNMASKED and sets BOTH nonexistent bits");
        chk(fld(d, 9, 9) = 0 and fld(d, 8, 8) = 0,
            "C8b: ...and reports NOT halted -- i.e. it did not CLAMP onto a "
            & "real hart the way Spike does");
        chk(fld(d, 11, 11) = 0 and fld(d, 10, 10) = 0,
            "C8c: ...and reports NOT running either");
        dmi_wr(A_DMCONTROL, dmcontrol_w(NHARTS_G - 1, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 14, 14) = 0 and fld(d, 15, 15) = 0,
            "C8d: hartsel = NHARTS-1 is EXISTENT -- the pair that stops a "
            & "hardwired nonexistent from passing C8a");

        -- =============================================================
        -- C9/C10/C11  haltsum0, haltsum1, and an unimplemented address
        -- =============================================================
        dmi_wr(A_DMCONTROL, dmcontrol_w(0, (others => '0')));
        dmi_rd(A_HALTSUM0, d, rop);
        chk(rop = RSP_SUCCESS, "C9a: haltsum0 (0x40) reads op = success");
        chk(d = x"00000000",   "C9b: haltsum0 = 0 with nothing halted");
        dmi_rd(A_HALTSUM1, d, rop);
        chk(rop = RSP_SUCCESS,
            "C10a: haltsum1 (0x13) reads op = SUCCESS -- d2_spec section 2 "
            & "carves it out of the unimplemented-address rule by name");
        chk(d = x"00000000", "C10b: haltsum1 reads zero");
        dmi_rd(A_UNIMPL, d, rop);
        chk(rop = RSP_FAILED,
            "C11: an unimplemented DMI address DOES return failed (the "
            & "counterpart to C10 -- either check alone is satisfiable by "
            & "an accident)");

        -- =============================================================
        -- C12  data0 proxy round trip
        -- =============================================================
        dmi_wr(A_DATA0, x"5EED0D2A");
        dmi_rd(A_DATA0, d, rop);
        chk(rop = RSP_SUCCESS and d = x"5EED0D2A",
            "C12a: data0 proxy round-trips a written value");
        dmi_wr(A_DATA0, x"A5A5F00D");
        dmi_rd(A_DATA0, d, rop);
        chk(d = x"A5A5F00D",
            "C12b: ...and a SECOND value, so C12a is not a reset constant");

        -- =============================================================
        -- C13  cmderr is W1C, in both directions
        -- =============================================================
        -- A LEGAL access-register command aimed at a RUNNING hart, which must be refused with HALT_RESUME.
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, (others => '0')));
        dmi_wr(A_COMMAND, x"00221008");        -- aarsize=2 transfer=1 read s0(x8)
        -- Wait out abstractcs.busy before reading cmderr.
        for i in 0 to N_BUSY loop
            dmi_rd(A_ABSTRACTCS, d, rop);
            exit when fld(d, 12, 12) = 0;
        end loop;
        chk(fld(d, 10, 8) = CMDERR_HALTRESUME,
            "C13a: a command aimed at a RUNNING hart sets cmderr = HALT_RESUME");
        dmi_wr(A_ABSTRACTCS, x"00000000");     -- write ZERO to the cmderr field
        dmi_rd(A_ABSTRACTCS, d, rop);
        chk(fld(d, 10, 8) = CMDERR_HALTRESUME,
            "C13b: writing ZERO to cmderr leaves it SET -- W1C, not "
            & "read/write (a normal RW register fails exactly here)");
        dmi_wr(A_ABSTRACTCS, x"00000700");     -- write ONES to the cmderr field
        dmi_rd(A_ABSTRACTCS, d, rop);
        chk(fld(d, 10, 8) = 0, "C13c: writing ONES to cmderr clears it");

        -- =============================================================
        -- C14/C15  abstractauto, dmcs2 group WARL
        -- =============================================================
        dmi_rd(A_ABSTRACTAUTO, d, rop);
        chk(d = x"00000000", "C14: abstractauto reads zero");

        dmi_rd(A_DMCS2, d, rop);
        chk(fld(d, 6, 2) = 0, "C15a: dmcs2.group resets to 0 (= no group)");
        -- hgwrite (bit 1) MUST be set for the group field to commit.
        -- The first draft wrote 0x7C, with hgwrite CLEAR, and then required a commit, i.e. it demanded non-conformant behaviour; this file's own tcl sibling always wrote 0x7E and always passed, which is what named the defect (R-D2-6(4)).
        dmi_wr(A_DMCS2, x"0000007E");          -- hgselect=0, hgwrite=1, group=all ones
        dmi_rd(A_DMCS2, d, rop);
        chk(fld(d, 6, 2) = 7,
            "C15b: dmcs2.group is WARL to 8 groups (all-ones reads back 7)");
        chk(fld(d, 0, 0) = 0, "C15c: dmcs2.hgselect stays 0 (harts, not triggers)");
        dmi_wr(A_DMCS2, x"00000002");          -- hgwrite, group 0: put it back
        dmi_wr(A_DMCS2, x"00000000");

        -- =============================================================
        -- C16-C21  THE LIVENESS HALF
        -- =============================================================
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 11, 11) = 1 and fld(d, 10, 10) = 1,
            "C16: hart 1 reads all- AND anyrunning BEFORE the halt request "
            & "(both bits of the pair driven -- OpenOCD misreads otherwise)");

        dmi_wr(A_DMCONTROL, dmcontrol_w(1, x"80000000"));   -- haltreq
        halted_seen := false;
        for i in 0 to N_HALT loop
            dmi_rd(A_DMSTATUS, d, rop);
            if fld(d, 9, 9) = 1 then halted_seen := true; exit; end if;
            wait for 2 us;
        end loop;
        chk(halted_seen,
            "C17a: haltreq through DMI halted hart 1 (allhalted)");
        chk(fld(d, 8, 8) = 1, "C17b: ...and anyhalted is driven too");
        chk(fld(d, 11, 11) = 0 and fld(d, 10, 10) = 0,
            "C17c: ...and running went low: the state is exclusive");
        -- Drop haltreq, as a debugger does; d2_spec section 4 makes the re-armed level the DM's job, not the core's.
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 9, 9) = 1,
            "C18: hart 1 STAYS halted after haltreq is dropped (halt is a "
            & "state; only a resume may end it)");

        dmi_rd(A_HALTSUM0, d, rop);
        chk(d = x"00000002",
            "C19: haltsum0 now reads EXACTLY bit 1 -- nonzero, and in the "
            & "right place.  This is what makes C9b evidence rather than a "
            & "hardwired zero (method rule 5)");

        dmi_wr(A_DMCONTROL, dmcontrol_w(2, (others => '0')));
        dmi_rd(A_DMSTATUS, d, rop);
        chk(fld(d, 9, 9) = 0 and fld(d, 11, 11) = 1,
            "C20: hart 2 is still RUNNING -- halting hart 1 halted only hart 1");

        -- C21/C22 on the HALTED hart, where HALT_RESUME cannot mask the answer.
        dmi_wr(A_DMCONTROL, dmcontrol_w(1, (others => '0')));
        dmi_wr(A_COMMAND, x"02201000");        -- cmdtype 2 = access memory
        for i in 0 to N_BUSY loop
            dmi_rd(A_ABSTRACTCS, d, rop);
            exit when fld(d, 12, 12) = 0;
        end loop;
        chk(fld(d, 10, 8) = CMDERR_NOTSUP,
            "C21: cmdtype 2 (access memory) on a HALTED hart returns "
            & "NOT_SUPPORTED -- that IS DD5's memory answer");
        dmi_wr(A_ABSTRACTCS, x"00000700");

        dmi_wr(A_COMMAND, x"00321008");        -- aarsize = 3 (64-bit)
        for i in 0 to N_BUSY loop
            dmi_rd(A_ABSTRACTCS, d, rop);
            exit when fld(d, 12, 12) = 0;
        end loop;
        chk(fld(d, 10, 8) = CMDERR_NOTSUP,
            "C22: aarsize = 3 on a HALTED hart returns NOT_SUPPORTED");
        dmi_wr(A_ABSTRACTCS, x"00000700");

        -- The halted hart is left halted ON PURPOSE: resuming it needs the trampoline at DEBUG_ENTRY_ADDR, which is a tcl deposit and belongs to the in-band instruments (see the header).
        wait for 20 us;
        if fails = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "dbg_dmi_tb: FAILURES" severity note;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
