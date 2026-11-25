#!/bin/bash
# Builds HamstersKanban.app as a self-contained macOS application.
# No external dependencies: only the Xcode command line tools are required.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="HamstersKanban"
APP="$ROOT/$APP_NAME.app"
BUILD="$ROOT/macos/.build"

mkdir -p "$BUILD"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling native shell..."
swiftc \
    -O \
    -swift-version 5 \
    -target "$(uname -m)-apple-macosx12.0" \
    -framework AppKit \
    -framework WebKit \
    -lsqlite3 \
    "$ROOT/macos/main.swift" \
    -o "$APP/Contents/MacOS/$APP_NAME"

cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/kanban.html" "$APP/Contents/Resources/kanban.html"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature lets macOS treat the bundle as a normal local app.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
