#!/usr/bin/env python3
"""VestaRV: run the chip generator inside a staged copy of the tree, never the source tree.

generate.py resolves every path from its own __file__ and LatexUserGuide.py reaches three
levels further up for the analog chapter and NPU.vhd, so the action copies its inputs into a
scratch tree at their workspace-relative paths and runs there, patching no path. Inputs arrive
as a bazel params file because the analog chapter alone is about 2000 files.
"""

import argparse
import os
import shutil
import subprocess
import sys


def _copyInto(srcPath, dstPath):
    """Copy one file, creating parents, and leave it writable. Bazel source files are read-only
    symlinks into the execroot and the generator rewrites some of the files it also reads, so the
    staged copy has to be a real writable file.
    """
    dstDir = os.path.dirname(dstPath)
    if dstDir and not os.path.isdir(dstDir):
        os.makedirs(dstDir)
    shutil.copyfile(srcPath, dstPath)
    os.chmod(dstPath, 0o644)


def _stageRelative(execPath):
    """Workspace-relative path for an action input. Source files already arrive that way; a generated
    input carries a bazel-out prefix that has to come off, so the file lands where the generator's
    __file__ arithmetic expects it.
    """
    parts = execPath.split('/')
    if parts and parts[0] == 'bazel-out':
        for i, part in enumerate(parts):
            if part in ('bin', 'genfiles', 'testlogs'):
                return '/'.join(parts[i + 1:])
    if parts and parts[0] == 'external':
        raise SystemExit('stage_generate: external-repository inputs are not '
                         'supported (no workspace-relative path): ' + execPath)
    return execPath


def _childEnv(args, stageRoot, configPath):
    """A scrubbed environment for the generator subprocess: nothing is inherited but PATH and TMPDIR,
    since a leaked PYTHONPATH could shadow a generator module and a leaked VESTA_TRM_DATE_EPOCH
    would unpin the TRM date. PYTHONUTF8 is mandatory; the SystemRDL closure is the one exception.
    """
    epoch = str(args.epoch)
    return {
        'PATH': os.environ.get('PATH', '/usr/bin:/bin'),
        'TMPDIR': os.environ.get('TMPDIR', '/tmp'),
        'HOME': stageRoot,
        'CHIP_NAME': args.chip_name,
        'CHIP_CONFIG': configPath,
        # Pins the TRM's printed revision date (LatexUserGuide.py) AND the
        # "Generated on ..." header stamp (mcu_vhd.generatedOnStamp).
        'VESTA_TRM_DATE_EPOCH': epoch,
        'SOURCE_DATE_EPOCH': epoch,
        'PYTHONDONTWRITEBYTECODE': '1',
        'PYTHONHASHSEED': '0',
        'PYTHONUTF8': '1',
        'PYTHONIOENCODING': 'utf-8',
        'LC_ALL': 'C.UTF-8',
        'LANG': 'C.UTF-8',
        'PYTHONPATH': _rdlPath(),
    }


# The third-party packages the SystemRDL compiler needs at run time. Named
# explicitly so the child's PYTHONPATH is a known list rather than whatever the
# py_binary bootstrap happened to put on sys.path.
_RDL_PACKAGES = ('systemrdl', 'antlr4', 'colorama', 'typing_extensions')


def _rdlPath():
    """The sys.path entries holding the SystemRDL closure, as a PYTHONPATH. Raises rather than
    returning empty: a generation that silently lost the register descriptions would emit a chip
    with no peripheral registers at all.
    """
    found = []
    for entry in sys.path:
        if not entry or not os.path.isdir(entry):
            continue
        for pkg in _RDL_PACKAGES:
            if (os.path.isdir(os.path.join(entry, pkg)) or
                    os.path.isfile(os.path.join(entry, pkg + '.py'))):
                if entry not in found:
                    found.append(entry)
                break
    if not any(os.path.isdir(os.path.join(e, 'systemrdl')) for e in found):
        raise SystemExit(
            'stage_generate: systemrdl-compiler is not in this action\'s runfiles, '
            'so generate.py cannot read hdl/common/regs/rdl/*.rdl. Add '
            'requirement("systemrdl-compiler") to //platform/common/bazel:stage_generate.')
    return os.pathsep.join(found)


# Declared outputs the generator may write beside the other outputs instead of into config/.
_BESIDE_OUTPUTS = {
    'config/ChipConfig.resolved.json': 'out/config/ChipConfig.resolved.json',
    'config/PadRing.json': 'out/config/PadRing.json',
}


