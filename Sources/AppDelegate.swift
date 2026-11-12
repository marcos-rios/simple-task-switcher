import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = Config()
    private var statusItem: NSStatusItem?
    private var forwardHotKey: HotKey?
    private var backwardHotKey: HotKey?
    private var panel: SwitcherPanel?

    /// PIDs ordered most-recently-activated first.
    private var mruPIDs: [pid_t] = []
    /// Apps shown in the panel, in the same order as its rows.
    private var shownApps: [NSRunningApplication] = []
    /// Polls NSEvent.modifierFlags while the switcher was opened by holding the modifier.
    private var modifierTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = SwitcherPanel()
        panel.onCommit = { [weak self] index in
            self?.stopModifierPolling()
            self?.activateShownApp(at: index)
        }
        panel.onCancel = { [weak self] in
            self?.stopModifierPolling()
            self?.shownApps = []
        }
        self.panel = panel

        setUpStatusItem()
        startTrackingActivations()
        applyConfig()
    }

    func applicationWillTerminate(_ notification: Notification) {
        forwardHotKey?.unregister()
        backwardHotKey?.unregister()
    }

    // MARK: - Config

    private func applyConfig() {
        config = Config.load()
        registerHotKeys()
        applyLaunchAtLogin()
    }

    /// Modifier+Tab opens the switcher / moves forward; Shift+Modifier+Tab moves backward.
    private func registerHotKeys() {
        forwardHotKey?.unregister()
        backwardHotKey?.unregister()

        let modifier = UInt32(config.hotKeyModifier == .option ? optionKey : controlKey)
        forwardHotKey = HotKey(keyCode: UInt32(kVK_Tab), modifiers: modifier) { [weak self] in
            self?.hotKeyPressed(step: 1)
        }
        backwardHotKey = HotKey(keyCode: UInt32(kVK_Tab), modifiers: modifier | UInt32(shiftKey)) { [weak self] in
            self?.hotKeyPressed(step: -1)
        }
        let name = config.hotKeyModifier.rawValue
        if forwardHotKey == nil { log("failed to register \(name)+Tab hotkey") }
        if backwardHotKey == nil { log("failed to register shift+\(name)+Tab hotkey") }
    }

    private var modifierFlag: NSEvent.ModifierFlags {
        config.hotKeyModifier == .option ? .option : .control
    }

    /// Only acts when running from /Applications, so a build in DerivedData never
    /// becomes a login item.
    private func applyLaunchAtLogin() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            if config.launchAtLogin {
                log("launch-at-login ignored: the app is not running from /Applications")
            }
            return
        }
        let service = SMAppService.mainApp
        do {
            if config.launchAtLogin, service.status != .enabled {
                try service.register()
            } else if !config.launchAtLogin, service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            log("launch-at-login: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval {
            log("launch-at-login needs approval in System Settings > General > Login Items")
        }
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
        menu.addItem(menuItem("Show Switcher", #selector(showSwitcher(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Config", #selector(openConfig(_:))))
        menu.addItem(menuItem("Reload Config", #selector(reloadConfig(_:))))
        menu.addItem(.separator())
        // Target nil: the action travels the responder chain and reaches NSApplication.terminate(_:).
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Opened from the menu, the modifier is not held: the panel stays open until Enter, Esc or a click outside.
    @objc private func showSwitcher(_ sender: Any?) {
        openSwitcher(step: 1)
    }

    /// Creates the file with every key commented out if needed, then opens it.
    @objc private func openConfig(_ sender: Any?) {
        let url = Config.url
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try Config.template.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log("could not create config: \(error.localizedDescription)")
                return
            }
        }
        let workspace = NSWorkspace.shared
        // A file without extension may have no default app: fall back to TextEdit.
        if workspace.urlForApplication(toOpen: url) != nil {
            workspace.open(url)
        } else if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            workspace.open([url], withApplicationAt: textEdit,
                           configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    @objc private func reloadConfig(_ sender: Any?) {
        panel?.cancel()
        applyConfig()
    }

    // MARK: - MRU tracking

    private func startTrackingActivations() {
        if let front = NSWorkspace.shared.frontmostApplication {
            mruPIDs = [front.processIdentifier]
        }
        // NSWorkspace posts these on its own notification center (not NotificationCenter.default),
        // on the main thread.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDidActivate(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidTerminate(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func appDidActivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        moveToFront(app.processIdentifier)
    }

    @objc private func appDidTerminate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        mruPIDs.removeAll { $0 == app.processIdentifier }
    }

    private func moveToFront(_ pid: pid_t) {
        mruPIDs.removeAll { $0 == pid }
        mruPIDs.insert(pid, at: 0)
    }

    /// Regular (Dock-visible) apps, excluding ourselves and filtered by the config,
    /// most recently used first. Apps never seen activating keep NSWorkspace's order, after the known ones.
    private func orderedApps() -> [NSRunningApplication] {
        // Safety net in case a notification was missed: the frontmost app is always first.
        if let front = NSWorkspace.shared.frontmostApplication {
            moveToFront(front.processIdentifier)
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Only query the window server when the filter is on.
        let pidsWithWindows: Set<pid_t>? = config.showWindowlessApps
            ? nil
            : Set(windows([.optionAll, .excludeDesktopElements]).map(\.pid))

        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, app.processIdentifier != ownPID else { return false }
            if let id = app.bundleIdentifier, config.exclude.contains(id) { return false }
            if app.isHidden { return config.showHiddenApps }
            // Hidden apps are handled above, so the window heuristic never decides them.
            if let pidsWithWindows, !pidsWithWindows.contains(app.processIdentifier) { return false }
            return true
        }

        var rank: [pid_t: Int] = [:]
        for (index, pid) in mruPIDs.enumerated() { rank[pid] = index }

        return apps.enumerated()
            .sorted { a, b in
                let ra = rank[a.element.processIdentifier] ?? Int.max
                let rb = rank[b.element.processIdentifier] ?? Int.max
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: - Windows (CGWindowList: owner PID, layer and bounds need no permission; titles would)

    private struct WindowInfo {
        let pid: pid_t
        let bounds: CGRect // global coordinates, origin at the top-left of the primary screen
    }

    /// Normal app windows (layer 0), ignoring invisible or tiny helper windows.
    /// With .optionOnScreenOnly the order is front to back.
    private func windows(_ options: CGWindowListOption) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  bounds.width >= 50, bounds.height >= 50
            else { return nil }
            return WindowInfo(pid: pid, bounds: bounds)
        }
    }

    private func targetScreen() -> NSScreen? {
        if config.screen == .focused,
           let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let window = windows([.optionOnScreenOnly, .excludeDesktopElements]).first(where: { $0.pid == pid }),
           let screen = screen(containing: window.bounds) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Screen with the largest overlap with a window given in CoreGraphics coordinates.
    private func screen(containing cgRect: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        // Cocoa's origin is the bottom-left of the primary screen, with y pointing up.
        let rect = CGRect(x: cgRect.minX, y: primary.frame.height - cgRect.maxY,
                          width: cgRect.width, height: cgRect.height)
        func overlap(_ screen: NSScreen) -> CGFloat {
            let area = screen.frame.intersection(rect)
            return area.isNull ? 0 : area.width * area.height
        }
        guard let best = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 else { return nil }
        return best
    }

    // MARK: - Switcher

    private func hotKeyPressed(step: Int) {
        guard let panel else { return }
        if panel.isShowing {
            panel.moveSelection(by: step)
        } else {
            openSwitcher(step: step)
        }
        // The modifier is part of the hotkey, so it is held right now: commit when it is released.
        startModifierPolling()
    }

    /// Forward opens on the 2nd app (like Cmd+Tab); backward opens on the last one.
    private func openSwitcher(step: Int) {
        guard let panel else { return }
        shownApps = orderedApps()
        let initial: Int
        if shownApps.count < 2 {
            initial = 0
        } else {
            initial = step > 0 ? 1 : shownApps.count - 1
        }
        let names = shownApps.map { $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)" }
        panel.show(names: names, selectedIndex: initial,
                   fontSize: CGFloat(config.fontSize), on: targetScreen())
    }

    // MARK: - Modifier release detection

    private func startModifierPolling() {
        guard modifierTimer == nil else { return }
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so it fires on the main thread.
            MainActor.assumeIsolated {
                self?.checkModifiers()
            }
        }
        // .common so it keeps firing during event tracking (e.g. while a menu is open).
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private func stopModifierPolling() {
        modifierTimer?.invalidate()
        modifierTimer = nil
    }

    private func checkModifiers() {
        // Class property: current modifier state, no permissions required.
        if !NSEvent.modifierFlags.contains(modifierFlag) {
            stopModifierPolling()
            panel?.commit()
        }
    }

    // MARK: - Activation

    private func activateShownApp(at index: Int) {
        guard shownApps.indices.contains(index) else { return }
        let app = shownApps[index]
        shownApps = []
        guard !app.isTerminated else { return }

        let pid = app.processIdentifier
        let bundleURL = app.bundleURL
        let name = app.localizedName ?? "pid \(pid)"

        if app.isHidden {
            app.unhide()
        } else if !windows([.optionOnScreenOnly, .excludeDesktopElements]).contains(where: { $0.pid == pid }) {
            // No window visible in this Space: minimized, in another Space (e.g. full screen),
            // or no windows at all. Do what a Dock click does: activate + "reopen", which
            // de-minimizes a window in AppKit apps. De-minimizing directly needs Accessibility.
            openWithWorkspace(bundleURL)
            return
        }

        // Since macOS 14 activation is cooperative: YES only means the system accepted the
        // request, not that the app came to the front. Verify, then fall back.
        guard app.activate(options: [.activateAllWindows]) else {
            log("activate() refused for \(name); using openApplication")
            openWithWorkspace(bundleURL)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                log("\(name) not frontmost after activate(); using openApplication")
                self?.openWithWorkspace(bundleURL)
            }
        }
    }

    /// Public fallback: same path as clicking the app in the Dock. Side effect: an app with no
    /// open windows may create a new one (it receives a "reopen" event).
    private func openWithWorkspace(_ bundleURL: URL?) {
        guard let bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                log("openApplication failed: \(error.localizedDescription)")
            }
        }
    }
}

nonisolated func log(_ message: String) {
    NSLog("SimpleTaskSwitcher: %@", message)
}
