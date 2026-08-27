# Candela

Brightness, volume, scenes, and layout for every display, from the menu bar.

中文说明见 [README.md](README.md)。

[Download the latest release](https://github.com/WymanY/Candela/releases/latest)

Requires macOS 14 or later. The current download is an Apple Silicon (`arm64`) DMG, signed with Developer ID and notarized.

<p align="center">
  <img src="docs/images/candela-icon-256.png" alt="Candela" width="128" height="128">
</p>

## What it can do

- Dim Apple backlights and third-party monitors; fall back to Software dimming when hardware control is missing.
- Adjust HDMI / DisplayPort speaker volume and mute when the display exposes speakers.
- Apply Night, Desk, and Max in one click.
- Turn on Follow keyboard brightness so other displays keep a relative offset while the keyboard brightness keys move the built-in panel.
- Save the current mix as Scenes, then Save Scene and Apply Scene later.
- Use Mirror to stack externals onto the built-in panel, or Layout to open Display Layout and Arrange extended displays.
- Open Picture in Picture / PiP on any real display, or Overview for Display Overview.
- On a MacBook, the panel title shows a battery chip with percent and remaining time.

## Install

Download the Apple Silicon `Candela-*-arm64.dmg` from the [latest GitHub Release](https://github.com/WymanY/Candela/releases/latest) and drag `Candela.app` into Applications.

The direct build is Developer ID signed and notarized by Apple.

## What it does not do

Candela does not create virtual screens, override EDID, unlock XDR nits, force HiDPI or custom resolutions, or take over media keys. It does not change the system default audio output in ordinary use; Apply Scene is the exception, and only then does it switch back to that scene's remembered speaker.

The GitHub download is the direct / Developer ID build, not a Mac App Store package. There is no shipping App Store listing yet.

## Requirements

- macOS 14.0 Sonoma or later
- Native only; Rosetta is refused
- DDC brightness and volume on third-party panels are implemented on Apple Silicon
- Picture in Picture and Display Overview need Screen Recording

## Develop

The generated `Candela.xcodeproj` is committed:

```sh
git clone https://github.com/WymanY/Candela.git
cd Candela
open Candela.xcodeproj
```

This is a native AppKit menu-bar app. More detail:

- Using Candela: [docs/using.en.md](docs/using.en.md) · [中文](docs/using.md)
- Local development: [docs/developing.en.md](docs/developing.en.md) · [中文](docs/developing.md)
- Tagging a release: [docs/releasing.en.md](docs/releasing.en.md) · [中文](docs/releasing.md)

## Command line / agents

Keep Candela running. The CLI talks to `~/Library/Application Support/Candela/control.sock`.

```sh
swift run --package-path . candela-cli list
swift run --package-path . candela-cli set-brightness --display builtin --value 0.35
swift run --package-path . candela-cli preset night
```

The rest of the CLI, the local `candela-mcp` server, and the Codex skill are in [docs/developing.en.md](docs/developing.en.md) and [`skills/candela`](skills/candela).

## License

MIT. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
