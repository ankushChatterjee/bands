# bands

bands is a local-first macOS menu bar app for capturing and organizing thoughts in named bands. It stores data on the device with SwiftData and keeps the main interface close at hand from the menu bar.

## What the app does

- Capture thoughts from the menu bar or with global shortcuts (Option-L opens the panel; Option-Q starts quick capture).
- Organize thoughts into named bands, add descriptions, reorder items, and complete or release thoughts.
- Navigate and edit from the keyboard, with shortcuts also listed in Settings.
- Track thought age with configurable thresholds and optional macOS notifications.
- Optionally use Jev to suggest a band for a quick capture. This requires a Jev token entered in Settings; without one, thoughts can be assigned manually.
- Optionally expose local band and thought operations through the `bands-mcp` MCP helper. The helper communicates with the running app over a local Unix socket. See [docs/MCP.md](docs/MCP.md).

The app is built with SwiftUI and AppKit, and persists its data with SwiftData. The core capture and organization features work locally. Jev categorization is the feature that makes an HTTPS request; it is opt-in and requires the user's own token. There is no account or telemetry service.

## Requirements

- macOS 14 or later
- Xcode 16.4 or later (Swift 6.1 toolchain)

## Build and test

From the repository root, the Swift Package Manager commands build the app and MCP helper and run the unit tests:

```sh
swift build
swift test
```

The Xcode project packages the menu-bar app as a `.app` bundle. Its convenience scripts are:

```sh
./scripts/build.sh          # Debug app bundle plus bands-mcp helper
./scripts/test.sh           # Run Swift unit tests
./scripts/run.sh            # Build and launch the app
./scripts/archive.sh        # Unsigned Release archive plus MCP helper
./scripts/install-local.sh  # Build and copy the app into ~/Applications
```

Open `bands.xcodeproj`, select the `bands` scheme, and choose Run to build from Xcode. Scripted builds generate the app icon locally with `scripts/generate-placeholder-icon.sh`.

Build products are written under `.build/`. The app target uses `Supporting/Info.plist` and is configured as a menu-bar utility (`LSUIElement = true`). Local build and archive commands do not configure Developer ID distribution or notarization.

## Optional self-signed release

The `scripts/build_and_release` script creates a release archive and DMG, signs them with a local code-signing identity, and creates a Git tag. It does not provide a Developer ID signature unless you supply one, and a local Apple Development signature may still trigger Gatekeeper warnings.

First list identities available on your Mac:

```sh
security find-identity -v -p codesigning
```

Pass the desired identity explicitly:

```sh
SELF_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build_and_release alpha
```

For notarization, configure a `notarytool` Keychain profile and provide it along with a suitable Developer ID Application identity:

```sh
SELF_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="your-notary-profile" ./scripts/build_and_release alpha
```

The release script requires a clean worktree on a named branch and a new valid Git tag. It tags the release after successfully building and signing the artifacts.

## More documentation

- [Keyboard interaction and shortcuts](docs/KEYBOARD.md)
- [Local MCP bridge setup and protocol](docs/MCP.md)
