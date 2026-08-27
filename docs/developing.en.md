# Developing Candela

Local build and debug notes. The product homepage is [README.en.md](../README.en.md). 中文：[developing.md](developing.md)

## Clone

The generated `Candela.xcodeproj` is committed, so a clone can build without XcodeGen.

```sh
git clone https://github.com/WymanY/Candela.git
cd Candela
open Candela.xcodeproj
```

Select the **Candela** scheme and run. That is the direct / Developer ID build.

- **Debug:** Dock icon and menu-bar extra, so the app is easy to find.
- **Release:** menu bar only.

From the command line:

```sh
xcodebuild -project Candela.xcodeproj -scheme Candela -configuration Debug -destination 'platform=macOS' build
swift test --package-path .
swift run --package-path . candela-cli --help
```

The Debug app typically lands at:

```
~/Library/Developer/Xcode/DerivedData/Candela-*/Build/Products/Debug/Candela.app
```

This is a native AppKit menu-bar app.

## Candela vs CandelaMAS

The **Candela** scheme is the direct build: sandbox off, system backlight / DDC / monitor controls on. Do not upload that scheme to the Mac App Store.

**CandelaMAS** is a reviewable sandboxed build line, not a completed App Store upload. The UI and feature set stay the same; private display APIs are compiled out and hardware I/O uses public interfaces. Sandboxed display I/O still needs hardware smoke, and this repo does not yet carry a Mac App Store signing identity or provisioning profile.

```sh
xcodebuild -project Candela.xcodeproj -scheme CandelaMAS -configuration Release -destination 'generic/platform=macOS' build
```

## Regenerate the Xcode project

Only needed after changing `project.yml`:

```sh
chmod +x Scripts/generate_project.sh
./Scripts/generate_project.sh
```

CI runs `xcodegen generate` and then builds, so drift is caught automatically.

## Fake hardware

To exercise the UI without writing to real displays:

```
# Scheme → Run → Arguments
--fake-hardware

# or
CANDELA_FAKE_HARDWARE=1
```

The fake catalog is:

- Built-in — system backlight, no volume or rotation
- DELL U2723QE — DDC brightness + volume
- HDMI Television — software dimming; software volume if HDMI speakers match
- Sidecar — Unsupported, grey, no sliders

## CLI, MCP, and the socket

Keep Candela running. The CLI talks to `~/Library/Application Support/Candela/control.sock`.

Display queries: name, custom name, `main`, `builtin`, or `external`. Values are `0...1`.

```sh
swift run --package-path . candela-cli list
swift run --package-path . candela-cli get --display builtin
swift run --package-path . candela-cli set-brightness --display builtin --value 0.35
swift run --package-path . candela-cli preset night
swift run --package-path . candela-cli scenes
swift run --package-path . candela-cli save-scene --name Night
swift run --package-path . candela-cli apply-scene Night
```

`candela-mcp` is a local stdio MCP server with the same operations. The Codex skill lives in [`skills/candela`](../skills/candela).

## App Intents log noise

Xcode may print `com.apple.linkd.autoShortcut` / `Error registering app with intents framework` on launch. Candela has no App Intents. That message is harmless. See [linkd-diagnosis.md](linkd-diagnosis.md).
