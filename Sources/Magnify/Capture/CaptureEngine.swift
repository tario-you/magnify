import AppKit

protocol CaptureEngine: AnyObject, Sendable {
    func setFrameHandler(_ handler: @escaping @MainActor (CGImage) -> Void)

    func startCapture(for request: CaptureRequest) async throws
    func updateCapture(for request: CaptureRequest)
    func stopCapture()
}
