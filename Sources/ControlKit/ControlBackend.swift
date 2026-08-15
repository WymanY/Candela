import DisplayCore
import Foundation

public struct ControlBackend {
    public var snapshots: () -> [DisplaySnapshot]
    public var setBrightness: (String, Double) -> Void
    public var setVolume: (String, Double) -> Void
    public var setMuted: (String, Bool) -> Void
    public var setContrast: (String, Double) -> Void
    public var setInput: (String, DisplayInputSource) -> Void
    public var setRotation: (String, DisplayRotation) -> Void
    public var rename: (String, String?) -> Bool
    public var applyPreset: (BrightnessPreset, String?) -> Void
    public var matchAll: (String) -> Void
    public var dump: (Bool) -> String

    public init(
        snapshots: @escaping () -> [DisplaySnapshot],
        setBrightness: @escaping (String, Double) -> Void,
        setVolume: @escaping (String, Double) -> Void,
        setMuted: @escaping (String, Bool) -> Void,
        setContrast: @escaping (String, Double) -> Void,
        setInput: @escaping (String, DisplayInputSource) -> Void,
        setRotation: @escaping (String, DisplayRotation) -> Void,
        rename: @escaping (String, String?) -> Bool,
        applyPreset: @escaping (BrightnessPreset, String?) -> Void,
        matchAll: @escaping (String) -> Void,
        dump: @escaping (Bool) -> String
    ) {
        self.snapshots = snapshots
        self.setBrightness = setBrightness
        self.setVolume = setVolume
        self.setMuted = setMuted
        self.setContrast = setContrast
        self.setInput = setInput
        self.setRotation = setRotation
        self.rename = rename
        self.applyPreset = applyPreset
        self.matchAll = matchAll
        self.dump = dump
    }
}

public enum ControlRouter {
    public static func apply(_ request: ControlRequest, backend: ControlBackend) -> ControlResponse {
        let all = backend.snapshots()
        switch request.action {
        case .list:
            return .success(displays: all.map(ControlDisplayDTO.init(snapshot:)))
        case .dump:
            return ControlResponse(ok: true, dump: backend.dump(request.redact ?? true))
        case .get, .setBrightness, .setVolume, .setMuted, .setContrast, .setInput, .setRotation, .rename, .preset, .matchAll:
            break
        }

        let query = request.display?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved: DisplaySnapshot?
        if request.action == .preset, query.isEmpty || query.lowercased() == "all" {
            resolved = nil
        } else {
            guard !query.isEmpty else {
                return .failure("Display query required. Use a name, persistentKey, main, builtin, or external.")
            }
            guard let match = DisplayQuery.resolve(query, in: all) else {
                return .failure("No display matched '\(query)'.")
            }
            resolved = match
        }

        switch request.action {
        case .list, .dump:
            return .failure("unreachable")
        case .get:
            return .success(displays: [ControlDisplayDTO(snapshot: resolved!)])
        case .setBrightness:
            guard let value = request.value else { return .failure("Brightness value 0...1 is required.") }
            guard resolved!.brightness.showsBrightnessSlider else {
                return .failure("\(resolved!.name) has no brightness control.")
            }
            backend.setBrightness(resolved!.id.persistentKey, value)
        case .setVolume:
            guard let value = request.value else { return .failure("Volume value 0...1 is required.") }
            guard resolved!.volume.supportsVolume else {
                return .failure("\(resolved!.name) has no volume control.")
            }
            backend.setVolume(resolved!.id.persistentKey, value)
        case .setMuted:
            guard let muted = request.muted else { return .failure("muted true/false is required.") }
            guard resolved!.volume.supportsMute || resolved!.volume.supportsVolume else {
                return .failure("\(resolved!.name) has no mute control.")
            }
            backend.setMuted(resolved!.id.persistentKey, muted)
        case .setContrast:
            guard let value = request.value else { return .failure("Contrast value 0...1 is required.") }
            guard resolved!.contrast.supportsContrast else {
                return .failure("\(resolved!.name) has no contrast control.")
            }
            backend.setContrast(resolved!.id.persistentKey, value)
        case .setInput:
            guard let raw = request.input, let source = DisplayInputSource.from(query: raw) else {
                return .failure("Input must be hdmi1, hdmi2, dp, dp2, usbc, or a VCP 0x60 code.")
            }
            guard resolved!.input.supportsInputSelect else {
                return .failure("\(resolved!.name) has no DDC input select.")
            }
            backend.setInput(resolved!.id.persistentKey, source)
        case .setRotation:
            guard let raw = request.rotation, let rotation = DisplayRotation.from(query: raw) else {
                return .failure("Rotation must be 0, 90, 180, 270, landscape, or portrait.")
            }
            guard !resolved!.isBuiltin, resolved!.rotation.supportsRotation else {
                return .failure("\(resolved!.name) cannot rotate.")
            }
            backend.setRotation(resolved!.id.persistentKey, rotation)
        case .rename:
            guard backend.rename(resolved!.id.persistentKey, request.name) else {
                return .failure("Could not rename \(resolved!.name).")
            }
        case .preset:
            guard let raw = request.preset, let preset = BrightnessPreset(rawValue: raw.lowercased()) else {
                return .failure("Preset must be night, desk, or max.")
            }
            backend.applyPreset(preset, resolved?.id.persistentKey)
        case .matchAll:
            backend.matchAll(resolved!.id.persistentKey)
        }

        let latest = backend.snapshots()
        if let resolved, let current = latest.first(where: { $0.id.persistentKey == resolved.id.persistentKey }) {
            return .success(displays: [ControlDisplayDTO(snapshot: current)])
        }
        return .success(displays: latest.map(ControlDisplayDTO.init(snapshot:)))
    }
}
