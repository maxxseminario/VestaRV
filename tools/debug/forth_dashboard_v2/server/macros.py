"""JSON-file-backed macro store (named Forth snippet library, feature F9).

A macro is {name, commands: [str, ...], description} (Fable ruling 6).
Persistence is a single JSON file (data/macros.json by default); the store
tolerates the file being absent (empty library) and writes atomically.  No
serial access here -- running a macro is the API layer enqueuing each command
line through the serial manager like any other command.
"""

import json
import os
import threading
from typing import Any, Dict, List, Optional


def default_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "data", "macros.json")


class MacroStore:
    def __init__(self, path: Optional[str] = None) -> None:
        self._path = path or default_path()
        self._lock = threading.Lock()
        self._macros = {}  # type: Dict[str, Dict[str, Any]]
        self._load()

    # -- persistence -------------------------------------------------------

    def _load(self) -> None:
        if not os.path.exists(self._path):
            self._macros = {}
            return
        try:
            with open(self._path) as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            self._macros = {}
            return
        # Accept either {"macros": [...]} or a bare list/dict for resilience.
        items = data.get("macros") if isinstance(data, dict) else data
        self._macros = {}
        for entry in (items or []):
            if isinstance(entry, dict) and entry.get("name"):
                self._macros[entry["name"]] = _normalise(entry)

    def _save(self) -> None:
        os.makedirs(os.path.dirname(self._path), exist_ok=True)
        tmp = self._path + ".tmp"
        with open(tmp, "w") as handle:
            json.dump({"macros": list(self._macros.values())}, handle, indent=2)
        os.replace(tmp, self._path)

    # -- CRUD --------------------------------------------------------------

    def list(self) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._macros.values())

    def get(self, name: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            return self._macros.get(name)

    def upsert(self, name: str, commands: List[str],
               description: str = "") -> Dict[str, Any]:
        if not name:
            raise ValueError("macro name is required")
        with self._lock:
            macro = {"name": name, "commands": list(commands),
                     "description": description}
            self._macros[name] = macro
            self._save()
            return macro

    def delete(self, name: str) -> bool:
        with self._lock:
            if name in self._macros:
                del self._macros[name]
                self._save()
                return True
            return False


def _normalise(entry: Dict[str, Any]) -> Dict[str, Any]:
    """Coerce a stored/legacy macro entry into {name, commands, description}."""
    commands = entry.get("commands")
    if commands is None:
        body = entry.get("body", "")            # tolerate the old single-body form
        commands = [line for line in str(body).splitlines() if line.strip()]
    return {
        "name": entry["name"],
        "commands": list(commands),
        "description": entry.get("description", ""),
    }
