# Fast SARADC Acquisition

High-speed SARADC data acquisition scripts with different measurement modes.

## Scripts

### fast_saradc_acquire.py - Continuous Mode
Reads SARADC in continuous mode at maximum speed (assumes ADC pre-configured).

```bash
# Run for 10 seconds (auto-named log file in logs/)
python3 fast_saradc_acquire.py 10

# Run for 30 seconds with custom filename
python3 fast_saradc_acquire.py 30 my_test.txt

# Run until Ctrl+C
python3 fast_saradc_acquire.py
```

**Performance:** 20-30 Hz or higher (UART limited)

### single_shot_saradc.py - Single-Shot Mode
Triggers individual ADC conversions, one at a time.

```bash
# Acquire 100 samples
python3 single_shot_saradc.py 100

# Acquire 1000 samples with custom filename
python3 single_shot_saradc.py 1000 my_single_shot.txt

# Run until Ctrl+C
python3 single_shot_saradc.py
```

**How it works:**
1. Configures SARADC for single-shot mode (CR[8] = 0)
2. Enables ADC to start conversion (CR[5] = 1)
3. Polls status register until data ready (SR[1] = 1)
4. Reads DATA register
5. Clears data_valid flag
6. Disables ADC
7. Repeats for next sample

**Performance:** ~5-10 Hz (limited by conversion + polling overhead)

## Output

All log files are automatically saved to the `logs/` subdirectory.

## Requirements

- UART access to Myshkin chip (/dev/ttyAMA0)

