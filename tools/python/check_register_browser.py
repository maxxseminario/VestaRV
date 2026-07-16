#!/usr/bin/env python3
# check_register_browser.py — provenance gate for docs/register_browser.html
#
# Verifies that the memory-map data embedded in the register browser page
# (between the /*VESTA_REGDATA_BEGIN*/ ... /*VESTA_REGDATA_END*/ markers) is
# byte-identical (after whitespace normalisation) to a source MemoryMap.json,
# and that the peripheral / register counts agree.
#
#   python3 tools/python/check_register_browser.py
#   python3 tools/python/check_register_browser.py --spot CLINT.MSIP0
#
# Python 3.6 compatible. Exits non-zero with a diff summary on any mismatch.
from __future__ import print_function
import argparse
import io
import json
import os
import sys

BEGIN = "/*VESTA_REGDATA_BEGIN*/"
END = "/*VESTA_REGDATA_END*/"

# repo-root-relative defaults (the gate is run from ~/vestarv)
DEF_PAGE = os.path.join("docs", "register_browser.html")
DEF_MAP = os.path.join("platform", "common", "out", "web", "MemoryMap.json")


def read_text(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return f.read()


def extract_embedded(page_text):
    i = page_text.find(BEGIN)
    if i < 0:
        raise ValueError("marker %s not found in page" % BEGIN)
    j = page_text.find(END, i)
    if j < 0:
        raise ValueError("marker %s not found in page" % END)
    return page_text[i + len(BEGIN):j]


def norm(s):
    # whitespace-insensitive comparison: collapse to a canonical token stream so
    # a future minifying re-splice still compares equal to the pretty source.
    return "".join(s.split())


def count_tree(data):
    periphs = data.get("Peripherals", [])
    nreg = 0
    nfld = 0
    for p in periphs:
        regs = p.get("Registers", [])
        nreg += len(regs)
        for r in regs:
            nfld += len(r.get("BitFields", []))
    return len(periphs), nreg, nfld


def find_register(data, periph_name, reg_name):
    for p in data.get("Peripherals", []):
        if p.get("PeripheralName") == periph_name:
            for r in p.get("Registers", []):
                if r.get("RegisterName") == reg_name:
                    return p, r
            return p, None
    return None, None


def fmt_reset(reg):
    rv = reg.get("ResetValue", 0)
    return "0x%X (%d)" % (rv & 0xFFFFFFFF, rv)


def fmt_addr(reg):
    a = reg.get("Address", 0)
    return "0x%X (%d)" % (a, a)


def do_spot(embedded_data, source_data, spot, source_label):
    if "." not in spot:
        print("ERROR: --spot expects PERIPH.REGISTER (got %r)" % spot)
        return 2
    pn, rn = spot.split(".", 1)
    rc = 0
    for label, data in (("page-embedded", embedded_data), (source_label, source_data)):
        p, r = find_register(data, pn, rn)
        if r is None:
            print("[%s] %s.%s NOT FOUND" % (label, pn, rn))
            rc = 3
            continue
        print("[%s] %s.%s  address=%s  reset=%s  offset=+%s  access-fields=%s" % (
            label, pn, rn, fmt_addr(r), fmt_reset(r), r.get("Offset"),
            ",".join(bf.get("Accessibility", "") for bf in r.get("BitFields", []))))
    # cross-source agreement
    _, re = find_register(embedded_data, pn, rn)
    _, rs = find_register(source_data, pn, rn)
    if re is not None and rs is not None:
        if re.get("Address") == rs.get("Address") and re.get("ResetValue") == rs.get("ResetValue"):
            print("OK: %s.%s address+reset agree between page and source" % (pn, rn))
        else:
            print("MISMATCH: %s.%s differs between page and source" % (pn, rn))
            rc = 4
    return rc


def main(argv):
    ap = argparse.ArgumentParser(description="Provenance gate for register_browser.html")
    ap.add_argument("--page", default=DEF_PAGE, help="path to register_browser.html")
    ap.add_argument("--map", default=DEF_MAP, help="path to source MemoryMap.json")
    ap.add_argument("--spot", default=None, metavar="PERIPH.REG",
                    help="print address/reset of one register from both sources")
    args = ap.parse_args(argv)

    if not os.path.exists(args.page):
        print("ERROR: page not found: %s" % args.page)
        return 2
    if not os.path.exists(args.map):
        print("ERROR: source map not found: %s" % args.map)
        return 2

    page_text = read_text(args.page)
    source_text = read_text(args.map)

    try:
        embedded_text = extract_embedded(page_text)
    except ValueError as e:
        print("ERROR: %s" % e)
        return 2

    try:
        embedded_data = json.loads(embedded_text)
    except ValueError as e:
        print("ERROR: embedded JSON does not parse: %s" % e)
        return 2
    source_data = json.loads(source_text)

    if args.spot:
        return do_spot(embedded_data, source_data, args.spot, args.map)

    ep, er, ef = count_tree(embedded_data)
    sp, sr, sf = count_tree(source_data)

    print("source : %s" % args.map)
    print("page   : %s" % args.page)
    print("chip   : %s" % source_data.get("ChipName"))
    print("counts : %d peripherals, %d registers, %d bit fields (source)" % (sp, sr, sf))
    print("counts : %d peripherals, %d registers, %d bit fields (page-embedded)" % (ep, er, ef))

    rc = 0

    if (ep, er) != (sp, sr):
        print("FAIL: peripheral/register counts differ (page %d/%d vs source %d/%d)" % (ep, er, sp, sr))
        rc = 1
    else:
        print("OK  : peripheral & register counts match")

    ne, nsrc = norm(embedded_text), norm(source_text)
    if ne != nsrc:
        print("FAIL: embedded JSON is not byte-equal to source (after whitespace normalisation)")
        print("      normalized lengths: page=%d source=%d" % (len(ne), len(nsrc)))
        # first divergence
        lim = min(len(ne), len(nsrc))
        k = 0
        while k < lim and ne[k] == nsrc[k]:
            k += 1
        lo = max(0, k - 30)
        print("      first divergence at normalized offset %d:" % k)
        print("        page   : ...%s..." % ne[lo:k + 30])
        print("        source : ...%s..." % nsrc[lo:k + 30])
        rc = 1
    else:
        print("OK  : embedded JSON byte-equal to source (whitespace-normalised, %d chars)" % len(ne))

    if rc == 0:
        print("PASS: register_browser.html data provenance verified")
    else:
        print("FAILED")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
