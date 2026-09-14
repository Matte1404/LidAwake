import AppKit
import XCTest
@testable import LidAwakeCore

final class StableMenuTests: XCTestCase {
    private let action = #selector(NSObject.description)

    func testRepeatedPollsDoNotMutateMenuOrReplaceItsItems() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        let entries: [MenuEntry] = [
            MenuEntry(id: "status", title: "On AC power · staying awake"),
            .separator("power-separator"),
            MenuEntry(id: "ac", title: "Connected to Power", action: action, state: .on, indentationLevel: 1, symbol: "powerplug.fill"),
            MenuEntry(id: "quit", title: "Quit", action: action)
        ]
        renderer.update(entries, target: self)
        let originalItems = menu.items
        let originalIcon = menu.items[2].image
        XCTAssertNotNil(originalIcon)
        var notifications = 0
        let observers = [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didChangeItemNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: menu, queue: nil) { _ in notifications += 1 }
        }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }
        for _ in 0..<5 { renderer.update(entries, target: self) }
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(menu.numberOfItems, originalItems.count)
        for (original, current) in zip(originalItems, menu.items) { XCTAssertTrue(original === current) }
        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertEqual(menu.items[2].indentationLevel, 1)
        XCTAssertTrue(menu.items[2].image === originalIcon)
    }

    func testDisablingDependentControlsPreservesTheirCheckmarksAndIndentation() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        func entries(enabled: Bool) -> [MenuEntry] {
            [MenuEntry(id: "enabled", title: "Enable LidAwake", action: action, state: enabled ? .on : .off),
             MenuEntry(id: "ac", title: "Connected to Power", action: action, state: .on, enabled: enabled, indentationLevel: 1),
             MenuEntry(id: "battery", title: "On Battery", action: action, enabled: enabled, indentationLevel: 1)]
        }
        renderer.update(entries(enabled: true), target: self)
        let original = menu.items
        for enabled in [false, true] {
            renderer.update(entries(enabled: enabled), target: self)
            XCTAssertTrue(menu.items[0].isEnabled)
            XCTAssertEqual(menu.items[0].state, enabled ? .on : .off)
            XCTAssertEqual(menu.items[1].state, .on)
            XCTAssertEqual(menu.items[2].state, .off)
            for index in 1...2 {
                XCTAssertTrue(menu.items[index] === original[index])
                XCTAssertEqual(menu.items[index].isEnabled, enabled)
                XCTAssertEqual(menu.items[index].indentationLevel, 1)
            }
        }
    }

    func testRealStateChangesUpdateExistingItemsWithoutMovingRows() {
        let menu = NSMenu()
        let renderer = StableMenu(menu: menu)
        renderer.update([
            MenuEntry(id: "status", title: "On AC power · staying awake"),
            MenuEntry(id: "ac", title: "Stay Awake on AC Power", action: action, state: .on)
        ], target: self)
        let original = menu.items
        renderer.update([
            MenuEntry(id: "status", title: "On battery · sleep enabled"),
            MenuEntry(id: "ac", title: "Stay Awake on AC Power", action: action, state: .off)
        ], target: self)
        XCTAssertTrue(menu.items[0] === original[0])
        XCTAssertTrue(menu.items[1] === original[1])
        XCTAssertEqual(menu.items[0].title, "On battery · sleep enabled")
        XCTAssertEqual(menu.items[1].state, .off)
    }

    func testErrorRowDoesNotRecreateOtherItems() {
        let menu = NSMenu()
        let renderer = StableMenu(menu: menu)
        let status = MenuEntry(id: "status", title: "Sleep enabled")
        let quit = MenuEntry(id: "quit", title: "Quit", action: action)
        renderer.update([status, quit], target: self)
        let original = menu.items
        renderer.update([status, MenuEntry(id: "error", title: "Needs attention"), quit], target: self)
        XCTAssertEqual(menu.numberOfItems, 3)
        XCTAssertTrue(menu.items[2] === original[1])
        renderer.update([status, quit], target: self)
        XCTAssertEqual(menu.numberOfItems, 2)
        XCTAssertTrue(menu.items[0] === original[0])
        XCTAssertTrue(menu.items[1] === original[1])
    }
}
