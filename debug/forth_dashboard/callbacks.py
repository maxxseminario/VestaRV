"""
Callbacks for the new Myshkin MCU GUI
Handles register read/write operations via UART/Forth
"""
import dash
from dash.dependencies import State, Output, Input, MATCH, ALL
from dash.exceptions import PreventUpdate
from dash import html
from app import app
from app import chip
from peripherals_config import PERIPHERALS
from bitfields_config import get_bitfields, extract_bitfield, insert_bitfield
from myshkin import get_command_history


################################################################################
# Register Read/Write Callbacks
################################################################################

@app.callback(
    Output({'type': 'bitfield-dropdown', 'name': MATCH}, 'value'),
    Output({'type': 'bitfield-numeric', 'name': MATCH}, 'value'),
    Input({'type': 'reg-read-btn', 'name': MATCH}, 'n_clicks'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'id'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'id'),
    prevent_initial_call=True
)
def read_register_and_update_bitfields(n_clicks, dropdown_ids, numeric_ids):
    """
    Read register and update all bitfield controls
    """
    if n_clicks is None:
        raise PreventUpdate
    
    # Get the register name from the callback context
    ctx = dash.callback_context
    if not ctx.triggered:
        raise PreventUpdate
    
    trigger_id = ctx.triggered[0]['prop_id'].split('.')[0]
    import json
    button_info = json.loads(trigger_id)
    full_reg_name = button_info['name']
    
    # Parse peripheral and register
    parts = full_reg_name.rsplit('_', 1)
    if len(parts) != 2:
        raise PreventUpdate
    
    periph_name, reg_name = parts
    
    # Get register address
    if periph_name not in PERIPHERALS or reg_name not in PERIPHERALS[periph_name]['registers']:
        raise PreventUpdate
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Read register value from chip
    reg_value = chip.read(addr)
    
    # Get bitfield definitions
    bitfields = get_bitfields(periph_name, reg_name)
    if not bitfields:
        raise PreventUpdate
    
    # Extract bitfield values
    dropdown_values = []
    numeric_values = []
    
    for dropdown_id in dropdown_ids:
        if dropdown_id['name'].startswith(full_reg_name):
            field_name = dropdown_id['name'].split('_')[-1]
            if field_name in bitfields:
                field_val = extract_bitfield(reg_value, bitfields[field_name])
                dropdown_values.append(field_val)
            else:
                dropdown_values.append(dash.no_update)
        else:
            dropdown_values.append(dash.no_update)
    
    for numeric_id in numeric_ids:
        if numeric_id['name'].startswith(full_reg_name):
            field_name = numeric_id['name'].split('_')[-1]
            if field_name in bitfields:
                field_val = extract_bitfield(reg_value, bitfields[field_name])
                numeric_values.append(field_val)
            else:
                numeric_values.append(dash.no_update)
        else:
            numeric_values.append(dash.no_update)
    
    # Return proper structure for multi-output
    if len(dropdown_values) == 1:
        dropdown_out = dropdown_values[0]
    else:
        dropdown_out = dropdown_values
    
    if len(numeric_values) == 1:
        numeric_out = numeric_values[0]
    else:
        numeric_out = numeric_values
    
    return dropdown_out, numeric_out


@app.callback(
    Output({'type': 'reg-write-btn', 'name': MATCH}, 'n_clicks'),
    Input({'type': 'reg-write-btn', 'name': MATCH}, 'n_clicks'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'value'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'id'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'value'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'id'),
    State({'type': 'reg-write-btn', 'name': MATCH}, 'id'),
    prevent_initial_call=True
)
def write_register_from_bitfields(n_clicks, dropdown_values, dropdown_ids, numeric_values, numeric_ids, button_id):
    """
    Collect bitfield values and write to register
    """
    if n_clicks is None:
        raise PreventUpdate
    
    full_reg_name = button_id['name']
    
    # Parse peripheral and register
    parts = full_reg_name.rsplit('_', 1)
    if len(parts) != 2:
        raise PreventUpdate
    
    periph_name, reg_name = parts
    
    # Get register address
    if periph_name not in PERIPHERALS or reg_name not in PERIPHERALS[periph_name]['registers']:
        raise PreventUpdate
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Get bitfield definitions
    bitfields = get_bitfields(periph_name, reg_name)
    if not bitfields:
        raise PreventUpdate
    
    # Build register value from bitfields
    reg_value = 0
    
    # Process dropdown values
    for i, dropdown_id in enumerate(dropdown_ids):
        if dropdown_id['name'].startswith(full_reg_name):
            field_name = dropdown_id['name'].split('_')[-1]
            if field_name in bitfields:
                reg_value = insert_bitfield(reg_value, bitfields[field_name], dropdown_values[i])
    
    # Process numeric values
    for i, numeric_id in enumerate(numeric_ids):
        if numeric_id['name'].startswith(full_reg_name):
            field_name = numeric_id['name'].split('_')[-1]
            if field_name in bitfields:
                reg_value = insert_bitfield(reg_value, bitfields[field_name], numeric_values[i])
    
    # Write to chip
    chip.write(addr, reg_value)
    
    raise PreventUpdate


