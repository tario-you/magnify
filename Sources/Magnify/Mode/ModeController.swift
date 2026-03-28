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
            enterEditMode(activating: true)
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
                onModeChange?(mode)
            } else {
                selectionWindowController.show(activating: true)
                onModeChange?(mode)
            }
        case .presenting:
            enterEditMode(activating: true)
        }
    }

    func enterEditMode(activating: Bool) {
        captureEngine.stopCapture()
        presentationWindowController.hide()
        selectionWindowController.show(activating: activating)
        mode = permissionsManager.hasScreenRecordingPermission() ? .edit : .blockedByPermissions
        isTransitioning = false
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
        selectionWindowController.hide()
        presentationWindowController.show(on: target.screen)

        do {
            try await captureEngine.startCapture(for: target.captureRequest)
            mode = .presenting
        } catch {
            presentationWindowController.hide()
            selectionWindowController.show(activating: true)
            onError?(error)
            mode = .edit
        }

        isTransitioning = false
    }
}
