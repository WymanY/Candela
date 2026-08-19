# Menu bar debugging on macOS 26

## Symptom

An `NSStatusItem` can report `isVisible == true` and have a valid button window while no icon appears in the menu bar. The app may also appear enabled under System Settings > Menu Bar > Allow in the Menu Bar.

## Cause

macOS 26 associates the menu bar permission with the app identity, including its bundle identifier and signing identity. A TestFlight build and a locally signed Debug build can therefore receive different menu bar permission state even when they use the same bundle identifier.

Do not try to override this state by writing undocumented defaults such as `NSStatusItem Visible ...` or `NSStatusItem VisibleCC ...`. Those keys are implementation details and can leave stale or contradictory state.

## Diagnosis

1. Confirm that `NSStatusItem.button`, its window, and its frame are valid.
2. Run a minimal AppKit menu bar app under a fresh bundle identifier.
3. If the minimal app appears, run the same code with the affected app identity.
4. Compare bundle identifiers and signing team identifiers with `codesign -dv --verbose=4 <app>`.

This separates status item implementation bugs from system permission and signing-state problems.

## Candela configuration

Candela uses only public AppKit APIs to create its status item. It configures the button before setting `isVisible = true`, runs as an `LSUIElement` accessory app, and does not write private status item preferences.

The local Debug build uses `app.candela.macos.debug`. Release and TestFlight builds continue to use `app.candela.macos`. This keeps local debugging independent from the installed production app and makes the menu bar permission deterministic on machines without the production team's development certificate.

If local Xcode signing is later configured with a development certificate from the same Apple Developer team as the production app, Debug may use the production bundle identifier instead. Separate Debug and Release bundle identifiers are a development convenience, not an AppKit requirement.
