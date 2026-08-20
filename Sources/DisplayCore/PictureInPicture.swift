import CoreGraphics
import Foundation

public enum PictureInPictureCorner: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center

    public var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .center: return "Center"
        }
    }
}

public struct PictureInPictureFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct PictureInPicturePlacement: Codable, Equatable, Sendable {
    public var opacity: Double
    public var clickThrough: Bool
    public var corner: PictureInPictureCorner?
    public var frame: PictureInPictureFrame?
    public var hostDisplayID: UInt32?
    public var mirrored: Bool
    public var mode: PictureInPictureMode
    public var window: PictureInPictureWindowIdentity?
    public var magnifierZoom: Double
    public var controlSource: Bool

    public init(
        opacity: Double = 1,
        clickThrough: Bool = false,
        corner: PictureInPictureCorner? = nil,
        frame: PictureInPictureFrame? = nil,
        hostDisplayID: UInt32? = nil,
        mirrored: Bool = false,
        mode: PictureInPictureMode = .display,
        window: PictureInPictureWindowIdentity? = nil,
        magnifierZoom: Double = PictureInPictureMagnifier.defaultZoom,
        controlSource: Bool = false
    ) {
        self.opacity = PictureInPictureLayout.clampedOpacity(opacity)
        self.controlSource = controlSource
        self.clickThrough = PictureInPictureInteraction.resolvedClickThrough(
            clickThrough: clickThrough,
            controlSource: controlSource
        )
        self.corner = corner
        self.frame = frame
        self.hostDisplayID = hostDisplayID
        self.mirrored = mirrored
        self.mode = mode
        self.window = window
        self.magnifierZoom = PictureInPictureMagnifier.clampedZoom(magnifierZoom)
    }

    public static let `default` = PictureInPicturePlacement()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opacity = PictureInPictureLayout.clampedOpacity(try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1)
        controlSource = try container.decodeIfPresent(Bool.self, forKey: .controlSource) ?? false
        clickThrough = PictureInPictureInteraction.resolvedClickThrough(
            clickThrough: try container.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? false,
            controlSource: controlSource
        )
        corner = try container.decodeIfPresent(PictureInPictureCorner.self, forKey: .corner)
        frame = try container.decodeIfPresent(PictureInPictureFrame.self, forKey: .frame)
        hostDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .hostDisplayID)
        mirrored = try container.decodeIfPresent(Bool.self, forKey: .mirrored) ?? false
        mode = try container.decodeIfPresent(PictureInPictureMode.self, forKey: .mode) ?? .display
        window = try container.decodeIfPresent(PictureInPictureWindowIdentity.self, forKey: .window)
        magnifierZoom = PictureInPictureMagnifier.clampedZoom(
            try container.decodeIfPresent(Double.self, forKey: .magnifierZoom) ?? PictureInPictureMagnifier.defaultZoom
        )
    }
}



public enum PictureInPictureMode: String, Codable, CaseIterable, Sendable {
    case display
    case window
    case magnifier

    public var title: String {
        switch self {
        case .display: return "Display"
        case .window: return "Window"
        case .magnifier: return "Magnifier"
        }
    }

    public static func from(query: String) -> PictureInPictureMode? {
        switch query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "display", "screen", "monitor":
            return .display
        case "window", "app":
            return .window
        case "magnifier", "loupe", "zoom":
            return .magnifier
        default:
            return nil
        }
    }
}

public struct PictureInPictureWindowIdentity: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var title: String
    public var ownerName: String

    public init(bundleIdentifier: String, title: String, ownerName: String = "") {
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayTitle: String {
        if title.isEmpty { return ownerName.isEmpty ? bundleIdentifier : ownerName }
        if ownerName.isEmpty || title.hasPrefix(ownerName) { return title }
        return "\(ownerName) - \(title)"
    }
}

public struct PictureInPictureWindowCandidate: Equatable, Sendable {
    public var windowID: UInt32
    public var bundleIdentifier: String
    public var title: String
    public var ownerName: String
    public var displayID: UInt32?
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    public var windowLayer: Int

    public init(
        windowID: UInt32,
        bundleIdentifier: String,
        title: String,
        ownerName: String,
        displayID: UInt32? = nil,
        pixelWidth: UInt32 = 0,
        pixelHeight: UInt32 = 0,
        windowLayer: Int = 0
    ) {
        self.windowID = windowID
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.ownerName = ownerName
        self.displayID = displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.windowLayer = windowLayer
    }

