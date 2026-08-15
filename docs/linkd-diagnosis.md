# `linkd` / App Intents console noise

Logs seen when running **Candela** from Xcode (macOS 26 / Tahoe, Xcode 26):

```
Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut"
Unable to re-register with Process Instance Registry
Error registering app with intents framework
Will NOT re-try to establish the connection
```

## Verdict

**Harmless system / Xcode noise. Not a Candela bug.** Our code does not register with App Intents, Shortcuts, Siri, or `linkd`. There is **no public plist key, entitlement, scheme setting, or “don’t link AppIntents” change that stops this.** Do not add dummy intents or Intents plist keys to “fix” it.

## Cause

`com.apple.linkd` is Apple’s Link daemon (private `LinkServices`). It owns App Intents / App Shortcuts / Spotlight / Apple Intelligence targeting of a **running process**.

On modern macOS (15+, louder on 26), **AppKit `NSApplication` launch** always tries to:

1. Open an XPC connection to Mach service `com.apple.linkd.autoShortcut`.
2. Register the process with the **Process Instance Registry** so Shortcuts / Siri / Spotlight can address *this* instance.

That path lives in AppKit + LinkServices, **not** in app code. It is **not** gated on:

- linking `AppIntents.framework` or `Intents.framework`
- an `AppIntent` / `AppShortcutsProvider` type
- `INIntentsSupported` / `NSUserActivityTypes`
- extracted App Intents metadata
- a Siri entitlement

`NSCocoaErrorDomain` **4097** is the usual XPC “connection invalid / interrupted / service not advertised to this client” failure. The daemon then logs the next three lines and **gives up** (`Will NOT re-try`). Registration is best-effort. Failure does not abort launch, change activation policy, or affect brightness / volume.

Why it shows up so often from Xcode:

- Console captures system `os_log` from AppKit / LinkServices.
- The binary lives under DerivedData, not `/Applications`.
- Debug signing + `get-task-allow` (Xcode default `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`) is a different client than a notarized `/Applications` build.
- For an app with **zero** intents, `linkd` has nothing to bind; the connection often dies immediately.

The same quartet is reported by other AppKit menu-bar apps that also have no App Intents (e.g. third-party LSUIElement apps). It is not unique to Candela.

`LSUIElement = true` and the Debug `NSApp.setActivationPolicy(.regular)` path do **not** cause this. They only change Dock / activation policy.

## What we searched (nothing in our tree)

| Area | Result |
| --- | --- |
| `AppIntents`, `AppIntent`, `AppShortcut`, `AppShortcutsProvider` | **none** |
| `INIntent`, `Intents.framework`, SiriKit | **none** |
| `NSUserActivity`, `continueUserActivity`, `NSUserActivityTypes` | **none** |
| `linkd`, `Process Instance Registry` | **none** (logs only) |
| `import` lines | AppKit / Foundation / IOKit / CoreAudio / CoreGraphics / our kits only |

Explicit **non-goal** in [`docs/design.md`](design.md) § Non-goals (v1): “App Intents / Shortcuts / Sparkle / iCloud”.

### Files that would have been the trigger (they are clean)

