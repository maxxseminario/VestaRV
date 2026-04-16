# Fast SARADC Acquisition

High-speed SARADC data acquisition script that bypasses GUI limitations.

## Usage

```bash
# Run for 10 seconds (auto-named log file in logs/)
python3 fast_saradc_acquire.py 10

# Run for 30 seconds with custom filename
python3 fast_saradc_acquire.py 30 my_test.txt

# Run until Ctrl+C
python3 fast_saradc_acquire.py
```

All log files are automatically saved to the `logs/` subdirectory.

## Performance

- GUI acquisition: ~9 Hz
- This script: 20-30 Hz or higher (UART limited)

## Requirements

- SARADC must be pre-configured via GUI to run continuously
- UART access to Myshkin chip (/dev/ttyAMA0)
