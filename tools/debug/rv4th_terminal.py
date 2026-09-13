#!/usr/bin/env python3
"""VestaRV: interactive Forth terminal for the myshkin chip over UART, for a Raspberry Pi 4.

Opens the RPi UART and pipes the raw-mode host terminal to the chip, which echoes its own
line. Wiring: chip P2.4/TX0 to header pin 10, P2.5/RX0 to pin 8, GND to pin 6, BOOT to pin
12 (--boot-pin), resetn to pin 11 (--reset-pin). The PCB inverts BOOT, so GPIO18 high
selects Forth mode. /boot/config.txt needs enable_uart=1 and dtoverlay=disable-bt.
"""

import argparse
import os
import select
import signal
import sys
import termios
import threading
import time
import tty

try:
    import serial
except ImportError:
    print("[error] pyserial is not installed.")
    print("        Install it with:  pip3 install pyserial")
    sys.exit(1)

# ─── Defaults ────────────────────────────────────────────────────────────────

DEFAULT_PORT = "/dev/ttyAMA0"
DEFAULT_BAUD = 115200

# Expected first message from chip after reset into Forth mode
BOOT_MESSAGE = "myshkin rv4th-rom!"

BANNER = """\
╔══════════════════════════════════════════════════════════════════════════════╗
║           rv4th Interactive Forth Terminal  —  myshkin chip                 ║
║           Raspberry Pi 4 Model B  │  115200 8N1                             ║
║           Ctrl-C to exit                                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""


# ─── Raw-terminal context manager ────────────────────────────────────────────

class RawTerminal:
    """Context manager switching stdin to raw single-character mode and restoring the original
    settings on exit, even on an exception. In raw mode characters are not buffered until Enter,
    the terminal does not echo locally, and Ctrl-C is read as '\x03' rather than raising SIGINT.
    """

    def __init__(self):
        self._fd = sys.stdin.fileno()
        self._saved = None

    def __enter__(self):
        self._saved = termios.tcgetattr(self._fd)
        tty.setraw(self._fd)
        return self

    def __exit__(self, *_):
        if self._saved is not None:
            termios.tcsetattr(self._fd, termios.TCSADRAIN, self._saved)
            self._saved = None


# ─── UART reader thread ───────────────────────────────────────────────────────

def uart_reader(ser: serial.Serial,
                stop: threading.Event,
                log_fh=None) -> None:
    """Background thread reading bytes from the chip straight to stdout, and to a log file when one
    is given. The chip echoes each character it receives and prints the result and next prompt,
    so with no local echo everything on screen comes through here.
    """
    while not stop.is_set():
        try:
            # Block for up to 100 ms, then loop to check stop flag.
            n = ser.in_waiting
            data = ser.read(n if n > 0 else 1)
            if data:
                # In raw terminal mode a bare \n only moves the cursor down;
                # it does NOT return to column 0.  Translate \n → \r\n for
                # display so the prompt always starts at the left margin.
                # The log file receives the original, untranslated bytes.
                if log_fh is not None:
                    log_fh.buffer.write(data)
                    log_fh.buffer.flush()
                sys.stdout.buffer.write(data.replace(b"\n", b"\r\n"))
                sys.stdout.buffer.flush()
        except serial.SerialException as exc:
            if not stop.is_set():
                # Use \r\n because we may still be in raw terminal mode
                sys.stdout.write(f"\r\n[uart-rx error: {exc}]\r\n")
                sys.stdout.flush()
                stop.set()
            break


# ─── Optional GPIO-controlled chip reset ─────────────────────────────────────

def gpio_reset(pin: int) -> bool:
    """Assert the chip's active-low resetn for at least 1 ms via a GPIO output, then release it;
    False if gpiozero is unavailable. The pin must reach the resetn pad, and needs a 1 kOhm series
    resistor unless both chips share the same 3.3 V rail.
    """
    try:
        from gpiozero import OutputDevice  # type: ignore
    except ImportError:
        print("[warn] gpiozero not found — cannot drive reset via GPIO.")
        print("       Install it with:  sudo apt install python3-gpiozero")
        return False

    try:
        # active_high=False  →  device.on()  pulls pin LOW  (asserts reset)
        #                       device.off() pulls pin HIGH (releases reset)
        rst = OutputDevice(pin, active_high=False, initial_value=True)
        time.sleep(0.001)   # hold reset asserted for 1 ms
        rst.off()           # release reset
        rst.close()
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] GPIO reset failed: {exc}")
        return False


# ─── GPIO boot-mode control ───────────────────────────────────────────────────

def forth_boot_pin_enable(pin: int):
    """Drive the boot-mode GPIO pin high and hold it for the session. The PCB inverts it, so GPIO
    high means BOOT low and Forth mode, and GPIO low means SPI flash boot. Returns the live
    OutputDevice so the caller can close it, or None if gpiozero is unavailable.
    """
    try:
        from gpiozero import OutputDevice  # type: ignore
    except ImportError:
        print("[warn] gpiozero not found — cannot control boot-mode pin.")
        print("       Install it with:  sudo apt install python3-gpiozero")
        print("       Manually ensure the chip's BOOT pin is held LOW during reset.")
        return None

    try:
        # initial_value=True  →  pin starts HIGH immediately
        dev = OutputDevice(pin, active_high=True, initial_value=True)
        return dev
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] Cannot drive boot-mode pin GPIO{pin}: {exc}")
        return None


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:  # noqa: C901  (complexity is intentional for a terminal app)
    parser = argparse.ArgumentParser(
        description="Interactive Forth terminal for the myshkin rv4th chip (RPi 4)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Example Forth commands:\n"
            "  123 0x04C00 !        write 123 to address 0x04C00\n"
            "  0x04C00 @ .          read from 0x04C00 and print\n"
            "  124 0x04B00 !        write 124 to address 0x04B00\n"
            "  0x04B00 @ .          read from 0x04B00 and print\n"
            "  -500 75689 * .       multiply and print  (= -37844500)\n"
            "  3 1 clk .            measure MCU clock frequency\n"
        ),
    )
    parser.add_argument(
        "-p", "--port",
        default=DEFAULT_PORT,
        help=f"Serial port device  (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "-b", "--baud",
        type=int,
        default=DEFAULT_BAUD,
        help=f"Baud rate  (default: {DEFAULT_BAUD})",
    )
    parser.add_argument(
        "--reset-pin",
        type=int,
        metavar="BCM",
        default=None,
        help=(
            "BCM GPIO number wired to the chip's resetn pad.  "
            "When specified the script will assert/release reset "
            "automatically before starting the terminal.  "
            "Requires gpiozero (sudo apt install python3-gpiozero)."
        ),
    )
    parser.add_argument(
        "--boot-pin",
        type=int,
        metavar="BCM",
        default=18,
        help=(
            "BCM GPIO number wired to the chip's BOOT mode input on the PCB "
            "(default: 18).  The script drives this pin HIGH, which the PCB "
            "inverts to pull the chip's BOOT pad LOW, selecting Forth mode.  "
            "The pin is held HIGH for the whole session and released on exit.  "
            "Pass --boot-pin 0 to disable GPIO boot-mode control entirely."
        ),
    )
    parser.add_argument(
        "--log",
        metavar="FILE",
        default=None,
        help="Append all terminal I/O to FILE for later inspection.",
    )
    args = parser.parse_args()

    # ── Banner ────────────────────────────────────────────────────────────────
    print(BANNER)
    print(f"  Port : {args.port}")
    print(f"  Baud : {args.baud}")
    if args.boot_pin:
        print(f"  Boot : GPIO{args.boot_pin} (BCM) → held HIGH → chip BOOT pin LOW → Forth mode")
    else:
        print("  Boot : GPIO boot-mode control disabled")
    if args.reset_pin is not None:
        print(f"  Reset: GPIO{args.reset_pin} (BCM)")
    if args.log:
        print(f"  Log  : {args.log}")
    print()

    # ── Open serial port ──────────────────────────────────────────────────────
    try:
        ser = serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.1,        # short read timeout so the reader thread can poll stop flag
            xonxoff=False,      # no software flow control
            rtscts=False,       # no hardware RTS/CTS
            dsrdtr=False,       # no hardware DSR/DTR
        )
    except serial.SerialException as exc:
        print(f"[error] Cannot open {args.port}: {exc}")
        print()
        print("  Troubleshooting:")
        print("  • Is the port name correct?  Try: ls /dev/ttyAMA*  or  ls /dev/serial*")
        print("  • Do you have permission?    sudo usermod -aG dialout $USER  (re-login)")
        print("  • Is the UART enabled?       Add  enable_uart=1  to /boot/config.txt")
        print("  • Is Bluetooth released?     Add  dtoverlay=disable-bt  to /boot/config.txt")
        sys.exit(1)

    # ── Optional log file ─────────────────────────────────────────────────────
    log_fh = None
    if args.log:
        try:
            log_fh = open(args.log, "ab")  # binary append
            print(f"[info] Session will be logged to '{args.log}'\n")
        except OSError as exc:
            print(f"[warn] Cannot open log file '{args.log}': {exc}\n")

    # ── Assert boot-mode pin (GPIO18 HIGH → chip BOOT LOW → Forth mode) ────────
    boot_pin_dev = None
    if args.boot_pin:
        boot_pin_dev = forth_boot_pin_enable(args.boot_pin)
        if boot_pin_dev:
            print(f"[info] GPIO{args.boot_pin} asserted HIGH — chip will boot in Forth mode.")
        # Small delay to ensure the pin is stable before reset is released
        time.sleep(0.005)

    # ── Optional GPIO reset ───────────────────────────────────────────────────
    if args.reset_pin is not None:
        print(f"[info] Asserting chip reset via GPIO{args.reset_pin}...")
        if gpio_reset(args.reset_pin):
            print("[info] Reset released.  Waiting for Forth boot message...\n")
        else:
            print("[info] GPIO reset failed.  Please reset the chip manually.\n")
    else:
        print("[info] Please reset the chip now.")
        print(f'[info] Waiting for:  "{BOOT_MESSAGE}"\n')

    # ── Shared stop event ─────────────────────────────────────────────────────
    stop = threading.Event()

    # ── Raw-terminal object (manages termios state) ───────────────────────────
    raw = RawTerminal()

    # ── Cleanup routine ───────────────────────────────────────────────────────
    def cleanup(signum=None, frame=None) -> None:  # noqa: ANN001
        """Restore terminal, close resources, and exit cleanly."""
        stop.set()
        raw.__exit__(None, None, None)   # restore terminal settings immediately
        ser.close()
        if log_fh is not None:
            log_fh.close()
        # Release the boot-mode pin (set LOW) so the chip boots normally next time
        if boot_pin_dev is not None:
            try:
                boot_pin_dev.off()   # drive LOW — chip BOOT pin returns HIGH
                boot_pin_dev.close()
            except Exception:  # noqa: BLE001
                pass
        # Use \r\n in case we were in raw mode when this is called
        print("\r\n[Disconnected]\r\n")
        # os._exit avoids any atexit handlers that might confuse the terminal
        os._exit(0)

    # Register cleanup for SIGTERM (Ctrl-C is caught in the keyboard loop below)
    signal.signal(signal.SIGTERM, cleanup)

    # ── Start UART reader thread ──────────────────────────────────────────────
    rx_thread = threading.Thread(
        target=uart_reader,
        args=(ser, stop, log_fh),
        daemon=True,
        name="uart-rx",
    )
    rx_thread.start()

    # ── Interactive keyboard loop ─────────────────────────────────────────────
    #
    # We operate in raw terminal mode so that every keystroke is read
    # immediately (no line-buffering by the OS) and is forwarded to the chip
    # without any local processing.
    #
    # The chip handles its own echo: it reads characters, buffers them until
    # it sees a newline, then echoes the whole line back followed by any
    # result and a fresh ">" prompt.  All of this arrives via the reader
    # thread and is printed to the screen.
    #
    # Key mappings:
    #   Any printable ASCII  →  sent verbatim to chip
    #   Enter (CR = \r)      →  sent as LF (\n) — Forth line terminator
    #   Backspace / DEL      →  sent as DEL (0x7F) to chip
    #   Ctrl-C  (\x03)       →  clean exit
    #   Ctrl-D  (\x04)       →  clean exit
    # ─────────────────────────────────────────────────────────────────────────

    raw.__enter__()
    try:
        while not stop.is_set():
            # select() with a short timeout lets us check the stop flag and
            # avoids blocking indefinitely when the chip is silent.
            readable, _, _ = select.select([sys.stdin], [], [], 0.2)
            if not readable:
                continue

            ch = sys.stdin.read(1)
            if not ch:
                continue

            # ── Exit keys ────────────────────────────────────────────────────
            if ch in ("\x03", "\x04"):   # Ctrl-C or Ctrl-D
                cleanup()

            # ── Enter → send LF (Forth line terminator) ───────────────────
            elif ch in ("\r", "\n"):
                ser.write(b"\n")
                ser.flush()

            # ── Backspace / DEL ───────────────────────────────────────────
            elif ch in ("\x7f", "\x08"):
                # Send DEL; most Forth implementations treat DEL as backspace
                ser.write(b"\x7f")
                ser.flush()

            # ── All other printable / control characters → passthrough ────
            else:
                try:
                    ser.write(ch.encode("ascii"))
                except UnicodeEncodeError:
                    # Non-ASCII key (e.g. arrow key escape sequence) — skip
                    pass
                else:
                    ser.flush()

    except Exception as exc:  # noqa: BLE001
        stop.set()
        raw.__exit__(None, None, None)
        print(f"\r\n[fatal error: {exc}]\r\n")
        ser.close()
        if log_fh is not None:
            log_fh.close()
        sys.exit(1)

    # Should not be reached, but clean up just in case
    cleanup()


if __name__ == "__main__":
    main()
