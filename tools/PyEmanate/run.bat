REM Runs PyEmanate on Windows

REM First, invoke the virtual environment
call venv-win\Scripts\activate.bat

REM Finally, run the python file
cd python
start /B pythonw PyEmanate.py
cd ..