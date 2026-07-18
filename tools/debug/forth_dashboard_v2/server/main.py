"""FastAPI application: the frozen REST contract + the single /ws hub.

Run directly (``python3 server/main.py --sim``) or via uvicorn.  create_app()
is a factory so tests can build a sim-mode app with custom register/macro paths.

Serial rule (contract): REST handlers NEVER touch pyserial.  They enqueue on the
one SerialManager and await its Future; blocking bulk ops (memops) run in a
thread executor so the event loop stays free.  The WS terminal enqueues raw
lines through the same queue.  One queue = no interleaved transactions.
"""

import argparse
import asyncio
import base64
import functools
import os
import sys
import threading
import time
from typing import Any, Dict, List, Optional, Union

# Allow "python3 server/main.py" (script) as well as "python3 -m server.main".
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect  # noqa: E402
from fastapi.responses import HTMLResponse, JSONResponse  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from server import forth, memops  # noqa: E402
from server.macros import MacroStore  # noqa: E402
from server.registers import (RegisterMap, RegisterNotFound,  # noqa: E402
                              RegistersUnavailable)
from server.serial_manager import SerialManager, list_ports  # noqa: E402
from server.sim_chip import SimChip  # noqa: E402


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

IntLike = Union[int, str]


def coerce_int(value: IntLike) -> int:
    """Accept an int or a string like '0x4000' / '123' and return an int."""
    if isinstance(value, int):
        return value
    return int(str(value), 0)


class ConnectBody(BaseModel):
    port: Optional[str] = None
    baud: Optional[int] = None


class ResetBody(BaseModel):
    boot_low: Optional[bool] = True


class CommandBody(BaseModel):
    cmd: str


class RegisterWriteBody(BaseModel):
    value: Optional[IntLike] = None
    fields: Optional[Dict[str, IntLike]] = None


class MemReadBody(BaseModel):
    addr: IntLike
    length: IntLike
    mode: int = 0


class MemWriteBody(BaseModel):
    addr: IntLike
    words: List[IntLike]
    verify: bool = True


class MemEraseBody(BaseModel):
    addr: IntLike
    length: IntLike


class FlashEraseBody(BaseModel):
    page: IntLike


class FlashWriteBody(BaseModel):
    page: IntLike
    data: Optional[str] = None       # base64
    data_hex: Optional[str] = None   # hex string (alternative)


class FlashReadBody(BaseModel):
    addr: IntLike
    length: IntLike


class ExecBody(BaseModel):
    addr: IntLike
    args: List[IntLike] = []


class ClkBody(BaseModel):
    clock_sel: int
    time_sel: int = 0


class MacroBody(BaseModel):
    name: str
    commands: List[str] = []
    description: str = ""


# ---------------------------------------------------------------------------
# WebSocket hub
# ---------------------------------------------------------------------------

class WSHub:
    """Fan-out of serial events to every connected WebSocket.

    The serial manager runs on its own thread and calls on_event() there.  Each
    WebSocket registers its OWN event loop + asyncio.Queue (created on that
    loop), so events are delivered with call_soon_threadsafe to the exact loop
    serving each client -- correct even when clients run on different loops
    (as the TestClient does, one thread/loop per websocket).
    """

    def __init__(self) -> None:
        self._subs = {}  # type: Dict[int, tuple]
        self._lock = threading.Lock()

    def register(self, loop: asyncio.AbstractEventLoop) -> "asyncio.Queue":
        queue = asyncio.Queue(maxsize=1000)  # type: asyncio.Queue
        with self._lock:
            self._subs[id(queue)] = (loop, queue)
        return queue

    def unregister(self, queue: "asyncio.Queue") -> None:
        with self._lock:
            self._subs.pop(id(queue), None)

    def on_event(self, event: Dict[str, Any]) -> None:
        with self._lock:
            subs = list(self._subs.values())
        for loop, queue in subs:
            try:
                loop.call_soon_threadsafe(_safe_put, queue, event)
            except RuntimeError:
                pass  # loop closed


