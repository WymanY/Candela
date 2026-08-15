# PR 4b — Apple Silicon DDC via IOAVService

Arm64 `IOAVService` client, DCPAVServiceProxy walk, and EDID-fragment score for **Candela**. Packets come from `DDCPacket.arm64Get/Set`. No edits to `DisplayIOBox`, `DisplaySessionController`, `DDCPacket`, AudioKit HAL, or App UI.

## How to verify

```sh
cd /Users/wyman/Documents/betterDisplay
swift test --package-path . --filter AVServiceScoreTests
```

Full package (must stay green):

```sh
swift test --package-path .
```

## Contract (design.md §7.2 + §11)

### IOAV `dlsym`

RTLD_DEFAULT first, then CoreDisplay (public then PrivateFrameworks). Loaded symbols:

- `IOAVServiceCreateWithService`
- `IOAVServiceReadI2C`
- `IOAVServiceWriteI2C`

`IOAVServiceCreate` (no-service) is never resolved or called. `CreateWithService` is Create-rule: `Unmanaged.takeRetainedValue()`. The strong property is nilled in `recreateHandle()`.

### On-wire

| | |
| --- | --- |
| Chip | `0x37` |
| Write `dataAddress` | `0x51` (not a buffer byte) |
| GET / SET body | `DDCPacket.arm64Get` / `arm64Set` |
| Reply | 11 bytes; `DDCPacket.parseReply` |
| Read offset | `0`, then `0x51` if unpinned; first valid checksum is pinned for the handle lifetime |
| Both offsets fail | GET latches unavailable; SET still allowed (write-only / `forceDDC`) |
| `ddcReadGap` | 50 ms after a SET before a verify GET, and after the GET write before `ReadI2C` |

Built-in (`CGDisplayIsBuiltin != 0`) never opens I²C. x86_64 and `CANDELA_GAMMA_ONLY` compile a stub (`isAvailable == false`).

### Matcher

Iterator: `IORegistryEntryCreateIterator` on the service plane, recursive.

- `AppleCLCD2` / `IOMobileFramebufferShim` → retain, replace current framebuffer, bump `serviceLocation`
- `DCPAVServiceProxy` with `Location == "External"` → `CreateWithService` and emit
- Missing / `Embedded` / other Location: do not emit

Score (IOReg `"EDID UUID"` with hyphens, uppercase):

| Fragment | Offset | Skip |
| --- | --- | --- |
| Vendor `%04X` clamped | 0 | `0000` |
| Product LE `%02X%02X` | 4 | `0000` |
| Week + year-1990 | 19 | `0000` |
| Image size mm/10 | 30 | `0000` |

Each hit +1. `kIODisplayLocationKey` exact vs IOReg path +10. Product name case-insensitive +1. Numeric serial (nonzero) equal +1.

Assignment: sort score descending; greedy; do not reuse `serviceLocation`; discard score 0. `serviceLocation` is not persisted.

## Files created

- `Sources/BrightnessKit/PrivateIO+IOAV.swift` — `PrivateSymbols` IOAV pointers + Create/Read/Write helpers
- `Sources/BrightnessKit/AVServiceMatcher.swift` — pure score + assign + IOReg walk
- `Sources/BrightnessKit/Arm64DDCClient.swift` — `DDCCommanding` (`#if arch(arm64)`)
- `Tests/BrightnessKitTests/AVServiceScoreTests.swift` — design-table fragments, example UUID `10AC4CD1-0000-0000-0A22-3C2200000000`, greedy assign
- `docs/pr4b-summary.md`

Public API:

```swift
AVServiceMatcher.score(display:service:)
AVServiceMatcher.assign(displays:services:)
AVServiceMatcher.walkExternalAVServices()
Arm64DDCClient(displayID:)
```

## Out of scope (other agents)

- Wiring `Arm64DDCClient` into `DisplayIOBox` / probe
- Intel `IOI2CInterface` (PR 4c)
- App UI / `DisplaySessionController` / AudioKit HAL
