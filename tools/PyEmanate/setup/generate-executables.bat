cd ..

REM Invoke the virtual environment
call venv-win\Scripts\activate.bat

cd python
pyinstaller --onefile PyEmanate.py
