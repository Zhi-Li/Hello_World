import SwiftUI
import AppKit
import Combine

// AppKit owns the status item and window lifecycle so the same UI works on Monterey.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var ownerWindow: NSWindow!
    private var statusItem: NSStatusItem!
    private var tooltipSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeWindow()
        makeMenus()
        tooltipSubscription = model.$menuBarTooltip.sink { [weak self] text in
            self?.statusItem.button?.toolTip = text
        }
        if !CommandLine.arguments.contains("--background") { showOwnerControls(nil) }
    }

    private func makeWindow() {
        let content = OwnerView().environmentObject(model)
            .frame(minWidth: 800, minHeight: 650)
        ownerWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        ownerWindow.title = "ScreenGate · Owner controls"
        ownerWindow.contentMinSize = NSSize(width: 800, height: 650)
        ownerWindow.isReleasedWhenClosed = false
        ownerWindow.delegate = self
        ownerWindow.contentView = NSHostingView(rootView: content)
        ownerWindow.center()
    }

    private func makeMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "ScreenGate")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = model.menuBarTooltip
        let statusMenu = NSMenu()
        let heading = NSMenuItem(title: "ScreenGate", action: nil, keyEquivalent: "")
        heading.isEnabled = false; statusMenu.addItem(heading)
        statusMenu.addItem(menuItem("Open owner controls…", action: #selector(showOwnerControls(_:))))
        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Stop & Quit…", action: #selector(stopAndQuit(_:))))
        statusItem.menu = statusMenu

        // Supply an Edit menu so password/text fields support the usual Mac shortcuts.
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "ScreenGate")
        applicationMenu.addItem(menuItem("Open owner controls…", action: #selector(showOwnerControls(_:))))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem("Stop & Quit ScreenGate…", action: #selector(stopAndQuit(_:)), key: "q"))
        applicationItem.submenu = applicationMenu; mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        let closeItem = NSMenuItem(title: "Close owner controls", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = ownerWindow; windowMenu.addItem(closeItem)
        windowItem.submenu = windowMenu; mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; return item
    }
    @objc private func showOwnerControls(_ sender: Any?) {
        ownerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func stopAndQuit(_ sender: Any?) {
        showOwnerControls(nil); model.requestQuit()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOwnerControls(nil); return true
    }
    func applicationDidResignActive(_ notification: Notification) { model.lock() }
    func windowWillClose(_ notification: Notification) { model.lock() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.quitAuthorized { return .terminateNow }
        stopAndQuit(nil); return .terminateCancel
    }
}

@main @MainActor struct ScreenGateApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