################################################################################
# Legacy Register Callbacks (for non-bitfield registers)
################################################################################

@app.callback(
    Output({'type': 'reg-display', 'name': MATCH}, 'children'),
    Input({'type': 'reg-read-btn', 'name': MATCH}, 'n_clicks'),
    State({'type': 'reg-read-btn', 'name': MATCH}, 'id'),
    prevent_initial_call=True
)
def read_register_status(n_clicks, btn_id):
    """
    Read a register and display its value (for STATUS registers)
    """
    if n_clicks is None:
        raise PreventUpdate
    
    # Parse peripheral and register name from ID
    full_name = btn_id['name']
    parts = full_name.rsplit('_', 1)
    if len(parts) != 2:
        return "Error: Invalid name"
    
    periph_name, reg_name = parts
    
    # Get register address from config
    if periph_name not in PERIPHERALS:
        return "Error: Unknown peripheral"
    
    if reg_name not in PERIPHERALS[periph_name]['registers']:
        return "Error: Unknown register"
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Read from chip
    value = chip.read(addr)
    
    # Format as hex based on register size
    size = PERIPHERALS[periph_name]['registers'][reg_name]['size']
    if size == 1:
        return f"0x{value:02X}"
    elif size == 2:
        return f"0x{value:04X}"
    else:
        return f"0x{value:08X}"


@app.callback(
    Output({'type': 'reg-input', 'name': MATCH}, 'value'),
    Input({'type': 'reg-read-btn', 'name': MATCH}, 'n_clicks'),
    State({'type': 'reg-input', 'name': MATCH}, 'id'),
    prevent_initial_call=True
)
def read_register_control(n_clicks, input_id):
    """
    Read a register and update input field (for CONTROL/DATA/CONFIG registers)
    """
    if n_clicks is None:
        raise PreventUpdate
    
    # Parse peripheral and register name
    full_name = input_id['name']
    parts = full_name.rsplit('_', 1)
    if len(parts) != 2:
        return 0
    
    periph_name, reg_name = parts
    
    # Get register address
    if periph_name not in PERIPHERALS or reg_name not in PERIPHERALS[periph_name]['registers']:
        return 0
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Read from chip
    value = chip.read(addr)
    return value


# Note: The old write_register callback has been removed because
# write_register_from_bitfields now handles all CONTROL register writes
# via bitfield controls. For registers without bitfields, the legacy
# reg-input control is still used with the read_register_control callback.


@app.callback(
    [Output({'type': 'reg-slider', 'name': MATCH}, 'value'),
     Output({'type': 'reg-slider-input', 'name': MATCH}, 'value')],
    [Input({'type': 'reg-slider', 'name': MATCH}, 'value'),
     Input({'type': 'reg-slider-input', 'name': MATCH}, 'value')],
    [State({'type': 'reg-slider', 'name': MATCH}, 'id')],
    prevent_initial_call=True
)
def sync_slider_and_input(slider_value, input_value, slider_id):
    """
    Sync slider and numeric input below it, and write value to register (for BIAS registers)
    """
    ctx = dash.callback_context
    if not ctx.triggered:
        raise PreventUpdate
    
    # Determine which input triggered the callback
    trigger_id = ctx.triggered[0]['prop_id']
    
    # Get the value from whichever was changed
    if 'reg-slider-input' in trigger_id:
        value = input_value
    else:
        value = slider_value
    
    if value is None:
        raise PreventUpdate
    
    # Parse peripheral and register name
    full_name = slider_id['name']
    parts = full_name.rsplit('_', 1)
    if len(parts) < 2:
        raise PreventUpdate
    
    # Handle multi-word register names like "BIAS_DBP"
    # Try to find the peripheral
    periph_name = None
    reg_name = None
    
    for potential_periph in PERIPHERALS.keys():
        if full_name.startswith(potential_periph + '_'):
            periph_name = potential_periph
            reg_name = full_name[len(potential_periph)+1:]
            break
    
    if periph_name is None or reg_name is None:
        raise PreventUpdate
    
    # Get register address
    if reg_name not in PERIPHERALS[periph_name]['registers']:
        raise PreventUpdate
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Write to chip
    chip.write(addr, int(value))
    
    # Return the value to update both slider and input
    return value, value


