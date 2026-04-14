"""
Myshkin MCU Peripheral Configuration
=====================================
This module contains the complete peripheral and register map for the Myshkin chip.
Extracted from MCU-User-Guide.pdf

Peripheral List:
- GPIO0, GPIO1, GPIO2, GPIO3 (4x GPIO ports, 8 pins each = 32 total)
- SPI0, SPI1 (2x SPI interfaces)
- UART0, UART1 (2x UART interfaces)
- TIMER0, TIMER1 (2x 32-bit timers with PWM)
- SYSTEM (Clock control, power management, interrupts, watchdog, DCO, CRC)
- NPU (Neural Processing Unit)
- POTENTIOSTAT (Potentiostat with DACs and bias generators)
- SARADC (10-bit SAR ADC)
- DSADC (Delta-Sigma ADC with bias generators)
- I2C0, I2C1 (2x I2C interfaces)
"""

# Peripheral base addresses
PERIPHERAL_BASES = {
    'GPIO0':   0x4000,
    'GPIO1':   0x4100,
    'SPI0':    0x4200,
    'SPI1':    0x4300,
    'UART0':   0x4400,
    'UART1':   0x4500,
    'TIMER0':  0x4600,
    'TIMER1':  0x4700,
    'GPIO2':   0x4800,
    'SYSTEM':  0x4900,
    'NPU':     0x4A00,
    'SARADC':      0x4B00,
    'POTENTIOSTAT': 0x4C00,
    'DSADC':       0x4C00,
    'GPIO3':   0x4D00,
    'I2C0':    0x4E00,
    'I2C1':    0x4F00,
}

# Register types for UI generation
REGISTER_TYPES = {
    'CONTROL': 'control',      # Control register - use dropdowns for each bit
    'STATUS': 'status',        # Status register - read-only, display values
    'BIAS': 'bias',           # Analog bias - use sliders
    'DATA': 'data',           # Data register
    'CONFIG': 'config',        # Configuration register
}

# Complete peripheral definitions
# Format: {peripheral_name: {registers: [...], description: "..."}}

