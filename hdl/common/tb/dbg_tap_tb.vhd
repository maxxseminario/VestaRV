-- =============================================================================
-- dbg_tap_tb.vhd -- D3 acceptance instrument J3: THE JTAG PORT BENCH.
--
-- BLIND-AUTHORED 2026-08-06 against d3_spec.md sections 0-2 and
-- d3_cdc_spec.md section 3 (both FROZEN) by an agent that has not seen and
-- will never see the D3 implementation.  At authoring time (HEAD f3d5172) no
-- JTAG port exists anywhere in hdl/common, hdl/argus or platform/common --
-- verified by grep, not assumed -- so this bench DOES NOT ELABORATE on the
-- tracked tree.  That is its part-1 seen-to-FAIL leg and it is deliberate:
-- the errors name the five missing formals on entity MCU.  DO NOT "FIX" IT BY
-- DELETING THEM.  (Precedent: dbg_dmi_tb.vhd, instrument J1, whose eight
-- *E,FMLUNK errors were the same demonstration one phase earlier.)
--
-- WHAT THIS FILE DOES THAT NO tcl HARNESS CAN
--   1. It NAMES the five JTAG formals in VHDL, so a missing, renamed or
--      mis-typed port is a COMPILE-TIME failure rather than a runtime poll
--      that times out and gets misattributed.
--   2. It names the EIGHT dmi_* formals in the same port map.  d3_cdc_spec 7
--      RETAINS the external DMI ports and merges them with the DTM by
--      OR-composition; a build that quietly repurposed them would pass every
--      TAP check in the D3 tcl family and fail to elaborate here.  The two
--      port groups are asserted together, in one place, on purpose.
--   3. IT DRIVES THE TAP WHILE THE CHIP IS HELD IN RESET.  d3_cdc_spec 3
--      says "The TAP is NOT reset by system resetn (a debugger must be
--      attachable while the chip is held in reset -- the halt-on-reset
--      story)".  riscv_tb releases reset within microseconds of time zero and
--      a tcl harness cannot easily get in front of it; this bench simply does
--      not release reset until check J5.  That clause has no other instrument.
--
-- USAGE
--   tools/cosim/gate/mp_test/run_dbg_tap.sh [<rcf-basename>]
--   NHARTS_G=18 ./run_dbg_tap.sh              -- the N=18 shape of this file
--
-- PASS iff the log prints "ALL CHECKS PASSED" and contains no "CHECK FAILED".
-- Severity is `warning` on a failed check, never `error`, so the run
-- continues: a bench that stops at the first failure can never tell you
-- whether the rest would also have failed.
--
-- THE TAP PIN PROTOCOL, and why it is written this way
--   d3_spec 1: TMS sampled on TCK rising, TDO changes on falling, LSB-first.
--   So tck_cycle presents TMS/TDI while TCK is low, waits a setup window,
--   raises TCK, waits, lowers it, and waits again for TDO to settle.  TDO for
--   bit k is therefore READ BEFORE the k-th cycle is issued.  Driving TMS and
--   TCK in the same delta would be a race against the DUT's own edge process.
--
-- -V200X: no VHDL-2008 anywhere in this file (no to_hstring, no
-- unary-and); values are reported with integer'image of an integer built by
-- hand.  That restriction is a repo rule, not a preference.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;
use work.MemoryMap.all;

entity dbg_tap_tb is
    generic (
        -- Any real image: this bench asserts nothing about what hart 0 runs.
        TEST_FILE : string(1 to 29) := "../rcf/xxxrv32ui-p-simple.rcf";
        -- Selects the expected IDCODE (R-DD4(1)) as well as the hart count,
        -- so the same file grades Castalia (4) and Argus (18).
        NHARTS_G  : integer := 4
    );
end entity;

