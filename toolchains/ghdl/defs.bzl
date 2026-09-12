"""GHDL rules for the open-source simulation tier.

Three rules:

  vhdl_source_set  pick an ORDERED subset of VHDL files out of a filegroup
  ghdl_library     analyze an ordered source list into a GHDL work library
  ghdl_test        analyze the same list and run one elaboration as a test

Why the source list is ordered and why it is a subset, not a glob: the vesta
tree contains three conflicting `regfile` entities, of which only
regfile_sbirq.vhd is correct, and two `ClkGate` entities, of which only the
hdl/common/sim one is a real behavioural model. Analysis order is also load
bearing. The curated list lives in opensource_sim/isa/run_isa.sh and must stay
in sync with sky130/synth.sh and sky130/sim/Makefile.

MEASURED FACT that shapes these rules: a GHDL work library is NOT relocatable.
`ghdl -a` records, per design unit, the absolute directory the analysis ran in
plus the source path relative to it, and the mcode backend re-reads those
sources at `ghdl -r` time because it has no separate elaboration step.
Copying a --workdir tree to another exec root and running there fails with
'cannot load entity' as soon as the original analysis directory is gone.
So ghdl_test does its own analysis; it does NOT consume a ghdl_library.
Analysis of the whole 22-file vesta core measures at about 0.07 s, so there is
nothing to gain by sharing it anyway.
"""

VhdlSourceSetInfo = provider(
    doc = "An ordered list of VHDL source files for GHDL analysis.",
    fields = {
        "ordered": "list[File] in analysis order",
    },
)

_STD_DEFAULT = "08"

# -fsynopsys is required by the vesta tree: several units use the Synopsys
# std_logic_arith / std_logic_unsigned packages.
_FLAGS_DEFAULT = ["-fsynopsys"]

def _lib_root(lib_files, std, runfiles):
    """Return the directory to hand GHDL's -P flag.

    GHDL's -P wants the directory that CONTAINS std/vXX/ and ieee/vXX/, so we
    find the compiled std library index and strip that tail off. Build actions
    resolve paths against the exec root (File.path); a test binary resolves
    them against its runfiles root (File.short_path).
    """
    marker = "/std/v%s/std-obj%s.cf" % (std, std)
    for f in lib_files:
        p = f.short_path if runfiles else f.path
        if p.endswith(marker):
            return p[:-len(marker)]
    return None

def _quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

# ---------------------------------------------------------------------------
# vhdl_source_set
# ---------------------------------------------------------------------------

def _vhdl_source_set_impl(ctx):
    by_path = {}
    for f in ctx.files.pool:
        by_path[f.short_path] = f

    ordered = []
    missing = []
    for p in ctx.attr.paths:
        f = by_path.get(p)
        if f == None:
            missing.append(p)
        else:
            ordered.append(f)

    if missing:
        fail("vhdl_source_set %s: these paths are not in `pool`: %s" %
             (ctx.label, missing))

    return [
        DefaultInfo(files = depset(ordered)),
        VhdlSourceSetInfo(ordered = ordered),
    ]

vhdl_source_set = rule(
    doc = """Select an ordered subset of a VHDL filegroup.

The vesta RTL lives in the //hdl package, whose individual source files are
not exported, so the only handle available to another package is the public
//hdl:vhdl_sources filegroup. This rule takes that filegroup as `pool` and a
list of workspace-relative paths as `paths`, and yields exactly those files in
exactly that order. An unmatched path is a hard error, which is what keeps a
renamed or deleted RTL file from silently dropping out of the analysis list.

If //hdl ever gains exports_files for its sources, ghdl_library / ghdl_test
also accept a plain ordered label_list and this rule can go away.
""",
    implementation = _vhdl_source_set_impl,
    attrs = {
        "paths": attr.string_list(
            mandatory = True,
            doc = "Workspace-relative paths, in analysis order.",
        ),
        "pool": attr.label_list(
            mandatory = True,
            allow_files = [".vhd", ".vhdl"],
            doc = "Filegroups to pick from, e.g. //hdl:vhdl_sources.",
        ),
    },
)

# ---------------------------------------------------------------------------
# Shared source resolution for ghdl_library / ghdl_test
# ---------------------------------------------------------------------------

