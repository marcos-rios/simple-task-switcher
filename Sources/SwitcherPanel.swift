import AppKit
import Carbon.HIToolbox

/// Floating, non-activating panel listing app names.
/// It can become key (to receive Esc) without activating our app.
@MainActor
final class SwitcherPanel: NSPanel {
    private let stackView = NSStackView()
    private let minWidth: CGFloat = 280

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)

        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false      // our app is never active; don't tie visibility to that
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: background.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stackView.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
        ])
        contentView = background
    }

    // Borderless windows refuse key status by default; we need it to receive Esc.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(appNames: [String]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let names = appNames.isEmpty ? ["(no apps)"] : appNames
        for name in names {
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 15)
            label.lineBreakMode = .byTruncatingTail
            stackView.addArrangedSubview(label)
        }

        if let contentView {
            contentView.layoutSubtreeIfNeeded()
            setContentSize(contentView.fittingSize)
        }
        centerOnMouseScreen()
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }

    /// Phase 1 uses the screen under the mouse pointer (refined in phase 3).
    private func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }

    // MARK: - Closing

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            dismiss()
        } else {
            super.keyDown(with: event)
        }
    }

    // Esc can also arrive as the standard "cancel" action.
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    // Clicking another app (or anywhere outside) takes key status away: close.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }
}
