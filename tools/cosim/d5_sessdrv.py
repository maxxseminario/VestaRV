#!/usr/bin/env python3
# VestaRV: run a real OpenOCD and gdb session against the in-simulator remote_bitbang bridge.
#
# Every grader is an ordering between snapshots taken between gdb verbs, which the in-simulator
# harness cannot take, so the bridge publishes a passive-only control port and this driver sends
# SNAP on it. The verb sequence is a script file (GDB/MON/SNAP/CTL/EXPECT/NOTE/FAILOK). Teardown
# SIGKILLs gdb and OpenOCD: either one's clean exit removes breakpoints, rewriting the tile TCM.
import argparse
import os
import re
import signal
import socket
import subprocess
import sys
import time

PROMPT = re.compile(r"\(gdb\) $")


class Ctl(object):
    """The passive control channel to the bridge."""

    def __init__(self, port, log):
        self.s = socket.create_connection(("127.0.0.1", port), timeout=600)
        self.f = self.s.makefile("rwb")
        self.log = log
        self.snaps = 0
        self.dead = False
        self.lost = 0

    def send(self, line):
        # A dead control channel is a REPORTED condition, never an exception
        # that takes the driver down.  It means the bridge's session already
        # ended -- which is itself the finding -- and the transcript up to that
        # point is the evidence.  Losing it to a traceback would be the worst
        # of both.
        if self.dead:
            self.log("CTL ! %s -- control channel already closed; not sent" % line)
            self.lost += 1
            return ""
        self.log("CTL > %s" % line)
        try:
            self.f.write((line + "\n").encode())
            self.f.flush()
            reply = self.f.readline().decode().rstrip("\r\n")
        except Exception as e:
            self.log("CTL ! %s -- control channel FAILED (%s); the bridge session"
                     " has ended.  Every later snapshot is lost and the graders"
                     " will say NOT-GRADED, which is the honest outcome." % (line, e))
            self.dead = True
            self.lost += 1
            return ""
        if reply == "":
            self.log("CTL ! %s -- EOF on the control channel (bridge session over)" % line)
            self.dead = True
            self.lost += 1
            return ""
        self.log("CTL < %s" % reply)
        if line.upper().startswith("SNAP"):
            self.snaps += 1
        return reply

    def close(self):
        try:
            self.s.close()
        except Exception:
            pass


