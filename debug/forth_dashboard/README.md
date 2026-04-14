# Myshkin MCU Configuration Interface

A web-based GUI for configuring and testing the Myshkin microcontroller via UART/Forth interface.

## Overview

This application provides a comprehensive interface to all peripherals and registers of the Myshkin MCU:
- **GPIO** (4 ports × 8 pins = 32 GPIO pins)
- **Communication** (2× UART, 2× SPI, 2× I2C)
- **Timers** (2× 32-bit timers with PWM and input capture)
- **System** (Clock control, power management, interrupts, watchdog, CRC)
- **NPU** (Neural Processing Unit for ML acceleration)
- **ADCs** (10-bit SAR ADC, dual-slope ADC in AFE)
- **AFE** (Analog Front End with potentiostat and bias generators)

## File Structure

### New Files (Updated Implementation)
- **`peripherals_config.py`** - Complete Myshkin peripheral and register definitions
- **`myshkin_new.py`** - Simplified Myshkin interface using UART/Forth commands
- **`app_new.py`** - Dash app configuration
- **`layout_new.py`** - Tab-based GUI layout with auto-generated register controls
- **`callbacks_new.py`** - Callbacks for register read/write operations
- **`index_new.py`** - Main entry point for the new application
- **`assets/myshkin-styles.css`** - CSS styling for the interface

### Original Files (For Reference)
- `myshkin.py` - Original implementation with hardcoded registers
- `app.py` - Original app configuration
- `layout.py` - Original layout (single-page with custom controls)
- `callbacks.py` - Original callbacks
- `index.py` - Original entry point

## Hardware Setup

1. Connect your Myshkin chip to a Raspberry Pi 4 via UART
2. Boot the Myshkin chip into Forth mode (BOOT pin LOW)
3. The chip should be communicating over UART0 at 115,200 baud

## Software Requirements

```bash
pip install dash dash-daq numpy pyserial
```

## Running the Application

### Option 1: Run the new implementation

```bash
cd /home/mseminario/vestarv/module_dash/module_dash_uart
python3 index_new.py
```

### Option 2: Run the original implementation

```bash
python3 index.py
```

Once started, open your web browser to:
**http://localhost:8050**

Or from another computer on the same network:
**http://<raspberry-pi-ip>:8050**

## Using the Interface

### Register Controls

The GUI automatically generates appropriate controls based on register type:

1. **Control Registers** - Read/Write with numeric input
   - Used for configuration bits and control flags
   - Enter value in decimal or hex (prefix with 0x)
   - Click "Read" to fetch current value
   - Click "Write" to update register

2. **Status Registers** - Read-only display
   - Shows current register state
   - Click "Read" to refresh

3. **Bias Registers** - Sliders
   - For analog bias voltages and currents
   - Drag slider to adjust value
   - Value is written immediately on change

4. **Data Registers** - Read/Write
   - For transmit/receive data buffers
   - Enter and read data values

### Tab Organization

- **GPIO** - 4 sub-tabs for GPIO0-GPIO3
- **Communication** - 6 sub-tabs for UART0/1, SPI0/1, I2C0/1
- **Timers** - 2 sub-tabs for TIMER0/1
- **System** - Single tab for system control
- **NPU** - Neural Processing Unit configuration
- **ADC** - 2 sub-tabs for SAR ADC and AFE (DSADC)

### Forth Command Format

The interface sends Forth commands over UART:
- **Read:** `$4000 @ .` (reads address 0x4000)
- **Write:** `0xFF $4000 !` (writes 0xFF to address 0x4000)

## Peripheral Configuration

All peripheral and register definitions are in `peripherals_config.py`. This includes:
- Base addresses for all peripherals
- Register addresses and sizes
- Register types (CONTROL, STATUS, BIAS, DATA, CONFIG)
- Descriptions for each peripheral and register

To add or modify registers, edit `peripherals_config.py` and restart the application.

## Development Notes

### Register Types

```python
REGISTER_TYPES = {
    'CONTROL': 'control',  # Control register - Read/Write with buttons
    'STATUS': 'status',    # Status register - Read-only display
    'BIAS': 'bias',        # Analog bias - Sliders for tuning
    'DATA': 'data',        # Data register - Read/Write
    'CONFIG': 'config',    # Configuration - Read/Write
}
```

### Adding a New Peripheral

1. Add peripheral definition to `PERIPHERALS` dict in `peripherals_config.py`
2. Include all registers with addresses, sizes, types, and descriptions
3. Add a new tab in `layout_new.py` if needed
4. Restart the application - register controls are auto-generated!

### Simulation Mode

If the UART port is not available, the application runs in simulation mode:
- No hardware communication occurs
- Read operations return 0
- Write operations are logged but not sent
- Useful for GUI development and testing

## Troubleshooting

### UART Connection Issues

```bash
# Check if device exists
ls -l /dev/ttyUSB*

# Check permissions
sudo chmod 666 /dev/ttyUSB0

# Or add user to dialout group
sudo usermod -a -G dialout $USER
# (logout and login required)
```

### Forth Communication

- Ensure chip is in Forth boot mode (BOOT pin LOW at reset)
- Verify baud rate is 115,200
- Check for proper RX/TX wiring
- Monitor UART with: `screen /dev/ttyUSB0 115200`

### Port Already in Use

If port 8050 is busy:
```python
# Edit index_new.py, change port:
app.run(host='0.0.0.0', port=8051, debug=True)
```

## Future Enhancements

- Bit-level control for control registers (dropdowns for each bit)
- Import/export register configurations
- Register descriptions from MCU User Guide in tooltips
- Automated register scanning and comparison
- Script recording and playback
- Real-time register monitoring

## References

- MCU User Guide: `/home/mseminario/vestarv/generator/latex/MCU-User-Guide/MCU-User-Guide.pdf`
- Forth Interpreter Documentation: See User Guide Section on Forth
- Hardware Datasheet: Contact UNL ECE for Myshkin documentation
