#!/usr/bin/python3.6
"""d5_sdf_live.py -- prove that an SDF back-annotation actually HAPPENED.

D5 acceptance instrument, blind-authored 2026-08-10 against d5_spec.md section 6
("SDF annotation PROVEN live -- the sdf.log consumed, banner quoted -- the
SDF-silently-optional lesson").  /usr/bin/python3.6 only.

WHY THIS EXISTS, AND WHY THE EXISTING GUARD IS NOT ENOUGH
    Every gate runner in this tree already carries the 2026-07-29 guard, e.g.
    xcelium/riscv_test/genus_mp/xrun.sh:80-88.  Read it: it checks that the
    .sdfcmd EXISTS and that every SDF_FILE it names RESOLVES -- all of it
    BEFORE xrun starts.  That is a pre-flight check, and it cannot see the one
    failure the memory entry is about: a run where the annotator did not
    consume the file, or consumed a DIFFERENT one.  A gate leg whose whole
    claim is "through the SDF-annotated gates" must show the POST-run half.

WHAT COUNTS AS PROOF, and each item is a POSITIVE artifact rather than an
absence:
    1. log/sdf.log exists, is non-empty, and is NEWER than the netlist it
       annotates (a stale log from a previous cut parses perfectly -- method
       rule 6, and it is exactly how a 47,012 nearly got quoted against a
       4,668,509 pin).
    2. Its header block carries the annotator's own banner:
       "Annotating SDF timing data:", a "Compiled SDF file:" line, a
       "Backannotation scope:" line and an "MTM control:" line.
    3. The compiled-SDF name matches what the caller EXPECTED (--expect-sdf).
       This is the check that catches the D5-specific mistake nothing else
       would: pointing the dbgon gate leg at MCU_MP.genus.sdf (the debug-OFF
       netlist's SDF) instead of MCU_MP.genus.dbgon.sdf.  The two files differ
       by 13 MB and by whether a TAP exists at all, and the run would look
       entirely healthy.
    4. -sdfstats wrote a non-empty statistics file.  Xcelium writes it only
       when the annotator ran; no annotation, no file.

WHAT IT DELIBERATELY DOES NOT DO
    It does not count annotations, because Xcelium does not report a count and
    a fabricated one would be a decorative metric (method rule 9).  The SDFNET
    warning lines are reported as an OBSERVATION with their source file path,
    never as a pass/fail.

EXIT CODES -- never a silent skip:
    0  LIVE
    1  NOT LIVE (a named, quoted reason)
    2  CANNOT EVALUATE (an input is missing; says which)

SELF-VALIDATION AGAINST A KNOWN NONZERO (method rule 4)
    --control <dir> points the same code at an artifact set already on disk
    that is known to have annotated -- the shipped
    xcelium/riscv_test/genus_mp/log/ -- and requires it to come out LIVE.  A
    checker that has only ever been run against the thing it is checking has
    not been checked.
"""

import os
import re
import sys
import time

BANNER = "Annotating SDF timing data:"


def _fail(code, msg, extra=()):
    tag = {1: "NOT-LIVE", 2: "CANNOT-EVALUATE"}[code]
    print("D5SDF %s: %s" % (tag, msg))
    for e in extra:
        print("D5SDF   %s" % e)
    return code


