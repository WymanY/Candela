import AppKit

@MainActor
final class SettingsGeneralView: NSView {
    private let session: DisplaySessionController
    private let launchAtLogin = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let restoreOnReconnect = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let softwareDimming = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let allowDimToBlack = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showPercent = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let followKeyboard = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private let errorLabel = CandelaChrome.makeCaption()

    init(session: DisplaySessionController) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 500))

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = CandelaChrome.makeTitle(String(localized: "General"), size: 22, weight: .semibold)
        let subtitle = CandelaChrome.makeCaption(String(localized: "Startup, dimming, and panel labels."))
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        for button in [launchAtLogin, restoreOnReconnect, softwareDimming, allowDimToBlack, showPercent, followKeyboard] {
            button.target = self
            button.action = #selector(settingChanged(_:))
            button.setButtonType(.switch)
            button.setContentHuggingPriority(.required, for: .horizontal)
        }

        languagePopup.controlSize = .regular
        languagePopup.font = .systemFont(ofSize: 13, weight: .medium)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        languagePopup.setContentHuggingPriority(.required, for: .horizontal)
        reloadLanguageMenu()

        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Startup"),
            rows: [(launchAtLogin, String(localized: "Launch at Login"), String(localized: "Open Candela when you log in."))]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Displays"),
            rows: [
                (restoreOnReconnect, String(localized: "Restore last brightness on reconnect"), String(localized: "Brightness restored after unplug.")),
                (followKeyboard, String(localized: "Follow keyboard brightness"), String(localized: "Keep other displays at a relative offset when the keyboard brightness keys move the built-in panel.")),
                (softwareDimming, String(localized: "Software dimming"), String(localized: "Use gamma when hardware control is missing.")),
                (allowDimToBlack, String(localized: "Allow dim to black"), String(localized: "Let software dimming reach 0%.")),
            ]
        ))
        stack.addArrangedSubview(makeGroup(
            title: String(localized: "Panel"),
            rows: [(showPercent, String(localized: "Show percent next to sliders"), String(localized: "Show 50% beside each slider."))]
        ))
        stack.addArrangedSubview(makeLanguageGroup())
        stack.addArrangedSubview(errorLabel)

        let document = NSView()
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
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let settings = session.settings
        launchAtLogin.state = settings.launchAtLogin ? .on : .off
        restoreOnReconnect.state = settings.restoreOnReconnect ? .on : .off
        softwareDimming.state = settings.softwareDimmingEnabled ? .on : .off
        allowDimToBlack.state = settings.allowDimToBlack ? .on : .off
        showPercent.state = settings.showPercentText ? .on : .off
        followKeyboard.state = settings.followKeyboardBrightness ? .on : .off
        reloadLanguageMenu()
        if let error = session.launchAtLoginError, !error.isEmpty {
            errorLabel.stringValue = error
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }
    }

    @objc private func settingChanged(_ sender: NSButton) {
        var next = session.settings
        next.launchAtLogin = launchAtLogin.state == .on
        next.restoreOnReconnect = restoreOnReconnect.state == .on
        next.softwareDimmingEnabled = softwareDimming.state == .on
        next.allowDimToBlack = allowDimToBlack.state == .on
        next.showPercentText = showPercent.state == .on
        next.followKeyboardBrightness = followKeyboard.state == .on
        session.saveSettings(next)
        reload()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        var next = session.settings
        if next.preferredLanguage == raw { return }
        next.preferredLanguage = raw
        AppLanguage.apply(raw)
        session.saveSettings(next)
        reload()
    }

    private func reloadLanguageMenu() {
        languagePopup.removeAllItems()
        let selected = AppLanguage(rawValue: session.settings.preferredLanguage) ?? .system
        for language in AppLanguage.allCases {
            languagePopup.addItem(withTitle: language.menuTitle)
            languagePopup.lastItem?.representedObject = language.rawValue
            if language == selected {
                languagePopup.select(languagePopup.lastItem)
            }
        }
    }

    private func makeLanguageGroup() -> NSView {
        let heading = CandelaChrome.makeCaption(String(localized: "Language").uppercased())
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = CandelaChrome.accent
        let card = CandelaChrome.makeModule()
        let titleField = CandelaChrome.makeTitle(String(localized: "App Language"), size: 13, weight: .medium)
        let caption = CandelaChrome.makeCaption(String(localized: "Defaults to the language set in System Settings."))
        let texts = NSStackView(views: [titleField, caption])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [texts, spacer, languagePopup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 556).isActive = true
        CandelaChrome.pin(row, to: card, insets: NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14))
        let wrap = NSStackView(views: [heading, card])
        wrap.orientation = .vertical
        wrap.alignment = .leading
        wrap.spacing = 6
        wrap.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: wrap.widthAnchor).isActive = true
        wrap.widthAnchor.constraint(equalToConstant: 584).isActive = true
        return wrap
    }

    private func makeGroup(title: String, rows: [(NSButton, String, String?)]) -> NSView {
        let heading = CandelaChrome.makeCaption(title.uppercased())
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = CandelaChrome.accent
        let card = CandelaChrome.makeModule()
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        for (index, row) in rows.enumerated() {
            column.addArrangedSubview(makeRow(checkbox: row.0, title: row.1, caption: row.2))
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

    private func makeRow(checkbox: NSButton, title: String, caption: String?) -> NSView {
        let titleField = CandelaChrome.makeTitle(title, size: 13, weight: .medium)
        let texts = NSStackView(views: [titleField])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        if let caption {
            texts.addArrangedSubview(CandelaChrome.makeCaption(caption))
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [texts, spacer, checkbox])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 556).isActive = true
        return row
    }
}
