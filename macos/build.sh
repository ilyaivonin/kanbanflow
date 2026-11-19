#!/bin/bash
# Builds a self-contained KanbanFlow.app without external dependencies.
# Requires macOS 12+ and the Xcode Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="KanbanFlow"
ARCH="${KANBANFLOW_ARCH:-$(uname -m)}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc was not found. Install the Xcode Command Line Tools:" >&2
    echo "  xcode-select --install" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling native shell for ${ARCH}..."
swiftc \
    -O \
    -swift-version 5 \
    -target "${ARCH}-apple-macosx12.0" \
    -framework AppKit \
    -framework WebKit \
    -lsqlite3 \
    "$ROOT/macos/main.swift" \
    -o "$APP/Contents/MacOS/$APP_NAME"

cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/kanban.html" "$APP/Contents/Resources/kanban.html"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signing is enough for local use. Replace with a Developer ID
# signature if you plan to distribute the app outside your Mac.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
echo "Run:   open \"$APP\""
