# PR 2 — Live catalog + identity

Replace `EmptyCatalog` as the default with a live `CGGetOnlineDisplayList` catalog. Panel lists real attached display names and `v1:` persistent keys. **No brightness writes** (no DDC I²C, no gamma, no DisplayServices set).

`--fake-hardware` / `CANDELA_FAKE_HARDWARE=1` still uses `FakeCatalog` unchanged.

## How to run

```sh
cd /Users/wyman/Documents/betterDisplay
./Scripts/generate_project.sh
open Candela.xcodeproj
```

Run the **Candela** scheme (no extra flags). The menu bar panel should list this Mac’s online displays (clamshell built-in hidden; mirrored slaves hidden). Virtual / Sidecar / AirPlay / DisplayLink / dummy `0xF0F0` rows are grey with no sliders. Other rows show a software-preview brightness slider that only updates the in-memory mailbox.

Fake catalog:

```
--fake-hardware
# or
CANDELA_FAKE_HARDWARE=1
```

## Verify

```sh
swift test --package-path .
xcodebuild -scheme Candela -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

Verified locally: **60 tests green**; Debug `ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO` **BUILD SUCCEEDED**.

## What landed

### DisplayCore (no AppKit, no IOKit)

- Virtual detector (§8): vendor `0xF0F0`, name/class contains dummy/sidecar/airplay/continuity/displaylink, `kCGDisplayIsVirtualDevice` / `kCGDisplayIsAirPlay`
- `classifyDisplayKind`: virtual → `virtualUnsupported`; builtin → `builtIn`; else `genericExternal` (no `appleExternal` until PR 3 DS probe)
- `ConnectionKind` first-hit: builtin → Transport Downstream/Upstream → `kIODisplayLocationKey` (`hdmi` / `displayport` / `/dp` / `thunderbolt` / `usb`) → unknown
- `effectiveDisplayID`, clamshell filter (`builtin && asleep`), mirror-slave hide, unique master IDs
- `buildLiveCatalog`: `makePersistentKey` with all online siblings + store records/aliases; §5 live-key aliasing (copy record, do not overwrite `newKey`, one-hop alias)
- Neutral capabilities: virtual = no sliders; others = `backend == .none` + `supportsSoftware` so the slider is mailbox-only. Volume `supportsVolume == false`
- EDID ASCII descriptors `0xFF` / `0xFC`
- `DisplayCataloging.requestRescan()` (default no-op) and `Notification.Name.candelaCatalogShouldRescan`
- `showsBrightnessSlider` is `supportsHardware || supportsSoftware` so PR 2 preview sliders appear without lying about a gamma/DS backend

### BrightnessKit

- `CoreDisplayInfo` — `dlsym("CoreDisplay_DisplayCreateInfoDictionary")` only (no extern in `CandelaPrivateIO`)
- `IOKitDisplaySource` — `CGDisplay*` + `IODisplayCreateInfoDictionary` (`takeRetainedValue`) + ARM `AppleCLCD2` / `IOMobileFramebufferShim` ProductAttributes / `"EDID UUID"`; Intel/fallback `synthesizeEdidUUID` from `kIODisplayEDIDKey`. Matching port is **`kIOMainPortDefault`**
- `SystemDisplayCatalog` — `CGDisplayRegisterReconfigurationCallback` (ignore `beginConfigurationFlag`), Foundation notification, **400 ms** debounce, full rescan, persist aliases via `PersistenceStoring`

### App

- `DisplaySessionController.makeDefault()`: fake → `FakeCatalog`; else `SystemDisplayCatalog` sharing the same `PersistenceStore`
- `NSScreen+Candela`: `NSScreenNumber` → `localizedName` only if IOKit/CoreDisplay name is empty
- `HotPlugObserver`: `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.didWakeNotification` / `willSleepNotification` → `requestRescan()`
- Rescan still-present/new boxes call `recreateHandles()` (no-op until PR 3/4)
- First-launch panel behavior unchanged

### Tests (no hardware)

- Virtual detector (name/vendor/flags/class)
- `ConnectionKind` from transport + location
- `effectiveDisplayID` / clamshell / mirror filter
- Live catalog builder: preview sliders, twins + port suffix, alias on twin attach, no overwrite of existing `newKey`
- Identity vectors still green; EDID descriptor parse

## Out of scope

DisplayServices / gamma / DDC writes, `appleExternal` classification, HAL volume bind, restore machine. Left `DDCPacket.swift` / `AudioMatching.swift` alone.
