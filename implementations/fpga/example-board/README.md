# Example FPGA Board Implementation

This is a template directory for documenting an FPGA implementation of VestaRV.

## Overview

- **FPGA Board**: Example Board
- **FPGA Device**: [e.g., Xilinx Artix-7 100T, Intel Cyclone V]
- **Target Application**: [e.g., prototype, development board, demo]

## Configuration

- **Core**: VestaRV32 (RV32IMAC + Zb*)
- **ROM Size**: [e.g., 16 KiB, implemented in block RAM]
- **RAM Size**: [e.g., 32 KiB, implemented in block RAM]
- **Clock Frequency**: [e.g., 50 MHz]
- **Peripherals**:
  - GPIO: Connected to LEDs, switches, buttons
  - UART: Connected to USB-UART bridge
  - SPI: Connected to [specify]
  - [List other peripherals and their board connections]

## Pin Assignments

| Signal | FPGA Pin | Board Connection |
|--------|----------|------------------|
| CLK    | [pin]    | [description]    |
| UART_TX| [pin]    | USB-UART         |
| UART_RX| [pin]    | USB-UART         |
| LED[0] | [pin]    | LED 0            |
| ...    | ...      | ...              |

## Directory Contents

- **`docs/`** — User guide, setup instructions
- **`config/`** — Configuration files and constraint files (.xdc, .sdc)
- **`images/`** — Block diagram, pinout diagram
- **`bitstreams/`** — Pre-built bitstream files

## Building

```bash
# Synthesis tool commands
[Add vivado/quartus commands here]
```

## Programming the FPGA

```bash
# Programming commands
[Add programming instructions]
```

## Resource Utilization

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs     | -    | -         | - %         |
| FFs      | -    | -         | - %         |
| BRAM     | -    | -         | - %         |
| DSP      | -    | -         | - %         |

## Testing

[Add notes about testing procedures, demo programs, etc.]
