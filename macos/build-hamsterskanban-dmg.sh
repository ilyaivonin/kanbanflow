#!/bin/bash
# Builds a clean, example-data-only HamstersKanban.dmg.
#
# The demo app uses its own bundle id, database and localStorage key.
# It never reads the production Hamster's Kanban database, so a fresh
# launch always shows the standard example board.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="HamstersKanban"
DMG="$ROOT/$APP_NAME.dmg"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/hamsterskanban-dmg.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

SRC="$BUILD/src"
APP="$BUILD/$APP_NAME.app"
STAGE="$BUILD/stage"
mkdir -p "$SRC/macos" "$STAGE"

cp "$ROOT/kanban.html" "$SRC/kanban.html"
cp "$ROOT/macos/main.swift" "$SRC/macos/main.swift"
cp "$ROOT/macos/Info.plist" "$SRC/macos/Info.plist"
ICON="$ROOT/macos/AppIcon.icns"
if [ ! -f "$ICON" ]; then ICON="$ROOT/assets/AppIcon.icns"; fi
cp "$ICON" "$SRC/AppIcon.icns"

python3 - "$SRC" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

edits = {
    "kanban.html": [
        ("kanbanflow_data", "hamsterskanban_data"),
        ("kanbanflow_backup.json", "hamsterskanban_backup.json"),
    ],
    "macos/main.swift": [
        ("KANBANFLOW_DB_PATH", "HAMSTERSKANBAN_DB_PATH"),
        ("HamstersKanban/kanbanflow.sqlite", "HamstersKanban/hamsterskanban.sqlite"),
        ("kanbanflow.sqlite", "hamsterskanban.sqlite"),
        ("kanbanflow_backup.json", "hamsterskanban_backup.json"),
        ("kanbanflow-selftest-", "hamsterskanban-selftest-"),
    ],
    "macos/Info.plist": [
        ("com.hamsterskanban.desktop", "com.hamsterskanban.demo"),
    ],
}

for name, pairs in edits.items():
    path = root / name
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
PY

echo "Compiling $APP_NAME..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc \
    -O \
    -swift-version 5 \
    -target "$(uname -m)-apple-macosx12.0" \
    -framework AppKit \
    -framework WebKit \
    -lsqlite3 \
    "$SRC/macos/main.swift" \
    -o "$APP/Contents/MacOS/$APP_NAME"

cp "$SRC/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC/kanban.html" "$APP/Contents/Resources/kanban.html"
cp "$SRC/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<'TXT'
HamstersKanban — demo build / демонстрационная сборка

This build starts with the standard example board only. It uses a separate
database at ~/Library/Application Support/HamstersKanban/hamsterskanban.sqlite
and never reads your Hamster's Kanban boards.

Эта сборка содержит только стандартную доску с примерами. Она использует
отдельную базу ~/Library/Application Support/HamstersKanban/hamsterskanban.sqlite
и не читает ваши доски Hamster's Kanban.

Drag HamstersKanban.app to Applications to install.
Перетащите HamstersKanban.app в Applications для установки.
TXT

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Built: $DMG"