PERIPHERALS = {
    'GPIO0': {
        'description': 'General Purpose I/O Port 0 (8 pins)',
        'base_addr': 0x4000,
        'registers': {
            'PIN': {'addr': 0x4000, 'size': 1, 'type': 'STATUS', 'description': 'GPIO read pin register'},
            'POUT': {'addr': 0x4004, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive register'},
            'POUTS': {'addr': 0x4008, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive set register'},
            'POUTC': {'addr': 0x400C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive clear register'},
            'POUTT': {'addr': 0x4010, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive toggle register'},
            'PDIR': {'addr': 0x4014, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO pin direction register'},
            'PREN': {'addr': 0x4018, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO resistor enable register'},
            'PSEL': {'addr': 0x401C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO peripheral select register'},
            'PIF': {'addr': 0x4020, 'size': 1, 'type': 'STATUS', 'description': 'GPIO interrupt flag register'},
            'PIES': {'addr': 0x4024, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt edge select register'},
            'PIE': {'addr': 0x4028, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt enable register'},
        }
    },
    
    'GPIO1': {
        'description': 'General Purpose I/O Port 1 (8 pins)',
        'base_addr': 0x4100,
        'registers': {
            'PIN': {'addr': 0x4100, 'size': 1, 'type': 'STATUS', 'description': 'GPIO read pin register'},
            'POUT': {'addr': 0x4104, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive register'},
            'POUTS': {'addr': 0x4108, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive set register'},
            'POUTC': {'addr': 0x410C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive clear register'},
            'POUTT': {'addr': 0x4110, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive toggle register'},
            'PDIR': {'addr': 0x4114, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO pin direction register'},
            'PREN': {'addr': 0x4118, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO resistor enable register'},
            'PSEL': {'addr': 0x411C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO peripheral select register'},
            'PIF': {'addr': 0x4120, 'size': 1, 'type': 'STATUS', 'description': 'GPIO interrupt flag register'},
            'PIES': {'addr': 0x4124, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt edge select register'},
            'PIE': {'addr': 0x4128, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt enable register'},
        }
    },
    
    'GPIO2': {
        'description': 'General Purpose I/O Port 2 (8 pins)',
        'base_addr': 0x4800,
        'registers': {
            'PIN': {'addr': 0x4800, 'size': 1, 'type': 'STATUS', 'description': 'GPIO read pin register'},
            'POUT': {'addr': 0x4804, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive register'},
            'POUTS': {'addr': 0x4808, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive set register'},
            'POUTC': {'addr': 0x480C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive clear register'},
            'POUTT': {'addr': 0x4810, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive toggle register'},
            'PDIR': {'addr': 0x4814, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO pin direction register'},
            'PREN': {'addr': 0x4818, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO resistor enable register'},
            'PSEL': {'addr': 0x481C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO peripheral select register'},
            'PIF': {'addr': 0x4820, 'size': 1, 'type': 'STATUS', 'description': 'GPIO interrupt flag register'},
            'PIES': {'addr': 0x4824, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt edge select register'},
            'PIE': {'addr': 0x4828, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt enable register'},
        }
    },
    
    'GPIO3': {
        'description': 'General Purpose I/O Port 3 (8 pins)',
        'base_addr': 0x4D00,
        'registers': {
            'PIN': {'addr': 0x4D00, 'size': 1, 'type': 'STATUS', 'description': 'GPIO read pin register'},
            'POUT': {'addr': 0x4D04, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive register'},
            'POUTS': {'addr': 0x4D08, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive set register'},
            'POUTC': {'addr': 0x4D0C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive clear register'},
            'POUTT': {'addr': 0x4D10, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO output drive toggle register'},
            'PDIR': {'addr': 0x4D14, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO pin direction register'},
            'PREN': {'addr': 0x4D18, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO resistor enable register'},
            'PSEL': {'addr': 0x4D1C, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO peripheral select register'},
            'PIF': {'addr': 0x4D20, 'size': 1, 'type': 'STATUS', 'description': 'GPIO interrupt flag register'},
            'PIES': {'addr': 0x4D24, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt edge select register'},
            'PIE': {'addr': 0x4D28, 'size': 1, 'type': 'CONTROL', 'description': 'GPIO interrupt enable register'},
        }
    },
    
    'UART0': {
        'description': 'Universal Asynchronous Receiver/Transmitter 0',
        'base_addr': 0x4400,
        'registers': {
            'CR': {'addr': 0x4400, 'size': 1, 'type': 'CONTROL', 'description': 'UART control register'},
            'SR': {'addr': 0x4404, 'size': 1, 'type': 'STATUS', 'description': 'UART status register'},
            'BR': {'addr': 0x4408, 'size': 2, 'type': 'CONFIG', 'description': 'UART baud rate register'},
            'RX': {'addr': 0x440C, 'size': 1, 'type': 'DATA', 'description': 'UART receive data register'},
            'TX': {'addr': 0x4410, 'size': 1, 'type': 'DATA', 'description': 'UART transmit data register'},
        }
    },
    
    'UART1': {
        'description': 'Universal Asynchronous Receiver/Transmitter 1',
        'base_addr': 0x4500,
        'registers': {
            'CR': {'addr': 0x4500, 'size': 1, 'type': 'CONTROL', 'description': 'UART control register'},
            'SR': {'addr': 0x4504, 'size': 1, 'type': 'STATUS', 'description': 'UART status register'},
            'BR': {'addr': 0x4508, 'size': 2, 'type': 'CONFIG', 'description': 'UART baud rate register'},
            'RX': {'addr': 0x450C, 'size': 1, 'type': 'DATA', 'description': 'UART receive data register'},
            'TX': {'addr': 0x4510, 'size': 1, 'type': 'DATA', 'description': 'UART transmit data register'},
        }
    },
    
    'SPI0': {
        'description': 'Serial Peripheral Interface 0 (with Flash access)',
        'base_addr': 0x4200,
        'registers': {
            'CR': {'addr': 0x4200, 'size': 4, 'type': 'CONTROL', 'description': 'SPI control register'},
            'SR': {'addr': 0x4204, 'size': 1, 'type': 'STATUS', 'description': 'SPI status register'},
            'TX': {'addr': 0x4208, 'size': 4, 'type': 'DATA', 'description': 'SPI transmit data register'},
            'RX': {'addr': 0x420C, 'size': 4, 'type': 'DATA', 'description': 'SPI receive data register'},
            'FOS': {'addr': 0x4210, 'size': 4, 'type': 'CONFIG', 'description': 'SPI flash offset address register'},
        }
    },
    
    'SPI1': {
        'description': 'Serial Peripheral Interface 1',
        'base_addr': 0x4300,
        'registers': {
            'CR': {'addr': 0x4300, 'size': 4, 'type': 'CONTROL', 'description': 'SPI control register'},
            'SR': {'addr': 0x4304, 'size': 1, 'type': 'STATUS', 'description': 'SPI status register'},
            'TX': {'addr': 0x4308, 'size': 4, 'type': 'DATA', 'description': 'SPI transmit data register'},
            'RX': {'addr': 0x430C, 'size': 4, 'type': 'DATA', 'description': 'SPI receive data register'},
            'FOS': {'addr': 0x4310, 'size': 4, 'type': 'CONFIG', 'description': 'SPI flash offset address register'},
        }
    },
    
    'TIMER0': {
        'description': '32-bit Timer 0 with PWM and Input Capture',
        'base_addr': 0x4600,
        'registers': {
            'CR': {'addr': 0x4600, 'size': 4, 'type': 'CONTROL', 'description': 'Timer control register'},
            'SR': {'addr': 0x4604, 'size': 1, 'type': 'STATUS', 'description': 'Timer status register'},
            'VAL': {'addr': 0x4608, 'size': 4, 'type': 'DATA', 'description': 'Timer value register'},
            'CMP0': {'addr': 0x460C, 'size': 4, 'type': 'CONFIG', 'description': 'Timer compare 0 register'},
            'CMP1': {'addr': 0x4610, 'size': 4, 'type': 'CONFIG', 'description': 'Timer compare 1 register'},
            'CMP2': {'addr': 0x4614, 'size': 4, 'type': 'CONFIG', 'description': 'Timer compare 2 register'},
            'CAP0': {'addr': 0x4618, 'size': 4, 'type': 'DATA', 'description': 'Timer capture 0 register'},
            'CAP1': {'addr': 0x461C, 'size': 4, 'type': 'DATA', 'description': 'Timer capture 1 register'},
        }
    },
    
    'TIMER1': {
        'description': '32-bit Timer 1 with PWM and Input Capture',
        'base_addr': 0x4700,
        'registers': {
            'CR': {'addr': 0x4700, 'size': 4, 'type': 'CONTROL', 'description': 'Timer control register'},
            'SR': {'addr': 0x4704, 'size': 1, 'type': 'STATUS', 'description': 'Timer status register'},
            'VAL': {'addr': 0x4708, 'size': 4, 'type': 'DATA', 'description': 'Timer value register'},
            'CMP0': {'addr': 0x470C, 'size': 4, 'type': 'CONFIG', 'description': 'Timer compare 0 register'},
            'CMP1': {'addr': 0x4710, 'size': 4, 'type': 'CONFIG', 'description': 'Timer compare 1 register'},
            'CMP2': {'addr': 0x4714, 'size': 4, 'type': 'CONFIG', 'description': 'Timer compare 2 register'},
            'CAP0': {'addr': 0x4718, 'size': 4, 'type': 'DATA', 'description': 'Timer capture 0 register'},
            'CAP1': {'addr': 0x471C, 'size': 4, 'type': 'DATA', 'description': 'Timer capture 1 register'},
        }
    },
    
    'SYSTEM': {
        'description': 'System Control - Clock, Power, Interrupts, Watchdog, CRC',
        'base_addr': 0x4900,
        'registers': {
            'CLKCR': {'addr': 0x4900, 'size': 2, 'type': 'CONTROL', 'description': 'System clock control register'},
            'CLKDIVCR': {'addr': 0x4904, 'size': 1, 'type': 'CONTROL', 'description': 'Clock divider control register'},
            'BLOCKPWR': {'addr': 0x4908, 'size': 1, 'type': 'CONTROL', 'description': 'Block power control register'},
            'CRCDATA': {'addr': 0x490C, 'size': 1, 'type': 'DATA', 'description': 'CRC data register'},
            'CRCSTATE': {'addr': 0x4910, 'size': 2, 'type': 'DATA', 'description': 'CRC state register'},
            'IRQENL': {'addr': 0x4914, 'size': 4, 'type': 'CONTROL', 'description': 'IRQ enable lower register'},
            'IRQENM': {'addr': 0x4918, 'size': 4, 'type': 'CONTROL', 'description': 'IRQ enable middle register'},
            'IRQENU': {'addr': 0x491C, 'size': 4, 'type': 'CONTROL', 'description': 'IRQ enable upper register'},
            'IRQPRIL': {'addr': 0x4920, 'size': 4, 'type': 'CONFIG', 'description': 'IRQ priority lower register'},
            'IRQPRIM': {'addr': 0x4924, 'size': 4, 'type': 'CONFIG', 'description': 'IRQ priority middle register'},
            'IRQPRIU': {'addr': 0x4928, 'size': 4, 'type': 'CONFIG', 'description': 'IRQ priority upper register'},
            'IRQCR': {'addr': 0x492C, 'size': 1, 'type': 'CONTROL', 'description': 'IRQ control register'},
            'WDTCR': {'addr': 0x4930, 'size': 1, 'type': 'CONTROL', 'description': 'Watchdog timer control register'},
            'WDTSR': {'addr': 0x4934, 'size': 1, 'type': 'STATUS', 'description': 'Watchdog timer status register'},
            'WDTPASS': {'addr': 0x4938, 'size': 4, 'type': 'CONFIG', 'description': 'Watchdog timer password register'},
            'WDTVAL': {'addr': 0x493C, 'size': 4, 'type': 'CONFIG', 'description': 'Watchdog timer value register'},
            'DCO0BIAS': {'addr': 0x4940, 'size': 2, 'type': 'BIAS', 'description': 'DCO0 bias control register'},
            'DCO1BIAS': {'addr': 0x4944, 'size': 2, 'type': 'BIAS', 'description': 'DCO1 bias control register'},
        }
    },
    
    'NPU': {
        'description': 'Neural Processing Unit - ML Accelerator',
        'base_addr': 0x4A00,
        'registers': {
            'CR': {'addr': 0x4A00, 'size': 4, 'type': 'CONTROL', 'description': 'NPU control register'},
            'IVSAR': {'addr': 0x4A04, 'size': 4, 'type': 'CONFIG', 'description': 'NPU input vector start address register'},
            'WVSAR': {'addr': 0x4A08, 'size': 4, 'type': 'CONFIG', 'description': 'NPU weight vector start address register'},
            'OVSAR': {'addr': 0x4A0C, 'size': 4, 'type': 'CONFIG', 'description': 'NPU output vector start address register'},
        }
    },
    
    'SARADC': {
        'description': '10-bit Successive Approximation ADC',
        'base_addr': 0x4B00,
        'registers': {
            'CR': {'addr': 0x4B00, 'size': 2, 'type': 'CONTROL', 'description': 'SARADC control register'},
            'CDIV': {'addr': 0x4B04, 'size': 1, 'type': 'CONFIG', 'description': 'SARADC clock divider register'},
            'SR': {'addr': 0x4B08, 'size': 1, 'type': 'STATUS', 'description': 'SARADC status register'},
            'DATA': {'addr': 0x4B0C, 'size': 2, 'type': 'DATA', 'description': 'SARADC data register'},
            'TPR': {'addr': 0x4B10, 'size': 1, 'type': 'CONFIG', 'description': 'SARADC test port register'},
        }
    },
    
    'POTENTIOSTAT': {
        'description': 'Potentiostat with DACs and Bias Generators',
        'base_addr': 0x4C00,
        'registers': {
            'CR': {'addr': 0x4C00, 'size': 4, 'type': 'CONTROL', 'description': 'AFE control register'},
            'TPR': {'addr': 0x4C04, 'size': 4, 'type': 'CONFIG', 'description': 'AFE test port register'},
            'SR': {'addr': 0x4C08, 'size': 1, 'type': 'STATUS', 'description': 'AFE status register'},
            'BIAS_CR': {'addr': 0x4C10, 'size': 1, 'type': 'CONTROL', 'description': 'Bias control register'},
            'BIAS_ADJ': {'addr': 0x4C14, 'size': 1, 'type': 'BIAS', 'description': 'Bias adjustment register'},
            'BIAS_DBP': {'addr': 0x4C18, 'size': 2, 'type': 'BIAS', 'description': 'Bias DAC BP register'},
            'BIAS_DBPC': {'addr': 0x4C1C, 'size': 2, 'type': 'BIAS', 'description': 'Bias DAC BPC register'},
            'BIAS_DBNC': {'addr': 0x4C20, 'size': 2, 'type': 'BIAS', 'description': 'Bias DAC BNC register'},
            'BIAS_DBN': {'addr': 0x4C24, 'size': 2, 'type': 'BIAS', 'description': 'Bias DAC BN register'},
            'BIAS_TC_POT': {'addr': 0x4C28, 'size': 1, 'type': 'BIAS', 'description': 'Bias TC potentiostat register'},
            'BIAS_LC_POT': {'addr': 0x4C2C, 'size': 1, 'type': 'BIAS', 'description': 'Bias LC potentiostat register'},
            'BIAS_TIA_G_POT': {'addr': 0x4C30, 'size': 4, 'type': 'BIAS', 'description': 'Bias TIA gain potentiostat register'},
            'BIAS_REV_POT': {'addr': 0x4C38, 'size': 2, 'type': 'BIAS', 'description': 'Bias REV potentiostat register'},
        }
    },
    
    'DSADC': {
        'description': 'Delta-Sigma ADC',
        'base_addr': 0x4C00,
        'registers': {
            'CR': {'addr': 0x4C00, 'size': 4, 'type': 'CONTROL', 'description': 'AFE control register'},
            'TPR': {'addr': 0x4C04, 'size': 4, 'type': 'CONFIG', 'description': 'AFE test port register'},
            'SR': {'addr': 0x4C08, 'size': 1, 'type': 'STATUS', 'description': 'AFE status register'},
            'ADC_VAL': {'addr': 0x4C0C, 'size': 2, 'type': 'DATA', 'description': 'DSADC result register'},
            'BIAS_DSADC_VCM': {'addr': 0x4C34, 'size': 2, 'type': 'BIAS', 'description': 'Bias DSADC VCM register'},
            'BIAS_TC_DSADC': {'addr': 0x4C3C, 'size': 1, 'type': 'BIAS', 'description': 'Bias TC DSADC register'},
            'BIAS_LC_DSADC': {'addr': 0x4C40, 'size': 1, 'type': 'BIAS', 'description': 'Bias LC DSADC register'},
            'BIAS_RIN_DSADC': {'addr': 0x4C44, 'size': 1, 'type': 'BIAS', 'description': 'Bias RIN DSADC register'},
            'BIAS_RFB_DSADC': {'addr': 0x4C48, 'size': 1, 'type': 'BIAS', 'description': 'Bias RFB DSADC register'},
        }
    },
    
    'I2C0': {
        'description': 'Inter-Integrated Circuit Interface 0 (Master/Slave)',
        'base_addr': 0x4E00,
        'registers': {
            'CR': {'addr': 0x4E00, 'size': 4, 'type': 'CONTROL', 'description': 'I2C control register'},
            'FCR': {'addr': 0x4E04, 'size': 1, 'type': 'CONFIG', 'description': 'I2C frequency control register'},
            'SR': {'addr': 0x4E08, 'size': 2, 'type': 'STATUS', 'description': 'I2C status register'},
            'MTX': {'addr': 0x4E0C, 'size': 1, 'type': 'DATA', 'description': 'I2C master TX register'},
            'MRX': {'addr': 0x4E10, 'size': 1, 'type': 'DATA', 'description': 'I2C master RX register'},
            'STX': {'addr': 0x4E14, 'size': 1, 'type': 'DATA', 'description': 'I2C slave TX register'},
            'SRX': {'addr': 0x4E18, 'size': 1, 'type': 'DATA', 'description': 'I2C slave RX register'},
            'AR': {'addr': 0x4E1C, 'size': 1, 'type': 'CONFIG', 'description': 'I2C address register'},
            'AMR': {'addr': 0x4E20, 'size': 1, 'type': 'CONFIG', 'description': 'I2C address mask register'},
        }
    },
    
    'I2C1': {
        'description': 'Inter-Integrated Circuit Interface 1 (Master/Slave)',
        'base_addr': 0x4F00,
        'registers': {
            'CR': {'addr': 0x4F00, 'size': 4, 'type': 'CONTROL', 'description': 'I2C control register'},
            'FCR': {'addr': 0x4F04, 'size': 1, 'type': 'CONFIG', 'description': 'I2C frequency control register'},
            'SR': {'addr': 0x4F08, 'size': 2, 'type': 'STATUS', 'description': 'I2C status register'},
            'MTX': {'addr': 0x4F0C, 'size': 1, 'type': 'DATA', 'description': 'I2C master TX register'},
            'MRX': {'addr': 0x4F10, 'size': 1, 'type': 'DATA', 'description': 'I2C master RX register'},
            'STX': {'addr': 0x4F14, 'size': 1, 'type': 'DATA', 'description': 'I2C slave TX register'},
            'SRX': {'addr': 0x4F18, 'size': 1, 'type': 'DATA', 'description': 'I2C slave RX register'},
            'AR': {'addr': 0x4F1C, 'size': 1, 'type': 'CONFIG', 'description': 'I2C address register'},
            'AMR': {'addr': 0x4F20, 'size': 1, 'type': 'CONFIG', 'description': 'I2C address mask register'},
        }
    },
}


# Helper function to get all peripherals of a certain type
def get_peripherals_by_type(periph_type):
    """Return list of peripheral names matching a type (e.g., 'GPIO', 'UART')"""
    return [name for name in PERIPHERALS.keys() if name.startswith(periph_type)]


# Helper function to get register address
def get_register_address(peripheral, register):
    """Get the full address of a register"""
    if peripheral in PERIPHERALS and register in PERIPHERALS[peripheral]['registers']:
        return PERIPHERALS[peripheral]['registers'][register]['addr']
    return None


# Helper function to convert address to Forth command
def addr_to_forth(address):
    """Convert address to Forth hex format (e.g., 0x4000 -> '0x04000')"""
    return f"0x{address:05X}"
