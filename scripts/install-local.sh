#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root_dir/scripts/build.sh"
user_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')
applications_dir="$user_home/Applications"
mkdir -p "$applications_dir"
rm -rf "$applications_dir/lanes.app"
cp -R "$root_dir/.build/xcode/Build/Products/Debug/lanes.app" "$applications_dir/lanes.app"
echo "Installed lanes.app in $applications_dir"
