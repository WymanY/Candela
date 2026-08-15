import Foundation

public struct DisplaySceneTarget: Codable, Equatable, Sendable {
    public var persistentKey: String
    public var brightness: Double?
    public var volume: Double?
    public var muted: Bool?
    public var contrast: Double?
    public var inputCode: UInt16?
    public var rotationDegrees: Int?
    public var pictureInPicture: Bool?

    public init(
        persistentKey: String,
        brightness: Double? = nil,
        volume: Double? = nil,
        muted: Bool? = nil,
        contrast: Double? = nil,
        inputCode: UInt16? = nil,
        rotationDegrees: Int? = nil,
        pictureInPicture: Bool? = nil
    ) {
        self.persistentKey = persistentKey
        self.brightness = brightness.map { min(1, max(0, $0)) }
        self.volume = volume.map { min(1, max(0, $0)) }
        self.muted = muted
        self.contrast = contrast.map { min(1, max(0, $0)) }
        self.inputCode = inputCode
        self.rotationDegrees = rotationDegrees
        self.pictureInPicture = pictureInPicture
    }

    public var input: DisplayInputSource? {
        inputCode.flatMap(DisplayInputSource.from(code:))
    }

    public var rotation: DisplayRotation? {
        rotationDegrees.flatMap { DisplayRotation(rawValue: $0) }
    }

    public var isEmpty: Bool {
        brightness == nil
            && volume == nil
            && muted == nil
            && contrast == nil
            && inputCode == nil
            && rotationDegrees == nil
            && pictureInPicture == nil
    }
}

public struct DisplayScene: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var targets: [DisplaySceneTarget]
    public var speakerUID: String?
    public var speakerVolume: Double?
    public var speakerMuted: Bool?

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        targets: [DisplaySceneTarget],
        speakerUID: String? = nil,
        speakerVolume: Double? = nil,
        speakerMuted: Bool? = nil
    ) {
        self.id = id
        self.name = DisplaySceneName.normalized(name)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.targets = targets
        self.speakerUID = speakerUID
        self.speakerVolume = speakerVolume.map { min(1, max(0, $0)) }
        self.speakerMuted = speakerMuted
    }

    public var displayName: String {
        name.isEmpty ? "Untitled Scene" : name
    }
}

public enum DisplaySceneName {
    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func slug(_ raw: String) -> String {
        let folded = normalized(raw)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.lowercased()
    }
}

public enum DisplaySceneCapture {
    public static func target(from snapshot: DisplaySnapshot) -> DisplaySceneTarget? {
        guard snapshot.kind != .virtualUnsupported else { return nil }
        var target = DisplaySceneTarget(persistentKey: snapshot.id.persistentKey)
        if snapshot.brightness.showsBrightnessSlider {
            target.brightness = snapshot.brightness.current
        }
        if snapshot.volume.supportsVolume {
            target.volume = snapshot.volume.current
        }
        if snapshot.volume.supportsMute || snapshot.volume.supportsVolume {
            target.muted = snapshot.volume.isMuted
        }
        if snapshot.contrast.supportsContrast {
            target.contrast = snapshot.contrast.current
        }
        if snapshot.input.supportsInputSelect {
            target.inputCode = snapshot.input.current?.code ?? snapshot.input.currentCode
        }
        if !snapshot.isBuiltin, snapshot.rotation.supportsRotation {
            target.rotationDegrees = snapshot.rotation.current.degrees
        }
        if PictureInPictureLayout.supports(kind: snapshot.kind) {
            target.pictureInPicture = snapshot.pictureInPictureActive
        }
        return target.isEmpty ? nil : target
    }

    public static func scene(
        name: String,
        from snapshots: [DisplaySnapshot],
        speaker: SpeakerOutput? = nil,
        now: Date = Date()
    ) -> DisplayScene {
        DisplayScene(
            name: name,
            createdAt: now,
            updatedAt: now,
            targets: snapshots.compactMap(target(from:)),
            speakerUID: speakerUID(from: speaker),
            speakerVolume: speakerVolume(from: speaker),
            speakerMuted: speakerMuted(from: speaker)
        )
    }

    public static func speakerUID(from speaker: SpeakerOutput?) -> String? {
        let uid = speaker?.uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return uid.isEmpty ? nil : uid
    }

    public static func speakerVolume(from speaker: SpeakerOutput?) -> Double? {
        guard let speaker, speaker.volume.supportsVolume else { return nil }
        return speaker.volume.current
    }

    public static func speakerMuted(from speaker: SpeakerOutput?) -> Bool? {
        guard let speaker, speaker.volume.supportsMute || speaker.volume.supportsVolume else { return nil }
        return speaker.volume.isMuted
    }
}

