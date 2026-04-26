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
import threading
import time

# Global acquisition thread control
acquisition_thread = None
acquisition_active = False
acquisition_lock = threading.Lock()


################################################################################
# Register Read/Write Callbacks
################################################################################

@app.callback(
    Output({'type': 'bitfield-dropdown', 'name': ALL}, 'value'),
    Output({'type': 'bitfield-numeric', 'name': ALL}, 'value'),
    Input({'type': 'reg-read-btn', 'name': ALL}, 'n_clicks'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'id'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'value'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'id'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'value'),
    State({'type': 'reg-read-btn', 'name': ALL}, 'id'),
    prevent_initial_call=True
)
def read_register_and_update_bitfields(n_clicks_list, dropdown_ids, dropdown_values_current, numeric_ids, numeric_values_current, button_ids):
    """
    Read register and update all bitfield controls
    """
    # Get the register name from the callback context
    ctx = dash.callback_context
    if not ctx.triggered:
        raise PreventUpdate
    
    trigger_id = ctx.triggered[0]['prop_id'].split('.')[0]
    import json
    button_info = json.loads(trigger_id)
    full_reg_name = button_info['name']
    
    # Parse peripheral and register — iterate to handle names with underscores (e.g. BIAS_CR)
    periph_name = None
    reg_name = None
    for potential_periph in PERIPHERALS.keys():
        if full_reg_name.startswith(potential_periph + '_'):
            candidate_reg = full_reg_name[len(potential_periph) + 1:]
            if candidate_reg in PERIPHERALS[potential_periph]['registers']:
                periph_name = potential_periph
                reg_name = candidate_reg
                break

    if periph_name is None or reg_name is None:
        raise PreventUpdate
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Read register value from chip
    reg_value = chip.read(addr)
    
    # Get bitfield definitions
    bitfields = get_bitfields(periph_name, reg_name)
    if not bitfields:
        raise PreventUpdate
    
    # Extract bitfield values and update only the matching controls
    # Start with current values to preserve other controls
    dropdown_values = list(dropdown_values_current) if dropdown_values_current else [dash.no_update] * len(dropdown_ids)
    numeric_values = list(numeric_values_current) if numeric_values_current else [dash.no_update] * len(numeric_ids)
    
    for i, dropdown_id in enumerate(dropdown_ids):
        if dropdown_id['name'].startswith(full_reg_name + '_'):
            # Extract field name by removing the register prefix
            field_name = dropdown_id['name'][len(full_reg_name) + 1:]
            if field_name in bitfields:
                field_val = extract_bitfield(reg_value, bitfields[field_name])
                dropdown_values[i] = field_val
    
    for i, numeric_id in enumerate(numeric_ids):
        if numeric_id['name'].startswith(full_reg_name + '_'):
            # Extract field name by removing the register prefix
            field_name = numeric_id['name'][len(full_reg_name) + 1:]
            if field_name in bitfields:
                field_val = extract_bitfield(reg_value, bitfields[field_name])
                numeric_values[i] = field_val
    
    return dropdown_values, numeric_values


