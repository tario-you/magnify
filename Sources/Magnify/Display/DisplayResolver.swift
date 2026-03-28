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
        let candidates = NSScreen.screens.compactMap { screen -> (screen: NSScreen, displayID: CGDirectDisplayID, intersection: CGRect, area: CGFloat)? in
            guard let displayID = screen.displayID else {
                return nil
            }

            let intersection = selectionFrame.intersection(screen.frame)
            guard !intersection.isNull, !intersection.isEmpty else {
                return nil
            }

            let area = intersection.width * intersection.height
            return (screen, displayID, intersection, area)
        }

        guard let best = candidates.max(by: { $0.area < $1.area }) else {
            return nil
        }

        let pixelWidth = CGFloat(CGDisplayPixelsWide(best.displayID))
        let pixelHeight = CGFloat(CGDisplayPixelsHigh(best.displayID))
        let scaleX = pixelWidth / best.screen.frame.width
        let scaleY = pixelHeight / best.screen.frame.height

        let relativeRect = CGRect(
            x: best.intersection.minX - best.screen.frame.minX,
            y: best.intersection.minY - best.screen.frame.minY,
            width: best.intersection.width,
            height: best.intersection.height
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
            screen: best.screen,
            captureRequest: CaptureRequest(
                displayID: best.displayID,
                pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
                cropRectPixels: cropRect
            )
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private extension CGRect {
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
}
