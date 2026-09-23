# Talking to Myshkin in Forth from a Raspberry Pi 4

Hold BOOT low while Myshkin comes out of reset and it skips the flash, prints
`myshkin rv4th-rom!` on UART0 (115200 8N1) and gives you a `>` Forth prompt. This page
gets a Pi 4 to that prompt, from a terminal or from the browser dashboard.

## Wiring

Everything is 3.3 V, so no level shifter. TX and RX cross over.

| Myshkin | Pi 4 header |
|---|---|
| `P2.4` TX0 | pin 10 (GPIO15, RXD) |
| `P2.5` RX0 | pin 8 (GPIO14, TXD) |
| `GND` | pin 6 |
| `resetn` (optional) | pin 11 (GPIO17) |
| `BOOT` via the PCB inverter | pin 12 (GPIO18) |

The board inverts BOOT, so GPIO18 **high** means BOOT **low**, which means Forth mode.

## Setting up the Pi (once)

Add these two lines to `/boot/firmware/config.txt` (`/boot/config.txt` on older images).
They move the good UART off Bluetooth and onto the header pins:

```ini
enable_uart=1
dtoverlay=disable-bt
```

Turn off the Linux serial console. If you leave it on, every character shows up twice:

```bash
sudo raspi-config nonint do_serial_cons 1
sudo raspi-config nonint do_serial_hw 0
sudo systemctl disable --now hciuart
```

Give yourself access to the port and the GPIOs, then log out and back in:

```bash
sudo usermod -aG dialout,gpio $USER
```

Install the packages. Recent Pi OS won't let `pip` install system-wide, so the GUI gets
its own venv:

```bash
sudo apt install python3-serial python3-gpiozero picocom

# only if you want the GUI
python3 -m venv --system-site-packages ~/fdash
~/fdash/bin/pip install -r forth_dashboard_v2/requirements.txt
```

Copy this folder onto the Pi (e.g. `~/vestarv/tools/debug`), reboot, and check:

```bash
ls -l /dev/ttyAMA0 /dev/serial0   # both should exist
cat /proc/cmdline                 # should NOT mention console=serial0
```

## Terminal

```bash
cd ~/vestarv/tools/debug
python3 rv4th_terminal.py --reset-pin 17
```

The script sets BOOT, resets the chip and drops you at the prompt:

```
myshkin rv4th-rom!

>
```

Try `-500 75689 * .` and you should get `-37844500`. Ctrl-C exits and lets go of BOOT, so
the next reset boots from flash as usual.

A few options you might want:

- No reset wire? Leave off `--reset-pin` and press the reset button yourself.
- BOOT not wired to GPIO18? Add `--boot-pin 0` and hold BOOT low by hand.
- Add `--log session.log` to keep a transcript.

If the script shows nothing, take it out of the picture and use picocom:

```bash
pinctrl set 18 op dh                         # BOOT low
picocom -b 115200 /dev/ttyAMA0               # leave this running in one terminal
pinctrl set 17 op dl; pinctrl set 17 op dh   # reset, from a second terminal
```

(Ctrl-A Ctrl-X quits picocom. On older Pi OS, use `raspi-gpio` in place of `pinctrl`.)

## Browser dashboard

The dashboard can't set BOOT, so do that first:

```bash
pinctrl set 18 op dh
cd ~/vestarv/tools/debug/forth_dashboard_v2
PYTHON=~/fdash/bin/python3 ./run.sh --port /dev/ttyAMA0 --reset-pin 17
```

Open `http://<pi-address>:8060` and hit Reset. The banner shows up in the terminal panel.
From there you get registers, memory, flash, GPIO and clock panels. `./run.sh --sim`
runs it without a chip if you just want to look around.

Two things to know:

- Don't type `0 echo`. The dashboard relies on the chip echoing each character, and
  turning echo off makes every command time out until you reset.
- To start it on boot, use `myshkin-dashboard.service` and follow the steps in
  `forth_dashboard_v2/README.md`. You'll need to fix the paths in it, point it at the
  venv (`Environment=PYTHON=/home/pi/fdash/bin/python3`) and add `--reset-pin 17`.

## Nothing on the screen?

Check these, most likely first:

1. TX and RX are swapped.
2. BOOT isn't actually low. Measure the `P1.7` pad itself, not GPIO18.
3. The serial console is still on (`console=serial0` in `/proc/cmdline`).
4. `/dev/ttyAMA0` is missing, so the `config.txt` lines didn't take or you haven't
   rebooted.

More detail: `RPI_SETUP.md` for the terminal, `forth_dashboard_v2/README.md` for the
dashboard.
