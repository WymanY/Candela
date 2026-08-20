import AppKit
import AudioKit
#if !CANDELA_MAS
import BrightnessKit
#endif
import ControlKit
import DisplayCore
import Foundation
import IOKit.ps
import PersistenceKit
import ServiceManagement
import TestSupport

@MainActor
final class DisplaySessionController {
    private let catalog: DisplayCataloging
    let persistence: PersistenceStoring
    var boxes: [String: DisplayIOBox] = [:]
    private var updatesTask: Task<Void, Never>?
    private var hotPlugObserver: HotPlugObserver?
    private var restoreTasks: [String: Task<Void, Never>] = [:]
    private var applyGeneration = 0
    private var lastAppliedKeys: Set<String> = []
    private var probedKeys: Set<String> = []
    private var pendingRotationByKey: [String: DisplayRotation] = [:]
    private var pictureInPictureWindows: [String: PictureInPictureWindowController] = [:]
    private var pictureInPictureWall: PictureInPictureWallWindowController?
    private var lastExtendedArrangementOverride: DisplayArrangementSnapshot?
    private var knownDisplayIDsByKey: [String: CGDirectDisplayID] = [:]

    var snapshots: [DisplaySnapshot] = []
    var pictureInPictureKeys: Set<String> {
        Set(pictureInPictureWindows.keys)
    }
    var isPictureInPictureWallOpen: Bool {
        pictureInPictureWall != nil
    }
    var speaker: SpeakerOutput?
    var speakerChoices: [SpeakerChoice] = []
    var powerStatus = PowerStatus(source: .unknown, isPresent: false, percent: nil)
    var brightnessFollow = BrightnessFollowEngine()
    private var brightnessFollowTimer: DispatchSourceTimer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var lowPowerModeObserver: NSObjectProtocol?
    var onChange: (() -> Void)?
    var launchAtLoginError: String?
    private var audioRouteObserver: HALAudioRouteObserver?
    var isAdjustingSpeakerVolume = false
    var lastLiveVolumeWrite: Date?

    var settings: GlobalSettings {
        persistence.global()
    }

    var isFollowingKeyboardBrightness: Bool {
        brightnessFollow.enabled
    }

    var canFollowKeyboardBrightness: Bool {
        BrightnessFollowPolicy.canFollow(in: snapshots)
    }

    func setFollowKeyboardBrightness(_ enabled: Bool) {
        if brightnessFollow.enabled == enabled { return }
        brightnessFollow.enabled = enabled
        if enabled {
            brightnessFollow.recapture(snapshots: snapshots)
        }
        onChange?()
    }

    @discardableResult
    func toggleFollowKeyboardBrightness() -> Bool {
        let enabled = !brightnessFollow.enabled
        setFollowKeyboardBrightness(enabled)
        return enabled
    }

    init(catalog: DisplayCataloging, persistence: PersistenceStoring) {
        self.catalog = catalog
        self.persistence = persistence
    }

    static func makeDefault() -> DisplaySessionController {
        let persistence = PersistenceStore()
        let catalog: DisplayCataloging
        if shouldUseFakeHardware {
            catalog = FakeCatalog()
        } else {
            catalog = SystemDisplayCatalog(
                persistence: persistence,
                fallbackNameProvider: { NSScreen.candelaLocalizedName(for: $0) }
            )
        }
        return DisplaySessionController(catalog: catalog, persistence: persistence)
    }

    static var shouldUseFakeHardware: Bool {
        ProcessInfo.processInfo.arguments.contains("--fake-hardware")
            || ProcessInfo.processInfo.environment["CANDELA_FAKE_HARDWARE"] == "1"
    }

