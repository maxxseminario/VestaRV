# Myshkin MCU Configuration Interface

Web-based GUI for configuring and interacting with the Myshkin microcontroller via UART.

## Quick Start

```bash
make run        # Start the application
make stop       # Stop the application
make restart    # Restart the application
```

Open browser to http://localhost:8050

## Requirements

- Python 3.7+
- Dash, plotly, dash-daq
- pyserial (for hardware communication)

## Hardware Setup

- Connect to Raspberry Pi 4 UART: `/dev/ttyAMA0` at 115200 baud
- See `rpi/rv4th_terminal.py` for GPIO wiring details

## Features

- Tab-based interface for all MCU peripherals
- Bitfield-level register control with descriptions
- Live Forth command terminal with color-coded output
- Clock frequency measurement
- Analog frontend (Potentiostat, SAR ADC, Delta-Sigma ADC) configuration
- Command logging to file

## Development

Run in simulation mode (no hardware required):
```bash
python3 index.py
```
