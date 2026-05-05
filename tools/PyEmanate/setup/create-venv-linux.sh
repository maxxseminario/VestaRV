#!/bin/bash

# Creates a Python virtual environment for PyEmanate
# If the virtual environment already exists, then it updates the specified pip packages
# Run this script from this directory

# Stop if there are any errors
set -e

# Create a Linux Python virtual environment
project_dir=..
venv_dir=$project_dir/venv-linux

if [ ! -d "$venv_dir" ]; then
	echo "Creating a Python virtual environment for Linux..."
	python3 -m venv $venv_dir
fi

# Invoke the virtual environment
echo "Activating virtual environment..."
source $venv_dir/bin/activate

# Install Pip packages
echo "Installing packages..."
pip_packages=`cat pip-packages.txt`
pip install pip setuptools wheel -U
pip install $pip_packages -U
