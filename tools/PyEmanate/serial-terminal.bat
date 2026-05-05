REM Runs Serial Terminal on Windows

REM First, invoke the virtual environment
call venv-win\Scripts\activate.bat

REM Finally, run the python file
cd python
python SerialTerminal.py
cd ..