public struct DisplaySceneCommand: Equatable, Sendable {
    public var persistentKey: String
    public var brightness: Double?
    public var volume: Double?
    public var muted: Bool?
    public var contrast: Double?
    public var input: DisplayInputSource?
    public var rotation: DisplayRotation?
    public var pictureInPicture: Bool?

    public init(
        persistentKey: String,
        brightness: Double? = nil,
        volume: Double? = nil,
        muted: Bool? = nil,
        contrast: Double? = nil,
        input: DisplayInputSource? = nil,
        rotation: DisplayRotation? = nil,
        pictureInPicture: Bool? = nil
    ) {
        self.persistentKey = persistentKey
        self.brightness = brightness
        self.volume = volume
        self.muted = muted
        self.contrast = contrast
        self.input = input
        self.rotation = rotation
        self.pictureInPicture = pictureInPicture
    }

    public var isEmpty: Bool {
        brightness == nil
            && volume == nil
            && muted == nil
            && contrast == nil
            && input == nil
            && rotation == nil
            && pictureInPicture == nil
    }
}

public struct DisplaySceneApplication: Equatable, Sendable {
    public var sceneID: String
    public var sceneName: String
    public var commands: [DisplaySceneCommand]
    public var missingKeys: [String]
    public var skippedKeys: [String]

    public init(
        sceneID: String,
        sceneName: String,
        commands: [DisplaySceneCommand],
        missingKeys: [String] = [],
        skippedKeys: [String] = []
    ) {
        self.sceneID = sceneID
        self.sceneName = sceneName
        self.commands = commands
        self.missingKeys = missingKeys
        self.skippedKeys = skippedKeys
    }

    public var appliedCount: Int { commands.count }
    public var isEmpty: Bool { commands.isEmpty }
}

public enum DisplayScenePlanner {
    public static func resolveLiveKey(
        _ key: String,
        snapshots: [DisplaySnapshot],
        aliases: [String: String] = [:]
    ) -> String? {
        let resolved = resolveAlias(key, aliases: aliases)
        if snapshots.contains(where: { $0.id.persistentKey == resolved }) {
            return resolved
        }
        if snapshots.contains(where: { $0.id.persistentKey == key }) {
            return key
        }
        if let old = aliases.first(where: { $0.value == key || $0.value == resolved })?.key,
           snapshots.contains(where: { $0.id.persistentKey == old }) {
            return old
        }
        return nil
    }

    public static func plan(scene: DisplayScene, snapshots: [DisplaySnapshot]) -> DisplaySceneApplication {
        plan(scene: scene, snapshots: snapshots, aliases: [:])
    }

