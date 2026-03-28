import AppKit
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import VideoToolbox

final class ScreenCaptureKitEngine: NSObject, CaptureEngine, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    @MainActor
    private var frameHandler: ((CGImage) -> Void)?

    private let sampleQueue = DispatchQueue(label: "magnify.capture.sample-queue", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "magnify.capture.state-queue")
    private var stream: SCStream?
    private var currentRequest: CaptureRequest?

    func setFrameHandler(_ handler: @escaping @MainActor (CGImage) -> Void) {
        Task { @MainActor in
            frameHandler = handler
        }
    }

    func startCapture(for request: CaptureRequest) async throws {
        stopCapture()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw MagnifyError.displayNotFound
        }

        let excludedApplications = content.applications.filter { app in
            app.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = Int(request.pixelSize.width)
        configuration.height = Int(request.pixelSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.showsCursor = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        stateQueue.sync {
            self.stream = stream
            currentRequest = request
        }
    }

    func stopCapture() {
        let streamToStop: SCStream? = stateQueue.sync {
            defer {
                stream = nil
                currentRequest = nil
            }

            return stream
        }

        guard let streamToStop else {
            return
        }

        Task.detached {
            try? await streamToStop.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else {
            return
        }

        let currentRequest = stateQueue.sync { self.currentRequest }

        guard let currentRequest, CMSampleBufferIsValid(sampleBuffer), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        guard status == noErr, let cgImage else {
            return
        }

        let cropRect = currentRequest.cropRectPixels.integral.intersection(
            CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )

        guard cropRect.width > 1, cropRect.height > 1, let croppedImage = cgImage.cropping(to: cropRect) else {
            return
        }

        Task { @MainActor in
            frameHandler?(croppedImage)
        }
    }
}
