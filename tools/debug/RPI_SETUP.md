# rv4th terminal on a Raspberry Pi 4

`rv4th_terminal.py` gives you the myshkin chip's Forth prompt over the Pi's UART.
It is the interactive version of what `rv4th_tb.vhd` does in simulation.

Hold the BOOT pin (P1.7) low at reset and the chip runs the rv4th ROM instead of
loading from SPI flash: it prints `myshkin rv4th-rom!` at 115200 8N1 and drops to
a `>` prompt. The script is a transparent pipe between the keyboard and the UART;
the chip echoes what it receives, so there is no local echo.

## Wiring

| myshkin pad | RPi header |
|---|---|
| P2.4, TX0 | pin 10, GPIO15 / RXD0 |
| P2.5, RX0 | pin 8, GPIO14 / TXD0 |
| GND | pin 6 |
| resetn, optional | pin 11, GPIO17 |
| BOOT through the PCB inverter, optional | pin 12, GPIO18 |

Both sides are 3.3 V, so no level shifter. A 1 kΩ series resistor on TX is cheap
insurance.

## Pi setup (once)

The PL011 UART is claimed by Bluetooth out of the box. Add to
`/boot/firmware/config.txt` (`/boot/config.txt` on older images):

```ini
enable_uart=1
dtoverlay=disable-bt
```

Then:

```bash
sudo usermod -aG dialout $USER
sudo apt install python3-serial python3-gpiozero   # gpiozero only for --reset-pin
sudo reboot
```

Check `/dev/ttyAMA0` exists afterwards. If characters come back doubled, the
serial login shell is still running: `sudo raspi-config` → Interface Options →
Serial Port → console off, hardware on.

## Use

```bash
python3 rv4th_terminal.py --reset-pin 17
```

| Option | Default | |
|---|---|---|
| `-p`, `--port` | `/dev/ttyAMA0` | serial device |
| `-b`, `--baud` | `115200` | baud rate |
| `--reset-pin BCM` | none | pulse resetn on start |
| `--boot-pin BCM` | `18` | held high for the session; `0` disables |
| `--log FILE` | none | append all I/O |

Without `--reset-pin`, hold BOOT and press reset by hand. Either way the banner
and `>` appear.

Enter sends LF, backspace sends DEL, Ctrl-C or Ctrl-D exits.

## Forth to try

The words the testbench exercises:

```
123 0x04C00 !      write 123 to 0x04C00
0x04C00 @ .        read it back            -> 123
-500 75689 * .     multiply                -> -37844500
3 1 clk .          measure the MCU clock
```

## When it does not work

- **Cannot open /dev/ttyAMA0** — check the two `config.txt` lines, that you
  rebooted, and that you are in `dialout`.
- **Nothing after reset** — BOOT was not low during reset, or TX/RX are not
  crossed (chip TX to Pi RX), or the baud is wrong.
