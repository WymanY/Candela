# Candela

Candela is a native macOS menu-bar app for controlling every attached display. It can dim Apple panels and third-party monitors, adjust HDMI/DP speaker volume when the hardware exposes it, rotate external screens, switch DDC inputs, and mirror a chosen display in a floating Picture in Picture window. 1.1 adds opacity, click-through, pinned corners, and remembered placement for that window. 1.2 can follow a window, flip the preview, magnify around the cursor, and tile every real display into a monitor wall.

1.3 can keep every other display at a relative offset when the keyboard brightness keys move the built-in panel, without taking over media keys.

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
- Keyboard brightness follow is off by default and lasts only for the current launch: F1/F2 still move the built-in panel, and other displays keep a relative offset. Dragging one slider only changes that display's offset.
- Scenes remember each display's brightness, volume, mute, contrast, input, rotation, and Picture in Picture, plus the current speaker output, volume, and mute, then restore that mix later.
- Match All copies one display's brightness (and volume/contrast when available) onto the others.
- Last brightness can be restored when a display reconnects.
- Menu-bar sliders follow hardware brightness after keyboard, System Settings, or OSD changes, without writing the sampled value back.

### Volume

- Binds HDMI / DisplayPort / Thunderbolt speakers through Core Audio when a matching output exists.
- Uses DDC volume/mute when the monitor exposes those VCPs.
- Falls back to software attenuation for digital outputs that have no hardware slider.
- Built-in laptop/iMac panels do not get a volume row.

### Extra monitor controls

- DDC contrast (`0x12`) and input select (`0x60`) when the monitor answers those VCPs.
- Rotation at 0° / 90° / 180° / 270° on external monitors that can rotate.
- Built-in panels never expose rotation.
- The panel footer Mirror button mirrors every attached display onto the built-in panel. Click it again to restore the previous arrangement. External rows hide while mirrored; the button stays in the footer.

### Picture in Picture

- Each real display has a PiP button in the menu-bar panel. The footer also opens a monitor wall.
- Opens a floating, resizable mirror of that screen on the display under the pointer.
- The source can be the whole display, one window, or a magnifier that follows the cursor. Until a window is chosen, Window mode still shows that display.
- The title bar shows the display name, then the window name in Window mode. Display and Window hint that you can scroll to zoom. Magnifier hints that Space-drag pans the canvas.
- In Magnifier, hold Space and drag or scroll the preview to pan around the magnified region. That gesture does not resize the PiP window.
- Flip the preview horizontally for a teleprompter.
- Scroll or pinch to zoom. A single PiP stays between 280 and 1280 wide. The monitor wall can grow to the current screen. A pinned window grows from that position.
- The title bar has opacity (down to 25%) and click-through. Clicks on the preview reach the work underneath. Hovering the window still zooms it with the scroll wheel. ⌘W closes the hovered PiP.
- Pin it to top-left, top-right, bottom-left, bottom-right, or center. Dragging it off that position unpins it.
- Each display remembers the last place, size, opacity, click-through, pin, flip, mode, and window identity. Closing and opening the window brings that layout back.
- The monitor wall tiles every real display into one floating window, remembers its own placement, and can zoom up to the current screen. Virtual screens stay out. Desktop Backstop layers and black capture overlays such as Screen Studio's window-picker highlighter are hidden from the window list.
- Captures at the source display's pixel size so text stays readable.
- Requires Screen Recording permission.
- Virtual screens such as Sidecar are not supported.

### Scenes

- Save the current display mix from the menu bar and apply recent scenes with one click.
- Applying a scene also switches back to the speaker that was selected then, and restores its volume and mute.
- The Settings Scenes tab can rename, update, or delete saved scenes.
- Saving with the same name overwrites that scene instead of duplicating it.
- Missing displays are skipped and applied again when they return.
- Candela does not ship built-in scene templates. Saved scenes live in local preferences and survive app relaunch.

### Battery

- When a MacBook is unplugged, the menu-bar panel shows the current battery percent and remaining time beside the title.
- On AC power the chip switches to a charging bolt so the plugged-in state stays visible.
- The chip hides on desktops, or when no internal battery is present.

### Settings

- Launch at Login
- Restore last brightness on reconnect
- Follow keyboard brightness
- Software dimming on/off
- Allow dim to black
- Show percent labels next to sliders
- Per-display custom names
- Save and apply display scenes

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
swift run --package-path . candela-cli set-pip --display DELL --mode window --window Slack --mirror true
swift run --package-path . candela-cli set-pip --display DELL --mode magnifier --zoom 3
swift run --package-path . candela-cli set-pip-wall --enabled true
swift run --package-path . candela-cli rename --display DELL --name Desk
swift run --package-path . candela-cli preset night
swift run --package-path . candela-cli match-all --display main
swift run --package-path . candela-cli set-mirror
swift run --package-path . candela-cli set-follow-keyboard --enabled true
swift run --package-path . candela-cli scenes
swift run --package-path . candela-cli save-scene --name Night
swift run --package-path . candela-cli apply-scene Night
swift run --package-path . candela-cli dump
```

Display queries: name, custom name, `persistentKey`, `main`, `builtin`, or `external`. Values are `0...1`.

`candela-mcp` is a local stdio MCP server with the same operations. The Codex skill lives in `skills/candela`.

## What it does not do

Candela does not create virtual screens, override EDID, unlock XDR nits, force HiDPI or custom resolutions, or take over media keys. It does not change the system default audio output in ordinary use; applying a saved scene is the exception, and only then does it switch back to that scene's remembered speaker.

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

Select the **Candela** scheme and run. That is the direct / Developer ID build: sandbox off, DisplayServices / DDC / MonitorPanel on.

- **Debug:** Dock icon and menu-bar extra, so the app is easy to find.
- **Release:** menu bar only.

Do not upload that scheme to the Mac App Store. Use **CandelaMAS** instead: sandbox on, private display APIs compiled out, hardware I/O on public IOKit (`IODisplay` brightness, `IOI2CInterface` DDC, `IOServiceRequestProbe` rotation). The UI and feature set stay the same; the direct / Developer ID scheme is unchanged.

```sh
xcodebuild -project Candela.xcodeproj -scheme CandelaMAS -configuration Release -destination 'generic/platform=macOS' build
```

This is a reviewable MAS build line, not a completed App Store upload. Sandboxed I2C / IODisplay / process-tap still need hardware smoke, and this repo does not yet carry a Mac App Store signing identity or provisioning profile.

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

CI also builds **Candela** and **CandelaMAS** on macOS 14.

## 1.3

- Keyboard brightness keys now move every controllable display. External panels keep a relative offset from the built-in panel.
- Follow can be turned on from the menu-bar panel or Settings for this launch only. Each display can still be dimmed on its own.

## 1.2

- Picture in Picture now opens on the display under the pointer.
- Picture in Picture can pin to the center of the current display.
- Picture in Picture can follow a window, not just a whole display. Until a window is chosen, it keeps showing that display.
- Flip the preview horizontally for a teleprompter.
- Magnifier mode crops a sharp region around the cursor. Hold Space and drag or scroll the preview to pan the canvas. That gesture does not resize the PiP window.
- A monitor wall tiles every real display into one floating window and can grow to the current screen.

## 1.1

- Picture in Picture now has opacity, click-through, and pinned corners.
- Scroll or pinch to zoom the floating window. A pinned window grows from that position.
- Each display remembers the last PiP place, size, and window state.
- With click-through on, clicks still reach the work underneath. Hovering the window still zooms it with the scroll wheel.

## License

MIT. See `LICENSE` and `NOTICE`.
