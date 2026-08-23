#!/usr/bin/env python3
"""Recompute the three published CPI tables from the recorded raw counts.

expected.json holds two kinds of number. The `images` map is RAW: four
counters per image, each proven against the RTL by its own cpi_test target.
Everything else is DERIVED from those counters by the same arithmetic the TRM
prints, and is recorded so that a reader can diff expected.json against TRM
Section 12 by eye.

This test proves the derived half follows from the raw half. It runs no
simulation, so it is cheap enough to stay in the default test set, and it
therefore covers the manual long-benchmark images too: a hand edit to
expected.json that no longer adds up is caught without simulating anything.

It does NOT prove the raw counters. That is each cpi_test target's job.
"""

import json
import sys

# CPI is published to three decimals and the cycles-lost share to one, so the
# comparison is made at exactly the precision the TRM prints.
_CPI_PLACES = 3

_PCT_PLACES = 1


def _fail(msg, failures):
    failures.append(msg)


def _kernel(images, name, failures):
    img = images.get(name)
    if img is None:
        _fail("no image entry %r" % name, failures)
        return None
    if img["status"] != "PASS":
        _fail("image %s recorded status %s" % (name, img["status"]), failures)
        return None
    return img


def check_instruction_classes(data, failures):
    """TRM Table t:cpi-timing, from the paired micro-kernels."""
    images = data["images"]
    for cls, want in sorted(data["instruction_classes"].items()):
        hi = _kernel(images, "micro_%s_64" % cls, failures)
        lo = _kernel(images, "micro_%s_0" % cls, failures)
        if hi is None or lo is None:
            continue
        dc = hi["cyc_kernel"] - lo["cyc_kernel"]
        di = hi["ins_kernel"] - lo["ins_kernel"]
        if di <= 0:
            _fail(
                "class %s: the NOPS=64 kernel retires %d more instructions "
                "than the NOPS=0 kernel, which cannot be right" % (cls, di),
                failures,
            )
            continue
        if di != want["delta_instructions"]:
            _fail(
                "class %s: delta-instructions is %d, expected.json records %d"
                % (cls, di, want["delta_instructions"]),
                failures,
            )
        got = round(dc / float(di), _CPI_PLACES)
        if got != want["cycles_per_instruction"]:
            _fail(
                "class %s: measured %.3f cycles per instruction "
                "(%d cycles over %d instructions), expected.json records %.3f"
                % (cls, got, dc, di, want["cycles_per_instruction"]),
                failures,
            )


def check_linearity(data, failures):
    """The alu32 linearity control, which validates the subtraction itself."""
    images = data["images"]
    want = data["linearity"]
    hi = _kernel(images, want["long_image"], failures)
    lo = _kernel(images, want["short_image"], failures)
    if hi is None or lo is None:
        return
    dc = hi["cyc_kernel"] - lo["cyc_kernel"]
    di = hi["ins_kernel"] - lo["ins_kernel"]
    if dc != want["delta_cycles"] or di != want["delta_instructions"]:
        _fail(
            "linearity control: measured %d cycles over %d instructions, "
            "expected.json records %d over %d"
            % (dc, di, want["delta_cycles"], want["delta_instructions"]),
            failures,
        )
    elif dc != di:
        _fail(
            "linearity control: %d cycles for %d instructions of a one-cycle "
            "class, so the loop overhead is not fully subtracted out"
            % (dc, di),
            failures,
        )


def check_benchmark_cpi(data, failures):
    """TRM Table t:cpi-bench, the timed-kernel CPI of the nine benchmarks."""
    images = data["images"]
    table = data["benchmark_cpi"]
    total_c = 0
    total_i = 0
    for name, want in sorted(table.items()):
        if name == "AGGREGATE":
            continue
        img = _kernel(images, name, failures)
        if img is None:
            continue
        if img["ins_kernel"] != want["instructions"]:
            _fail(
                "benchmark %s: kernel retired %d instructions, expected.json "
                "records %d" % (name, img["ins_kernel"], want["instructions"]),
                failures,
            )
        got = round(img["cyc_kernel"] / float(img["ins_kernel"]), _CPI_PLACES)
        if got != want["cpi"]:
            _fail(
                "benchmark %s: kernel CPI %.3f, expected.json records %.3f"
                % (name, got, want["cpi"]),
                failures,
            )
        total_c += img["cyc_kernel"]
        total_i += img["ins_kernel"]

    agg = table["AGGREGATE"]
    if total_i != agg["instructions"]:
        _fail(
            "benchmark aggregate: %d instructions retired, expected.json "
            "records %d" % (total_i, agg["instructions"]),
            failures,
        )
    if total_i:
        got = round(total_c / float(total_i), _CPI_PLACES)
        if got != agg["cpi"]:
            _fail(
                "benchmark aggregate: CPI %.3f, expected.json records %.3f"
                % (got, agg["cpi"]),
                failures,
            )


