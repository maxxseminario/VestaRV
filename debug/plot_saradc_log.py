#!/usr/bin/env python3
"""
Plot SARADC log files - ADC value vs sample number

Usage:
    python3 plot_saradc_log.py <log_file>
    python3 plot_saradc_log.py forth_dashboard/saradc_logs/saradc_data_20260415_213844.txt

This script reads SARADC acquisition log files and plots the ADC values
over sample number (sequential order), showing the distribution and trends.
"""

import sys
import os
import matplotlib.pyplot as plt


def read_saradc_log(log_file):
    """
    Read SARADC log file and extract ADC values
    
    Args:
        log_file: Path to log file
        
    Returns:
        tuple: (sample_numbers, adc_values, timestamps)
    """
    sample_numbers = []
    adc_values = []
    timestamps = []
    
    if not os.path.exists(log_file):
        print(f"Error: Log file not found: {log_file}")
        return None, None, None
    
    sample_count = 0
    with open(log_file, 'r') as f:
        for line in f:
            # Skip comment lines and empty lines
            if line.startswith('#') or not line.strip():
                continue
            
            # Parse data line: "timestamp, value, hex_value"
            if ',' in line:
                try:
                    parts = line.strip().split(',')
                    if len(parts) >= 2:
                        timestamp = float(parts[0].strip())
                        value = int(parts[1].strip())
                        
                        # Validate 10-bit ADC range
                        if 0 <= value <= 1023:
                            sample_numbers.append(sample_count)
                            adc_values.append(value)
                            timestamps.append(timestamp)
                            sample_count += 1
                except (ValueError, IndexError) as e:
                    print(f"Warning: Failed to parse line: {line.strip()} - {e}")
                    continue
    
    print(f"Read {len(adc_values)} valid samples from {log_file}")
    return sample_numbers, adc_values, timestamps


def plot_saradc_data(sample_numbers, adc_values, timestamps, log_file):
    """
    Plot ADC values vs sample number
    
    Args:
        sample_numbers: List of sample indices
        adc_values: List of ADC values
        timestamps: List of timestamps
        log_file: Path to log file (for title)
    """
    if not adc_values:
        print("No data to plot")
        return
    
    # Calculate statistics
    mean_value = sum(adc_values) / len(adc_values)
    min_value = min(adc_values)
    max_value = max(adc_values)
    
    # Calculate acquisition rate
    if len(timestamps) > 1:
        total_time = timestamps[-1] - timestamps[0]
        rate = len(timestamps) / total_time if total_time > 0 else 0
    else:
        rate = 0
    
    # Create figure with 2 subplots
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))
    
    # Plot 1: ADC value vs sample number
    ax1.plot(sample_numbers, adc_values, linewidth=0.8, color='#3498db', alpha=0.7)
    ax1.set_xlabel('Sample Number')
    ax1.set_ylabel('ADC Value')
    ax1.set_title(f'SARADC Data: {os.path.basename(log_file)}')
    ax1.grid(True, alpha=0.3)
    ax1.axhline(y=mean_value, color='r', linestyle='--', linewidth=1, label=f'Mean: {mean_value:.1f}')
    ax1.legend()
    
    # Add statistics text
    stats_text = f'Samples: {len(adc_values)} | Min: {min_value} | Max: {max_value} | Mean: {mean_value:.1f} | Rate: {rate:.1f} Hz'
    ax1.text(0.02, 0.98, stats_text, transform=ax1.transAxes, 
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    # Plot 2: Histogram
    ax2.hist(adc_values, bins=range(0, 1024), color='#3498db', alpha=0.7, edgecolor='#2980b9', linewidth=0.5)
    ax2.set_xlabel('ADC Value (Bin)')
    ax2.set_ylabel('Count')
    ax2.set_title('ADC Value Distribution')
    ax2.grid(True, alpha=0.3, axis='y')
    ax2.set_xlim(0, 1023)
    
    plt.tight_layout()
    plt.show()


def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("Usage: python3 plot_saradc_log.py <log_file>")
        print("\nExample:")
        print("  python3 plot_saradc_log.py forth_dashboard/saradc_logs/saradc_data_20260415_213844.txt")
        print("\nAvailable log files:")
        
        # List available log files
        log_dir = "forth_dashboard/saradc_logs"
        if os.path.exists(log_dir):
            log_files = sorted([f for f in os.listdir(log_dir) if f.endswith('.txt')])
            for log_file in log_files:
                print(f"  {os.path.join(log_dir, log_file)}")
        else:
            print(f"  Log directory not found: {log_dir}")
        
        sys.exit(1)
    
    log_file = sys.argv[1]
    
    # Read log file
    sample_numbers, adc_values, timestamps = read_saradc_log(log_file)
    
    if adc_values is None or len(adc_values) == 0:
        print("Error: No valid data found in log file")
        sys.exit(1)
    
    # Plot data
    plot_saradc_data(sample_numbers, adc_values, timestamps, log_file)


if __name__ == '__main__':
    main()
