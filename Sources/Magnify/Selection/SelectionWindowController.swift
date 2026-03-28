import AppKit

@MainActor
final class SelectionWindowController: NSWindowController, NSWindowDelegate {
    var onFrameChange: ((CGRect) -> Void)?

    private let selectionView = SelectionView(frame: .zero)

    init(initialFrame: CGRect) {
        let window = SelectionWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = selectionView

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var frame: CGRect {
        window?.frame ?? .zero
    }

    func setFrame(_ frame: CGRect, display: Bool = true) {
        window?.setFrame(frame.integral, display: display)
    }

    func show(activating: Bool) {
        guard let window else {
            return
        }

        if activating {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChange?(frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onFrameChange?(frame)
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChange?(frame)
    }
}

@MainActor
private final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
