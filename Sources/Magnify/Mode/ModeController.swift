import AppKit
import Foundation

@MainActor
final class ModeController {
    private enum ZoomConstants {
        static let minimum: CGFloat = 1.0
        static let maximum: CGFloat = 4.0
        static let step: CGFloat = 0.12
        static let edgePanThreshold: CGFloat = 24.0
        static let edgePanStep: CGFloat = 28.0
    }

    private enum PresentationSource {
        case selection
        case cursorZoom
    }

    private(set) var mode: AppMode = .edit {
        didSet {
            onModeChange?(mode)
        }
    }

    var onModeChange: ((AppMode) -> Void)?
    var onError: ((Error) -> Void)?
    var isEditPaneVisible: Bool {
        mode == .edit && selectionWindowController.isVisible
    }

    private let permissionsManager: PermissionsManager
    private let selectionWindowController: SelectionWindowController
    private let presentationWindowController: PresentationWindowController
    private let displayResolver: DisplayResolver
    private let captureEngine: CaptureEngine
    private let selectionAppearanceSampler = SelectionAppearanceSampler()

    private var isTransitioning = false
    private var zoomFactor: CGFloat = 1.0
    private var presentationSource: PresentationSource?
    private var cursorZoomTimer: Timer?
    private var lastCursorZoomRequest: CaptureRequest?
    private var cursorZoomScreen: NSScreen?
    private var cursorZoomCenter: CGPoint?

    init(
        permissionsManager: PermissionsManager,
        selectionWindowController: SelectionWindowController,
        presentationWindowController: PresentationWindowController,
        displayResolver: DisplayResolver,
        captureEngine: CaptureEngine
    ) {
        self.permissionsManager = permissionsManager
        self.selectionWindowController = selectionWindowController
        self.presentationWindowController = presentationWindowController
        self.displayResolver = displayResolver
        self.captureEngine = captureEngine

        captureEngine.setFrameHandler { [weak presentationWindowController] image in
            presentationWindowController?.update(image: image)
        }
    }

    func start() {
        if permissionsManager.hasScreenRecordingPermission() {
            captureEngine.stopCapture()
            presentationWindowController.hide()
            selectionWindowController.hide()
            stopCursorZoomTracking()
            stopSelectionAppearanceSampling()
            presentationSource = nil
            lastCursorZoomRequest = nil
            cursorZoomScreen = nil
            cursorZoomCenter = nil
            mode = .edit
            isTransitioning = false
        } else {
            mode = .blockedByPermissions
            selectionWindowController.hide()
            presentationWindowController.hide()
        }
    }

    func toggleMode() {
        guard !isTransitioning else {
            return
        }

        switch mode {
        case .blockedByPermissions:
            requestPermissions()
        case .edit:
            Task {
                await enterSelectionPresentationMode()
            }
        case .presenting:
            enterEditMode(activating: false, showingSelection: false)
        }
    }

    func toggleEditMode() {
        guard !isTransitioning else {
            return
        }

        switch mode {
        case .blockedByPermissions:
            requestPermissions()
        case .edit:
            if selectionWindowController.isVisible {
                selectionWindowController.hide()
                stopSelectionAppearanceSampling()
                onModeChange?(mode)
            } else {
                selectionWindowController.show(activating: true)
                startSelectionAppearanceSampling()
                onModeChange?(mode)
            }
        case .presenting:
            enterEditMode(activating: true, showingSelection: true)
        }
    }

    func toggleCursorZoom() {
        guard !isTransitioning else {
            return
        }

        switch mode {
        case .blockedByPermissions:
            requestPermissions()

            if mode == .edit {
                Task {
                    await enterCursorZoomPresentationMode()
                }
            }
        case .edit:
            Task {
                await enterCursorZoomPresentationMode()
            }
        case .presenting:
            if presentationSource == .cursorZoom {
                enterEditMode(activating: false, showingSelection: false)
            } else {
                Task {
                    await enterCursorZoomPresentationMode()
                }
            }
        }
    }

    func increaseZoom() {
        let didChange = setZoomFactor(zoomFactor + ZoomConstants.step)
        autoEnterCursorZoomIfNeeded(onlyWhenZoomChanged: didChange)
    }

