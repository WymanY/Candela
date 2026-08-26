import CoreGraphics
import DisplayCore
import Foundation

public enum DisplayLayoutHardwareError: Error, Equatable, Sendable {
    case displayQueryFailed(Int32)
    case unresolvedDisplay(CGDirectDisplayID)
    case unresolvedPersistentKey(String)
    case ambiguousPersistentKey(String)
    case insufficientDisplays
    case mirroringActive
    case invalidDraft(DisplayLayoutValidationError)
    case displayGeometryChanged(String)
    case beginConfigurationFailed(Int32)
    case configureOriginFailed(persistentKey: String, code: Int32)
    case completeConfigurationFailed(Int32)
    case verificationFailed([String])
}

/// Applies or restores a macOS display arrangement through CoreGraphics.
public enum DisplayArrangementControl {
    public static func currentLayout(
        keysByDisplayID: [CGDirectDisplayID: String],
        namesByKey: [String: String] = [:],
        isVirtual: (CGDirectDisplayID) -> Bool = { _ in false }
    ) throws -> DisplayLayoutDraft {
        let displayIDs = try onlineDisplayIDsThrowing()
        let keys = resolvedKeys(keysByDisplayID, displayIDs: displayIDs)
        let eligibleIDs = displayIDs.filter {
            CGDisplayIsAsleep($0) == 0 && !isVirtual($0)
        }
        for id in eligibleIDs where keys[id] == nil {
            throw DisplayLayoutHardwareError.unresolvedDisplay(id)
        }

        let targets = currentTargets(
            displayIDs: displayIDs,
            keysByDisplayID: keys,
            isVirtual: isVirtual
        ).filter { target in
            !target.isVirtual && CGDisplayIsAsleep(target.displayID) == 0
        }
        switch DisplayLayoutPlanning.availability(targets: targets) {
        case .available:
            break
        case .insufficientDisplays:
            throw DisplayLayoutHardwareError.insufficientDisplays
        case .mirroring:
            throw DisplayLayoutHardwareError.mirroringActive
        }

        let slots = targets.map { target -> DisplayLayoutSlot in
            let bounds = CGDisplayBounds(target.displayID)
            return DisplayLayoutSlot(
                persistentKey: target.persistentKey,
                name: namesByKey[target.persistentKey] ?? "Display",
                origin: DisplayLayoutPoint(
                    x: Double(bounds.origin.x),
                    y: Double(bounds.origin.y)
                ),
                // CGConfigureDisplayOrigin uses the CGDisplayBounds coordinate
                // space, which can differ from physical pixel dimensions.
                size: DisplayLayoutSize(
                    width: Double(bounds.size.width),
                    height: Double(bounds.size.height)
                ),
                isMain: target.isMain,
                isBuiltin: target.isBuiltin
            )
        }
        let draft = DisplayLayoutDraft(slots: slots)
        do {
            try draft.validated()
        } catch let error as DisplayLayoutValidationError {
            throw DisplayLayoutHardwareError.invalidDraft(error)
        }
        return draft
    }

    /// Atomically applies every display origin, then re-reads and verifies the
    /// hardware arrangement. No mode, rotation, mirror, or main-display setting
    /// is changed by this operation.
    @discardableResult
    public static func applyLayout(
        _ draft: DisplayLayoutDraft,
        keysByDisplayID: [CGDirectDisplayID: String],
        namesByKey: [String: String] = [:],
        isVirtual: (CGDirectDisplayID) -> Bool = { _ in false }
    ) throws -> DisplayLayoutDraft {
        let live = try currentLayout(
            keysByDisplayID: keysByDisplayID,
            namesByKey: namesByKey,
            isVirtual: isVirtual
        )
        do {
            try draft.validated(liveDeviceKeys: live.capturedDeviceKeys)
        } catch let error as DisplayLayoutValidationError {
            throw DisplayLayoutHardwareError.invalidDraft(error)
        }

        guard draft.anchorPersistentKey == live.anchorPersistentKey else {
            throw DisplayLayoutHardwareError.invalidDraft(.missingMainDisplay)
        }
        let normalized = draft.placingMainAtZero()
        for slot in normalized.slots {
            guard let liveSlot = live.slot(for: slot.persistentKey),
                  abs(liveSlot.size.width - slot.size.width) < 0.5,
                  abs(liveSlot.size.height - slot.size.height) < 0.5
            else {
                throw DisplayLayoutHardwareError.displayGeometryChanged(slot.persistentKey)
            }
        }

        let displayIDs = try onlineDisplayIDsThrowing()
        let keys = resolvedKeys(keysByDisplayID, displayIDs: displayIDs)
        var idsByKey: [String: CGDirectDisplayID] = [:]
        for (displayID, key) in keys {
            if idsByKey[key] != nil {
                throw DisplayLayoutHardwareError.ambiguousPersistentKey(key)
            }
            idsByKey[key] = displayID
        }
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            throw DisplayLayoutHardwareError.beginConfigurationFailed(beginError.rawValue)
        }

