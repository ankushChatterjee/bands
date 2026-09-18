# lanes

lanes is a small, local-first native macOS menu bar app for quickly putting thoughts somewhere safe.

## Requirements

- macOS 14+
- Xcode 16.4+
- Swift 6.1+ (included with Xcode 16.4)

## Build, test, run, and archive

```sh
swift build
swift test
```

The SwiftPM commands above remain the dependency-free developer/test path. The packaged app path is an Xcode project and produces a real menu-bar `.app` bundle:

```sh
open lanes.xcodeproj
./scripts/build.sh       # Debug lanes.app in .build/xcode/Build/Products/Debug
./scripts/test.sh        # swift test -j 2
./scripts/run.sh         # build, then open lanes.app
./scripts/archive.sh     # unsigned Release archive in .build/lanes.xcarchive
./scripts/install-local.sh # build and copy to ~/Applications/lanes.app
```

In Xcode, select the `lanes` scheme and Run. The target uses `Supporting/Info.plist`; its packaged value is `LSUIElement = true`, so the app is configured as a menu-bar utility. The app icon is generated locally by `scripts/generate-placeholder-icon.sh` (no remote assets or third-party tools) and is included in the asset catalog during scripted builds. Xcode Run may show the placeholder icon only after that script has been run once.

The archive and scripted builds intentionally set `CODE_SIGNING_ALLOWED=NO` for local development. No signing, notarization, Gatekeeper approval, or Dock behavior is claimed. For distribution, configure your own Apple Developer team, signing identity, provisioning settings, and notarization workflow in Xcode.

## Local self-signed releases

`scripts/build_and_release` re-signs the archived app and its DMG using a local code-signing identity. It is not a Developer ID signature and does not avoid Gatekeeper's unknown-developer warning.

List local signing identities with:

```sh
security find-identity -v -p codesigning
```

The release script uses the local `Apple Development: ac.ankush15@gmail.com (J6G9D2S38S)` identity by default. Create a release with it:

```sh
./scripts/build_and_release alpha
```

Override the identity for a particular release when needed:

```sh
SELF_SIGNING_IDENTITY="Another Local Identity" ./scripts/build_and_release alpha
```

For distribution without a second Gatekeeper warning when launching the copied app,
use a Developer ID Application identity and notarize both artifacts. Store the
notarytool credentials in the Keychain, then pass the profile name:

```sh
SELF_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="lanes-notary" ./scripts/build_and_release alpha
```

Notarization is the supported way to avoid separate DMG and app warnings. A local
Apple Development signature can still produce Gatekeeper warnings on both the DMG
and the app, and cannot reliably be reduced to exactly one warning by DMG layout.

The app uses SwiftUI for its panel, AppKit for the status item/panel and local macOS notifications, and SwiftData for the on-device store. It has no network, account, telemetry, voice, or AI code.

## V1 interaction

Click the grid icon in the menu bar, type into the capture field, and press Return. Captures land in the first lane; lane-local `+` adds directly to that lane. Click a thought to complete it, double-click to edit, or use its context menu to move or let it go. Thought age is derived from its creation date and is shown with increasingly warm semantic colors.

The package scaffold intentionally keeps the product small. The Xcode app target is now available without changing the SwiftUI/domain layer. The app icon and menu-bar status icon share the same three parallel-rail mark.
