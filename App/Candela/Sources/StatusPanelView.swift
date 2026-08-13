import AppKit
import DisplayCore

@MainActor
final class StatusPanelView: NSView {
    private let session: DisplaySessionController
    private let effectView = NSVisualEffectView()
    private let stack = NSStackView()
    private var rows: [DisplayRowView] = []
    private var rowKeys: [String] = []

    init(session: DisplaySessionController) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            widthAnchor.constraint(equalToConstant: 300),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var fittingSize: NSSize {
        let stackSize = stack.fittingSize
        return NSSize(width: 300, height: max(stackSize.height, 48))
    }

    func reload(_ snapshots: [DisplaySnapshot]) {
        let keys = snapshots.map(\.id.persistentKey)
        if keys == rowKeys, rows.count == snapshots.count {
            for (row, snapshot) in zip(rows, snapshots) {
                row.apply(snapshot, showPercent: session.settings.showPercentText)
            }
            return
        }
        rowKeys = keys
        rows.forEach { $0.removeFromSuperview() }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        rows.removeAll()

        if snapshots.isEmpty {
            let empty = NSTextField(labelWithString: String(localized: "No Displays"))
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 13)
            empty.alignment = .center
            stack.addArrangedSubview(empty)
            return
        }

        for snapshot in snapshots {
            let row = DisplayRowView()
            row.onBrightness = { [weak self] value in
                self?.session.setBrightness(key: snapshot.id.persistentKey, value: value)
            }
            row.onVolume = { [weak self] value in
                self?.session.setVolume(key: snapshot.id.persistentKey, value: value)
            }
            row.onMute = { [weak self] muted in
                self?.session.setMuted(key: snapshot.id.persistentKey, muted: muted)
            }
            row.apply(snapshot, showPercent: session.settings.showPercentText)
            stack.addArrangedSubview(row)
            rows.append(row)
        }
    }
}
