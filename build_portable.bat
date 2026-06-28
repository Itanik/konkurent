@echo off
cd /d "%~dp0"

echo === Installation pyinstaller ===
.venv\Scripts\pip install pyinstaller -q

for /f "delims=" %%i in ('.venv\Scripts\python.exe -c "import sysconfig; print(sysconfig.get_paths()['purelib'])"') do set SITE_PKGS=%%i

set MYPYC_PYD=
for %%f in ("%SITE_PKGS%\*__mypyc*.pyd") do set MYPYC_PYD=%%f
set MYPYC_BINARY=
if defined MYPYC_PYD (
    set MYPYC_BINARY=--add-binary "%MYPYC_PYD%;."
    echo mypyc found
) else (
    echo mypyc not found (not critical)
)

echo === Building portable ===
.venv\Scripts\pyinstaller --onedir --windowed ^
    --add-data "конкурент.xlsx;." ^
    %MYPYC_BINARY% ^
    --name kongkurent ^
    gui.py

echo.
echo === Done! ===
echo dist\kongkurent\ is the portable folder
echo Run: dist\kongkurent\kongkurent.exe