def check(logdir, expect_sdf=None, newer_than=None, quiet=False):
    """Return (rc, info-dict). Prints its own reasoning."""
    sdflog = os.path.join(logdir, "sdf.log")
    stats = os.path.join(logdir, "sdf_stats.log")

    if not os.path.isdir(logdir):
        return _fail(2, "no such log directory: %s" % logdir), {}
    if not os.path.isfile(sdflog):
        return _fail(2, "no sdf.log in %s -- the runner's .sdfcmd LOG_FILE must "
                        "point here, and a run that produced none did not annotate"
                        % logdir), {}
    if os.path.getsize(sdflog) == 0:
        return _fail(1, "%s is EMPTY -- the annotator produced no banner at all" % sdflog), {}

    with open(sdflog, "r", errors="replace") as f:
        head = [next(f, "") for _ in range(40)]
        f.seek(0)
        body = f.read()

    headtxt = "".join(head)
    if BANNER not in headtxt:
        return _fail(1, "%s does not carry the annotator's banner %r" % (sdflog, BANNER),
                     ["first line: %r" % (head[0].rstrip() if head else "")]), {}

    def field(name):
        m = re.search(r"^\s*%s\s*(.*)$" % re.escape(name), headtxt, re.M)
        return m.group(1).strip() if m else None

    compiled = field("Compiled SDF file:")
    scope = field("Backannotation scope:")
    mtm = field("MTM control:")
    if compiled is None or scope is None or mtm is None:
        return _fail(1, "%s has the banner but not the header triple "
                        "(Compiled SDF file / Backannotation scope / MTM control)" % sdflog,
                     ["compiled=%r scope=%r mtm=%r" % (compiled, scope, mtm)]), {}

    info = {"sdflog": sdflog, "compiled": compiled, "scope": scope, "mtm": mtm,
            "mtime": time.strftime("%Y-%m-%d %H:%M:%S",
                                   time.localtime(os.path.getmtime(sdflog)))}

    # The SDF the annotator really read, quoted from the warnings' own file
    # references.  This is stronger than the header, because the header names
    # the COMPILED image while the warnings name the SOURCE path.
    srcs = sorted(set(re.findall(r"<([^<>,]+\.sdf), line \d+>", body)))
    info["sources"] = srcs
    nwarn = body.count("*W,SDFNET")
    info["sdfnet_warnings"] = nwarn

    if expect_sdf:
        base = os.path.basename(expect_sdf)
        hit_hdr = base.split(".sdf")[0] in compiled
        hit_src = any(os.path.basename(s) == base for s in srcs)
        if not (hit_hdr or hit_src):
            return _fail(1, "the annotated SDF is NOT the one this leg claims",
                         ["expected basename : %s" % base,
                          "header compiled   : %s" % compiled,
                          "source paths seen : %s" % (", ".join(srcs) or "(none)"),
                          "This is the failure a pre-flight guard cannot see: the run",
                          "is healthy, the timing is real, and it is the WRONG cut."]), info

    if newer_than:
        if not os.path.exists(newer_than):
            return _fail(2, "--newer-than target does not exist: %s" % newer_than), info
        if os.path.getmtime(sdflog) < os.path.getmtime(newer_than):
            return _fail(1, "sdf.log is OLDER than %s -- this is a STALE artifact and a "
                            "stale artifact parses cleanly (method rule 6)" % newer_than,
                         ["sdf.log      %s" % info["mtime"],
                          "reference    %s" % time.strftime(
                              "%Y-%m-%d %H:%M:%S",
                              time.localtime(os.path.getmtime(newer_than)))]), info

    if not os.path.isfile(stats) or os.path.getsize(stats) == 0:
        return _fail(1, "no non-empty sdf_stats.log in %s -- Xcelium writes it only when "
                        "the annotator ran, so its absence is the positive evidence "
                        "missing" % logdir,
                     ["add `-sdfstats log/sdf_stats.log` to the runner"]), info

    if not quiet:
        print("D5SDF LIVE")
        print("D5SDF   sdf.log        : %s  (%s)" % (sdflog, info["mtime"]))
        print("D5SDF   compiled SDF   : %s" % compiled)
        print("D5SDF   source SDF(s)  : %s" % (", ".join(srcs) or "(none quoted in warnings)"))
        print("D5SDF   scope          : %s" % scope)
        print("D5SDF   MTM control    : %s" % mtm)
        print("D5SDF   sdf_stats.log  : %d bytes" % os.path.getsize(stats))
        print("D5SDF   OBSERVATION    : %d *W,SDFNET line(s) -- reported, never graded" % nwarn)
    return 0, info


def main(argv):
    logdir = None
    expect = None
    newer = None
    control = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--expect-sdf":
            i += 1; expect = argv[i]
        elif a == "--newer-than":
            i += 1; newer = argv[i]
        elif a == "--control":
            i += 1; control = argv[i]
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            logdir = a
        i += 1

    if control:
        print("D5SDF ---- KNOWN-NONZERO CONTROL (method rule 4) ----")
        print("D5SDF   Running the same code against an artifact set already known to")
        print("D5SDF   have annotated.  If this does not come out LIVE, no verdict")
        print("D5SDF   below is worth reading.")
        rc, _ = check(control)
        if rc != 0:
            print("D5SDF CONTROL FAILED -- the checker cannot recognise a live annotation.")
            return 2
        print("D5SDF CONTROL OK\n")

    if logdir is None:
        print("usage: d5_sdf_live.py <logdir> [--expect-sdf <path>] "
              "[--newer-than <path>] [--control <logdir>]")
        return 2
    rc, _ = check(logdir, expect, newer)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
