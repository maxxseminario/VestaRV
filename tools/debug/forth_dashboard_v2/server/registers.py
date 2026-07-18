"""Load data/registers.json and provide lookup + field pack/unpack helpers.

Schema consumed (produced by WP1's gen_registers.py, verified 2026-07-18):

    {
      "chip": "myshkin",
      "peripherals": {
        "GPIO0": {
          "description": "...",
          "base_addr": 16384,
          "registers": {
            "PIN": {
              "addr": 16384, "size": 1, "type": "STATUS",
              "description": "...",
              "fields": {
                "FIELDNAME": {"lsb": 0, "width": 1, "desc": "...",
                              "values": {"0": "Disabled", "1": "Enabled"}}
              }
            }
          }
        }
      }
    }

Absence of the file is tolerated: load() raises RegistersUnavailable with a
clear message, which the API surfaces at endpoint-use time (never at import).
"""

import json
import os
from typing import Any, Dict, List, Optional

from server import forth


class RegistersUnavailable(Exception):
    """registers.json is missing or unreadable."""


class RegisterNotFound(Exception):
    """A peripheral/register name was not in the map."""


def default_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "data", "registers.json")


class RegisterMap:
    def __init__(self, data: Dict[str, Any], source: str) -> None:
        self._data = data
        self.source = source
        self._peripherals = data.get("peripherals") or {}

    # -- construction ------------------------------------------------------

    @classmethod
    def load(cls, path: Optional[str] = None) -> "RegisterMap":
        path = path or default_path()
        if not os.path.exists(path):
            raise RegistersUnavailable(
                "register map not found at %s (run data/gen_registers.py)" % path)
        try:
            with open(path) as handle:
                data = json.load(handle)
        except (OSError, ValueError) as exc:
            raise RegistersUnavailable("cannot read %s: %s" % (path, exc))
        return cls(data, path)

    # -- raw access --------------------------------------------------------

    def raw(self) -> Dict[str, Any]:
        return self._data

    def peripherals(self) -> Dict[str, Any]:
        return self._peripherals

    def get_register(self, periph: str, reg: str) -> Dict[str, Any]:
        pdef = self._peripherals.get(periph)
        if pdef is None:
            raise RegisterNotFound("unknown peripheral %r" % periph)
        rdef = (pdef.get("registers") or {}).get(reg)
        if rdef is None:
            raise RegisterNotFound("unknown register %s.%s" % (periph, reg))
        return rdef

    def address(self, periph: str, reg: str) -> int:
        rdef = self.get_register(periph, reg)
        if "addr" in rdef:
            return int(rdef["addr"])
        base = int((self._peripherals[periph]).get("base_addr", 0))
        return base + int(rdef.get("offset", 0))

    def fields(self, periph: str, reg: str) -> Dict[str, Any]:
        return self.get_register(periph, reg).get("fields") or {}

    # -- field pack / unpack ----------------------------------------------

    def unpack_fields(self, periph: str, reg: str, value: int) -> Dict[str, Any]:
        """Decode a register value into per-field {value, decoded, lsb, width}."""
        value = forth.to_u32(value)
        out = {}  # type: Dict[str, Any]
        for name, fdef in self.fields(periph, reg).items():
            lsb = int(fdef["lsb"])
            width = int(fdef["width"])
            raw = (value >> lsb) & ((1 << width) - 1)
            values = fdef.get("values") or {}
            out[name] = {
                "value": raw,
                "decoded": values.get(str(raw)),
                "lsb": lsb,
                "width": width,
            }
        return out

    def pack_fields(self, periph: str, reg: str,
                    field_values: Dict[str, int], base: int = 0) -> int:
        """Merge field values over *base*, returning the new register word."""
        result = forth.to_u32(base)
        defs = self.fields(periph, reg)
        for name, val in field_values.items():
            fdef = defs.get(name)
            if fdef is None:
                raise RegisterNotFound(
                    "unknown field %s.%s.%s" % (periph, reg, name))
            lsb = int(fdef["lsb"])
            width = int(fdef["width"])
            mask = ((1 << width) - 1) << lsb
            result = (result & ~mask) | ((int(val) << lsb) & mask)
        return forth.to_u32(result)

    def list_registers(self, periph: str) -> List[str]:
        pdef = self._peripherals.get(periph)
        if pdef is None:
            raise RegisterNotFound("unknown peripheral %r" % periph)
        return list((pdef.get("registers") or {}).keys())
