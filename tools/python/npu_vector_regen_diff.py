#!/usr/bin/env python3
# coding: utf-8
"""VestaRV: re-run an NPU vector generator and diff its output against the tracked vectors.

Each generator derives its output directory from __file__ with no redirect flag, so running
it in place would overwrite the vectors it is checked against and pass by construction; the
generator directory is copied to a scratch tree and the copy is run. The generators seed
their own Random instances, and this asserts that rather than assuming it. Exit 0, 1 or 2.
"""

from __future__ import print_function

import argparse
import filecmp
import os
import shutil
import subprocess
import sys
import tempfile


def die(msg):
    print("npu_vector_regen_diff: FATAL -- " + msg, file=sys.stderr)
    return 2


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="re-run an NPU vector generator and diff it against the "
                    "tracked vectors")
    ap.add_argument("--generator", required=True,
                    help="the gen_*_vectors.py to re-run")
    ap.add_argument("--golden", required=True,
                    help="the tracked vector directory it must reproduce")
    # gen_gemm_vectors.py calls gen_aen_relu_exp(), which writes into OUT_DIR,
    # BEFORE write_case_files() creates OUT_DIR, so it only runs where the
    # directory already exists. In the tracked tree it always does, which is
    # why the ordering bug has never been felt. This flag reproduces that
    # precondition explicitly rather than hiding it; drop it the day
    # gen_gemm_vectors.py makes its own directory first.
    ap.add_argument("--precreate-outdir", action="store_true",
                    help="create the output directory before running the "
                         "generator (see the gen_gemm_vectors note in source)")
    args = ap.parse_args(sys.argv[1:] if argv is None else argv)

    gen = os.path.abspath(args.generator)
    golden = os.path.abspath(args.golden)
    if not os.path.isfile(gen):
        return die("no generator at " + gen)
    if not os.path.isdir(golden):
        return die("no tracked vector directory at " + golden)

    srcdir = os.path.dirname(gen)
    work = tempfile.mkdtemp(prefix="npuvec")
    try:
        # The generators import their siblings (npu_fixed, and for the golden
        # partners each other), so the whole module set travels together.
        staged = os.path.join(work, "npu")
        os.makedirs(staged)
        for name in sorted(os.listdir(srcdir)):
            if name.endswith(".py"):
                shutil.copyfile(os.path.join(srcdir, name),
                                os.path.join(staged, name))

        if args.precreate_outdir:
            os.makedirs(os.path.join(staged, os.path.basename(golden)))

        run = os.path.join(staged, os.path.basename(gen))
        proc = subprocess.Popen([sys.executable, run], cwd=staged,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        out, _ = proc.communicate()
        text = out.decode("utf-8", "replace")
        if proc.returncode != 0:
            print(text)
            return die("%s exited %d" % (os.path.basename(gen),
                                         proc.returncode))

        produced = os.path.join(staged, os.path.basename(golden))
        if not os.path.isdir(produced):
            print(text)
            return die("the generator wrote no %s directory in the scratch "
                       "tree; its OUT_DIR is not named after --golden"
                       % os.path.basename(golden))

        want = sorted(n for n in os.listdir(golden)
                      if os.path.isfile(os.path.join(golden, n)))
        got = sorted(n for n in os.listdir(produced)
                     if os.path.isfile(os.path.join(produced, n)))

        # An empty tracked directory would make every comparison below vacuous.
        if not want:
            return die("the tracked directory " + golden + " holds no files")

        missing = [n for n in want if n not in got]
        extra = [n for n in got if n not in want]
        differ = []
        same = 0
        for name in want:
            if name in missing:
                continue
            a = os.path.join(golden, name)
            b = os.path.join(produced, name)
            if filecmp.cmp(a, b, shallow=False):
                same += 1
            else:
                differ.append(name)

        print("npu_vector_regen_diff: %s -> %s"
              % (os.path.basename(gen), os.path.basename(golden)))
        print("  tracked %d file(s), regenerated %d file(s)"
              % (len(want), len(got)))
        print("  byte-identical: %d" % same)

        rc = 0
        for label, names in (("DIFFERS", differ),
                             ("NOT REGENERATED", missing),
                             ("UNTRACKED OUTPUT", extra)):
            if names:
                rc = 1
                print("")
                print("  %s (%d):" % (label, len(names)))
                for name in names:
                    print("    " + name)

        print("")
        if rc:
            print("FAIL: the tracked vectors are not what this generator "
                  "produces today.")
        else:
            print("OK: all %d tracked file(s) reproduced byte-identically."
                  % same)
        return rc
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
