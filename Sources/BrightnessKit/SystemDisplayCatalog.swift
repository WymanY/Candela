import CoreGraphics
import Dispatch
import DisplayCore
import Foundation
import os

/// Live `CGGetOnlineDisplayList` catalog. No brightness / DDC / gamma writes.
public final class SystemDisplayCatalog: DisplayCataloging {
    public static let hotPlugDebounceMilliseconds: Int = 400

    public private(set) var snapshots: [DisplaySnapshot] = []
    public let updates: AsyncStream<[DisplaySnapshot]>

    private let continuation: AsyncStream<[DisplaySnapshot]>.Continuation
    private let queue = DispatchQueue(label: "candela.catalog")
    private let persistence: PersistenceStoring
    private let fallbackNameProvider: ((CGDirectDisplayID) -> String?)?
    private let log = Logger(subsystem: "app.candela.macos", category: "discovery")

    private var debounceWork: DispatchWorkItem?
    private var running = false
    private var notificationObserver: NSObjectProtocol?
    private var previousKeysByDisplayID: [CGDirectDisplayID: String] = [:]
    private var rememberedKeysByDisplayID: [CGDirectDisplayID: String] = [:]
    private var previousSnapshots: [DisplaySnapshot] = []

    public init(
        persistence: PersistenceStoring,
        fallbackNameProvider: ((CGDirectDisplayID) -> String?)? = nil
    ) {
        self.persistence = persistence
        self.fallbackNameProvider = fallbackNameProvider
        let stream = AsyncStream<[DisplaySnapshot]>.makeStream()
        self.updates = stream.0
        self.continuation = stream.1
    }

    deinit {
        debounceWork?.cancel()
        if running {
            CGDisplayRemoveReconfigurationCallback(
                Self.reconfigurationCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    public func start() {
        let names: [CGDirectDisplayID: String]
        if Thread.isMainThread {
            names = collectScreenNames(Self.onlineDisplayIDs())
        } else {
            names = [:]
        }
        queue.sync {
            guard !self.running else { return }
            self.running = true
            self.registerObserversLocked()
            self.performRescanLocked(screenNames: names)
        }
    }

    public func stop() {
        queue.sync {
            self.stopLocked()
        }
    }

    public func requestRescan() {
        queue.async { self.scheduleRescanLocked() }
    }

    private func stopLocked() {
        debounceWork?.cancel()
        debounceWork = nil
        if running {
            CGDisplayRemoveReconfigurationCallback(
                Self.reconfigurationCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
        if running {
            continuation.finish()
        }
        running = false
    }

    private func registerObserversLocked() {
        CGDisplayRegisterReconfigurationCallback(
            Self.reconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .candelaCatalogShouldRescan,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.requestRescan()
        }
    }

    private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        if flags.contains(.beginConfigurationFlag) { return }
        guard let userInfo else { return }
        Unmanaged<SystemDisplayCatalog>.fromOpaque(userInfo).takeUnretainedValue().requestRescan()
    }

    private func scheduleRescanLocked() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runDebouncedRescan()
        }
        debounceWork = work
        queue.asyncAfter(
            deadline: .now() + .milliseconds(Self.hotPlugDebounceMilliseconds),
            execute: work
        )
    }

    private func runDebouncedRescan() {
        let ids = Self.onlineDisplayIDs()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let names = self.collectScreenNames(ids)
            self.queue.async {
                self.performRescanLocked(screenNames: names)
            }
        }
    }

    private func performRescanLocked(screenNames: [CGDirectDisplayID: String]) {
        guard running else { return }
        let online = Self.onlineDisplayIDs()
        let ids = visibleOnlineDisplayIDs(online)
        let facts = IOKitDisplaySource.facts(for: ids, screenNames: screenNames)
        let built = buildLiveCatalog(
            facts: facts,
            records: persistence.allRecords(),
            aliases: persistence.allAliases(),
            previousKeysByDisplayID: previousKeysByDisplayID,
            previousSnapshots: previousSnapshots
        )
        for record in built.copiedRecords {
            persistence.save(record)
        }
        for alias in built.keyAliases {
            persistence.alias(old: alias.oldKey, new: alias.newKey)
        }
        previousKeysByDisplayID = built.keysByDisplayID
        for (id, key) in built.keysByDisplayID {
            rememberedKeysByDisplayID[id] = key
        }
        var keysForMirror = rememberedKeysByDisplayID
        for (id, key) in built.keysByDisplayID {
            keysForMirror[id] = key
        }
        let stamped = stampMirrorState(built.snapshots, onlineIDs: online, keysByDisplayID: keysForMirror)
        previousSnapshots = stamped
        snapshots = stamped
        log.debug("rescan displays=\(stamped.count, privacy: .public)")
        let next = stamped
        DispatchQueue.main.async { [weak self] in
            self?.continuation.yield(next)
        }
    }

    private func collectScreenNames(_ ids: [CGDirectDisplayID]) -> [CGDirectDisplayID: String] {
        guard let fallbackNameProvider else { return [:] }
        var names: [CGDirectDisplayID: String] = [:]
        for id in ids {
            if let name = fallbackNameProvider(id), !name.isEmpty {
                names[id] = name
            }
        }
        return names
    }

    private func stampMirrorState(
        _ snapshots: [DisplaySnapshot],
        onlineIDs: [CGDirectDisplayID],
        keysByDisplayID: [CGDirectDisplayID: String]
    ) -> [DisplaySnapshot] {
        let targets = DisplayArrangementControl.currentTargets(
            displayIDs: onlineIDs,
            keysByDisplayID: keysByDisplayID,
            isVirtual: { id in
                snapshots.first(where: { $0.sessionDisplayID == id })?.kind == .virtualUnsupported
            }
        )
        let kind = DisplayArrangementPlanning.kind(for: targets)
        let canMirror = DisplayArrangementPlanning.canMirrorToBuiltIn(targets: targets)
        return snapshots.map { snapshot in
            var next = snapshot
            next.isMirroringBuiltIn = kind != .none
            next.canMirrorBuiltIn = canMirror || kind != .none
            return next
        }
    }

    static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var allocated: UInt32 = 64
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(allocated))
        var count: UInt32 = 0
        var error = CGGetOnlineDisplayList(allocated, &ids, &count)
        if error != .success {
            return []
        }
        if count > allocated {
            allocated = count
            ids = [CGDirectDisplayID](repeating: 0, count: Int(allocated))
            error = CGGetOnlineDisplayList(allocated, &ids, &count)
            if error != .success {
                return []
            }
        }
        return Array(ids.prefix(Int(count)))
    }
}