def _safe_put(queue: "asyncio.Queue", event: Dict[str, Any]) -> None:
    try:
        queue.put_nowait(event)
    except asyncio.QueueFull:
        pass


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------

def create_app(sim: bool = False, port: str = "/dev/ttyAMA0", baud: int = 115200,
               registers_path: Optional[str] = None,
               macros_path: Optional[str] = None,
               reset_pin: Optional[int] = None,
               static_dir: Optional[str] = None,
               autoconnect: bool = True) -> FastAPI:
    app = FastAPI(title="Forth Dashboard v2", version="2.0")

    if sim:
        def factory(p: str, b: int):
            return SimChip(registers_path=registers_path)
    else:
        def factory(p: str, b: int):
            from server.serial_manager import RealSerial
            return RealSerial(p, b)

    manager = SerialManager(factory)
    hub = WSHub()
    macros = MacroStore(macros_path)

    app.state.manager = manager
    app.state.hub = hub
    app.state.macros = macros
    app.state.reset_pin = reset_pin
    app.state.registers_path = registers_path
    app.state.default_port = port
    app.state.default_baud = baud
    app.state.sim = sim
    app.state.reg_cache = {}          # (periph,reg) -> last value
    app.state.register_map = None     # lazy

    # -- lifecycle ---------------------------------------------------------

    @app.on_event("startup")
    def _startup() -> None:
        manager.add_listener(hub.on_event)
        manager.start()
        if autoconnect:
            manager.connect(port, baud)

    @app.on_event("shutdown")
    def _shutdown() -> None:
        manager.stop()

    # -- helpers -----------------------------------------------------------

    def get_register_map() -> RegisterMap:
        if app.state.register_map is None:
            app.state.register_map = RegisterMap.load(registers_path)
        return app.state.register_map

    async def run_command(command: str, timeout: Optional[float] = None) -> str:
        # wrap_future/run_in_executor bind to the *running* request loop.
        future = manager.submit(command, timeout=timeout)
        return await asyncio.wrap_future(future)

    async def in_executor(func, *args, **kwargs):
        call = functools.partial(func, *args, **kwargs)
        return await asyncio.get_event_loop().run_in_executor(None, call)

    async def wait_connected(timeout: float = 2.0) -> Dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if manager.connected:
                break
            await asyncio.sleep(0.02)
        return manager.status()

    # -- connection / status ----------------------------------------------

    @app.get("/api/status")
    def api_status() -> Dict[str, Any]:
        return manager.status()

    @app.get("/api/ports")
    def api_ports() -> Dict[str, Any]:
        return {"ports": list_ports()}

    @app.post("/api/connect")
    async def api_connect(body: ConnectBody) -> Dict[str, Any]:
        manager.connect(body.port or port, body.baud or baud)
        return await wait_connected()

    @app.post("/api/disconnect")
    def api_disconnect() -> Dict[str, Any]:
        manager.disconnect()
        return manager.status()

    @app.post("/api/reset")
    async def api_reset(body: ResetBody) -> Dict[str, Any]:
        if app.state.sim:
            manager.disconnect()
            manager.connect(port, baud)
            status = await wait_connected()
            return {"ok": True, "method": "sim-reconnect", "status": status}
        method, ok = _gpio_reset(app.state.reset_pin, bool(body.boot_low))
        return {"ok": ok, "method": method, "status": manager.status()}

    # -- raw command passthrough ------------------------------------------

    @app.post("/api/command")
    async def api_command(body: CommandBody) -> Dict[str, Any]:
        start = time.monotonic()
        try:
            rx = await run_command(body.cmd)
        except Exception as exc:  # noqa: BLE001
            return JSONResponse(status_code=200, content={
                "tx": body.cmd, "rx": "", "ok": False,
                "ms": round((time.monotonic() - start) * 1000, 1),
                "error": str(exc)})
        return {"tx": body.cmd, "rx": rx, "ok": True,
                "ms": round((time.monotonic() - start) * 1000, 1)}

    # -- registers ---------------------------------------------------------

    @app.get("/api/registers")
    def api_registers() -> Dict[str, Any]:
        try:
            return get_register_map().raw()
        except RegistersUnavailable as exc:
            raise HTTPException(status_code=503, detail=str(exc))

    @app.get("/api/register/{periph}/{reg}")
    async def api_register_read(periph: str, reg: str,
                                cached: bool = False) -> Dict[str, Any]:
        try:
            rmap = get_register_map()
            addr = rmap.address(periph, reg)
        except RegistersUnavailable as exc:
            raise HTTPException(status_code=503, detail=str(exc))
        except RegisterNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc))
        key = (periph, reg)
        if cached and key in app.state.reg_cache:
            value = app.state.reg_cache[key]
        else:
            try:
                text = await run_command(forth.build_read_hex(addr))
                value = forth.parse_hex_word(text)
            except Exception as exc:  # noqa: BLE001
                raise HTTPException(status_code=502, detail=str(exc))
            app.state.reg_cache[key] = value
        return {"addr": addr, "value": value,
                "fields": rmap.unpack_fields(periph, reg, value)}

    @app.post("/api/register/{periph}/{reg}")
    async def api_register_write(periph: str, reg: str,
                                 body: RegisterWriteBody) -> Dict[str, Any]:
        try:
            rmap = get_register_map()
            addr = rmap.address(periph, reg)
        except RegistersUnavailable as exc:
            raise HTTPException(status_code=503, detail=str(exc))
        except RegisterNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc))

        try:
            if body.value is not None:
                new_value = forth.to_u32(coerce_int(body.value))
            elif body.fields is not None:
                current = forth.parse_hex_word(
                    await run_command(forth.build_read_hex(addr)))
                fields = {k: coerce_int(v) for k, v in body.fields.items()}
                new_value = rmap.pack_fields(periph, reg, fields, base=current)
            else:
                raise HTTPException(status_code=400,
                                    detail="provide 'value' or 'fields'")
            await run_command(forth.build_write(addr, new_value))
            read_back = forth.parse_hex_word(
                await run_command(forth.build_read_hex(addr)))
        except HTTPException:
            raise
        except RegisterNotFound as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))

        app.state.reg_cache[(periph, reg)] = read_back
        return {"addr": addr, "value": read_back,
                "verified": read_back == new_value,
                "fields": rmap.unpack_fields(periph, reg, read_back)}

    # -- memory ------------------------------------------------------------

    @app.post("/api/memory/read")
    async def api_memory_read(body: MemReadBody) -> Dict[str, Any]:
        # Fable ruling 1: always base64 (ASCII-hex reads are decoded to raw
        # bytes server-side by memops before base64-encoding).
        try:
            result = await in_executor(
                memops.read_memory, manager, coerce_int(body.addr),
                coerce_int(body.length), body.mode)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))
        return {"addr": result["addr"], "length": result["length"],
                "mode": result["mode"], "encoding": "base64",
                "data": result["base64"]}

    @app.post("/api/memory/write")
    async def api_memory_write(body: MemWriteBody) -> Dict[str, Any]:
        words = [coerce_int(w) for w in body.words]
        try:
            return await in_executor(
                memops.write_memory, manager, coerce_int(body.addr),
                words, body.verify)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))

    @app.post("/api/memory/erase")
    async def api_memory_erase(body: MemEraseBody) -> Dict[str, Any]:
        try:
            return await in_executor(
                memops.erase_memory, manager, coerce_int(body.addr),
                coerce_int(body.length))
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))

    # -- flash -------------------------------------------------------------

    @app.post("/api/flash/erase")
    async def api_flash_erase(body: FlashEraseBody) -> Dict[str, Any]:
        # body.page is a page INDEX (0..page_count-1); memops validates + *256.
        try:
            return await in_executor(memops.flash_erase, manager,
                                     coerce_int(body.page))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))

    @app.post("/api/flash/write")
    async def api_flash_write(body: FlashWriteBody) -> Dict[str, Any]:
        if body.data is not None:
            data = base64.b64decode(body.data)
        elif body.data_hex is not None:
            data = bytes.fromhex(body.data_hex)
        else:
            raise HTTPException(status_code=400,
                                detail="provide 'data' (base64) or 'data_hex'")
        try:
            return await in_executor(memops.flash_write_page, manager,
                                     coerce_int(body.page), data)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))

    @app.get("/api/flash/info")
    def api_flash_info() -> Dict[str, Any]:
        return memops.flash_info()

    @app.post("/api/flash/read")
    async def api_flash_read(body: FlashReadBody) -> Dict[str, Any]:
        try:
            return await in_executor(memops.flash_read, manager,
                                     coerce_int(body.addr), coerce_int(body.length))
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))

    # -- exec / clk --------------------------------------------------------

    @app.post("/api/exec")
    async def api_exec(body: ExecBody) -> Dict[str, Any]:
        # Fable ruling 5: response is exactly {value, tx, ms}.
        addr = coerce_int(body.addr)
        args = [coerce_int(a) for a in body.args]
        command = forth.build_exec(addr, args)
        start = time.monotonic()
        try:
            rx = await run_command(command)
            value = forth.parse_decimal(rx)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))
        return {"value": value, "tx": command,
                "ms": round((time.monotonic() - start) * 1000, 1)}

    @app.post("/api/clk")
    async def api_clk(body: ClkBody) -> Dict[str, Any]:
        command = forth.build_clk(body.clock_sel, body.time_sel)
        try:
            rx = await run_command(command)
            freq = forth.parse_decimal(rx)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc))
        return {"clock_sel": body.clock_sel, "time_sel": body.time_sel,
                "freq": freq}

    # -- macros ------------------------------------------------------------

    @app.get("/api/macros")
    def api_macros_list() -> List[Dict[str, Any]]:
        # Fable ruling 6: GET returns a JSON ARRAY of {name, commands, description}.
        return macros.list()

    @app.post("/api/macros")
    def api_macros_upsert(body: MacroBody) -> Dict[str, Any]:
        return macros.upsert(body.name, body.commands, body.description)

    @app.delete("/api/macros/{name}")
    def api_macros_delete(name: str) -> Dict[str, Any]:
        return {"deleted": macros.delete(name)}

    @app.post("/api/macros/{name}/run")
    async def api_macros_run(name: str) -> Dict[str, Any]:
        macro = macros.get(name)
        if macro is None:
            raise HTTPException(status_code=404, detail="unknown macro %r" % name)
        start = time.monotonic()
        results = []  # type: List[Dict[str, Any]]
        ok = True
        for line in macro["commands"]:
            try:
                rx = await run_command(line)
                results.append({"tx": line, "rx": rx, "ok": True})
            except Exception as exc:  # noqa: BLE001
                ok = False
                results.append({"tx": line, "rx": "", "ok": False,
                                "error": str(exc)})
                break
        return {"name": name, "ok": ok, "results": results,
                "ms": round((time.monotonic() - start) * 1000, 1)}

    # -- WebSocket ---------------------------------------------------------

    @app.websocket("/ws")
    async def ws_endpoint(ws: WebSocket) -> None:
        await ws.accept()
        queue = hub.register(asyncio.get_event_loop())
        await ws.send_json({"type": "state", "data": manager.status(),
                            "ts": time.time()})

        async def pump() -> None:
            while True:
                event = await queue.get()
                await ws.send_json(event)

        pump_task = asyncio.ensure_future(pump())
        try:
            while True:
                msg = await ws.receive_json()
                if msg.get("type") == "input":
                    line = str(msg.get("data", "")).rstrip("\r\n")
                    manager.submit(line)
        except WebSocketDisconnect:
            pass
        except Exception:  # noqa: BLE001
            pass
        finally:
            pump_task.cancel()
            hub.unregister(queue)

    # -- static (mount last so /api and /ws win) ---------------------------

    _mount_static(app, static_dir)

    return app


