import AppKit
import AudioKit
import BrightnessKit
import DisplayCore
import Foundation
import PersistenceKit
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

    var snapshots: [DisplaySnapshot] = []
    var onChange: (() -> Void)?

    var settings: GlobalSettings {
        persistence.global()
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
        }
    }

    func prepareToQuit() {
        hotPlugObserver?.invalidate()
        hotPlugObserver = nil
        updatesTask?.cancel()
        updatesTask = nil
        for task in restoreTasks.values {
            task.cancel()
        }
        restoreTasks.removeAll()
        catalog.stop()
        if !Self.shouldUseFakeHardware {
            for box in boxes.values {
                box.restoreSoftwareOnQuitNow()
            }
        }
    }

    func setBrightness(key: String, value: Double) {
        let clamped = min(1, max(0, value))
        boxes[key]?.setBrightness(clamped)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].brightness.current = clamped
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastBrightness = clamped
        persistence.save(record)
    }

    func setVolume(key: String, value: Double) {
        let clamped = min(1, max(0, value))
        boxes[key]?.setVolume(clamped)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].volume.current = clamped
            if let uid = snapshots[index].volume.audioDeviceUID {
                HALVolumeControl.setVolume(uid: uid, value: clamped)
            }
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastVolume = clamped
        persistence.save(record)
    }

    func setMuted(key: String, muted: Bool) {
        boxes[key]?.setMuted(muted)
        if let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) {
            snapshots[index].volume.isMuted = muted
            if let uid = snapshots[index].volume.audioDeviceUID {
                HALVolumeControl.setMuted(uid: uid, muted: muted)
            }
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.lastMuted = muted
        persistence.save(record)
    }

    func markPanelOpenedOnce() {
        var next = settings
        next.hasOpenedPanelOnce = true
        persistence.saveGlobal(next)
    }

    func saveSettings(_ settings: GlobalSettings) {
        persistence.saveGlobal(settings)
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
                "\(snapshot.name) key=\(key) kind=\(snapshot.kind.rawValue) conn=\(snapshot.connection.rawValue) br=\(snapshot.brightness.backend.rawValue) vol=\(snapshot.volume.backend.rawValue)"
            )
        }
        return lines.joined(separator: "\n")
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
        refreshAudioBindings()
        onChange?()

        Task {
            if fake { return }
            for (snapshot, box) in work {
                guard generation == self.applyGeneration else { return }
                let context = self.makeProbeContext(for: snapshot)
                await box.recreateHandles(sessionDisplayID: snapshot.sessionDisplayID)
                let caps = await box.probeBrightness(kind: snapshot.kind, context: context)
                guard generation == self.applyGeneration else { return }
                self.mergeBrightness(key: snapshot.id.persistentKey, capabilities: caps, isBuiltin: snapshot.isBuiltin)
                box.useDDCMute = self.persistence.record(for: snapshot.id.persistentKey)?.useDDCMute ?? false
                let volumeCaps = await box.probeDDCVolume()
                guard generation == self.applyGeneration else { return }
                self.mergeVolume(key: snapshot.id.persistentKey, capabilities: volumeCaps)
            }
            guard generation == self.applyGeneration else { return }
            self.refreshAudioBindings()
            self.onChange?()
            self.scheduleRestores(for: next)
        }
    }

    private func preserveProbedState(_ next: [DisplaySnapshot]) -> [DisplaySnapshot] {
        let previous = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id.persistentKey, $0) })
        return next.map { snapshot in
            guard let old = previous[snapshot.id.persistentKey] else { return snapshot }
            var merged = snapshot
            merged.brightness = old.brightness
            merged.brightness.current = snapshot.brightness.current
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

    private func mergeVolume(key: String, capabilities: VolumeCapabilities) {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return }
        if snapshots[index].volume.backend == .coreAudio, snapshots[index].volume.supportsVolume {
            return
        }
        snapshots[index].volume = capabilities
        onChange?()
    }

    private func mergeBrightness(key: String, capabilities: BrightnessCapabilities, isBuiltin: Bool) {
        guard let index = snapshots.firstIndex(where: { $0.id.persistentKey == key }) else { return }
        snapshots[index].brightness = capabilities
        if capabilities.backend == .displayServices && !isBuiltin {
            snapshots[index].kind = .appleExternal
        }
        var record = persistence.record(for: key) ?? DisplayRecord(persistentKey: key)
        record.brightnessBackend = capabilities.backend
        persistence.save(record)
        onChange?()
    }

    private func scheduleRestores(for snapshots: [DisplaySnapshot]) {
        let restore = settings.restoreOnReconnect
        for snapshot in snapshots {
            let key = snapshot.id.persistentKey
            restoreTasks[key]?.cancel()
            guard restore, let last = persistence.record(for: key)?.lastBrightness else {
                restoreTasks[key] = nil
                continue
            }
            restoreTasks[key] = Task { [weak self] in
                let delay = UInt64(BrightnessTiming.restoreDelayAfterAttachMilliseconds) * 1_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.setBrightness(key: key, value: last)
                }
            }
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
}
