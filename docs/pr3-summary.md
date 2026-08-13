# PR 3 — DisplayServices and gamma brightness

Real brightness control: **DisplayServices** (`dlsym` only) for built-in / Apple panels, **gamma LUT** (`CGSetDisplayTransferByTable`) as the fallback for HDMI-dongle and when DS fails. Exclusive backend (K8). **No DDC / IOAVService / Intel I²C** in this PR.

`--fake-hardware` / `CANDELA_FAKE_HARDWARE=1` still uses `FakeCatalog` and never writes a real `CGDirectDisplayID`.

## How to run

```sh
cd /Users/wyman/Documents/betterDisplay
./Scripts/generate_project.sh
open Candela.xcodeproj
```

Run the **Candela** scheme (no extra flags). Built-in should track hardware brightness. A cheap HDMI dongle should dim via gamma. Slider ticks coalesce (mailbox consume). Quit restores the ColorSync baseline (does **not** call `CGDisplayRestoreColorSyncSettings()`).

Fake catalog (no real writes):

```
--fake-hardware
# or
CANDELA_FAKE_HARDWARE=1
```

Settings → General has a **Software dimming** checkbox (`GlobalSettings.softwareDimmingEnabled`).

## Verify

```sh
swift test --package-path .
xcodebuild -scheme Candela -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

Verified locally: **100 tests green**; Debug `ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO` **BUILD SUCCEEDED**.

## What landed

### Private I/O (`Sources/BrightnessKit/PrivateSymbols.swift`)

- `dlopen` DisplayServices, CoreDisplay, SkyLight as §11
- Function pointers only — never `extern` names that need linking
- `DisplayServicesGetBrightness` / `SetBrightness`
- `CGSIsHDREnabled` / `CGSIsHDRSupported` as `Int32`; non-zero is true
- `CGSServiceForDisplayNumber` resolved for later DDC
- `CoreDisplay_DisplayCreateInfoDictionary` lives here once; `CoreDisplayInfo` reuses it
- NULL pointer → that backend is unavailable; log once
- `CANDELA_GAMMA_ONLY` skips DisplayServices load

### Probe + exclusive fallback (§7 flowchart, K8, K22)

- `virtualUnsupported` → `none`, no sliders
- DS probe success: Get returns `0` **and** brightness ≥ 0
- macOS 15 HDR skip: `vendor != 0x0610` && HDR supported && HDR enabled → do not treat as Apple; fall through to gamma
- Missing HDR symbols → treat as pre-15 (do not skip)
- Never DDC a built-in; no DDC client at all this PR
- Force DDC ignored if DS succeeded; if DS failed, stay gamma
- Live DS fail ×3 → gamma if software allowed, else none — **never DDC** until a *new* `probeBrightness` (not `recreateHandles` alone)

### Gamma (§7.3, K9, K24)

- `scaleGamma(baseline:t:)` → `r'[i] = baseline[i] * t`
- Floor `t >= 0.05` unless `allowDimToBlack`
- Capture baseline via `CGGetDisplayTransferByTable` (actual sample count)
- Recapture after reconfig in `recreateHandles()` (restore first so `t` is not baked in)
- Keep-alive: repeating 2 s timer on `candela.io.<key>` while `softwareGamma && t < 1`
- Launch repair: if `|measuredT - expectedT| > 0.02` write last (restore on) or `1.0`
- SIGKILL leftover: invert current peak to recover baseline
- On quit / detach: write baseline back
- `CGError` failure → `supportsSoftware = false`
- `hdrWashes` when `CGSIsHDREnabled` and backend is gamma; row shows “Software dimming reduces HDR contrast.”
- Interference: 3 peak-drift hits while keep-alive is running → stop fighting

### Mailbox consume (§4, brightness only)

- `setBrightness(v)` → `latest = v`; arm 80 ms `sliderHold` if no write scheduled
- `beginWrite`: `toSend = latest; latest = nil`; write via DS/gamma/injected sink; `scheduleNext`
- One set after idle → one pulse (not a loop)
- DisplayServices / gamma / injected writer **do not** stamp `lastDDC` / `ddcInFlight`

### Session

After apply/rescan:

1. `recreateHandles()` then `probeBrightness`
2. Assign `snapshot.brightness = caps`; `kind = appleExternal` when DS wins and not built-in
3. 700 ms later if `restoreOnReconnect && lastBrightness != nil`: `setBrightness(last)` (ours wins)
4. Cancel restore task if the key detaches
5. Fake hardware: skip real probe; keep FakeSnapshots backends

### Tests

- Gamma scale: `t = 0.5` halves a synthetic table
- Launch-repair target + leftover-baseline invert
- HDR skip / probe winner / live-fail hysteresis as pure functions
- Mailbox consume with a fake writer: one `setBrightness` after idle → write count 1; two sets during hold → one write of the last value
- Live fail ×3 on a DS box → `softwareGamma`
- Fake snapshot probe does not touch hardware
- Existing suite stays green (100 tests)

## Out of scope

IOAVService / Intel I²C, DDC packet I/O, rewriting `AudioMatching` or `DDCPacket`. Volume mailbox consume stays store-only (HAL bind is unchanged).
