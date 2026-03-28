#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-Magnify}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
SOURCE_RESOURCES_DIR="${SOURCE_RESOURCES_DIR:-$ROOT_DIR/Resources}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_APP="${INSTALL_APP:-0}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-$APP_NAME}"
VERSION="${VERSION:-1.0.0}"
SHORT_VERSION="${SHORT_VERSION:-1.0.0}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-dev.magnify.app}"

mkdir -p "$DIST_DIR"

echo "Building $APP_NAME ($BUILD_CONFIGURATION)..."
swift build -c "$BUILD_CONFIGURATION" --package-path "$ROOT_DIR"

BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --package-path "$ROOT_DIR" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "Creating app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -d "$SOURCE_RESOURCES_DIR" ]]; then
  echo "Copying bundle resources"
  ditto "$SOURCE_RESOURCES_DIR" "$RESOURCES_DIR"
fi

cat > "$INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  echo "Signing app bundle"
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

if [[ "$INSTALL_APP" == "1" ]]; then
  echo "Installing app bundle to $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED_APP_BUNDLE"
  ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  touch "$INSTALLED_APP_BUNDLE"
fi

echo
echo "Packaged app:"
echo "  $APP_BUNDLE"

if [[ "$INSTALL_APP" == "1" ]]; then
  echo
  echo "Installed app:"
  echo "  $INSTALLED_APP_BUNDLE"
fi

echo
echo "Launch it with:"
if [[ "$INSTALL_APP" == "1" ]]; then
  echo "  open \"$INSTALLED_APP_BUNDLE\""
else
  echo "  open \"$APP_BUNDLE\""
fi
