#!/usr/bin/env bash
# Полная проверка проекта: форматирование, линтер, сборка Rojo, строгая типизация, тесты.
# Запуск из корня репозитория: ./scripts/check.sh
# Инструменты ставятся через `rokit install` (см. rokit.toml).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build

echo "== stylua (форматирование)"
stylua --check src tests

echo "== selene (линтер)"
selene src

echo "== rojo build"
rojo build default.project.json -o build/pixel-fight.rbxl

echo "== luau-lsp analyze (--!strict)"
DEFINITIONS=build/globalTypes.d.luau
if [ ! -f "$DEFINITIONS" ]; then
	curl -fsSL -o "$DEFINITIONS" \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze \
	--platform=roblox \
	--sourcemap=sourcemap.json \
	--definitions="$DEFINITIONS" \
	--ignore="Packages/**" \
	src

echo "== тесты (lune)"
lune run tests/run.luau

echo "Все проверки пройдены."