architecture sim of dbg_tap_tb is

    constant clk_hfxt_delay  : time := (0.5 sec) / 24000000;   -- 24 MHz
    constant clk_lfxt_delay  : time := (0.5 sec) / 32768;
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;

    -- TCK timing.  ~7.1 MHz against mclk's 24 MHz: a ratio a real debugger
    -- would use, and nothing in this bench depends on it.
    constant tck_setup : time := 20 ns;
    constant tck_half  : time := 60 ns;

    -- DM register DMI word addresses (debug_defines.h; d2_spec section 3)
    constant A_DATA0      : integer := 16#04#;
    constant A_DMCONTROL  : integer := 16#10#;
    constant A_DMSTATUS   : integer := 16#11#;
    constant A_HARTINFO   : integer := 16#12#;
    constant A_UNIMPL     : integer := 16#1A#;

    -- IR opcodes and DR lengths (d3_spec section 1)
    constant IR_IDCODE : std_logic_vector(4 downto 0) := "00001";
    constant IR_DTMCS  : std_logic_vector(4 downto 0) := "10000";
    constant IR_DMI    : std_logic_vector(4 downto 0) := "10001";
    constant IR_BYPASS : std_logic_vector(4 downto 0) := "11111";
    constant DR_DMI_LEN : integer := 41;   -- abits 7 + 34

    -- The USER's IDCODEs (R-DD4(1)).  version 1, partnum 0xCA57 / 0xA265,
    -- manufid 0x777, LSB 1.
    constant IDCODE_CASTALIA : std_logic_vector(31 downto 0) := x"1CA57EEF";
    constant IDCODE_ARGUS    : std_logic_vector(31 downto 0) := x"1A265EEF";

    constant OP_READ  : std_logic_vector(1 downto 0) := "01";
    constant OP_WRITE : std_logic_vector(1 downto 0) := "10";
    constant RSP_SUCCESS : std_logic_vector(1 downto 0) := "00";
    constant RSP_FAILED  : std_logic_vector(1 downto 0) := "10";

    -- Bounded everywhere.  A bench that can hang promises evidence that
    -- cannot occur (method rule 9), and the 1-minute rule makes a hung sim a
    -- wasted licence seat.
    constant W_XACT   : integer := 400;   -- mclk cycles per raw DMI phase
    constant N_IDLE   : integer := 16;    -- TCK cycles parked in Run-Test/Idle
    constant N_RETRY  : integer := 8;     -- TAP DMI attempts before giving up

    signal mclk    : std_logic;
    signal clk_lfxt: std_logic;
    signal resetn  : std_logic := '0';
    signal done    : boolean := false;
    signal fails   : integer := 0;
    signal checks  : integer := 0;
    signal dmi_dead : boolean := false;

    -- the frozen D2 DMI port (d2_spec section 2) -- NAMED HERE ON PURPOSE
    signal dmi_req_valid : std_logic := '0';
    signal dmi_req_op    : std_logic_vector(1 downto 0) := "00";
    signal dmi_req_addr  : std_logic_vector(6 downto 0) := (others => '0');
    signal dmi_req_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal dmi_req_ready : std_logic;
    signal dmi_rsp_valid : std_logic;
    signal dmi_rsp_data  : std_logic_vector(31 downto 0);
    signal dmi_rsp_op    : std_logic_vector(1 downto 0);

    -- the D3 JTAG port (d3_spec section 0).  trstn starts LOW: that is the
    -- fail-safe condition the spec names (TAP held in reset => inert), and
    -- this bench is the thing that plugs a debugger in.
    signal tck   : std_logic := '0';
    signal tms   : std_logic := '1';
    signal tdi   : std_logic := '0';
    signal trstn : std_logic := '0';
    signal tdo   : std_logic;

    -- pads / chip plumbing (the riscv_tb shape, reduced to what boots)
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
    -- clocks, pads, flash: copied in SHAPE from dbg_dmi_tb.vhd / riscv_tb.vhd.
    -- ---------------------------------------------------------------------
    ProcClkHFXT: process
    begin
        if done then wait; end if;
        mclk <= '0'; wait for clk_hfxt_period / 2;
        mclk <= '1'; wait for clk_hfxt_period / 2;
    end process;

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
    prt1(7)               <= '1' when boot_done_flag = '0' else 'Z';

    prt2_in <= (others => '0');
    prt3_in <= (others => '0');
    prt4_in <= (others => '0');
    prt5_in <= (others => '0');
    prt6_in <= (others => '0');

    process(resetn, flash_awake)
    begin
        if resetn = '0' then
            boot_done_flag <= '0';
        elsif falling_edge(flash_awake) then
            boot_done_flag <= '1';
        end if;
    end process;

    cs_flash <= prt1(pnum_gpio0_cs_flash) when boot_done_flag = '0' else '1';

    boot_watch: process(mclk)
    begin
        if rising_edge(mclk) then
            if flash_awake = '1' then boot_seen <= true; end if;
        end if;
    end process;

    watchdog: process
    begin
        wait for 60 ms;
        if not done then
            report "dbg_tap_tb: WATCHDOG -- the bench did not finish. "
                 & "CHECK FAILED: watchdog" severity note;
            report "dbg_tap_tb: WATCHDOG" severity failure;
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
    -- THE DUT.  `entity work.MCU`, not the riscv_tb COMPONENT, precisely so
    -- the JTAG and DMI formals can be NAMED -- which is what makes this
    -- file's FAIL leg an elaboration error rather than a silent pass.
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
            tck   => tck,
            tms   => tms,
            tdi   => tdi,
            tdo   => tdo,
            trstn => trstn,
            a0 => a0, a0_1 => a0_1, a0_2 => a0_2, a0_3 => a0_3
        );

    -- ---------------------------------------------------------------------
    -- THE CHECK SEQUENCE
    -- ---------------------------------------------------------------------
    stim: process

        variable idcode_exp : std_logic_vector(31 downto 0);
        variable dr32 : std_logic_vector(31 downto 0);
        variable dr41 : std_logic_vector(40 downto 0);
        variable cap41 : std_logic_vector(40 downto 0);
        variable rop  : std_logic_vector(1 downto 0);
        variable rdat : std_logic_vector(31 downto 0);
        variable ok   : boolean;
        variable i    : integer;

        procedure chk(cond : boolean; msg : string) is
        begin
            checks <= checks + 1;
            if cond then
                report "CHECK ok: " & msg severity note;
            else
                report "CHECK FAILED: " & msg severity warning;
                fails <= fails + 1;
            end if;
            wait for 0 ns;
        end procedure;

        -- ONE TCK cycle.  TCK is low on entry and on exit; TDO is settled and
        -- readable on exit.  See the header for why the setup window exists.
        procedure tck_cycle(tms_v : std_logic; tdi_v : std_logic) is
        begin
            tms <= tms_v;
            tdi <= tdi_v;
            wait for tck_setup;
            tck <= '1';
            wait for tck_half;
            tck <= '0';
            wait for tck_half;
        end procedure;

        -- TMS high x5 reaches Test-Logic-Reset from any of the 16 states.
        procedure tap_tlr is
        begin
            for k in 0 to 4 loop tck_cycle('1', '0'); end loop;
            tck_cycle('0', '0');          -- -> Run-Test/Idle
        end procedure;

        procedure tap_idle(n : integer) is
        begin
            for k in 1 to n loop tck_cycle('0', '0'); end loop;
        end procedure;

        -- Load IR from Run-Test/Idle, ending back in Run-Test/Idle.
        procedure scan_ir(v : std_logic_vector(4 downto 0)) is
        begin
            tck_cycle('1', '0');          -- Select-DR
            tck_cycle('1', '0');          -- Select-IR
            tck_cycle('0', '0');          -- Capture-IR
            tck_cycle('0', '0');          -- Shift-IR
            for k in 0 to 3 loop tck_cycle('0', v(k)); end loop;
            tck_cycle('1', v(4));         -- last bit -> Exit1-IR
            tck_cycle('1', '0');          -- Update-IR
            tck_cycle('0', '0');          -- Run-Test/Idle
        end procedure;

        -- Shift a 32-bit DR from Run-Test/Idle, ending back in Run-Test/Idle.
        -- LSB-first; TDO is sampled BEFORE each cycle.
        procedure scan_dr32(vout : std_logic_vector(31 downto 0);
                            vin  : out std_logic_vector(31 downto 0)) is
            variable c : std_logic_vector(31 downto 0);
        begin
            c := (others => '0');
            tck_cycle('1', '0');          -- Select-DR
            tck_cycle('0', '0');          -- Capture-DR
            tck_cycle('0', '0');          -- Shift-DR
            for k in 0 to 31 loop
                c(k) := tdo;
                if k = 31 then
                    tck_cycle('1', vout(k));
                else
                    tck_cycle('0', vout(k));
                end if;
            end loop;
            tck_cycle('1', '0');          -- Update-DR
            tck_cycle('0', '0');          -- Run-Test/Idle
            vin := c;
        end procedure;

        procedure scan_dr41(vout : std_logic_vector(40 downto 0);
                            vin  : out std_logic_vector(40 downto 0)) is
            variable c : std_logic_vector(40 downto 0);
        begin
            c := (others => '0');
            tck_cycle('1', '0');
            tck_cycle('0', '0');
            tck_cycle('0', '0');
            for k in 0 to DR_DMI_LEN-1 loop
                c(k) := tdo;
                if k = DR_DMI_LEN-1 then
                    tck_cycle('1', vout(k));
                else
                    tck_cycle('0', vout(k));
                end if;
            end loop;
            tck_cycle('1', '0');
            tck_cycle('0', '0');
            vin := c;
        end procedure;

        -- build a 41-bit dmi DR word: op[1:0], data[33:2], address[40:34]
        function dmi_word(op : std_logic_vector(1 downto 0);
                          dat : std_logic_vector(31 downto 0);
                          adr : integer) return std_logic_vector is
            variable w : std_logic_vector(40 downto 0);
        begin
            w := (others => '0');
            w(1 downto 0)  := op;
            w(33 downto 2) := dat;
            w(40 downto 34) := conv_std_logic_vector(adr, 7);
            return w;
        end function;

        -- ONE logical DMI transaction over the TAP: arm, dwell, NOP-capture,
        -- retry through dmireset on busy.  Bounded by N_RETRY.
        procedure tap_dmi(op : std_logic_vector(1 downto 0);
                          adr : integer;
                          dat : std_logic_vector(31 downto 0);
                          rop_o : out std_logic_vector(1 downto 0);
                          rdat_o : out std_logic_vector(31 downto 0)) is
            variable cap : std_logic_vector(40 downto 0);
            variable dc  : std_logic_vector(31 downto 0);
            variable junk : std_logic_vector(31 downto 0);
            variable attempt : integer;
            variable finished : boolean;
        begin
            rop_o := "01";                -- 01 is reserved: "never answered"
            rdat_o := (others => '0');
            finished := false;
            attempt := 0;
            while (not finished) and (attempt < N_RETRY) loop
                attempt := attempt + 1;
                scan_ir(IR_DMI);
                scan_dr41(dmi_word(op, dat, adr), cap);
                tap_idle(N_IDLE);
                scan_dr41(dmi_word("00", (others => '0'), 0), cap);
                if cap(1 downto 0) = "11" then
                    -- busy: clear the sticky flag and re-issue.  dmireset also
                    -- abandons the outstanding transaction (d3_spec 2), so the
                    -- whole request has to be presented again.
                    scan_ir(IR_DTMCS);
                    dc := (others => '0');
                    dc(16) := '1';                 -- dmireset
                    scan_dr32(dc, junk);
                else
                    rop_o := cap(1 downto 0);
                    rdat_o := cap(33 downto 2);
                    finished := true;
                    if cap(1 downto 0) = RSP_FAILED then
                        scan_ir(IR_DTMCS);
                        dc := (others => '0');
                        dc(16) := '1';
                        scan_dr32(dc, junk);
                    end if;
                end if;
            end loop;
        end procedure;

        -- ONE raw DMI transaction on the frozen D2 port (the dbg_dmi_tb
        -- shape), so this bench can also assert the OR-merge at run time.
        procedure raw_dmi(op : std_logic_vector(1 downto 0);
                          adr : integer;
                          dat : std_logic_vector(31 downto 0);
                          rop_o : out std_logic_vector(1 downto 0);
                          rdat_o : out std_logic_vector(31 downto 0)) is
            variable n : integer;
            variable got : boolean;
        begin
            rop_o := "01";
            rdat_o := (others => '0');
            if dmi_dead then return; end if;
            dmi_req_addr <= conv_std_logic_vector(adr, 7);
            dmi_req_data <= dat;
            dmi_req_op   <= op;
            dmi_req_valid <= '1';
            got := false;
            n := 0;
            while (not got) and (n < W_XACT) loop
                wait until rising_edge(mclk);
                n := n + 1;
                if dmi_req_ready = '1' then got := true; end if;
            end loop;
            dmi_req_valid <= '0';
            dmi_req_op <= "00";
            if not got then
                dmi_dead <= true;
                return;
            end if;
            got := false;
            n := 0;
            while (not got) and (n < W_XACT) loop
                wait until rising_edge(mclk);
                n := n + 1;
                if dmi_rsp_valid = '1' then
                    rop_o := dmi_rsp_op;
                    rdat_o := dmi_rsp_data;
                    got := true;
                end if;
            end loop;
        end procedure;

    begin
        if NHARTS_G = 18 then
            idcode_exp := IDCODE_ARGUS;
        else
            idcode_exp := IDCODE_CASTALIA;
        end if;

        -- =================================================================
        -- PHASE 1 -- THE CHIP IS HELD IN RESET.  resetn has never been
        -- released; mclk is running but the design is in reset.  Everything
        -- in this phase tests d3_cdc_spec 3's promise that the TAP is a
        -- separate reset domain.  IF THE TAP ONLY WORKS AFTER BOOT, THE
        -- HALT-ON-RESET STORY IS UNREACHABLE FROM A DEBUGGER and this phase
        -- is the only place in the whole D3 instrument set that says so.
        -- =================================================================
        wait for 20 * clk_hfxt_period;
        trstn <= '0';
        wait for 10 * clk_hfxt_period;
        trstn <= '1';                      -- plug the debugger in
        wait for 10 * clk_hfxt_period;
        tap_tlr;

        scan_dr32(x"00000000", dr32);      -- IR reset value is IDCODE
        chk(dr32 = idcode_exp,
            "J1: IDCODE reads correctly WITH THE CHIP HELD IN SYSTEM RESET "
          & "(the TAP is not in the resetn domain -- d3_cdc_spec 3)");
        chk(dr32(0) = '1', "J2: IDCODE bit 0 = 1 (1149.1 mandatory)");
        chk(dr32(31 downto 28) = "0001", "J3a: IDCODE version = 1");
        -- manufid 0x777 in 11 bits is "11101110111".  The first cut wrote
        -- "01110111011" (= 0x3BB) -- a mis-transcribed literal, instrument
        -- defect I-5.  T2's G5 asks the same question ARITHMETICALLY
        -- ([d2_fld $id 11 1] == 0x777) and passed on the same IDCODE in the
        -- same session: two independent instruments disagreed and the
        -- arithmetic one was right.  That is the argument for expressing a
        -- constant as a number wherever the language allows it.
        chk(dr32(11 downto 1) = "11101110111",
            "J3b: IDCODE manufid = 0x777 (R-DD4(1))");
        if NHARTS_G = 18 then
            chk(dr32(27 downto 12) = x"A265", "J3c: IDCODE partnum = 0xA265 (Argus)");
        else
            chk(dr32(27 downto 12) = x"CA57", "J3c: IDCODE partnum = 0xCA57 (Castalia)");
        end if;

        scan_ir(IR_DTMCS);
        scan_dr32(x"00000000", dr32);
        chk(dr32(3 downto 0) = "0001", "J4a: dtmcs.version = 1, still in system reset");
        chk(dr32(9 downto 4) = "000111", "J4b: dtmcs.abits = 7, still in system reset");
        chk(dr32(11 downto 10) = "00", "J4c: dtmcs.dmistat = 0 at rest");

        -- =================================================================
        -- PHASE 2 -- release reset, boot, and use the TAP for real.
        -- =================================================================
        resetn <= '0';
        wait for 40 * clk_hfxt_period;
        resetn <= '1';
        wait for 200 * clk_hfxt_period;
        resetn <= '0';
        wait for 4 * clk_hfxt_period;
        resetn <= '1';

        i := 0;
        while (not boot_seen) and (i < 400) loop
            wait for 50 us;
            i := i + 1;
        end loop;
        chk(boot_seen, "J5a: the chip BOOTED (the SPI flash was driven) -- "
                     & "so a later failure is about the DM, not the plumbing");

        tap_tlr;
        scan_dr32(x"00000000", dr32);
        chk(dr32 = idcode_exp,
            "J5b: IDCODE still reads correctly AFTER the system reset pulses -- "
          & "system resetn did not disturb the TAP");

        wait for 2 ms;                     -- let the tiles park

        tap_dmi(OP_READ, A_DMSTATUS, x"00000000", rop, rdat);
        chk(rop = RSP_SUCCESS,
            "J6a: a DMI read of dmstatus over the TAP returned SUCCESS");
        chk(rdat(3 downto 0) = "0011",
            "J6b: ...and dmstatus.version = 3 -- the 41 bits landed where the "
          & "DM expects them (d2_spec 3; Spike's 2 is the deviation)");

        tap_dmi(OP_READ, A_HARTINFO, x"00000000", rop, rdat);
        chk(rop = RSP_SUCCESS and rdat(11 downto 0) = x"680",
            "J7: hartinfo.dataaddr reads 0x680 over the TAP");

        tap_dmi(OP_READ, A_UNIMPL, x"00000000", rop, rdat);
        chk(rop = RSP_FAILED,
            "J8: an unimplemented DMI address returns FAILED over the TAP "
          & "(the same question dbg_conf's K11 asks over the raw port)");

        -- =================================================================
        -- PHASE 3 -- the OR-merge, at run time.  The eight dmi_* formals are
        -- associated in this bench's port map, so this is family B driving
        -- the DM directly while the DTM sits idle beside it.
        -- =================================================================
        raw_dmi(OP_READ, A_DMSTATUS, x"00000000", rop, rdat);
        chk((not dmi_dead) and rop = RSP_SUCCESS and rdat(3 downto 0) = "0011",
            "J9: the RAW dmi_* port ALSO reaches the DM with the DTM present "
          & "and idle -- d3_cdc_spec 7's OR-merge, proven at run time");

        raw_dmi(OP_WRITE, A_DATA0, x"5EED0D3A", rop, rdat);
        tap_dmi(OP_READ, A_DATA0, x"00000000", rop, rdat);
        chk(rop = RSP_SUCCESS and rdat = x"5EED0D3A",
            "J10: a RAW write is read back over the TAP -- both masters are "
          & "talking to ONE Debug Module");

        tap_dmi(OP_WRITE, A_DATA0, x"0D3A5EED", rop, rdat);
        raw_dmi(OP_READ, A_DATA0, x"00000000", rop, rdat);
        chk((not dmi_dead) and rop = RSP_SUCCESS and rdat = x"0D3A5EED",
            "J11: ...and the converse, a TAP write read back over the raw port");

        if dmi_dead then
            report "dbg_tap_tb: the RAW dmi_* port never handshook; J9/J11 are "
                 & "about the OR-merge, not about the TAP" severity note;
        end if;

        if fails = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "dbg_tap_tb: FAILURES" severity note;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
