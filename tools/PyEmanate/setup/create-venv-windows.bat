REM Creates a Python virtual environment for PyEmanate
REM Run from this directory

set project_dir=..\
set venv_dir=%project_dir%\venv-win

if not exist %venv_dir% (
	echo "Creating a Windows Python virtual environment..."
	python -m venv %venv_dir%
)

echo "Activating virtual environment..."
call %venv_dir%\Scripts\activate.bat

echo "Installing packages..."
set /p pip_packages=<pip-packages.txt
pip install pip -U
pip install setuptools wheel -U
pip install %pip_packages% -U
