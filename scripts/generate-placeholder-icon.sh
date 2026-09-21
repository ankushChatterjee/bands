#!/bin/sh
set -eu

# Creates the local, dependency-free app icon used by AppIcon.appiconset.
# The mark mirrors the three parallel rails used by the menu-bar status icon.
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
icon_dir="$root_dir/Supporting/Assets.xcassets/AppIcon.appiconset"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/bands-icon.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

cat > "$tmp_dir/make-icon.swift" <<'SWIFT'
import AppKit
import CoreGraphics

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Match BandsTheme.graphite (#1C1C1F) used throughout the app UI.
context.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor)
let iconBounds = CGRect(x: 28, y: 28, width: 968, height: 968)
context.addPath(CGPath(roundedRect: iconBounds, cornerWidth: 218, cornerHeight: 218, transform: nil))
context.fillPath()
context.setStrokeColor(NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.87, alpha: 1).cgColor)
context.setLineWidth(44)
context.setLineCap(.round)

for y in [330.0, 694.0] {
    context.move(to: CGPoint(x: 220, y: y))
    context.addLine(to: CGPoint(x: 804, y: y))
}
context.strokePath()

// Keep the center rail visually distinct at small sizes, as it is in the menu-bar mark.
context.setLineDash(phase: 0, lengths: [104, 72])
context.move(to: CGPoint(x: 220, y: 512))
context.addLine(to: CGPoint(x: 804, y: 512))
context.strokePath()
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
SWIFT

swiftc "$tmp_dir/make-icon.swift" -o "$tmp_dir/make-icon"
"$tmp_dir/make-icon" "$icon_dir/AppIcon-1024.png"