def check_straddling_fetch(data, failures):
    """TRM Table t:cpi-align, the RV32IMAC versus RV32IMA comparison."""
    images = data["images"]
    table = data["straddling_fetch"]
    tc = tn = ti = 0
    for name, want in sorted(table.items()):
        if name == "AGGREGATE":
            continue
        with_c = _kernel(images, name, failures)
        without_c = _kernel(images, name + "_noc", failures)
        if with_c is None or without_c is None:
            continue
        # The load-bearing property of the pair: gcc emits the same
        # instruction sequence either way, so only the encoding differs and
        # the whole cycle delta is the straddling-fetch penalty. If the
        # retired counts ever diverge, the comparison means nothing.
        if with_c["ins_kernel"] != without_c["ins_kernel"]:
            _fail(
                "straddling-fetch pair %s: the RV32IMAC build retires %d "
                "kernel instructions and the RV32IMA build %d. The pair is "
                "only a fetch-alignment comparison while those are equal."
                % (name, with_c["ins_kernel"], without_c["ins_kernel"]),
                failures,
            )
            continue
        cpi_c = round(with_c["cyc_kernel"] / float(with_c["ins_kernel"]), _CPI_PLACES)
        cpi_n = round(without_c["cyc_kernel"] / float(without_c["ins_kernel"]), _CPI_PLACES)
        # The residual penalty in CPI terms, which is the figure the TRM prose
        # quotes. It is the cycle difference over the RV32IMAC build's retired
        # count, not the difference of the two rounded CPIs, so that a small
        # penalty does not vanish into the rounding of two larger numbers.
        pen = round(
            (with_c["cyc_kernel"] - without_c["cyc_kernel"]) / float(with_c["ins_kernel"]),
            _CPI_PLACES,
        )
        lost = round(
            100.0 * (with_c["cyc_kernel"] - without_c["cyc_kernel"]) / float(with_c["cyc_kernel"]),
            _PCT_PLACES,
        )
        if (cpi_c, cpi_n, pen, lost) != (
            want["cpi_c"], want["cpi_noc"], want["penalty_cpi"], want["cycles_lost_pct"],
        ):
            _fail(
                "straddling-fetch %s: measured cpi_c=%.3f cpi_noc=%.3f "
                "penalty=%.3f cycles_lost=%.1f%%, expected.json records "
                "%.3f / %.3f / %.3f / %.1f%%"
                % (
                    name, cpi_c, cpi_n, pen, lost,
                    want["cpi_c"], want["cpi_noc"], want["penalty_cpi"],
                    want["cycles_lost_pct"],
                ),
                failures,
            )
        tc += with_c["cyc_kernel"]
        tn += without_c["cyc_kernel"]
        ti += with_c["ins_kernel"]

    agg = table["AGGREGATE"]
    if ti:
        cpi_c = round(tc / float(ti), _CPI_PLACES)
        cpi_n = round(tn / float(ti), _CPI_PLACES)
        pen = round((tc - tn) / float(ti), _CPI_PLACES)
        lost = round(100.0 * (tc - tn) / float(tc), _PCT_PLACES)
        if (cpi_c, cpi_n, pen, lost) != (
            agg["cpi_c"], agg["cpi_noc"], agg["penalty_cpi"], agg["cycles_lost_pct"],
        ):
            _fail(
                "straddling-fetch aggregate: measured cpi_c=%.3f cpi_noc=%.3f "
                "penalty=%.3f cycles_lost=%.1f%%, expected.json records "
                "%.3f / %.3f / %.3f / %.1f%%"
                % (
                    cpi_c, cpi_n, pen, lost,
                    agg["cpi_c"], agg["cpi_noc"], agg["penalty_cpi"],
                    agg["cycles_lost_pct"],
                ),
                failures,
            )


def main():
    with open(sys.argv[1]) as f:
        data = json.load(f)

    failures = []
    check_instruction_classes(data, failures)
    check_linearity(data, failures)
    check_benchmark_cpi(data, failures)
    check_straddling_fetch(data, failures)

    if failures:
        print("FAIL derived_tables_test: expected.json does not add up")
        for f in failures:
            print("  " + f)
        print("")
        print(
            "The derived tables must follow from the `images` counters. If "
            "the raw counts moved on purpose, re-record BOTH halves of "
            "expected.json and the matching tables of TRM Section 12 (s:cpi) "
            "in the same commit. See verification/cpi/README.md."
        )
        return 1

    print("PASS derived_tables_test: all three published tables follow from the recorded counts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
