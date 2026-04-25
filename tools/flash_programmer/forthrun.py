#!/usr/bin/env python3
"""
forthrun.py - Stream a *.forth script (as produced by rcf2forth.py) to the
chip's rv4th ROM interpreter over UART.

Behaves like rv4th_terminal.py for the transport layer (serial port, optional
boot-mode GPIO, optional reset GPIO) but instead of reading from the
keyboard, it reads lines from a file and sends them one at a time with a
small inter-line delay so the ROM's polling UART RX doesn't drop bytes.

Each line is sent verbatim (with a trailing '\\n'); blank lines and lines
starting with '\\' (rv4th's line-comment character) are skipped. The chip's
responses (echoes, `>` prompts, anything else) are mirrored to stdout so you
can watch progress -- and they're also captured for post-hoc inspection.

Since the final line of a typical script is `<entry> call0`, once the chip
jumps to RAM the Forth REPL never returns. forthrun stops reading from the
file after the last command, drains anything else the chip might print for
a moment, and exits.

Usage
-----
  python3 forthrun.py software/blinky/forth/blinky.forth
  python3 forthrun.py blinky.forth --port /dev/ttyAMA0 --baud 115200
  python3 forthrun.py blinky.forth --line-delay 0.015
  python3 forthrun.py blinky.forth --boot-pin 18 --reset-pin 17
  python3 forthrun.py blinky.forth --log session.log --quiet
"""

import argparse
import os
import sys
import time

try:
    import serial
