#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root_dir/scripts/generate-placeholder-icon.sh"
cd "$root_dir"
xcodebuild -project bands.xcodeproj -scheme bands -configuration Release -archivePath "$root_dir/.build/bands.xcarchive" archive CODE_SIGNING_ALLOWED=NO
swift build -c release --product bands-mcp
cp "$root_dir/.build/release/bands-mcp" "$root_dir/.build/bands.xcarchive/Products/Applications/bands.app/Contents/MacOS/bands-mcp"