@app.callback(
    Output({'type': 'reg-write-btn', 'name': MATCH}, 'n_clicks'),
    Input({'type': 'reg-write-btn', 'name': MATCH}, 'n_clicks'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'value'),
    State({'type': 'bitfield-dropdown', 'name': ALL}, 'id'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'value'),
    State({'type': 'bitfield-numeric', 'name': ALL}, 'id'),
    State({'type': 'reg-input', 'name': ALL}, 'value'),
    State({'type': 'reg-input', 'name': ALL}, 'id'),
    State({'type': 'reg-write-btn', 'name': MATCH}, 'id'),
    prevent_initial_call=True
)
def write_register_from_bitfields(n_clicks, dropdown_values, dropdown_ids, numeric_values, numeric_ids, reg_input_values, reg_input_ids, button_id):
    """
    Collect bitfield values and write to register (for CONTROL registers with bitfields)
    OR write from reg-input (for CONFIG/DATA registers without bitfields)
    """
    if n_clicks is None:
        raise PreventUpdate
    
    full_reg_name = button_id['name']
    
    # Parse peripheral and register — iterate to handle names with underscores (e.g. BIAS_CR)
    periph_name = None
    reg_name = None
    for potential_periph in PERIPHERALS.keys():
        if full_reg_name.startswith(potential_periph + '_'):
            candidate_reg = full_reg_name[len(potential_periph) + 1:]
            if candidate_reg in PERIPHERALS[potential_periph]['registers']:
                periph_name = potential_periph
                reg_name = candidate_reg
                break

    if periph_name is None or reg_name is None:
        raise PreventUpdate
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Get bitfield definitions
    bitfields = get_bitfields(periph_name, reg_name)
    
    if not bitfields:
        # No bitfields - this is a simple register (CONFIG/DATA type)
        # Get value from reg-input control
        for i, input_id in enumerate(reg_input_ids):
            if input_id['name'] == full_reg_name:
                value = reg_input_values[i]
                if value is not None:
                    chip.write(addr, int(value))
                    raise PreventUpdate
        raise PreventUpdate
    
    # Has bitfields - build register value from bitfields
    reg_value = 0
    
    # Process dropdown values
    for i, dropdown_id in enumerate(dropdown_ids):
        if dropdown_id['name'].startswith(full_reg_name + '_'):
            # Extract field name by removing the register prefix
            field_name = dropdown_id['name'][len(full_reg_name) + 1:]
            if field_name in bitfields:
                reg_value = insert_bitfield(reg_value, bitfields[field_name], dropdown_values[i])
    
    # Process numeric values
    for i, numeric_id in enumerate(numeric_ids):
        if numeric_id['name'].startswith(full_reg_name + '_'):
            # Extract field name by removing the register prefix
            field_name = numeric_id['name'][len(full_reg_name) + 1:]
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
    
    # Parse peripheral and register — iterate to handle names with underscores (e.g. BIAS_CR)
    periph_name = None
    reg_name = None
    for potential_periph in PERIPHERALS.keys():
        if full_name.startswith(potential_periph + '_'):
            candidate_reg = full_name[len(potential_periph) + 1:]
            if candidate_reg in PERIPHERALS[potential_periph]['registers']:
                periph_name = potential_periph
                reg_name = candidate_reg
                break

    if periph_name is None or reg_name is None:
        return "Error: Invalid name"
    
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
    periph_name = None
    reg_name = None
    for potential_periph in PERIPHERALS.keys():
        if full_name.startswith(potential_periph + '_'):
            candidate_reg = full_name[len(potential_periph) + 1:]
            if candidate_reg in PERIPHERALS[potential_periph]['registers']:
                periph_name = potential_periph
                reg_name = candidate_reg
                break

    if periph_name is None or reg_name is None:
        return 0
    
    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    
    # Read from chip
    value = chip.read(addr)
    
    # Fix MSB inversion bug in SARADC DATA register (hardware issue)
    if addr == 0x4B0C:  # SARADC_DATA
        value = value ^ 512  # Invert bit 9 (MSB of 10-bit value)
    
    return value


# Note: The old write_register callback has been removed because
# write_register_from_bitfields now handles all CONTROL register writes
# via bitfield controls. For registers without bitfields, the legacy
# reg-input control is still used with the read_register_control callback.


# ---------------------------------------------------------------------------
# BIAS_TIA_G_POT – thermometer lookup table
# 17 discrete slider positions (0 = max R, 16 = min R).
# Assumed bit layout (adjust if hardware differs):
#   bit 15 = 1 MΩ short; bits 0-14 = 15 × 60 kΩ thermometer shorts
# ---------------------------------------------------------------------------
_TIA_GAIN_STEPS = [
    0x00000000,  # 0:  max R  – nothing shorted
    0x00008000,  # 1:  1M shorted            (large step)
    0x00008001,  # 2:  1M + 1×60k
    0x00008003,  # 3:  1M + 2×60k
    0x00008007,  # 4:  1M + 3×60k
    0x0000800F,  # 5:  1M + 4×60k
    0x0000801F,  # 6:  1M + 5×60k
    0x0000803F,  # 7:  1M + 6×60k
    0x0000807F,  # 8:  1M + 7×60k
    0x000080FF,  # 9:  1M + 8×60k
    0x000081FF,  # 10: 1M + 9×60k
    0x000083FF,  # 11: 1M + 10×60k
    0x000087FF,  # 12: 1M + 11×60k
    0x00008FFF,  # 13: 1M + 12×60k
    0x00009FFF,  # 14: 1M + 13×60k
    0x0000BFFF,  # 15: 1M + 14×60k
    0x0000FFFF,  # 16: min R – 1M + all 15×60k shorted
]
_TIA_GAIN_REG_TO_SLIDER = {reg: pos for pos, reg in enumerate(_TIA_GAIN_STEPS)}


