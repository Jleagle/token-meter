#!/bin/bash
set -e

echo "=== Building UsageToolbar macOS App Bundle ==="

# 1. Compile release binary
echo "Compiling Swift Package in Release mode..."
swift build -c release --disable-sandbox --disable-index-store

# 2. Setup .app directory structure
APP_NAME="UsageToolbar.app"
APP_DIR="$APP_NAME/Contents"
MACOS_DIR="$APP_DIR/MacOS"
RESOURCES_DIR="$APP_DIR/Resources"

echo "Creating bundle structure for $APP_NAME..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy executable
BINARY_PATH="$(swift build -c release --disable-sandbox --disable-index-store --show-bin-path)/UsageToolbar"
cp "$BINARY_PATH" "$MACOS_DIR/UsageToolbar"
chmod +x "$MACOS_DIR/UsageToolbar"

# 4. Generate Info.plist
echo "Generating Info.plist..."
cat <<EOF > "$APP_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>UsageToolbar</string>
    <key>CFBundleIdentifier</key>
    <string>com.usage.toolbar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>UsageToolbar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "Signing bundle..."
codesign --force --deep -s - "$APP_NAME"

echo "=== Build Complete! ==="
echo "You can launch the app by double-clicking $APP_NAME in Finder or running:"
echo "open ./$APP_NAME"
