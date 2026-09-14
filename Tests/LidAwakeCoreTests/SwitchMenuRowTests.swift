import AppKit
import XCTest
@testable import LidAwakeCore

final class SwitchMenuRowTests: XCTestCase {
    private final class Target: NSObject {
        var change: () -> Void = {}
        @objc func toggle() { change() }
    }

    private func entry(on: Bool, enabled: Bool = true) -> MenuEntry {
        MenuEntry(id: "enabled", title: "LidAwake", action: #selector(Target.toggle), keyEquivalent: "e",
                  state: on ? .on : .off, enabled: enabled, style: .toggle,
                  subtitle: "Staying awake · AC power", symbol: "cup.and.saucer.fill")
    }

    func testNativeSwitchHasAccessibleLabelAndStaysStableAcrossPolls() throws {
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([entry(on: true)], target: target)
        let item = try XCTUnwrap(menu.items.first)
        let row = try XCTUnwrap(item.view as? SwitchMenuRow)
        let statusIcon = try XCTUnwrap(row.subviews.compactMap { $0 as? NSImageView }.first)
        let originalImage = try XCTUnwrap(statusIcon.image)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertEqual(row.toggle.accessibilityLabel(), "LidAwake")
        let frame = row.frame
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didChangeItemNotification,
                                                              object: menu, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for _ in 0..<5 { renderer.update([entry(on: true)], target: target) }
        XCTAssertTrue(item.view === row)
        XCTAssertEqual(row.frame, frame)
        XCTAssertEqual(notifications, 0)
        XCTAssertTrue(statusIcon.image === originalImage)
    }

    func testClickKeepsRequestedPositionDuringWorkAndRollsBackOnFailure() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([entry(on: true)], target: target)
        let row = try XCTUnwrap(menu.items.first?.view as? SwitchMenuRow)
        var calls = 0
        target.change = {
            calls += 1
            renderer.update([self.entry(on: true, enabled: false)], target: target)
        }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(row.toggle.state, .off)
        XCTAssertFalse(row.toggle.isEnabled)
        renderer.update([entry(on: true)], target: target)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertTrue(row.toggle.isEnabled)
        // Canceling setup may return without starting a background operation.
        target.change = { calls += 1 }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(row.toggle.state, .on)
    }

    func testKeyboardEquivalentAndDisabledStateUseTheSameMenuAction() throws {
        _ = NSApplication.shared
        let target = Target(), menu = NSMenu()
        menu.autoenablesItems = false
        let renderer = StableMenu(menu: menu)
        renderer.update([entry(on: true, enabled: false)], target: target)
        let row = try XCTUnwrap(menu.items.first?.view as? SwitchMenuRow)
        XCTAssertEqual(row.toggle.state, .on)
        XCTAssertFalse(row.toggle.isEnabled)
        var calls = 0
        target.change = { calls += 1 }
        row.toggle.performClick(nil)
        XCTAssertEqual(calls, 0)
        renderer.update([entry(on: true)], target: target)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                 timestamp: 0, windowNumber: 0, context: nil,
                                                 characters: "e", charactersIgnoringModifiers: "e",
                                                 isARepeat: false, keyCode: 14))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertEqual(calls, 1)
    }
}
