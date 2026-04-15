"""
New Layout for Myshkin MCU GUI
Tab-based interface with one tab per peripheral type
"""
from dash import dcc, html
import dash_daq as daq
from app import app
from peripherals_config import PERIPHERALS
from bitfields_config import get_bitfields


def create_peripheral_tab(peripheral_name, figure_path=None, figure_caption=None, side_figures=None):
    """
    Create a tab content for a specific peripheral
    
    Args:
        peripheral_name: Name of peripheral (e.g., 'GPIO0', 'UART0', 'POTENTIOSTAT')
        figure_path: Optional path to a top figure image (relative to assets/)
        figure_caption: Optional caption for the top figure
        side_figures: Optional list of dicts with 'path' and 'caption' for sidebar figures
    
    Returns:
        html.Div containing the peripheral controls
    """
    periph = PERIPHERALS[peripheral_name]
    
    children = [
        html.H4(f"{peripheral_name} - {periph['description']}"),
        html.Hr(),
    ]
    
    # Add top figure if provided
    if figure_path:
        children.append(
            html.Div(
                className='peripheral-figure',
                children=[
                    html.Img(
                        src=f'/assets/{figure_path}',
                        className='schematic-image',
                    ),
                    html.P(figure_caption, className='figure-caption') if figure_caption else None,
                ]
            )
        )
        children.append(html.Hr())
    
    # Create sidebar figures if provided
    sidebar_content = None
    if side_figures:
        sidebar_items = []
        for fig in side_figures:
            sidebar_items.append(
                html.Div(
                    className='sidebar-figure',
                    children=[
                        html.Img(
                            src=f"/assets/{fig['path']}",
                            className='sidebar-schematic-image',
                        ),
                        html.P(fig.get('caption', ''), className='sidebar-figure-caption'),
                    ]
                )
            )
        sidebar_content = html.Div(className='figures-sidebar', children=sidebar_items)
    
    # Create controls for each register
    for reg_name, reg_info in periph['registers'].items():
        reg_type = reg_info['type']
        full_name = f"{peripheral_name}_{reg_name}"
        
        # Create control based on register type
        if reg_type == 'CONTROL':
            # Control registers show bitfield controls
            bitfields = get_bitfields(peripheral_name, reg_name)
            
            if bitfields:
                # Create individual controls for each bitfield
                bitfield_controls = []
                
                for field_name, field_info in bitfields.items():
                    field_id = f"{full_name}_{field_name}"
                    field_desc = field_info['desc']
                    
                    if field_info.get('values'):
                        # Dropdown for enumerated values
                        options = [{'label': f"{k}: {v}", 'value': k} for k, v in field_info['values'].items()]
                        bitfield_controls.append(html.Div(
                            className='bitfield-control',
                            children=[
                                html.Label([
                                    html.Span(f"{field_name}", className='bitfield-name'),
                                    html.Span(f" - {field_desc}", className='bitfield-desc')
                                ]),
                                dcc.Dropdown(
                                    id={'type': 'bitfield-dropdown', 'name': field_id},
                                    options=options,
                                    value=0,
                                    clearable=False,
                                    className='bitfield-dropdown'
                                ),
                            ]
                        ))
                    else:
                        # Numeric input for multi-bit fields without enum
                        max_val = (1 << field_info['width']) - 1
                        bitfield_controls.append(html.Div(
                            className='bitfield-control',
                            children=[
                                html.Label([
                                    html.Span(f"{field_name}", className='bitfield-name'),
                                    html.Span(f" - {field_desc}", className='bitfield-desc')
                                ]),
                                daq.NumericInput(
                                    id={'type': 'bitfield-numeric', 'name': field_id},
                                    min=0,
                                    max=max_val,
                                    value=0,
                                    size=80,
                                ),
                            ]
                        ))
                
                children.append(html.Div(
                    className='register-control',
                    children=[
                        html.Div(className='register-header', children=[
                            html.Label(f"{reg_name}: {reg_info['description']}", className='register-title'),
                            html.Div(className='register-actions', children=[
                                html.Button(
                                    'Read All',
                                    id={'type': 'reg-read-btn', 'name': full_name},
                                    className='reg-button reg-button-small'
                                ),
                                html.Button(
                                    'Write All',
                                    id={'type': 'reg-write-btn', 'name': full_name},
                                    className='reg-button reg-button-small'
                                ),
                            ]),
                        ]),
                        html.Div(className='bitfields-container', children=bitfield_controls),
                    ]
                ))
            else:
                # Fallback: single numeric input if no bitfield definitions
                children.append(html.Div(
                    className='register-control',
                    children=[
                        html.Label(f"{reg_name}: {reg_info['description']}"),
                        html.Div(className='register-controls-row', children=[
                            daq.NumericInput(
                                id={'type': 'reg-input', 'name': full_name},
                                min=0,
                                max=(1 << (reg_info['size'] * 8)) - 1,
                                value=0,
                                size=120,
                            ),
                            html.Button(
                                'Read',
                                id={'type': 'reg-read-btn', 'name': full_name},
                                className='reg-button'
                            ),
                            html.Button(
                                'Write',
                                id={'type': 'reg-write-btn', 'name': full_name},
                                className='reg-button'
                            ),
                        ]),
                    ]
                ))
        
        elif reg_type == 'STATUS':
            # Status registers get only a read button
            children.append(html.Div(
                className='register-status',
                children=[
                    html.Label(f"{reg_name}: {reg_info['description']}"),
                    html.Div(className='register-controls-row', children=[
                        html.Div(
                            id={'type': 'reg-display', 'name': full_name},
                            className='register-display',
                            children='0x0000'
                        ),
                        html.Button(
                            'Read',
                            id={'type': 'reg-read-btn', 'name': full_name},
                            className='reg-button'
                        ),
                    ]),
                ]
            ))
        
        elif reg_type == 'BIAS':
            # Bias registers get sliders
            max_val = (1 << (reg_info['size'] * 8)) - 1
            children.append(html.Div(
                className='register-bias',
                children=[
                    html.Label(f"{reg_name}: {reg_info['description']}"),
                    dcc.Slider(
                        id={'type': 'reg-slider', 'name': full_name},
                        min=0,
                        max=max_val,
                        value=0,
                        marks={i: str(i) for i in range(0, max_val+1, max(1, max_val//8))},
                        tooltip={"placement": "bottom", "always_visible": False},
                    ),
                    html.Div(
                        className='slider-value-display',
                        children=[
                            daq.NumericInput(
                                id={'type': 'reg-slider-input', 'name': full_name},
                                min=0,
                                max=max_val,
                                value=0,
                                size=150,
                            ),
                        ]
                    ),
                ]
            ))
        
        elif reg_type in ['DATA', 'CONFIG']:
            # Data/Config registers get read/write capability
            children.append(html.Div(
                className='register-data',
                children=[
                    html.Label(f"{reg_name}: {reg_info['description']}"),
                    html.Div(className='register-controls-row', children=[
                        daq.NumericInput(
                            id={'type': 'reg-input', 'name': full_name},
                            min=0,
                            max=(1 << (reg_info['size'] * 8)) - 1,
                            value=0,
                            size=120,
                        ),
                        html.Button(
                            'Read',
                            id={'type': 'reg-read-btn', 'name': full_name},
                            className='reg-button'
                        ),
                        html.Button(
                            'Write',
                            id={'type': 'reg-write-btn', 'name': full_name},
                            className='reg-button'
                        ),
                    ]),
                ]
            ))
    
    # Wrap register controls in a container
    if sidebar_content:
        # Two-column layout: figures on left, controls on right
        # Separate the title/header section from the register controls
        if figure_path:
            # If top figure exists: Title, HR, Figure, HR are first 4 elements
            title_section = children[:4]
            register_controls = children[4:]
        else:
            # No top figure: Title and HR are first 2 elements  
            title_section = children[:2]
            register_controls = children[2:]
        
        main_content = html.Div(
            className='two-column-layout',
            children=[
                sidebar_content,
                html.Div(className='controls-content', children=register_controls)
            ]
        )
        return html.Div(className='peripheral-tab-content', children=title_section + [main_content])
    else:
        return html.Div(className='peripheral-tab-content', children=children)


# Main layout
layout = html.Div(
    id='app-div',
    children=[
        # Store for register cache
        dcc.Store(id='storage', storage_type='session'),

        # Banner
        html.Div(
            id="banner",
            className="banner",
            children=[
                html.Div(
                    id="banner-text",
                    children=[html.H3("Myshkin MCU Configuration Interface")],
                ),
                html.Div(
                    id="banner-logo",
                    children=[html.Img(id="logo", src=app.get_asset_url("logo.png"))],
                ),
            ],
        ),

        # Control bar
        html.Div(
            id="control_bar",
            className="control-bar",
            children=[
                html.Button(id='sync_all_button', children='Sync All Registers'),
                html.Button(id='reset_button', children='Reset Chip'),
                html.Button(id='clear_log_button', children='Clear Log'),
            ],
        ),

        # Interval component for live updates
        dcc.Interval(
            id='terminal_update_interval',
            interval=1000,  # Update every 1 second
            n_intervals=0
        ),

        # Main content area with tabs and terminal sidebar
        html.Div(
            className="main-content-with-terminal",
            children=[
                # Left: Main tabs for peripheral groups
                html.Div(
                    className="tabs-content",
                    children=[
                        dcc.Tabs(id='main-tabs', value='tab-potentiostat', children=[
            
            # Potentiostat Tab (first)
            dcc.Tab(label='Potentiostat', value='tab-potentiostat', children=[
                create_peripheral_tab(
                    'POTENTIOSTAT',
                    figure_path='figures/afe_block_acquisition_focus.png',
                    figure_caption='AFE block diagram showing acquisition signal path with potentiostat and DSADC',
                    side_figures=[
                        {'path': 'figures/bias-generator.png', 'caption': 'Bias generator circuit providing reference voltages'},
                        {'path': 'figures/dualslope_schem.png', 'caption': 'Dual-slope ADC schematic'},
                        {'path': 'figures/dualslopewave.png', 'caption': 'Dual-slope conversion waveform showing analog-to-digital conversion over time'},
                    ]
                )
            ]),
            
            # SARADC Tab
            dcc.Tab(label='SARADC', value='tab-saradc', children=[
                html.Div(className='peripheral-tab-content', children=[
                    *create_peripheral_tab(
                        'SARADC',
                        figure_path='figures/CDAC_layout.png',
                        figure_caption='Capacitive DAC (CDAC) layout used in the SAR ADC architecture'
                    ).children,
                    
                    # Data Acquisition Section
                    html.H4("Fast Data Acquisition", style={'margin-top': '30px', 'color': '#2c3e50'}),
                    html.Hr(),
                    
                    html.Div(className='register-control', children=[
                        html.Div(className='register-controls-row', children=[
                            html.Button(
                                'Start Acquisition',
                                id='saradc-start-btn',
                                className='reg-button',
                                style={'background-color': '#27ae60'}
                            ),
                            html.Button(
                                'Stop Acquisition',
                                id='saradc-stop-btn',
                                className='reg-button',
                                style={'background-color': '#e74c3c'}
                            ),
                            html.Div(
                                id='saradc-status-display',
                                className='register-display',
                                children='Ready',
                                style={'margin-left': '15px'}
                            ),
                        ]),
                        html.Div(className='register-controls-row', style={'margin-top': '10px'}, children=[
                            html.Label("Samples: ", style={'margin-right': '5px'}),
                            html.Div(
                                id='saradc-sample-count',
                                children='0',
                                style={'font-weight': 'bold', 'margin-right': '20px'}
                            ),
                            html.Label("Log file: ", style={'margin-right': '5px'}),
                            html.Div(
                                id='saradc-log-file',
                                children='--',
                                style={'font-style': 'italic'}
                            ),
                        ]),
                    ]),
                    
                    # Histogram plot (generated after acquisition stops)
                    html.Div(className='register-control', style={'margin-top': '20px'}, children=[
                        html.Label("ADC Value Distribution (generated after stopping)"),
                        dcc.Graph(
                            id='saradc-plot',
                            config={'displayModeBar': False},
                            style={'height': '400px'}
                        ),
                    ]),
                    
                    # Hidden interval component for data acquisition
                    dcc.Interval(
                        id='saradc-acquisition-interval',
                        interval=150,  # 150ms = ~6.7 Hz acquisition rate (slower for UART stability)
                        disabled=True,
                        n_intervals=0
                    ),
                    
                    # Store for acquisition data
                    dcc.Store(id='saradc-data-store', data={'samples': [], 'timestamps': [], 'acquiring': False, 'log_file': None}),
                ])
            ]),
            
            # DSADC Tab
            dcc.Tab(label='DSADC', value='tab-dsadc', children=[
                create_peripheral_tab('DSADC')
            ]),
            
            # GPIO Tab
            dcc.Tab(label='GPIO', value='tab-gpio', children=[
                dcc.Tabs(id='gpio-subtabs', value='gpio0', children=[
                    dcc.Tab(label='GPIO0', value='gpio0', children=[
                        create_peripheral_tab('GPIO0')
                    ]),
                    dcc.Tab(label='GPIO1', value='gpio1', children=[
                        create_peripheral_tab('GPIO1')
                    ]),
                    dcc.Tab(label='GPIO2', value='gpio2', children=[
                        create_peripheral_tab('GPIO2')
                    ]),
                    dcc.Tab(label='GPIO3', value='gpio3', children=[
                        create_peripheral_tab('GPIO3')
                    ]),
                ]),
            ]),
            
            # Communication Tab
            dcc.Tab(label='Communication', value='tab-comm', children=[
                dcc.Tabs(id='comm-subtabs', value='uart0', children=[
                    dcc.Tab(label='UART0', value='uart0', children=[
                        create_peripheral_tab('UART0')
                    ]),
                    dcc.Tab(label='UART1', value='uart1', children=[
                        create_peripheral_tab('UART1')
                    ]),
                    dcc.Tab(label='SPI0', value='spi0', children=[
                        create_peripheral_tab('SPI0')
                    ]),
                    dcc.Tab(label='SPI1', value='spi1', children=[
                        create_peripheral_tab('SPI1')
                    ]),
                    dcc.Tab(label='I2C0', value='i2c0', children=[
                        create_peripheral_tab('I2C0')
                    ]),
                    dcc.Tab(label='I2C1', value='i2c1', children=[
                        create_peripheral_tab('I2C1')
                    ]),
                ]),
            ]),
            
            # Timers Tab
            dcc.Tab(label='Timers', value='tab-timers', children=[
                dcc.Tabs(id='timer-subtabs', value='timer0', children=[
                    dcc.Tab(label='TIMER0', value='timer0', children=[
                        create_peripheral_tab('TIMER0')
                    ]),
                    dcc.Tab(label='TIMER1', value='timer1', children=[
                        create_peripheral_tab('TIMER1')
                    ]),
                ]),
            ]),
            
            # System Tab
            dcc.Tab(label='System', value='tab-system', children=[
                html.Div(className='peripheral-tab-content', children=[
                    *create_peripheral_tab('SYSTEM').children,
                    
                    # Clock Frequency Measurement Section
                    html.H4("Clock Frequency Measurement", style={'margin-top': '30px', 'color': '#2c3e50'}),
                    html.Hr(),
                    
                    html.Div(className='register-control', children=[
                        html.Label("CLK Frequency"),
                        html.Div(className='register-controls-row', children=[
                            html.Button(
                                'Measure CLK',
                                id='measure-clk-btn',
                                className='reg-button'
                            ),
                            html.Div(
                                id='clk-freq-display',
                                className='register-display',
                                children='-- Hz'
                            ),
                        ]),
                    ]),
                    
                    html.Div(className='register-control', children=[
                        html.Label("SMCLK Frequency"),
                        html.Div(className='register-controls-row', children=[
                            html.Button(
                                'Measure SMCLK',
                                id='measure-smclk-btn',
                                className='reg-button'
                            ),
                            html.Div(
                                id='smclk-freq-display',
                                className='register-display',
                                children='-- Hz'
                            ),
                        ]),
                    ]),
                ])
            ]),
            
            # NPU Tab
            dcc.Tab(label='NPU', value='tab-npu', children=[
                create_peripheral_tab('NPU')
            ]),
            
                        ]),
                    ]
                ),
                
                # Right: Live Command Terminal (sidebar)
                html.Div(
                    id="command_terminal_container",
                    className="command-terminal-sidebar",
                    children=[
                        html.Div(
                            className="terminal-header",
                            children=[
                                html.H5("Live Forth Monitor", style={'margin': '0'}),
                                html.Span("Updates every 1s", className="terminal-subtitle")
                            ]
                        ),
                        html.Div(
                            id='command_terminal',
                            className='command-terminal',
                            children="Waiting for commands..."
                        ),
                        html.Div(
                            className="terminal-legend",
                            children=[
                                html.Span([html.Span("TX", className="legend-tx"), " Transmitted"], className="legend-item"),
                                html.Span([html.Span("RX", className="legend-rx"), " Received"], className="legend-item"),
                                html.Span([html.Span("ERR", className="legend-error"), " Error"], className="legend-item"),
                                html.Span([html.Span("SIM", className="legend-sim"), " Simulation"], className="legend-item"),
                            ]
                        ),
                    ],
                ),
            ]
        ),
    ]
)
