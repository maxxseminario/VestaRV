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


# Corrections from the fabricated design, applied over v1's data. Field dicts use v1's form.
_AFE_TPR_FIELDS = "POTENTIOSTAT_TPR"
PERIPHERAL_DESCRIPTIONS = {"DSADC": "Dual-slope ADC"}
# Register offsets v1 has wrong, from MemoryMap.vhd. Keyed by peripheral with digits stripped.
OFFSET_CORRECTIONS = {
    ("GPIO", "PIF"): 0x18, ("GPIO", "PIES"): 0x1C, ("GPIO", "PIE"): 0x20,
    ("GPIO", "PSEL"): 0x24, ("GPIO", "PREN"): 0x28,
    ("SYSTEM", "WDTPASS"): 0x30, ("SYSTEM", "WDTCR"): 0x34, ("SYSTEM", "WDTSR"): 0x38,
}
REGISTER_CORRECTIONS = {
    ("DSADC", "ADC_VAL"): {
        "description": "12-bit conversion result; a write starts a conversion when ADCEN is set",
    },
    ("DSADC", "BIAS_TC_DSADC"): {
        "description": "Integrator op-amp bias current", "reset": 0x30,
    },
    ("DSADC", "BIAS_LC_DSADC"): {
        "description": "Integrator op-amp LC resistor trim", "reset": 0x28,
    },
    ("DSADC", "BIAS_RIN_DSADC"): {
        "description": "Integrator input resistor; each set bit shorts a segment", "reset": 0x23,
    },
    ("DSADC", "BIAS_RFB_DSADC"): {
        "description": "Resistor in series with the integrator cap; each set bit shorts a segment",
        "reset": 0x2F,
    },
    ("POTENTIOSTAT", "BIAS_DSADC_VCM"): {
        "description": "VCM DAC code, shared by the dual-slope ADC and the potentiostat",
        "reset": 0x2000,
    },
    ("POTENTIOSTAT", "BIAS_TIA_G_POT"): {
        "description": "TIA feedback resistor string: 1 Mohm in series with 16 x 60 kohm",
        "reset": 0x1FFFF,
        "fields": {
            "R60K_SHORT": {
                "bits": [0, 15], "width": 16,
                "desc": "Each set bit shorts one 60 kohm resistor",
            },
            "R1M_SHORT": {
                "bits": 16, "width": 1, "desc": "1 Mohm resistor",
                "values": {0: "In circuit", 1: "Shorted"},
            },
        },
    },
}


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


def register_address(peripheral: str, register: str, pdef: Dict[str, Any]) -> int:
    """Return a register's address, applying any offset correction."""
    offset = OFFSET_CORRECTIONS.get((peripheral.rstrip("0123456789"), register))
    if offset is None:
        return pdef["registers"][register]["addr"]
    return pdef["base_addr"] + offset


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
            correction = REGISTER_CORRECTIONS.get((pname, rname), {})
            key = _AFE_TPR_FIELDS if (pname, rname) == ("DSADC", "TPR") else bitfield_key(pname, rname)
            block = correction.get("fields") or bitfields.get(key)
            if block:
                fields = {fn: normalize_field(block[fn]) for fn in sorted(block)}
            else:
                fields = {}
            out_regs[rname] = {
                "addr": register_address(pname, rname, pdef),
                "size": rdef["size"],
                "type": rdef["type"],
                "description": correction.get("description", rdef["description"]),
                "fields": fields,
            }
            if "reset" in correction:
                out_regs[rname]["reset"] = correction["reset"]
        out_periphs[pname] = {
            "description": PERIPHERAL_DESCRIPTIONS.get(pname, pdef["description"]),
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
