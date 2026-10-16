import AppKit

// Fixed read-only rows update in place while the status menu is open. The
// ordinary owner-control actions remain in the same menu below these rows.
@MainActor public final class MenuBarUsageController: NSObject, NSMenuDelegate {
    private weak var menu: NSMenu?
    private let rows: [NSMenuItem]
    public var onOpen: (() -> Void)?

    public init(menu: NSMenu, insertionIndex: Int, summary: String) {
        self.menu = menu
        rows = (0..<5).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
        super.init()
        for (index, row) in rows.enumerated() {
            row.isEnabled = false
            row.indentationLevel = index == 0 ? 0 : 1
            menu.insertItem(row, at: insertionIndex + index)
        }
        menu.delegate = self
        update(summary: summary)
    }

    public func update(summary: String) {
        let lines = Array(summary.components(separatedBy: "\n").dropFirst().filter { !$0.isEmpty })
        for (index, row) in rows.enumerated() {
            let value = index < lines.count ? lines[index] : nil
            row.title = value ?? ""
            row.isHidden = value == nil
        }
        menu?.update()
    }
    public func menuWillOpen(_ menu: NSMenu) { onOpen?() }

    public func invalidate() {
        if menu?.delegate === self { menu?.delegate = nil }
        if let menu {
            for row in rows where row.menu === menu { menu.removeItem(row) }
        }
        onOpen = nil
    }
}
