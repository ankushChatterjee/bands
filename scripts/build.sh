#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root_dir/scripts/generate-placeholder-icon.sh"
cd "$root_dir"
xcodebuild -project lanes.xcodeproj -scheme lanes -configuration Debug -derivedDataPath .build/xcode build
swift build --product lanes-mcp
cp "$root_dir/.build/debug/lanes-mcp" "$root_dir/.build/xcode/Build/Products/Debug/lanes.app/Contents/MacOS/lanes-mcp"
