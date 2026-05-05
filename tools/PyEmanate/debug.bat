REM Runs PyEmanate on Windows

REM First, invoke the virtual environment
call venv-win\Scripts\activate.bat

REM Finally, run the python file
cd python
python PyEmanate.py
cd ..
set /p DUMMY=Press ENTER to quit...
