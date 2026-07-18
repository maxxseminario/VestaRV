"""The serial core: one owner thread, one command queue, prompt-driven framing.

Design (per the WP2 contract):

* ONE background thread owns the transport.  Nothing else ever reads or writes
  it.  REST handlers and the WS terminal both enqueue a request and await a
  concurrent.futures.Future -> transactions never interleave.
* Framing is driven by the chip's echo + '>' prompt, NOT by sleeps.  The chip
  echoes every byte it receives; getLine() prints "\n>" whenever it wants input.
  A text transaction therefore is:  write "cmd\n"  ->  read back the echo of
  exactly those bytes  ->  read output until '>' (the prompt).  Because ASCII/
  decimal/hex output never contains '>', and the echo (which may hold the Forth
  word '>') is consumed first by exact byte count, the '>' we stop on is always
  the prompt.
* Binary reads (mr mode 1) can contain a 0x3E ('>') byte, so they are gated on a
  length-counted read (read_exact), never a prompt scan -- see memops.py.  Such
  transactions supply their own runner via submit_interaction().
* Explicit state machine, auto-reconnect with capped backoff, and an unsolicited
  output channel (bytes that arrive when no transaction is active, e.g. a reset
  banner) routed to listeners.

No time.sleep() is used anywhere in the serial path: blocking waits are the
port read timeout, queue.get(timeout=...), and stop-event waits.
"""

import enum
import threading
import time
from collections import deque
from concurrent.futures import Future
from queue import Empty, Queue
from typing import Any, Callable, Dict, List, Optional

from server import forth

# Tunables -------------------------------------------------------------------
IDLE_POLL = 0.05          # how long queue.get blocks while waiting for work (s)
IDLE_READ = 0.05          # how long an idle transport read blocks (s)
FILL_SLICE = 0.25         # max single blocking read inside a transaction (s)
BANNER_DRAIN = 0.4        # window to soak up a banner right after connect (s)
DEFAULT_TIMEOUT = 2.0     # per-command timeout (s)
DEFAULT_RETRIES = 1       # extra attempts after the first
RECONNECT_BACKOFF = (0.5, 1.0, 2.0, 4.0)  # capped exponential backoff (s)
RESYNC_QUIET_READ = 0.05  # per drain read while waiting for the line to go quiet
RESYNC_MAX_DRAIN = 64     # bound on drain reads (never spin forever)
RESYNC_PROMPT_TIMEOUT = 0.5   # deadline to re-establish the prompt after a "\n"


class ConnectionState(enum.Enum):
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    IDLE = "idle"
    BUSY = "busy"
    UNRESPONSIVE = "unresponsive"


class TransactionTimeout(Exception):
    """The chip did not complete a transaction before the deadline."""


class TransportError(Exception):
    """The underlying port failed (unplugged, closed, OS error)."""


# ---------------------------------------------------------------------------
# Transports
# ---------------------------------------------------------------------------

class RealSerial:
    """pyserial-backed transport.  pyserial is imported lazily on first use."""

    def __init__(self, port: str, baud: int) -> None:
        import serial  # lazy: unit tests never construct RealSerial
        self._serial = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0,        # non-blocking; per-read timeout set below
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        )
        self.description = port
        self.baud = baud

    def read(self, max_bytes: int, timeout: float) -> bytes:
        ser = self._serial
        try:
            ser.timeout = max(0.0, timeout)
            first = ser.read(1)          # blocks up to timeout for >=1 byte
            if not first:
                return b""
            waiting = ser.in_waiting
            if waiting and max_bytes > 1:
                return first + ser.read(min(waiting, max_bytes - 1))
            return first
        except (OSError, Exception) as exc:  # noqa: BLE001 - normalise to TransportError
            raise TransportError(str(exc))

    def write(self, data: bytes) -> None:
        try:
            self._serial.write(data)
            self._serial.flush()
        except (OSError, Exception) as exc:  # noqa: BLE001
            raise TransportError(str(exc))

    def close(self) -> None:
        try:
            self._serial.close()
        except Exception:  # noqa: BLE001
            pass


# ---------------------------------------------------------------------------
# Framing channel (exclusive to the owner thread for the life of one txn)
# ---------------------------------------------------------------------------

