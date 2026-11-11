import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var panel: SwitcherPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = SwitcherPanel()
        self.panel = panel

        setUpStatusItem()

        // Option+Tab. Phase 1: toggles the panel. Phase 2: will advance the selection.
        hotKey = HotKey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)) { [weak self] in
            self?.toggleSwitcher()
        }
        if hotKey == nil {
            NSLog("SimpleTaskSwitcher: failed to register Option+Tab hotkey")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Simple Task Switcher")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        // Target nil: the action travels the responder chain and reaches NSApplication.terminate(_:).
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    @objc private func showSwitcher(_ sender: Any?) {
        panel?.show(appNames: runningAppNames())
    }

    // MARK: - Switcher

    private func toggleSwitcher() {
        guard let panel else { return }
        if panel.isVisible {
            panel.dismiss()
        } else {
            panel.show(appNames: runningAppNames())
        }
    }

    /// Regular (Dock-visible) apps, excluding ourselves. No MRU order yet: whatever order
    /// NSWorkspace returns (not documented; observed to be roughly launch order).
    private func runningAppNames() -> [String] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map { $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)" }
    }
}