def _tia_slider_to_reg(pos):
    """Convert 0-16 slider position to register value for BIAS_TIA_G_POT."""
    pos = max(0, min(16, int(pos)))
    return _TIA_GAIN_STEPS[pos]


def _tia_reg_to_slider(reg_val):
    """Convert raw register value to nearest 0-16 slider position for BIAS_TIA_G_POT."""
    if reg_val in _TIA_GAIN_REG_TO_SLIDER:
        return _TIA_GAIN_REG_TO_SLIDER[reg_val]
    # Fallback: find the closest step
    return min(range(17), key=lambda i: abs(_TIA_GAIN_STEPS[i] - reg_val))


@app.callback(
    [Output({'type': 'reg-slider', 'name': MATCH}, 'value'),
     Output({'type': 'reg-slider-input', 'name': MATCH}, 'value')],
    [Input({'type': 'reg-slider', 'name': MATCH}, 'value'),
     Input({'type': 'reg-slider-input', 'name': MATCH}, 'value'),
     Input({'type': 'reg-bias-read-btn', 'name': MATCH}, 'n_clicks')],
    [State({'type': 'reg-slider', 'name': MATCH}, 'id')],
    prevent_initial_call=True
)
def sync_slider_and_input(slider_value, input_value, read_clicks, slider_id):
    """
    Sync slider and numeric input below it, and write value to register (for BIAS registers).
    Also handles read button: reads the register from the chip and updates both controls.
    """
    ctx = dash.callback_context
    if not ctx.triggered:
        raise PreventUpdate

    trigger_id = ctx.triggered[0]['prop_id']

    # Parse peripheral and register name (shared by all branches)
    full_name = slider_id['name']
    periph_name = None
    reg_name = None
    for potential_periph in PERIPHERALS.keys():
        if full_name.startswith(potential_periph + '_'):
            periph_name = potential_periph
            reg_name = full_name[len(potential_periph)+1:]
            break

    if periph_name is None or reg_name is None:
        raise PreventUpdate

    if reg_name not in PERIPHERALS[periph_name]['registers']:
        raise PreventUpdate

    addr = PERIPHERALS[periph_name]['registers'][reg_name]['addr']
    is_tia = (reg_name == 'BIAS_TIA_G_POT')

    # Read button: read from chip and update controls without writing
    if 'reg-bias-read-btn' in trigger_id:
        raw = chip.read(addr)
        if is_tia:
            pos = _tia_reg_to_slider(raw)
            return pos, pos
        return raw, raw

    # Slider or numeric input changed: sync and write to chip
    if 'reg-slider-input' in trigger_id:
        value = input_value
    else:
        value = slider_value

    if value is None:
        raise PreventUpdate

    if is_tia:
        # value is a slider position 0-16; convert to actual register bits before writing
        reg_val = _tia_slider_to_reg(value)
        chip.write(addr, reg_val)
    else:
        chip.write(addr, int(value))

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


################################################################################
# SARADC Fast Data Acquisition
################################################################################

