import AppKit

@MainActor
final class SettingsShortcutsView: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 500))

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let heading = CandelaChrome.makeTitle(String(localized: "Shortcuts"), size: 22, weight: .semibold)
        let subtitle = CandelaChrome.makeCaption(String(localized: "Keyboard shortcuts already available in Candela."))
        let header = NSStackView(views: [heading, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        header.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "App"),
            rows: [
                (String(localized: "Open Settings"), "⌘,"),
                (String(localized: "Quit"), "⌘Q"),
            ]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Menu Bar"),
            rows: [
                (String(localized: "Close Panel"), "Esc"),
            ]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Settings"),
            rows: [
                (String(localized: "Close Settings"), "Esc"),
            ]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Picture in Picture"),
            rows: [
                (String(localized: "Close Picture in Picture"), "⌘W"),
                (String(localized: "Scroll to zoom"), String(localized: "Scroll")),
                (String(localized: "Space-drag to pan"), String(localized: "Space-drag")),
            ]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Display Overview"),
            rows: [
                (String(localized: "Close Display Overview"), "⌘W"),
                (String(localized: "Scroll to zoom"), String(localized: "Scroll")),
            ]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "About"),
            rows: [
                (String(localized: "Copy debug dump"), String(localized: "Option-click")),
            ]
        ))

        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
        ])
        document.setContentHuggingPriority(.required, for: .vertical)
        document.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeGroup(title: String, rows: [(String, String)]) -> NSView {
        let heading = CandelaChrome.makeCaption(title.uppercased())
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = CandelaChrome.accent
        let card = CandelaChrome.makeModule()
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        for (index, row) in rows.enumerated() {
            column.addArrangedSubview(makeRow(title: row.0, shortcut: row.1))
            if index < rows.count - 1 {
                column.addArrangedSubview(CandelaChrome.makeHairline())
            }
        }
        CandelaChrome.pin(column, to: card, insets: NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14))
        let wrap = NSStackView(views: [heading, card])
        wrap.orientation = .vertical
        wrap.alignment = .leading
        wrap.spacing = 6
        wrap.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: wrap.widthAnchor).isActive = true
        wrap.widthAnchor.constraint(equalToConstant: 584).isActive = true
        return wrap
    }

    private func makeRow(title: String, shortcut: String) -> NSView {
        let titleField = CandelaChrome.makeTitle(title, size: 13, weight: .medium)
        let shortcutField = CandelaChrome.makeCaption(shortcut)
        shortcutField.font = .systemFont(ofSize: 12, weight: .semibold)
        shortcutField.textColor = .secondaryLabelColor
        shortcutField.alignment = .right
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [titleField, spacer, shortcutField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 556).isActive = true
        return row
    }
}

private final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
