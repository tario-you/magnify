import AppKit
import CoreGraphics
import CoreImage
import Foundation

final class SelectionAppearanceSampler: @unchecked Sendable {
    private let debounceDelay: DispatchTimeInterval = .milliseconds(180)
    private let sampleQueue = DispatchQueue(label: "magnify.selection-appearance-sampler", qos: .utility)
    private let ciContext = CIContext(options: nil)

    private var pendingSampleWorkItem: DispatchWorkItem?
    private var latestStyle: SelectionContrastStyle?
    private var frameProvider: (@MainActor () -> CGRect)?
    private var windowIDProvider: (@MainActor () -> CGWindowID?)?
    private var styleHandler: (@MainActor (SelectionContrastStyle) -> Void)?

    func start(
        frameProvider: @escaping @MainActor () -> CGRect,
        windowIDProvider: @escaping @MainActor () -> CGWindowID?,
        styleHandler: @escaping @MainActor (SelectionContrastStyle) -> Void
    ) {
        self.frameProvider = frameProvider
        self.windowIDProvider = windowIDProvider
        self.styleHandler = styleHandler

        scheduleSample(after: .milliseconds(10))
    }

    func refresh() {
        scheduleSample(after: debounceDelay)
    }

    func stop() {
        pendingSampleWorkItem?.cancel()
        pendingSampleWorkItem = nil
        latestStyle = nil
        frameProvider = nil
        windowIDProvider = nil
        styleHandler = nil
    }

    private func scheduleSample(after delay: DispatchTimeInterval) {
        pendingSampleWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.sampleAppearance()
        }

        pendingSampleWorkItem = workItem
        sampleQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func sampleAppearance() {
        guard
            let frameProvider,
            let windowIDProvider,
            let styleHandler
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let selectionFrame = frameProvider()
            let windowID = windowIDProvider()

            self.sampleQueue.async { [weak self] in
                self?.processSample(
                    selectionFrame: selectionFrame,
                    windowID: windowID,
                    styleHandler: styleHandler
                )
            }
        }
    }

    private func processSample(
        selectionFrame: CGRect,
        windowID: CGWindowID?,
        styleHandler: @escaping @MainActor (SelectionContrastStyle) -> Void
    ) {
        guard
            !selectionFrame.isNull,
            !selectionFrame.isEmpty,
            let cgImage = snapshotImage(for: selectionFrame, excluding: windowID),
            let style = classifyAppearance(for: cgImage)
        else {
            return
        }

        guard style != latestStyle else {
            return
        }

        latestStyle = style
        Task { @MainActor in
            styleHandler(style)
        }
    }

    private func snapshotImage(for frame: CGRect, excluding windowID: CGWindowID?) -> CGImage? {
        let bounds = sampleBounds(for: frame)
        guard bounds.width > 1, bounds.height > 1 else {
            return nil
        }

        if let windowID {
            return CGWindowListCreateImage(
                bounds,
                .optionOnScreenBelowWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
        }

        return CGWindowListCreateImage(
            bounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    private func sampleBounds(for frame: CGRect) -> CGRect {
        let maxSampleSize: CGFloat = 160
        let width = min(frame.width, maxSampleSize)
        let height = min(frame.height, maxSampleSize)

        return CGRect(
            x: frame.midX - (width / 2),
            y: frame.midY - (height / 2),
            width: width,
            height: height
        ).integral
    }

    private func classifyAppearance(for image: CGImage) -> SelectionContrastStyle? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var rgba = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let red = Double(rgba[0]) / 255.0
        let green = Double(rgba[1]) / 255.0
        let blue = Double(rgba[2]) / 255.0
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)

        if luminance <= 0.35 {
            return .darkSurface
        }

        if luminance >= 0.65 {
            return .lightSurface
        }

        return .mixedSurface
    }
}