def _mount_static(app: FastAPI, static_dir: Optional[str]) -> None:
    """Serve ./static with a plain file reader (no aiofiles/StaticFiles dep).

    Registered AFTER the API/WS routes so those always win; the catch-all only
    picks up otherwise-unmatched GETs.  Path traversal is blocked.
    """
    import mimetypes
    from fastapi import Response

    if static_dir is None:
        here = os.path.dirname(os.path.abspath(__file__))
        static_dir = os.path.join(os.path.dirname(here), "static")
    root = os.path.abspath(static_dir)
    index = os.path.join(root, "index.html")

    if not (os.path.isdir(root) and os.path.exists(index)):
        @app.get("/", response_class=HTMLResponse)
        def _root() -> str:
            return ("<h1>Forth Dashboard v2</h1>"
                    "<p>Backend up. Frontend (static/) not present yet.</p>"
                    "<p>See <code>/docs</code> for the API.</p>")
        return

    def _read(rel: str):
        target = os.path.abspath(os.path.join(root, rel))
        if not (target == root or target.startswith(root + os.sep)):
            raise HTTPException(status_code=404, detail="not found")
        if os.path.isdir(target):
            target = os.path.join(target, "index.html")
        if not os.path.isfile(target):
            raise HTTPException(status_code=404, detail="not found")
        with open(target, "rb") as handle:
            body = handle.read()
        media = mimetypes.guess_type(target)[0] or "application/octet-stream"
        return Response(content=body, media_type=media)

    @app.get("/")
    def _serve_index():
        return _read("index.html")

    @app.get("/{path:path}")
    def _serve_path(path: str):
        return _read(path)


