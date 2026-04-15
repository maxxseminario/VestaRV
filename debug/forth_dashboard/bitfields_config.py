"""
Enhanced Peripheral Configuration with Bitfield Definitions
Includes detailed bit-level information for all control registers
"""

from peripherals_config import PERIPHERALS, PERIPHERAL_BASES

# Bitfield definitions for control registers
# Format: {peripheral_reg: {bitfield_name: {bit: pos/range, desc: description, values: {0: desc, 1: desc}}}}

BITFIELDS = {
    # SPI0 and SPI1 Control Register
    'SPI_CR': {
        'FEN': {
            'bits': 19,
            'width': 1,
            'desc': 'SPI Flash extended memory enable',
            'values': {
                0: 'Flash extended memory disabled',
                1: 'Flash extended memory enabled'
            }
        },
        'SM': {
            'bits': 18,
            'width': 1,
            'desc': 'SPI slave mode select',
            'values': {
                0: 'Master mode',
                1: 'Slave mode'
            }
        },
        'TXSB': {
            'bits': 17,
            'width': 1,
            'desc': 'SPI TX swap bytes',
            'values': {
                0: 'Bytes not swapped',
                1: 'Bytes swapped'
            }
        },
        'RXSB': {
            'bits': 16,
            'width': 1,
            'desc': 'SPI RX swap bytes',
            'values': {
                0: 'Bytes not swapped',
                1: 'Bytes swapped'
            }
        },
        'BR': {
            'bits': [8, 15],
            'width': 8,
            'desc': 'SPI clock baud rate (SMCLK/(2*(1+BR)))',
            'values': None  # Numeric field, not enumerated
        },
        'EN': {
            'bits': 7,
            'width': 1,
            'desc': 'SPI enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
        'MSB': {
            'bits': 6,
            'width': 1,
            'desc': 'Bit endianness',
            'values': {
                0: 'LSB-first',
                1: 'MSB-first'
            }
        },
        'TCIE': {
            'bits': 5,
            'width': 1,
            'desc': 'Transmit complete interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'TEIE': {
            'bits': 4,
            'width': 1,
            'desc': 'Transmit empty interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'DL': {
            'bits': [2, 3],
            'width': 2,
            'desc': 'Data length select',
            'values': {
                0: '8-bit transfers',
                1: '16-bit transfers',
                2: '32-bit transfers',
                3: 'Reserved'
            }
        },
        'CPOL': {
            'bits': 1,
            'width': 1,
            'desc': 'Clock polarity',
            'values': {
                0: 'SCK idles low',
                1: 'SCK idles high'
            }
        },
        'CPHA': {
            'bits': 0,
            'width': 1,
            'desc': 'Clock phase',
            'values': {
                0: 'Sample on leading edge',
                1: 'Sample on trailing edge'
            }
        },
    },
    
    # UART Control Register
    'UART_CR': {
        'EN': {
            'bits': 7,
            'width': 1,
            'desc': 'UART enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
        'RXIE': {
            'bits': 6,
            'width': 1,
            'desc': 'Receive interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'TXIE': {
            'bits': 5,
            'width': 1,
            'desc': 'Transmit interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'SB': {
            'bits': 2,
            'width': 1,
            'desc': 'Stop bits',
            'values': {
                0: '1 stop bit',
                1: '2 stop bits'
            }
        },
        'PEN': {
            'bits': 1,
            'width': 1,
            'desc': 'Parity enable',
            'values': {
                0: 'Parity disabled',
                1: 'Parity enabled'
            }
        },
        'PSEL': {
            'bits': 0,
            'width': 1,
            'desc': 'Parity select',
            'values': {
                0: 'Even parity',
                1: 'Odd parity'
            }
        },
    },
    
    # GPIO Control Registers
    'GPIO_POUT': {
        'OUT7': {'bits': 7, 'width': 1, 'desc': 'Pin 7 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT6': {'bits': 6, 'width': 1, 'desc': 'Pin 6 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT5': {'bits': 5, 'width': 1, 'desc': 'Pin 5 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT4': {'bits': 4, 'width': 1, 'desc': 'Pin 4 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT3': {'bits': 3, 'width': 1, 'desc': 'Pin 3 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT2': {'bits': 2, 'width': 1, 'desc': 'Pin 2 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT1': {'bits': 1, 'width': 1, 'desc': 'Pin 1 output', 'values': {0: 'Low', 1: 'High'}},
        'OUT0': {'bits': 0, 'width': 1, 'desc': 'Pin 0 output', 'values': {0: 'Low', 1: 'High'}},
    },
    
    'GPIO_POUTS': {
        'SET7': {'bits': 7, 'width': 1, 'desc': 'Set pin 7 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET6': {'bits': 6, 'width': 1, 'desc': 'Set pin 6 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET5': {'bits': 5, 'width': 1, 'desc': 'Set pin 5 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET4': {'bits': 4, 'width': 1, 'desc': 'Set pin 4 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET3': {'bits': 3, 'width': 1, 'desc': 'Set pin 3 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET2': {'bits': 2, 'width': 1, 'desc': 'Set pin 2 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET1': {'bits': 1, 'width': 1, 'desc': 'Set pin 1 output', 'values': {0: 'No action', 1: 'Set high'}},
        'SET0': {'bits': 0, 'width': 1, 'desc': 'Set pin 0 output', 'values': {0: 'No action', 1: 'Set high'}},
    },
    
    'GPIO_POUTC': {
        'CLR7': {'bits': 7, 'width': 1, 'desc': 'Clear pin 7 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR6': {'bits': 6, 'width': 1, 'desc': 'Clear pin 6 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR5': {'bits': 5, 'width': 1, 'desc': 'Clear pin 5 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR4': {'bits': 4, 'width': 1, 'desc': 'Clear pin 4 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR3': {'bits': 3, 'width': 1, 'desc': 'Clear pin 3 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR2': {'bits': 2, 'width': 1, 'desc': 'Clear pin 2 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR1': {'bits': 1, 'width': 1, 'desc': 'Clear pin 1 output', 'values': {0: 'No action', 1: 'Set low'}},
        'CLR0': {'bits': 0, 'width': 1, 'desc': 'Clear pin 0 output', 'values': {0: 'No action', 1: 'Set low'}},
    },
    
    'GPIO_POUTT': {
        'TOG7': {'bits': 7, 'width': 1, 'desc': 'Toggle pin 7 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG6': {'bits': 6, 'width': 1, 'desc': 'Toggle pin 6 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG5': {'bits': 5, 'width': 1, 'desc': 'Toggle pin 5 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG4': {'bits': 4, 'width': 1, 'desc': 'Toggle pin 4 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG3': {'bits': 3, 'width': 1, 'desc': 'Toggle pin 3 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG2': {'bits': 2, 'width': 1, 'desc': 'Toggle pin 2 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG1': {'bits': 1, 'width': 1, 'desc': 'Toggle pin 1 output', 'values': {0: 'No action', 1: 'Toggle'}},
        'TOG0': {'bits': 0, 'width': 1, 'desc': 'Toggle pin 0 output', 'values': {0: 'No action', 1: 'Toggle'}},
    },
    
    'GPIO_PDIR': {
        'DIR7': {'bits': 7, 'width': 1, 'desc': 'Pin 7 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR6': {'bits': 6, 'width': 1, 'desc': 'Pin 6 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR5': {'bits': 5, 'width': 1, 'desc': 'Pin 5 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR4': {'bits': 4, 'width': 1, 'desc': 'Pin 4 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR3': {'bits': 3, 'width': 1, 'desc': 'Pin 3 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR2': {'bits': 2, 'width': 1, 'desc': 'Pin 2 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR1': {'bits': 1, 'width': 1, 'desc': 'Pin 1 direction', 'values': {0: 'Input', 1: 'Output'}},
        'DIR0': {'bits': 0, 'width': 1, 'desc': 'Pin 0 direction', 'values': {0: 'Input', 1: 'Output'}},
    },
    
    'GPIO_PSEL': {
        'SEL7': {'bits': 7, 'width': 1, 'desc': 'Pin 7 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL6': {'bits': 6, 'width': 1, 'desc': 'Pin 6 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL5': {'bits': 5, 'width': 1, 'desc': 'Pin 5 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL4': {'bits': 4, 'width': 1, 'desc': 'Pin 4 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL3': {'bits': 3, 'width': 1, 'desc': 'Pin 3 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL2': {'bits': 2, 'width': 1, 'desc': 'Pin 2 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL1': {'bits': 1, 'width': 1, 'desc': 'Pin 1 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
        'SEL0': {'bits': 0, 'width': 1, 'desc': 'Pin 0 function', 'values': {0: 'GPIO', 1: 'Peripheral'}},
    },
    
    'GPIO_PREN': {
        'REN7': {'bits': 7, 'width': 1, 'desc': 'Pin 7 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN6': {'bits': 6, 'width': 1, 'desc': 'Pin 6 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN5': {'bits': 5, 'width': 1, 'desc': 'Pin 5 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN4': {'bits': 4, 'width': 1, 'desc': 'Pin 4 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN3': {'bits': 3, 'width': 1, 'desc': 'Pin 3 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN2': {'bits': 2, 'width': 1, 'desc': 'Pin 2 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN1': {'bits': 1, 'width': 1, 'desc': 'Pin 1 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'REN0': {'bits': 0, 'width': 1, 'desc': 'Pin 0 resistor', 'values': {0: 'Disabled', 1: 'Enabled'}},
    },
    
    'GPIO_PIES': {
        'IES7': {'bits': 7, 'width': 1, 'desc': 'Pin 7 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES6': {'bits': 6, 'width': 1, 'desc': 'Pin 6 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES5': {'bits': 5, 'width': 1, 'desc': 'Pin 5 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES4': {'bits': 4, 'width': 1, 'desc': 'Pin 4 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES3': {'bits': 3, 'width': 1, 'desc': 'Pin 3 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES2': {'bits': 2, 'width': 1, 'desc': 'Pin 2 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES1': {'bits': 1, 'width': 1, 'desc': 'Pin 1 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
        'IES0': {'bits': 0, 'width': 1, 'desc': 'Pin 0 interrupt edge', 'values': {0: 'Rising edge', 1: 'Falling edge'}},
    },
    
    'GPIO_PIE': {
        'IE7': {'bits': 7, 'width': 1, 'desc': 'Pin 7 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE6': {'bits': 6, 'width': 1, 'desc': 'Pin 6 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE5': {'bits': 5, 'width': 1, 'desc': 'Pin 5 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE4': {'bits': 4, 'width': 1, 'desc': 'Pin 4 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE3': {'bits': 3, 'width': 1, 'desc': 'Pin 3 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE2': {'bits': 2, 'width': 1, 'desc': 'Pin 2 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE1': {'bits': 1, 'width': 1, 'desc': 'Pin 1 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
        'IE0': {'bits': 0, 'width': 1, 'desc': 'Pin 0 interrupt enable', 'values': {0: 'Disabled', 1: 'Enabled'}},
    },
    
    # Potentiostat and DSADC share the same control register (AFE_CR)
    'POTENTIOSTAT_CR': {
        'RAMPNUM': {
            'bits': [12, 23],
            'width': 12,
            'desc': 'Number of DSADC ramp cycles per conversion',
            'values': None
        },
        'ADCSEL': {
            'bits': 11,
            'width': 1,
            'desc': 'ADC output multiplexer select',
            'values': {
                0: 'DSADC result',
                1: 'SARADC result'
            }
        },
        'ATPSEL': {
            'bits': 10,
            'width': 1,
            'desc': 'Analog test port signal select',
            'values': {
                0: 'Potentiostat output',
                1: 'DSADC output'
            }
        },
        'ATPEN': {
            'bits': 9,
            'width': 1,
            'desc': 'Analog test port enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
        'ADCEXTIN': {
            'bits': 8,
            'width': 1,
            'desc': 'DSADC input source select',
            'values': {
                0: 'External pin',
                1: 'Potentiostat output pad'
            }
        },
        'CONTMEAS': {
            'bits': 4,
            'width': 1,
            'desc': 'Continuous measurement mode',
            'values': {
                0: 'Single conversion',
                1: 'Continuous'
            }
        },
        'DACEN': {
            'bits': 3,
            'width': 1,
            'desc': 'Enable the bias DACs',
            'values': {
                0: 'DACs disabled',
                1: 'DACs enabled'
            }
        },
        'DATARDYIE': {
            'bits': 2,
            'width': 1,
            'desc': 'Data-ready interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'EN': {
            'bits': 1,
            'width': 1,
            'desc': 'AFE enable',
            'values': {
                0: 'AFE clock disabled',
                1: 'AFE clock enabled'
            }
        },
        'ADCEN': {
            'bits': 0,
            'width': 1,
            'desc': 'DSADC enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
    },
    
    'DSADC_CR': {
        'RAMPNUM': {
            'bits': [12, 23],
            'width': 12,
            'desc': 'Number of DSADC ramp cycles per conversion',
            'values': None
        },
        'ADCSEL': {
            'bits': 11,
            'width': 1,
            'desc': 'ADC output multiplexer select',
            'values': {
                0: 'DSADC result',
                1: 'SARADC result'
            }
        },
        'ATPSEL': {
            'bits': 10,
            'width': 1,
            'desc': 'Analog test port signal select',
            'values': {
                0: 'Potentiostat output',
                1: 'DSADC output'
            }
        },
        'ATPEN': {
            'bits': 9,
            'width': 1,
            'desc': 'Analog test port enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
        'ADCEXTIN': {
            'bits': 8,
            'width': 1,
            'desc': 'DSADC input source select',
            'values': {
                0: 'External pin',
                1: 'Potentiostat output pad'
            }
        },
        'CONTMEAS': {
            'bits': 4,
            'width': 1,
            'desc': 'Continuous measurement mode',
            'values': {
                0: 'Single conversion',
                1: 'Continuous'
            }
        },
        'DACEN': {
            'bits': 3,
            'width': 1,
            'desc': 'Enable the bias DACs',
            'values': {
                0: 'DACs disabled',
                1: 'DACs enabled'
            }
        },
        'DATARDYIE': {
            'bits': 2,
            'width': 1,
            'desc': 'Data-ready interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'EN': {
            'bits': 1,
            'width': 1,
            'desc': 'AFE enable',
            'values': {
                0: 'AFE clock disabled',
                1: 'AFE clock enabled'
            }
        },
        'ADCEN': {
            'bits': 0,
            'width': 1,
            'desc': 'DSADC enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
    },
    
    # AFE Control Register (legacy, kept for backwards compatibility)
    'AFE_CR': {
        'RAMPNUM': {
            'bits': [12, 23],
            'width': 12,
            'desc': 'Number of DSADC ramp cycles per conversion',
            'values': None
        },
        'ADCSEL': {
            'bits': 11,
            'width': 1,
            'desc': 'ADC output multiplexer select',
            'values': {
                0: 'DSADC result',
                1: 'SARADC result'
            }
        },
        'ATPSEL': {
            'bits': 10,
            'width': 1,
            'desc': 'Analog test port signal select',
            'values': {
                0: 'Potentiostat output',
                1: 'DSADC output'
            }
        },
        'ATPEN': {
            'bits': 9,
            'width': 1,
            'desc': 'Analog test port enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
        'ADCEXTIN': {
            'bits': 8,
            'width': 1,
            'desc': 'DSADC input source select',
            'values': {
                0: 'External pin',
                1: 'Potentiostat output pad'
            }
        },
        'CONTMEAS': {
            'bits': 4,
            'width': 1,
            'desc': 'Continuous measurement mode',
            'values': {
                0: 'Single conversion',
                1: 'Continuous'
            }
        },
        'DACEN': {
            'bits': 3,
            'width': 1,
            'desc': 'Enable the bias DACs',
            'values': {
                0: 'DACs disabled',
                1: 'DACs enabled'
            }
        },
        'DATARDYIE': {
            'bits': 2,
            'width': 1,
            'desc': 'Data-ready interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'EN': {
            'bits': 1,
            'width': 1,
            'desc': 'AFE enable',
            'values': {
                0: 'AFE clock disabled',
                1: 'AFE clock enabled'
            }
        },
        'ADCEN': {
            'bits': 0,
            'width': 1,
            'desc': 'DSADC enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
    },
    
    'POTENTIOSTAT_BIAS_CR': {
        'USEDAC': {
            'bits': 4,
            'width': 1,
            'desc': 'Bias source select',
            'values': {
                0: 'Internal bias generator',
                1: 'Bias DACs'
            }
        },
        'BUFEN': {
            'bits': 3,
            'width': 1,
            'desc': 'Bias voltage buffer enable',
            'values': {
                0: 'Buffers disabled',
                1: 'Buffers enabled'
            }
        },
        'EN': {
            'bits': 2,
            'width': 1,
            'desc': 'Internal bias generator enable',
            'values': {
                0: 'Generator disabled',
                1: 'Generator enabled'
            }
        },
    },
    
    # Legacy AFE_BIAS_CR for backwards compatibility
    'AFE_BIAS_CR': {
        'USEDAC': {
            'bits': 4,
            'width': 1,
            'desc': 'Bias source select',
            'values': {
                0: 'Internal bias generator',
                1: 'Bias DACs'
            }
        },
        'BUFEN': {
            'bits': 3,
            'width': 1,
            'desc': 'Bias voltage buffer enable',
            'values': {
                0: 'Buffers disabled',
                1: 'Buffers enabled'
            }
        },
        'EN': {
            'bits': 2,
            'width': 1,
            'desc': 'Internal bias generator enable',
            'values': {
                0: 'Generator disabled',
                1: 'Generator enabled'
            }
        },
    },
    
    # SARADC Control Register
    # Based on SARADC.vhd - 9 bits total (bits 0-8)
    'SARADC_CR': {
        'CONTMEAS': {
            'bits': 8,
            'width': 1,
            'desc': 'Continuous measurement mode',
            'values': {
                0: 'Single conversion',
                1: 'Continuous conversion'
            }
        },
        'DATAIE': {
            'bits': 7,
            'width': 1,
            'desc': 'ADC data valid interrupt enable',
            'values': {
                0: 'Interrupt disabled',
                1: 'Interrupt enabled'
            }
        },
        'DEBUG': {
            'bits': 6,
            'width': 1,
            'desc': 'Debug mode enable',
            'values': {
                0: 'Normal mode',
                1: 'Debug mode'
            }
        },
        'EN': {
            'bits': 5,
            'width': 1,
            'desc': 'SARADC enable',
            'values': {
                0: 'Disabled',
                1: 'Enabled'
            }
        },
        'SAMPLESTEP': {
            'bits': [1, 4],
            'width': 4,
            'desc': 'Sample step counter initial value (0-15)',
            'values': None
        },
        'RESET': {
            'bits': 0,
            'width': 1,
            'desc': 'ADC reset',
            'values': {
                0: 'Normal operation',
                1: 'Reset ADC'
            }
        },
    },
}


def get_bitfields(peripheral, register):
    """
    Get bitfield definitions for a register
    
    Args:
        peripheral: Peripheral name (e.g., 'SPI0', 'GPIO0')
        register: Register name (e.g., 'CR', 'POUT')
    
    Returns:
        Dictionary of bitfields or None if not found
    """
    # Create a generic register name (remove instance number)
    generic_peripheral = peripheral.rstrip('0123456789')
    key = f"{generic_peripheral}_{register}"
    
    return BITFIELDS.get(key)


def extract_bitfield(reg_value, bitfield_info):
    """
    Extract a bitfield value from a register value
    
    Args:
        reg_value: Full register value
        bitfield_info: Bitfield info dict with 'bits' and 'width'
    
    Returns:
        Extracted bitfield value
    """
    bits = bitfield_info['bits']
    width = bitfield_info['width']
    
    if isinstance(bits, list):
        # Multi-bit field: [start_bit, end_bit]
        start_bit = bits[0]
        mask = (1 << width) - 1
        return (reg_value >> start_bit) & mask
    else:
        # Single bit
        return (reg_value >> bits) & 1


def insert_bitfield(reg_value, bitfield_info, field_value):
    """
    Insert a bitfield value into a register value
    
    Args:
        reg_value: Current register value
        bitfield_info: Bitfield info dict with 'bits' and 'width'
        field_value: New value for the bitfield
    
    Returns:
        Updated register value
    """
    bits = bitfield_info['bits']
    width = bitfield_info['width']
    
    if isinstance(bits, list):
        # Multi-bit field
        start_bit = bits[0]
        mask = (1 << width) - 1
        # Clear the field
        reg_value &= ~(mask << start_bit)
        # Set the new value
        reg_value |= (field_value & mask) << start_bit
    else:
        # Single bit
        if field_value:
            reg_value |= (1 << bits)
        else:
            reg_value &= ~(1 << bits)
    
    return reg_value
