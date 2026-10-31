#!/bin/zsh
# Builds DiskFree.app (Apple Silicon only) next to this script.
set -euo pipefail

cd "${0:A:h}"
app=DiskFree.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

swiftc -O -target arm64-apple-macos13.0 -o "$app/Contents/MacOS/DiskFree" main.swift

[[ -f AppIcon.icns ]] || swift make_icon.swift
cp AppIcon.icns "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>DiskFree</string>
    <key>CFBundleIdentifier</key>        <string>local.diskfree</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleName</key>              <string>DiskFree</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSArchitecturePriority</key>    <array><string>arm64</string></array>
    <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST

echo "Built $PWD/$app"
