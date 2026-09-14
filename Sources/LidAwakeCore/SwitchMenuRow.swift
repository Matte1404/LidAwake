import AppKit

/// A persistent menu header with a native, accessible on/off switch.
final class SwitchMenuRow: NSView {
    private weak var item: NSMenuItem?
    private let label = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    let toggle = NSSwitch()
    private var awaitingChange = false

    init(item: NSMenuItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 64))
        autoresizingMask = [.width]
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.setAccessibilityElement(false)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .labelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        statusIcon.contentTintColor = .labelColor
        statusIcon.setAccessibilityElement(false)
        toggle.controlSize = .regular
        toggle.target = self
        toggle.action = #selector(switchChanged)
        for view in [label, subtitleLabel, statusIcon, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -16),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            statusIcon.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 16),
            statusIcon.heightAnchor.constraint(equalToConstant: 16),
            statusIcon.centerYAnchor.constraint(equalTo: subtitleLabel.centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 6),
            subtitleLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14)
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateStatus(subtitle: String, image: NSImage?) {
        if subtitleLabel.stringValue != subtitle { subtitleLabel.stringValue = subtitle }
        if statusIcon.image !== image { statusIcon.image = image }
    }

    func update() {
        guard let item = item else { return }
        if label.stringValue != item.title {
            label.stringValue = item.title
            toggle.setAccessibilityLabel(item.title)
        }
        if toggle.isEnabled != item.isEnabled { toggle.isEnabled = item.isEnabled }
        // A click animates immediately. While the operation is pending, keep that
        // position; the next enabled update confirms success or rolls it back.
        if !awaitingChange || item.isEnabled {
            if toggle.state != item.state { toggle.state = item.state }
            awaitingChange = false
        }
        let color = item.isEnabled ? NSColor.labelColor : .disabledControlTextColor
        if label.textColor != color { label.textColor = color }
        let hint = item.keyEquivalent.isEmpty ? item.title : "\(item.title) (⌘\(item.keyEquivalent.uppercased()))"
        if toolTip != hint { toolTip = hint }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // The status line is informational; only the title/switch area toggles.
        guard bounds.contains(point), point.y >= bounds.height - 34 else { return }
        toggle.performClick(nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === label ? self : hit
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        guard let item = item, item.isEnabled, let action = item.action else { update(); return }
        awaitingChange = true
        NSApplication.shared.sendAction(action, to: item.target, from: sender)
        // Setup may have been canceled without starting an operation.
        update()
    }
}
