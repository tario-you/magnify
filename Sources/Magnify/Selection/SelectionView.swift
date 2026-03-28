import AppKit

@MainActor
final class SelectionView: NSView {
    struct ResizeEdge: OptionSet {
        let rawValue: Int

        static let left = ResizeEdge(rawValue: 1 << 0)
        static let right = ResizeEdge(rawValue: 1 << 1)
        static let top = ResizeEdge(rawValue: 1 << 2)
        static let bottom = ResizeEdge(rawValue: 1 << 3)
    }

    private enum Interaction {
        case move
        case resize(ResizeEdge)
    }

    private let borderInset: CGFloat = 8
    private let cornerRadius: CGFloat = 16
    private let resizeHandleThickness: CGFloat = 12
    private let minimumSize = CGSize(width: 220, height: 140)

    private var activeInteraction: Interaction?
    private var initialFrame: CGRect = .zero
    private var initialMouseLocation: CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        let insetBounds = bounds.insetBy(dx: borderInset / 2, dy: borderInset / 2)
        let path = NSBezierPath(roundedRect: insetBounds, xRadius: cornerRadius, yRadius: cornerRadius)

        NSColor.white.withAlphaComponent(0.10).setFill()
        path.fill()

        path.lineWidth = 2
        NSColor.white.withAlphaComponent(0.72).setStroke()
        path.stroke()

        let innerPath = NSBezierPath(roundedRect: insetBounds.insetBy(dx: 5, dy: 5), xRadius: cornerRadius - 4, yRadius: cornerRadius - 4)
        innerPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.16).setStroke()
        innerPath.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)

        let leftRect = CGRect(x: 0, y: resizeHandleThickness, width: resizeHandleThickness, height: bounds.height - (resizeHandleThickness * 2))
        let rightRect = CGRect(x: bounds.maxX - resizeHandleThickness, y: resizeHandleThickness, width: resizeHandleThickness, height: bounds.height - (resizeHandleThickness * 2))
        let topRect = CGRect(x: resizeHandleThickness, y: bounds.maxY - resizeHandleThickness, width: bounds.width - (resizeHandleThickness * 2), height: resizeHandleThickness)
        let bottomRect = CGRect(x: resizeHandleThickness, y: 0, width: bounds.width - (resizeHandleThickness * 2), height: resizeHandleThickness)

        addCursorRect(leftRect, cursor: .resizeLeftRight)
        addCursorRect(rightRect, cursor: .resizeLeftRight)
        addCursorRect(topRect, cursor: .resizeUpDown)
        addCursorRect(bottomRect, cursor: .resizeUpDown)

        addCursorRect(CGRect(x: 0, y: bounds.maxY - resizeHandleThickness, width: resizeHandleThickness, height: resizeHandleThickness), cursor: .crosshair)
        addCursorRect(CGRect(x: bounds.maxX - resizeHandleThickness, y: 0, width: resizeHandleThickness, height: resizeHandleThickness), cursor: .crosshair)
        addCursorRect(CGRect(x: 0, y: 0, width: resizeHandleThickness, height: resizeHandleThickness), cursor: .crosshair)
        addCursorRect(CGRect(x: bounds.maxX - resizeHandleThickness, y: bounds.maxY - resizeHandleThickness, width: resizeHandleThickness, height: resizeHandleThickness), cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        initialFrame = window.frame
        initialMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        activeInteraction = interaction(for: convert(event.locationInWindow, from: nil))

        if case .move = activeInteraction {
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let activeInteraction else {
            return
        }

        let currentLocation = window.convertPoint(toScreen: event.locationInWindow)
        let delta = CGPoint(
            x: currentLocation.x - initialMouseLocation.x,
            y: currentLocation.y - initialMouseLocation.y
        )

        let newFrame: CGRect
        switch activeInteraction {
        case .move:
            newFrame = CGRect(
                x: initialFrame.origin.x + delta.x,
                y: initialFrame.origin.y + delta.y,
                width: initialFrame.width,
                height: initialFrame.height
            )
        case .resize(let edges):
            newFrame = resizedFrame(from: initialFrame, delta: delta, edges: edges)
        }

        window.setFrame(newFrame.integral, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if case .move = activeInteraction {
            NSCursor.pop()
        }

        activeInteraction = nil
    }

    private func interaction(for point: CGPoint) -> Interaction {
        var edges: ResizeEdge = []

        if point.x <= resizeHandleThickness {
            edges.insert(.left)
        }
        if point.x >= bounds.width - resizeHandleThickness {
            edges.insert(.right)
        }
        if point.y <= resizeHandleThickness {
            edges.insert(.bottom)
        }
        if point.y >= bounds.height - resizeHandleThickness {
            edges.insert(.top)
        }

        return edges.isEmpty ? .move : .resize(edges)
    }

    private func resizedFrame(from frame: CGRect, delta: CGPoint, edges: ResizeEdge) -> CGRect {
        var newFrame = frame

        if edges.contains(.left) {
            newFrame.origin.x += delta.x
            newFrame.size.width -= delta.x
        }
        if edges.contains(.right) {
            newFrame.size.width += delta.x
        }
        if edges.contains(.bottom) {
            newFrame.origin.y += delta.y
            newFrame.size.height -= delta.y
        }
        if edges.contains(.top) {
            newFrame.size.height += delta.y
        }

        if newFrame.width < minimumSize.width {
            if edges.contains(.left) {
                newFrame.origin.x = frame.maxX - minimumSize.width
            }
            newFrame.size.width = minimumSize.width
        }

        if newFrame.height < minimumSize.height {
            if edges.contains(.bottom) {
                newFrame.origin.y = frame.maxY - minimumSize.height
            }
            newFrame.size.height = minimumSize.height
        }

        return newFrame
    }
}
