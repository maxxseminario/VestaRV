#!/usr/bin/env python3
"""
Plot SARADC log files - ADC value vs sample number with INL/DNL analysis

Usage:
    python3 plot_saradc_log.py <log_file> [--min-code MIN] [--max-code MAX]
    python3 plot_saradc_log.py forth_dashboard/saradc_logs/saradc_data_20260415_213844.txt
    python3 plot_saradc_log.py my_data.txt --min-code 200 --max-code 800

This script reads SARADC acquisition log files and plots the ADC values
over sample number (sequential order), showing the distribution, trends,
and linearity metrics (INL/DNL).
"""

import sys
import os
import argparse
import numpy as np
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


def calculate_dnl_inl(adc_values, num_codes=1024, min_code=0, max_code=1023):
    """
    Calculate DNL and INL from ADC histogram
    
    DNL (Differential Nonlinearity): Deviation of each code bin width from ideal (1 LSB)
    INL (Integral Nonlinearity): Cumulative error, deviation from ideal transfer function
    
    Args:
        adc_values: List of ADC samples
        num_codes: Number of ADC codes (1024 for 10-bit)
        min_code: Minimum code to analyze (default: 0)
        max_code: Maximum code to analyze (default: 1023)
        
    Returns:
        tuple: (codes, dnl, inl, histogram)
    """
    # Validate range
    min_code = max(0, min_code)
    max_code = min(num_codes - 1, max_code)
    
    # Build histogram
    histogram, _ = np.histogram(adc_values, bins=range(num_codes + 1))
    
    # Calculate ideal count per code (uniform distribution)
    # Only count samples in the specified range
    samples_in_range = sum(1 for v in adc_values if min_code <= v <= max_code)
    codes_in_range = max_code - min_code + 1
    ideal_count = samples_in_range / codes_in_range if codes_in_range > 0 else 0
    
    # Calculate DNL for the specified range
    # DNL(i) = (actual_count(i) / ideal_count) - 1
    # Expressed in LSB units
    dnl = np.zeros(num_codes)
    for i in range(min_code, max_code + 1):
        if ideal_count > 0:
            dnl[i] = (histogram[i] / ideal_count) - 1.0
        else:
            dnl[i] = 0
    
    # Calculate INL (cumulative sum of DNL)
    # INL shows overall deviation from ideal transfer function
    inl = np.cumsum(dnl)
    
    codes = np.arange(num_codes)
    
    return codes, dnl, inl, histogram, min_code, max_code


