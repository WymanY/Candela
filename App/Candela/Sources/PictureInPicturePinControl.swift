import AppKit
import DisplayCore

@MainActor
final class PictureInPicturePinControl: NSPopUpButton {
    var onChange: ((PictureInPictureCorner?) -> Void)?

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .recessed
        controlSize = .small
        isBordered = false
        imagePosition = .imageOnly
        pullsDown = true
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

    private func rebuildMenu() {
        removeAllItems()
        addItem(withTitle: "")
        item(at: 0)?.image = Self.symbol("rectangle.dashed")

        addOption(title: String(localized: "Free Position"), value: "", symbolName: "arrow.up.and.down.and.arrow.left.and.right")
        addOption(title: String(localized: "Snap Top Left"), value: PictureInPictureCorner.topLeft.rawValue, symbolName: "rectangle.lefthalf.inset.filled.arrow.left")
        addOption(title: String(localized: "Snap Top Right"), value: PictureInPictureCorner.topRight.rawValue, symbolName: "rectangle.righthalf.inset.filled.arrow.right")
        addOption(title: String(localized: "Snap Bottom Left"), value: PictureInPictureCorner.bottomLeft.rawValue, symbolName: "rectangle.bottomhalf.inset.filled")
        addOption(title: String(localized: "Snap Bottom Right"), value: PictureInPictureCorner.bottomRight.rawValue, symbolName: "rectangle.tophalf.inset.filled")
        select(corner: nil)
    }

    private func addOption(title: String, value: String, symbolName: String) {
        addItem(withTitle: title)
        lastItem?.representedObject = value
        lastItem?.image = Self.symbol(symbolName)
        lastItem?.toolTip = title
    }

    @objc private func selectionChanged(_ sender: NSPopUpButton) {
        refreshTitleImage()
        let raw = selectedItem?.representedObject as? String ?? ""
        onChange?(PictureInPictureCorner(rawValue: raw))
    }

    private func refreshTitleImage() {
        let raw = selectedItem?.representedObject as? String ?? ""
        let symbolName: String
        switch PictureInPictureCorner(rawValue: raw) {
        case .topLeft:
            symbolName = "rectangle.lefthalf.inset.filled.arrow.left"
        case .topRight:
            symbolName = "rectangle.righthalf.inset.filled.arrow.right"
        case .bottomLeft:
            symbolName = "rectangle.bottomhalf.inset.filled"
        case .bottomRight:
            symbolName = "rectangle.tophalf.inset.filled"
        case nil:
            symbolName = "arrow.up.and.down.and.arrow.left.and.right"
        }
        item(at: 0)?.image = Self.symbol(symbolName)
        toolTip = selectedItem?.title.isEmpty == false ? selectedItem?.title : String(localized: "Snap to Corner")
        setAccessibilityValue(toolTip)
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}