def _resolve_srcs(ctx):
    """Ordered analysis list: source sets expand in place, files stay in order."""
    out = []
    for t in ctx.attr.srcs:
        if VhdlSourceSetInfo in t:
            out.extend(t[VhdlSourceSetInfo].ordered)
        else:
            out.extend(t[DefaultInfo].files.to_list())
    return out

# ---------------------------------------------------------------------------
# ghdl_library
# ---------------------------------------------------------------------------

def _ghdl_library_impl(ctx):
    srcs = _resolve_srcs(ctx)
    lib_files = ctx.files.vhdl_libs
    lib_root = _lib_root(lib_files, ctx.attr.std, runfiles = False)
    if lib_root == None:
        fail("ghdl_library %s: no std-obj%s.cf in vhdl_libs" % (ctx.label, ctx.attr.std))

    workdir = ctx.actions.declare_directory(ctx.label.name + ".work")

    args = ctx.actions.args()
    args.add("-a")
    args.add("--std=" + ctx.attr.std)
    args.add_all(ctx.attr.flags)
    args.add("-P" + lib_root)
    args.add(workdir.path, format = "--workdir=%s")
    args.add_all(srcs)

    ctx.actions.run(
        executable = ctx.executable.ghdl,
        arguments = [args],
        inputs = depset(srcs + lib_files),
        outputs = [workdir],
        mnemonic = "GhdlAnalyze",
        progress_message = "Analyzing %d VHDL files for %s" % (len(srcs), ctx.label),
    )

    return [DefaultInfo(files = depset([workdir]))]

ghdl_library = rule(
    doc = """Analyze an ordered VHDL source list into a GHDL work library.

The output is the --workdir tree. Treat it as a BUILD-TIME ANALYSIS CHECK: it
proves the curated source list parses and elaborates its bindings under
--std=08 -fsynopsys, and it fails the build the moment an RTL edit breaks
that. It is deliberately NOT an input to ghdl_test, because a GHDL work
library is not relocatable across exec roots (see the module docstring).
""",
    implementation = _ghdl_library_impl,
    attrs = {
        "flags": attr.string_list(
            default = _FLAGS_DEFAULT,
            doc = "Extra GHDL flags applied to analysis.",
        ),
        "ghdl": attr.label(
            default = "@ghdl//:ghdl_mcode",
            executable = True,
            cfg = "exec",
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".vhd", ".vhdl"],
            doc = "vhdl_source_set targets or plain files, in analysis order.",
        ),
        "std": attr.string(default = _STD_DEFAULT),
        "vhdl_libs": attr.label(
            default = "@ghdl//:vhdl_libs_v08",
            doc = "Compiled GHDL std/ieee libraries for `std`.",
        ),
    },
)

# ---------------------------------------------------------------------------
# ghdl_test
# ---------------------------------------------------------------------------

_TEST_TEMPLATE = """#!/bin/bash
# Generated by //toolchains/ghdl:defs.bzl -- do not edit.
set -uo pipefail

GHDL={ghdl}
LIBROOT={lib_root}
WORK="${{TEST_TMPDIR:-/tmp}}/ghdl_work"
rm -rf "$WORK"; mkdir -p "$WORK"

# Analysis and run must share one --workdir, and the run has to happen from
# the same directory the analysis ran in: GHDL stores the analysis directory
# in the library index and the mcode backend re-reads the sources at run time.
"$GHDL" -a --std={std} {flags} "-P$LIBROOT" "--workdir=$WORK" {srcs} \
    > "$WORK/analyze.log" 2>&1
arc=$?
if [ "$arc" -ne 0 ]; then
    echo "FAIL {name}: ghdl analysis failed (exit $arc)"
    cat "$WORK/analyze.log"
    exit 1
fi

timeout {timeout_s} "$GHDL" -r --std={std} {flags} "-P$LIBROOT" "--workdir=$WORK" \
    {entity} {generics} {run_options} > "$WORK/run.log" 2>&1
rc=$?

# The run log is the only record of what a bench actually PRINTED, and for a
# multi-minute sim that is worth keeping whatever the verdict. bazel collects
# this directory into bazel-testlogs/<target>/test.outputs/, or into
# outputs.zip beside it when --zip_undeclared_test_outputs is on.
if [ -n "${{TEST_UNDECLARED_OUTPUTS_DIR:-}}" ]; then
    mkdir -p "$TEST_UNDECLARED_OUTPUTS_DIR"
    cp "$WORK/analyze.log" "$WORK/run.log" "$TEST_UNDECLARED_OUTPUTS_DIR/" 2>/dev/null || true
fi

if [ "$rc" -eq 124 ]; then
    echo "FAIL {name}: wall-clock timeout after {timeout_s}s"
    tail -40 "$WORK/run.log"
    exit 1
fi
if [ "$rc" -ne 0 ]; then
    reason="ghdl exit $rc"
    if grep -q "TEST TIMED OUT" "$WORK/run.log"; then reason="sim watchdog timeout"; fi
    echo "FAIL {name}: $reason"
    tail -40 "$WORK/run.log"
    exit 1
fi
{pass_check}
echo "PASS {name}"
exit 0
"""

