"""End-to-end test: boot the REAL server as a subprocess in sim mode and drive
a realistic bench session over plain HTTP.

Unlike test_api.py (which uses FastAPI's in-process TestClient), this launches
``server/main.py --sim`` as its own OS process on a random localhost port and
talks to it only through urllib -- the exact path a browser / curl takes.  It
proves run.sh's target (``python3 server/main.py --sim``) actually serves the
whole stack.

Stdlib only (urllib + subprocess); this host's python3 is 3.6, and we do not
want a `requests` dependency for the deploy smoke test.  Skips cleanly if
fastapi/uvicorn are not importable.
"""

import base64
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest

pytest.importorskip("fastapi", reason="fastapi not installed")
pytest.importorskip("uvicorn", reason="uvicorn not installed")

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN_PY = os.path.join(REPO_DIR, "server", "main.py")
MACROS_JSON = os.path.join(REPO_DIR, "data", "macros.json")


# ---------------------------------------------------------------------------
# tiny stdlib HTTP helpers
# ---------------------------------------------------------------------------

def _pick_free_port():
    # High random port; avoid 8061 (may be occupied by another session's server).
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


def _request(base, method, path, body=None, timeout=10.0):
    url = base + path
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
    return json.loads(raw) if raw else None


def _get(base, path, timeout=10.0):
    return _request(base, "GET", path, timeout=timeout)


def _post(base, path, body=None, timeout=10.0):
    return _request(base, "POST", path, body or {}, timeout=timeout)


def _delete(base, path, timeout=10.0):
    return _request(base, "DELETE", path, timeout=timeout)


# ---------------------------------------------------------------------------
# server subprocess fixture
# ---------------------------------------------------------------------------

@pytest.fixture
def server(tmp_path):
    port = _pick_free_port()
    base = "http://127.0.0.1:%d" % port
    # main.py has no --macros knob (the store defaults to data/macros.json), so
    # snapshot that tracked file and restore it after -- the test never leaves a
    # macro behind, even if it fails mid-way.
    macros_backup = None
    if os.path.exists(MACROS_JSON):
        with open(MACROS_JSON, "rb") as handle:
            macros_backup = handle.read()
    env = dict(os.environ)
    env["PYTHONUNBUFFERED"] = "1"
    proc = subprocess.Popen(
        [sys.executable, MAIN_PY, "--sim", "--listen", "127.0.0.1:%d" % port],
        cwd=REPO_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        _wait_ready(proc, base)
        yield base
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
        if macros_backup is not None:
            with open(MACROS_JSON, "wb") as handle:
                handle.write(macros_backup)


def _wait_ready(proc, base, timeout=25.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read().decode("utf-8", "replace") if proc.stdout else ""
            raise AssertionError("server exited early (rc=%s):\n%s"
                                 % (proc.returncode, out))
        try:
            st = _get(base, "/api/status", timeout=1.0)
        except (urllib.error.URLError, socket.timeout, ConnectionError):
            time.sleep(0.15)
            continue
        if st.get("connected") and st.get("banner_seen"):
            return st
        time.sleep(0.1)
    raise AssertionError("server never became ready on %s" % base)


# ---------------------------------------------------------------------------
# the bench session
# ---------------------------------------------------------------------------

def test_bench_session(server):
    base = server

    # 1) status
    st = _get(base, "/api/status")
    assert st["connected"] is True
    assert st["banner_seen"] is True
    assert st["state"] == "idle"

    # 2) command round-trip: 7 6 * .  ->  42
    cmd = _post(base, "/api/command", {"cmd": "7 6 * ."})
    assert cmd["ok"] is True
    assert "42" in cmd["rx"], cmd

    # 3) register write + readback (GPIO0.PDIR is writable, reset 0)
    before = _get(base, "/api/register/GPIO0/PDIR")
    assert before["addr"] == 0x4014
    w = _post(base, "/api/register/GPIO0/PDIR", {"value": 0xF0})
    assert w["value"] == 0xF0
    assert w["verified"] is True
    rb = _get(base, "/api/register/GPIO0/PDIR")
    assert rb["value"] == 0xF0

    # 4) memory write / read / erase cycle (shared RAM band)
    words = [0x11223344, 0xAABBCCDD]
    mw = _post(base, "/api/memory/write",
               {"addr": 0x10010, "words": words, "verify": True})
    assert mw["mismatches"] == []
    assert mw["written"] == 2 and mw["verified"] == 2
    mr = _post(base, "/api/memory/read",
               {"addr": 0x10010, "length": 8, "mode": 0})
    assert mr["encoding"] == "base64"
    data = base64.b64decode(mr["data"])
    # little-endian word storage
    assert data[:4] == bytes([0x44, 0x33, 0x22, 0x11])
    assert data[4:8] == bytes([0xDD, 0xCC, 0xBB, 0xAA])
    _post(base, "/api/memory/erase", {"addr": 0x10010, "length": 8})
    mr2 = _post(base, "/api/memory/read",
                {"addr": 0x10010, "length": 8, "mode": 1})
    assert base64.b64decode(mr2["data"]) == b"\x00" * 8

    # 5) flash erase / write / read-verify of page 3 (256 bytes)
    info = _get(base, "/api/flash/info")
    assert info["page_size"] == 256
    page = 3
    er = _post(base, "/api/flash/erase", {"page": page})
    assert er["ok"] is True
    payload = bytes((i * 7 + 1) & 0xFF for i in range(256))
    fw = _post(base, "/api/flash/write",
               {"page": page, "data": base64.b64encode(payload).decode()})
    assert fw["ok"] is True
    # page index 3 -> byte address 3 * 256 = 768
    fr = _post(base, "/api/flash/read", {"addr": page * 256, "length": 256})
    assert bytes.fromhex(fr["hex"]) == payload

    # 6) exec (call0) -> canned return value
    ex = _post(base, "/api/exec", {"addr": 0x8200, "args": []})
    assert ex["value"] == 0x2A
    assert "tx" in ex and "ms" in ex

    # 7) macros: save / run / delete
    assert isinstance(_get(base, "/api/macros"), list)
    macro = {"name": "e2e_blink",
             "commands": ["255 0x4004 !", "0x4000 @ h."],
             "description": "e2e smoke macro"}
    _post(base, "/api/macros", macro)
    listed = _get(base, "/api/macros")
    assert any(m["name"] == "e2e_blink" for m in listed)
    run = _post(base, "/api/macros/e2e_blink/run")
    assert run["ok"] is True
    assert len(run["results"]) == 2
    dele = _delete(base, "/api/macros/e2e_blink")
    assert dele["deleted"] is True
    assert all(m["name"] != "e2e_blink" for m in _get(base, "/api/macros"))
