import AppKit
import DisplayCore

@MainActor
final class SettingsScenesView: NSView, NSTextFieldDelegate {
    private let session: DisplaySessionController
    private let stack = NSStackView()
    private let empty = CandelaChrome.makeCaption(String(localized: "No saved scenes yet."))

    init(session: DisplaySessionController) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 500))

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let heading = CandelaChrome.makeTitle(String(localized: "Scenes"), size: 22, weight: .semibold)
        let subtitle = CandelaChrome.makeCaption(String(localized: "Save the current displays as a named scene, then apply it later."))
        let header = NSStackView(views: [heading, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        header.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = CandelaChrome.makeQuietButton(title: String(localized: "Save Current…"), symbolName: "plus")
        saveButton.target = self
        saveButton.action = #selector(saveCurrent)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        empty.font = .systemFont(ofSize: 13, weight: .medium)

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(header)
        document.addSubview(saveButton)
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
            header.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            saveButton.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            saveButton.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 14),
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
        let scenes = session.scenes
        if scenes.isEmpty {
            stack.addArrangedSubview(empty)
            return
        }
        for scene in scenes {
            let card = makeCard(scene)
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeCard(_ scene: DisplayScene) -> NSView {
        let card = CandelaChrome.makeModule()
        let field = NSTextField(string: scene.name)
        field.identifier = NSUserInterfaceItemIdentifier(scene.id)
        field.delegate = self
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.target = self
        field.action = #selector(nameEdited(_:))

        let summary = CandelaChrome.makeCaption(summaryText(for: scene))
        let apply = CandelaChrome.makeQuietButton(title: String(localized: "Apply"), symbolName: "play.fill")
        apply.identifier = NSUserInterfaceItemIdentifier(scene.id)
        apply.target = self
        apply.action = #selector(applyClicked(_:))
        if DisplayScenePlanner.matches(scene, snapshots: session.snapshots, aliases: [:], speaker: session.speaker) {
            apply.contentTintColor = CandelaChrome.accent
        }
        let update = CandelaChrome.makeQuietButton(title: String(localized: "Update"), symbolName: "arrow.triangle.2.circlepath")
        update.identifier = NSUserInterfaceItemIdentifier(scene.id)
        update.target = self
        update.action = #selector(updateClicked(_:))
        let delete = CandelaChrome.makeQuietButton(title: String(localized: "Delete"), symbolName: "trash")
        delete.identifier = NSUserInterfaceItemIdentifier(scene.id)
        delete.target = self
        delete.action = #selector(deleteClicked(_:))

        let buttons = NSStackView(views: [apply, update, delete])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let column = NSStackView(views: [field, summary, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        CandelaChrome.pin(column, to: card, insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func summaryText(for scene: DisplayScene) -> String {
        let plan = DisplayScenePlanner.plan(scene: scene, snapshots: session.snapshots)
        var parts = ["\(scene.targets.count) " + String(localized: "displays")]
        if plan.missingKeys.isEmpty == false {
            parts.append("\(plan.missingKeys.count) " + String(localized: "missing"))
        }
        if DisplayScenePlanner.matches(scene, snapshots: session.snapshots, aliases: [:], speaker: session.speaker) {
            parts.append(String(localized: "Active"))
        }
        return parts.joined(separator: " · ")
    }

    @objc private func saveCurrent() {
        promptForName(defaultName: suggestedName()) { [weak self] name in
            _ = self?.session.saveScene(named: name)
            self?.reload()
        }
    }

    @objc private func applyClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        _ = session.applyScene(id)
        reload()
    }

    @objc private func updateClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let scene = session.scene(matching: id) else { return }
        _ = session.saveScene(named: scene.name)
        reload()
    }

    @objc private func deleteClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let scene = session.scene(matching: id) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete Scene")
        alert.informativeText = String(localized: "Remove “\(scene.displayName)”? This cannot be undone.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = session.deleteScene(id)
        reload()
    }

    @objc private func nameEdited(_ sender: NSTextField) {
        commit(sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        commit(field)
    }

    private func commit(_ field: NSTextField) {
        guard let id = field.identifier?.rawValue else { return }
        _ = session.renameScene(id, to: field.stringValue)
        reload()
    }

    private func suggestedName() -> String {
        let existing = Set(session.scenes.map { DisplaySceneName.slug($0.name) })
        if !existing.contains("desk") { return String(localized: "Desk") }
        if !existing.contains("night") { return String(localized: "Night") }
        var index = session.scenes.count + 1
        while existing.contains(DisplaySceneName.slug("Scene \(index)")) {
            index += 1
        }
        return String(localized: "Scene \(index)")
    }

    private func promptForName(defaultName: String, completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Scene")
        alert.informativeText = String(localized: "Capture brightness, volume, input, rotation, and Picture in Picture for the current displays.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        completion(field.stringValue)
    }
}