class Channel:
    """Deadline-bounded framing helpers over a transport.

    All reads honour a single absolute deadline; when it passes they raise
    TransactionTimeout.  Leftover bytes past a marker are retained for the next
    read within the same transaction.
    """

    def __init__(self, transport: Any, deadline: float) -> None:
        self._t = transport
        self._deadline = deadline
        self._pending = bytearray()

    def _fill(self) -> None:
        remaining = self._deadline - time.monotonic()
        if remaining <= 0:
            raise TransactionTimeout("deadline exceeded")
        data = self._t.read(4096, min(remaining, FILL_SLICE))
        if data:
            self._pending.extend(data)

    def read_exact(self, count: int) -> bytes:
        """Return exactly *count* bytes (used for length-counted binary reads)."""
        while len(self._pending) < count:
            self._fill()
        out = bytes(self._pending[:count])
        del self._pending[:count]
        return out

    def read_until(self, marker: bytes) -> bytes:
        """Return everything before the first *marker*, consuming the marker."""
        while True:
            idx = self._pending.find(marker)
            if idx >= 0:
                out = bytes(self._pending[:idx])
                del self._pending[:idx + len(marker)]
                return out
            self._fill()

    def expect_echo(self, text: str) -> None:
        """Consume and discard the chip's byte-exact echo of *text*."""
        self.read_exact(len(text.encode("latin-1")))

    def write(self, data: bytes) -> None:
        self._t.write(data)


# ---------------------------------------------------------------------------
# Requests
# ---------------------------------------------------------------------------

class _Request:
    __slots__ = ("run", "future", "tx_label", "timeout", "retries")

    def __init__(self, run: Callable[[Channel], Any], future: "Future",
                 tx_label: str, timeout: float, retries: int) -> None:
        self.run = run
        self.future = future
        self.tx_label = tx_label
        self.timeout = timeout
        self.retries = retries


def _text_runner(command: str) -> Callable[[Channel], str]:
    line = command + "\n"

    def run(ch: Channel) -> str:
        ch.write(line.encode("latin-1"))
        ch.expect_echo(line)
        out = ch.read_until(forth.PROMPT)
        return forth.strip_noise(out.decode("latin-1")).strip()

    return run


# ---------------------------------------------------------------------------
# Serial manager
# ---------------------------------------------------------------------------

