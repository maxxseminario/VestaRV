# Forth dashboard (v1)

Browser GUI (port 8050) for the myshkin chip's rv4th Forth ROM: register control, terminal,
clocks, analog front end. Installed on the boards; v2 is not a drop-in replacement.
Pi setup: [`../README.md`](../README.md), plus `python3-dash python3-plotly`.

```bash
pinctrl set 18 op dh                  # BOOT low; the dashboard does not set boot mode or reset
cd ~/vestarv/tools/debug/forth_dashboard
make run                              # make stop, make restart
```

Open `http://<pi-address>:8050`, then reset the chip. If `/dev/ttyAMA0` does not open, it runs
in simulation mode with dummy values.
