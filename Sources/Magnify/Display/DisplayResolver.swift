import AppKit
import CoreGraphics

struct CaptureRequest: Sendable {
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
    func resolveDisplayTarget(for selectionFrame: CGRect) -> DisplayTarget? {
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

        let relativeRect = CGRect(
            x: intersection.minX - screen.frame.minX,
            y: intersection.minY - screen.frame.minY,
            width: intersection.width,
            height: intersection.height
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
}
