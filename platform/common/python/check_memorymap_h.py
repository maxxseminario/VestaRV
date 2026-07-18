#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Standing gate: prove the generated MemoryMap.h is C-includable.

The chip generator emits a C header (out/software/include/MemoryMap.h). It must
compile cleanly as freestanding RISC-V C — a regression here (e.g. duplicate
struct-padding member names) silently breaks every downstream firmware build,
because the header itself stops being `#include`-able.

This script writes a tiny translation unit that includes the header and runs
    riscv-none-elf-gcc -march=rv32ima -mabi=ilp32 -ffreestanding -fsyntax-only
against it. Exit 0 = the header parses; nonzero = it does not (the compiler's
diagnostics are printed verbatim).

Usage:
    python3 check_memorymap_h.py [path/to/MemoryMap.h]

With no argument it checks the default emitted header,
../out/software/include/MemoryMap.h (relative to this script).

Kept Python-3.6-compatible (no f-strings with '=', no walrus, no dirs_exist_ok);
never invoked as `python3 -c "..."` (this machine's python3 is a Calibre wrapper
that strips quotes) — it is a script FILE on purpose.
"""

import os
import subprocess
import sys
import tempfile


def _defaultHeaderPath():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, '..', 'out', 'software', 'include', 'MemoryMap.h'))


def _findCompiler():
    # Allow an override for unusual toolchain installs; default to the documented
    # RISC-V prefix (see the repo CLAUDE.md: riscv-none-elf-).
    cc = os.environ.get('RISCV_CC', 'riscv-none-elf-gcc')
    # shutil.which honours PATH and absolute paths alike.
    try:
        import shutil
        if os.path.isabs(cc):
            return cc if os.path.exists(cc) else None
        return shutil.which(cc)
    except Exception:
        return cc


def checkHeader(headerPath):
    headerPath = os.path.abspath(headerPath)
    if not os.path.isfile(headerPath):
        sys.stderr.write('check_memorymap_h: header not found: ' + headerPath + '\n')
        return 2

    cc = _findCompiler()
    if cc is None:
        sys.stderr.write(
            'check_memorymap_h: RISC-V C compiler not found '
            '(looked for %s; set RISCV_CC to override).\n'
            % os.environ.get('RISCV_CC', 'riscv-none-elf-gcc'))
        return 3

    includeDir = os.path.dirname(headerPath)
    # A minimal TU: include the header and reference nothing — a syntax-only pass
    # is enough to catch duplicate members / malformed structs.
    src = (
        '#include "' + os.path.basename(headerPath) + '"\n'
        'int main(void) { return 0; }\n'
    )

    tmpdir = tempfile.mkdtemp(prefix='memmap_h_check_')
    srcPath = os.path.join(tmpdir, 'memmap_include_check.c')
    # The emitted header pulls in <stdint.h> (freestanding-builtin), <bits.h> and
    # <custom_ops.S>. bits.h/custom_ops.S are SDK-side headers the generator does
    # NOT emit into out/, so we supply empty shims here. They are searched AFTER
    # the header's own directory, so a real SDK snapshot's siblings win; when they
    # are absent (the generator's out/ tree) the shims let the parse reach the
    # struct definitions — which is exactly what we want to syntax-check. The
    # header only references the BITx / custom-op macros inside unexpanded
    # object-like #defines, so empty shims are sufficient for -fsyntax-only.
    shimPaths = []
    try:
        for shimName in ('bits.h', 'custom_ops.S'):
            shimPath = os.path.join(tmpdir, shimName)
            sf = open(shimPath, 'w')
            try:
                sf.write('/* check_memorymap_h shim (empty) */\n')
            finally:
                sf.close()
            shimPaths.append(shimPath)

        f = open(srcPath, 'w')
        try:
            f.write(src)
        finally:
            f.close()

        cmd = [
            cc,
            '-march=rv32ima', '-mabi=ilp32',
            '-ffreestanding', '-fsyntax-only',
            '-I', includeDir,
            '-I', tmpdir,
            srcPath,
        ]
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            universal_newlines=True)
        out, _ = proc.communicate()
        rc = proc.returncode

        if rc == 0:
            print('check_memorymap_h: OK — ' + headerPath + ' compiles clean '
                  '(riscv-none-elf-gcc -fsyntax-only).')
            return 0

        sys.stderr.write('check_memorymap_h: FAIL — ' + headerPath +
                         ' does not compile:\n')
        sys.stderr.write('  $ ' + ' '.join(cmd) + '\n')
        if out:
            for line in out.rstrip('\n').split('\n'):
                sys.stderr.write('  ' + line + '\n')
        return 1
    finally:
        for p in [srcPath] + shimPaths:
            try:
                os.remove(p)
            except OSError:
                pass
        try:
            os.rmdir(tmpdir)
        except OSError:
            pass


def main(argv):
    headerPath = argv[1] if len(argv) > 1 else _defaultHeaderPath()
    return checkHeader(headerPath)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
