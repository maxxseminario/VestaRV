#!/bin/bash
# Fetch the public EEMBC CoreMark sources, pinned, into $1 (default the perf run dir). Not vendored: EEMBC's agreement
# covers the trademark, and the sources stay upstream's. coremark.md5 in upstream is stale for coremark.h since a
# 2023 comment typo fix; the five .c files match it, which this script checks.
set -e
SHA=1f483d5b8316753a742cbf5590caf5bd0a4e4777
D="${1:-$(cd "$(dirname "$0")/../.." && pwd)/xcelium/riscv_test/perf_mp/coremark-src}"
mkdir -p "$D"
curl -sSL -m 120 "https://github.com/eembc/coremark/archive/$SHA.tar.gz" | tar xz -C "$D" --strip-components=1
cd "$D"
grep -v coremark.h coremark.md5 | md5sum -c -
