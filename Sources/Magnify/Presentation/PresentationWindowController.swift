import AppKit

@MainActor
final class PresentationWindowController: NSWindowController {
    private let presentationView = PresentationView(frame: .zero)

    init() {
        let window = PresentationWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.contentView = presentationView

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(on screen: NSScreen) {
        guard let window else {
            return
        }

        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func update(image: CGImage?) {
        presentationView.update(image: image)
    }
}

private final class PresentationWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
