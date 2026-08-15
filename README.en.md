# Candela

Candela is a native macOS menu-bar app for controlling every attached display. It can dim Apple panels and third-party monitors, adjust HDMI/DP speaker volume when the hardware exposes it, rotate external screens, switch DDC inputs, and mirror a chosen display in a floating Picture in Picture window.

It is an AppKit accessory app. Bundle ID: `app.candela.macos`.

中文说明见 [README.md](README.md)。

## Features

### Display discovery

- Lists built-in and external displays as cables and docks attach or detach.
- Identifies each panel with a stable `persistentKey`, not a session `CGDirectDisplayID`.
- Hides a clamshell built-in that is asleep, and hides mirrored slave screens.
- Shows Sidecar, AirPlay, Continuity, and DisplayLink rows as unsupported. They are visible but not controllable.

### Brightness

- Apple built-in and Apple external panels use DisplayServices.
- Third-party HDMI / DisplayPort / USB-C monitors use DDC/CI VCP `0x10` on Apple Silicon.
- If hardware control is missing or fails, Candela falls back to software gamma dimming and keeps the LUT alive so WindowServer does not revert it.
- Night / Desk / Max presets: 20%, 50%, and 100%.
- Match All copies one display's brightness (and volume/contrast when available) onto the others.
- Last brightness can be restored when a display reconnects.

### Volume

- Binds HDMI / DisplayPort / Thunderbolt speakers through Core Audio when a matching output exists.
- Uses DDC volume/mute when the monitor exposes those VCPs.
- Falls back to software attenuation for digital outputs that have no hardware slider.
- Built-in laptop/iMac panels do not get a volume row.

### Extra monitor controls

- DDC contrast (`0x12`) and input select (`0x60`) when the monitor answers those VCPs.
- Rotation at 0° / 90° / 180° / 270° on external monitors that can rotate.
- Built-in panels never expose rotation.

### Picture in Picture

- Each real display has a PiP button in the menu-bar panel.
- Opens a floating, resizable mirror of that screen, preferably on another display.
- Captures at the source display's pixel size so text stays readable.
- Requires Screen Recording permission.
- Virtual screens such as Sidecar are not supported.

### Settings

- Launch at Login
- Restore last brightness on reconnect
- Software dimming on/off
- Allow dim to black
- Show percent labels next to sliders
- Per-display custom names

### Agent interface

Keep Candela running. The CLI talks to `~/Library/Application Support/Candela/control.sock`.

```sh
swift run --package-path . candela-cli list
swift run --package-path . candela-cli get --display builtin
swift run --package-path . candela-cli set-brightness --display builtin --value 0.35
swift run --package-path . candela-cli set-volume --display DELL --value 0.2
swift run --package-path . candela-cli set-mute --display DELL --muted true
swift run --package-path . candela-cli set-contrast --display DELL --value 0.5
swift run --package-path . candela-cli set-input --display DELL hdmi1
swift run --package-path . candela-cli set-rotation --display DELL 90
swift run --package-path . candela-cli set-pip --display DELL --enabled true
swift run --package-path . candela-cli rename --display DELL --name Desk
swift run --package-path . candela-cli preset night
swift run --package-path . candela-cli match-all --display main
swift run --package-path . candela-cli dump
```

Display queries: name, custom name, `persistentKey`, `main`, `builtin`, or `external`. Values are `0...1`.

`candela-mcp` is a local stdio MCP server with the same operations. The Codex skill lives in `skills/candela`.

## What it does not do

Candela does not create virtual screens, override EDID, unlock XDR nits, force HiDPI or custom resolutions, take over media keys, or change the system default audio output.

## Requirements

| Item | Minimum |
| --- | --- |
| macOS | 14.0 Sonoma |
| Xcode | 16.0 |
| Swift | 5.10 language mode (Swift 6.0 tools) |
| Chip | Apple Silicon or Intel. Must run natively. Rosetta is refused. |
| XcodeGen | 2.42.0 or newer, only if you regenerate the Xcode project |

DDC brightness/volume on third-party panels is implemented for Apple Silicon. Picture in Picture and software volume need Screen Recording. Software volume for HDMI/DP speakers also needs audio capture permission.

## Build

The generated `Candela.xcodeproj` is committed, so a clone can build without XcodeGen.

### Xcode

```sh
git clone https://github.com/WymanY/Candela.git
cd Candela
open Candela.xcodeproj
```

Select the **Candela** scheme and run.

- **Debug:** Dock icon and menu-bar extra, so the app is easy to find.
- **Release:** menu bar only.

Xcode may print `com.apple.linkd.autoShortcut` / `Error registering app with intents framework` on launch. Candela has no App Intents. That message is harmless. See `docs/linkd-diagnosis.md`.

### Command line

```sh
# App
xcodebuild -project Candela.xcodeproj -scheme Candela -configuration Debug -destination 'platform=macOS' build

# Package tests, CLI, and MCP
swift test --package-path .
swift run --package-path . candela-cli --help
```

The Debug app lands in DerivedData. After a local Xcode build it is typically:

```
~/Library/Developer/Xcode/DerivedData/Candela-*/Build/Products/Debug/Candela.app
```

### Regenerate the Xcode project

Only needed after changing `project.yml`.

```sh
chmod +x Scripts/generate_project.sh
./Scripts/generate_project.sh
```

CI runs `xcodegen generate` and then builds, so drift is caught automatically.

### Fake hardware

To exercise the UI without writing to real displays:

```
# Scheme → Run → Arguments
--fake-hardware

# or
CANDELA_FAKE_HARDWARE=1
```

The fake catalog is:

- Built-in — DisplayServices brightness, no volume or rotation
- DELL U2723QE — DDC brightness + volume
- HDMI Television — software gamma; software volume if HDMI speakers match
- Sidecar — unsupported, grey, no sliders

## Tests

```sh
swift test --package-path .
```

CI also builds the Candela app on macOS 14.

## License

MIT. See `LICENSE` and `NOTICE`.
