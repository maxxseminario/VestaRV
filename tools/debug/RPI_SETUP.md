# rv4th Terminal — RPi 4 Interactive Forth Shell

Interactive Forth terminal for the **myshkin** chip, running on a
Raspberry Pi 4 Model B.  Mirrors what the VHDL testbench
(`rv4th_tb.vhd`) does automatically, but hands control to the user so
commands can be typed manually.

---

## How it works

When the chip is reset with its **BOOT pin (P1.7) held LOW**, it enters
**rv4th-ROM mode** instead of loading from SPI flash.  In this mode the
chip:

1. Prints the banner `myshkin rv4th-rom!` over UART0 (115200 8N1).
2. Drops to a Forth REPL, showing a `>` prompt.
3. Accepts Forth words over UART, echoes them back, executes them, and
   prints any stack output before showing the next `>`.

`rv4th_terminal.py` opens the RPi's UART, switches the host terminal
into raw mode, and creates a transparent pipe:

```
keyboard → RPi UART TX → chip RX → (chip processes) → chip TX → RPi UART RX → screen
```

No local echo is applied; the chip echoes every received character.

---

## Hardware wiring

```
myshkin chip pad          RPi 4 GPIO header
─────────────────         ─────────────────────────────
P2.4  (TX0, UART out) ──► Pin 10  (GPIO15 / RXD0)
P2.5  (RX0, UART in)  ◄── Pin  8  (GPIO14 / TXD0)
GND                   ────  Pin  6  (GND)

Optional — GPIO-controlled reset:
resetn pad (active low)◄── Pin 11  (GPIO17)   ← use --reset-pin 17
```

> **Voltage levels**: Both the RPi GPIO and the chip run at 3.3 V, so
> no level shifter is needed.  If you are unsure, add a 1 kΩ series
> resistor on the TX line for protection.

---

## One-time RPi UART setup

By default, the RPi 4's full-featured PL011 UART (`/dev/ttyAMA0`) is
claimed by the Bluetooth module.  To move it to GPIO14/15:

1. Open `/boot/config.txt` (or `/boot/firmware/config.txt` on newer
   Raspberry Pi OS images):

   ```
   sudo nano /boot/config.txt
   ```

2. Add (or uncomment) these two lines:

   ```ini
   enable_uart=1
   dtoverlay=disable-bt
   ```

3. Reboot:

   ```bash
   sudo reboot
   ```

4. Verify the UART is present:

   ```bash
   ls -la /dev/ttyAMA0 /dev/serial0
   ```

5. Add yourself to the `dialout` group (if not already):

   ```bash
   sudo usermod -aG dialout $USER
   # log out and back in for the change to take effect
   ```

---

## Installation

```bash
cd /home/mseminario/vestarv/rpi
pip3 install -r requirements.txt
```

`gpiozero` is pre-installed on Raspberry Pi OS; it is only needed when
you use `--reset-pin`.

---

## Usage

```
python3 rv4th_terminal.py [options]
```

| Option | Default | Description |
|---|---|---|
| `-p`, `--port` | `/dev/ttyAMA0` | Serial port device |
| `-b`, `--baud` | `115200` | Baud rate |
| `--reset-pin BCM` | *(none)* | BCM GPIO number wired to chip's resetn; script will pulse it LOW for 1 ms to reset the chip automatically |
| `--log FILE` | *(none)* | Append all terminal I/O to FILE |

### Basic usage (manual reset)

```bash
python3 rv4th_terminal.py
```

Then hold the BOOT button on the chip and press the reset button.
You should see:

```
myshkin rv4th-rom!

>
```

### Automatic reset via GPIO

If GPIO17 (pin 11) is wired to the chip's resetn pad:

```bash
python3 rv4th_terminal.py --reset-pin 17
```

The script asserts reset, waits 1 ms, then releases it.  The chip must
have its BOOT pin tied LOW (or held by a button) at the same time.

### Log a session

```bash
python3 rv4th_terminal.py --log session_2026-03-17.log
```

---

## Forth commands quick reference

These are the commands exercised by the simulation test-bench
(`rv4th_tb.vhd`):

| Command | Effect | Expected output |
|---|---|---|
| `123 0x04C00 !` | Write `123` to address `0x04C00` | *(no output, just `>`)* |
| `0x04C00 @ .` | Fetch `0x04C00` and print | `123` |
| `124 0x04B00 !` | Write `124` to address `0x04B00` | *(no output, just `>`)* |
| `0x04B00 @ .` | Fetch `0x04B00` and print | `124` |
| `-500 75689 * .` | Multiply and print | `-37844500` |
| `3 1 clk .` | Measure / print MCU clock frequency | *freq value* |

---

## Key bindings

| Key | Action |
|---|---|
| Any printable character | Sent verbatim to chip |
| **Enter** | Sends `\n` (LF) — Forth line terminator |
| **Backspace** / **Del** | Sends `DEL` (0x7F) to chip |
| **Ctrl-C** | Exit the terminal cleanly |
| **Ctrl-D** | Exit the terminal cleanly |

---

## Troubleshooting

**`[error] Cannot open /dev/ttyAMA0`**
- Check `ls /dev/ttyAMA* /dev/serial*`
- Ensure `enable_uart=1` and `dtoverlay=disable-bt` are in
  `/boot/config.txt` and you have rebooted.
- Ensure you are in the `dialout` group.

**Nothing appears after reset**
- Confirm the BOOT pin (P1.7) was held LOW during reset.
- Check TX/RX wiring — remember it is a crossover (chip TX → RPi RX).
- Check baud rate: should be 115200.

**Characters appear doubled on screen**
- The chip is echoing characters AND something else is echoing locally.
  Disable serial console on the RPi (`sudo raspi-config` → Interface
  Options → Serial Port → disable login shell, keep hardware enabled).

**`gpiozero` not found**
```bash
sudo apt install python3-gpiozero
```
