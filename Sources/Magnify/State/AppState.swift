import Foundation

enum AppMode {
    case blockedByPermissions
    case edit
    case presenting
}

enum MagnifyError: LocalizedError {
    case screenRecordingPermissionDenied
    case invalidSelection
    case displayNotFound
    case streamUnavailable

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is required before Magnify can present a live region."
        case .invalidSelection:
            return "The current selection is invalid. Resize or move it and try again."
        case .displayNotFound:
            return "Magnify could not resolve a display for the current selection."
        case .streamUnavailable:
            return "Magnify could not start the display capture stream."
        }
    }
}