def continuous_acquisition_loop(log_file):
    """
    Continuous acquisition loop that runs in background thread.
    Reads SARADC as fast as possible and writes to log file.
    """
    global acquisition_active
    
    print(f"Acquisition thread started, logging to: {log_file}")
    sample_count = 0
    start_time = time.time()
    
    while True:
        with acquisition_lock:
            if not acquisition_active:
                break
        
        try:
            # Read SARADC DATA register (address 0x4B0C)
            adc_value = chip.read(0x4B0C)
            
            # Validate ADC value (10-bit ADC: 0-1023)
            if adc_value < 0 or adc_value > 1023:
                continue
            
            # Fix hardware bug: Invert MSB (bit 9) of 10-bit ADC value
            adc_value = adc_value ^ 512
            
            # Calculate timestamp
            timestamp = time.time() - start_time
            
            # Write to log file immediately
            with open(log_file, 'a') as f:
                f.write(f"{timestamp:.6f}, {adc_value}, 0x{adc_value:03X}\n")
            
            sample_count += 1
            
            # Print progress every 100 samples
            if sample_count % 100 == 0:
                elapsed = time.time() - start_time
                rate = sample_count / elapsed if elapsed > 0 else 0
                print(f"Acquired {sample_count} samples, rate: {rate:.1f} Hz")
                
        except Exception as e:
            print(f"Acquisition error: {e}")
            continue
    
    elapsed = time.time() - start_time
    rate = sample_count / elapsed if elapsed > 0 else 0
    print(f"Acquisition thread stopped. Total: {sample_count} samples in {elapsed:.2f}s ({rate:.1f} Hz)")


