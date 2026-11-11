import AppKit

// Manual entry point: no storyboard or nib. Top-level code in main.swift runs on
// the main thread; `assumeIsolated` tells the compiler so (and traps if it is not).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate          // `delegate` is weak; `run()` never returns, so this local keeps it alive.
    app.setActivationPolicy(.accessory) // Same effect as LSUIElement; harmless redundancy.
    app.run()
}
