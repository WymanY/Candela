# PR 1 — Scaffold summary

Menu-bar shell for **Candela** (`app.candela.macos`) plus identity-pure DisplayCore. No real I²C, DisplayServices, or gamma writes.

## How to run

```sh
cd /Users/wyman/Documents/betterDisplay
./Scripts/generate_project.sh
open Candela.xcodeproj
```

Run the **Candela** scheme. The app is an accessory (menu bar only).

Fake catalog (built-in, Dell USB-C, HDMI TV, Sidecar):

```
# Scheme → Run → Arguments Passed On Launch
--fake-hardware

# or
CANDELA_FAKE_HARDWARE=1
```

Tests / app compile:

```sh
swift test --package-path .
xcodegen generate --spec project.yml
xcodebuild -scheme Candela -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES build
```

Verified locally: `swift test` 22 tests green; Debug `ONLY_ACTIVE_ARCH=YES` and unsigned `ONLY_ACTIVE_ARCH=NO` both **BUILD SUCCEEDED**. XcodeGen 2.44.1 generated `Candela.xcodeproj` (pin comment remains 2.42.0).

First launch opens the panel once (`hasOpenedPanelOnce`). Left-click the sun status item to toggle; right-click for Settings… / Quit.

## Files created

### Repo / tooling
- `Package.swift` — Appendix B (CandelaKit products unchanged)
- `project.yml` — Appendix A
- `.gitignore`, `.github/workflows/ci.yml`
- `Scripts/generate_project.sh`
- `LICENSE` (MIT), `NOTICE`, `README.md`
- `Candela.xcodeproj` — generated, shared `Candela` scheme

### CandelaPrivateIO
- `Sources/CandelaPrivateIO/include/CandelaPrivateIO.h` — typedefs only
- `Sources/CandelaPrivateIO/include/module.modulemap`
- `Sources/CandelaPrivateIO/CandelaPrivateIO.c` — header include so SPM has a translation unit

### DisplayCore
- Kinds, capabilities, `DisplaySnapshot`, `GlobalSettings`, `DisplayRecord`
- `DisplayIdentity` — `==` / `hash` on `persistentKey` only
- `sanitizeToken` / `sanitizeName`, `makeCore`, FNV-1a32, `makePersistentKey`, `resolveRecord` (suffixed then unsuffixed + one-hop aliases; never `portLocation` alone)
- `synthesizeEdidUUID`
- Protocols: `DDCCommanding`, `DisplayCataloging`, `PersistenceStoring`
- `HALOutputDevice`, `AudioMatching.match` stub → `nil`

### Façades
- `BrightnessKit/DisplayIOBox.swift` — in-memory mailbox
- `AudioKit/AudioKit.swift` — empty module marker
- `PersistenceKit/PersistenceStore.swift` — `UserDefaults.standard` only

### TestSupport + tests
- `FakeCatalog`, `FakeDDC`, four fake snapshots
- `Tests/DisplayCoreTests` — identity vectors 1–10 + protocol smoke
- Mailbox / persistence / AudioKit module smokes

### App
- `@main` only in `App/Candela/Sources/AppDelegate.swift` (Rosetta abort)
- `DisplaySessionController`, status item + 300pt `NSPanel`, settings tabs
- `NSScreen+Candela.swift` stub
- `Info.plist` (§12), empty `Candela.entitlements`, `Localizable.xcstrings` (en), `Assets.xcassets`

## Out of scope (later PRs)
Live CG catalog, DisplayServices/gamma writes, DDC packets, HAL matcher, launch-at-login.