def wait_for_file(path, timeout, log):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if os.path.exists(path):
            time.sleep(0.3)          # the bridge writes-then-renames; be safe
            with open(path) as fh:
                txt = fh.read().split()
            if len(txt) == 2:
                log("portfile %s -> rbb=%s ctl=%s after %.1fs"
                    % (path, txt[0], txt[1], time.time() - t0))
                return int(txt[0]), int(txt[1])
        time.sleep(1.0)
    raise SystemExit("FATAL: portfile %s never appeared within %ds" % (path, timeout))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--portfile", required=True)
    ap.add_argument("--cfg", required=True)
    ap.add_argument("--elf", required=True)
    ap.add_argument("--script", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--openocd",
                    default=os.path.expanduser("~/vesta_tools/xpack-openocd-0.12.0-7/bin/openocd"))
    ap.add_argument("--gdb", default="riscv-none-elf-gdb")
    ap.add_argument("--gdb-port", type=int, default=3333)
    ap.add_argument("--debuglevel", default="3",
                    help="OpenOCD -d level.  d5_wire_order.py needs 3.")
    ap.add_argument("--portfile-timeout", type=int, default=1800)
    ap.add_argument("--gdb-timeout", type=int, default=1200)
    ap.add_argument("--ready-regex", default=None,
                    help="After OpenOCD announces its gdb port, ALSO wait for "
                         "this regex in the OpenOCD log before spawning gdb. "
                         "MEASURED NECESSARY AT N=18: OpenOCD starts listening "
                         "before it has examined the harts, and a gdb that "
                         "connects during examination desynchronises the packet "
                         "stream -- 'Remote replied unexpectedly to "
                         "vMustReplyEmpty', then 'No threads' and '\"monitor\" "
                         "command not supported by this target'.  That reads "
                         "like a dead target and is a RACE.  Pass e.g. "
                         r"'\[vesta\.cpu17\] Examination succeed'.")
    args = ap.parse_args()

    if not os.path.isdir(args.outdir):
        os.makedirs(args.outdir)
    tpath = os.path.join(args.outdir, "driver.log")
    tlog = open(tpath, "w")

    def log(msg):
        line = "[%8.2f] %s" % (time.time() - T0, msg)
        print(line)
        sys.stdout.flush()
        tlog.write(line + "\n")
        tlog.flush()

    T0 = time.time()
    log("D5SESSDRV start  cfg=%s elf=%s script=%s" % (args.cfg, args.elf, args.script))

    rbb, ctlport = wait_for_file(args.portfile, args.portfile_timeout, log)

    # OpenOCD
    ocdlog = os.path.join(args.outdir, "openocd.log")
    env = dict(os.environ)
    env["REMOTE_BITBANG_PORT"] = str(rbb)
    env["REMOTE_BITBANG_HOST"] = "localhost"
    cmd = [args.openocd, "-d%s" % args.debuglevel, "-l", ocdlog,
           "-c", "gdb port %d" % args.gdb_port,
           "-c", "telnet port disabled", "-c", "tcl port disabled",
           "-f", args.cfg]
    log("OPENOCD launch: %s" % " ".join(cmd))
    ocd = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)

    # Wait for OpenOCD's own gdb-listen line IN ITS LOG.  Never infer readiness
    # from a sleep: the attach cost over this transport is minutes at N=18.
    want = "Listening on port %d for gdb connections" % args.gdb_port
    t0 = time.time()
    ready = False
    while time.time() - t0 < args.portfile_timeout:
        if ocd.poll() is not None:
            log("OPENOCD exited early rc=%s -- see %s" % (ocd.returncode, ocdlog))
            break
        if os.path.exists(ocdlog):
            with open(ocdlog, errors="replace") as fh:
                if want in fh.read():
                    ready = True
                    break
        time.sleep(1.0)
    if not ready:
        log("FATAL: OpenOCD never announced its gdb port")
        try:
            ocd.kill()
        except Exception:
            pass
        raise SystemExit(2)
    log("OPENOCD ready after %.1fs (gdb port %d)" % (time.time() - t0, args.gdb_port))

    # The listen line is NOT readiness -- see --ready-regex's help text.
    if args.ready_regex:
        rx = re.compile(args.ready_regex)
        t1 = time.time()
        seen = False
        while time.time() - t1 < args.portfile_timeout:
            if ocd.poll() is not None:
                log("OPENOCD exited early rc=%s while waiting for /%s/"
                    % (ocd.returncode, args.ready_regex))
                break
            with open(ocdlog, errors="replace") as fh:
                if rx.search(fh.read()):
                    seen = True
                    break
            time.sleep(1.0)
        if not seen:
            log("FATAL: OpenOCD never logged /%s/ -- refusing to attach gdb into"
                " an unexamined target, which desynchronises the packet stream"
                % args.ready_regex)
            try:
                ocd.kill()
            except Exception:
                pass
            raise SystemExit(2)
        log("OPENOCD examined after a further %.1fs (matched /%s/)"
            % (time.time() - t1, args.ready_regex))

    # The IDCODE line is READ, never inferred: a -expected-id mismatch is only a
    # WARNING in this OpenOCD, so the absence of a failure proves nothing.
    with open(ocdlog, errors="replace") as fh:
        for ln in fh:
            if "tap/device found" in ln or "Error" in ln and "tap" in ln.lower():
                log("OPENOCD IDCODE LINE: %s" % ln.rstrip())

    ctl = Ctl(ctlport, log)

    # gdb
    import pexpect
    gdb = pexpect.spawn(args.gdb, ["-nx", "-q", args.elf],
                        timeout=args.gdb_timeout, encoding="utf-8",
                        codec_errors="replace")
    gdb.logfile_read = open(os.path.join(args.outdir, "gdb.log"), "w")
    gdb.expect(PROMPT)

    failures = []
    last_out = [""]

    def gdb_cmd(c, failok=False):
        log("GDB > %s" % c)
        gdb.sendline(c)
        try:
            gdb.expect(PROMPT)
        except pexpect.TIMEOUT:
            log("GDB !! TIMEOUT waiting for prompt after: %s" % c)
            failures.append("TIMEOUT: %s" % c)
            last_out[0] = gdb.before
            return
        out = gdb.before
        last_out[0] = out
        for ln in out.splitlines()[1:]:
            if ln.strip():
                log("GDB < %s" % ln.rstrip())

    # boilerplate that is NOT part of the measured session
    for c in ["set confirm off", "set pagination off", "set height 0",
              "set width 0", "set remotetimeout 120",
              "set architecture riscv:rv32"]:
        gdb_cmd(c)

    # run the script
    nlines = 0
    with open(args.script) as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            nlines += 1
            failok = False
            if s.upper().startswith("FAILOK "):
                failok = True
                s = s[7:].strip()
            verb, _, rest = s.partition(" ")
            verb = verb.upper()
            rest = rest.strip()
            if verb == "GDB":
                gdb_cmd(rest, failok)
            elif verb == "MON":
                gdb_cmd("monitor " + rest, failok)
            elif verb == "SNAP":
                ctl.send("SNAP " + rest)
            elif verb == "CTL":
                ctl.send(rest)
            elif verb == "NOTE":
                log("NOTE %s" % rest)
            elif verb == "EXPECT":
                if re.search(rest, last_out[0] or "", re.M):
                    log("EXPECT ok: /%s/" % rest)
                else:
                    log("EXPECT FAILED: /%s/ did not match the last gdb output" % rest)
                    if not failok:
                        failures.append("EXPECT %s" % rest)
            elif verb == "SLEEP":
                time.sleep(float(rest))
            else:
                log("SCRIPT: unknown directive %r -- ignored" % verb)
                failures.append("unknown directive %s" % verb)

    log("SCRIPT complete: %d directives, %d snapshot(s) delivered, %d control"
        " line(s) LOST to a closed channel, %d failure(s)"
        % (nlines, ctl.snaps, ctl.lost, len(failures)))
    if ctl.lost:
        failures.append("%d control line(s) lost -- the bridge session ended early" % ctl.lost)
    for f in failures:
        log("  FAILURE: %s" % f)

    # teardown (see the header: this is instrument, not housekeeping)
    log("TEARDOWN: SIGKILL gdb WITHOUT detaching, so the planted ebreak and the"
        " register cookie survive into the graders' live reads")
    try:
        gdb.kill(signal.SIGKILL)
    except Exception:
        pass
    time.sleep(2.0)
    ctl.send("STAT")
    ctl.close()
    # SIGKILL, not SIGTERM: a CLEAN OpenOCD exit deletes every breakpoint from
    # every target, which on this chip rewrites the victim's TCM and destroys
    # the evidence SG-G1 reads at grading time.  See the header.  The bridge
    # ends its session on EOF, so nothing depends on the `Q`.
    log("TEARDOWN: SIGKILL OpenOCD -- a clean exit would run"
        " breakpoint_remove_all_internal() and un-plant the ebreak; the bridge"
        " ends its session on EOF instead of on Q")
    try:
        ocd.kill()
        ocd.wait(timeout=120)
    except Exception:
        pass
    log("OPENOCD rc=%s" % ocd.returncode)
    log("D5SESSDRV done in %.1fs; transcript %s" % (time.time() - T0, tpath))
    tlog.close()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