# A bench that states its verdict through pass_pattern rather than the exit
# code has usually ALREADY said which check failed, hundreds of lines above the
# end of the log, so tail alone can miss it. The error grep is what makes the
# red result name the failing check instead of just the missing banner.
_PASS_PATTERN_CHECK = """
if grep -q {pattern} "$WORK/run.log"; then
    echo "{name}: $(grep -m 1 {pattern} "$WORK/run.log")"
else
    echo "FAIL {name}: ghdl exited 0 but the pass banner {pattern} is absent"
    errs="$(grep -in -m 20 error "$WORK/run.log" || true)"
    if [ -n "$errs" ]; then
        echo "--- lines reporting an error ---"
        echo "$errs"
        echo "--- end of run log ---"
    fi
    tail -40 "$WORK/run.log"
    exit 1
fi
"""

def _ghdl_test_impl(ctx):
    srcs = _resolve_srcs(ctx)
    lib_files = ctx.files.vhdl_libs
    lib_root = _lib_root(lib_files, ctx.attr.std, runfiles = True)
    if lib_root == None:
        fail("ghdl_test %s: no std-obj%s.cf in vhdl_libs" % (ctx.label, ctx.attr.std))

    generics = []
    for k, v in ctx.attr.generics.items():
        generics.append("-g%s=%s" % (k, v))
    image_files = []
    if ctx.attr.image:
        image = ctx.file.image
        image_files = [image]
        generics.append("-g%s=%s" % (ctx.attr.image_generic, image.short_path))

    # GHDL run options go AFTER the top-level unit name, unlike the analysis
    # flags. --stop-time bounds a design that has no self-terminating stimulus
    # of its own, which is what an elaboration-and-asserts check is.
    run_options = []
    if ctx.attr.stop_time:
        run_options.append("--stop-time=" + ctx.attr.stop_time)
    run_options.extend(ctx.attr.run_options)

    pass_check = ""
    if ctx.attr.pass_pattern:
        pass_check = _PASS_PATTERN_CHECK.format(
            name = ctx.label.name,
            pattern = _quote(ctx.attr.pass_pattern),
        )

    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = script,
        is_executable = True,
        content = _TEST_TEMPLATE.format(
            ghdl = _quote(ctx.executable.ghdl.short_path),
            lib_root = _quote(lib_root),
            std = ctx.attr.std,
            flags = " ".join([_quote(f) for f in ctx.attr.flags]),
            srcs = " ".join([_quote(f.short_path) for f in srcs]),
            entity = _quote(ctx.attr.entity),
            generics = " ".join([_quote(g) for g in generics]),
            run_options = " ".join([_quote(o) for o in run_options]),
            timeout_s = str(ctx.attr.sim_timeout_s),
            name = ctx.label.name,
            pass_check = pass_check,
        ),
    )

    runfiles = ctx.runfiles(
        files = [ctx.executable.ghdl] + srcs + lib_files + image_files +
                ctx.files.data,
    )
    runfiles = runfiles.merge(ctx.attr.ghdl[DefaultInfo].default_runfiles)

    return [DefaultInfo(executable = script, runfiles = runfiles)]