@app.callback(
    Output('saradc-acquisition-interval', 'disabled'),
    Output('saradc-sample-count-interval', 'disabled'),
    Output('saradc-data-store', 'data'),
    Output('saradc-status-display', 'children'),
    Input('saradc-start-btn', 'n_clicks'),
    Input('saradc-stop-btn', 'n_clicks'),
    State('saradc-data-store', 'data'),
    prevent_initial_call=True
)
def control_saradc_acquisition(start_clicks, stop_clicks, store_data):
    """
    Start or stop SARADC data acquisition using background thread
    """
    global acquisition_thread, acquisition_active
    
    ctx = dash.callback_context
    if not ctx.triggered:
        raise PreventUpdate
    
    trigger_id = ctx.triggered[0]['prop_id'].split('.')[0]
    
    if trigger_id == 'saradc-start-btn':
        # Start acquisition in background thread
        import os
        
        with acquisition_lock:
            if acquisition_active:
                raise PreventUpdate  # Already running
            
            print("SARADC acquisition starting...")
            
            # Create log file with timestamp (relative path)
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            log_dir = "saradc_logs"
            os.makedirs(log_dir, exist_ok=True)
            log_file_relative = os.path.join(log_dir, f"saradc_data_{timestamp}.txt")
            log_file_absolute = os.path.abspath(log_file_relative)
            
            print(f"Log file created: {log_file_absolute}")
            
            # Write header to log file
            with open(log_file_absolute, 'w') as f:
                f.write("# SARADC Data Acquisition Log\n")
                f.write(f"# Started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write("# Timestamp(s), ADC_Value(decimal), ADC_Value(hex)\n")
            
            # Start background acquisition thread (pass absolute path for file operations)
            acquisition_active = True
            acquisition_thread = threading.Thread(target=continuous_acquisition_loop, args=(log_file_absolute,), daemon=True)
            acquisition_thread.start()
        
        return True, False, {'samples': [], 'timestamps': [], 'acquiring': True, 'log_file': log_file_absolute, 'log_file_display': log_file_relative, 'start_time': time.time()}, 'Acquiring...'
    
    elif trigger_id == 'saradc-stop-btn':
        # Stop acquisition thread
        print("SARADC acquisition stopping...")
        
        with acquisition_lock:
            acquisition_active = False
        
        # Wait for thread to finish (with timeout)
        if acquisition_thread and acquisition_thread.is_alive():
            acquisition_thread.join(timeout=2.0)
        
        log_file = None
        log_file_display = None
        
        if store_data and store_data.get('acquiring'):
            # Count actual samples from log file
            log_file = store_data.get('log_file')
            log_file_display = store_data.get('log_file_display')
            sample_count = 0
            if log_file:
                import os
                try:
                    # Count data lines in log file (skip comment lines)
                    with open(log_file, 'r') as f:
                        for line in f:
                            if not line.startswith('#') and line.strip() and ',' in line:
                                sample_count += 1
                except Exception as e:
                    print(f"Error counting samples in log: {e}")
                    sample_count = 0
                
                # Write summary to log file
                with open(log_file, 'a') as f:
                    f.write(f"\n# Acquisition stopped: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                    f.write(f"# Total samples: {sample_count}\n")
                print(f"Total samples collected: {sample_count}")
        
        return True, True, {'samples': [], 'timestamps': [], 'acquiring': False, 'log_file': log_file, 'log_file_display': log_file_display}, 'Stopped'
    
    raise PreventUpdate


@app.callback(
    Output('saradc-sample-count', 'children'),
    Input('saradc-sample-count-interval', 'n_intervals'),
    State('saradc-data-store', 'data'),
    prevent_initial_call=True
)
def update_sample_count_realtime(n_intervals, store_data):
    """
    Update sample count display in real-time during acquisition
    """
    if not store_data or not store_data.get('acquiring'):
        raise PreventUpdate
    
    log_file = store_data.get('log_file')
    if not log_file:
        raise PreventUpdate
    
    # Count samples in log file
    sample_count = 0
    try:
        with open(log_file, 'r') as f:
            for line in f:
                if not line.startswith('#') and line.strip() and ',' in line:
                    sample_count += 1
    except Exception as e:
        # File might be being written, just return last known count
        raise PreventUpdate
    
    return str(sample_count)


@app.callback(
    Output('saradc-plot', 'figure'),
    Output('saradc-sample-count', 'children', allow_duplicate=True),
    Output('saradc-log-file', 'children'),
    Input('saradc-stop-btn', 'n_clicks'),
    State('saradc-data-store', 'data'),
    prevent_initial_call=True
)
def update_saradc_plot(stop_clicks, store_data):
    """
    Update histogram plot of SARADC data after acquisition stops
    """
    import plotly.graph_objs as go
    import os
    
    if not store_data:
        # Return empty plot
        figure = {
            'data': [],
            'layout': go.Layout(
                title='ADC Value Histogram',
                xaxis={'title': 'ADC Value (Bin)', 'gridcolor': '#ecf0f1'},
                yaxis={'title': 'Count', 'gridcolor': '#ecf0f1'},
                margin={'l': 60, 'r': 20, 't': 40, 'b': 50},
                plot_bgcolor='#ffffff',
                paper_bgcolor='#ffffff',
                font={'size': 11}
            )
        }
        return figure, '0', '--'
    
    log_file = store_data.get('log_file', '--')
    
    # Read samples from log file
    samples = []
    if log_file and log_file != '--':
        try:
            with open(log_file, 'r') as f:
                for line in f:
                    if not line.startswith('#') and line.strip() and ',' in line:
                        try:
                            # Parse: "timestamp, value, hex_value"
                            parts = line.strip().split(',')
                            if len(parts) >= 2:
                                value = int(parts[1].strip())
                                # Validate (10-bit ADC: 0-1023)
                                if 0 <= value <= 1023:
                                    samples.append(value)
                        except (ValueError, IndexError):
                            continue
        except Exception as e:
            print(f"Error reading log file for histogram: {e}")
    
    print(f"Generating histogram with {len(samples)} samples from log file")  # Debug logging
    
    # Create histogram
    figure = {
        'data': [
            go.Histogram(
                x=samples,
                xbins=dict(start=0, end=1023, size=1),  # One bin per ADC value (0-1023)
                marker={'color': '#3498db', 'line': {'color': '#2980b9', 'width': 0.5}},
                name='ADC Distribution'
            )
        ],
        'layout': go.Layout(
            title=f'ADC Value Distribution ({len(samples)} samples)',
            xaxis={'title': 'ADC Value (Bin)', 'gridcolor': '#ecf0f1', 'range': [0, 1023]},
            yaxis={'title': 'Count', 'gridcolor': '#ecf0f1'},
            margin={'l': 60, 'r': 20, 't': 60, 'b': 50},
            hovermode='closest',
            plot_bgcolor='#ffffff',
            paper_bgcolor='#ffffff',
            font={'size': 11},
            bargap=0.01
        )
    }
    
    # Format log file path for display (use relative path if available)
    if log_file and log_file != '--':
        log_file_display = store_data.get('log_file_display', os.path.basename(log_file))
    else:
        log_file_display = '--'
    
    return figure, str(len(samples)), log_file_display

