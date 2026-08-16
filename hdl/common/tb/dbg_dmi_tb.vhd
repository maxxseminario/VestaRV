/* =============================================================================
   dbg_dmi_tb.vhd
   =============================================================================
   Debug Module register-map conformance bench: it drives the MCU's DMI port and grades dmstatus, hartinfo, abstractcs, hartsel WARL, haltsum0/1, data0, cmderr, abstractauto and dmcs2.
   The DUT is entity work.MCU rather than the riscv_tb component so the DMI formals are NAMED here, which turns a missing DMI port into an elaboration error instead of a silent pass.
   Assumed handshake, legal under either reading of the port contract: one request in flight, req_valid held until req_ready is sampled high, rsp_valid one-shot per request.
   Out of scope: resume, register transfers, progbuf/postexec, halt groups and dcsr.prv all need a trampoline deposited at DEBUG_ENTRY_ADDR, so they belong to the in-band instruments.
   Run xcelium/mp_test/run_dbg_dmi.sh; PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;
use work.MemoryMap.all;

entity dbg_dmi_tb is
    generic (
        -- Any real image: this bench needs a booting chip, not a particular test, and asserts nothing about what hart 0 executes.
        TEST_FILE : string(1 to 29) := "../rcf/xxxrv32ui-p-simple.rcf";
        -- Hart count drives the hartsel WARL-width and nonexistent arithmetic, so one file grades any chip shape.
        NHARTS_G  : integer := 4
    );
end entity;

architecture sim of dbg_dmi_tb is

    constant clk_hfxt_delay  : time := (0.5 sec) / 24000000;   -- 24 MHz mclk
    constant clk_lfxt_delay  : time := (0.5 sec) / 32768;      -- 32.768 kHz LFXT
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;

    -- DM register DMI word addresses.
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
    -- Deliberately unallocated, so the bench has an address that must answer "failed".
    constant A_UNIMPL     : integer := 16#1A#;

    -- DMI request opcodes and response codes.
    constant OP_READ  : std_logic_vector(1 downto 0) := "01";
    constant OP_WRITE : std_logic_vector(1 downto 0) := "10";
    constant RSP_SUCCESS : std_logic_vector(1 downto 0) := "00";
    constant RSP_FAILED  : std_logic_vector(1 downto 0) := "10";

    -- abstractcs.cmderr encodings this bench expects.
    constant CMDERR_NOTSUP     : integer := 2;
    constant CMDERR_HALTRESUME : integer := 4;

    -- Budgets are generous because DMI latency is unspecified and what is under test is "eventually" versus "never", but not unbounded: a poll whose every iteration is itself a timing-out transaction multiplies the two budgets together.
    -- So transactions are bounded in mclk cycles, polls in iterations, and a port that never handshakes is latched dead after the first attempt so the run reports instead of grinding.
    constant W_XACT  : integer := 400;     -- mclk cycles per DMI phase (~17 us)
    constant N_HALT  : integer := 400;     -- dmstatus polls after haltreq
    constant N_BUSY  : integer := 200;     -- abstractcs polls while busy

    signal mclk    : std_logic;
    signal clk_lfxt: std_logic;
    signal resetn  : std_logic := '0';
    signal done    : boolean := false;   -- set when the stimulus process finishes
    signal fails   : integer := 0;       -- failed checks
    signal checks  : integer := 0;       -- checks attempted
    -- Latched the first time a DMI transaction gets no req_ready; every later transaction then returns immediately, so an absent or wedged DM is reported rather than ground on.
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
    -- Latched the first time the bootrom actually drives the SPI flash: the one check here that grades the CHIP rather than the DM, so a failing log separates plumbing from DM.
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

    -- Clocks, pads and flash in the riscv_tb shape, reduced to the boot path; the unused GPIO inputs idle low.
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

    -- Remember that the flash was ever addressed, i.e. that the chip really booted.
    boot_watch: process(mclk)
    begin
        if rising_edge(mclk) then
            if flash_awake = '1' then boot_seen <= true; end if;
        end if;
    end process;

    -- A bench that can hang promises evidence that never arrives, so every loop here is bounded and this watchdog is the belt for anything those bounds cannot see.
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

    -- The DUT, instantiated as entity work.MCU rather than through a component, so the DMI formals are named and a missing port fails elaboration.
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

    -- The stimulus and grading process: boot the chip, then walk the checks in order.
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
        -- The temporary is THIRTY-ONE bits, not 32: conv_integer raises "CONV_INTEGER argument too large" for any 32-bit argument regardless of its value.
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

        -- Wait for the chip to be OBSERVABLY alive rather than for a fixed time: the bootrom switches SMCLK onto LFXT mid-boot, so the flash handshake lands long after any plausible fixed delay.
        for i in 0 to 400 loop
            exit when boot_seen;
            wait for 50 us;
        end loop;

        -- C0a: the chip booted, independent of the DM: reset released, hart 0 fetched the ROM through the arbiter, programmed GPIO0 and drove the flash.
        -- Without it a log full of DMI timeouts cannot distinguish "no DM" from "no chip".
        chk(boot_seen,
            "C0a: the chip BOOTED -- the bootrom drove the SPI flash (this "
            & "check knows nothing about the DM)");

        -- C1-C4: dmstatus identity, read with hart 0 selected.
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

        -- C5: hartinfo, the advertised data window.
        dmi_rd(A_HARTINFO, d, rop);
        chk(rop = RSP_SUCCESS, "C5a: hartinfo read returns op = success");
        chk(fld(d, 11, 0) = 16#680#,
            "C5b: hartinfo.dataaddr = 0x680 (the low 12 bits of 0x10680)");
        chk(fld(d, 16, 16) = 1, "C5c: hartinfo.dataaccess = 1 (memory-mapped)");
        chk(fld(d, 15, 12) = 1, "C5d: hartinfo.datasize = 1");

        -- C6: abstractcs shape, clean before anything is asked of it.
        dmi_rd(A_ABSTRACTCS, d, rop);
        chk(rop = RSP_SUCCESS, "C6a: abstractcs read returns op = success");
        chk(fld(d, 28, 24) = 2, "C6b: abstractcs.progbufsize = 2");
        chk(fld(d, 3, 0) = 1,   "C6c: abstractcs.datacount = 1");
        chk(fld(d, 12, 12) = 0, "C6d: abstractcs.busy = 0 before any command");
        chk(fld(d, 10, 8) = 0,  "C6e: abstractcs.cmderr = 0 before any command");

        -- C7: hartsel WARL width, writing all ten hartsello bits and all ten hartselhi bits at once.
        -- 0x03FFFFC1 = hartsello[25:16] all ones, hartselhi[15:6] all ones and dmactive, with bits 1-5 left clear (set and clr resethaltreq together would be an ambiguous stimulus).
        dmi_wr(A_DMCONTROL, x"03FFFFC1");
        dmi_rd(A_DMCONTROL, d, rop);
        -- hartsello stores ALL TEN bits at every hart count: masking it would contradict the nonexistent rule and let a wide write silently select a different EXISTING hart.
        expect_hs := 16#3FF#;
        chk(fld(d, 25, 16) = expect_hs,
            "C7a: hartsello stores ALL TEN bits at both N (no mask, no clamp)");
        chk(fld(d, 15, 6) = 0, "C7b: hartselhi reads zero on both chips");
        chk(fld(d, 1, 1) = 0,  "C7c: ndmreset reads zero (WARL, D2 residue)");
        chk(fld(d, 29, 29) = 0,"C7d: hartreset reads zero (WARL, D2 residue)");
        chk(fld(d, 26, 26) = 0,"C7e: hasel reads zero (dropped at D2)");

        -- C8: an out-of-range hartsel must read NONEXISTENT, never clamp onto a real hart.
        -- Use the SMALLEST out-of-range value, not 0x3FF: NHARTS+1 is what a bit-masking implementation folds onto a real hart, and 0x3FF cannot catch that.
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

        -- C9/C10/C11: haltsum0, haltsum1, and an unimplemented address.
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

        -- C12: data0 proxy round trip (whether the proxy really touched the shared word is the in-band instruments' half).
        dmi_wr(A_DATA0, x"5EED0D2A");
        dmi_rd(A_DATA0, d, rop);
        chk(rop = RSP_SUCCESS and d = x"5EED0D2A",
            "C12a: data0 proxy round-trips a written value");
        dmi_wr(A_DATA0, x"A5A5F00D");
        dmi_rd(A_DATA0, d, rop);
        chk(d = x"A5A5F00D",
            "C12b: ...and a SECOND value, so C12a is not a reset constant");

        -- C13: cmderr is W1C in both directions, so writing zero must leave it set and writing ones must clear it.
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

        -- C14/C15: abstractauto and the dmcs2 group WARL.
        dmi_rd(A_ABSTRACTAUTO, d, rop);
        chk(d = x"00000000", "C14: abstractauto reads zero");

        dmi_rd(A_DMCS2, d, rop);
        chk(fld(d, 6, 2) = 0, "C15a: dmcs2.group resets to 0 (= no group)");
        -- hgwrite (bit 1) MUST be set for the group field to commit, so the stimulus is 0x7E and never 0x7C.
        dmi_wr(A_DMCS2, x"0000007E");          -- hgselect=0, hgwrite=1, group=all ones
        dmi_rd(A_DMCS2, d, rop);
        chk(fld(d, 6, 2) = 7,
            "C15b: dmcs2.group is WARL to 8 groups (all-ones reads back 7)");
        chk(fld(d, 0, 0) = 0, "C15c: dmcs2.hgselect stays 0 (harts, not triggers)");
        dmi_wr(A_DMCS2, x"00000002");          -- hgwrite, group 0: put it back
        dmi_wr(A_DMCS2, x"00000000");

        -- C16-C22: the liveness half, which actually halts a hart so that the expected-zero checks above are evidence and not a hardwired zero.
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
        -- Drop haltreq, as a debugger does; re-arming the level is the DM's job, not the core's.
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

        -- The halted hart is left halted ON PURPOSE: resuming it needs the trampoline at DEBUG_ENTRY_ADDR, which is a deposit only the in-band instruments can make.
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
