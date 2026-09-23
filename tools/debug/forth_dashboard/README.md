# Forth dashboard (v1)

Browser GUI on port 8050 for driving the myshkin chip over UART while it runs
its rv4th Forth ROM. This is the version installed on the boards in use; keep
using it. `../forth_dashboard_v2` is a rework and is not a drop-in replacement.

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
sudo apt install python3-serial python3-dash python3-plotly
sudo reboot
```

Wiring is in `../RPI_SETUP.md`: chip TX0 to pin 10, RX0 to pin 8, grounds
together, and GPIO18 to the BOOT inverter if you want to select Forth mode from
software.

## Run

The dashboard talks to a chip that is already at the `>` prompt; it does not set
boot mode or reset the chip itself.

```bash
pinctrl set 18 op dh                  # BOOT low through the PCB inverter
cd ~/vestarv/tools/debug/forth_dashboard
make run                              # make stop, make restart
```

Open `http://<pi-address>:8050`, then reset the chip. Without hardware, or if
`/dev/ttyAMA0` will not open, it starts in simulation mode and returns dummy
values.

## What it gives you

Tabs per peripheral with bitfield-level register control, a Forth terminal
panel, clock measurement, the analog front end (potentiostat, SAR ADC,
dual-slope ADC), and a command log.
