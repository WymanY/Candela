# Candela

Menu-bar brightness for every display on macOS, plus per-display volume when a monitor exposes HDMI/DP speakers.

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

Run the **Candela** scheme. The app lives in the menu bar (no Dock icon).

## Fake hardware

By default the menu bar lists **real attached displays** and drives brightness via DisplayServices (Apple panels) or software gamma (everyone else; DDC is a later PR). Pass a flag or env var to list four canned displays instead (built-in, Dell USB-C, HDMI TV, Sidecar) with **no real hardware writes**:

```sh
# Scheme → Run → Arguments
--fake-hardware

# or
CANDELA_FAKE_HARDWARE=1
```

- Built-in — DisplayServices brightness, no volume
- DELL U2723QE — DDC brightness + volume
- HDMI Television — software gamma, no volume
- Sidecar — unsupported, grey, no sliders

## Tests

```sh
swift test --package-path .
```

## License

MIT. See `LICENSE` and `NOTICE`.
