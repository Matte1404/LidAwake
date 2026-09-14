import AppKit

public struct MenuEntry: Equatable {
    public enum Style { case standard, toggle }
    public let id: String
    let title: String
    let action: Selector?
    let keyEquivalent: String
    let state: NSControl.StateValue
    let enabled: Bool
    let separator: Bool
    let indentationLevel: Int
    let style: Style
    let subtitle: String
    let symbol: String?

    public init(id: String, title: String = "", action: Selector? = nil, keyEquivalent: String = "",
                state: NSControl.StateValue = .off, enabled: Bool = true, separator: Bool = false,
                indentationLevel: Int = 0, style: Style = .standard, subtitle: String = "", symbol: String? = nil) {
        self.id = id
        self.title = title
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.state = state
        self.enabled = action != nil && enabled
        self.separator = separator
        self.indentationLevel = indentationLevel
        self.style = style
        self.subtitle = subtitle
        self.symbol = symbol
    }

    public static func separator(_ id: String) -> MenuEntry { MenuEntry(id: id, separator: true) }
}

/// Keeps native menu items (and their tracking/highlight state) alive across polls.
/// Identical snapshots do not send any changes to AppKit.
public final class StableMenu {
    private let menu: NSMenu
    private var entries = [MenuEntry]()
    private var items = [String: NSMenuItem]()
    private var images = [String: NSImage]()
    private weak var target: AnyObject?

    public init(menu: NSMenu) { self.menu = menu }

    public func update(_ entries: [MenuEntry], target: AnyObject) {
        guard self.entries != entries || self.target !== target else { return }
        let wanted = Set(entries.map(\.id))
        for id in Array(items.keys) where !wanted.contains(id) {
            if let item = items.removeValue(forKey: id) { menu.removeItem(item) }
        }
        for (index, entry) in entries.enumerated() {
            let item: NSMenuItem
            if let existing = items[entry.id] {
                item = existing
            } else {
                item = entry.separator ? .separator() : NSMenuItem()
                items[entry.id] = item
            }
            if menu.index(of: item) != index {
                if item.menu === menu { menu.removeItem(item) }
                menu.insertItem(item, at: index)
            }
            guard !entry.separator else { continue }
            if item.title != entry.title { item.title = entry.title }
            if item.action != entry.action { item.action = entry.action }
            if item.target !== target { item.target = target }
            if item.keyEquivalent != entry.keyEquivalent { item.keyEquivalent = entry.keyEquivalent }
            if item.state != entry.state { item.state = entry.state }
            if item.isEnabled != entry.enabled { item.isEnabled = entry.enabled }
            if item.indentationLevel != entry.indentationLevel { item.indentationLevel = entry.indentationLevel }
            let icon = entry.symbol.flatMap { name -> NSImage? in
                if let existing = images[name] { return existing }
                let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
                image?.isTemplate = true
                images[name] = image
                return image
            }
            if entry.style == .toggle {
                let row: SwitchMenuRow
                if let existing = item.view as? SwitchMenuRow { row = existing }
                else {
                    row = SwitchMenuRow(item: item)
                    item.view = row
                }
                if item.image != nil { item.image = nil }
                row.updateStatus(subtitle: entry.subtitle, image: icon)
                row.update()
            } else {
                if item.view != nil { item.view = nil }
                if item.image !== icon { item.image = icon }
            }
        }
        self.entries = entries
        self.target = target
    }
}
