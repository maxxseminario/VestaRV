"""pytest bootstrap: make the `server` package importable from the repo dir."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
