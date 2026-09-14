#!/bin/sh
set -eu
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$root_dir/scripts/build.sh"
open "$root_dir/.build/xcode/Build/Products/Debug/lanes.app"