    func start() {
        syncLaunchAtLoginFromSystem()
        catalog.start()
        apply(catalog.snapshots)
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await next in self.catalog.updates {
                self.apply(next)
            }
        }
        if !Self.shouldUseFakeHardware {
            hotPlugObserver = HotPlugObserver { [weak self] in
                self?.catalog.requestRescan()
            }
            audioRouteObserver = HALAudioRouteObserver { [weak self] in
                Task { @MainActor in
                    self?.handleAudioRouteChange()
                }
            }
            observeActiveSpeakerVolume()
            startPowerSourceObserver()
            startLowPowerModeObserver()
            startBrightnessFollowObserver()
        } else {
            refreshPowerStatus()
            syncBrightnessFollowFromSettings()
        }
    }

    func prepareToQuit() {
        hotPlugObserver?.invalidate()
        hotPlugObserver = nil
        audioRouteObserver?.invalidate()
        audioRouteObserver = nil
        stopPowerSourceObserver()
        stopLowPowerModeObserver()
        stopBrightnessFollowObserver()
        updatesTask?.cancel()
        updatesTask = nil
        for task in restoreTasks.values {
            task.cancel()
        }
        restoreTasks.removeAll()
        closeAllPictureInPicture()
        closePictureInPictureWall()
        catalog.stop()
        if !Self.shouldUseFakeHardware {
            for box in boxes.values {
                box.restoreSoftwareOnQuitNow()
            }
            SoftwareVolumeControl.shared.stopAll()
        }
    }

    func setBrightness(key: String, value: Double, origin: BrightnessWriteOrigin = .user) {
        let clamped = min(1, max(0, value))
        boxes[key]?.setBrightness(clamped)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].brightness.current = clamped
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastBrightness = clamped
        persistence.save(record)
        if origin == .user {
            noteBrightnessFollowWrite(key: key, value: clamped)
        }
        if origin != .follow {
            onChange?()
        }
    }

    func setVolume(key: String, value: Double) {
        applySpeakerVolume(key: key, value: value, persist: true, notify: true)
    }

    func setMuted(key: String, muted: Bool) {
        applySpeakerMute(key: key, muted: muted, persist: true, notify: true)
    }

    func setContrast(key: String, value: Double) {
        let clamped = min(1, max(0, value))
        boxes[key]?.setContrast(clamped)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].contrast.current = clamped
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastContrast = clamped
        persistence.save(record)
    }

    func setInput(key: String, source: DisplayInputSource) {
        boxes[key]?.setInput(source)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].input.current = source
            snapshots[index].input.currentCode = source.code
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastInputCode = source.code
        persistence.save(record)
    }

    func isPictureInPictureOpen(key: String) -> Bool {
        pictureInPictureWindows[key] != nil
    }

    @discardableResult
    func togglePictureInPicture(key: String) -> Bool {
        if isPictureInPictureOpen(key: key) {
            closePictureInPicture(key: key)
            return false
        }
        return openPictureInPicture(key: key)
    }

    @discardableResult
    func openPictureInPicture(key: String) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.id.persistentKey == key }) else { return false }
        guard PictureInPictureLayout.supports(kind: snapshot.kind) else { return false }
        if let existing = pictureInPictureWindows[key] {
            existing.updateTitle(snapshot.name)
            existing.window?.makeKeyAndOrderFront(nil)
            return true
        }
        let placement = persistence.record(for: key)?.pictureInPicture ?? .default
        let controller = PictureInPictureWindowController(
            key: key,
            title: snapshot.name,
            displayID: snapshot.sessionDisplayID,
            pixelWidth: snapshot.pixelWidth,
            pixelHeight: snapshot.pixelHeight,
            usePlaceholder: Self.shouldUseFakeHardware,
            placement: placement
        )
        controller.onPlacementChange = { [weak self] placement in
            self?.savePictureInPicturePlacement(key: key, placement: placement)
        }
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.pictureInPictureWindows.removeValue(forKey: key)
            self.stampPictureInPictureState()
            self.onChange?()
        }
        pictureInPictureWindows[key] = controller
        controller.showWindow(nil)
        controller.capturePlacement()
        stampPictureInPictureState()
        onChange?()
        return true
    }

    func closePictureInPicture(key: String) {
        guard let controller = pictureInPictureWindows.removeValue(forKey: key) else { return }
        controller.onClose = nil
        controller.stop()
        stampPictureInPictureState()
        onChange?()
    }

    private func closeAllPictureInPicture() {
        for controller in pictureInPictureWindows.values {
            controller.onClose = nil
            controller.stop()
        }
        pictureInPictureWindows.removeAll()
    }

    func configurePictureInPicture(
        key: String,
        mode: PictureInPictureMode? = nil,
        mirrored: Bool? = nil,
        window: PictureInPictureWindowIdentity? = nil,
        magnifierZoom: Double? = nil,
        openIfNeeded: Bool = true
    ) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.id.persistentKey == key }) else { return false }
        guard PictureInPictureLayout.supports(kind: snapshot.kind) else { return false }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        var placement = record.pictureInPicture ?? .default
        if let mode { placement.mode = mode }
        if let mirrored { placement.mirrored = mirrored }
        if window != nil || mode == .display || mode == .magnifier {
            placement.window = window
        }
        if let magnifierZoom {
            placement.magnifierZoom = PictureInPictureMagnifier.clampedZoom(magnifierZoom)
        }
        record.pictureInPicture = placement
        persistence.save(record)
        if let controller = pictureInPictureWindows[key] {
            controller.applyConfiguration(mode: mode, mirrored: mirrored, window: placement.window, magnifierZoom: magnifierZoom)
            stampPictureInPictureState()
            onChange?()
            return true
        }
        if openIfNeeded {
            return openPictureInPicture(key: key)
        }
        stampPictureInPictureState()
        onChange?()
        return true
    }

    @discardableResult
    func togglePictureInPictureWall() -> Bool {
        if isPictureInPictureWallOpen {
            closePictureInPictureWall()
            return false
        }
        return openPictureInPictureWall()
    }

    @discardableResult
    func openPictureInPictureWall() -> Bool {
        if let existing = pictureInPictureWall {
            existing.update(snapshots: snapshots)
            existing.window?.makeKeyAndOrderFront(nil)
            onChange?()
            return true
        }
        let controller = PictureInPictureWallWindowController(
            usePlaceholder: Self.shouldUseFakeHardware,
            placement: persistence.global().pictureInPictureWall ?? .default
        )
        controller.onPlacementChange = { [weak self] placement in
            self?.savePictureInPictureWallPlacement(placement)
        }
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.pictureInPictureWall = nil
            self.onChange?()
        }
        pictureInPictureWall = controller
        controller.showWindow(nil)
        controller.update(snapshots: snapshots)
        controller.capturePlacement()
        onChange?()
        return true
    }

    func closePictureInPictureWall() {
        guard let controller = pictureInPictureWall else { return }
        pictureInPictureWall = nil
        controller.onClose = nil
        controller.stop()
        onChange?()
    }

    func reloadLocalizedChrome() {
        for controller in pictureInPictureWindows.values {
            controller.reloadLocalizedChrome()
        }
        pictureInPictureWall?.reloadLocalizedChrome()
    }

    private func savePictureInPictureWallPlacement(_ placement: PictureInPicturePlacement) {
        var next = settings
        next.pictureInPictureWall = placement
        persistence.saveGlobal(next)
    }

    func setRotation(key: String, rotation: DisplayRotation) {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return }
        guard !snapshots[index].isBuiltin, snapshots[index].rotation.supportsRotation else { return }
        let displayID = snapshots[index].sessionDisplayID
        if !Self.shouldUseFakeHardware {
            guard DisplayRotationControl.set(rotation, displayID: displayID) else { return }
        }
        pendingRotationByKey[key] = rotation
        snapshots[index].rotation.current = rotation
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastRotationDegrees = rotation.degrees
        persistence.save(record)
        onChange?()
    }

    @discardableResult
    func renameDisplay(key: String, customName: String?) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else {
            return false
        }
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.customName = (trimmed?.isEmpty == false) ? trimmed : nil
        persistence.save(record)
        snapshots[index].name = DisplayNameResolver.displayName(
            hardwareName: snapshots[index].hardwareName,
            customName: record.customName
        )
        onChange?()
        return true
    }

    func applyPreset(_ preset: BrightnessPreset, key: String? = nil) {
        let targets: [String]
        if let key {
            targets = [key]
        } else {
            targets = snapshots.compactMap { snapshot in
                snapshot.kind == .virtualUnsupported ? nil : snapshot.id.persistentKey
            }
        }
        for target in targets {
            guard let snapshot = snapshots.first(where: { $0.id.persistentKey == target }) else { continue }
            if snapshot.brightness.showsBrightnessSlider {
                setBrightness(key: target, value: preset.value, origin: .explicit)
            }
        }
        brightnessFollow.recapture(snapshots: snapshots)
        onChange?()
    }

    var isMirroringBuiltIn: Bool {
        snapshots.contains(where: \.isMirroringBuiltIn)
            || DisplayArrangementPlanning.kind(for: liveMirrorTargets()) == .builtin
    }

    var canToggleBuiltInMirror: Bool {
        switch DisplayArrangementPlanning.availability(
            targets: liveMirrorTargets(),
            savedArrangement: savedExtendedArrangement
        ) {
        case .unavailable:
            return false
        case .available, .mirroringBuiltIn:
            return true
        }
    }

    private var savedExtendedArrangement: DisplayArrangementSnapshot? {
        lastExtendedArrangementOverride ?? settings.lastExtendedArrangement
    }

    @discardableResult
    func toggleBuiltInMirror() -> Bool {
        if isMirroringBuiltIn {
            return restoreExtendedArrangement()
        }
        return mirrorToBuiltIn()
    }

    @discardableResult
    func mirrorToBuiltIn() -> Bool {
        let targets = liveMirrorTargets()
        guard DisplayArrangementPlanning.canMirrorToBuiltIn(targets: targets) else { return false }
        if DisplayArrangementPlanning.kind(for: targets) != .builtin {
            rememberExtendedArrangement(from: targets)
        }
        if Self.shouldUseFakeHardware {
            applyFakeMirrorState(isMirroring: true)
            return true
        }
        guard DisplayArrangementControl.mirrorToBuiltIn(keysByDisplayID: liveKeysByDisplayID()) else {
            return false
        }
        applyOptimisticMirrorState(isMirroring: true)
        catalog.requestRescan()
        return true
    }

    @discardableResult
    func restoreExtendedArrangement() -> Bool {
        guard let saved = savedExtendedArrangement else { return false }
        if Self.shouldUseFakeHardware {
            applyFakeMirrorState(isMirroring: false)
            return true
        }
        guard DisplayArrangementControl.restore(saved, keysByDisplayID: liveKeysByDisplayID()) else {
            return false
        }
        applyOptimisticMirrorState(isMirroring: false)
        catalog.requestRescan()
        return true
    }

    func matchAll(to key: String) {
        guard let source = snapshots.first(where: { $0.id.persistentKey == key }) else { return }
        for snapshot in snapshots where snapshot.id.persistentKey != key && snapshot.kind != .virtualUnsupported {
            if snapshot.brightness.showsBrightnessSlider && source.brightness.showsBrightnessSlider {
                setBrightness(key: snapshot.id.persistentKey, value: source.brightness.current, origin: .explicit)
            }
            if snapshot.volume.supportsVolume && source.volume.supportsVolume {
                setVolume(key: snapshot.id.persistentKey, value: source.volume.current)
                if snapshot.volume.supportsMute {
                    setMuted(key: snapshot.id.persistentKey, muted: source.volume.isMuted)
                }
            }
            if snapshot.contrast.supportsContrast && source.contrast.supportsContrast {
                setContrast(key: snapshot.id.persistentKey, value: source.contrast.current)
            }
        }
        brightnessFollow.recapture(snapshots: snapshots)
        onChange?()
    }

    var scenes: [DisplayScene] {
        persistence.allScenes().sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func scene(matching query: String) -> DisplayScene? {
        DisplaySceneQuery.resolve(query, in: persistence.allScenes())
    }

    @discardableResult
    func applyScene(_ query: String) -> DisplayScene? {
        guard let scene = scene(matching: query) else { return nil }
        let plan = DisplayScenePlanner.plan(
            scene: scene,
            snapshots: snapshots,
            aliases: persistence.allAliases()
        )
        for command in plan.commands {
            apply(command)
        }
        applySpeaker(from: scene, commands: plan.commands)
        reconcileAppliedScene(plan)
        refreshSpeaker()
        brightnessFollow.recapture(snapshots: snapshots)
        onChange?()
        return scene
    }

    @discardableResult
    func saveScene(named rawName: String) -> DisplayScene? {
        let name = DisplaySceneName.normalized(rawName)
        guard !name.isEmpty else { return nil }
        var scenes = persistence.allScenes()
        let captured = DisplaySceneCapture.scene(name: name, from: snapshots, speaker: speaker)
        guard !captured.targets.isEmpty else { return nil }
        if let index = scenes.firstIndex(where: { DisplaySceneName.slug($0.name) == DisplaySceneName.slug(name) }) {
            scenes[index].name = name
            scenes[index].targets = captured.targets
            scenes[index].speakerUID = captured.speakerUID
            scenes[index].speakerVolume = captured.speakerVolume
            scenes[index].speakerMuted = captured.speakerMuted
            scenes[index].updatedAt = Date()
            persistence.saveScenes(scenes)
            onChange?()
            return scenes[index]
        }
        scenes.append(captured)
        persistence.saveScenes(scenes)
        onChange?()
        return captured
    }

    @discardableResult
    func renameScene(_ query: String, to rawName: String) -> DisplayScene? {
        let name = DisplaySceneName.normalized(rawName)
        guard !name.isEmpty else { return nil }
        guard let current = scene(matching: query) else { return nil }
        var scenes = persistence.allScenes()
        guard let index = scenes.firstIndex(where: { $0.id == current.id }) else { return nil }
        scenes[index].name = name
        scenes[index].updatedAt = Date()
        persistence.saveScenes(scenes)
        onChange?()
        return scenes[index]
    }

    @discardableResult
    func deleteScene(_ query: String) -> Bool {
        guard let current = scene(matching: query) else { return false }
        var scenes = persistence.allScenes()
        guard let index = scenes.firstIndex(where: { $0.id == current.id }) else { return false }
        scenes.remove(at: index)
        persistence.saveScenes(scenes)
        onChange?()
        return true
    }

    private func reconcileAppliedScene(_ plan: DisplaySceneApplication) {
        for command in plan.commands {
            guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == command.persistentKey }) else {
                continue
            }
            if let brightness = command.brightness {
                snapshots[index].brightness.current = brightness
            }
            if let volume = command.volume {
                snapshots[index].volume.current = volume
            }
            if let muted = command.muted {
                snapshots[index].volume.isMuted = muted
            }
            if let contrast = command.contrast {
                snapshots[index].contrast.current = contrast
            }
            if let input = command.input {
                snapshots[index].input.current = input
                snapshots[index].input.currentCode = input.code
            }
            if let rotation = command.rotation {
                snapshots[index].rotation.current = rotation
            }
            if let pictureInPicture = command.pictureInPicture {
                snapshots[index].pictureInPictureActive = pictureInPicture
            }
        }
    }

    private func applySpeaker(from scene: DisplayScene, commands: [DisplaySceneCommand]) {
        guard let restore = DisplaySceneSpeakerRestore.resolve(scene: scene, speaker: speaker, commands: commands) else {
            return
        }
        if let uid = restore.uid, speaker?.uid != uid {
            _ = setDefaultSpeaker(uid: uid)
        }
        if let volume = restore.volume {
            setSpeakerVolume(volume)
        }
        if let muted = restore.muted {
            setSpeakerMuted(muted)
        }
    }

    private func apply(_ command: DisplaySceneCommand) {
        if let brightness = command.brightness {
            setBrightness(key: command.persistentKey, value: brightness, origin: .explicit)
        }
        if let volume = command.volume {
            setVolume(key: command.persistentKey, value: volume)
        }
        if let muted = command.muted {
            setMuted(key: command.persistentKey, muted: muted)
        }
        if let contrast = command.contrast {
            setContrast(key: command.persistentKey, value: contrast)
        }
        if let input = command.input {
            setInput(key: command.persistentKey, source: input)
        }
        if let rotation = command.rotation {
            setRotation(key: command.persistentKey, rotation: rotation)
        }
        if let pictureInPicture = command.pictureInPicture {
            if pictureInPicture {
                _ = openPictureInPicture(key: command.persistentKey)
            } else {
                closePictureInPicture(key: command.persistentKey)
            }
        }
    }

    func applyLaunchAtLogin(_ enabled: Bool) -> String? {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        #endif
        return enabled ? localizedText("Launch at Login requires macOS 13 or later.") : nil
    }

    func syncLaunchAtLoginFromSystem() {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            var next = settings
            next.launchAtLogin = SMAppService.mainApp.status == .enabled
            if next != settings {
                persistence.saveGlobal(next)
            }
        }
        #endif
    }

    func display(matching query: String) -> DisplaySnapshot? {
        DisplayQuery.resolve(query, in: snapshots)
    }

    func handleControl(_ request: ControlRequest) -> ControlResponse {
        ControlRouter.apply(request, backend: ControlBackend(
            snapshots: { self.snapshots },
            setBrightness: { self.setBrightness(key: $0, value: $1) },
            setVolume: { self.setVolume(key: $0, value: $1) },
            setMuted: { self.setMuted(key: $0, muted: $1) },
            setContrast: { self.setContrast(key: $0, value: $1) },
            setInput: { self.setInput(key: $0, source: $1) },
            setRotation: { self.setRotation(key: $0, rotation: $1) },
            setPictureInPicture: { key, enabled in
                if enabled {
                    return self.openPictureInPicture(key: key)
                }
                self.closePictureInPicture(key: key)
                return true
            },
            configurePictureInPicture: { key, mode, mirrored, window, zoom in
                self.configurePictureInPicture(
                    key: key,
                    mode: mode,
                    mirrored: mirrored,
                    window: window,
                    magnifierZoom: zoom
                )
            },
            setPictureInPictureWall: { enabled in
                if enabled {
                    return self.openPictureInPictureWall()
                }
                self.closePictureInPictureWall()
                return true
            },
            isPictureInPictureWallOpen: { self.isPictureInPictureWallOpen },
            rename: { self.renameDisplay(key: $0, customName: $1) },
            applyPreset: { self.applyPreset($0, key: $1) },
            matchAll: { self.matchAll(to: $0) },
            toggleBuiltInMirror: { self.toggleBuiltInMirror() },
            isMirroringBuiltIn: { self.isMirroringBuiltIn },
            scenes: { self.scenes },
            applyScene: { self.applyScene($0) },
            saveScene: { self.saveScene(named: $0) },
            renameScene: { self.renameScene($0, to: $1) },
            deleteScene: { self.deleteScene($0) },
            followKeyboardBrightness: { self.isFollowingKeyboardBrightness },
            setFollowKeyboardBrightness: { self.setFollowKeyboardBrightness($0) },
            dump: { self.debugDump(redact: $0) }
        ))
    }

    func markPanelOpenedOnce() {
        var next = settings
        next.hasOpenedPanelOnce = true
        persistence.saveGlobal(next)
    }

    func saveSettings(_ settings: GlobalSettings) {
        var next = settings
        if next.launchAtLogin != persistence.global().launchAtLogin {
            if let error = applyLaunchAtLogin(next.launchAtLogin) {
                next.launchAtLogin = persistence.global().launchAtLogin
                launchAtLoginError = error
            } else {
                launchAtLoginError = nil
            }
        }
        persistence.saveGlobal(next)
        onChange?()
        if !Self.shouldUseFakeHardware {
            reprobeAll()
        }
    }

    func debugDump(redact: Bool) -> String {
        var lines: [String] = [
            "Candela debug dump",
            "fakeHardware=\(Self.shouldUseFakeHardware)",
            "displays=\(snapshots.count)",
            "scenes=\(scenes.count)",
            "followKeyboard=\(isFollowingKeyboardBrightness)",
        ]
        for snapshot in snapshots {
            var key = snapshot.id.persistentKey
            if redact {
                key = key.replacingOccurrences(
                    of: #"s[0-9A-Fa-f]{8}"#,
                    with: "s********",
                    options: .regularExpression
                )
            }
            lines.append(
                "\(snapshot.name) key=\(key) kind=\(snapshot.kind.rawValue) conn=\(snapshot.connection.rawValue) mode=\(DisplayPresentation.modeTitle(for: snapshot) ?? "-") \(DisplayPresentation.refreshTitle(for: snapshot) ?? "") br=\(snapshot.brightness.backend.rawValue) vol=\(snapshot.volume.backend.rawValue)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private func liveKeysByDisplayID() -> [CGDirectDisplayID: String] {
        var keys: [CGDirectDisplayID: String] = [:]
        for (key, id) in knownDisplayIDsByKey where id != 0 {
            keys[id] = key
        }
        for snapshot in snapshots {
            keys[snapshot.sessionDisplayID] = snapshot.id.persistentKey
        }
        return keys
    }

    private func liveMirrorTargets() -> [DisplayMirrorTarget] {
        if Self.shouldUseFakeHardware {
            return snapshots.map { snapshot in
                DisplayMirrorTarget(
                    displayID: snapshot.sessionDisplayID,
                    persistentKey: snapshot.id.persistentKey,
                    isBuiltin: snapshot.isBuiltin,
                    isVirtual: snapshot.kind == .virtualUnsupported,
                    origin: .zero,
                    pixelWidth: snapshot.pixelWidth,
                    pixelHeight: snapshot.pixelHeight,
                    refreshHz: snapshot.refreshHz,
                    isMain: snapshot.isMain,
                    mirrorsDisplayID: snapshot.isMirroringBuiltIn && !snapshot.isBuiltin
                        ? (snapshots.first(where: \.isBuiltin)?.sessionDisplayID ?? 0)
                        : 0
                )
            }
        }
        let visible = snapshots.map { snapshot in
            DisplayMirrorTarget(
                displayID: snapshot.sessionDisplayID,
                persistentKey: snapshot.id.persistentKey,
                isBuiltin: snapshot.isBuiltin,
                isVirtual: snapshot.kind == .virtualUnsupported,
                origin: .zero,
                pixelWidth: snapshot.pixelWidth,
                pixelHeight: snapshot.pixelHeight,
                refreshHz: snapshot.refreshHz,
                isMain: snapshot.isMain
            )
        }
        let hardware = DisplayArrangementControl.currentTargets(keysByDisplayID: liveKeysByDisplayID())
        if hardware.isEmpty {
            return visible
        }
        var merged = hardware
        // Keep catalog-only identities such as Sidecar that CoreGraphics still lists.
        let hardwareIDs = Set(hardware.map(\.displayID))
        for extra in visible where !hardwareIDs.contains(extra.displayID) {
            merged.append(extra)
        }
        return merged
    }

    private func rememberExtendedArrangement(from targets: [DisplayMirrorTarget]) {
        let snapshot = DisplayArrangementPlanning.capture(
            targets: targets,
            keysByDisplayID: liveKeysByDisplayID()
        )
        guard snapshot.slots.count > 1 else { return }
        lastExtendedArrangementOverride = snapshot
        var next = settings
        next.lastExtendedArrangement = snapshot
        persistence.saveGlobal(next)
    }

    private func applyFakeMirrorState(isMirroring: Bool) {
        for index in snapshots.indices {
            snapshots[index].isMirroringBuiltIn = isMirroring
            snapshots[index].canMirrorBuiltIn = true
        }
        onChange?()
    }

    private func applyOptimisticMirrorState(isMirroring: Bool) {
        for index in snapshots.indices {
            snapshots[index].isMirroringBuiltIn = isMirroring
            snapshots[index].canMirrorBuiltIn = true
        }
        onChange?()
    }

    private func apply(_ next: [DisplaySnapshot]) {
        applyGeneration += 1
        let generation = applyGeneration
        let fake = Self.shouldUseFakeHardware
        let nextKeys = Set(next.map(\.id.persistentKey))

        for (key, box) in boxes where !nextKeys.contains(key) {
            restoreTasks[key]?.cancel()
            restoreTasks[key] = nil
            if !fake {
                if let uid = snapshots.first(where: { $0.id.persistentKey == key })?.volume.audioDeviceUID {
                    SoftwareVolumeControl.shared.stop(uid: uid)
                }
                box.restoreSoftwareOnQuitNow()
            }
        }

        var kept: [String: DisplayIOBox] = [:]
        var work: [(DisplaySnapshot, DisplayIOBox)] = []
        for snapshot in next {
            let key = snapshot.id.persistentKey
            if let existing = boxes[key] {
                existing.sessionDisplayID = snapshot.sessionDisplayID
                kept[key] = existing
                work.append((snapshot, existing))
            } else {
                let box = DisplayIOBox(snapshot: snapshot, enablesHardware: !fake)
                bindLiveFailure(box, key: key, isBuiltin: snapshot.isBuiltin)
                kept[key] = box
                work.append((snapshot, box))
            }
        }
        boxes = kept
        snapshots = preserveProbedState(next)
        for snapshot in snapshots {
            knownDisplayIDsByKey[snapshot.id.persistentKey] = snapshot.sessionDisplayID
        }
        refreshRotationSupport()
        syncPictureInPictureWindows()
        stampPictureInPictureState()
        stampMirrorState()
        refreshBrightnessFollowOffsets()
        lastAppliedKeys = nextKeys
        probedKeys = probedKeys.intersection(nextKeys)
        pendingRotationByKey = pendingRotationByKey.filter { nextKeys.contains($0.key) }
        refreshAudioBindings()
        syncSoftwareVolumeSessions()
        onChange?()

        Task {
            if fake { return }
            var freshlyProbed: [String] = []
            for (snapshot, box) in work {
                guard generation == self.applyGeneration else { return }
                let key = snapshot.id.persistentKey
                if shouldSkipFullCapabilityProbe(key: key, probedKeys: self.probedKeys) {
                    // Rotation/mode reconfigs keep the same identity. Recapture
                    // gamma only; a full DDC/DS probe is what snaps rotation back.
                    await box.recreateHandles(sessionDisplayID: snapshot.sessionDisplayID)
                    continue
                }
                let context = self.makeProbeContext(for: snapshot)
                await box.recreateHandles(sessionDisplayID: snapshot.sessionDisplayID)
                let caps = await box.probeBrightness(kind: snapshot.kind, context: context)
                guard generation == self.applyGeneration else { return }
                self.mergeBrightness(key: key, capabilities: caps, isBuiltin: snapshot.isBuiltin)
                self.probedKeys.insert(key)
                freshlyProbed.append(key)
                box.useDDCMute = self.persistence.record(for: key)?.useDDCMute ?? false
                let volumeCaps = await box.probeDDCVolume()
                guard generation == self.applyGeneration else { return }
                self.mergeVolume(key: key, capabilities: volumeCaps)
                let extras = await box.probeDDCExtras()
                guard generation == self.applyGeneration else { return }
                self.mergeExtras(key: key, contrast: extras.0, input: extras.1)
            }
            guard generation == self.applyGeneration else { return }
            if !freshlyProbed.isEmpty {
                self.refreshAudioBindings()
                self.syncSoftwareVolumeSessions()
                self.onChange?()
                // Startup applies the catalog twice with the same identities.
                // Restore from the keys we just probed, not from lastAppliedKeys.
                self.scheduleRestores(
                    for: next.filter { freshlyProbed.contains($0.id.persistentKey) },
                    previousKeys: []
                )
            }
        }
    }

    private func stampMirrorState() {
        let availability = DisplayArrangementPlanning.availability(
            targets: liveMirrorTargets(),
            savedArrangement: savedExtendedArrangement
        )
        let mirroring = availability == .mirroringBuiltIn
        let canToggle = availability != .unavailable
        for index in snapshots.indices {
            snapshots[index].isMirroringBuiltIn = mirroring
            snapshots[index].canMirrorBuiltIn = canToggle
        }
    }

    private func stampPictureInPictureState() {
        for index in snapshots.indices {
            let key = snapshots[index].id.persistentKey
            snapshots[index].pictureInPictureActive = pictureInPictureWindows[key] != nil
            if let controller = pictureInPictureWindows[key] {
                let placement = controller.currentPlacement
                snapshots[index].pictureInPictureMode = placement.mode
                snapshots[index].pictureInPictureMirrored = placement.mirrored
                snapshots[index].pictureInPictureWindow = placement.window
            } else if let placement = persistence.record(for: key)?.pictureInPicture {
                snapshots[index].pictureInPictureMode = placement.mode
                snapshots[index].pictureInPictureMirrored = placement.mirrored
                snapshots[index].pictureInPictureWindow = placement.window
            }
        }
    }

    private func syncPictureInPictureWindows() {
        let live = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id.persistentKey, $0) })
        for key in Array(pictureInPictureWindows.keys) {
            guard let snapshot = live[key], PictureInPictureLayout.supports(kind: snapshot.kind) else {
                closePictureInPicture(key: key)
                continue
            }
            pictureInPictureWindows[key]?.updateTitle(snapshot.name)
            pictureInPictureWindows[key]?.updateSourceDisplay(snapshot.sessionDisplayID)
            pictureInPictureWindows[key]?.updateSourcePixels(width: snapshot.pixelWidth, height: snapshot.pixelHeight)
        }
        pictureInPictureWall?.update(snapshots: snapshots)
    }

    private func savePictureInPicturePlacement(key: String, placement: PictureInPicturePlacement) {
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.pictureInPicture = placement
        persistence.save(record)
    }

    private func refreshRotationSupport() {
        guard !Self.shouldUseFakeHardware else { return }
        for index in snapshots.indices {
            let key = snapshots[index].id.persistentKey
            let displayID = snapshots[index].sessionDisplayID
            let hardware = DisplayRotationControl.current(for: displayID)
            if pendingRotationByKey[key] == hardware {
                pendingRotationByKey.removeValue(forKey: key)
            }
            let current = pendingRotationByKey[key] ?? hardware
            let supports = !snapshots[index].isBuiltin
                && snapshots[index].kind != .virtualUnsupported
                && DisplayRotationControl.canRotate(displayID)
            snapshots[index].rotation = supports ? .supported(current) : .unsupported
        }
    }

    private func preserveProbedState(_ next: [DisplaySnapshot]) -> [DisplaySnapshot] {
        let previous = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id.persistentKey, $0) })
        return next.map { snapshot in
            var merged = snapshot
            let record = persistence.record(for: snapshot.id.persistentKey)
            merged.name = DisplayNameResolver.displayName(
                hardwareName: snapshot.hardwareName,
                customName: record?.customName
            )
            guard let old = previous[snapshot.id.persistentKey] else { return merged }
            merged.brightness = old.brightness
            if old.brightness.backend == .none, old.brightness.current == 1, snapshot.brightness.current != 1 {
                merged.brightness.current = snapshot.brightness.current
            }
            merged.volume = old.volume
            merged.contrast = old.contrast
            merged.input = old.input
            if snapshot.isBuiltin || snapshot.kind == .virtualUnsupported {
                merged.rotation = .unsupported
            } else if let pending = pendingRotationByKey[snapshot.id.persistentKey] {
                merged.rotation = .supported(pending)
            } else if snapshot.rotation.supportsRotation {
                merged.rotation = snapshot.rotation
            } else {
                merged.rotation = old.rotation
            }
            if old.kind == .appleExternal {
                merged.kind = .appleExternal
            }
            return merged
        }
    }

    private func bindLiveFailure(_ box: DisplayIOBox, key: String, isBuiltin: Bool) {
        box.onBrightnessCapabilitiesChange = { [weak self] caps in
            Task { @MainActor in
                self?.mergeBrightness(key: key, capabilities: caps, isBuiltin: isBuiltin)
            }
        }
    }

    private func makeProbeContext(for snapshot: DisplaySnapshot) -> BrightnessProbeContext {
        let key = snapshot.id.persistentKey
        let record = persistence.record(for: key)
        let global = persistence.global()
        let debugForce = UserDefaults.standard.bool(forKey: "debug.forceDDC.\(key)")
        return BrightnessProbeContext(
            vendorID: snapshot.id.fields.inputs.vendorID,
            isBuiltin: snapshot.isBuiltin,
            softwareDimmingEnabled: global.softwareDimmingEnabled,
            softwareDimmingDisabled: record?.softwareDimmingDisabled ?? false,
            allowDimToBlack: global.allowDimToBlack,
            lastBrightness: record?.lastBrightness,
            restoreOnReconnect: global.restoreOnReconnect,
            forceDDC: (record?.forceDDC ?? false) || debugForce
        )
    }

    func applyLiveVolume(_ snapshot: DisplaySnapshot) {
        guard let uid = snapshot.volume.audioDeviceUID else { return }
        switch snapshot.volume.backend {
        case .coreAudio:
            HALVolumeControl.setVolume(uid: uid, value: snapshot.volume.current)
            if snapshot.volume.supportsMute {
                HALVolumeControl.setMuted(uid: uid, muted: snapshot.volume.isMuted)
            }
        case .software:
            SoftwareVolumeControl.shared.apply(
                uid: uid,
                volume: snapshot.volume.current,
                muted: snapshot.volume.isMuted
            )
        case .ddc, .none:
            break
        }
    }

    private func syncSoftwareVolumeSessions() {
        guard !Self.shouldUseFakeHardware else { return }
        let defaultUID = HALDeviceEnumerator.defaultOutputUID()
        let uids = Set(snapshots.compactMap { snapshot -> String? in
            guard snapshot.volume.backend == .software,
                  let uid = snapshot.volume.audioDeviceUID,
                  uid == defaultUID
            else { return nil }
            return uid
        })
        SoftwareVolumeControl.shared.retain(uids: uids)
        for snapshot in snapshots where snapshot.volume.backend == .software {
            guard snapshot.volume.audioDeviceUID == defaultUID else { continue }
            applyLiveVolume(snapshot)
        }
    }

    private func mergeVolume(key: String, capabilities: VolumeCapabilities) {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return }
        var next = VolumeResolution.preferringExistingHAL(
            existing: snapshots[index].volume,
            probed: capabilities
        )
        let record = persistence.record(for: key)
        if let last = record?.lastVolume,
           next.supportsVolume,
           abs(next.current - last) > 0.02,
           abs(snapshots[index].volume.current - last) <= 0.02
        {
            next.current = last
        }
        if let lastMuted = record?.lastMuted,
           (next.supportsMute || next.supportsVolume),
           next.isMuted != lastMuted,
           snapshots[index].volume.isMuted == lastMuted
        {
            next.isMuted = lastMuted
        }
        if next.supportsVolume {
            snapshots[index].volume = next
        } else if snapshots[index].volume.supportsVolume {
            return
        } else {
            snapshots[index].volume = next
        }
        refreshSpeaker()
        onChange?()
    }

    private func mergeExtras(key: String, contrast: ContrastCapabilities, input: InputCapabilities) {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return }
        var nextContrast = contrast
        var nextInput = input
        let record = persistence.record(for: key)
        if let last = record?.lastContrast,
           nextContrast.supportsContrast,
           abs(nextContrast.current - last) > 0.02,
           abs(snapshots[index].contrast.current - last) <= 0.02
        {
            nextContrast.current = last
        }
        if let lastCode = record?.lastInputCode,
           nextInput.supportsInputSelect,
           nextInput.currentCode != lastCode,
           snapshots[index].input.currentCode == lastCode || snapshots[index].input.current?.code == lastCode
        {
            nextInput.currentCode = lastCode
            nextInput.current = DisplayInputSource.from(code: lastCode)
        }
        snapshots[index].contrast = nextContrast
        snapshots[index].input = nextInput
        onChange?()
    }

    private func mergeBrightness(key: String, capabilities: BrightnessCapabilities, isBuiltin: Bool) {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return }
        var next = capabilities
        if let last = persistence.record(for: key)?.lastBrightness,
           abs(next.current - last) > 0.02,
           abs(snapshots[index].brightness.current - last) <= 0.02
        {
            next.current = last
        }
        snapshots[index].brightness = next
        if next.backend == .displayServices && !isBuiltin {
            snapshots[index].kind = .appleExternal
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.brightnessBackend = next.backend
        persistence.save(record)
        onChange?()
    }

    private func scheduleRestores(for snapshots: [DisplaySnapshot], previousKeys: Set<String> = []) {
        let restore = settings.restoreOnReconnect
        let attached = newlyAttachedDisplayKeys(
            previous: previousKeys,
            next: Set(snapshots.map(\.id.persistentKey))
        )
        for snapshot in snapshots {
            let key = snapshot.id.persistentKey
            restoreTasks[key]?.cancel()
            let record = persistence.record(for: key)
            guard restore, record != nil, attached.contains(key) else {
                restoreTasks[key] = nil
                continue
            }
            restoreTasks[key] = Task { [weak self] in
                let delay = UInt64(BrightnessTiming.restoreDelayAfterAttachMilliseconds) * 1_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, !Task.isCancelled, let record = self.persistence.record(for: key) else { return }
                    if let last = record.lastBrightness {
                        self.setBrightness(key: key, value: last, origin: .explicit)
                    }
                    if let last = record.lastVolume,
                       let snapshot = self.snapshots.first(where: { $0.id.persistentKey == key }),
                       snapshot.volume.supportsVolume
                    {
                        self.setVolume(key: key, value: last)
                    }
                    if let last = record.lastMuted,
                       let snapshot = self.snapshots.first(where: { $0.id.persistentKey == key }),
                       snapshot.volume.supportsMute || snapshot.volume.supportsVolume
                    {
                        self.setMuted(key: key, muted: last)
                    }
                    if let last = record.lastContrast {
                        self.setContrast(key: key, value: last)
                    }
                    if let code = record.lastInputCode, let source = DisplayInputSource.from(code: code) {
                        self.setInput(key: key, source: source)
                    }
                    if let degrees = record.lastRotationDegrees,
                       let rotation = DisplayRotation(rawValue: degrees),
                       let snapshot = self.snapshots.first(where: { $0.id.persistentKey == key }),
                       snapshot.rotation.supportsRotation,
                       snapshot.rotation.current != rotation
                    {
                        self.setRotation(key: key, rotation: rotation)
                    }
                    self.refreshBrightnessFollowOffsets()
                }
            }
        }
    }

    func handleAudioRouteChange() {
        if VolumeInteractionPolicy.shouldIgnoreHALEcho(
            isAdjusting: isAdjustingSpeakerVolume,
            lastWrite: lastLiveVolumeWrite
        ) {
            return
        }
        refreshAudioBindings()
        syncSoftwareVolumeSessions()
        onChange?()
    }

    func sampleLiveSpeakerVolume() {
        refreshSpeaker()
    }

    func observeActiveSpeakerVolume() {
        guard !Self.shouldUseFakeHardware else { return }
        audioRouteObserver?.observeVolume(uid: speaker?.uid)
        persistAdoptedSpeakerVolume()
    }

    private func persistAdoptedSpeakerVolume() {
        guard let speaker, let key = speaker.displayKey else { return }
        guard speaker.volume.supportsVolume || speaker.volume.supportsMute else { return }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        var changed = false
        if speaker.volume.supportsVolume, record.lastVolume.map({ abs($0 - speaker.volume.current) > 0.02 }) ?? true {
            record.lastVolume = speaker.volume.current
            changed = true
        }
        if speaker.volume.supportsMute || speaker.volume.supportsVolume,
           record.lastMuted != speaker.volume.isMuted
        {
            record.lastMuted = speaker.volume.isMuted
            changed = true
        }
        if changed {
            persistence.save(record)
        }
    }

    private func reprobeAll() {
        applyGeneration += 1
        let generation = applyGeneration
        let current = snapshots
        Task {
            for snapshot in current {
                guard generation == self.applyGeneration else { return }
                guard let box = self.boxes[snapshot.id.persistentKey] else { continue }
                let caps = await box.probeBrightness(kind: snapshot.kind, context: self.makeProbeContext(for: snapshot))
                guard generation == self.applyGeneration else { return }
                self.mergeBrightness(key: snapshot.id.persistentKey, capabilities: caps, isBuiltin: snapshot.isBuiltin)
            }
        }
    }

    func refreshPowerStatus() {
        let next = PowerStatusReader.current()
        guard next != powerStatus else { return }
        powerStatus = next
        onChange?()
    }

    private func startPowerSourceObserver() {
        guard powerSourceRunLoopSource == nil else {
            refreshPowerStatus()
            return
        }
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let session = Unmanaged<DisplaySessionController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                session.refreshPowerStatus()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        guard let source else {
            refreshPowerStatus()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSourceRunLoopSource = source
        refreshPowerStatus()
    }

    private func stopPowerSourceObserver() {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceRunLoopSource = nil
        }
    }

    private func startLowPowerModeObserver() {
        guard lowPowerModeObserver == nil else { return }
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPowerStatus()
        }
    }

    private func stopLowPowerModeObserver() {
        if let lowPowerModeObserver {
            NotificationCenter.default.removeObserver(lowPowerModeObserver)
            self.lowPowerModeObserver = nil
        }
    }

    private func noteBrightnessFollowWrite(key: String, value: Double) {
        guard let source = BrightnessFollowPolicy.source(in: snapshots) else { return }
        if key == source.id.persistentKey {
            brightnessFollow.noteLocalSourceWrite(value)
            guard brightnessFollow.enabled else { return }
            let commands = brightnessFollow.plan(snapshots: snapshots, sourceBrightness: value)
            for command in commands {
                setBrightness(key: command.persistentKey, value: command.brightness, origin: .follow)
            }
            return
        }
        brightnessFollow.noteFollowerWrite(
            key: key,
            brightness: value,
            sourceBrightness: source.brightness.current
        )
    }

    private func syncBrightnessFollowFromSettings() {
        if brightnessFollow.enabled {
            brightnessFollow.recapture(snapshots: snapshots)
        }
    }

    private func refreshBrightnessFollowOffsets() {
        guard let source = BrightnessFollowPolicy.source(in: snapshots) else {
            brightnessFollow.offsets = [:]
            return
        }
        brightnessFollow.offsets = BrightnessFollowPolicy.mergingOffsets(
            existing: brightnessFollow.offsets,
            snapshots: snapshots,
            sourceKey: source.id.persistentKey,
            sourceBrightness: source.brightness.current
        )
    }

    private func startBrightnessFollowObserver() {
        syncBrightnessFollowFromSettings()
        guard brightnessFollowTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + BrightnessFollowTiming.pollInterval,
            repeating: BrightnessFollowTiming.pollInterval
        )
        timer.setEventHandler { [weak self] in
            self?.pollKeyboardBrightness()
        }
        timer.resume()
        brightnessFollowTimer = timer
    }

    private func stopBrightnessFollowObserver() {
        brightnessFollowTimer?.cancel()
        brightnessFollowTimer = nil
    }

    private func pollKeyboardBrightness() {
        guard brightnessFollow.enabled else { return }
        guard let source = BrightnessFollowPolicy.source(in: snapshots) else { return }
        let live: Double?
        if Self.shouldUseFakeHardware {
            live = source.brightness.current
        } else {
            live = LiveBrightnessReader.current(displayID: source.sessionDisplayID)
        }
        guard let live else { return }
        applyLiveBuiltinBrightness(live)
    }

    func applyLiveBuiltinBrightness(_ live: Double) {
        let commands = brightnessFollow.ingestLiveSource(snapshots: snapshots, live: live)
        guard let source = BrightnessFollowPolicy.source(in: snapshots) else { return }
        var changed = false
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == source.id.persistentKey }),
           abs(snapshots[index].brightness.current - live) > BrightnessFollowTiming.changeEpsilon
        {
            snapshots[index].brightness.current = min(1, max(0, live))
            var record = persistence.record(for: source.id.persistentKey) ?? DisplayRecord(persistentKey: source.id.persistentKey)
            record.lastBrightness = snapshots[index].brightness.current
            persistence.save(record)
            changed = true
        }
        for command in commands {
            setBrightness(key: command.persistentKey, value: command.brightness, origin: .follow)
            changed = true
        }
        if changed {
            onChange?()
        }
    }
}
