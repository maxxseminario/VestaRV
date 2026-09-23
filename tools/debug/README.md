# Myshkin Forth mode from a Raspberry Pi 4

## Pi setup (once)

Add to `/boot/firmware/config.txt` (`/boot/config.txt` on older images):

```ini
enable_uart=1
dtoverlay=disable-bt
```

Then:

```bash
sudo raspi-config nonint do_serial_cons 1   # serial console off
sudo raspi-config nonint do_serial_hw 0     # UART on
sudo systemctl disable --now hciuart
sudo usermod -aG dialout,gpio $USER
sudo apt install python3-serial python3-gpiozero
sudo reboot
```

For the GUI, also:

```bash
python3 -m venv --system-site-packages ~/fdash
~/fdash/bin/pip install -r ~/vestarv/tools/debug/forth_dashboard_v2/requirements.txt
```

## Terminal

```bash
cd ~/vestarv/tools/debug
python3 rv4th_terminal.py --reset-pin 17
```

The script puts the chip in Forth mode, resets it, and you should see:

```
myshkin rv4th-rom!

>
```

Type Forth at the prompt, e.g. `-500 75689 * .` prints `-37844500`. Ctrl-C exits.

## GUI

```bash
pinctrl set 18 op dh    # Forth mode; the GUI doesn't set this itself
cd ~/vestarv/tools/debug/forth_dashboard_v2
PYTHON=~/fdash/bin/python3 ./run.sh --port /dev/ttyAMA0 --reset-pin 17
```

Open `http://<pi-address>:8060` and press Reset. The same banner and `>` prompt appear in
the terminal panel. Don't send `0 echo`; the GUI needs the chip's echo to work.
