#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "=== Установка pyinstaller ==="
.venv/bin/pip install pyinstaller -q

SITE_PKGS=$(.venv/bin/python3 -c "import sysconfig; print(sysconfig.get_paths()['purelib'])")
MYPYC_SO=$(ls "$SITE_PKGS"/*__mypyc*.so 2>/dev/null | head -1)
MYPYC_BINARY=""
if [ -n "$MYPYC_SO" ]; then
    MYPYC_BINARY="--add-binary $MYPYC_SO:."
    echo "  найден mypyc: $MYPYC_SO"
else
    echo "  mypyc не найден (не критично)"
fi

echo "=== Сборка portable ==="
.venv/bin/pyinstaller --onedir \
    --add-data "конкурент.xlsx:." \
    $MYPYC_BINARY \
    --name конкурент \
    gui.py 2>&1

echo ""
echo "=== Готово! ==="
echo "dist/конкурент/ — portable-папка"
echo "Запуск: dist/конкурент/конкурент"
du -sh dist/конкурент/
