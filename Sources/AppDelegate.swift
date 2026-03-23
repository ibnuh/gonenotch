import Cocoa
import Carbon.HIToolbox
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    private var displayManager: DisplayManager!
    private var settingsController: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // Dynamic menu items
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!

    // Prevents screensChanged from clobbering a manual toggle
    private var suppressScreenChange = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        displayManager = DisplayManager()
        settingsController = SettingsWindowController()

        if displayManager.savedStateIsEnabled {
            displayManager.enable()
        } else {
            displayManager.syncState()
        }

        setupStatusItem()
        registerGlobalHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Display mode persists via UserDefaults; restored on next launch.
    }

    // MARK: - Status Item & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateIcon(button)
        }

        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        toggleMenuItem = NSMenuItem(
            title: "Disable",
            action: #selector(handleToggle),
            keyEquivalent: "n"
        )
        toggleMenuItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(toggleMenuItem)

        menu.addItem(NSMenuItem.separator())

        loginMenuItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        menu.addItem(loginMenuItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))

        menu.addItem(NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit GoneNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func updateIcon(_ button: NSStatusBarButton) {
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            button.title = "GN"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        }
    }

    private func refreshMenuState() {
        let enabled = displayManager.isEnabled
        toggleMenuItem.title = enabled ? "Disable" : "Enable"
        loginMenuItem.state = LoginItemManager.isEnabled ? .on : .off

        if let screen = NSScreen.main {
            let w = Int(screen.frame.width)
            let h = Int(screen.frame.height)
            let label = enabled ? "below notch" : "default"
            statusMenuItem.title = "\(w) x \(h) (\(label))"
        }

        if let button = statusItem.button {
            updateIcon(button)
        }
    }

    // MARK: - Actions

    @objc private func handleToggle() {
        suppressScreenChange = true
        displayManager.toggle()

        // Delay UI refresh slightly so the display mode settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshMenuState()
            self?.suppressScreenChange = false
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let newState = !LoginItemManager.isEnabled
        LoginItemManager.setEnabled(newState)
        loginMenuItem.state = LoginItemManager.isEnabled ? .on : .off
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func screensChanged() {
        if suppressScreenChange { return }
        displayManager.syncState()
        refreshMenuState()
    }

    // MARK: - Global Hot Key (Cmd+Ctrl+N)

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                guard let delegate = NSApp.delegate as? AppDelegate else { return }
                delegate.handleToggle()
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x474E4348),
            id: 1
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(cmdKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            hotKeyRef = ref
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }
}
