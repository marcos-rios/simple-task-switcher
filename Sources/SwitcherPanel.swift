import AppKit
import Carbon.HIToolbox

/// Floating, non-activating panel listing app names with one selected row.
/// It can become key (to receive keys) without activating our app.
@MainActor
final class SwitcherPanel: NSPanel {
    /// Called with the selected row index when the user confirms.
    var onCommit: ((Int) -> Void)?
    /// Called when the panel closes without choosing (Esc, click outside).
    var onCancel: (() -> Void)?

    private(set) var isShowing = false
    private(set) var selectedIndex = 0

    private let stackView = NSStackView()
    private var rows: [NSView] = []
    private var labels: [NSTextField] = []
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
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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

    // Borderless windows refuse key status by default; we need it to receive keys.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Showing

    func show(names: [String], selectedIndex: Int, fontSize: CGFloat, on screen: NSScreen?) {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        labels = []

        let items = names.isEmpty ? ["(no apps)"] : names
        for name in items {
            let (row, label) = makeRow(name, fontSize: fontSize)
            stackView.addArrangedSubview(row)
            // Full-width rows so the selection highlight spans the panel.
            row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 8).isActive = true
            row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -8).isActive = true
            rows.append(row)
            labels.append(label)
        }
        self.selectedIndex = min(max(selectedIndex, 0), items.count - 1)
        updateHighlight()

        if let contentView {
            contentView.layoutSubtreeIfNeeded()
            setContentSize(contentView.fittingSize)
        }
        center(on: screen)
        isShowing = true
        makeKeyAndOrderFront(nil)
    }

    private func makeRow(_ text: String, fontSize: CGFloat) -> (NSView, NSTextField) {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: fontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
        ])
        return (row, label)
    }

    /// The caller picks the screen (mouse or focused window, per config).
    private func center(on screen: NSScreen?) {
        guard let area = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }

    // MARK: - Selection

    /// Moves the selection, wrapping around at both ends (like Cmd+Tab).
    func moveSelection(by delta: Int) {
        guard isShowing, !rows.isEmpty else { return }
        let count = rows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        updateHighlight()
    }

    private func updateHighlight() {
        for (index, row) in rows.enumerated() {
            let selected = index == selectedIndex
            row.layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.cgColor : nil
            labels[index].textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        }
    }

    // MARK: - Closing

    func commit() {
        guard finish() else { return }
        onCommit?(selectedIndex)
    }

    func cancel() {
        guard finish() else { return }
        onCancel?()
    }

    /// Returns false if already closed. Clears `isShowing` before `orderOut`, which triggers
    /// `resignKey` re-entrantly: that call then becomes a no-op.
    private func finish() -> Bool {
        guard isShowing else { return false }
        isShowing = false
        orderOut(nil)
        return true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commit()
        case kVK_DownArrow:
            moveSelection(by: 1)
        case kVK_UpArrow:
            moveSelection(by: -1)
        case kVK_Tab:
            // Plain Tab when opened from the menu; also catches Shift+Option+Tab if
            // that hotkey never reaches us (the panel is key, so the key lands here).
            moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        default:
            break // swallow other keys (no beep)
        }
    }

    // Esc can also arrive as the standard "cancel" action.
    override func cancelOperation(_ sender: Any?) {
        cancel()
    }

    // Clicking another app (or anywhere outside) takes key status away: cancel.
    override func resignKey() {
        super.resignKey()
        cancel()
    }
}
