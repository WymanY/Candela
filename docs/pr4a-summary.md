# PR 4a — DDC packet builders + golden vectors

Pure DDC/CI packet encode/decode for **Candela**. No I²C, `IOAVService`, `IOI2CInterface`, or mailbox I/O. Hardware clients are PR 4b / 4c.

## How to verify

```sh
cd /Users/wyman/Documents/betterDisplay
swift test --package-path . --filter DDCPacketTests
```

Full package (must stay green):

```sh
swift test --package-path .
```

## Contract (design.md §7.2)

`xor8(seed, bytes)` is an inclusive XOR fold. Arm64 send buffers omit `0x51` (it is the `IOAVServiceWriteI2C` data address). Intel send buffers start with `0x51`. GET/SET checksum seeds:

| Path | Seed |
| --- | --- |
| Arm64 GET | `0x6E` |
| Arm64 SET | `0x6E ^ 0x51` (`0x3F`) |
| Intel GET/SET | `0x6E` over the send prefix |
| Reply | `0x50` over bytes `[0]…[9]` |

Reply is valid only when `count == 11`, checksum matches, `reply[2] == 0x02`, and `reply[3] == 0x00`. Then `max = [6]<<8|[7]`, `current = [8]<<8|[9]`.

Normative goldens (byte-for-byte):

| Case | Bytes |
| --- | --- |
| Arm64 GET `0x10` | `82 01 10 FD` |
| Arm64 GET `0x62` | `82 01 62 8F` |
| Arm64 SET `0x10` = 0 | `84 03 10 00 00 A8` |
| Arm64 SET `0x10` = 50 | `84 03 10 00 32 9A` |
| Arm64 SET `0x10` = 100 | `84 03 10 00 64 CC` |
| Arm64 SET `0x62` = 25 | `84 03 62 00 19 C3` |
| Intel GET `0x10` | `51 82 01 10 AC` |
| Intel GET `0x62` | `51 82 01 62 DE` |
| Intel SET `0x10` = 50 | `51 84 03 10 00 32 9A` |
| Intel SET `0x10` = 100 | `51 84 03 10 00 64 CC` |
| Intel SET `0x62` = 25 | `51 84 03 62 00 19 C3` |
| Reply current=50 max=100 | `6E 51 02 00 10 00 00 64 00 32 2B` |

## Files created

- `Sources/BrightnessKit/DDCPacket.swift` — `xor8`, Arm64/Intel GET+SET, `parseReply`, VCP `0x10` / `0x62` / `0x8D`
- `Tests/BrightnessKitTests/DDCPacketTests.swift` — §7.2 goldens + invalid-reply rejects
- `docs/pr4a-summary.md`

Public API:

```swift
DDCPacket.xor8(seed:bytes:)
DDCPacket.arm64Get(vcp:)
DDCPacket.arm64Set(vcp:value:)
DDCPacket.intelGet(vcp:)
DDCPacket.intelSet(vcp:value:)
DDCPacket.parseReply(_:)
DDCPacket.VCP.brightness / .volume / .mute
```

## Out of scope (later PRs)

- Arm64 `IOAVService` client (PR 4b)
- Intel `IOI2CInterface` client (PR 4c)
- Mailbox coalesce / `lastDDC` pulse tests (needs a real client)
- `App/`, DisplayCore identity, `AudioMatching`, `DisplayIOBox`, `project.yml`
