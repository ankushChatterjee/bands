#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root_dir/scripts/generate-placeholder-icon.sh"
cd "$root_dir"
xcodebuild -project lanes.xcodeproj -scheme lanes -configuration Debug -derivedDataPath .build/xcode build
swift build --product lanes-mcp
cp "$root_dir/.build/debug/lanes-mcp" "$root_dir/.build/xcode/Build/Products/Debug/lanes.app/Contents/MacOS/lanes-mcp"

# Copying the MCP helper changes the app bundle after Xcode has signed it.
# Sign it again so macOS Keychain ACLs continue to recognize Lanes as the
# trusted application permitted to use its saved tokens without a prompt.
signing_identity=$(xcodebuild -project lanes.xcodeproj -scheme lanes -configuration Debug -showBuildSettings | awk -F ' = ' '/^[[:space:]]*CODE_SIGN_IDENTITY = /{ print $2; exit }')
if [ -z "$signing_identity" ]; then
  echo "No signing identity configured for lanes." >&2
  exit 1
fi
xcrun codesign --force --deep --sign "$signing_identity" "$root_dir/.build/xcode/Build/Products/Debug/lanes.app"
