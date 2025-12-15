#!/bin/bash
set -e

# Configuration
APP_NAME="Mole"
# Get the actual build path dynamically
BUILD_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"
ICON_SOURCE="Resources/mole.icns"

echo "🚀 Building Release Binary..."
swift build -c release

echo "📦 Creating App Bundle Structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "📄 Copying Executable..."
cp "$BUILD_PATH" "$APP_BUNDLE/Contents/MacOS/"

echo "📝 Generatign Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.tw93.mole</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -f "$ICON_SOURCE" ]; then
    echo "🎨 Copying App Icon from $ICON_SOURCE..."
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "✅ App Icon set successfully."
else
    echo "⚠️ Icon file not found at $ICON_SOURCE. App will use default icon."
fi

# Remove xattr com.apple.quarantine to avoid warnings
xattr -cr "$APP_BUNDLE"

echo "✅ App Packaged: $APP_BUNDLE"
echo "👉 You can now move $APP_NAME.app to /Applications"
