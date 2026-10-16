import AppKit

@MainActor final class ScreenTimeHoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Track the button itself, leaving AppKit's normal status-menu click handling
// intact. A nonactivating panel works even when another application is active.
@MainActor public final class MenuBarHoverController: NSObject, NSMenuDelegate {
    private weak var button: NSStatusBarButton?
    private weak var menu: NSMenu?
    private var trackingArea: NSTrackingArea?
    private var pointerInside = false
    private var menuOpen = false
    private let label = NSTextField(wrappingLabelWithString: "")
    let panel = ScreenTimeHoverPanel(contentRect: NSRect(x: 0, y: 0, width: 316, height: 80),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    public var onHover: (() -> Void)?
    public var isVisible: Bool { panel.isVisible }
    var displayedText: String { label.stringValue }

    public init(button: NSStatusBarButton, menu: NSMenu, text: String) {
        self.button = button; self.menu = menu
        super.init()
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.material = .popover; background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 9
        background.layer?.masksToBounds = true
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.isSelectable = false
        background.addSubview(label)
        panel.contentView = background
        // No periodically reassigned native tooltip to compete with the panel.
        button.toolTip = nil
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        button.addTrackingArea(area); trackingArea = area
        menu.delegate = self
        update(text: text)
    }

    public func update(text: String) {
        label.stringValue = text
        let height = ceil(label.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: 288, height: 1000)).height ?? 80)
        panel.setContentSize(NSSize(width: 316, height: max(44, height + 24)))
        label.frame = NSRect(x: 14, y: 12, width: 288, height: height)
        button?.setAccessibilityHelp(text)
        if panel.isVisible { positionPanel() }
    }

    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        pointerInside = true
        guard !menuOpen else { return }
        onHover?()
        guard positionPanel() else { return }
        panel.orderFrontRegardless()
    }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        pointerInside = false; panel.orderOut(nil)
    }
    public func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true; panel.orderOut(nil)
    }
    public func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    @discardableResult private func positionPanel() -> Bool {
        guard pointerInside, !menuOpen, let button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            panel.orderOut(nil); return false
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrame(Self.popupFrame(anchor: anchor, screen: screen.visibleFrame,
            size: panel.frame.size), display: true)
        return true
    }
    static func popupFrame(anchor: NSRect, screen: NSRect, size: NSSize) -> NSRect {
        let width = min(size.width, max(1, screen.width - 16))
        let height = min(size.height, max(1, screen.height - 16))
        let x = min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = min(max(anchor.minY - height - 6, screen.minY + 8), screen.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    public func invalidate() {
        panel.orderOut(nil)
        if let area = trackingArea { button?.removeTrackingArea(area) }
        trackingArea = nil
        if menu?.delegate === self { menu?.delegate = nil }
        onHover = nil
    }
}
