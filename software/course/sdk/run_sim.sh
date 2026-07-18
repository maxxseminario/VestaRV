#!/bin/bash
# run_sim.sh -- INSTRUCTOR wrapper: run ONE course firmware image in the
# course-config (argus_course) behavioral simulator and report PASS/FAIL plus
# the UART0 console output.
#
#   sdk/run_sim.sh <path-to-flashed-rcf>
#   (course.mk's `make sim` calls this for you.)
#
# Students run on physical chips; simulation is instructor-side. This drives the
# firmware through the same riscv_tb the chip generator's `make verify` stages,
# in the verify_<chip> environment for config/argus_course.json (chip "Argus").
#
# Contracts baked in (see ~/vestarv/CLAUDE.md and platform/common/verify.sh):
#   * TEST_FILE is the fixed 29-char string "../rco/" + a 22-char x-padded name.
#   * The student image is staged into a COURSE-OWNED rcf dir (rcf_course) via a
#     3-char symlink (rco) -- NEVER the suite's rcf/ (an N=18 image there would
#     poison the N=4 regression). rcf_course carries its own .nharts=18 stamp.
#   * A healthy sim finishes in ~1 min; a watchdog kills a hung run by PID and
#     reports HUNG. Only this run's own xmsim is ever killed.
#   * The runner never pipes xmsim through head/tail (SIGPIPE leaves stale logs).
# NB: no `set -u` -- sourcing cdspaths.sh references vars that may be unset.
set -o pipefail

REPO="$HOME/vestarv"
STAGE="$REPO/xcelium/riscv_test/verify_argus"        # verify_<chip>, chip=Argus
RISCV_TEST="$REPO/xcelium/riscv_test"
COURSE_RCF="$REPO/verification/isa/rcf_course"        # course-owned image dir
SUITE_RCF="$REPO/verification/isa/rcf"                # the N=4 regression set
LINK="rco"                                            # 3-char symlink -> rcf_course
WATCHDOG="${WATCHDOG:-150}"                            # seconds (1-min rule + margin)
TOP="tb_course"

die() { echo "run_sim: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: run_sim.sh <path-to-flashed-rcf>"
RCF="$1"
[ -f "$RCF" ] || die "no such rcf: $RCF"
BASE="$(basename "$RCF")"
[ "${#BASE}" -eq 22 ] || die "rcf basename must be 22 chars (the TEST_FILE contract); got ${#BASE}: $BASE
  (build with course.mk so flash_prepend.sh pads it: flash_prepend.sh <rcf> 22)"

# --- the course-config sim environment must already be staged ----------------
[ -d "$STAGE/xcelium.d/work" ] || die "course sim env not staged.
  Run first:  make -C $REPO/platform/common verify CONFIG=config/argus_course.json"
grep -q "npu0" "$STAGE/hdl/MCU.vhd" 2>/dev/null || die "staged $STAGE is NOT the course (NPU) config.
  Re-stage:   make -C $REPO/platform/common verify CONFIG=config/argus_course.json"

source "$REPO/cdspaths.sh" 2>/dev/null || die "could not source cdspaths.sh"

# --- stage the student image into the course-owned rcf dir -------------------
mkdir -p "$COURSE_RCF"
cp -f "$RCF" "$COURSE_RCF/$BASE"
echo 18 > "$COURSE_RCF/.nharts"                       # course build is N=18
ln -sfn "../../verification/isa/rcf_course" "$RISCV_TEST/$LINK"

# hygiene: never let this touch the N=4 suite stamp
if [ -f "$SUITE_RCF/.nharts" ] && [ "$(cat "$SUITE_RCF/.nharts")" != 4 ]; then
    die "refusing to run: $SUITE_RCF/.nharts != 4 (suite images poisoned) -- rebuild them"
fi

TEST_FILE="../$LINK/$BASE"                             # 7 + 22 = 29 chars
[ "${#TEST_FILE}" -eq 29 ] || die "internal: TEST_FILE is ${#TEST_FILE} chars, want 29"

# --- per-test wrapper + capture tcl -----------------------------------------
RUN="$STAGE/course_run"
mkdir -p "$RUN" "$STAGE/wrappers" "$STAGE/log"
cat > "$STAGE/wrappers/${TOP}.vhd" <<VHDL
entity ${TOP} is end ${TOP};
architecture behavioral of ${TOP} is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "${TEST_FILE}");
end architecture;
VHDL

