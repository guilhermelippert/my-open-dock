#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="My Open Dock"
BUILD_DIR="$PWD/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Sources/DocksetLocal/*.swift -o "$APP_DIR/Contents/MacOS/DocksetLocal" -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement -framework IOKit
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
if [ -f LICENSE ]; then cp LICENSE "$APP_DIR/Contents/Resources/LICENSE"; fi
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
if [ "${1:-}" = "--install" ]; then
  INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
  if [ -d "$INSTALL_DIR" ]; then
    BACKUP_DIR="$BUILD_DIR/previous-$(date +%Y%m%d-%H%M%S).app"
    ditto "$INSTALL_DIR" "$BACKUP_DIR"
  fi
  mkdir -p "$HOME/Applications"
  ditto "$APP_DIR" "$INSTALL_DIR"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR"
  echo "Instalado: $INSTALL_DIR"
fi
