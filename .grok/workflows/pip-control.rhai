let meta = #{
    name: "pip-control",
    description: "Implement Picture in Picture remote control of the captured display or window, one phase at a time",
    when_to_use: "When adding or continuing PIP control of the source app from the floating preview",
    phases: [
        #{ title: "Map", detail: "preview-to-source coordinate mapping" },
        #{ title: "Chrome", detail: "Control toggle exclusive with click-through" },
        #{ title: "Inject", detail: "display-mode mouse click and scroll" },
        #{ title: "Keys", detail: "keyboard forwarding while hovering the preview" },
        #{ title: "Window", detail: "window-mode mapping and raise-on-click" },
    ],
};

let status_schema = #{
    "type": "object",
    "required": ["ok", "summary"],
    "properties": #{
        "ok": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
    },
};

let raw_phase = if args == () { () } else { args.phase };
let phase = if raw_phase == () { "all" } else { raw_phase };
log("pip-control phase=" + phase);

let repo = "/Users/wyman/Documents/betterDisplay";
let summaries = [];
let failed = 0;

fn wants(phase, name) {
    phase == "all" || phase == name
}

fn phase_ok(result) {
    result != () && result.success && result.output != () && result.output.ok == true
}

fn phase_summary(label, result) {
    if phase_ok(result) {
        let s = result.output.summary;
        if s == () { return label + ": ok"; }
        return label + ": " + s;
    }
    label + ": failed"
}