def _gpio_reset(reset_pin: Optional[int], boot_low: bool):
    """Pulse the chip's active-low resetn via gpiozero.  (method, ok)."""
    if reset_pin is None:
        return ("no-reset-pin", False)
    try:
        from gpiozero import OutputDevice  # type: ignore
    except ImportError:
        return ("gpiozero-missing", False)
    try:
        rst = OutputDevice(reset_pin, active_high=False, initial_value=True)
        # 1 ms assert is enough; use a plain busy check rather than sleep-import.
        end = time.monotonic() + 0.001
        while time.monotonic() < end:
            pass
        rst.off()
        rst.close()
        return ("gpio-pulse", True)
    except Exception as exc:  # noqa: BLE001
        return ("gpio-error: %s" % exc, False)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_listen(value: str):
    if ":" in value:
        host, _, port = value.rpartition(":")
        return host or "0.0.0.0", int(port)
    return "0.0.0.0", int(value)


def main() -> None:
    parser = argparse.ArgumentParser(description="Forth Dashboard v2 backend")
    parser.add_argument("--sim", action="store_true",
                        help="run against the in-process SimChip (no hardware)")
    parser.add_argument("--port", default="/dev/ttyAMA0", help="serial port")
    parser.add_argument("--baud", type=int, default=115200, help="baud rate")
    parser.add_argument("--listen", default="0.0.0.0:8060", help="host:port")
    parser.add_argument("--reset-pin", type=int, default=None,
                        help="BCM GPIO wired to the chip resetn (optional)")
    args = parser.parse_args()

    host, listen_port = _parse_listen(args.listen)
    app = create_app(sim=args.sim, port=args.port, baud=args.baud,
                     reset_pin=args.reset_pin)

    import uvicorn
    uvicorn.run(app, host=host, port=listen_port)


if __name__ == "__main__":
    main()
