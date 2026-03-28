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
        normalizeToDisplayAspect(display: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var frame: CGRect {
        window?.frame ?? .zero
    }

    func setFrame(_ frame: CGRect, display: Bool = true) {
        window?.setFrame(normalizedFrame(for: frame), display: display)
    }

    func show(activating: Bool) {
        guard let window else {
            return
        }

        normalizeToDisplayAspect(display: true)

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

    func normalizeToDisplayAspect(display: Bool) {
        guard let window else {
            return
        }

        let adjustedFrame = normalizedFrame(for: window.frame)
        guard adjustedFrame != window.frame.integral else {
            return
        }

        window.setFrame(adjustedFrame, display: display)
        onFrameChange?(adjustedFrame)
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChange?(frame)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        normalizeToDisplayAspect(display: true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onFrameChange?(frame)
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChange?(frame)
    }

    private func normalizedFrame(for frame: CGRect) -> CGRect {
        guard let screen = NSScreen.screenContainingLargestIntersection(with: frame) ?? NSScreen.main else {
            return frame.integral
        }

        let aspectRatio = screen.displayAspectRatio
        let aspectValue = aspectRatio.width / aspectRatio.height
        let maxFrame = screen.frame

        let heightFromWidth = frame.width / aspectValue
        let widthFromHeight = frame.height * aspectValue

        var size: CGSize
        if abs(heightFromWidth - frame.height) <= abs(widthFromHeight - frame.width) {
            size = CGSize(width: frame.width, height: heightFromWidth)
        } else {
            size = CGSize(width: widthFromHeight, height: frame.height)
        }

        if size.width > maxFrame.width {
            size.width = maxFrame.width
            size.height = size.width / aspectValue
        }

        if size.height > maxFrame.height {
            size.height = maxFrame.height
            size.width = size.height * aspectValue
        }

        let minimumWidth = max(CGFloat(220), CGFloat(140) * aspectValue)
        if size.width < minimumWidth {
            size.width = minimumWidth
            size.height = size.width / aspectValue
        }

        if size.height > maxFrame.height {
            size.height = maxFrame.height
            size.width = size.height * aspectValue
        }

        var adjustedFrame = CGRect(origin: .zero, size: size).centered(at: frame.center)
        adjustedFrame.origin.x = min(max(adjustedFrame.origin.x, maxFrame.minX), maxFrame.maxX - adjustedFrame.width)
        adjustedFrame.origin.y = min(max(adjustedFrame.origin.y, maxFrame.minY), maxFrame.maxY - adjustedFrame.height)

        return adjustedFrame.integral
    }
}

@MainActor
private final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
