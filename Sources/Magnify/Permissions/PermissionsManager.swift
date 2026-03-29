import AppKit
import CoreGraphics
import Foundation

@MainActor
final class PermissionsManager {
    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        armRelaunchAfterTerminationIfNeeded()

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func armRelaunchAfterTerminationIfNeeded() {
        let processID = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path.removingPercentEncoding
            ?? Bundle.main.bundleURL.standardizedFileURL.path

        guard bundlePath.hasSuffix(".app") else {
            return
        }

        let executablePath = Bundle.main.executableURL?.path ?? ""
        let escapedBundlePath = shellQuoted(bundlePath)
        let escapedExecutablePath = shellQuoted(executablePath)
        let script = """
        while kill -0 \(processID) 2>/dev/null; do
          sleep 0.2
        done
        sleep 1
        if ! pgrep -f \(escapedExecutablePath) >/dev/null 2>&1; then
          /usr/bin/open \(escapedBundlePath) >/dev/null 2>&1
        fi
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        try? process.run()
    }

    private func shellQuoted(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
