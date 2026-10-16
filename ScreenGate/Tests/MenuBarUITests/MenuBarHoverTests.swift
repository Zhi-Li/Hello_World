import AppKit
import XCTest
@testable import MenuBarUI

final class MenuBarHoverTests: XCTestCase {
    @MainActor private func withHover(_ body: (NSStatusItem, MenuBarHoverController) throws -> Void) rethrows {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: 28)
        item.button!.title = "S"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Owner controls", action: nil, keyEquivalent: ""))
        item.menu = menu
        let controller = MenuBarHoverController(button: item.button!, menu: menu,
            text: "ScreenGate\nToday's screen time: 1m 00s\nIn-school: 0m 00s\nAfter-school: 1m 00s")
        defer { controller.invalidate(); NSStatusBar.system.removeStatusItem(item) }
        try body(item, controller)
    }
    @MainActor private func event(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }
    @MainActor func testTrackingWorksWhileInactiveAndKeepsNormalClickMenu() {
        withHover { item, controller in
            let area = item.button!.trackingAreas.first { $0.owner === controller }
            XCTAssertNotNil(area)
            XCTAssertTrue(area!.options.contains(.activeAlways))
            XCTAssertTrue(area!.options.contains(.inVisibleRect))
            XCTAssertTrue(area!.options.contains(.mouseEnteredAndExited))
            XCTAssertNil(item.button!.toolTip)
            XCTAssertNotNil(item.menu)
            XCTAssertEqual(item.menu?.items.first?.title, "Owner controls")
        }
    }
    @MainActor func testHoverShowsCurrentTextAndUpdatesWithoutClosing() {
        withHover { _, controller in
            var refreshes = 0
            controller.onHover = { refreshes += 1 }
            controller.mouseEntered(with: event(.mouseEntered))
            XCTAssertEqual(refreshes, 1)
            XCTAssertTrue(controller.isVisible)
            controller.update(text: "ScreenGate\nToday's screen time: 1m 02s\nIn-school: 0m 00s\nAfter-school: 1m 02s")
            XCTAssertTrue(controller.isVisible)
            XCTAssertTrue(controller.displayedText.contains("1m 02s"))
            controller.mouseExited(with: event(.mouseExited))
            XCTAssertFalse(controller.isVisible)
        }
    }
    @MainActor func testOpenClickMenuSuppressesHoverPanel() {
        withHover { item, controller in
            controller.mouseEntered(with: event(.mouseEntered))
            XCTAssertTrue(controller.isVisible)
            controller.menuWillOpen(item.menu!)
            XCTAssertFalse(controller.isVisible)
            controller.mouseEntered(with: event(.mouseEntered))
            XCTAssertFalse(controller.isVisible)
            controller.menuDidClose(item.menu!)
            controller.mouseEntered(with: event(.mouseEntered))
            XCTAssertTrue(controller.isVisible)
        }
    }
    @MainActor func testPanelCannotTakeFocusAndInvalidationRemovesTracking() {
        withHover { item, controller in
            XCTAssertFalse(controller.panel.canBecomeKey)
            XCTAssertFalse(controller.panel.canBecomeMain)
            XCTAssertTrue(controller.panel.ignoresMouseEvents)
            controller.mouseEntered(with: event(.mouseEntered))
            controller.invalidate()
            XCTAssertFalse(controller.isVisible)
            XCTAssertFalse(item.button!.trackingAreas.contains { $0.owner === controller })
        }
    }
    @MainActor func testPanelStaysBelowMenuBarAndInsideEitherDisplay() {
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 875),
                       NSRect(x: -1920, y: 200, width: 1920, height: 1055)] {
            for x in [screen.minX, screen.midX, screen.maxX - 28] {
                let anchor = NSRect(x: x, y: screen.maxY, width: 28, height: 25)
                let frame = MenuBarHoverController.popupFrame(anchor: anchor, screen: screen,
                    size: NSSize(width: 316, height: 140))
                XCTAssertTrue(screen.contains(frame))
                XCTAssertLessThan(frame.maxY, anchor.minY)
                XCTAssertEqual(frame.width, 316)
            }
        }
    }
}
