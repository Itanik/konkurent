#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "=== Установка pyinstaller ==="
.venv/bin/pip install pyinstaller -q

MYPYC_SO=$(ls .venv/lib/python3.14/site-packages/*__mypyc*.so 2>/dev/null | head -1)
if [ -z "$MYPYC_SO" ]; then
    echo "Ошибка: mypyc .so не найден"
    exit 1
fi
MYPYC_NAME=$(basename "$MYPYC_SO")

echo "=== Сборка portable ==="
.venv/bin/pyinstaller --onedir \
    --add-data "конкурент.xlsx:." \
    --add-binary "$MYPYC_SO:." \
    --name конкурент \
    gui.py 2>&1

echo ""
echo "=== Готово! ==="
echo "dist/конкурент/ — portable-папка"
echo "Запуск: dist/конкурент/конкурент"
du -sh dist/конкурент/
