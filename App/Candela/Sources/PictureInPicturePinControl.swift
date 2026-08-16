import AppKit
import DisplayCore

@MainActor
final class PictureInPicturePinControl: NSPopUpButton {
    var onChange: ((PictureInPictureCorner?) -> Void)?
    private var isRebuilding = false

    convenience init() {
        self.init(frame: .zero, pullsDown: true)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pullsDown: true)
        configure()
    }

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: true)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(corner: PictureInPictureCorner?) {
        let selected = corner?.rawValue ?? ""
        if let index = itemArray.dropFirst().firstIndex(where: { ($0.representedObject as? String) == selected }) {
            select(itemArray[index])
        } else if numberOfItems > 1 {
            selectItem(at: 1)
        }
        refreshTitleImage()
    }

    private func configure() {
        bezelStyle = .recessed
        controlSize = .small
        isBordered = false
        imagePosition = .imageOnly
        preferredEdge = .minY
        target = self
        action = #selector(selectionChanged(_:))
        setAccessibilityLabel(String(localized: "Snap to Corner"))
        toolTip = String(localized: "Snap to Corner")
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        rebuildMenu()
    }

    private func rebuildMenu() {
        isRebuilding = true
        removeAllItems()
        addItem(withTitle: "")
        item(at: 0)?.image = Self.symbol("arrow.up.and.down.and.arrow.left.and.right")

        addOption(title: String(localized: "Free Position"), value: "", symbolName: "arrow.up.and.down.and.arrow.left.and.right")
        addOption(title: String(localized: "Snap Top Left"), value: PictureInPictureCorner.topLeft.rawValue, symbolName: "arrow.up.left.square")
        addOption(title: String(localized: "Snap Top Right"), value: PictureInPictureCorner.topRight.rawValue, symbolName: "arrow.up.right.square")
        addOption(title: String(localized: "Snap Bottom Left"), value: PictureInPictureCorner.bottomLeft.rawValue, symbolName: "arrow.down.left.square")
        addOption(title: String(localized: "Snap Bottom Right"), value: PictureInPictureCorner.bottomRight.rawValue, symbolName: "arrow.down.right.square")
        isRebuilding = false
        select(corner: nil)
    }

    private func addOption(title: String, value: String, symbolName: String) {
        addItem(withTitle: title)
        lastItem?.representedObject = value
        lastItem?.image = Self.symbol(symbolName)
        lastItem?.toolTip = title
    }

    @objc private func selectionChanged(_ sender: NSPopUpButton) {
        guard !isRebuilding else { return }
        refreshTitleImage()
        let raw = selectedItem?.representedObject as? String ?? ""
        onChange?(PictureInPictureCorner(rawValue: raw))
    }

    private func refreshTitleImage() {
        let raw = selectedItem?.representedObject as? String ?? ""
        let symbolName: String
        switch PictureInPictureCorner(rawValue: raw) {
        case .topLeft:
            symbolName = "arrow.up.left.square"
        case .topRight:
            symbolName = "arrow.up.right.square"
        case .bottomLeft:
            symbolName = "arrow.down.left.square"
        case .bottomRight:
            symbolName = "arrow.down.right.square"
        case nil:
            symbolName = "arrow.up.and.down.and.arrow.left.and.right"
        }
        item(at: 0)?.image = Self.symbol(symbolName)
        let title = selectedItem?.title.isEmpty == false ? selectedItem?.title : String(localized: "Snap to Corner")
        toolTip = title
        setAccessibilityValue(title)
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}