    public static func plan(
        scene: DisplayScene,
        snapshots: [DisplaySnapshot],
        aliases: [String: String]
    ) -> DisplaySceneApplication {
        let live = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id.persistentKey, $0) })
        var commands: [DisplaySceneCommand] = []
        var missing: [String] = []
        var skipped: [String] = []

        for target in scene.targets {
            guard let liveKey = resolveLiveKey(target.persistentKey, snapshots: snapshots, aliases: aliases),
                  let snapshot = live[liveKey] else {
                missing.append(target.persistentKey)
                continue
            }
            if snapshot.kind == .virtualUnsupported {
                skipped.append(target.persistentKey)
                continue
            }
            var command = DisplaySceneCommand(persistentKey: liveKey)
            if let brightness = target.brightness,
               snapshot.brightness.showsBrightnessSlider || snapshot.kind != .virtualUnsupported {
                command.brightness = brightness
            }
            if let volume = target.volume, snapshot.kind != .virtualUnsupported {
                command.volume = volume
            }
            if let muted = target.muted, snapshot.kind != .virtualUnsupported {
                command.muted = muted
            }
            if let contrast = target.contrast, snapshot.contrast.supportsContrast {
                command.contrast = contrast
            }
            if let input = target.input, snapshot.input.supportsInputSelect {
                command.input = input
            }
            if let rotation = target.rotation, !snapshot.isBuiltin, snapshot.rotation.supportsRotation {
                command.rotation = rotation
            }
            if let pictureInPicture = target.pictureInPicture, PictureInPictureLayout.supports(kind: snapshot.kind) {
                command.pictureInPicture = pictureInPicture
            }
            if command.isEmpty {
                skipped.append(target.persistentKey)
            } else {
                commands.append(command)
            }
        }

        return DisplaySceneApplication(
            sceneID: scene.id,
            sceneName: scene.displayName,
            commands: commands,
            missingKeys: missing,
            skippedKeys: skipped
        )
    }

    public static func matches(
        _ scene: DisplayScene,
        snapshots: [DisplaySnapshot],
        tolerance: Double = 0.02
    ) -> Bool {
        matches(scene, snapshots: snapshots, aliases: [:], speaker: nil, tolerance: tolerance)
    }

    public static func matches(
        _ scene: DisplayScene,
        snapshots: [DisplaySnapshot],
        aliases: [String: String],
        speaker: SpeakerOutput? = nil,
        tolerance: Double = 0.02
    ) -> Bool {
        let live = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id.persistentKey, $0) })
        var compared = false
        for target in scene.targets {
            guard let liveKey = resolveLiveKey(target.persistentKey, snapshots: snapshots, aliases: aliases),
                  let snapshot = live[liveKey],
                  snapshot.kind != .virtualUnsupported else {
                continue
            }
            if let brightness = target.brightness,
               snapshot.brightness.showsBrightnessSlider || snapshot.kind != .virtualUnsupported {
                compared = true
                if abs(snapshot.brightness.current - brightness) > tolerance { return false }
            }
            if let volume = target.volume, snapshot.volume.supportsVolume {
                compared = true
                if abs(snapshot.volume.current - volume) > tolerance { return false }
            }
            if let muted = target.muted, snapshot.volume.supportsMute || snapshot.volume.supportsVolume {
                compared = true
                if snapshot.volume.isMuted != muted { return false }
            }
            if let contrast = target.contrast, snapshot.contrast.supportsContrast {
                compared = true
                if abs(snapshot.contrast.current - contrast) > tolerance { return false }
            }
            if let inputCode = target.inputCode, snapshot.input.supportsInputSelect {
                compared = true
                let current = snapshot.input.current?.code ?? snapshot.input.currentCode
                if current != inputCode { return false }
            }
            if let rotation = target.rotation, !snapshot.isBuiltin, snapshot.rotation.supportsRotation {
                compared = true
                if snapshot.rotation.current != rotation { return false }
            }
            if let pictureInPicture = target.pictureInPicture, PictureInPictureLayout.supports(kind: snapshot.kind) {
                compared = true
                if snapshot.pictureInPictureActive != pictureInPicture { return false }
            }
        }
        if let speaker {
            if let expected = DisplaySceneSpeakerRestore.resolve(
                scene: scene,
                speaker: speaker,
                commands: plan(scene: scene, snapshots: snapshots, aliases: aliases).commands
            ) {
                if let volume = expected.volume, speaker.volume.supportsVolume {
                    compared = true
                    if abs(speaker.volume.current - volume) > tolerance { return false }
                }
                if let muted = expected.muted, speaker.volume.supportsMute || speaker.volume.supportsVolume {
                    compared = true
                    if speaker.volume.isMuted != muted { return false }
                }
            }
        }
        return compared
    }
}

public struct DisplaySceneSpeakerRestore: Equatable, Sendable {
    public var uid: String?
    public var volume: Double?
    public var muted: Bool?

    public init(uid: String? = nil, volume: Double? = nil, muted: Bool? = nil) {
        self.uid = uid
        self.volume = volume
        self.muted = muted
    }

    public var isEmpty: Bool {
        uid == nil && volume == nil && muted == nil
    }

    public static func resolve(
        scene: DisplayScene,
        speaker: SpeakerOutput?,
        commands: [DisplaySceneCommand]
    ) -> DisplaySceneSpeakerRestore? {
        let uid = scene.speakerUID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUID = (uid?.isEmpty == false) ? uid : nil
        var volume = scene.speakerVolume
        var muted = scene.speakerMuted

        if volume == nil || muted == nil {
            let inferred = inferredCommand(for: speaker, commands: commands)
            if volume == nil { volume = inferred?.volume }
            if muted == nil { muted = inferred?.muted }
        }

        let restore = DisplaySceneSpeakerRestore(uid: resolvedUID, volume: volume, muted: muted)
        return restore.isEmpty ? nil : restore
    }

    private static func inferredCommand(
        for speaker: SpeakerOutput?,
        commands: [DisplaySceneCommand]
    ) -> DisplaySceneCommand? {
        if let key = speaker?.displayKey {
            return commands.first(where: { $0.persistentKey == key && ($0.volume != nil || $0.muted != nil) })
        }
        let volumeCommands = commands.filter { $0.volume != nil || $0.muted != nil }
        return volumeCommands.count == 1 ? volumeCommands[0] : nil
    }
}

public enum DisplaySceneQuery {
    public static func resolve(_ query: String, in scenes: [DisplayScene]) -> DisplayScene? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exactID = scenes.first(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exactID
        }
        let slug = DisplaySceneName.slug(trimmed)
        if !slug.isEmpty {
            let slugMatches = scenes.filter { DisplaySceneName.slug($0.name) == slug }
            if slugMatches.count == 1 { return slugMatches[0] }
        }
        let named = scenes.filter { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        if named.count == 1 { return named[0] }
        return nil
    }
}
