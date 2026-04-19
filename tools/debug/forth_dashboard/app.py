"""
Dash App Configuration
Creates the app instance and initializes the Myshkin chip interface
"""
import dash
from myshkin import Myshkin

external_stylesheets = ['https://codepen.io/chriddyp/pen/bWLwgP.css']
app = dash.Dash(__name__, title="Myshkin MCU", update_title=None, external_stylesheets=external_stylesheets)
app.config['suppress_callback_exceptions'] = True  # Since layout is dynamic

# Instance of Myshkin chip that allows access to UART interface comms.
# Will try to connect to /dev/ttyUSB0 by default, or fall back to simulation mode
chip = Myshkin()