        for slot in normalized.slots {
            guard let displayID = idsByKey[slot.persistentKey] else {
                CGCancelDisplayConfiguration(config)
                throw DisplayLayoutHardwareError.unresolvedPersistentKey(slot.persistentKey)
            }
            let error = CGConfigureDisplayOrigin(
                config,
                displayID,
                Int32(slot.origin.x.rounded()),
                Int32(slot.origin.y.rounded())
            )
            guard error == .success else {
                CGCancelDisplayConfiguration(config)
                throw DisplayLayoutHardwareError.configureOriginFailed(
                    persistentKey: slot.persistentKey,
                    code: error.rawValue
                )
            }
        }

        let completeError = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeError == .success else {
            throw DisplayLayoutHardwareError.completeConfigurationFailed(completeError.rawValue)
        }

        let verified = try currentLayout(
            keysByDisplayID: keys,
            namesByKey: namesByKey,
            isVirtual: isVirtual
        )
        var mismatches: [String] = []
        for slot in normalized.slots {
            guard let actual = verified.slot(for: slot.persistentKey),
                  abs(actual.origin.x - slot.origin.x.rounded()) < 0.5,
                  abs(actual.origin.y - slot.origin.y.rounded()) < 0.5
            else {
                mismatches.append(slot.persistentKey)
                continue
            }
        }
        guard mismatches.isEmpty else {
            throw DisplayLayoutHardwareError.verificationFailed(mismatches.sorted())
        }
        return verified
    }

    public static func currentTargets(
        keysByDisplayID: [CGDirectDisplayID: String],
        isVirtual: (CGDirectDisplayID) -> Bool = { _ in false }
    ) -> [DisplayMirrorTarget] {
        currentTargets(
            displayIDs: onlineDisplayIDs(),
            keysByDisplayID: resolvedKeys(keysByDisplayID),
            isVirtual: isVirtual
        )
    }

    /// When a display is already a mirror slave it is hidden from Candela's catalog.
    /// Fall back to vendor/product matching so restore can still find it.
    private static func resolvedKeys(
        _ keysByDisplayID: [CGDirectDisplayID: String],
        displayIDs: [CGDirectDisplayID]? = nil
    ) -> [CGDirectDisplayID: String] {
        var keys = keysByDisplayID
        for id in displayIDs ?? onlineDisplayIDs() where keys[id] == nil {
            if let existing = keys.first(where: {
                CGDisplayVendorNumber($0.key) == CGDisplayVendorNumber(id)
                    && CGDisplayModelNumber($0.key) == CGDisplayModelNumber(id)
                    && CGDisplaySerialNumber($0.key) == CGDisplaySerialNumber(id)
            }) {
                keys[id] = existing.value
            }
        }
        return keys
    }

    public static func currentTargets(
        displayIDs: [CGDirectDisplayID],
        keysByDisplayID: [CGDirectDisplayID: String],
        isVirtual: (CGDirectDisplayID) -> Bool = { _ in false }
    ) -> [DisplayMirrorTarget] {
        let keys = resolvedKeys(keysByDisplayID, displayIDs: displayIDs)
        return displayIDs.compactMap { id in
            guard let key = keys[id] else { return nil }
            let bounds = CGDisplayBounds(id)
            return DisplayMirrorTarget(
                displayID: id,
                persistentKey: key,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isVirtual: isVirtual(id),
                origin: bounds.origin,
                pixelWidth: UInt32(CGDisplayPixelsWide(id)),
                pixelHeight: UInt32(CGDisplayPixelsHigh(id)),
                refreshHz: CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0,
                isMain: CGDisplayIsMain(id) != 0,
                mirrorsDisplayID: CGDisplayMirrorsDisplay(id)
            )
        }
    }

    public static func currentKind(
        keysByDisplayID: [CGDirectDisplayID: String]
    ) -> DisplayMirrorKind {
        DisplayArrangementPlanning.kind(for: currentTargets(keysByDisplayID: keysByDisplayID))
    }

    @discardableResult
    public static func mirrorToBuiltIn(
        keysByDisplayID: [CGDirectDisplayID: String]
    ) -> Bool {
        let targets = currentTargets(keysByDisplayID: keysByDisplayID)
        guard let builtin = targets.first(where: { $0.isBuiltin && !$0.isVirtual }) else {
            return false
        }
        guard let slaves = DisplayArrangementPlanning.mirrorPlan(targets: targets) else {
            return false
        }
        return configure { config in
            for slave in slaves {
                let error = CGConfigureDisplayMirrorOfDisplay(config, slave, builtin.displayID)
                if error != .success {
                    return false
                }
            }
            return true
        }
    }

    @discardableResult
    public static func restore(
        _ snapshot: DisplayArrangementSnapshot,
        keysByDisplayID: [CGDirectDisplayID: String]
    ) -> Bool {
        let targets = currentTargets(keysByDisplayID: keysByDisplayID)
        let liveByKey = Dictionary(uniqueKeysWithValues: targets.map { ($0.persistentKey, $0) })
        let slots = DisplayArrangementPlanning.restorePlan(saved: snapshot, targets: targets)
        guard !slots.isEmpty else { return false }
        return configure { config in
            for slot in slots {
                guard let target = liveByKey[slot.persistentKey] else { continue }
                if slot.mirrorsPersistentKey == nil {
                    let disable = CGConfigureDisplayMirrorOfDisplay(config, target.displayID, kCGNullDirectDisplay)
                    if disable != .success {
                        return false
                    }
                    let origin = CGConfigureDisplayOrigin(
                        config,
                        target.displayID,
                        Int32(slot.originX.rounded()),
                        Int32(slot.originY.rounded())
                    )
                    if origin != .success {
                        return false
                    }
                } else if let masterKey = slot.mirrorsPersistentKey, let master = liveByKey[masterKey] {
                    let error = CGConfigureDisplayMirrorOfDisplay(config, target.displayID, master.displayID)
                    if error != .success {
                        return false
                    }
                }
            }
            if let main = slots.first(where: \.isMain), let target = liveByKey[main.persistentKey] {
                let error = CGConfigureDisplayOrigin(
                    config,
                    target.displayID,
                    Int32(main.originX.rounded()),
                    Int32(main.originY.rounded())
                )
                if error != .success {
                    return false
                }
            }
            return true
        }
    }

    public static func disableMirroring(for displayIDs: [CGDirectDisplayID]) -> Bool {
        configure { config in
            for id in displayIDs {
                let error = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
                if error != .success {
                    return false
                }
            }
            return true
        }
    }

    @discardableResult
    private static func configure(_ body: (CGDisplayConfigRef) -> Bool) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return false
        }
        guard body(config) else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        (try? onlineDisplayIDsThrowing()) ?? []
    }

    private static func onlineDisplayIDsThrowing() throws -> [CGDirectDisplayID] {
        var allocated: UInt32 = 64
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(allocated))
        var count: UInt32 = 0
        var error = CGGetOnlineDisplayList(allocated, &ids, &count)
        if error != .success {
            throw DisplayLayoutHardwareError.displayQueryFailed(error.rawValue)
        }
        if count > allocated {
            allocated = count
            ids = [CGDirectDisplayID](repeating: 0, count: Int(allocated))
            error = CGGetOnlineDisplayList(allocated, &ids, &count)
            if error != .success {
                throw DisplayLayoutHardwareError.displayQueryFailed(error.rawValue)
            }
        }
        return Array(ids.prefix(Int(count)))
    }
}
