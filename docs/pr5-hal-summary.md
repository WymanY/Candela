# PR 5 (HAL) — volume / mute via `AudioObject*`

Core Audio HAL enumerate + get/set for Candela. Isolated `AudioKit` files. No DDC, no `DisplayIOBox` rewrite, no SwiftUI, no `DDCPacket` / `PrivateSymbols`.

## How to verify

```sh
cd /Users/wyman/Documents/betterDisplay
swift test --package-path .
```

76 tests green, including `HALVolumeControlTests` (16). Live HAL tests only **read** the default output device; they never write volume or mute.

## Contract (design.md §9.2, §9.4, K10, K20)

All HAL I/O is `AudioObjectHasProperty` / `AudioObjectIsPropertySettable` / `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`. Array sizing uses `AudioObjectGetPropertyDataSize` (same `AudioObject*` family). **Never** `AudioHardwareService*`. Default output is never changed.

```swift
public let kCandelaVirtualMainVolume: AudioObjectPropertySelector = 0x766D7663 // 'vmvc'
```

Use `'vmvc'` only when `HasProperty && settable`. Try Output first; try Global **only if** Output `HasProperty` is false. There is no VirtualMasterMute / `'vmm '`.

**Volume write** (`Float32` 0...1), first settable path wins; channel fall-through writes **every** settable element:

1. `'vmvc'` Output (or Global if Output `HasProperty` is false), element Main
2. `kAudioDevicePropertyVolumeScalar` + output + `ElementMain`
3. Else walk `kAudioDevicePropertyStreamConfiguration` (`AudioBufferList`) and write the same scalar to every settable `VolumeScalar` element (channel index, not stream count; not just 1–2)

**Mute** (`UInt32` 0/1): Main `kAudioDevicePropertyMute`, else the same stream-configuration walk.

**Enumerate:** `kAudioHardwarePropertyDevices` entries that have an output stream (`kAudioStreamPropertyDirection == 0`). Transport, name, manufacturer, UID. `hasVolume` / `hasMute` via `HasProperty` on the §9.4 addresses. Returns `[HALOutputDevice]`.

## Files

- `Sources/AudioKit/HALDeviceEnumerator.swift` — `outputDevices()`, UID lookup, default-output UID (read), `AudioObject*` helpers
- `Sources/AudioKit/HALVolumeControl.swift` — address builders, path selection, get/set volume + mute
- `Tests/AudioKitTests/HALVolumeControlTests.swift` — FourCC, addresses, channel walk, path order, read-only default device
- `App/Candela/Sources/DisplaySessionController+Audio.swift` — `refreshAudioBindings()`
- `App/Candela/Sources/DisplaySessionController.swift` — call `refreshAudioBindings()` after snapshots update; `setVolume` / `setMuted` also call `HALVolumeControl` when `audioDeviceUID` is set

Public API:

```swift
HALDeviceEnumerator.outputDevices() -> [HALOutputDevice]
HALDeviceEnumerator.defaultOutputUID() -> String?
HALVolumeControl.setVolume(uid:value:)
HALVolumeControl.volume(uid:)
HALVolumeControl.setMuted(uid:muted:)
HALVolumeControl.isMuted(uid:)
HALVolumeControl.volumeWritePath(hasProperty:isSettable:channelElements:)
HALVolumeControl.channelElements(bufferChannelCounts:)
```

## Session wiring (minimal)

After `apply` updates snapshots (skipped for `--fake-hardware` / `CANDELA_FAKE_HARDWARE`):

1. Enumerate HAL output devices
2. `AudioMatching.match` per display (built-in / virtual skipped)
3. `box.bindAudio(uid:)`
4. Set `volume.audioDeviceUID`, `supportsVolume` / `supportsMute`, `backend = .coreAudio` when the device has volume or mute
5. Missing override UID → rematch and `volume.notes = "Saved audio device missing — rematched"`

Slider writes still go to the box mailbox **and** HAL when a UID is bound. No `probeDDCVolume` hardware. No `DisplayIOBox` changes.

## Out of scope

- DDC VCP `0x62` / `0x8D` probe
- HAL device listener / default-output changes
- Settings override UI
- `DisplayIOBox.applyHALVolume` (intentionally not added)
