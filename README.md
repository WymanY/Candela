# Candela

Menu-bar brightness for every display on macOS, plus per-display volume when a monitor exposes HDMI/DP speakers (HAL, DDC, or software attenuation).

Candela is an AppKit accessory (`LSUIElement`) app. Bundle ID: `app.candela.macos`.

## Requirements

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.42.0 or newer (to regenerate the project)

## Generate, open, run

```sh
chmod +x Scripts/generate_project.sh
./Scripts/generate_project.sh
open Candela.xcodeproj
```

The generated `Candela.xcodeproj` is committed so a clone can build without XcodeGen. CI still runs `xcodegen` to detect drift.

Run the **Candela** scheme.

- **Debug** (Xcode Run): Dock icon **and** menu-bar extra so the app is easy to find.
- **Release**: menu bar only (`LSUIElement`).

Xcode may print `com.apple.linkd.autoShortcut` / `Error registering app with intents framework` on launch. That is AppKit talking to Apple’s Shortcuts daemon; Candela has no App Intents. It is harmless. See `docs/linkd-diagnosis.md`.

## Fake hardware

By default the menu bar lists **real attached displays** and drives brightness via DisplayServices (Apple panels) or software gamma (everyone else; DDC is a later PR). Pass a flag or env var to list four canned displays instead (built-in, Dell USB-C, HDMI TV, Sidecar) with **no real hardware writes**:

```sh
# Scheme → Run → Arguments
--fake-hardware

# or
CANDELA_FAKE_HARDWARE=1
```

- Built-in — DisplayServices brightness, no volume or rotation
- DELL U2723QE — DDC brightness + volume
- HDMI Television — software gamma; software volume if HDMI speakers match
- Sidecar — unsupported, grey, no sliders

## Everyday controls

The menu-bar panel now has Night / Desk / Max brightness presets, Match All, DDC contrast, input select, and per-display rotation (0/90/180/270) on external monitors that can rotate. Built-in panels never expose rotation. Settings covers Launch at Login, restore on reconnect, percent labels, dim-to-black, and per-display custom names.

## Agent interface

Keep Candela running, then use the CLI against the live app:

```sh
swift run --package-path . candela-cli list
swift run --package-path . candela-cli set-brightness --display builtin --value 0.3
swift run --package-path . candela-cli preset night
```

`candela-mcp` is a local stdio MCP server with the same operations. The Codex skill lives in `skills/candela`.

BetterDisplay-style virtual screens, EDID overrides, XDR unlock, PiP, and resolution/HiDPI forcing are intentionally out of scope.

## Tests

```sh
swift test --package-path .
```

## License

MIT. See `LICENSE` and `NOTICE`.
