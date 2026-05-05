REM First, invoke the virtual environment
call venv-win\Scripts\activate.bat

REM Create the executable
pyinstaller PyEmanate.spec