class SerialManager:
    """Owns the transport thread, the command queue, and the state machine."""

    def __init__(self, transport_factory: Callable[[str, int], Any],
                 default_timeout: float = DEFAULT_TIMEOUT,
                 default_retries: int = DEFAULT_RETRIES) -> None:
        self._factory = transport_factory
        self._default_timeout = default_timeout
        self._default_retries = default_retries

        self._queue = Queue()               # type: Queue
        self._listeners = []                # type: List[Callable[[dict], None]]
        self._wants = deque()               # (action, port, baud)
        self._wants_lock = threading.Lock()

        self._transport = None              # type: Optional[Any]
        self._state = ConnectionState.DISCONNECTED
        self._desired_connected = False
        self._port = None                   # type: Optional[str]
        self._baud = None                   # type: Optional[int]
        self._banner_seen = False
        self._connect_time = None           # type: Optional[float]
        self._last_error = None             # type: Optional[str]
        self._backoff_idx = 0
        self._banner_window = ""

        self._stop = threading.Event()
        self._thread = threading.Thread(
            target=self._run, name="serial-owner", daemon=True)

    # -- lifecycle ---------------------------------------------------------

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread.is_alive():
            self._thread.join(timeout=3.0)
        self._drain_queue(RuntimeError("serial manager stopped"))
        if self._transport is not None:
            self._transport.close()
            self._transport = None

    # -- listener plumbing -------------------------------------------------

    def add_listener(self, fn: Callable[[dict], None]) -> None:
        self._listeners.append(fn)

    def remove_listener(self, fn: Callable[[dict], None]) -> None:
        if fn in self._listeners:
            self._listeners.remove(fn)

    def _emit(self, event_type: str, data: Any) -> None:
        event = {"type": event_type, "data": data, "ts": time.time()}
        for fn in list(self._listeners):
            try:
                fn(event)
            except Exception:  # noqa: BLE001 - a bad listener must not break serial
                pass

    # -- public control ----------------------------------------------------

    def connect(self, port: Optional[str] = None,
                baud: Optional[int] = None) -> None:
        port = port or self._port
        baud = baud or self._baud
        with self._wants_lock:
            self._wants.append(("connect", port, baud))

    def disconnect(self) -> None:
        with self._wants_lock:
            self._wants.append(("disconnect", None, None))

    def submit(self, command: str, timeout: Optional[float] = None,
               retries: Optional[int] = None) -> "Future":
        """Enqueue a text Forth command; Future resolves to the framed output."""
        return self._enqueue(_text_runner(command), command,
                             timeout, retries)

    def submit_interaction(self, run: Callable[[Channel], Any], tx_label: str,
                           timeout: Optional[float] = None,
                           retries: Optional[int] = None) -> "Future":
        """Enqueue a custom interaction (binary mr, flash fw handshake, ...)."""
        return self._enqueue(run, tx_label, timeout, retries)

    def _enqueue(self, run: Callable[[Channel], Any], tx_label: str,
                 timeout: Optional[float], retries: Optional[int]) -> "Future":
        future = Future()  # type: Future
        req = _Request(
            run=run,
            future=future,
            tx_label=tx_label,
            timeout=self._default_timeout if timeout is None else timeout,
            retries=self._default_retries if retries is None else retries,
        )
        self._queue.put(req)
        return future

    # -- status ------------------------------------------------------------

    @property
    def state(self) -> ConnectionState:
        return self._state

    @property
    def connected(self) -> bool:
        return self._state in (ConnectionState.IDLE, ConnectionState.BUSY,
                               ConnectionState.UNRESPONSIVE)

    @property
    def banner_seen(self) -> bool:
        return self._banner_seen

    def uptime(self) -> float:
        if self._connect_time is None or not self.connected:
            return 0.0
        return time.monotonic() - self._connect_time

    def status(self) -> Dict[str, Any]:
        return {
            "connected": self.connected,
            "state": self._state.value,
            "port": self._port,
            "baud": self._baud,
            "banner_seen": self._banner_seen,
            "uptime": round(self.uptime(), 3),
            "error": self._last_error,
        }

    # -- owner thread ------------------------------------------------------

    def _run(self) -> None:
        while not self._stop.is_set():
            self._process_wants()
            if self._transport is None:
                if self._desired_connected:
                    self._try_open()
                else:
                    self._stop.wait(IDLE_POLL)
                continue
            try:
                req = self._queue.get(timeout=IDLE_POLL)
            except Empty:
                req = None
            if req is not None:
                self._service(req)
            else:
                self._idle_read()

    def _process_wants(self) -> None:
        while True:
            with self._wants_lock:
                if not self._wants:
                    return
                action, port, baud = self._wants.popleft()
            if action == "connect":
                self._desired_connected = True
                self._port, self._baud = port, baud
                self._backoff_idx = 0
                self._close_transport()
                self._try_open()
            elif action == "disconnect":
                self._desired_connected = False
                self._close_transport()
                self._set_state(ConnectionState.DISCONNECTED)

    def _try_open(self) -> None:
        self._set_state(ConnectionState.CONNECTING)
        try:
            self._transport = self._factory(self._port, self._baud)
        except Exception as exc:  # noqa: BLE001
            self._last_error = str(exc)
            self._emit("error", "connect failed: %s" % exc)
            self._transport = None
            self._set_state(ConnectionState.DISCONNECTED)
            backoff = RECONNECT_BACKOFF[min(self._backoff_idx,
                                            len(RECONNECT_BACKOFF) - 1)]
            self._backoff_idx += 1
            self._stop.wait(backoff)      # backoff wait (interruptible, no sleep)
            return
        self._backoff_idx = 0
        self._connect_time = time.monotonic()
        self._last_error = None
        self._drain_banner()
        self._set_state(ConnectionState.IDLE)

    def _drain_banner(self) -> None:
        """Soak up any banner/prompt already sitting in the port after open."""
        deadline = time.monotonic() + BANNER_DRAIN
        while time.monotonic() < deadline:
            try:
                data = self._transport.read(4096, IDLE_READ)
            except TransportError:
                return
            if not data:
                break
            text = data.decode("latin-1", "replace")
            self._emit("rx", text)
            self._note_banner(text)

    def _service(self, req: _Request) -> None:
        # If the last command left us out of sync, re-synchronise BEFORE ever
        # sending a new command -- never resend onto a stream that may still be
        # carrying stale echo/output from a timed-out attempt.
        if self._state == ConnectionState.UNRESPONSIVE:
            try:
                if self._resync():
                    self._set_state(ConnectionState.IDLE)
                else:
                    self._last_error = "chip unresponsive (resync failed)"
                    self._emit("error", self._last_error)
                    req.future.set_exception(TimeoutError(self._last_error))
                    return  # fail fast, stay UNRESPONSIVE, do not send
            except TransportError as exc:
                self._fail_transport(req, exc)
                return

        self._set_state(ConnectionState.BUSY)
        self._emit("tx", req.tx_label)
        attempts = max(1, req.retries + 1)
        last_error = None  # type: Optional[Exception]
        for attempt in range(attempts):
            if attempt > 0:
                # Before a retry, drain the stale bytes of the timed-out attempt
                # and re-establish the prompt; if that fails, fail fast rather
                # than resend onto a corrupted stream (the retry would otherwise
                # mis-attribute late bytes to expect_echo).
                try:
                    if not self._resync():
                        last_error = TimeoutError("resync failed before retry")
                        break
                except TransportError as exc:
                    self._fail_transport(req, exc)
                    return
            deadline = time.monotonic() + req.timeout
            channel = Channel(self._transport, deadline)
            try:
                result = req.run(channel)
            except TransactionTimeout as exc:
                last_error = TimeoutError(str(exc) or "transaction timed out")
                if attempt + 1 < attempts:
                    self._emit("error", "timeout, resync+retry (%s)" % req.tx_label)
                continue
            except TransportError as exc:
                self._fail_transport(req, exc)
                return
            self._emit("rx", _display(result))
            self._note_banner(_display(result))
            req.future.set_result(result)
            self._set_state(ConnectionState.IDLE)
            return
        # every attempt failed
        self._last_error = "command failed: %s" % req.tx_label
        self._emit("error", self._last_error)
        req.future.set_exception(last_error or TimeoutError(self._last_error))
        self._set_state(ConnectionState.UNRESPONSIVE)

    def _resync(self) -> bool:
        """Recover synchronisation after a timeout.

        (1) Drain stale input until the line is quiet (bounded repeated short
        reads, stopping on the first empty read).  (2) Write a lone "\\n" to
        elicit a fresh getLine() prompt.  (3) Read until the prompt with a short
        deadline.  Returns True if the prompt was reached, False otherwise (the
        caller must then fail fast).  Propagates TransportError if the port dies.
        """
        for _ in range(RESYNC_MAX_DRAIN):
            if not self._transport.read(4096, RESYNC_QUIET_READ):
                break
        self._transport.write(b"\n")
        channel = Channel(self._transport, time.monotonic() + RESYNC_PROMPT_TIMEOUT)
        try:
            channel.read_until(forth.PROMPT)
            return True
        except TransactionTimeout:
            return False

    def _fail_transport(self, req: _Request, exc: Exception) -> None:
        self._last_error = "transport error: %s" % exc
        self._emit("error", self._last_error)
        req.future.set_exception(TransportError(str(exc)))
        self._close_transport()
        self._set_state(ConnectionState.DISCONNECTED)

    def _idle_read(self) -> None:
        try:
            data = self._transport.read(4096, IDLE_READ)
        except TransportError as exc:
            self._last_error = "transport error: %s" % exc
            self._emit("error", self._last_error)
            self._close_transport()
            self._set_state(ConnectionState.DISCONNECTED)
            return
        if data:
            text = data.decode("latin-1", "replace")
            self._emit("rx", text)
            self._note_banner(text)

    # -- helpers -----------------------------------------------------------

    def _note_banner(self, text: str) -> None:
        if not text:
            return
        self._banner_window = (self._banner_window + text)[-64:]
        if not self._banner_seen and forth.contains_banner(self._banner_window):
            self._banner_seen = True
            self._emit("info", "banner detected: chip in rv4th-ROM mode")

    def _set_state(self, new: ConnectionState) -> None:
        if new == self._state:
            return
        self._state = new
        self._emit("state", self.status())

    def _close_transport(self) -> None:
        if self._transport is not None:
            try:
                self._transport.close()
            except Exception:  # noqa: BLE001
                pass
            self._transport = None

    def _drain_queue(self, exc: Exception) -> None:
        while True:
            try:
                req = self._queue.get_nowait()
            except Empty:
                return
            if not req.future.done():
                req.future.set_exception(exc)


def _display(result: Any) -> str:
    """Human-readable form of a transaction result for the WS rx stream."""
    if isinstance(result, str):
        return result
    if isinstance(result, (bytes, bytearray)):
        preview = bytes(result[:32]).hex()
        suffix = "..." if len(result) > 32 else ""
        return "<%d bytes> %s%s" % (len(result), preview, suffix)
    return repr(result)


# ---------------------------------------------------------------------------
# Port discovery
# ---------------------------------------------------------------------------

def list_ports() -> List[Dict[str, str]]:
    """Return candidate serial ports as [{device, description}, ...]."""
    ports = []  # type: List[Dict[str, str]]
    try:
        from serial.tools import list_ports as _lp  # type: ignore
        for info in _lp.comports():
            ports.append({"device": info.device,
                          "description": info.description or info.device})
    except Exception:  # noqa: BLE001 - pyserial missing or no comports on host
        import glob
        seen = set()
        for pattern in ("/dev/ttyAMA*", "/dev/serial*", "/dev/ttyUSB*",
                        "/dev/ttyACM*", "/dev/ttyS*"):
            for dev in sorted(glob.glob(pattern)):
                if dev not in seen:
                    seen.add(dev)
                    ports.append({"device": dev, "description": dev})
    return ports
