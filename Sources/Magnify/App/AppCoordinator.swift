import AppKit

@MainActor
final class AppCoordinator: NSObject {
    private let permissionsManager = PermissionsManager()
    private let settingsStore = SettingsStore()
    private let displayResolver = DisplayResolver()
    private let captureEngine = ScreenCaptureKitEngine()
    private let hotkeyManager = GlobalHotkeyManager()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private let toggleItem = NSMenuItem(title: "Toggle Presentation", action: nil, keyEquivalent: "m")
    private let openSelectionItem = NSMenuItem(title: "Toggle Edit Pane", action: nil, keyEquivalent: "e")
    private let resetSelectionItem = NSMenuItem(title: "Reset Selection Size", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Screen Recording Permission", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")

    private lazy var selectionWindowController: SelectionWindowController = {
        let initialFrame = settingsStore.loadSelectionFrame() ?? settingsStore.defaultSelectionFrame(on: NSScreen.main)
        let controller = SelectionWindowController(initialFrame: initialFrame)
        controller.onFrameChange = { [weak self] frame in
            self?.settingsStore.saveSelectionFrame(frame)
            self?.modeController.refreshSelectionAppearance()
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
            let iconImage = menuBarIconImage()
                ?? NSImage(systemSymbolName: "macwindow.and.cursorarrow", accessibilityDescription: "Magnify")
            iconImage?.size = NSSize(width: 21, height: 21)
            button.title = ""
            button.image = iconImage
            button.imagePosition = .imageOnly
            button.toolTip = "Magnify"
        }

        toggleItem.target = self
        toggleItem.action = #selector(togglePresentation)
        toggleItem.keyEquivalentModifierMask = [.command, .option]

        openSelectionItem.target = self
        openSelectionItem.action = #selector(toggleEditPane)
        openSelectionItem.keyEquivalentModifierMask = [.command, .option]

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

        if let iconImage = bundledAppIcon() {
            NSApp.applicationIconImage = iconImage
        }
    }

    private func menuBarIconImage() -> NSImage? {
        guard let iconURL = Bundle.main.url(forResource: "MenuBarSymbol", withExtension: "png"),
              let image = NSImage(contentsOf: iconURL) else {
            return nil
        }

        image.isTemplate = true
        return image
    }

    private func bundledAppIcon() -> NSImage? {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: iconURL)
        }

        return nil
    }

    private func configureHotKey() {
        hotkeyManager.onModeTogglePressed = { [weak self] in
            Task { @MainActor in
                self?.modeController.toggleMode()
            }
        }

        hotkeyManager.onZoomTogglePressed = { [weak self] in
            Task { @MainActor in
                self?.modeController.toggleCursorZoom()
            }
        }

        hotkeyManager.onEditModeTogglePressed = { [weak self] in
            Task { @MainActor in
                self?.modeController.toggleEditMode()
            }
        }

        hotkeyManager.onZoomOutPressed = { [weak self] in
            Task { @MainActor in
                self?.modeController.decreaseZoom()
            }
        }

        hotkeyManager.onZoomInPressed = { [weak self] in
            Task { @MainActor in
                self?.modeController.increaseZoom()
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
            openSelectionItem.title = "Toggle Edit Pane"
            openSelectionItem.isHidden = false
            openSelectionItem.isEnabled = false
            resetSelectionItem.isHidden = false
            resetSelectionItem.isEnabled = false
            permissionItem.isHidden = false
        case .edit:
            toggleItem.title = "Start Presentation"
            openSelectionItem.title = modeController.isEditPaneVisible ? "Hide Edit Pane" : "Show Edit Pane"
            openSelectionItem.isHidden = false
            openSelectionItem.isEnabled = true
            resetSelectionItem.isHidden = false
            resetSelectionItem.isEnabled = true
            permissionItem.isHidden = true
        case .presenting:
            toggleItem.title = "Stop Presentation"
            openSelectionItem.title = "Show Edit Pane"
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
    private func toggleEditPane() {
        modeController.toggleEditMode()
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
