#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root_dir/scripts/generate-placeholder-icon.sh"
cd "$root_dir"
xcodebuild -project lanes.xcodeproj -scheme lanes -configuration Release -archivePath "$root_dir/.build/lanes.xcarchive" archive CODE_SIGNING_ALLOWED=NO
swift build -c release --product lanes-mcp
cp "$root_dir/.build/release/lanes-mcp" "$root_dir/.build/lanes.xcarchive/Products/Applications/lanes.app/Contents/MacOS/lanes-mcp"
