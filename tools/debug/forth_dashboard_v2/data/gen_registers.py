#!/usr/bin/env python3
"""
gen_registers.py -- generate registers.json for the Forth Dashboard v2.

This standalone stdlib-only script imports the v1 dashboard's register
definitions (the single source of truth) and emits a flat, self-contained
``registers.json`` that both the v2 backend and frontend consume. It never
copies the v1 data: it imports it live from
``tools/debug/forth_dashboard/{peripherals_config,bitfields_config}.py``.

Bitfield -> register resolution
-------------------------------
Replicated faithfully from v1's ``bitfields_config.get_bitfields`` (lines
938-942): a register's bitfield block is found by stripping the trailing
instance digits from the peripheral name and joining with the register name::

    generic = peripheral.rstrip('0123456789')   # 'SPI0' -> 'SPI', 'I2C1' -> 'I2C'
    key     = f"{generic}_{register}"           # 'SPI_CR', 'GPIO_POUT', ...
    fields  = BITFIELDS.get(key)                # None -> no fields

So SPI0.CR and SPI1.CR both resolve to the shared 'SPI_CR' block; every GPIO
port shares the 'GPIO_*' blocks; UART0/UART1 share 'UART_*'; etc. Registers
with no matching key (e.g. all of SYSTEM, the SPI FOS register) carry ``{}``.

Bitfield encoding normalization
-------------------------------
v1 encodes a field's position two ways (see ``extract_bitfield``, lines
956-967):
  * ``'bits': <int>``          -- the LSB position (the field is ``width`` bits
                                  wide starting there; width may be > 1, e.g.
                                  the TPR DTP selectors are width 5 at a scalar
                                  LSB).
  * ``'bits': [lo, hi]``       -- an inclusive range whose LOW element is the
                                  LSB (v1 uses ``bits[0]`` as ``start_bit``);
                                  e.g. SPI_CR.BR is ``[8, 15]`` width 8 -> LSB 8.
Both are normalized here to ``lsb`` + ``width`` (``width`` is taken verbatim
from v1, which always matches ``hi - lo + 1`` for the ranged fields).

Output schema (registers.json)
-------------------------------
{
  "generated_from": "<source description>",
  "chip": "myshkin",
  "peripherals": {
    "<PERIPH>": {
      "description": "<str>",
      "base_addr": <int>,
      "registers": {
        "<REG>": {
          "addr": <int>,
          "size": <int>,            # width in BYTES (v1 value, verbatim)
          "type": "<str>",          # CONTROL/STATUS/DATA/CONFIG/BIAS
          "description": "<str>",
          "fields": {               # {} when the register has no bitfield block
            "<FIELD>": {
              "lsb": <int>,
              "width": <int>,
              "desc": "<str>",
              "values": {"0": "<str>", ...} | null   # null == numeric field
            }
          }
        }
      }
    }
  }
}

Determinism: addresses are ints; peripheral/register/field keys are emitted in
sorted order and enum ``values`` keys in numeric order, with ``sort_keys=False``
so the chosen ordering is stable. The same v1 input always yields byte-identical
output, so the script is safely rerunnable.

Usage::

    python3 gen_registers.py                 # writes ./registers.json
    python3 gen_registers.py -o /tmp/out.json
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
    """Resolve a (peripheral, register) pair to its BITFIELDS key.

    Faithful to v1 ``bitfields_config.get_bitfields``: strip trailing instance
    digits from the peripheral name, then join with the register name.
    """
    generic = peripheral.rstrip("0123456789")
    return f"{generic}_{register}"


def normalize_field(info: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize one v1 bitfield dict into ``{lsb, width, desc, values}``.

    Collapses v1's two ``bits`` encodings (scalar LSB vs inclusive ``[lo, hi]``
    range whose low element is the LSB) into an explicit ``lsb``.
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
