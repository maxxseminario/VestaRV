#!/usr/bin/env python3
"""VestaRV: the gate that keeps a new RTL file from dodging synthesis.

Every entity under hdl/common/ minus the documented exclusions must be a ghdl_synth_test top
(a documented SKIP counts) or a module row in a census. Module names are `<entity>` at the top
and `<entity>_B<architecture>` below, split on the capital B, compared case-insensitively. An
architecture named `blackbox` is not coverage; an exclusion matching no file is an error.
"""

import argparse
import fnmatch
import json
import os
import re
import sys

# THE EXCLUSION LIST.  Every entry says what it covers and why that is not a
# hole in the gate.  Patterns are fnmatch over the workspace-relative path, so
# a trailing "*" reaches into subdirectories too.

EXCLUSIONS = [
    (
        "hdl/common/tb/*",
        "testbenches and the device models they drive.  Not silicon, and "
        "half of them are deliberately unsynthesizable (file I/O, `wait "
        "for`, transport delays).  Graded by //hdl/common/tb, behaviourally.",
    ),
    (
        "hdl/common/sim/*",
        "behavioural stand-ins for cells that are not RTL in the physical "
        "flow: the compiled memory macros (ARM_IP_RAM/ARM_IP_ROM, which the "
        ".gitignore `*ARM*` pattern hides, so they are absent from a fresh "
        "clone), the analog oscillator / POR / glitch filter, and the "
        "technology clock cells.  Genus reads the real versions from timing "
        "libraries and elaborates them as blackboxes "
        "(genus/MCU_WOUND/tcl/MCU_WOUND_hier.genus.tcl:163).  ClkGate, "
        "ClockMuxGlitchFree and PreICG are nevertheless graded here, "
        "transitively, through every peripheral that gates a clock -- they "
        "are the modules on the allow_latches list.",
    ),
    (
        "hdl/common/commune/*",
        "vendor and technology HDL this project does not own: the ARM clock "
        "cell wrappers and macro models, the VHDL-2008 fixed-point packages, "
        "and the arithmetic and CDC cells that came with them.  The ones the "
        "chip actually instantiates are graded transitively -- CRC16 through "
        "DMA, FPMac and FPSigmoid through NPU, ClkDivPower2 and TieLow "
        "through MCU.",
    ),
    (
        "hdl/common/periph/TrngRoEnsemble_sim.vhd",
        "the `sim` architecture of an entity whose `rtl` architecture IS "
        "graded (//hdl/common/synth:TrngRoEnsemble).  Its own header forbids "
        "co-listing the two files, because the real ring ensemble's "
        "combinational feedback delta-loops a behavioural simulator.",
    ),
    (
        "hdl/common/vesta/regfile.vhd",
        "one of THREE files declaring entity `regfile`, of which only "
        "regfile_sbirq.vhd is correct -- the reason vhdl_source_set exists "
        "(toolchains/ghdl/defs.bzl module docstring).  The graded `regfile` "
        "is regfile_sbirq's, through vesta.",
    ),
    (
        "hdl/common/vesta/regfile_firq.vhd",
        "the second superseded `regfile`; see regfile.vhd above.",
    ),
    (
        "hdl/common/vesta/vesta_tracer.vhd",
        "a simulation-only retire-trace observer: no output ports, std.textio "
        "its only interface.  vesta.vhd instantiates it inside `if "
        "TRACE_ENABLE generate`, false in every build, and leaves it a "
        "COMPONENT precisely so a non-tracing flow need not carry the file.",
    ),
]

# hdl/common/synth/ holds this package's own synthesis-only VHDL (the black
# boxes and the afe_stub width wrapper).  It needs no exclusion entry: that
# directory is a bazel package, and //hdl:vhdl_sources is a glob rooted at
# hdl/ which does not descend into a subpackage, so its files never reach the
# source manifest this gate reads.

ROOT = "hdl/common/"

# VHDL parsing
#
# Comments must go first, and BOTH kinds: this tree uses VHDL-2008 /* */ block
# comments heavily for its file headers, and several of them quote entity
# declarations in prose.

_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
_LINE_COMMENT = re.compile(r"--[^\n]*")
_ENTITY_DECL = re.compile(r"(?<![\w.])entity\s+([A-Za-z]\w*)\s+is\b", re.I)


def entities_in(path):
    """Every entity declared in one VHDL file, in declaration order. An `entity work.foo`
    instantiation does not match, having no `is`, and `end entity foo;` does not match for the
    same reason.
    """
    try:
        text = open(path, "r", errors="replace").read()
    except IOError as exc:
        sys.stderr.write("ERROR: cannot read %s: %s\n" % (path, exc))
        return None
    text = _BLOCK_COMMENT.sub(" ", text)
    text = _LINE_COMMENT.sub(" ", text)
    return [m.group(1) for m in _ENTITY_DECL.finditer(text)]


