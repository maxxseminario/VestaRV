"""A hermetic chip-generation action.

One `chip_artifacts` target runs platform/common/python/generate.py for one
configuration inside a staged copy of the tree (see stage_generate.py) and
declares the generated files plus the whole latex/TRM tree as bazel outputs.
The source tree is never written to, so the target is safe to build
concurrently with any other work in the workspace.
"""

# The files the generator writes that anything downstream consumes, as paths
# relative to the chip root (platform/common). Every one of these is asserted
# present by the action, so a generator change that stops emitting one is a
# build error rather than a silently missing artifact.
CHIP_OUT_FILES = [
    "out/hdl/MCU.vhd",
    "out/hdl/MemoryMap.vhd",
    "out/hdl/riscv_tb.vhd",
    "out/hdl/MCU_routing_template.vhd",
    "out/software/include/MemoryMap.h",
    "out/software/include/core_features.h",
    "out/software/include/periph.S",
    "out/linker-scripts/memory.x",
    "out/linker-scripts/periph.x",
    "out/linker-scripts/RAM_START.txt",
    "out/linker-scripts/RAM_SIZE.txt",
    "out/linker-scripts/ROM_START.txt",
    "out/linker-scripts/ROM_SIZE.txt",
    "out/pnr/chip_top_padring.tcl",
    "out/web/chip_data.js",
    "out/web/MemoryMap.json",
    "config/MemoryMap.json",
    "config/ChipConfig.resolved.json",
    "config/PadRing.json",
]

# out/web/MemoryMap.json is the Makefile's `web-copy` step, not something
# generate.py writes; the action reproduces that copy so the register browser's
# input has one canonical label.
_POST_COPY = ["config/MemoryMap.json=out/web/MemoryMap.json"]

# An arbitrary fixed instant (2025-01-01 UTC), matching platform/common/Makefile's
# SOURCE_DATE_EPOCH. It pins the TRM's printed revision date and the "Generated
# on ..." header stamp so a rebuild is byte-identical. It is deliberately not
# derived from the clock or from HEAD.
DEFAULT_EPOCH = 1735689600

def outputGroupName(relPath):
    """The output-group name a filegroup uses to pick one generated file out."""
    return relPath.replace("/", "_").replace(".", "_").replace("-", "_")

def chip_artifact(name, rel_path, target):
    """A named single-file handle on one artifact of a chip_artifacts target."""
    native.filegroup(
        name = name,
        srcs = [target],
        output_group = outputGroupName(rel_path),
    )

def _chip_artifacts_impl(ctx):
    name = ctx.label.name

    outs = {}
    for rel in CHIP_OUT_FILES:
        outs[rel] = ctx.actions.declare_file(name + "/" + rel)
    trmDir = ctx.actions.declare_directory(name + "/latex/TRM")
    runLog = ctx.actions.declare_file(name + "/generate.log")

    # A scratch tree beside the outputs, wiped by the action when it finishes.
    stageRoot = "{}/{}/{}_stage".format(ctx.bin_dir.path, ctx.label.package, name)

    inputs = ctx.files.srcs + ctx.files.chip_root_srcs + ctx.files.out_of_tree_srcs
    if ctx.file.config:
        inputs = inputs + [ctx.file.config]

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)
    args.add("--stage-root", stageRoot)
    args.add("--chip-root", ctx.attr.chip_root)
    args.add("--chip-name", ctx.attr.chip_name)
    args.add("--epoch", str(ctx.attr.epoch))
    args.add("--log", runLog.path)
    if ctx.file.config:
        args.add("--config", ctx.file.config.path)
    for spec in _POST_COPY:
        args.add("--post-copy", spec)
    for rel in CHIP_OUT_FILES:
        args.add("--out", rel + "=" + outs[rel].path)
    args.add("--out-dir", "latex/TRM=" + trmDir.path)
    args.add_all(inputs, before_each = "--input")

    ctx.actions.run(
        executable = ctx.executable._stager,
        arguments = [args],
        inputs = depset(inputs),
        outputs = outs.values() + [trmDir, runLog],
        mnemonic = "ChipGenerate",
        progress_message = "Generating chip artifacts for %s" % name,
        use_default_shell_env = False,
        # The generator subprocess gets its own scrubbed environment inside
        # stage_generate.py; this is only what the py_binary bootstrap needs.
        env = {"PATH": "/usr/local/bin:/usr/bin:/bin"},
    )

    groups = {}
    for rel in CHIP_OUT_FILES:
        groups[outputGroupName(rel)] = depset([outs[rel]])
    groups["trm"] = depset([trmDir])
    groups["log"] = depset([runLog])

    allFiles = depset(outs.values() + [trmDir, runLog])
    return [
        DefaultInfo(files = allFiles, runfiles = ctx.runfiles(files = outs.values())),
        OutputGroupInfo(**groups),
    ]

chip_artifacts = rule(
    implementation = _chip_artifacts_impl,
    doc = "Runs generate.py for one chip configuration in a staged copy of the tree.",
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "The generator's own python modules.",
        ),
        "chip_root_srcs": attr.label_list(
            allow_files = True,
            doc = "Everything else under the chip root that the generator reads: " +
                  "hdl_templates, the latex source tree, the config json files.",
        ),
        "out_of_tree_srcs": attr.label_list(
            allow_files = True,
            doc = "Inputs the generator reads from above the chip root, staged at " +
                  "their workspace-relative paths: hdl/common/periph/NPU.vhd and the " +
                  "implementations/asic/<chip>/analog chapter.",
        ),
        "config": attr.label(
            allow_single_file = [".json"],
            doc = "Optional CHIP_CONFIG json; omitted means the built-in Castalia default.",
        ),
        "chip_name": attr.string(default = ""),
        "chip_root": attr.string(default = "platform/common"),
        "epoch": attr.int(default = DEFAULT_EPOCH),
        "_stager": attr.label(
            default = "//platform/common/bazel:stage_generate",
            executable = True,
            cfg = "exec",
        ),
    },
)
