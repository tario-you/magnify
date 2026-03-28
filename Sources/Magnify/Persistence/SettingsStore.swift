import AppKit

@MainActor
final class SettingsStore {
    private enum Keys {
        static let selectionFrame = "selectionFrame"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSelectionFrame() -> CGRect? {
        guard let string = defaults.string(forKey: Keys.selectionFrame) else {
            return nil
        }

        let frame = NSRectFromString(string)
        guard !frame.isEmpty else {
            return nil
        }

        return frame
    }

    func saveSelectionFrame(_ frame: CGRect) {
        defaults.set(NSStringFromRect(frame), forKey: Keys.selectionFrame)
    }

    func defaultSelectionFrame(on screen: NSScreen?) -> CGRect {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let referenceFrame = targetScreen?.visibleFrame ?? CGRect(x: 200, y: 200, width: 1280, height: 800)
        let aspectRatio = targetScreen?.displayAspectRatio ?? CGSize(width: 16, height: 10)
        let aspectValue = aspectRatio.width / aspectRatio.height

        var width = min(max(referenceFrame.width * 0.42, 420), 960)
        var height = width / aspectValue

        if height > referenceFrame.height * 0.42 {
            height = referenceFrame.height * 0.42
            width = height * aspectValue
        }

        return CGRect(
            x: referenceFrame.midX - (width / 2),
            y: referenceFrame.midY - (height / 2),
            width: width,
            height: height
        ).integral
    }
}