def main(argv):
    parser = argparse.ArgumentParser(fromfile_prefix_chars='@')
    parser.add_argument('--stage-root', required=True)
    parser.add_argument('--chip-root', required=True,
                        help='workspace-relative chip root, e.g. platform/common')
    parser.add_argument('--chip-name', default='')
    parser.add_argument('--config', default='',
                        help='workspace-relative CHIP_CONFIG json, or empty')
    parser.add_argument('--epoch', type=int, required=True)
    parser.add_argument('--input', action='append', default=[],
                        help='exec-root-relative path of one staged input file')
    parser.add_argument('--post-copy', action='append', default=[],
                        help='SRC=DST, both chip-root-relative, run after generation')
    parser.add_argument('--out', action='append', default=[],
                        help='CHIPRELPATH=OUTPUTPATH for one declared file output')
    parser.add_argument('--out-dir', action='append', default=[],
                        help='CHIPRELPATH=OUTPUTDIR for one declared directory output')
    parser.add_argument('--log', default='', help='declared file to capture the run log into')
    args = parser.parse_args(argv)

    stageRoot = os.path.abspath(args.stage_root)
    if os.path.isdir(stageRoot):
        shutil.rmtree(stageRoot)
    os.makedirs(stageRoot)

    for execPath in args.input:
        _copyInto(execPath, os.path.join(stageRoot, _stageRelative(execPath)))

    chipRoot = os.path.join(stageRoot, args.chip_root)
    # The generator asserts latex/TRM exists before writing into it, and expects
    # to be able to create out/ and config/ underneath the chip root.
    for rel in ('out', 'config', 'latex/TRM/include'):
        path = os.path.join(chipRoot, rel)
        if not os.path.isdir(path):
            os.makedirs(path)

    configPath = ''
    if args.config:
        configPath = os.path.join(stageRoot, _stageRelative(args.config))
        if not os.path.isfile(configPath):
            raise SystemExit('stage_generate: CHIP_CONFIG was not staged: ' + configPath)

    pythonDir = os.path.join(chipRoot, 'python')
    proc = subprocess.run(
        [sys.executable, 'generate.py'],
        cwd=pythonDir,
        env=_childEnv(args, stageRoot, configPath),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log = proc.stdout.decode('utf-8', 'replace')
    sys.stdout.write(log)
    if args.log:
        _copyLogDir = os.path.dirname(args.log)
        if _copyLogDir and not os.path.isdir(_copyLogDir):
            os.makedirs(_copyLogDir)
        with open(args.log, 'w', encoding='utf-8') as f:
            f.write(log)
    if proc.returncode != 0:
        raise SystemExit('stage_generate: generate.py failed with exit code %d'
                         % proc.returncode)

    # The Makefile's web-copy step: out/web/MemoryMap.json is a copy of
    # config/MemoryMap.json, not something generate.py writes itself.
    for spec in args.post_copy:
        src, dst = spec.split('=', 1)
        _copyInto(os.path.join(chipRoot, src), os.path.join(chipRoot, dst))

    for spec in args.out:
        rel, dstPath = spec.split('=', 1)
        srcPath = os.path.join(chipRoot, rel)
        if not os.path.isfile(srcPath) and rel in _BESIDE_OUTPUTS:
            # The resolved record and the pad ring are tracked files, so generate.py writes them
            # to out/config/ and refreshes config/ only for the default configuration. Either
            # location satisfies the same declared output; out/config/ is preferred because it
            # is always this run's, while config/ may be a staged copy of the tracked default.
            beside = os.path.join(chipRoot, _BESIDE_OUTPUTS[rel])
            if os.path.isfile(beside):
                srcPath = beside
        if not os.path.isfile(srcPath):
            raise SystemExit('stage_generate: the generator did not write the '
                             'declared output ' + rel)
        _copyInto(srcPath, dstPath)

    for spec in args.out_dir:
        rel, dstPath = spec.split('=', 1)
        srcPath = os.path.join(chipRoot, rel)
        if not os.path.isdir(srcPath):
            raise SystemExit('stage_generate: the generator did not write the '
                             'declared output directory ' + rel)
        if os.path.isdir(dstPath):
            shutil.rmtree(dstPath)
        shutil.copytree(srcPath, dstPath)

    # The stage is ~25MB of copies whose only purpose was this one run.
    shutil.rmtree(stageRoot, ignore_errors=True)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