def plot_saradc_data(sample_numbers, adc_values, timestamps, log_file, min_code=0, max_code=1023):
    """
    Plot ADC values vs sample number with INL/DNL analysis
    
    Args:
        sample_numbers: List of sample indices
        adc_values: List of ADC values
        timestamps: List of timestamps
        log_file: Path to log file (for title)
        min_code: Minimum code for INL/DNL analysis
        max_code: Maximum code for INL/DNL analysis
    """
    if not adc_values:
        print("No data to plot")
        return
    
    # Calculate statistics
    mean_value = np.mean(adc_values)
    min_value = min(adc_values)
    max_value = max(adc_values)
    std_value = np.std(adc_values)
    
    # Calculate acquisition rate
    if len(timestamps) > 1:
        total_time = timestamps[-1] - timestamps[0]
        rate = len(timestamps) / total_time if total_time > 0 else 0
    else:
        rate = 0
    
    # Calculate DNL and INL
    codes, dnl, inl, histogram, actual_min, actual_max = calculate_dnl_inl(adc_values, min_code=min_code, max_code=max_code)
    
    # Calculate DNL/INL statistics only for the specified range
    dnl_range = dnl[actual_min:actual_max+1]
    inl_range = inl[actual_min:actual_max+1]
    dnl_max = np.max(np.abs(dnl_range))
    inl_max = np.max(np.abs(inl_range))
    dnl_rms = np.sqrt(np.mean(dnl_range**2))
    inl_rms = np.sqrt(np.mean(inl_range**2))
    
    # Create figure with 4 subplots (2x2 grid)
    fig = plt.figure(figsize=(16, 10))
    gs = fig.add_gridspec(2, 2, hspace=0.3, wspace=0.3)
    
    # Plot 1: ADC value vs sample number (time series)
    ax1 = fig.add_subplot(gs[0, :])  # Top row, span both columns
    ax1.plot(sample_numbers, adc_values, linewidth=0.8, color='#3498db', alpha=0.7)
    ax1.set_xlabel('Sample Number')
    ax1.set_ylabel('ADC Value')
    ax1.set_title(f'SARADC Data: {os.path.basename(log_file)}')
    ax1.grid(True, alpha=0.3)
    ax1.axhline(y=mean_value, color='r', linestyle='--', linewidth=1, label=f'Mean: {mean_value:.1f}')
    ax1.legend()
    
    # Add statistics text
    stats_text = f'Samples: {len(adc_values)} | Min: {min_value} | Max: {max_value} | Mean: {mean_value:.1f} | Std: {std_value:.2f} | Rate: {rate:.1f} Hz'
    ax1.text(0.02, 0.98, stats_text, transform=ax1.transAxes, 
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    # Plot 2: Histogram
    ax2 = fig.add_subplot(gs[1, 0])  # Bottom left
    ax2.bar(codes, histogram, width=1.0, color='#3498db', alpha=0.7, edgecolor='#2980b9', linewidth=0.3)
    ax2.set_xlabel('ADC Code')
    ax2.set_ylabel('Count')
    ax2.set_title('Code Distribution (Histogram)')
    ax2.grid(True, alpha=0.3, axis='y')
    ax2.set_xlim(0, 1023)
    
    # Plot 3: DNL
    ax3 = fig.add_subplot(gs[1, 1])  # Bottom right upper
    ax3.plot(codes[actual_min:actual_max+1], dnl[actual_min:actual_max+1], linewidth=0.8, color='#e74c3c', alpha=0.8)
    ax3.set_xlabel('ADC Code')
    ax3.set_ylabel('DNL (LSB)')
    ax3.set_title(f'Differential Nonlinearity (DNL) [Codes {actual_min}-{actual_max}]')
    ax3.grid(True, alpha=0.3)
    ax3.axhline(y=0, color='k', linestyle='-', linewidth=0.8)
    ax3.axhline(y=1, color='r', linestyle='--', linewidth=0.8, alpha=0.5, label='±1 LSB')
    ax3.axhline(y=-1, color='r', linestyle='--', linewidth=0.8, alpha=0.5)
    ax3.set_xlim(actual_min, actual_max)
    
    # Add DNL statistics text
    dnl_stats = f'Max: {dnl_max:.3f} LSB | RMS: {dnl_rms:.3f} LSB'
    ax3.text(0.02, 0.98, dnl_stats, transform=ax3.transAxes,
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='lightcoral', alpha=0.5))
    ax3.legend()
    
    # Create second figure for INL (larger view)
    fig2, ax4 = plt.subplots(1, 1, figsize=(16, 6))
    ax4.plot(codes[actual_min:actual_max+1], inl[actual_min:actual_max+1], linewidth=0.8, color='#9b59b6', alpha=0.8)
    ax4.set_xlabel('ADC Code')
    ax4.set_ylabel('INL (LSB)')
    ax4.set_title(f'Integral Nonlinearity (INL) [Codes {actual_min}-{actual_max}] - {os.path.basename(log_file)}')
    ax4.grid(True, alpha=0.3)
    ax4.axhline(y=0, color='k', linestyle='-', linewidth=0.8)
    ax4.axhline(y=1, color='r', linestyle='--', linewidth=0.8, alpha=0.5, label='±1 LSB')
    ax4.axhline(y=-1, color='r', linestyle='--', linewidth=0.8, alpha=0.5)
    ax4.set_xlim(actual_min, actual_max)
    
    # Add INL statistics text
    inl_stats = f'Max: {inl_max:.3f} LSB | RMS: {inl_rms:.3f} LSB'
    ax4.text(0.02, 0.98, inl_stats, transform=ax4.transAxes,
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='plum', alpha=0.5))
    ax4.legend()
    
    # Print summary statistics
    print("\n" + "="*60)
    print("ADC Linearity Analysis")
    print("="*60)
    print(f"Analysis range: Codes {actual_min} to {actual_max}")
    print(f"DNL - Max: {dnl_max:.4f} LSB, RMS: {dnl_rms:.4f} LSB")
    print(f"INL - Max: {inl_max:.4f} LSB, RMS: {inl_rms:.4f} LSB")
    print(f"Missing codes in range: {np.sum(histogram[actual_min:actual_max+1] == 0)} / {actual_max - actual_min + 1}")
    print("="*60 + "\n")
    
    plt.show()


def main():
    """Main function"""
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='Plot SARADC log files with ADC linearity analysis (DNL/INL)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 plot_saradc_log.py data.txt
  python3 plot_saradc_log.py data.txt --min-code 200 --max-code 800
  python3 plot_saradc_log.py forth_dashboard/saradc_logs/saradc_data_20260415_213844.txt
        """
    )
    
    parser.add_argument('log_file', help='Path to SARADC log file')
    parser.add_argument('--min-code', type=int, default=0, 
                        help='Minimum ADC code for DNL/INL analysis (default: 0)')
    parser.add_argument('--max-code', type=int, default=1023,
                        help='Maximum ADC code for DNL/INL analysis (default: 1023)')
    
    args = parser.parse_args()
    
    # Validate range
    if args.min_code < 0 or args.min_code > 1023:
        print(f"Error: --min-code must be between 0 and 1023")
        sys.exit(1)
    if args.max_code < 0 or args.max_code > 1023:
        print(f"Error: --max-code must be between 0 and 1023")
        sys.exit(1)
    if args.min_code >= args.max_code:
        print(f"Error: --min-code must be less than --max-code")
        sys.exit(1)
    
    # Read log file
    sample_numbers, adc_values, timestamps = read_saradc_log(args.log_file)
    
    if adc_values is None or len(adc_values) == 0:
        print("Error: No valid data found in log file")
        sys.exit(1)
    
    # Plot data
    plot_saradc_data(sample_numbers, adc_values, timestamps, args.log_file, 
                     min_code=args.min_code, max_code=args.max_code)


if __name__ == '__main__':
    main()