ghdl_test = rule(
    doc = """Analyze an ordered VHDL source list and run one GHDL simulation.

Analysis and run are one test action on purpose. The mcode backend has no
separate elaboration step, and vesta_isa_tb loads its RAM image through a
signal initializer that runs AT elaboration, so every image needs its own
elaboration with a real -gTEST_FILE.

Verdict: the GHDL exit code, plus an optional `pass_pattern` that must appear
in the run log. A wall-clock `timeout` guards the a0-sentinel testbenches,
whose failure mode for an unmet cross-hart or peripheral dependency is to spin
rather than to report.
""",
    implementation = _ghdl_test_impl,
    attrs = {
        "data": attr.label_list(
            allow_files = True,
            doc = "Runtime files placed in the test's runfiles and NOT named " +
                  "on any GHDL command line. A VHDL model that opens a file " +
                  "by a path it holds internally reaches it this way; the " +
                  "path is runfiles relative, which is what the test's " +
                  "working directory is.",
        ),
        "entity": attr.string(
            mandatory = True,
            doc = "Top-level entity to elaborate and run.",
        ),
        "flags": attr.string_list(default = _FLAGS_DEFAULT),
        "generics": attr.string_dict(
            doc = "Extra -g<name>=<value> generic overrides.",
        ),
        "ghdl": attr.label(
            default = "@ghdl//:ghdl_mcode",
            executable = True,
            cfg = "target",
        ),
        "image": attr.label(
            allow_single_file = True,
            doc = "Optional data file passed as a generic holding its path.",
        ),
        "image_generic": attr.string(
            default = "TEST_FILE",
            doc = "Generic name that receives the `image` path.",
        ),
        "pass_pattern": attr.string(
            doc = "If set, this fixed string must appear in the run log.",
        ),
        "run_options": attr.string_list(
            doc = "Extra GHDL run options, placed after the top-level unit " +
                  "name alongside --stop-time. --assert-level=failure lives " +
                  "here: a testbench whose end-of-run marker is a `severity " +
                  "error` report would otherwise make GHDL exit non-zero on " +
                  "a passing run, and such a bench must state its verdict " +
                  "through pass_pattern instead of the exit code.",
        ),
        "sim_timeout_s": attr.int(
            default = 90,
            doc = "Wall-clock cap on the ghdl -r step, matching run_isa.sh.",
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".vhd", ".vhdl"],
            doc = "vhdl_source_set targets or plain files, in analysis order.",
        ),
        "std": attr.string(default = _STD_DEFAULT),
        "stop_time": attr.string(
            doc = "If set, a GHDL --stop-time value such as \"1ns\". Required " +
                  "for a top level with no stimulus of its own, whose whole " +
                  "verdict is elaboration plus the concurrent asserts that " +
                  "execute once at time zero, and for a bench that runs to a " +
                  "verdict but never stops itself. Set the stop time HERE, " +
                  "not in run_options, so there is one place to look for it.",
        ),
        "vhdl_libs": attr.label(default = "@ghdl//:vhdl_libs_v08"),
    },
    test = True,
)

# ---------------------------------------------------------------------------
# ghdl_synth_test
# ---------------------------------------------------------------------------
#
# The synthesizability gate.  ghdl_test proves a block BEHAVES; this proves it
# is still hardware.  `ghdl --synth` refuses a `wait` in a process, an
# incomplete `if` that infers a latch, and a constant index outside its array
# bound -- the three mistakes that used to reach Genus, which needs a license,
# takes minutes, and does not run on every commit.  Synthesis of the largest
# block here (NFC) measures at 1.9 s.
#
# TWO ARTIFACTS, ONE BUILD ACTION.  The action analyzes, synthesizes to a raw
# netlist, and writes a JSON census; the test reads the census and decides.
# The action exits 0 even when GHDL fails, recording status="error" plus the
# log, so a broken design gives a RED TEST with the diagnostics attached
# rather than a build error with nothing kept.  The census is also exposed in
# the "census" output group, which is how //toolchains/ghdl:synth_census_test
# reads every block's counts without re-running anything.
#
# THE LATCH POLICY.  GHDL 6.0.0 has no --latches=off: `--latches` is an opt-in
# that ALLOWS latches, and the default already errors on one, naming the net.
# Three clock cells in this tree contain a latch on purpose (ClkGate's
# ClkSync, PreICG, ClockMuxGlitchFree), and without --latches every peripheral
# that gates a clock would be ungradeable.  So the action always passes
# --latches and the policy moves into the census: a latch is FATAL unless the
# module holding it matches an `allow_latches` pattern.  That is equivalent to
# the default for a block with an empty allowlist and strictly stronger for
# one with a clock gate, because the frozen census also pins WHICH modules
# hold latches and HOW MANY bits.
#
# Patterns match GHDL's synthesis module name, "<entity>_B<architecture>"
# lowercased with a generic/hash suffix, so they are written as globs:
# "clkgate_B*", not "clkgate_Bbehavioral".