UARTLOG="$RUN/uart_console.txt"
SIMLOG="$STAGE/log/${TOP}.log"
TCL="$RUN/run_uart.tcl"
# UART0 TX console tap: the CPU writes each byte to the UART0 TX register; on
# every start_tx pulse the transmitted byte is in uart0.UART_TX. `value` has no
# -radix here and returns the bit-string WITH quotes, so strip to [01] and parse
# as binary. `stop -object ... -continue -execute` is this Xcelium's value-change
# callback (there is no `when`).
cat > "$TCL" <<TCL
source ../../disable_x_warnings.tcl
set ::ufh [open "$UARTLOG" w]
stop -object :uut:dut:uart0:start_tx -continue -execute {
    if {[value :uut:dut:uart0:start_tx] eq "'1'"} {
        set raw [value :uut:dut:uart0:UART_TX]
        regsub -all {[^01]} \$raw "" b
        if {[string length \$b] == 8} {
            puts -nonewline \$::ufh [format %c [expr 0b\$b]]; flush \$::ufh
        }
    }
}
run
close \$::ufh
exit
TCL
: > "$UARTLOG"

# --- compile the wrapper into the staged work lib, elaborate ----------------
cd "$STAGE" || die "cannot cd $STAGE"
echo "run_sim: compiling wrapper + elaborating ${TOP} ..."
xmvhdl -V200X -WORK work -CONTROLRELAX nlstex -RELAX "wrappers/${TOP}.vhd" \
    > "$STAGE/log/${TOP}.compile.log" 2>&1 || die "wrapper compile failed (see log/${TOP}.compile.log)"
xmelab -ACCESS +r "work.${TOP}:behavioral" \
    > "$STAGE/log/${TOP}.elab.log" 2>&1 || die "elaboration failed (see log/${TOP}.elab.log)"

# --- simulate under a PID watchdog ------------------------------------------
echo "run_sim: simulating (watchdog ${WATCHDOG}s) ..."
START=$(date +%s)
timeout -k 15 "$WATCHDOG" \
    xmsim "work.${TOP}:behavioral" -input "$TCL" -licqueue -LOGFILE "$SIMLOG" \
    > /dev/null 2>&1
RC=$?
END=$(date +%s)
WALL=$((END - START))
# reap any straggler xmsim from THIS run only (match our unique logfile path)
pkill -9 -f "$SIMLOG" 2>/dev/null

# --- report -----------------------------------------------------------------
echo ""
echo "================= UART0 console ================="
cat "$UARTLOG"
echo ""
echo "================================================="
VERDICT=FAIL
if [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
    echo "run_sim: HUNG (watchdog fired after ${WATCHDOG}s) -- see $SIMLOG"
    exit 2
fi
if grep -aq "TEST PASSED" "$SIMLOG" 2>/dev/null; then
    VERDICT=PASS
elif grep -aq "TEST FAILED\|TEST TIMED OUT" "$SIMLOG" 2>/dev/null; then
    VERDICT=FAIL
else
    echo "run_sim: no verdict line in $SIMLOG (unexpected)"
    exit 3
fi
A0=$([ "$VERDICT" = PASS ] && echo "a0=0xCAFEBABE" || echo "a0=0xDEADBEEF")
echo "run_sim: $VERDICT ($A0)   wall=${WALL}s   image=$BASE"
[ "$VERDICT" = PASS ] && exit 0 || exit 1