################################################################################
# Global Control Callbacks
################################################################################

@app.callback(
    Output('storage', 'data'),
    Input('sync_all_button', 'n_clicks'),
    prevent_initial_call=True
)
def sync_all_registers(n_clicks):
    """
    Read all registers and update the GUI
    This is a placeholder - in a full implementation, this would read
    all registers and update all controls
    """
    if n_clicks is None:
        raise PreventUpdate
    
    print("Syncing all registers...")
    # In a full implementation, iterate through all peripherals and read registers
    
    return {'synced': True}


@app.callback(
    Output('reset_button', 'n_clicks'),
    Input('reset_button', 'n_clicks'),
    prevent_initial_call=True
)
def reset_chip(n_clicks):
    """
    Reset the chip (placeholder - implement based on your reset mechanism)
    """
    if n_clicks is None:
        raise PreventUpdate
    
    print("Resetting chip...")
    # Implement chip reset via Forth command
    # chip.send_forth_command('reset')
    
    raise PreventUpdate


################################################################################
# Live Terminal Callbacks
################################################################################

@app.callback(
    Output('command_terminal', 'children'),
    Input('terminal_update_interval', 'n_intervals'),
    prevent_initial_call=False
)
def update_terminal_display(n_intervals):
    """
    Update the live terminal with recent command history
    """
    history = get_command_history()
    
    if not history:
        return html.Div("Waiting for commands...", className='terminal-empty')
    
    # Display last 20 commands (most recent at bottom)
    recent_commands = list(history)[-20:]
    
    terminal_lines = []
    for line in recent_commands:
        # Color code TX (blue), RX (green), ERROR (red), SIM (yellow)
        if 'TX:' in line:
            css_class = 'terminal-tx'
        elif 'RX:' in line:
            css_class = 'terminal-rx'
        elif 'ERROR:' in line:
            css_class = 'terminal-error'
        elif '[SIM]' in line:
            css_class = 'terminal-sim'
        else:
            css_class = 'terminal-line'
        
        terminal_lines.append(html.Div(line, className=css_class))
    
    return terminal_lines


@app.callback(
    Output('terminal_update_interval', 'n_intervals'),
    Input('clear_log_button', 'n_clicks'),
    prevent_initial_call=True
)
def clear_log(n_clicks):
    """
    Clear the command history log
    """
    if n_clicks is None:
        raise PreventUpdate
    
    from myshkin import command_history
    command_history.clear()
    print("Command log cleared")
    
    return 0


################################################################################
# Clock Frequency Measurement Callbacks
################################################################################

@app.callback(
    Output('clk-freq-display', 'children'),
    Input('measure-clk-btn', 'n_clicks'),
    prevent_initial_call=True
)
def measure_clk_frequency(n_clicks):
    """
    Measure CLK frequency using Forth command: 3 1 clk .
    """
    if n_clicks is None:
        raise PreventUpdate
    
    command = "3 1 clk ."
    response = chip.send_forth_command(command)
    
    if response:
        try:
            # Parse the frequency value from response
            freq_hz = int(response.strip().split()[-1])
            return f"{freq_hz:,} Hz"
        except (ValueError, IndexError):
            return f"Error: {response}"
    
    return "No response"


@app.callback(
    Output('smclk-freq-display', 'children'),
    Input('measure-smclk-btn', 'n_clicks'),
    prevent_initial_call=True
)
def measure_smclk_frequency(n_clicks):
    """
    Measure SMCLK frequency using Forth command: 3 1 smclk .
    """
    if n_clicks is None:
        raise PreventUpdate
    
    command = "3 1 smclk ."
    response = chip.send_forth_command(command)
    
    if response:
        try:
            # Parse the frequency value from response
            freq_hz = int(response.strip().split()[-1])
            return f"{freq_hz:,} Hz"
        except (ValueError, IndexError):
            return f"Error: {response}"
    
    return "No response"