| File | Relevant contents |
| --- | --- |
| [`App/Candela/Sources/AppDelegate.swift`](../App/Candela/Sources/AppDelegate.swift) | `@main` `NSApplicationDelegate`. Rosetta abort, activation policy, session + status item. No activity / intent APIs. |
| [`App/Candela/Resources/Info.plist`](../App/Candela/Resources/Info.plist) | Identity + `LSUIElement`, `LSRequiresNativeExecution`, `NSPrincipalClass = NSApplication`, no auto-termination. **No** `INIntentsSupported`, `NSUserActivityTypes`, `NSServices`, document types, App Intents keys. |
| [`App/Candela/Supporting/Candela.entitlements`](../App/Candela/Supporting/Candela.entitlements) | Empty `<dict/>`. No `com.apple.developer.siri`, no App Groups, no iCloud. |
| [`project.yml`](../project.yml) | `GENERATE_INFOPLIST_FILE: NO`. No `AppIntents` package/framework. No metadata extract flags. |
| [`Candela.xcodeproj/project.pbxproj`](../Candela.xcodeproj/project.pbxproj) | No `AppIntents.framework`, no Extract App Intents Metadata phase, no `APP_INTENTS_*` / `SKIP_APP_INTENTS_*` settings. |
| [`Candela.xcodeproj/xcshareddata/xcschemes/Candela.xcscheme`](../Candela.xcodeproj/xcshareddata/xcschemes/Candela.xcscheme) | Stock Debug run. No Intents / UI testing / environment that would talk to `linkd`. |
| [`Package.swift`](../Package.swift) | DisplayCore / BrightnessKit / AudioKit / PersistenceKit / TestSupport. Linked frameworks: IOKit, CoreGraphics, CoreDisplay, CoreAudio, AudioToolbox only. |

`NSApplication` is the principal class (`Info.plist` + `project.yml`). There is no `NSApplication` subclass that could hook launch beyond `AppDelegate`.

## Can we prevent the registration?

**No, not with a supported API.**

| Idea | Do it? | Why |
| --- | --- | --- |
| Stop linking AppIntents | N/A | We already don’t. AppKit still calls LinkServices. |
| Add `INIntentsSupported` / `NSUserActivityTypes` (empty or dummy) | **No** | Old SiriKit. Invites *more* Intents machinery. |
| Add a stub `AppIntent` / empty metadata so registration “succeeds” | **No** | Contradicts the v1 non-goal; still talks to `linkd`; may surface a empty Shortcuts entry. |
| Invented keys (`NSAppIntentsEnabled=false`, etc.) | **No** | Not documented. Ignored. |
| `GENERATE_INFOPLIST_FILE` / `INFOPLIST_KEY_*` App Intents keys | **No** | Already `GENERATE_INFOPLIST_FILE = NO`. Those keys enable metadata, they don’t disable runtime PIR. |
| Build setting `SKIP_APP_INTENTS_METADATA` / don’t run metadata processor | **No effect** | Build-time extract only. Runtime AppKit still registers. We have no extract phase anyway. |
| Scheme: turn off “Debug executable”, Location, etc. | **No** | Unrelated. |
| `OS_ACTIVITY_MODE=disable` in the scheme | **Do not commit** | Hides *all* `os_log`, including ours (`subsystem: app.candela.macos`). |
| Xcode console filter for `linkd` / `intents framework` | Optional, local only | Fine as a personal filter; don’t encode in the scheme. |
| Ship only from `/Applications` with a real team | Optional | May reduce how often XPC 4097 fires; **does not** stop the attempt. Empty `CANDELA_DEVELOPMENT_TEAM` can make debug XPC pickier but is not the root cause. |

**Recommended action: none.** Treat the four lines as known Xcode/macOS 26 console spam. File a Feedback to Apple if we want it quieter (`AppKit` + `App Intents`); there is nothing for Candela to change until Apple adds an opt-out.

If a later PR actually ships App Intents (out of v1 scope), these logs become *diagnostic*: then a failed `linkd` connection would mean Shortcuts/Siri cannot see the running instance, and we would debug signing, install location (`/Applications`), and metadata extract — not suppress the log.

## Severity

| Question | Answer |
| --- | --- |
| User-visible? | No |
| Breaks brightness / volume / panel / quit? | No |
| Data loss / security? | No |
| Blocks shipping? | No |
| Our registration bug? | No — we never register |
| When to re-open | Only if we add App Intents / Shortcuts and they fail to appear |

## Quick re-check

```sh
rg -n 'AppIntents|AppIntent|AppShortcut|INIntent|NSUserActivity|linkd|Intents' \
  --glob '!docs/**' --glob '!*.md'
```

Expect no hits in Swift / plist / yml / entitlements / pbxproj.
