---
name: candela
description: Control Candela display brightness, HDMI/DP hardware or software volume, DDC contrast, and input select on this Mac. Use when an agent should list displays, dim or brighten a monitor, apply Night/Desk/Max presets, mute speakers, switch HDMI/DP input, rename a display, or debug Candela. Prefer candela-cli against the running menu-bar app.
---

# Candela

Control the running Candela menu-bar app through `candela-cli`. Do not guess brightness APIs or write DDC packets yourself.

## Preconditions

1. Candela.app must be running. The CLI talks to `~/Library/Application Support/Candela/control.sock`.
2. Resolve the binary first:
   - `swift run --package-path /Users/wyman/Documents/betterDisplay candela-cli --help` during development
   - or a built `.build/debug/candela-cli`
3. If the socket is missing, tell the user to launch Candela. Do not fall back to `brightness`/`ddcctl`.

## Display queries

Use one of: display name, custom name, `persistentKey`, `main`, `builtin`, `external`.

If `list` returns several similar names, ask or use the key.

## Commands

```bash
candela-cli list
candela-cli get --display "DELL"
candela-cli set-brightness --display builtin --value 0.35
candela-cli set-volume --display DELL --value 0.2
# Software attenuation is used when the matched HDMI/DP device has no HAL/DDC volume.
candela-cli set-mute --display DELL --muted true
candela-cli set-contrast --display DELL --value 0.5
candela-cli set-input --display DELL hdmi1
candela-cli rename --display DELL --name "Desk"
candela-cli preset night
candela-cli preset --display external desk
candela-cli match-all --display main
candela-cli dump
```

Values are `0...1`. Presets: `night` = 0.20, `desk` = 0.50, `max` = 1.0.

Every command prints one JSON object. `ok: false` means stop and report `error`.

## MCP

`candela-mcp` is a local stdio MCP server with the same operations. See [references/cli.md](references/cli.md) for tool names. Prefer the CLI unless the host is already configured for MCP.

## Limits

Candela does not create virtual screens, override EDID, unlock XDR nits, change resolution, or take over media keys. Built-in panels do not support rotation. Sidecar/AirPlay rows are listed but not controllable.
