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
| `set-mirror` | `setBuiltInMirror` | Mirror onto the built-in display or restore the previous arrangement |
| `set-follow-keyboard --enabled true` | `setFollowKeyboardBrightness` | This launch only; off again next start |
| `scenes` | `listScenes` | Saved scenes |
| `save-scene --name Night` | `saveScene` | Capture current mix; same name overwrites |
| `apply-scene Night` | `applyScene` | Name, slug, or id |
| `rename-scene Night --name Late` | `renameScene` | Rename a saved scene |
| `delete-scene Night` | `deleteScene` | Delete a saved scene |
| `set-pip --display Q --enabled true` | `setPictureInPicture` | Floating display mirror |
| `set-pip --display Q --mode window --window Slack --mirror true` | `configurePictureInPicture` | Follow a window and/or flip |
| `set-pip --display Q --mode magnifier --zoom 3` | `configurePictureInPicture` | Cursor magnifier |
| `set-pip-wall --enabled true` | `setPictureInPictureWall` | Multi-display wall |
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
- `candela_set_follow_keyboard`
- `candela_list_scenes`
- `candela_apply_scene`
- `candela_save_scene`
- `candela_rename_scene`
- `candela_delete_scene`
- `candela_set_picture_in_picture`
- `candela_set_picture_in_picture_wall`
- `candela_debug_dump`

stdio JSON-RPC, protocol `2024-11-05`.