def _synth_action(ctx, srcs, lib_root, netlist, census, log):
    args = ctx.actions.args()
    args.add("run")
    args.add("--ghdl", ctx.executable.ghdl.path)
    args.add("--lib-root", lib_root)
    args.add("--std", ctx.attr.std)
    args.add_all(ctx.attr.flags, format_each = "--flag=%s")
    args.add_all(srcs, format_each = "--src=%s")
    for k, v in ctx.attr.generics.items():
        args.add("--generic", "%s=%s" % (k, v))
    args.add_all(ctx.attr.allow_latches, format_each = "--allow-latch=%s")
    args.add("--entity", ctx.attr.entity)
    args.add("--target", ctx.label.name)
    args.add("--netlist", netlist.path)
    args.add("--census", census.path)
    args.add("--log", log.path)

    ctx.actions.run(
        executable = ctx.executable._census_tool,
        arguments = [args],
        inputs = depset(srcs + ctx.files.vhdl_libs),
        outputs = [netlist, census, log],
        tools = [ctx.attr.ghdl[DefaultInfo].files_to_run],
        mnemonic = "GhdlSynth",
        progress_message = "Synthesizing %s for %s" % (ctx.attr.entity, ctx.label),
    )

_SYNTH_TEST_TEMPLATE = """#!/bin/bash
# Generated by //toolchains/ghdl:defs.bzl -- do not edit.
set -uo pipefail

# The netlist, the census and the GHDL log are kept whatever the verdict: on a
# red run they are the evidence, and on a green one the netlist is the only
# place the per-module rollup can be re-derived from.
if [ -n "${{TEST_UNDECLARED_OUTPUTS_DIR:-}}" ]; then
    mkdir -p "$TEST_UNDECLARED_OUTPUTS_DIR"
    cp {census} {log} "$TEST_UNDECLARED_OUTPUTS_DIR/" 2>/dev/null || true
    if [ -s {netlist} ]; then
        gzip -c {netlist} > "$TEST_UNDECLARED_OUTPUTS_DIR/{name}.netlist.raw.gz" 2>/dev/null || true
    fi
fi

exec {tool} gate --census {census} --log {log}
"""

def _ghdl_synth_test_impl(ctx):
    netlist = ctx.actions.declare_file(ctx.label.name + ".netlist.raw")
    census = ctx.actions.declare_file(ctx.label.name + ".census.json")
    log = ctx.actions.declare_file(ctx.label.name + ".synth.log")

    if ctx.attr.skip_reason:
        # A documented skip is still a target, still in the suite, and still in
        # the frozen census -- what is frozen is the REASON, so deleting the
        # reason without deleting the skip fails //toolchains/ghdl:synth_census_test.
        ctx.actions.write(netlist, "")
        ctx.actions.write(log, "skipped: " + ctx.attr.skip_reason + "\n")
        ctx.actions.write(census, json.encode_indent(struct(
            entity = ctx.attr.entity,
            target = ctx.label.name,
            status = "skipped",
            skip_reason = ctx.attr.skip_reason,
        )) + "\n")
    else:
        srcs = _resolve_srcs(ctx)
        lib_root = _lib_root(ctx.files.vhdl_libs, ctx.attr.std, runfiles = False)
        if lib_root == None:
            fail("ghdl_synth_test %s: no std-obj%s.cf in vhdl_libs" %
                 (ctx.label, ctx.attr.std))
        _synth_action(ctx, srcs, lib_root, netlist, census, log)

    script = ctx.actions.declare_file(ctx.label.name + ".synth.sh")
    ctx.actions.write(
        output = script,
        is_executable = True,
        content = _SYNTH_TEST_TEMPLATE.format(
            tool = _quote(ctx.executable._census_gate.short_path),
            census = _quote(census.short_path),
            log = _quote(log.short_path),
            netlist = _quote(netlist.short_path),
            name = ctx.label.name,
        ),
    )

    runfiles = ctx.runfiles(
        files = [census, log, netlist, ctx.executable._census_gate],
    )
    runfiles = runfiles.merge(
        ctx.attr._census_gate[DefaultInfo].default_runfiles,
    )

    return [
        DefaultInfo(executable = script, runfiles = runfiles),
        OutputGroupInfo(census = depset([census])),
    ]

