"""FastAPI TestClient end-to-end tests in sim mode.

Exercises every REST endpoint plus a WS terminal round-trip against SimChip.
Skipped cleanly if fastapi/starlette cannot be imported on this host.
"""

import base64
import os
import time

import pytest

fastapi = pytest.importorskip("fastapi", reason="fastapi not installed")
from fastapi.testclient import TestClient  # noqa: E402

from server.main import create_app  # noqa: E402
from server import forth  # noqa: E402

FIXTURE_REGS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "fixtures", "registers.json")


@pytest.fixture
def client(tmp_path):
    app = create_app(sim=True, registers_path=FIXTURE_REGS,
                     macros_path=str(tmp_path / "macros.json"),
                     static_dir=str(tmp_path / "no_static"))
    with TestClient(app) as c:
        _wait_connected(c)
        yield c


def _wait_connected(client, timeout=4.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        st = client.get("/api/status").json()
        if st["connected"] and st["banner_seen"]:
            return st
        time.sleep(0.02)
    raise AssertionError("sim chip never connected: %s" % st)


# --- status / ports / connect ----------------------------------------------

def test_status(client):
    st = client.get("/api/status").json()
    assert st["connected"] is True
    assert st["state"] == "idle"
    assert st["banner_seen"] is True


def test_ports(client):
    body = client.get("/api/ports").json()
    assert "ports" in body and isinstance(body["ports"], list)


def test_reset_sim_reconnects(client):
    body = client.post("/api/reset", json={"boot_low": True}).json()
    assert body["ok"] is True
    assert body["method"] == "sim-reconnect"


# --- raw command ------------------------------------------------------------

def test_command_arithmetic(client):
    body = client.post("/api/command", json={"cmd": "5 3 + ."}).json()
    assert body["ok"] is True
    assert forth.parse_decimal(body["rx"]) == 8
    assert body["ms"] >= 0


# --- registers --------------------------------------------------------------

def test_registers_dump(client):
    body = client.get("/api/registers").json()
    assert body["chip"] == "myshkin"
    assert "GPIO0" in body["peripherals"]


def test_register_read(client):
    body = client.get("/api/register/GPIO0/PIN").json()
    assert body["addr"] == 0x4000
    assert "value" in body and "fields" in body


def test_register_write_value_and_verify(client):
    body = client.post("/api/register/GPIO0/POUT", json={"value": 255}).json()
    assert body["value"] == 255
    assert body["verified"] is True


def test_register_write_fields(client):
    body = client.post("/api/register/SPI0/CR",
                       json={"fields": {"EN": 1, "BR": 5}}).json()
    assert body["verified"] is True
    assert body["value"] == (1 | (5 << 8))
    assert body["fields"]["EN"]["value"] == 1
    assert body["fields"]["EN"]["decoded"] == "Enabled"
    assert body["fields"]["BR"]["value"] == 5


def test_register_unknown_404(client):
    r = client.get("/api/register/NOPE/NOPE")
    assert r.status_code == 404


# --- memory (ruling 1: always base64) --------------------------------------

def test_memory_write_read_ascii(client):
    words = [0x11223344, 0xAABBCCDD]
    w = client.post("/api/memory/write",
                    json={"addr": 0x10010, "words": words, "verify": True}).json()
    assert w["mismatches"] == []
    r = client.post("/api/memory/read",
                    json={"addr": 0x10010, "length": 8, "mode": 0}).json()
    assert r["encoding"] == "base64"
    data = base64.b64decode(r["data"])
    assert data[:4] == bytes([0x44, 0x33, 0x22, 0x11])  # little-endian


def test_memory_read_binary_mode(client):
    client.post("/api/memory/write",
                json={"addr": 0x10020, "words": [0x0000003E]}).json()
    r = client.post("/api/memory/read",
                    json={"addr": 0x10020, "length": 4, "mode": 1}).json()
    assert r["encoding"] == "base64"
    assert base64.b64decode(r["data"]) == bytes([0x3E, 0x00, 0x00, 0x00])


def test_memory_erase(client):
    client.post("/api/memory/write", json={"addr": 0x10030, "words": [0x12345678]})
    client.post("/api/memory/erase", json={"addr": 0x10030, "length": 4})
    r = client.post("/api/memory/read",
                    json={"addr": 0x10030, "length": 4, "mode": 1}).json()
    assert base64.b64decode(r["data"]) == b"\x00\x00\x00\x00"


# --- flash ------------------------------------------------------------------

def test_flash_info(client):
    body = client.get("/api/flash/info").json()
    assert body["page_size"] == 256
    assert body["total_bytes"] == 0x1000000
    assert body["page_count"] == 0x1000000 // 256


def test_flash_erase_write_read(client):
    # page is a page INDEX (Fable ruling): index 0x200 -> byte addr 0x20000.
    page = 0x200
    assert client.post("/api/flash/erase", json={"page": page}).json()["ok"]
    payload = bytes((i * 3) & 0xFF for i in range(256))
    w = client.post("/api/flash/write",
                    json={"page": page,
                          "data": base64.b64encode(payload).decode()}).json()
    assert w["ok"] is True
    r = client.post("/api/flash/read",
                    json={"addr": page * 256, "length": 16}).json()
    assert bytes.fromhex(r["hex"]) == payload[:16]


def test_flash_page_index_semantics(client):
    # Cross-WP bug repro (G2): erase+write page index 3 -> read at byte addr 768.
    assert client.post("/api/flash/erase", json={"page": 3}).json()["ok"]
    payload = bytes((i * 5 + 1) & 0xFF for i in range(256))
    w = client.post("/api/flash/write",
                    json={"page": 3,
                          "data": base64.b64encode(payload).decode()}).json()
    assert w["ok"] is True
    r = client.post("/api/flash/read", json={"addr": 768, "length": 16}).json()
    assert bytes.fromhex(r["hex"]) == payload[:16]


def test_flash_page_out_of_range_is_400(client):
    r = client.post("/api/flash/erase", json={"page": 0x10000})  # == page_count
    assert r.status_code == 400


# --- exec / clk (ruling 5) --------------------------------------------------

def test_exec_value_tx_ms(client):
    body = client.post("/api/exec", json={"addr": 0x8200, "args": [1, 2]}).json()
    assert body["value"] == 0x2A
    assert "tx" in body and "ms" in body


def test_clk(client):
    body = client.post("/api/clk", json={"clock_sel": 2, "time_sel": 0}).json()
    assert body["freq"] == 32768


# --- macros (ruling 6) ------------------------------------------------------

def test_macros_crud(client):
    empty = client.get("/api/macros").json()
    assert isinstance(empty, list)

    macro = {"name": "blink", "commands": ["255 0x4004 !", "0 0x4004 !"],
             "description": "toggle GPIO0"}
    client.post("/api/macros", json=macro)

    listed = client.get("/api/macros").json()
    assert any(m["name"] == "blink" and m["commands"] == macro["commands"]
               for m in listed)

    run = client.post("/api/macros/blink/run").json()
    assert run["ok"] is True
    assert len(run["results"]) == 2

    assert client.delete("/api/macros/blink").json()["deleted"] is True
    assert all(m["name"] != "blink" for m in client.get("/api/macros").json())


# --- WebSocket terminal round-trip -----------------------------------------

def test_ws_terminal_round_trip(client):
    with client.websocket_connect("/ws") as ws:
        first = ws.receive_json()
        assert first["type"] == "state"
        ws.send_json({"type": "input", "data": "5 3 + ."})
        saw_rx_with_8 = False
        for _ in range(40):
            event = ws.receive_json()
            if event["type"] == "rx" and "8" in str(event["data"]):
                saw_rx_with_8 = True
                break
        assert saw_rx_with_8
