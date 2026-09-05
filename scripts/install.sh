#!/bin/bash
# One-shot installer: build Bbox, move it to /Applications, launch it.
# Registers itself to start at login.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Bbox"
DEST="/Applications/${APP_NAME}.app"

echo "▶ Собираю приложение…"
./scripts/build_app.sh >/dev/null

echo "▶ Останавливаю старую версию (если запущена)…"
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "▶ Устанавливаю в /Applications…"
rm -rf "${DEST}"
cp -R "build/${APP_NAME}.app" "${DEST}"

echo "▶ Запускаю…"
open "${DEST}"

cat <<EOF

Готово. Bbox установлен в /Applications и запущен.

   Вызов буфера:   Option+V
   Иконка:         в строке меню (правый клик даёт меню с пунктом «Выход»)
   Автозапуск:     включён

При первом запуске macOS попросит доступ к «Универсальному доступу»
(Accessibility). Он нужен для автоматической вставки по Option+V.
Системные настройки, раздел «Конфиденциальность и безопасность»,
пункт «Универсальный доступ», включить Bbox.
Без этого доступа запись всё равно кладётся в буфер, вставляйте вручную (Cmd+V).
EOF