ghdl_synth_test = rule(
    doc = """Synthesize one entity with `ghdl --synth` and census the result.

FAILS ON: any GHDL error, an internal GHDL exception, a `-Wruntime-error`
(a constant index outside its array bound, which GHDL folds to X and Genus
does not), a `-Wnowrite` naming a PORT (a dangling output), and any inferred
latch in a module outside `allow_latches`.

DOES NOT FAIL ON: `-Wbinding` (vesta.vhd instantiates vesta_tracer inside a
`if TRACE_ENABLE generate` that is false in every build, and GHDL warns before
discarding it), `-Wunhandled-attribute` (sync.vhd's DONT_TOUCH / ASYNC_REG are
for the downstream synthesizer), `-Wopen-assoc` (the -frelaxed waiver the
benches already carry), `-Wnowrite` on an internal signal slice (periph_regs
leaves whole mask words unwritten for registers a block does not implement),
and `-Whide`.  The full list, with the reason on each line, is at the top of
toolchains/ghdl/synth_census.py.

Outputs, all three kept in bazel-testlogs/<target>/test.outputs/: the raw
netlist (gzipped), the census JSON, and the GHDL log.
""",
    implementation = _ghdl_synth_test_impl,
    attrs = {
        "allow_latches": attr.string_list(
            doc = "fnmatch patterns over GHDL module names (\"<entity>_B<arch>\" " +
                  "plus a generic suffix, lowercased) whose inferred latches " +
                  "are intended.  A latch anywhere else is fatal.  The only " +
                  "legitimate entries in this tree are the clock cells: " +
                  "\"clkgate_B*\", \"preicg_B*\", \"clockmuxglitchfree_B*\".",
        ),
        "entity": attr.string(
            mandatory = True,
            doc = "Top-level entity to synthesize.",
        ),
        "flags": attr.string_list(
            default = ["-fsynopsys", "-frelaxed"],
            doc = "Analysis flags, matching what the benches use.",
        ),
        "generics": attr.string_dict(
            doc = "-g<name>=<value> overrides.  These are the SHIPPED values: " +
                  "a block synthesized at its entity defaults is not the block " +
                  "the chip contains, and for debug_module the default folds " +
                  "the whole design away (ENABLE_DEBUG is false by default and " +
                  "true in MemoryMap.vhd).",
        ),
        "ghdl": attr.label(
            default = "@ghdl//:ghdl_mcode",
            executable = True,
            cfg = "exec",
        ),
        "skip_reason": attr.string(
            doc = "If set, no synthesis runs and the test passes with this " +
                  "reason printed.  A skip is DOCUMENTED, not silent: the " +
                  "reason is part of the frozen census, so removing it " +
                  "without removing the skip fails the census test.",
        ),
        "srcs": attr.label_list(
            allow_files = [".vhd", ".vhdl"],
            doc = "vhdl_source_set targets or plain files, in analysis order.",
        ),
        "std": attr.string(default = _STD_DEFAULT),
        "vhdl_libs": attr.label(default = "@ghdl//:vhdl_libs_v08"),
        # The same py_binary twice, in the two configurations it is needed in:
        # once as a build tool that runs GHDL, once inside the test's runfiles
        # where it reads the census the action already wrote.
        "_census_gate": attr.label(
            default = "//toolchains/ghdl:synth_census",
            executable = True,
            cfg = "target",
        ),
        "_census_tool": attr.label(
            default = "//toolchains/ghdl:synth_census",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
)
