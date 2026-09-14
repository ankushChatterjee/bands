#!/bin/sh
set -eu

# Creates the local, dependency-free placeholder used by AppIcon.appiconset.
# Replace this script and the generated PNG with final artwork when available.
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
icon_dir="$root_dir/Supporting/Assets.xcassets/AppIcon.appiconset"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/lanes-icon.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

cat > "$tmp_dir/make-icon.swift" <<'SWIFT'
import AppKit
import CoreGraphics

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1).cgColor)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(NSColor.systemBlue.cgColor)
context.fillEllipse(in: CGRect(x: 192, y: 192, width: 640, height: 640))
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
SWIFT

swiftc "$tmp_dir/make-icon.swift" -o "$tmp_dir/make-icon"
"$tmp_dir/make-icon" "$icon_dir/AppIcon-1024.png"
