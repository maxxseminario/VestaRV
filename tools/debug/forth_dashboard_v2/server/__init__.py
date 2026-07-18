"""Forth Dashboard v2 backend package (WP2).

Talks to the Myshkin chip's on-chip rv4th Forth REPL over UART.  All modules
here are pure Python + the three declared runtime deps (fastapi / uvicorn /
pyserial); pyserial and fastapi are imported lazily so the parser and
serial-manager unit tests run with neither installed.
"""