    public var identity: PictureInPictureWindowIdentity {
        PictureInPictureWindowIdentity(
            bundleIdentifier: bundleIdentifier,
            title: title,
            ownerName: ownerName
        )
    }
}

public enum PictureInPictureWindowMatching {
    /// Desktop backdrops and capture overlays are not useful app windows.
    public static func shouldOffer(_ candidate: PictureInPictureWindowCandidate) -> Bool {
        !isSystemBackdrop(candidate) && !isCaptureOverlay(candidate)
    }

    public static func isSystemBackdrop(_ candidate: PictureInPictureWindowCandidate) -> Bool {
        let title = normalize(candidate.title)
        let owner = normalize(candidate.ownerName)
        let bundle = normalize(candidate.bundleIdentifier)
        if title.contains("backstop") { return true }
        if owner == "windowserver" || owner == "window server" { return true }
        if bundle == "com.apple.windowserver" { return true }
        return false
    }

    /// Screen Studio's window-picker highlighter and similar HUD layers capture as a black frame.
    public static func isCaptureOverlay(_ candidate: PictureInPictureWindowCandidate) -> Bool {
        let title = normalize(candidate.title)
        if title.contains("window picker") { return true }
        if title.contains("highlighter") { return true }
        if candidate.windowLayer != 0 && title.isEmpty { return true }
        return false
    }

    public static func match(
        identity: PictureInPictureWindowIdentity,
        candidates: [PictureInPictureWindowCandidate],
        preferringDisplay displayID: UInt32? = nil
    ) -> PictureInPictureWindowCandidate? {
        let pool = sameApp(as: identity, in: scopedToDisplay(candidates, displayID: displayID))
        guard !pool.isEmpty else { return nil }
        if let exact = pool.first(where: { normalize($0.title) == normalize(identity.title) && !identity.title.isEmpty }) {
            return exact
        }
        if !identity.title.isEmpty {
            let title = normalize(identity.title)
            if let contains = pool.first(where: {
                let candidate = normalize($0.title)
                return candidate.contains(title) || title.contains(candidate) || sharesTokens(title, candidate)
            }) {
                return contains
            }
        }
        if pool.count == 1 { return pool[0] }
        return pool.first
    }