    func decreaseZoom() {
        let didChange = setZoomFactor(zoomFactor - ZoomConstants.step)
        autoEnterCursorZoomIfNeeded(onlyWhenZoomChanged: didChange)
    }

    func enterEditMode(activating: Bool, showingSelection: Bool = true) {
        captureEngine.stopCapture()
        presentationWindowController.hide()
        stopCursorZoomTracking()
        presentationSource = nil
        lastCursorZoomRequest = nil
        cursorZoomScreen = nil
        cursorZoomCenter = nil
        mode = permissionsManager.hasScreenRecordingPermission() ? .edit : .blockedByPermissions

        guard mode == .edit, showingSelection else {
            selectionWindowController.hide()
            stopSelectionAppearanceSampling()
            isTransitioning = false
            return
        }

        selectionWindowController.show(activating: activating)
        startSelectionAppearanceSampling()
        isTransitioning = false
    }

    func refreshSelectionAppearance() {
        guard mode == .edit, selectionWindowController.isVisible else {
            return
        }

        selectionAppearanceSampler.refresh()
    }

    func requestPermissions() {
        let granted = permissionsManager.requestScreenRecordingPermission()

        guard granted else {
            onError?(MagnifyError.screenRecordingPermissionDenied)
            mode = .blockedByPermissions
            return
        }

        enterEditMode(activating: true)
    }

    private func enterSelectionPresentationMode() async {
        guard permissionsManager.hasScreenRecordingPermission() else {
            requestPermissions()
            return
        }

        selectionWindowController.normalizeToDisplayAspect(display: true)

        guard let target = displayResolver.resolveDisplayTarget(
            for: selectionWindowController.frame,
            zoomFactor: 1.0
        ) else {
            onError?(MagnifyError.invalidSelection)
            return
        }

        isTransitioning = true
        stopSelectionAppearanceSampling()
        stopCursorZoomTracking()
        selectionWindowController.hide()
        presentationWindowController.show(on: target.screen)

        do {
            try await captureEngine.startCapture(for: target.captureRequest)
            presentationSource = .selection
            mode = .presenting
        } catch {
            presentationWindowController.hide()
            selectionWindowController.show(activating: true)
            startSelectionAppearanceSampling()
            presentationSource = nil
            onError?(error)
            mode = .edit
        }

        isTransitioning = false
    }

    @discardableResult
    private func setZoomFactor(_ proposedZoomFactor: CGFloat) -> Bool {
        let clampedZoomFactor = min(max(proposedZoomFactor, ZoomConstants.minimum), ZoomConstants.maximum)
        guard abs(clampedZoomFactor - zoomFactor) > 0.001 else {
            return false
        }

        zoomFactor = clampedZoomFactor
        refreshCursorZoomCapture(force: true)
        return true
    }

    private func autoEnterCursorZoomIfNeeded(onlyWhenZoomChanged didChange: Bool) {
        guard !isTransitioning else {
            return
        }

        switch mode {
        case .presenting:
            if presentationSource == .cursorZoom {
                refreshCursorZoomCapture(force: true)
                return
            }

            Task {
                await enterCursorZoomPresentationMode()
            }
        case .blockedByPermissions:
            requestPermissions()

            if mode == .edit, didChange {
                Task {
                    await enterCursorZoomPresentationMode()
                }
            }
        case .edit:
            guard didChange else {
                return
            }

            Task {
                await enterCursorZoomPresentationMode()
            }
        }
    }

    private func enterCursorZoomPresentationMode() async {
        guard permissionsManager.hasScreenRecordingPermission() else {
            requestPermissions()
            return
        }

        guard let target = displayResolver.resolveCursorZoomTarget(
            for: NSEvent.mouseLocation,
            zoomFactor: zoomFactor
        ) else {
            onError?(MagnifyError.displayNotFound)
            return
        }

        isTransitioning = true
        stopSelectionAppearanceSampling()
        selectionWindowController.hide()
        presentationWindowController.show(on: target.screen)

        do {
            if mode == .presenting {
                captureEngine.updateCapture(for: target.captureRequest)
            } else {
                try await captureEngine.startCapture(for: target.captureRequest)
            }

            presentationSource = .cursorZoom
            lastCursorZoomRequest = target.captureRequest
            cursorZoomScreen = target.screen
            cursorZoomCenter = clampedCursorZoomCenter(NSEvent.mouseLocation, on: target.screen)
            startCursorZoomTracking()
            mode = .presenting
        } catch {
            presentationWindowController.hide()
            presentationSource = nil
            lastCursorZoomRequest = nil
            cursorZoomScreen = nil
            cursorZoomCenter = nil
            onError?(error)
            mode = .edit
        }

        isTransitioning = false
    }