# Census reading

_MODULE_SPLIT = re.compile(r"^(.+?)_B(.*)$")


def module_entity(module):
    """(entity, architecture) for a GHDL synthesis module name.

    A top module carries no "_B" suffix and is the entity name as written.
    """
    match = _MODULE_SPLIT.match(module)
    if match:
        return match.group(1), match.group(2)
    return module, ""


def covered_from_censuses(paths):
    """Entity names, lowercased, that the censuses prove were synthesized."""
    covered = {}
    for path in paths:
        census = json.load(open(path))
        target = census.get("target") or census.get("entity")
        entity = census.get("entity", "")
        if entity:
            covered.setdefault(entity.lower(), set()).add(target)
        for row in census.get("modules", []):
            name, arch = module_entity(row["module"])
            # A black box is a port-compatible stand-in, not a graded design.
            if arch.split("_")[0].lower() == "blackbox":
                continue
            covered.setdefault(name.lower(), set()).add(target)
    return covered


# Runfiles resolution, same shape as synth_census.py's

def runfiles_root():
    for var in ("RUNFILES_DIR", "TEST_SRCDIR"):
        base = os.environ.get(var)
        if base:
            return base
    guess = os.path.abspath(sys.argv[0]) + ".runfiles"
    if os.path.isdir(guess):
        return guess
    return None


def data_path(rel):
    if os.path.exists(rel):
        return rel
    root = runfiles_root()
    if root:
        for candidate in (os.path.join(root, "_main", rel),
                          os.path.join(root, rel)):
            if os.path.exists(candidate):
                return candidate
    return rel


def read_manifest(path):
    out = []
    handle = open(data_path(path))
    try:
        for line in handle:
            text = line.strip()
            if text:
                out.append(text)
    finally:
        handle.close()
    return out


def workspace_relative(path):
    """Strip a runfiles or bazel-out prefix off a manifest entry. A source file's entry is already
    workspace relative; the prefix handling is here so the same gate runs unchanged under
    `bazel run`.
    """
    marker = ROOT
    index = path.find(marker)
    if index >= 0:
        return path[index:]
    return path


# main

def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sources-from", required=True,
                        help="file holding one VHDL source path per line")
    parser.add_argument("--census-from", required=True,
                        help="file holding one census JSON path per line")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    source_paths = read_manifest(args.sources_from)
    census_paths = [data_path(p) for p in read_manifest(args.census_from)]
    if not census_paths:
        sys.stderr.write("ERROR: the census manifest is empty.\n")
        return 2

    # Only hdl/common/ is in scope.  hdl/argus/ and hdl/myshkin/ are frozen
    # do-not-touch trees, and hdl/ has no other RTL of its own.
    in_scope = []
    for path in source_paths:
        rel = workspace_relative(path)
        if rel.startswith(ROOT):
            in_scope.append((rel, path))
    if not in_scope:
        sys.stderr.write(
            "ERROR: no VHDL source under %s reached this gate, so it would\n"
            "       pass by scanning nothing.  Check the source manifest.\n"
            % ROOT)
        return 2

    used_exclusions = set()
    graded = []
    for rel, path in sorted(set(in_scope)):
        hit = None
        for pattern, _reason in EXCLUSIONS:
            if fnmatch.fnmatch(rel, pattern):
                hit = pattern
                break
        if hit:
            used_exclusions.add(hit)
            continue
        names = entities_in(path)
        if names is None:
            return 2
        for name in names:
            graded.append((rel, name))

    covered = covered_from_censuses(census_paths)

    failures = []
    for rel, name in graded:
        if name.lower() not in covered:
            failures.append(
                "%s: entity %s is synthesized by nothing.\n"
                "    Give it a ghdl_synth_test in hdl/common/synth/BUILD.bazel,\n"
                "    instantiate it inside a block that already has one, or add\n"
                "    it to EXCLUSIONS in toolchains/ghdl/synth_coverage.py with\n"
                "    the reason." % (rel, name))

    for pattern, _reason in EXCLUSIONS:
        if pattern not in used_exclusions:
            failures.append(
                "exclusion %r matches no file under %s any more.  A licence to\n"
                "    skip must not outlive the file it was written for: delete\n"
                "    the entry, or fix the pattern." % (pattern, ROOT))

    if failures:
        print("FAIL: the synthesis gate does not cover all of %s." % ROOT)
        for line in failures:
            print("  %s" % line)
        return 1

    if args.verbose:
        for rel, name in graded:
            print("  %-52s %-22s <- %s"
                  % (rel, name, ", ".join(sorted(covered[name.lower()]))))
    print("OK: %d entities in %d files under %s, all synthesized; "
          "%d documented exclusions."
          % (len(graded), len(set(r for r, _ in graded)), ROOT,
             len(EXCLUSIONS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
