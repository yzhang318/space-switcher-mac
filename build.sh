#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SpaceSwitcher"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building ${APP_NAME}..."
swift build -c release

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "Info.plist"                  "${APP_BUNDLE}/Contents/"

echo "==> Done: ${APP_BUNDLE}"
echo ""
echo "Run with:  open ${APP_BUNDLE}"
echo ""
echo "NOTE: On first launch, macOS will ask for Accessibility permission"
echo "      (System Settings → Privacy & Security → Accessibility)"
echo "      so that osascript can send key events to switch Spaces."