    private func startCursorZoomTracking() {
        guard presentationSource == .cursorZoom else {
            stopCursorZoomTracking()
            return
        }

        if let cursorZoomTimer {
            cursorZoomTimer.invalidate()
        }

        cursorZoomTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCursorZoomCapture()
            }
        }
    }

    private func stopCursorZoomTracking() {
        cursorZoomTimer?.invalidate()
        cursorZoomTimer = nil
    }

    private func refreshCursorZoomCapture(force: Bool = false) {
        guard
            mode == .presenting,
            presentationSource == .cursorZoom,
            let screen = cursorZoomScreen,
            let currentCenter = cursorZoomCenter
        else {
            return
        }

        let updatedCenter = updatedCursorZoomCenter(
            from: currentCenter,
            on: screen,
            mouseLocation: NSEvent.mouseLocation
        )

        guard let target = displayResolver.resolveCursorZoomTarget(
            on: screen,
            centerPoint: updatedCenter,
            zoomFactor: zoomFactor
        ) else {
            return
        }

        cursorZoomCenter = clampedCursorZoomCenter(updatedCenter, on: screen)

        if force || target.captureRequest != lastCursorZoomRequest {
            lastCursorZoomRequest = target.captureRequest
            captureEngine.updateCapture(for: target.captureRequest)
        }
    }

    private func updatedCursorZoomCenter(from center: CGPoint, on screen: NSScreen, mouseLocation: CGPoint) -> CGPoint {
        let localX = mouseLocation.x - screen.frame.minX
        let localY = mouseLocation.y - screen.frame.minY
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height
        var updatedCenter = center

        if localX <= ZoomConstants.edgePanThreshold {
            updatedCenter.x -= ZoomConstants.edgePanStep
        } else if localX >= screenWidth - ZoomConstants.edgePanThreshold {
            updatedCenter.x += ZoomConstants.edgePanStep
        }

        if localY <= ZoomConstants.edgePanThreshold {
            updatedCenter.y -= ZoomConstants.edgePanStep
        } else if localY >= screenHeight - ZoomConstants.edgePanThreshold {
            updatedCenter.y += ZoomConstants.edgePanStep
        }

        return updatedCenter
    }

    private func clampedCursorZoomCenter(_ center: CGPoint, on screen: NSScreen) -> CGPoint {
        let sourceWidth = screen.frame.width / max(zoomFactor, 1.0)
        let sourceHeight = screen.frame.height / max(zoomFactor, 1.0)
        let halfWidth = sourceWidth / 2
        let halfHeight = sourceHeight / 2

        return CGPoint(
            x: min(max(center.x, screen.frame.minX + halfWidth), screen.frame.maxX - halfWidth),
            y: min(max(center.y, screen.frame.minY + halfHeight), screen.frame.maxY - halfHeight)
        )
    }

    private func refreshPresentationZoom() {
        guard
            mode == .presenting,
            let target = displayResolver.resolveDisplayTarget(
                for: selectionWindowController.frame,
                zoomFactor: zoomFactor
            )
        else {
            return
        }

        captureEngine.updateCapture(for: target.captureRequest)
    }

    private func startSelectionAppearanceSampling() {
        guard mode != .blockedByPermissions, selectionWindowController.isVisible else {
            stopSelectionAppearanceSampling()
            return
        }

        selectionAppearanceSampler.start(
            frameProvider: { [weak selectionWindowController] in
                selectionWindowController?.frame ?? .zero
            },
            windowIDProvider: { [weak selectionWindowController] in
                selectionWindowController?.windowID
            },
            styleHandler: { [weak selectionWindowController] style in
                selectionWindowController?.update(contrastStyle: style)
            }
        )
    }

    private func stopSelectionAppearanceSampling() {
        selectionAppearanceSampler.stop()
    }
}
