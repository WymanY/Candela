# Using Candela

Help for the menu-bar app. The product homepage is [README.en.md](../README.en.md). 中文：[using.md](using.md)

Keep the user-visible English labels as they appear in the app.

## Display discovery

The menu-bar panel updates when cables attach or detach, and after clamshell sleep. A sleeping built-in panel and mirrored slave screens are hidden.

Sidecar, AirPlay, Continuity, and DisplayLink appear as Unsupported: visible, not controllable.

## Brightness and volume

Apple built-in and Apple external panels use system backlight. Third-party HDMI / DisplayPort / USB-C monitors use DDC brightness on Apple Silicon. If hardware control is missing or fails, Candela falls back to Software dimming.

Night, Desk, and Max are 20%, 50%, and 100%. Match All copies one display's brightness (and volume / contrast when available) onto the others.

Follow keyboard brightness keeps other displays at a relative offset while F1 / F2 still move the built-in panel. The switch lasts only for the current launch. Dragging one slider only changes that display's offset. Candela does not take over media keys.

Restore last brightness on reconnect brings a panel back to its last brightness after unplug. Menu-bar sliders follow hardware brightness after keyboard, System Settings, or OSD changes, without writing the sampled value back.

Laptop and iMac built-in panels do not get a volume row. Matching HDMI / DisplayPort / Thunderbolt speakers use system volume; DDC volume is used when the monitor exposes it; digital outputs without a hardware slider fall back to software attenuation. Software volume needs Screen Recording. HDMI / DP software volume also needs audio capture permission.

External monitors that can rotate support 0° / 90° / 180° / 270°. Built-in panels never expose rotation. Contrast and input select appear when the monitor answers those controls.

## Mirror and Layout

The footer Mirror button mirrors every attached display onto the built-in panel. It becomes Unmirror; click again to restore the previous arrangement. External rows hide while mirrored; the button stays in the footer. Mirror hides when only one real display is live.

Layout opens a separate Display Layout window to Arrange extended displays. Drag any display; the layout applies after you stop dragging. You need at least two real displays, and mirroring must be off. The footer action is Done.

Mirror stacks screens onto the built-in panel. Layout changes the relative position of an extended desktop. Do not use both at once.

## Picture in Picture and Display Overview

Each real display has a PiP button. The footer Overview control opens Display Overview.

Picture in Picture is a floating, resizable window and opens on the display under the pointer. The source can be Display, Window, or Magnifier. Until a window is chosen, Window still shows that display. Display and Window hint Scroll to zoom. Magnifier hints Space-drag to pan. Flip the preview horizontally for a teleprompter.

The title bar has Opacity (down to 25%) and Click Through. Clicks on the preview reach the work underneath; hovering the window still zooms it with the scroll wheel. Pin Corner snaps to top-left, top-right, bottom-left, bottom-right, or center. Dragging off that position unpins it. Each display remembers the last place, size, opacity, and window state.

Esc closes the hovered PiP or Display Overview; otherwise it closes Overview first, then every remaining PiP. Control-Esc only leaves source control. ⌘W still closes the hovered window.

Display Overview tiles every real display into one floating window. Each tile can be dismissed. Show Hidden brings those tiles back. Closing the wall, or dismissing every tile, also turns Overview off in the menu-bar panel. The next open restores the full wall. Virtual screens stay out.

Picture in Picture and Display Overview need Screen Recording: System Settings → Privacy & Security → Screen Recording.

## Scenes

Save Scene from the menu bar and Apply Scene later. Applying a scene also switches back to the speaker that was selected then, and restores its volume and mute. That is the only time Candela changes the system default audio output.

The Settings Scenes tab can rename, update, or delete saved scenes. Saving with the same name overwrites that scene instead of duplicating it. Missing displays are skipped and applied again when they return. Candela does not ship built-in scene templates. Saved scenes live in local preferences and survive app relaunch.

## Battery

When a MacBook is unplugged, the menu-bar panel shows the current battery percent and remaining time beside the title. On AC power the chip switches to a charging bolt. The chip hides on desktops, or when no internal battery is present.

## Settings

- Launch at Login
- Restore last brightness on reconnect
- Follow keyboard brightness
- Software dimming
- Allow dim to black
- Show percent next to sliders
- Per-display custom names
- Save and apply Scenes

## Permissions

- Picture in Picture, Display Overview, and software volume: Screen Recording
- HDMI / DP software volume: audio capture
- Source control (send clicks and scrolls to the other display): Accessibility; Control-Esc exits
