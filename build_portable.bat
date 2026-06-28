@echo off
cd /d "%~dp0"

echo === Instalation pyinstaller ===
.venv\Scripts\pip install pyinstaller -q

echo === Sbornuc portable ===
.venv\Scripts\pyinstaller --onedir --windowed ^
    --add-data "конкурент.xlsx;." ^
    --name konkurent ^
    gui.py

echo.
echo === Gotowo! ===
echo dist\konkurent\ — portable-panka
echo Zapusk: dist\konkurent\konkurent.exe
