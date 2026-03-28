import AppKit

@MainActor
final class AppCoordinator: NSObject {
    private let permissionsManager = PermissionsManager()
    private let settingsStore = SettingsStore()
    private let displayResolver = DisplayResolver()
    private let captureEngine = ScreenCaptureKitEngine()
    private let hotkeyManager = GlobalHotkeyManager()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let toggleItem = NSMenuItem(title: "Toggle Presentation", action: nil, keyEquivalent: "")
    private let openSelectionItem = NSMenuItem(title: "Open Selection", action: nil, keyEquivalent: "")
    private let resetSelectionItem = NSMenuItem(title: "Reset Selection Size", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Screen Recording Permission", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")

    private lazy var selectionWindowController: SelectionWindowController = {
        let initialFrame = settingsStore.loadSelectionFrame() ?? settingsStore.defaultSelectionFrame(on: NSScreen.main)
        let controller = SelectionWindowController(initialFrame: initialFrame)
        controller.onFrameChange = { [weak self] frame in
            self?.settingsStore.saveSelectionFrame(frame)
        }
        return controller
    }()

    private lazy var presentationWindowController = PresentationWindowController()

    private lazy var modeController = ModeController(
        permissionsManager: permissionsManager,
        selectionWindowController: selectionWindowController,
        presentationWindowController: presentationWindowController,
        displayResolver: displayResolver,
        captureEngine: captureEngine
    )

    func start() {
        configureMenuBar()
        configureHotKey()
        configureModeCallbacks()
        modeController.start()
        refreshMenu(for: modeController.mode)
    }

    func stop() {
        hotkeyManager.unregister()
        captureEngine.stopCapture()
        settingsStore.saveSelectionFrame(selectionWindowController.frame)
    }

    private func configureMenuBar() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "macwindow.and.cursorarrow", accessibilityDescription: "Magnify")
        }

        toggleItem.target = self
        toggleItem.action = #selector(togglePresentation)

        openSelectionItem.target = self
        openSelectionItem.action = #selector(openSelectionWindow)

        resetSelectionItem.target = self
        resetSelectionItem.action = #selector(resetSelection)

        permissionItem.target = self
        permissionItem.action = #selector(requestPermission)

        quitItem.target = self
        quitItem.action = #selector(quit)

        menu.items = [
            toggleItem,
            openSelectionItem,
            resetSelectionItem,
            permissionItem,
            .separator(),
            quitItem
        ]

        statusItem.menu = menu
    }

    private func configureHotKey() {
        hotkeyManager.onHotKeyPressed = { [weak self] in
            Task { @MainActor in
                self?.modeController.toggleMode()
            }
        }
        hotkeyManager.register()
    }

    private func configureModeCallbacks() {
        modeController.onModeChange = { [weak self] mode in
            self?.refreshMenu(for: mode)
        }

        modeController.onError = { [weak self] error in
            self?.presentError(error)
        }
    }

    private func refreshMenu(for mode: AppMode) {
        switch mode {
        case .blockedByPermissions:
            toggleItem.title = "Request Permission"
            openSelectionItem.isHidden = false
            openSelectionItem.isEnabled = false
            resetSelectionItem.isHidden = false
            resetSelectionItem.isEnabled = false
            permissionItem.isHidden = false
        case .edit:
            toggleItem.title = "Start Presentation"
            openSelectionItem.isHidden = false
            openSelectionItem.isEnabled = false
            resetSelectionItem.isHidden = false
            resetSelectionItem.isEnabled = true
            permissionItem.isHidden = true
        case .presenting:
            toggleItem.title = "Return to Edit Mode"
            openSelectionItem.isHidden = false
            openSelectionItem.isEnabled = true
            resetSelectionItem.isHidden = false
            resetSelectionItem.isEnabled = false
            permissionItem.isHidden = true
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Magnify"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        if case MagnifyError.screenRecordingPermissionDenied = error {
            alert.addButton(withTitle: "Open Settings")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if case MagnifyError.screenRecordingPermissionDenied = error, response == .alertSecondButtonReturn {
            permissionsManager.openScreenRecordingSettings()
        }
    }

    @objc
    private func togglePresentation() {
        modeController.toggleMode()
    }

    @objc
    private func openSelectionWindow() {
        modeController.enterEditMode(activating: true)
    }

    @objc
    private func resetSelection() {
        let frame = settingsStore.defaultSelectionFrame(on: NSScreen.main)
        selectionWindowController.setFrame(frame)
        settingsStore.saveSelectionFrame(frame)
        modeController.enterEditMode(activating: true)
    }

    @objc
    private func requestPermission() {
        modeController.requestPermissions()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
