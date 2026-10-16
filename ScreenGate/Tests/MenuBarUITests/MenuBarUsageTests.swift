import AppKit
import XCTest
@testable import MenuBarUI

final class MenuBarUsageTests: XCTestCase {
    @MainActor private func withMenu(_ body: (NSMenu, MenuBarUsageController, NSMenuItem) -> Void) {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "ScreenGate", action: nil, keyEquivalent: "")
        let controls = NSMenuItem(title: "Open owner controls…", action: nil, keyEquivalent: "")
        menu.addItem(heading); menu.addItem(.separator()); menu.addItem(controls)
        let controller = MenuBarUsageController(menu: menu, insertionIndex: 1,
            summary: "ScreenGate\nToday's screen time: 1m 00s\nIn-school: 0m 00s\nAfter-school: 1m 00s")
        defer { controller.invalidate() }
        body(menu, controller, controls)
    }
    @MainActor func testClickMenuShowsTotalAndBothModesAboveOwnerControls() {
        withMenu { menu, controller, controls in
            var refreshes = 0
            controller.onOpen = { refreshes += 1 }
            controller.menuWillOpen(menu)
            XCTAssertEqual(refreshes, 1)
            let visible = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
            XCTAssertEqual(visible, ["ScreenGate", "Today's screen time: 1m 00s", "In-school: 0m 00s",
                "After-school: 1m 00s", "Open owner controls…"])
            XCTAssertTrue(menu.items.last === controls)
            for row in menu.items[1...5] {
                XCTAssertFalse(row.isEnabled); XCTAssertNil(row.action); XCTAssertNil(row.target)
            }
        }
    }
    @MainActor func testRefreshUpdatesExistingRowsWhileMenuIsOpen() {
        withMenu { menu, controller, controls in
            let totalRow = menu.items[1], schoolRow = menu.items[2], afterRow = menu.items[3]
            controller.menuWillOpen(menu)
            controller.update(summary: "ScreenGate\nToday's screen time: 2m 03s\nIn-school: 1m 00s\nAfter-school: 1m 03s")
            XCTAssertTrue(menu.items[1] === totalRow)
            XCTAssertTrue(menu.items[2] === schoolRow)
            XCTAssertTrue(menu.items[3] === afterRow)
            XCTAssertEqual(totalRow.title, "Today's screen time: 2m 03s")
            XCTAssertEqual(schoolRow.title, "In-school: 1m 00s")
            XCTAssertEqual(afterRow.title, "After-school: 1m 03s")
            XCTAssertTrue(menu.items.last === controls)
        }
    }
    @MainActor func testUnavailableAndNotRecordedSummariesHideStaleModeRows() {
        withMenu { menu, controller, _ in
            for message in ["Unavailable", "Not recorded yet", "Updating…"] {
                controller.update(summary: "ScreenGate\nToday's screen time: \(message)")
                XCTAssertEqual(menu.items[1].title, "Today's screen time: \(message)")
                XCTAssertFalse(menu.items[1].isHidden)
                XCTAssertTrue(menu.items[2...5].allSatisfy(\.isHidden))
            }
        }
    }
    @MainActor func testScheduleGapAndEarlierUnsplitTimeAreVisibleOnlyWhenPresent() {
        withMenu { menu, controller, _ in
            controller.update(summary: "ScreenGate\nToday's screen time: 5m 00s\nIn-school: 1m 00s\nAfter-school: 1m 00s\nOutside scheduled modes: 1m 00s\nEarlier unsplit time: 2m 00s")
            XCTAssertEqual(menu.items[4].title, "Outside scheduled modes: 1m 00s")
            XCTAssertEqual(menu.items[5].title, "Earlier unsplit time: 2m 00s")
            XCTAssertFalse(menu.items[4].isHidden); XCTAssertFalse(menu.items[5].isHidden)
            controller.update(summary: "ScreenGate\nToday's screen time: 0m 00s\nIn-school: 0m 00s\nAfter-school: 0m 00s")
            XCTAssertTrue(menu.items[4].isHidden); XCTAssertTrue(menu.items[5].isHidden)
        }
    }
    @MainActor func testCleanupPreservesOwnerControlMenuItems() {
        withMenu { menu, controller, controls in
            controller.invalidate()
            XCTAssertNil(menu.delegate)
            XCTAssertEqual(menu.items.count, 3)
            XCTAssertTrue(menu.items.last === controls)
        }
    }
}
