import CoreGraphics
import DisplayCore
import Foundation

/// Applies or restores a macOS display arrangement through CoreGraphics.
public enum DisplayArrangementControl {
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
