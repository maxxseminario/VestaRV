#!/usr/bin/python3.6
"""VestaRV: prove that an SDF back-annotation actually happened.

The runners' pre-flight guard only shows the .sdfcmd resolves; this reads the post-run half:
sdf.log non-empty and newer than the netlist, its banner/compiled-SDF/scope/MTM lines present,
the compiled-SDF name equal to --expect-sdf, a non-empty -sdfstats file. --control <dir> runs
the same code against a known-live set. Exit 0 live, 1 not live, 2 cannot evaluate.
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