    public static func query(
        _ raw: String,
        bundleIdentifier: String? = nil,
        preferringDisplay displayID: UInt32? = nil,
        in candidates: [PictureInPictureWindowCandidate]
    ) -> PictureInPictureWindowCandidate? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundle = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var pool = candidates
        if !bundle.isEmpty {
            pool = pool.filter { $0.bundleIdentifier.compare(bundle, options: .caseInsensitive) == .orderedSame }
        }
        pool = scopedToDisplay(pool, displayID: displayID)
        if query.isEmpty {
            return preferred(pool, displayID: displayID)
        }
        let needle = normalize(query)
        let scored = pool.compactMap { candidate -> (PictureInPictureWindowCandidate, Int)? in
            let title = normalize(candidate.title)
            let owner = normalize(candidate.ownerName)
            let identifier = normalize(candidate.bundleIdentifier)
            var score = 0
            if title == needle { score += 80 }
            else if title.contains(needle) || needle.contains(title) { score += 50 }
            if owner == needle { score += 40 }
            else if owner.contains(needle) { score += 20 }
            if identifier.contains(needle) { score += 15 }
            if score == 0 { return nil }
            if let displayID, candidate.displayID == displayID { score += 5 }
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }
        return scored.first?.0
    }

    /// Prefer the display whose frame covers the most of this window.
    public static func displayIDContaining(
        _ frame: CGRect,
        displays: [(id: UInt32, bounds: CGRect)]
    ) -> UInt32? {
        let ranked = displays
            .map { item -> (id: UInt32, area: CGFloat) in
                let overlap = item.bounds.intersection(frame)
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                return (item.id, area)
            }
            .filter { $0.area > 1 }
            .sorted { $0.area > $1.area }
        if let best = ranked.first {
            return best.id
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first(where: { $0.bounds.insetBy(dx: -2, dy: -2).contains(point) })?.id
    }

    /// A display's PiP should only follow windows that currently sit on that display.
    public static func scopedToDisplay(
        _ candidates: [PictureInPictureWindowCandidate],
        displayID: UInt32?
    ) -> [PictureInPictureWindowCandidate] {
        guard let displayID else { return candidates }
        return candidates.filter { $0.displayID == displayID }
    }

    public static func preferred(
        _ candidates: [PictureInPictureWindowCandidate],
        displayID: UInt32?
    ) -> PictureInPictureWindowCandidate? {
        if let displayID, let match = candidates.first(where: { $0.displayID == displayID }) {
            return match
        }
        return candidates.first
    }

    public static func sorted(
        _ candidates: [PictureInPictureWindowCandidate],
        preferringDisplay displayID: UInt32?
    ) -> [PictureInPictureWindowCandidate] {
        candidates.sorted { lhs, rhs in
            let leftSame = displayID != nil && lhs.displayID == displayID
            let rightSame = displayID != nil && rhs.displayID == displayID
            if leftSame != rightSame { return leftSame && !rightSame }
            let owner = lhs.ownerName.localizedCaseInsensitiveCompare(rhs.ownerName)
            if owner != .orderedSame { return owner == .orderedAscending }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func sameApp(
        as identity: PictureInPictureWindowIdentity,
        in candidates: [PictureInPictureWindowCandidate]
    ) -> [PictureInPictureWindowCandidate] {
        if !identity.bundleIdentifier.isEmpty {
            let matches = candidates.filter {
                $0.bundleIdentifier.compare(identity.bundleIdentifier, options: .caseInsensitive) == .orderedSame
            }
            if !matches.isEmpty { return matches }
        }
        if !identity.ownerName.isEmpty {
            return candidates.filter {
                $0.ownerName.compare(identity.ownerName, options: .caseInsensitive) == .orderedSame
            }
        }
        return []
    }


    private static func sharesTokens(_ lhs: String, _ rhs: String) -> Bool {
        let left = tokens(in: lhs)
        let right = tokens(in: rhs)
        return !left.isEmpty && !left.isDisjoint(with: right)
    }

    private static func tokens(in raw: String) -> Set<String> {
        Set(
            raw.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

public enum PictureInPictureMirror {
    /// Scale X for a layer whose anchor is already at the center of its bounds.
    public static func centeredAffineTransform(mirrored: Bool) -> CGAffineTransform {
        CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1)
    }

    /// Flip horizontally around the center of `bounds` so the preview stays in place.
    public static func affineTransform(mirrored: Bool, bounds: CGRect) -> CGAffineTransform {
        guard mirrored, bounds.width > 1, bounds.height > 1 else { return .identity }
        return CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .scaledBy(x: -1, y: 1)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
    }
}

public enum PictureInPictureMagnifier {
    public static let defaultZoom: Double = 2
    public static let minZoom: Double = 1.5
    public static let maxZoom: Double = 4
    public static let zoomStops: [Double] = [1.5, 2, 3, 4]

    public static func clampedZoom(_ value: Double) -> Double {
        min(max(value, minZoom), maxZoom)
    }

    public static func nearestStop(_ value: Double) -> Double {
        let zoom = clampedZoom(value)
        return zoomStops.min(by: { abs($0 - zoom) < abs($1 - zoom) }) ?? defaultZoom
    }

    /// Cursor and returned crop use source-pixel space with the origin at the top-left.
    public static func cropRect(
        sourceWidth: Double,
        sourceHeight: Double,
        cursor: CGPoint,
        zoom: Double
    ) -> CGRect {
        let width = max(sourceWidth, 1)
        let height = max(sourceHeight, 1)
        let cropWidth = max(width / clampedZoom(zoom), 32)
        let cropHeight = max(height / clampedZoom(zoom), 32)
        let x = min(max(cursor.x - cropWidth / 2, 0), max(width - cropWidth, 0))
        let y = min(max(cursor.y - cropHeight / 2, 0), max(height - cropHeight, 0))
        return CGRect(x: x, y: y, width: min(cropWidth, width), height: min(cropHeight, height))
    }

    /// Convert an AppKit mouse point into source pixels for the display that owns `screenFrame`.
    public static func cursorInSourcePixels(
        mouse: CGPoint,
        screenFrame: CGRect,
        pixelWidth: Double,
        pixelHeight: Double
    ) -> CGPoint? {
        guard screenFrame.width > 1, screenFrame.height > 1 else { return nil }
        let inset = screenFrame.insetBy(dx: -1, dy: -1)
        guard inset.contains(mouse) else { return nil }
        let localX = mouse.x - screenFrame.minX
        let localYFromTop = screenFrame.maxY - mouse.y
        return CGPoint(
            x: localX / screenFrame.width * max(pixelWidth, 1),
            y: localYFromTop / screenFrame.height * max(pixelHeight, 1)
        )
    }

    public static func clampedFocus(
        _ focus: CGPoint,
        sourceWidth: Double,
        sourceHeight: Double,
        zoom: Double
    ) -> CGPoint {
        let crop = cropRect(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            cursor: focus,
            zoom: zoom
        )
        return CGPoint(x: crop.midX, y: crop.midY)
    }

    /// Space-drag pans the crop like grabbing the canvas.
    /// Dragging the pointer up should reveal content below, so the crop
    /// moves down in source space. AppKit's deltaY is positive for that
    /// movement, and ScreenCaptureKit's sourceRect grows downward.
    public static func pannedFocus(
        current: CGPoint,
        deltaX: Double,
        deltaY: Double,
        previewWidth: Double,
        previewHeight: Double,
        sourceWidth: Double,
        sourceHeight: Double,
        zoom: Double
    ) -> CGPoint {
        let crop = cropRect(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            cursor: current,
            zoom: zoom
        )
        let scaleX = previewWidth > 1 ? crop.width / previewWidth : 1
        let scaleY = previewHeight > 1 ? crop.height / previewHeight : 1
        return clampedFocus(
            CGPoint(
                x: current.x - deltaX * scaleX,
                y: current.y - deltaY * scaleY
            ),
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            zoom: zoom
        )
    }
}

public enum PictureInPictureWallLayout {
    public static let gap: CGFloat = 8
    public static let defaultWidth: CGFloat = 720
    public static let minWidth: CGFloat = 360
    public static let maxWidth: CGFloat = 4096

    public static func snapshots(_ snapshots: [DisplaySnapshot]) -> [DisplaySnapshot] {
        snapshots.filter { PictureInPictureLayout.supports(kind: $0.kind) }
    }

    public static func sanitizedHiddenKeys(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        return stored.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func visibleSnapshots(
        _ snapshots: [DisplaySnapshot],
        hiddenKeys: [String]
    ) -> [DisplaySnapshot] {
        let hidden = Set(sanitizedHiddenKeys(hiddenKeys))
        return self.snapshots(snapshots).filter { !hidden.contains($0.id.persistentKey) }
    }

    public static func hiding(
        _ key: String,
        in stored: [String],
        among snapshots: [DisplaySnapshot]
    ) -> [String] {
        let available = Set(self.snapshots(snapshots).map(\.id.persistentKey))
        guard available.contains(key) else {
            return sanitizedHiddenKeys(stored)
        }
        return sanitizedHiddenKeys(stored + [key])
    }

    public static func shouldCloseAfterHidingLastTile(
        hiddenKeys: [String],
        snapshots: [DisplaySnapshot]
    ) -> Bool {
        visibleSnapshots(snapshots, hiddenKeys: hiddenKeys).isEmpty
            && !self.snapshots(snapshots).isEmpty
    }

    /// If every live display is hidden, the next open restores the full wall.
    public static func restoredHiddenKeys(
        stored: [String],
        snapshots: [DisplaySnapshot]
    ) -> [String] {
        let available = Set(self.snapshots(snapshots).map(\.id.persistentKey))
        let hidden = sanitizedHiddenKeys(stored)
        let hiddenLiveCount = hidden.reduce(into: 0) { count, key in
            if available.contains(key) {
                count += 1
            }
        }
        if !available.isEmpty, hiddenLiveCount >= available.count {
            return []
        }
        return hidden
    }

    public static func hasHiddenTiles(
        stored: [String],
        snapshots: [DisplaySnapshot]
    ) -> Bool {
        let available = Set(self.snapshots(snapshots).map(\.id.persistentKey))
        let hidden = Set(sanitizedHiddenKeys(stored))
        return available.contains { hidden.contains($0) }
    }

    public static func grid(for count: Int) -> (columns: Int, rows: Int) {
        switch max(count, 0) {
        case 0: return (0, 0)
        case 1: return (1, 1)
        case 2: return (2, 1)
        case 3, 4: return (2, 2)
        case 5, 6: return (3, 2)
        default:
            let columns = 3
            let rows = Int(ceil(Double(count) / Double(columns)))
            return (columns, rows)
        }
    }

    public static func contentSize(
        displayCount: Int,
        preferredWidth: CGFloat = defaultWidth,
        maxWidth: CGFloat = maxWidth
    ) -> CGSize {
        let count = max(displayCount, 1)
        let grid = grid(for: count)
        let width = min(max(preferredWidth, minWidth), max(maxWidth, minWidth))
        let tileWidth = (width - gap * CGFloat(max(grid.columns - 1, 0))) / CGFloat(max(grid.columns, 1))
        let tileHeight = tileWidth * 9 / 16
        let height = tileHeight * CGFloat(grid.rows) + gap * CGFloat(max(grid.rows - 1, 0))
        return CGSize(width: width, height: max(height, 80))
    }

    public static func tileFrames(count: Int, in bounds: CGRect, gap: CGFloat = gap) -> [CGRect] {
        let grid = grid(for: count)
        guard count > 0, grid.columns > 0, grid.rows > 0, bounds.width > 1, bounds.height > 1 else {
            return []
        }
        let tileWidth = (bounds.width - gap * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
        let tileHeight = (bounds.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        return (0..<count).map { index in
            let column = index % grid.columns
            let row = index / grid.columns
            return CGRect(
                x: bounds.minX + CGFloat(column) * (tileWidth + gap),
                y: bounds.maxY - CGFloat(row + 1) * tileHeight - CGFloat(row) * gap,
                width: tileWidth,
                height: tileHeight
            )
        }
    }
}

public enum PictureInPictureLayout {
    public static let defaultWidth: CGFloat = 640
    public static let minWidth: CGFloat = 280
    public static let maxWidth: CGFloat = 1280
    public static let chromeHeight: CGFloat = 58
    public static let margin: CGFloat = 24
    public static let minimumCaptureWidth = 1280
    public static let minimumCaptureHeight = 720
    public static let minimumOpacity: Double = 0.25
    public static let snapTolerance: CGFloat = 12
    public static let zoomStep: CGFloat = 1.08
    public static let preciseZoomDivisor: CGFloat = 250

    public static func supports(kind: DisplayKind) -> Bool {
        kind != .virtualUnsupported
    }

    public static func clampedOpacity(_ value: Double) -> Double {
        min(1, max(minimumOpacity, value))
    }

    public static func contentSize(
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        preferredWidth: CGFloat = defaultWidth
    ) -> CGSize {
        let sourceWidth = max(CGFloat(pixelWidth), 1)
        let sourceHeight = max(CGFloat(pixelHeight), 1)
        let width = min(max(preferredWidth, minWidth), maxWidth)
        return CGSize(width: width, height: max(width * (sourceHeight / sourceWidth), 80))
    }

    public static func windowSize(forContent content: CGSize) -> CGSize {
        CGSize(width: content.width, height: content.height + chromeHeight)
    }

    /// Capture at the source display's pixels so the floating window stays sharp.
    public static func captureSize(pixelWidth: UInt32, pixelHeight: UInt32) -> (width: Int, height: Int) {
        var width = max(Int(pixelWidth), minimumCaptureWidth)
        var height = max(Int(pixelHeight), minimumCaptureHeight)
        if pixelWidth > 0, pixelHeight > 0 {
            width = Int(pixelWidth)
            height = Int(pixelHeight)
        }
        width = max(width - width % 2, 2)
        height = max(height - height % 2, 2)
        return (width, height)
    }

    /// Prefer the screen under the pointer so a first-open window appears where the user is looking.
    public static func origin(
        windowSize: CGSize,
        sourceDisplayID: CGDirectDisplayID,
        screens: [(id: CGDirectDisplayID, visible: CGRect)],
        pointer: CGPoint? = nil
    ) -> CGPoint {
        windowFrame(
            windowSize: windowSize,
            sourceDisplayID: sourceDisplayID,
            screens: screens,
            placement: .default,
            pointer: pointer
        ).origin
    }

    public static func windowFrame(
        windowSize: CGSize,
        sourceDisplayID: CGDirectDisplayID,
        screens: [(id: CGDirectDisplayID, visible: CGRect)],
        placement: PictureInPicturePlacement = .default,
        pointer: CGPoint? = nil
    ) -> CGRect {
        let size = clampedWindowSize(windowSize)
        let host = hostScreen(
            preferredDisplayID: placement.hostDisplayID,
            savedFrame: placement.frame?.rect,
            sourceDisplayID: sourceDisplayID,
            screens: screens,
            pointer: pointer
        )
        guard let host else {
            return CGRect(origin: .zero, size: size)
        }
        if let corner = placement.corner {
            return CGRect(origin: snapOrigin(windowSize: size, corner: corner, visible: host.visible), size: size)
        }
        if let saved = placement.frame?.rect, saved.width > 1, saved.height > 1 {
            let overlap = saved.intersection(host.visible)
            if overlap.width * overlap.height > 1 {
                return clampedFrame(CGRect(origin: saved.origin, size: size), in: host.visible)
            }
        }
        return CGRect(
            origin: snapOrigin(windowSize: size, corner: .bottomRight, visible: host.visible),
            size: size
        )
    }

    public static func snapOrigin(windowSize: CGSize, corner: PictureInPictureCorner, visible: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: visible.minX + margin, y: visible.maxY - windowSize.height - margin)
        case .topRight:
            return CGPoint(x: visible.maxX - windowSize.width - margin, y: visible.maxY - windowSize.height - margin)
        case .bottomLeft:
            return CGPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:
            return CGPoint(x: visible.maxX - windowSize.width - margin, y: visible.minY + margin)
        case .center:
            return CGPoint(
                x: visible.midX - windowSize.width / 2,
                y: visible.midY - windowSize.height / 2
            )
        }
    }

    public static func clampedFrame(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var next = frame
        if next.width > visible.width {
            next.size.width = visible.width
        }
        if next.height > visible.height {
            next.size.height = visible.height
        }
        if next.maxX > visible.maxX {
            next.origin.x = visible.maxX - next.width
        }
        if next.maxY > visible.maxY {
            next.origin.y = visible.maxY - next.height
        }
        if next.minX < visible.minX {
            next.origin.x = visible.minX
        }
        if next.minY < visible.minY {
            next.origin.y = visible.minY
        }
        return next
    }

    /// Menu bar and dock sit just outside `visibleFrame`, so pad before giving up.
    public static let pointerHitPadding = CGSize(width: 24, height: 48)

    public static func hostScreen(
        preferredDisplayID: UInt32?,
        savedFrame: CGRect?,
        sourceDisplayID: CGDirectDisplayID,
        screens: [(id: CGDirectDisplayID, visible: CGRect)],
        pointer: CGPoint? = nil
    ) -> (id: CGDirectDisplayID, visible: CGRect)? {
        if let pointer, let match = screenContaining(point: pointer, screens: screens) {
            return match
        }
        if let savedFrame {
            let ranked = screens
                .map { screen -> (screen: (id: CGDirectDisplayID, visible: CGRect), area: CGFloat) in
                    (screen, screen.visible.intersection(savedFrame).width * screen.visible.intersection(savedFrame).height)
                }
                .filter { $0.area > 1 }
                .sorted { $0.area > $1.area }
            if let best = ranked.first {
                return best.screen
            }
        }
        if let preferredDisplayID,
           let match = screens.first(where: { $0.id == preferredDisplayID })
        {
            return match
        }
        return screens.first(where: { $0.id != sourceDisplayID }) ?? screens.first
    }

    public static func screenContaining(
        point: CGPoint,
        screens: [(id: CGDirectDisplayID, visible: CGRect)]
    ) -> (id: CGDirectDisplayID, visible: CGRect)? {
        if let exact = screens.first(where: { $0.visible.contains(point) }) {
            return exact
        }
        let padded = screens.filter {
            $0.visible.insetBy(dx: -pointerHitPadding.width, dy: -pointerHitPadding.height).contains(point)
        }
        if padded.count == 1 {
            return padded[0]
        }
        if let closest = padded.min(by: { distanceSquared($0.visible, to: point) < distanceSquared($1.visible, to: point) }) {
            return closest
        }
        return nil
    }

    private static func distanceSquared(_ rect: CGRect, to point: CGPoint) -> CGFloat {
        let x = point.x < rect.minX ? rect.minX - point.x : max(point.x - rect.maxX, 0)
        let y = point.y < rect.minY ? rect.minY - point.y : max(point.y - rect.maxY, 0)
        return x * x + y * y
    }

    public static func clampedWindowSize(_ size: CGSize) -> CGSize {
        let width = min(max(size.width, minWidth), maxWidth)
        let height = max(size.height, chromeHeight + 80)
        return CGSize(width: width, height: height)
    }

    public static func movedOffPinnedCorner(
        frame: CGRect,
        corner: PictureInPictureCorner,
        visible: CGRect
    ) -> Bool {
        let snap = snapOrigin(windowSize: frame.size, corner: corner, visible: visible)
        let dx = frame.origin.x - snap.x
        let dy = frame.origin.y - snap.y
        return (dx * dx + dy * dy).squareRoot() > snapTolerance
    }

    /// Space-pan in magnifier mode must not resize the floating window.
    public static func shouldResizeWindow(forMagnifierPan spaceHeld: Bool, mode: PictureInPictureMode) -> Bool {
        !(mode == .magnifier && spaceHeld)
    }

    /// Space-pan must change only the captured crop, never the window frame.
    public static func shouldMoveWindow(forMagnifierPan spaceHeld: Bool, mode: PictureInPictureMode) -> Bool {
        !(mode == .magnifier && spaceHeld)
    }

    /// Window mode without a chosen, resolvable window should keep showing the display.
    public static func shouldFallBackToDisplay(mode: PictureInPictureMode, hasResolvedWindow: Bool) -> Bool {
        mode == .window && !hasResolvedWindow
    }

    /// Positive `deltaY` zooms in. Discrete wheels take one step; trackpads scale by distance.
    public static func zoomFactor(deltaY: CGFloat, precise: Bool) -> CGFloat {
        if precise {
            return min(max(1 + (deltaY / preciseZoomDivisor), 0.85), 1.18)
        }
        if deltaY == 0 { return 1 }
        return deltaY > 0 ? zoomStep : 1 / zoomStep
    }

    public static func isMouseOverWindow(
        mouse: CGPoint,
        windowFrame: CGRect,
        inset: CGFloat = 0
    ) -> Bool {
        windowFrame.insetBy(dx: -inset, dy: -inset).contains(mouse)
    }

    public static func shouldCloseOnCommandW(
        mouse: CGPoint,
        windowFrame: CGRect,
        commandPressed: Bool,
        key: String
    ) -> Bool {
        commandPressed && key.lowercased() == "w" && isMouseOverWindow(mouse: mouse, windowFrame: windowFrame)
    }

    public static func zoomedFrame(
        current: CGRect,
        factor: CGFloat,
        aspect: CGFloat,
        corner: PictureInPictureCorner? = nil,
        visible: CGRect? = nil,
        minWidth: CGFloat = minWidth,
        maxWidth: CGFloat = maxWidth
    ) -> CGRect {
        _ = aspect
        let nextWidth = min(max(current.width * factor, minWidth), max(maxWidth, minWidth))
        let scale = current.width > 1 ? nextWidth / current.width : 1
        let nextHeight = max(current.height * scale, chromeHeight + 80)
        var next = CGRect(x: current.origin.x, y: current.origin.y, width: nextWidth, height: nextHeight)
        if abs(nextWidth - current.width) < 0.5, abs(nextHeight - current.height) < 0.5 {
            return visible.map { clampedFrame(current, in: $0) } ?? current
        }
        if let corner, let visible {
            next.origin = snapOrigin(windowSize: next.size, corner: corner, visible: visible)
            return clampedFrame(next, in: visible)
        }
        return centeredFrame(next, around: current, visible: visible)
    }

    /// AppKit / Auto Layout can change the height after `setFrame`.
    /// Re-center the settled size on the pre-zoom midpoint so zoom-in/out
    /// does not walk the window.
    public static func centeredFrame(
        _ frame: CGRect,
        around current: CGRect,
        visible: CGRect? = nil
    ) -> CGRect {
        var next = frame
        next.origin.x = current.midX - next.width / 2
        next.origin.y = current.midY - next.height / 2
        if let visible {
            return clampedFrame(next, in: visible)
        }
        return next
    }
}
