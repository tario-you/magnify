import AppKit

enum SelectionContrastStyle: Equatable {
    case darkSurface
    case lightSurface
    case mixedSurface

    var fillColor: NSColor {
        switch self {
        case .darkSurface:
            return .white.withAlphaComponent(0.10)
        case .lightSurface:
            return .black.withAlphaComponent(0.08)
        case .mixedSurface:
            return NSColor(calibratedWhite: 0.55, alpha: 0.10)
        }
    }

    var strokeColor: NSColor {
        switch self {
        case .darkSurface:
            return .white.withAlphaComponent(0.72)
        case .lightSurface:
            return .black.withAlphaComponent(0.78)
        case .mixedSurface:
            return NSColor(calibratedWhite: 0.55, alpha: 0.88)
        }
    }

    var innerStrokeColor: NSColor {
        switch self {
        case .darkSurface:
            return .white.withAlphaComponent(0.16)
        case .lightSurface:
            return .black.withAlphaComponent(0.18)
        case .mixedSurface:
            return NSColor(calibratedWhite: 0.45, alpha: 0.30)
        }
    }
}
