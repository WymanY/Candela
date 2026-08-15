import Foundation

public enum DisplayQuery {
    public static func resolve(_ query: String, in snapshots: [DisplaySnapshot]) -> DisplaySnapshot? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        switch lowered {
        case "main", "primary":
            return snapshots.first(where: \.isMain) ?? snapshots.first
        case "builtin", "built-in", "internal", "laptop":
            return snapshots.first(where: \.isBuiltin)
        case "external":
            return snapshots.first { !$0.isBuiltin && $0.kind != .virtualUnsupported }
        default:
            break
        }

        if let exactKey = snapshots.first(where: { $0.id.persistentKey.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exactKey
        }
        if let exactName = snapshots.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exactName
        }
        if let hardware = snapshots.first(where: { $0.hardwareName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return hardware
        }

        let generic = Set(["display", "monitor", "screen", "panel"])
        if generic.contains(lowered) {
            return nil
        }
        let named = snapshots.filter {
            $0.name.lowercased().contains(lowered) || $0.hardwareName.lowercased().contains(lowered)
        }
        if named.count == 1 {
            return named[0]
        }

        if trimmed.hasPrefix("v1:") {
            return snapshots.first { $0.id.persistentKey.lowercased().contains(lowered) }
        }
        return nil
    }
}
