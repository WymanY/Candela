# PR 5 (matcher) — `AudioMatching.match`

Pure DisplayCore matcher from design §9.3. No CoreAudio, no I²C, no PersistenceKit, no App UI.

## API

```swift
public enum AudioMatching {
    public static func match(
        display: DisplaySnapshot,
        overrideUID: String?,
        devices: [HALOutputDevice]
    ) -> String?  // uid or nil
}
```

`HALOutputDevice.transport` is `UInt32` (FourCC). Constants on `AudioMatching`:

| Transport | FourCC | Value | Auto-bind |
| --- | --- | --- | --- |
| HDMI | `'hdmi'` | `0x68646D69` | always |
| DisplayPort | `'dprt'` | `0x64707274` | always |
| Thunderbolt | `'thun'` | `0x7468756E` | always |
| USB | `'usb '` | `0x75736220` | only `DisplayKind.appleExternal` |
| built-in / other | — | — | never (score 0) |

Built-in and `virtualUnsupported` displays always return `nil` (override ignored).

## Algorithm

1. Strip leftover `" (2)"` / `" (3)"` with ` \([0-9]+\)$` **before** normalize.
2. `normalize`: uppercase; remove HDMI / DISPLAYPORT / DISPLAY PORT / THUNDERBOLT / USB-C / USB C / USB (longest first); drop punctuation; collapse whitespace.
3. Score pairs (0 if transport not allowed, except a present override):

| Condition | Score |
| --- | --- |
| Override UID equals device UID | +1000 |
| Normalized names equal, length ≥ 3 | +10 |
| One normalized name contains the other, min length ≥ 5 | +6 |
| `modelToken` equal | +8 |
| `sizeToken` equal (15–49 in) | +2 |
| Shared `VENDOR_TOKENS` (name / manufacturer / EDID PNP) | +4 |
| Connection matches HDMI / DP / TB transport | +3 |
| `appleExternal` + USB or Thunderbolt | +3 |

4. Keep pairs with score ≥ 6 **or** override.
5. Sort score desc, `persistentKey` asc, `uid` asc.
6. Greedy assign if neither side is taken.
7. Same-score tie on that display **or** that device: assign **neither** of the tied pairs; continue at lower scores.
8. Override UID missing from the device list: ignore it and rematch. Pure function — no `volume.notes`.

Internal `AudioMatching.assign` runs the same engine over several displays (session can use it later so two rows do not claim one UID).

Vendor-from-EDID: decode the 3-letter PNP from `vendorID` and map the closed list (APP→APPLE, DEL→DELL, GSM→LG, …).

## Tests

`Tests/DisplayCoreTests/AudioMatchingTests.swift`

1. Dell HDMI + HDMI device, same name → bind
2. Two displays + two identical-score devices → bind neither (per-display and global)
3. USB headset vs USB-C generic Dell → no bind
4. Studio Display (`appleExternal`) + USB speakers, matching name → bind
5. Override UID wins even when names differ (including USB on a generic panel)
6. Device name leftover ` (2)` still matches
7. Override UID missing → rematch to the name pair, not `nil`

Also: built-in / virtual never bind; a two-way high-score tie falls through to a unique lower pair.

`ProtocolSmokeTests` now asserts built-in never binds (the old stub-returns-nil fixture would have bound under override).

`LiveCatalogBuilderTests.testVirtualGetsNoSliderGenericGetsPreview` compared `Optional.none` to `BrightnessBackendKind.none`; the assertion is now explicit so `swift test` is green. No catalog logic change.

## Verify

```sh
cd /Users/wyman/Documents/betterDisplay
swift test --package-path .
```

## Out of scope (rest of PR 5)

- HAL `AudioObject*` get/set (`'vmvc'`, VolumeScalar, mute)
- `bindAudio` / `probeDDCVolume` on `DisplayIOBox`
- Settings override UI / `volume.notes` warning copy