if wants(phase, "mapping") {
    phase("Map");
    let p = "";
    p += "Implement Picture in Picture coordinate mapping in " + repo + ". ";
    p += "Read Sources/DisplayCore/PictureInPicture.swift, App/Candela/Sources/PictureInPictureWindowController.swift, ";
    p += "App/Candela/Sources/PictureInPictureCapture.swift, Tests/DisplayCoreTests/PictureInPictureTests.swift. ";
    p += "Add Sources/DisplayCore/PictureInPictureInteraction.swift with pure CoreGraphics functions, no AppKit: ";
    p += "letterboxedContentRect (aspect-fit, matches AVLayerVideoGravity.resizeAspect), ";
    p += "normalizedPoint (preview AppKit origin bottom-left -> captured image origin top-left), ";
    p += "quartzPoint (preview click -> sourceBounds in Quartz global coords, origin top-left of main display), ";
    p += "canControlSource (false when hostDisplayID equals sourceDisplayID, or either id is 0, or host is missing), ";
    p += "resolvedClickThrough (false when controlSource is true). ";
    p += "Add PictureInPicturePlacement.controlSource Bool default false; decodeIfPresent default false so old JSON still loads. ";
    p += "Unit-test letterbox, mirrored X, letterbox miss returns nil, same-display reject, legacy JSON without controlSource. ";
    p += "Do not inject events in this phase. Run: swift test --filter PictureInPictureTests. ";
    p += "Set ok=true only after tests pass. summary=files changed.";
    let r = agent(p, #{ label: "map:implement", capability_mode: "all", output_schema: status_schema });
    summaries.push(phase_summary("mapping", r));
    if !phase_ok(r) { failed += 1; }
}

if wants(phase, "chrome") {
    phase("Chrome");
    let p = "";
    p += "Add a Control toggle to the Candela PIP chrome in " + repo + ". ";
    p += "Read PictureInPictureWindowController.swift, PictureInPicturePinControl.swift, CandelaChrome.swift, ";
    p += "Localizable.xcstrings, MenuBarGuide.swift, PersistenceStoreTests.swift. ";
    p += "Button symbol cursorarrow.click, next to Click Through. Mutually exclusive with clickThrough. ";
    p += "Persist placement.controlSource. Disable when canControlSource is false (PIP on the source display) ";
    p += "or when APP_SANDBOX_CONTAINER_ID is set (Mac App Store). ";
    p += "Turning Control on must force clickThrough off; turning clickThrough on must force Control off. ";
    p += "Preview swallows mouse (allowsWindowDrag=false) while Control is on; chrome still moves the panel. ";
    p += "Do not post CGEvents yet. Add en and zh-Hans strings. ";
    p += "Fix MenuBarGuide: hidden icon is not a permission issue; PIP uses Screen Recording; Control uses Accessibility. ";
    p += "Set ok=true after reading the controller and confirming the toggle compiles in your head against existing applyClickThrough. ";
    p += "summary=chrome behavior.";
    let r = agent(p, #{ label: "chrome:implement", capability_mode: "all", output_schema: status_schema });
    summaries.push(phase_summary("chrome", r));
    if !phase_ok(r) { failed += 1; }
}

if wants(phase, "inject") {
    phase("Inject");
    let p = "";
    p += "Implement display-mode mouse forwarding for Candela PIP in " + repo + ". ";
    p += "New App/Candela/Sources/PictureInPictureEventInjector.swift: AXIsProcessTrustedWithOptions, ";
    p += "CGEvent mouse and scroll at a Quartz point, restoreCursor via CGWarpMouseCursorPosition back to the AppKit pointer, ";
    p += "CGEventSource.setLocalEventsSuppressionInterval(0). Skip inject when usePlaceholder or sandboxed. ";
    p += "Prompt Accessibility only when the user turns Control on. If denied, leave Control off. ";
    p += "Map preview clicks with PictureInPictureInteraction.quartzPoint using the last captured sourceQuartzBounds ";
    p += "(CGDisplayBounds / SCDisplay.frame for display, crop for magnifier, SCWindow.frame for window). ";
    p += "Forward left/right click, drag, scroll. Do not forward hover mouseMoved. ";
    p += "Letterbox clicks swallow (do not drag the PIP). In Control mode scroll goes to the source, pinch still zooms the PIP. ";
    p += "Magnifier space-pan still wins over inject. Draw a small virtual cursor on the preview. ";
    p += "If the user drags the PIP onto the source display, turn Control off. ";
    p += "Set ok=true only if injector and window controller compile conceptually and tests still pass. summary=inject path.";
    let r = agent(p, #{ label: "inject:implement", capability_mode: "all", output_schema: status_schema });
    summaries.push(phase_summary("inject", r));
    if !phase_ok(r) { failed += 1; }
}

if wants(phase, "keyboard") {
    phase("Keys");
    let p = "";
    p += "Add keyboard forwarding for Candela PIP Control in " + repo + ". ";
    p += "While Control is on and the pointer is over the preview, a local NSEvent key monitor posts CGEvent keyboard events. ";
    p += "Do not swallow Command-W (closes hovered PIP), Command-Tab, Command-comma. ";
    p += "Do not forward Space while magnifier canvas pan is active. ";
    p += "Candela is a nonactivating panel so the last injected click should leave the source app focused. ";
    p += "Set ok=true after implementing and grepping that Cmd-W still closes. summary=keyboard rules.";
    let r = agent(p, #{ label: "keys:implement", capability_mode: "all", output_schema: status_schema });
    summaries.push(phase_summary("keyboard", r));
    if !phase_ok(r) { failed += 1; }
}

if wants(phase, "window") {
    phase("Window");
    let p = "";
    p += "Finish window-mode PIP control in " + repo + ". ";
    p += "Keep sourceQuartzBounds = last SCWindow.frame while mode is window. ";
    p += "On first click, if the mapped point would miss because the window moved, re-resolve via PictureInPictureWindowMatching ";
    p += "and PictureInPictureCapture.window. Optionally AX-raise the window if HID click would hit something else. ";
    p += "Do not claim occluded windows are pixel-perfect. Wall tiles stay view-only. ";
    p += "Set ok=true after window bounds refresh exists. summary=window mapping.";
    let r = agent(p, #{ label: "window:implement", capability_mode: "all", output_schema: status_schema });
    summaries.push(phase_summary("window", r));
    if !phase_ok(r) { failed += 1; }
}

let report = "";
let si = 0;
for row in summaries {
    if si > 0 { report += " | "; }
    report += row;
    si += 1;
}
if report == "" { report = "no phases selected"; }

complete(#{
    ok: failed == 0,
    phase: phase,
    failed: failed,
    summary: report,
});
