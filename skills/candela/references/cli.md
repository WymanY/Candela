# Candela CLI and MCP

## CLI

Binary: `candela-cli` from the CandelaKit package.

Socket: `~/Library/Application Support/Candela/control.sock`

| Command | Request action | Notes |
| --- | --- | --- |
| `list` | `list` | All live displays |
| `get --display Q` | `get` | One display |
| `set-brightness --display Q --value N` | `setBrightness` | 0...1 |
| `set-volume --display Q --value N` | `setVolume` | HDMI/DP speakers (HAL, DDC, or software) |
| `set-mute --display Q --muted true` | `setMuted` | true/false/on/off |
| `set-contrast --display Q --value N` | `setContrast` | DDC 0x12 |
| `set-input --display Q hdmi1` | `setInput` | hdmi1, hdmi2, dp, dp2, usbc, or 0x60 code |
| `rename --display Q --name Desk` | `rename` | Empty name clears custom name |
| `preset night` | `preset` | night/desk/max; optional `--display` |
| `match-all --display Q` | `matchAll` | Copy source brightness/volume/contrast |
| `dump` | `dump` | Redacted unless `--no-redact` |

## MCP tools

`candela-mcp` exposes:

- `candela_list_displays`
- `candela_get_display`
- `candela_set_brightness`
- `candela_set_volume`
- `candela_set_mute`
- `candela_set_contrast`
- `candela_set_input`
- `candela_rename_display`
- `candela_apply_preset`
- `candela_match_all`
- `candela_debug_dump`

stdio JSON-RPC, protocol `2024-11-05`.