except ImportError:
    print('[error] pyserial is not installed. Install with: pip3 install pyserial',
          file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Defaults (match rv4th_terminal.py)
# ---------------------------------------------------------------------------
DEFAULT_PORT = '/dev/ttyAMA0'
DEFAULT_BAUD = 115200
BOOT_MESSAGE = 'myshkin rv4th-rom!'


# ---------------------------------------------------------------------------
# Optional GPIO helpers (lifted from rv4th_terminal.py, same semantics)
# ---------------------------------------------------------------------------
def _forth_boot_pin_enable(pin):
    """Drive boot-mode GPIO HIGH (→ chip BOOT low → Forth mode). Returns
    a gpiozero device (to be closed on exit) or None."""
    try:
        from gpiozero import OutputDevice
    except ImportError:
        print('[warn] gpiozero not found - cannot control boot-mode pin.',
              file=sys.stderr)
        return None
    try:
        return OutputDevice(pin, active_high=True, initial_value=True)
    except Exception as exc:
        print(f'[warn] Cannot drive boot-mode pin GPIO{pin}: {exc}',
              file=sys.stderr)
        return None


def _gpio_reset(pin):
    """Assert active-low reset on `pin` for ~1ms, then release. True on success."""
    try:
        from gpiozero import OutputDevice
    except ImportError:
        print('[warn] gpiozero not found - cannot drive reset via GPIO.',
              file=sys.stderr)
        return False
    try:
        rst = OutputDevice(pin, active_high=False, initial_value=True)
        time.sleep(0.001)
        rst.off()
        rst.close()
        return True
    except Exception as exc:
        print(f'[warn] GPIO reset failed: {exc}', file=sys.stderr)
        return False


# ---------------------------------------------------------------------------
# File parsing
# ---------------------------------------------------------------------------
def _loadForthScript(path):
    """Return a list of command strings (no trailing newline, no blanks,
    no rv4th comments). Raises OSError on read failure."""
    with open(path, 'r') as f:
        raw = f.readlines()
    cmds = []
    for line in raw:
        s = line.rstrip('\r\n').rstrip()
        if not s:
            continue
        # rv4th comments start with '\' followed by space or end-of-line.
        # Be liberal: skip any line whose first non-space char is '\'.
        stripped = s.lstrip()
        if stripped.startswith('\\'):
            continue
        cmds.append(s)
    return cmds


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description='Stream a *.forth script (rcf2forth.py output) to the '
                    'myshkin rv4th ROM interpreter over UART.')
    parser.add_argument('ScriptFile',
        help='Path to a *.forth file (one Forth command per line; comments '
             'starting with "\\" are ignored).')
    parser.add_argument('-p', '--port', default=DEFAULT_PORT,
        help=f'Serial port (default: {DEFAULT_PORT})')
    parser.add_argument('-b', '--baud', type=int, default=DEFAULT_BAUD,
        help=f'Baud rate (default: {DEFAULT_BAUD})')
    parser.add_argument('--line-delay', type=float, default=0.020,
        help='Seconds to pause between sending lines (default: 0.020). '
             'This is the gap AFTER the trailing newline of each line, '
             'before the next line begins. Independent of --char-delay.')
    parser.add_argument('--char-delay', type=float, default=0.003,
        help='Seconds to pause between individual bytes within a line '
             '(default: 0.003 = 3 ms). At 115200 baud one byte takes '
             '~87 us; the ROM UART has no RX FIFO, so if the chip is busy '
             'echoing a byte when the next one arrives, it gets dropped. '
             'A 3 ms inter-byte gap leaves plenty of room for echo.')
    parser.add_argument('--drain-tail', type=float, default=0.5,
        help='After the last line, keep reading the UART for this many '
             'seconds so post-jump output (or a TRAP/boot banner) still '
             'makes it onto the console (default: 0.5).')
    parser.add_argument('--no-echo', action='store_true',
        help='Send "0 echo" before streaming to silence the chip\'s '
             'per-byte echo and the ">" prompt. The upload becomes silent '
             'and noticeably faster, but you cannot see line-by-line '
             'progress. Default is to leave echo ON so you can watch.')
    parser.add_argument('--boot-pin', type=int, default=None, metavar='BCM',
        help='Optional BCM GPIO pin to drive HIGH during the session '
             '(PCB-inverted to pull chip BOOT LOW -> Forth mode). Held for '
             'the whole run and released on exit.')
    parser.add_argument('--reset-pin', type=int, default=None, metavar='BCM',
        help='Optional BCM GPIO pin wired to the chip resetn pad. If set, '
             'reset is pulsed before the script is streamed.')
    parser.add_argument('--wait-boot', action='store_true',
        help='After opening the port, wait for the boot banner '
             f'"{BOOT_MESSAGE}" before streaming. Useful right after a reset.')
    parser.add_argument('--log', metavar='FILE', default=None,
        help='Append everything read from the chip (and a transcript of '
             'what was sent) to FILE.')
    parser.add_argument('-q', '--quiet', action='store_true',
        help='Do not mirror chip output to stdout (still written to --log).')
    parser.add_argument('--ignore-errors', action='store_true',
        help='By default, forthrun ABORTS on the first "?" reply from the '
             'chip. A "?" means the chip dropped a byte mid-line, which '
             'leaves a broken line that may still execute its trailing "!" '
             'with garbage stack values -- one dropped byte can do an '
             'arbitrary memory write that crashes the chip. With this flag, '
             'forthrun keeps streaming anyway. Use only for debugging.')
    args = parser.parse_args()

    # --- load the script
    if not os.path.exists(args.ScriptFile):
        print(f'[error] file not found: {args.ScriptFile}', file=sys.stderr)
        sys.exit(1)
    cmds = _loadForthScript(args.ScriptFile)
    if not cmds:
        print('[error] no executable lines in script', file=sys.stderr)
        sys.exit(1)

    print(f'[info] {args.ScriptFile}: {len(cmds)} command line(s) to send')
    print(f'[info] port={args.port} baud={args.baud} line-delay={args.line_delay}s')

    # --- open port
    try:
        ser = serial.Serial(
            port=args.port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.05,
            xonxoff=False, rtscts=False, dsrdtr=False,
        )
    except serial.SerialException as exc:
        print(f'[error] cannot open {args.port}: {exc}', file=sys.stderr)
        sys.exit(1)

    # --- optional log
    log_fh = None
    if args.log:
        try:
            log_fh = open(args.log, 'ab')
            print(f'[info] logging to {args.log}')
        except OSError as exc:
            print(f'[warn] cannot open log {args.log}: {exc}', file=sys.stderr)

    # --- optional boot/reset GPIOs
    boot_dev = None
    if args.boot_pin is not None:
        boot_dev = _forth_boot_pin_enable(args.boot_pin)
        if boot_dev:
            print(f'[info] GPIO{args.boot_pin} held HIGH (Forth mode)')
            time.sleep(0.005)
    if args.reset_pin is not None:
        print(f'[info] pulsing reset via GPIO{args.reset_pin}')
        _gpio_reset(args.reset_pin)
        # give the ROM time to print its banner
        time.sleep(0.05)

    # --- local helpers ------------------------------------------------------
    def drainAndShow(timeoutSeconds, note=None):
        """Read bytes from the chip for up to `timeoutSeconds` of silence and
        mirror them to stdout / log. Returns everything read."""
        end = time.monotonic() + timeoutSeconds
        chunks = []
        while time.monotonic() < end:
            n = ser.in_waiting
            data = ser.read(n if n > 0 else 1)
            if data:
                chunks.append(data)
                if log_fh is not None:
                    log_fh.write(data)
                    log_fh.flush()
                if not args.quiet:
                    sys.stdout.write(data.decode('ascii', errors='replace'))
                    sys.stdout.flush()
                # reset quiet-window: there's more coming
                end = time.monotonic() + timeoutSeconds
        if note and log_fh is not None:
            log_fh.write(f'\n--- {note} ---\n'.encode('ascii'))
            log_fh.flush()
        return b''.join(chunks)

    def send(line):
        """Send a line + LF, byte-by-byte with --char-delay pacing.
        After each byte we briefly drain RX so the chip's echo (if on)
        appears interleaved on the console. Returns the bytes received
        from the chip during this call so the caller can scan for '?'.
        """
        data = (line + '\n').encode('ascii')
        if log_fh is not None:
            log_fh.write(f'\n>>> {line}\n'.encode('ascii'))
            log_fh.flush()
        rx = bytearray()
        for b in data:
            ser.write(bytes([b]))
            ser.flush()
            if args.char_delay > 0:
                time.sleep(args.char_delay)
            n = ser.in_waiting
            if n:
                got = ser.read(n)
                rx.extend(got)
                if log_fh is not None:
                    log_fh.write(got); log_fh.flush()
                if not args.quiet:
                    sys.stdout.write(got.decode('ascii', errors='replace'))
                    sys.stdout.flush()
        return bytes(rx)

    # --- optionally wait for the boot banner
    if args.wait_boot:
        print(f'[info] waiting for boot banner "{BOOT_MESSAGE}" ...')
        deadline = time.monotonic() + 5.0
        seen = b''
        while time.monotonic() < deadline:
            data = ser.read(1)
            if not data:
                continue
            seen += data
            if log_fh is not None:
                log_fh.write(data); log_fh.flush()
            if not args.quiet:
                sys.stdout.write(data.decode('ascii', errors='replace'))
                sys.stdout.flush()
            if BOOT_MESSAGE.encode('ascii') in seen:
                print('\n[info] boot banner seen')
                break
        else:
            print('\n[warn] timed out waiting for boot banner; continuing anyway',
                  file=sys.stderr)

    # --- initial drain of anything sitting in RX
    drainAndShow(0.1)

    # --- silence the chip's echo+prompt ONLY if user opted in.
    # Default behaviour is to keep echo on; the per-byte pacing in send()
    # gives the ROM enough time to echo each byte without dropping the next.
    if args.no_echo:
        print('[info] disabling chip echo via "0 echo"')
        send('0 echo')
        time.sleep(0.05)
        drainAndShow(0.05)

    # --- stream lines -------------------------------------------------------
    aborted = False
    try:
        for i, line in enumerate(cmds, 1):
            rx = send(line)
            time.sleep(args.line_delay)
            # Drain any final reply (the chip's '\n' + '>' prompt).
            tail = drainAndShow(0.02)
            rx = rx + tail
            # Detect trouble in the chip's reply:
            #   (a) literal '?' (0x3F): rv4th's parse-error reply -- a
            #       dropped/extra byte made a token unparseable.
            #   (b) any non-printable / non-ASCII byte (< 0x20 except
            #       \r\n\t, or >= 0x80): the UART itself corrupted a byte.
            #       Python's errors='replace' shows these as '?' on screen
            #       but the underlying byte is not 0x3F, so we have to
            #       check the raw bytes ourselves.
            # Either way the line is broken; the trailing '!' may already
            # have done a wild memory write -> chip in undefined state.
            badByte = None
            for byteVal in rx:
                if byteVal == 0x3F:
                    badByte = ('parse-error', byteVal); break
                if byteVal >= 0x80:
                    badByte = ('uart-corruption', byteVal); break
                if byteVal < 0x20 and byteVal not in (0x09, 0x0A, 0x0D):
                    badByte = ('uart-control', byteVal); break
            if badByte is not None and not args.ignore_errors:
                kind, bv = badByte
                print(f'\n[error] chip reply on line {i}/{len(cmds)} '
                      f'contains {kind} byte 0x{bv:02X}', file=sys.stderr)
                print(f'[error]   line: {line!r}', file=sys.stderr)
                print(f'[error]   raw rx: {bytes(rx)!r}', file=sys.stderr)
                print('[error] aborting -- the chip dropped/garbled a byte. '
                      'The trailing "!" may already have written garbage '
                      'to a wild address. Try increasing --char-delay '
                      '(currently {:.4f}s) or --line-delay (currently '
                      '{:.4f}s), or use --no-echo to eliminate echo '
                      'collisions entirely.'.format(
                          args.char_delay, args.line_delay), file=sys.stderr)
                print('[error] use --ignore-errors to push through anyway.',
                      file=sys.stderr)
                aborted = True
                break
            if not args.quiet and (i % 50 == 0):
                print(f'\n[info] sent {i}/{len(cmds)} lines', file=sys.stderr)

        if not aborted:
            # Tail drain: the last line is usually `<entry> call0`, after
            # which the chip leaves the REPL. But it might still print a
            # prompt echo, a trap banner, a reboot, etc.
            drainAndShow(args.drain_tail, note='end of script')
        if not args.quiet:
            sys.stdout.write('\n')

    except KeyboardInterrupt:
        print('\n[info] interrupted', file=sys.stderr)
    finally:
        ser.close()
        if log_fh is not None:
            log_fh.close()
        if boot_dev is not None:
            try:
                boot_dev.off()
                boot_dev.close()
            except Exception:
                pass

    if aborted:
        print('[info] aborted; chip may need reset before retrying',
              file=sys.stderr)
        sys.exit(2)
    print(f'[info] done; {len(cmds)} line(s) sent')


if __name__ == '__main__':
    main()
