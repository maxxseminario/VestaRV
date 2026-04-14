"""
Myshkin MCU Configuration Interface
Main entry point for the Dash web application
"""
from dash import dcc, html
from dash.dependencies import Output, Input

from app import app
import layout as layout_module
import callbacks
import logging

app.layout = html.Div([
    dcc.Location(id='url', refresh=False),
    html.Div(id='page-content')
])

@app.callback(Output('page-content', 'children'),
              [Input('url', 'pathname')])
def display_page(pathname):
    return layout_module.layout


################################################################################
# Main Entry
################################################################################

if __name__ == '__main__':
    print("=" * 60)
    print("Myshkin MCU Configuration Interface")
    print("=" * 60)
    print("\nStarting web server...")
    print("Once started, open your browser to:")
    print("  → http://localhost:8050")
    print("\nPress Ctrl+C to stop the server")
    print("=" * 60)
    
    # Disable most logging for Flask
    log = logging.getLogger('werkzeug')
    log.setLevel(logging.ERROR)

    # Launch app
    app.run(host='0.0.0.0', port=8050, debug=True)
