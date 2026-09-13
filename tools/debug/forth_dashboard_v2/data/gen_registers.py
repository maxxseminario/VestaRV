#!/usr/bin/env python3
"""
VestaRV: generate registers.json for the Forth Dashboard v2.

Imports the v1 dashboard's register and bitfield definitions live rather than copying them.
A bitfield block is keyed peripheral-with-trailing-digits-stripped + '_' + register, so SPI0.CR
and SPI1.CR share SPI_CR; v1's scalar-LSB and [lo, hi] forms both normalise to lsb + width.
"""

import argparse
import json
import os
import sys
from typing import Any, Dict, Optional

# Absolute path to the v1 dashboard directory (the single source of truth).
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
V1_DIR = os.path.abspath(os.path.join(_THIS_DIR, "..", "..", "forth_dashboard"))

# Human-readable provenance string baked into the JSON (relative, machine-stable).
GENERATED_FROM = (
    "tools/debug/forth_dashboard/peripherals_config.py + "
    "tools/debug/forth_dashboard/bitfields_config.py"
)
CHIP = "myshkin"


def load_v1() -> "tuple[Dict[str, Any], Dict[str, Any]]":
    """Import the v1 PERIPHERALS and BITFIELDS dicts (no data is copied)."""
    if V1_DIR not in sys.path:
        sys.path.insert(0, V1_DIR)
    import peripherals_config  # noqa: E402  (path set up above)
    import bitfields_config  # noqa: E402

    return peripherals_config.PERIPHERALS, bitfields_config.BITFIELDS


def bitfield_key(peripheral: str, register: str) -> str:
    """Resolve a (peripheral, register) pair to its BITFIELDS key, as v1 does: strip trailing
    instance digits from the peripheral name, then join with the register name.
    """
    generic = peripheral.rstrip("0123456789")
    return f"{generic}_{register}"


def normalize_field(info: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize one v1 bitfield dict into {lsb, width, desc, values}, collapsing v1's scalar-LSB and
    inclusive [lo, hi] encodings into an explicit lsb.
    """
    bits = info["bits"]
    lsb = bits[0] if isinstance(bits, list) else bits
    raw_values = info.get("values")
    if raw_values is None:
        values: Optional[Dict[str, Any]] = None
    else:
        # Emit enum keys as strings in numeric order for a clean, stable diff.
        values = {str(k): raw_values[k] for k in sorted(raw_values)}
    return {
        "lsb": lsb,
        "width": info["width"],
        "desc": info["desc"],
        "values": values,
    }


def build_registers(
    peripherals: Dict[str, Any], bitfields: Dict[str, Any]
) -> Dict[str, Any]:
    """Build the full registers.json document as a plain dict."""
    out_periphs: Dict[str, Any] = {}
    for pname in sorted(peripherals):
        pdef = peripherals[pname]
        out_regs: Dict[str, Any] = {}
        for rname in sorted(pdef["registers"]):
            rdef = pdef["registers"][rname]
            block = bitfields.get(bitfield_key(pname, rname))
            if block:
                fields = {fn: normalize_field(block[fn]) for fn in sorted(block)}
            else:
                fields = {}
            out_regs[rname] = {
                "addr": rdef["addr"],
                "size": rdef["size"],
                "type": rdef["type"],
                "description": rdef["description"],
                "fields": fields,
            }
        out_periphs[pname] = {
            "description": pdef["description"],
            "base_addr": pdef["base_addr"],
            "registers": out_regs,
        }
    return {
        "generated_from": GENERATED_FROM,
        "chip": CHIP,
        "peripherals": out_periphs,
    }


def render_json(doc: Dict[str, Any]) -> str:
    """Render the document to a deterministic JSON string (trailing newline)."""
    # sort_keys=False: ordering is already fixed by build_registers /
    # normalize_field, so numeric enum-key order is preserved.
    return json.dumps(doc, indent=2, sort_keys=False, ensure_ascii=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument(
        "-o",
        "--output",
        default=os.path.join(_THIS_DIR, "registers.json"),
        help="output path for registers.json (default: alongside this script)",
    )
    args = parser.parse_args()

    peripherals, bitfields = load_v1()
    doc = build_registers(peripherals, bitfields)
    text = render_json(doc)
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(
        f"wrote {args.output}: {len(doc['peripherals'])} peripherals, "
        f"{sum(len(p['registers']) for p in doc['peripherals'].values())} registers"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
