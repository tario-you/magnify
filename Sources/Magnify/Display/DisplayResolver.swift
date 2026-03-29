import AppKit
import CoreGraphics

struct CaptureRequest: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    let pixelSize: CGSize
    let cropRectPixels: CGRect
}

struct DisplayTarget {
    let screen: NSScreen
    let captureRequest: CaptureRequest
}

@MainActor
final class DisplayResolver {
    func resolveDisplayTarget(for selectionFrame: CGRect, zoomFactor: CGFloat = 1.0) -> DisplayTarget? {
        guard
            let screen = NSScreen.screenContainingLargestIntersection(with: selectionFrame),
            let displayID = screen.displayID
        else {
            return nil
        }

        let intersection = selectionFrame.intersection(screen.frame)
        guard !intersection.isNull, !intersection.isEmpty else {
            return nil
        }

        let pixelWidth = CGFloat(CGDisplayPixelsWide(displayID))
        let pixelHeight = CGFloat(CGDisplayPixelsHigh(displayID))
        let scaleX = pixelWidth / screen.frame.width
        let scaleY = pixelHeight / screen.frame.height

        let clampedZoomFactor = max(1.0, zoomFactor)
        let zoomedIntersection = CGRect(
            x: intersection.midX - ((intersection.width / clampedZoomFactor) / 2),
            y: intersection.midY - ((intersection.height / clampedZoomFactor) / 2),
            width: intersection.width / clampedZoomFactor,
            height: intersection.height / clampedZoomFactor
        ).integral.clamped(to: intersection)

        let relativeRect = CGRect(
            x: zoomedIntersection.minX - screen.frame.minX,
            y: zoomedIntersection.minY - screen.frame.minY,
            width: zoomedIntersection.width,
            height: zoomedIntersection.height
        )

        let cropRect = CGRect(
            x: relativeRect.minX * scaleX,
            y: pixelHeight - ((relativeRect.minY + relativeRect.height) * scaleY),
            width: relativeRect.width * scaleX,
            height: relativeRect.height * scaleY
        ).integral.clamped(to: CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))

        guard cropRect.width >= 2, cropRect.height >= 2 else {
            return nil
        }

        return DisplayTarget(
            screen: screen,
            captureRequest: CaptureRequest(
                displayID: displayID,
                pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
                cropRectPixels: cropRect
            )
        )
    }

    func resolveCursorZoomTarget(for cursorLocation: CGPoint, zoomFactor: CGFloat) -> DisplayTarget? {
        guard
            let screen = NSScreen.screenContaining(cursorLocation),
            let displayID = screen.displayID
        else {
            return nil
        }

        return resolveCursorZoomTarget(on: screen, centerPoint: cursorLocation, zoomFactor: zoomFactor, displayID: displayID)
    }

    func resolveCursorZoomTarget(on screen: NSScreen, centerPoint: CGPoint, zoomFactor: CGFloat) -> DisplayTarget? {
        guard let displayID = screen.displayID else {
            return nil
        }

        return resolveCursorZoomTarget(on: screen, centerPoint: centerPoint, zoomFactor: zoomFactor, displayID: displayID)
    }

    private func resolveCursorZoomTarget(
        on screen: NSScreen,
        centerPoint: CGPoint,
        zoomFactor: CGFloat,
        displayID: CGDirectDisplayID
    ) -> DisplayTarget? {
        let pixelWidth = CGFloat(CGDisplayPixelsWide(displayID))
        let pixelHeight = CGFloat(CGDisplayPixelsHigh(displayID))
        let scaleX = pixelWidth / screen.frame.width
        let scaleY = pixelHeight / screen.frame.height

        let clampedZoomFactor = max(1.0, zoomFactor)
        let sourceWidth = screen.frame.width / clampedZoomFactor
        let sourceHeight = screen.frame.height / clampedZoomFactor

        let sourceRect = CGRect(
            x: centerPoint.x - (sourceWidth / 2),
            y: centerPoint.y - (sourceHeight / 2),
            width: sourceWidth,
            height: sourceHeight
        ).clampedCenterPreservingSize(to: screen.frame)

        let relativeRect = CGRect(
            x: sourceRect.minX - screen.frame.minX,
            y: sourceRect.minY - screen.frame.minY,
            width: sourceRect.width,
            height: sourceRect.height
        )

        let cropRect = CGRect(
            x: relativeRect.minX * scaleX,
            y: pixelHeight - ((relativeRect.minY + relativeRect.height) * scaleY),
            width: relativeRect.width * scaleX,
            height: relativeRect.height * scaleY
        ).integral.clamped(to: CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))

        guard cropRect.width >= 2, cropRect.height >= 2 else {
            return nil
        }

        return DisplayTarget(
            screen: screen,
            captureRequest: CaptureRequest(
                displayID: displayID,
                pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
                cropRectPixels: cropRect
            )
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var displayAspectRatio: CGSize {
        CGSize(width: frame.width, height: frame.height)
    }

    static func screenContainingLargestIntersection(with frame: CGRect) -> NSScreen? {
        screens
            .compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
                let intersection = frame.intersection(screen.frame)
                guard !intersection.isNull, !intersection.isEmpty else {
                    return nil
                }

                return (screen, intersection.width * intersection.height)
            }
            .max(by: { $0.area < $1.area })?
            .screen
    }

    static func screenContaining(_ point: CGPoint) -> NSScreen? {
        screens.first(where: { $0.frame.contains(point) }) ?? main
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func clamped(to bounds: CGRect) -> CGRect {
        guard !self.isNull, !self.isEmpty else {
            return .null
        }

        let minX = max(bounds.minX, self.minX)
        let maxX = min(bounds.maxX, self.maxX)
        let minY = max(bounds.minY, self.minY)
        let maxY = min(bounds.maxY, self.maxY)

        guard maxX > minX, maxY > minY else {
            return .null
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func centered(at point: CGPoint) -> CGRect {
        CGRect(
            x: point.x - (width / 2),
            y: point.y - (height / 2),
            width: width,
            height: height
        )
    }

    func clampedCenterPreservingSize(to bounds: CGRect) -> CGRect {
        guard !self.isNull, !self.isEmpty else {
            return .null
        }

        let width = min(self.width, bounds.width)
        let height = min(self.height, bounds.height)
        let minX = bounds.minX
        let maxX = bounds.maxX - width
        let minY = bounds.minY
        let maxY = bounds.maxY - height

        return CGRect(
            x: min(max(self.origin.x, minX), maxX),
            y: min(max(self.origin.y, minY), maxY),
            width: width,
            height: height
        )
    }
}
