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
        let aspectRatio = currentAspectRatio(for: frame)
        let aspectValue = aspectRatio.width / aspectRatio.height
        let screenFrame = NSScreen.screenContainingLargestIntersection(with: frame)?.frame ?? NSScreen.main?.frame ?? frame

        let maxWidth = screenFrame.width
        let maxHeight = screenFrame.height
        let minimumWidth = max(minimumSize.width, minimumSize.height * aspectValue)
        let minimumHeight = minimumWidth / aspectValue

        let hasHorizontalEdge = edges.intersection([.left, .right]).isEmpty == false
        let hasVerticalEdge = edges.intersection([.top, .bottom]).isEmpty == false

        switch (hasHorizontalEdge, hasVerticalEdge) {
        case (true, true):
            return resizedFromCorner(
                frame: frame,
                delta: delta,
                edges: edges,
                aspectValue: aspectValue,
                minimumWidth: minimumWidth,
                minimumHeight: minimumHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                screenFrame: screenFrame
            )
        case (true, false):
            return resizedFromHorizontalEdge(
                frame: frame,
                delta: delta,
                edges: edges,
                aspectValue: aspectValue,
                minimumWidth: minimumWidth,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                screenFrame: screenFrame
            )
        case (false, true):
            return resizedFromVerticalEdge(
                frame: frame,
                delta: delta,
                edges: edges,
                aspectValue: aspectValue,
                minimumHeight: minimumHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                screenFrame: screenFrame
            )
        case (false, false):
            return frame
        }
    }

    private func currentAspectRatio(for frame: CGRect) -> CGSize {
        NSScreen.screenContainingLargestIntersection(with: frame)?.displayAspectRatio
            ?? NSScreen.main?.displayAspectRatio
            ?? CGSize(width: 16, height: 10)
    }

    private func resizedFromHorizontalEdge(
        frame: CGRect,
        delta: CGPoint,
        edges: ResizeEdge,
        aspectValue: CGFloat,
        minimumWidth: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let widthDelta = edges.contains(.left) ? -delta.x : delta.x
        var width = max(frame.width + widthDelta, minimumWidth)
        width = min(width, maxWidth)

        var height = width / aspectValue
        if height > maxHeight {
            height = maxHeight
            width = height * aspectValue
        }

        let x = edges.contains(.left) ? frame.maxX - width : frame.minX
        let y = frame.midY - (height / 2)

        return clampedFrame(
            CGRect(x: x, y: y, width: width, height: height),
            to: screenFrame
        )
    }

    private func resizedFromVerticalEdge(
        frame: CGRect,
        delta: CGPoint,
        edges: ResizeEdge,
        aspectValue: CGFloat,
        minimumHeight: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let heightDelta = edges.contains(.bottom) ? -delta.y : delta.y
        var height = max(frame.height + heightDelta, minimumHeight)
        height = min(height, maxHeight)

        var width = height * aspectValue
        if width > maxWidth {
            width = maxWidth
            height = width / aspectValue
        }

        let x = frame.midX - (width / 2)
        let y = edges.contains(.bottom) ? frame.maxY - height : frame.minY

        return clampedFrame(
            CGRect(x: x, y: y, width: width, height: height),
            to: screenFrame
        )
    }

    private func resizedFromCorner(
        frame: CGRect,
        delta: CGPoint,
        edges: ResizeEdge,
        aspectValue: CGFloat,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let proposedWidth = frame.width + (edges.contains(.left) ? -delta.x : delta.x)
        let proposedHeight = frame.height + (edges.contains(.bottom) ? -delta.y : delta.y)
        let normalizedWidthChange = abs((proposedWidth - frame.width) / max(frame.width, 1))
        let normalizedHeightChange = abs((proposedHeight - frame.height) / max(frame.height, 1))
        let shouldDriveFromWidth = normalizedWidthChange >= normalizedHeightChange

        var width: CGFloat
        var height: CGFloat

        if shouldDriveFromWidth {
            width = max(proposedWidth, minimumWidth)
            width = min(width, maxWidth)
            height = width / aspectValue
            if height > maxHeight {
                height = maxHeight
                width = height * aspectValue
            }
        } else {
            height = max(proposedHeight, minimumHeight)
            height = min(height, maxHeight)
            width = height * aspectValue
            if width > maxWidth {
                width = maxWidth
                height = width / aspectValue
            }
        }

        let x = edges.contains(.left) ? frame.maxX - width : frame.minX
        let y = edges.contains(.bottom) ? frame.maxY - height : frame.minY

        return clampedFrame(
            CGRect(x: x, y: y, width: width, height: height),
            to: screenFrame
        )
    }

    private func clampedFrame(_ frame: CGRect, to screenFrame: CGRect) -> CGRect {
        let width = min(frame.width, screenFrame.width)
        let height = min(frame.height, screenFrame.height)
        let x = min(max(frame.minX, screenFrame.minX), screenFrame.maxX - width)
        let y = min(max(frame.minY, screenFrame.minY), screenFrame.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}
