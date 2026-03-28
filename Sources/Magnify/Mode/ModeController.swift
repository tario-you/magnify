import AppKit
import Foundation

@MainActor
final class ModeController {
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
            enterEditMode(activating: false)
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
                await enterPresentationMode()
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

    func enterEditMode(activating: Bool, showingSelection: Bool = true) {
        captureEngine.stopCapture()
        presentationWindowController.hide()
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

    private func enterPresentationMode() async {
        guard permissionsManager.hasScreenRecordingPermission() else {
            requestPermissions()
            return
        }

        selectionWindowController.normalizeToDisplayAspect(display: true)

        guard let target = displayResolver.resolveDisplayTarget(for: selectionWindowController.frame) else {
            onError?(MagnifyError.invalidSelection)
            return
        }

        isTransitioning = true
        stopSelectionAppearanceSampling()
        selectionWindowController.hide()
        presentationWindowController.show(on: target.screen)

        do {
            try await captureEngine.startCapture(for: target.captureRequest)
            mode = .presenting
        } catch {
            presentationWindowController.hide()
            selectionWindowController.show(activating: true)
            startSelectionAppearanceSampling()
            onError?(error)
            mode = .edit
        }

        isTransitioning = false
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
