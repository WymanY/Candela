import AppKit
import DisplayCore

@MainActor
final class SettingsDisplaysView: NSView, NSTextFieldDelegate {
    private let session: DisplaySessionController
    private let stack = NSStackView()
    private let empty = CandelaChrome.makeCaption(String(localized: "No Displays"))

    init(session: DisplaySessionController) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 500))

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let heading = CandelaChrome.makeTitle(String(localized: "Displays"), size: 22, weight: .semibold)
        let subtitle = CandelaChrome.makeCaption(String(localized: "Identity, connection, and control path for each panel."))
        let header = NSStackView(views: [heading, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        empty.font = .systemFont(ofSize: 13, weight: .medium)
        empty.alignment = .center

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(header)
        document.addSubview(stack)
        scroll.documentView = document
        header.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            header.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28),
        ])
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let snapshots = session.snapshots
        if snapshots.isEmpty {
            stack.addArrangedSubview(empty)
            return
        }
        for snapshot in snapshots {
            let card = makeCard(snapshot)
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeCard(_ snapshot: DisplaySnapshot) -> NSView {
        let card = CandelaChrome.makeModule()
        let name = CandelaChrome.makeTitle(snapshot.hardwareName, size: 14, weight: .semibold)
        let badges = NSStackView()
        badges.orientation = .horizontal
        badges.alignment = .centerY
        badges.spacing = 6
        badges.addArrangedSubview(makeBadge(DisplayPresentation.connectionTitle(for: snapshot)))
        if snapshot.isMain {
            badges.addArrangedSubview(makeBadge(String(localized: "Main")))
        }
        if snapshot.kind == .virtualUnsupported {
            badges.addArrangedSubview(makeBadge(String(localized: "Unsupported")))
        }

        let field = NSTextField(string: snapshot.name == snapshot.hardwareName ? "" : snapshot.name)
        field.placeholderString = snapshot.hardwareName
        field.identifier = NSUserInterfaceItemIdentifier(snapshot.id.persistentKey)
        field.delegate = self
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 13)
        field.target = self
        field.action = #selector(nameEdited(_:))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let nameLabel = CandelaChrome.makeCaption(String(localized: "Custom Name"))
        let nameColumn = NSStackView(views: [nameLabel, field])
        nameColumn.orientation = .vertical
        nameColumn.alignment = .leading
        nameColumn.spacing = 4
        nameColumn.setHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [name, NSView(), badges])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let facts = NSGridView(views: factRows(for: snapshot))
        facts.rowSpacing = 6
        facts.columnSpacing = 16
        facts.xPlacement = .leading
        facts.yPlacement = .center
        if facts.numberOfColumns > 0 {
            facts.column(at: 0).width = 92
        }

        let column = NSStackView(views: [header, facts, nameColumn])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        CandelaChrome.pin(column, to: card, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        card.translatesAutoresizingMaskIntoConstraints = false
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        facts.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        header.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        nameColumn.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return card
    }

    private func factRows(for snapshot: DisplaySnapshot) -> [[NSView]] {
        var rows: [[NSView]] = []
        if let mode = DisplayPresentation.modeTitle(for: snapshot) {
            var value = mode
            if let refresh = DisplayPresentation.refreshTitle(for: snapshot) {
                value += " · \(refresh)"
            }
            if let scale = DisplayPresentation.scaleTitle(for: snapshot) {
                value += " · \(scale)"
            }
            rows.append(factRow(String(localized: "Resolution"), value))
        }
        rows.append(factRow(String(localized: "Connection"), DisplayPresentation.connectionTitle(for: snapshot)))
        rows.append(factRow(String(localized: "Brightness"), DisplayPresentation.brightnessBackendTitle(for: snapshot)))
        rows.append(factRow(String(localized: "Volume"), DisplayPresentation.volumeBackendTitle(for: snapshot)))
        if snapshot.contrast.supportsContrast {
            rows.append(factRow(String(localized: "Contrast"), String(localized: "DDC")))
        }
        if snapshot.input.supportsInputSelect {
            let current = snapshot.input.current?.title ?? String(localized: "DDC")
            rows.append(factRow(String(localized: "Input"), current))
        }
        if snapshot.rotation.supportsRotation {
            rows.append(factRow(String(localized: "Rotation"), DisplayPresentation.rotationTitle(for: snapshot)))
        }
        if PictureInPictureLayout.supports(kind: snapshot.kind) {
            let value = snapshot.pictureInPictureActive ? String(localized: "Open") : String(localized: "Available")
            rows.append(factRow(String(localized: "Picture in Picture"), value))
        }
        if let vendor = DisplayPresentation.vendorTitle(for: snapshot) {
            rows.append(factRow(String(localized: "Vendor"), vendor))
        }
        rows.append(factRow(String(localized: "Product"), DisplayPresentation.identityTitle(for: snapshot)))
        if let serial = DisplayPresentation.serialTitle(for: snapshot) {
            rows.append(factRow(String(localized: "Serial"), serial))
        }
        if snapshot.isMain {
            rows.append(factRow(String(localized: "Role"), String(localized: "Main display")))
        }
        return rows
    }

    private func factRow(_ title: String, _ value: String) -> [NSView] {
        let label = CandelaChrome.makeCaption(title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        let field = CandelaChrome.makeCaption(value)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingMiddle
        return [label, field]
    }

    private func makeBadge(_ title: String) -> NSView {
        CandelaChrome.makeCapsule(title)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        commit(field)
    }

    @objc private func nameEdited(_ sender: NSTextField) {
        commit(sender)
    }

    private func commit(_ field: NSTextField) {
        guard let key = field.identifier?.rawValue else { return }
        _ = session.renameDisplay(key: key, customName: field.stringValue)
        reload()
    }
}
