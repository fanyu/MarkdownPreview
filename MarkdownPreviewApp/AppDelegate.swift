import AppKit

/// Wires Xcode follow mode: XcodeWatcher detects the active .md in Xcode,
/// FileMonitor tracks saves, PreviewPanel displays. Also listens for the
/// Source Editor Extension's toggle notification.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let followXcodeKey = "followXcode"
    static let toggleNotification = Notification.Name("com.fanyu.markdownpreview.toggle")
    static private(set) weak var shared: AppDelegate?

    private lazy var panel = PreviewPanel()
    private let watcher = XcodeWatcher()
    private let fileMonitor = FileMonitor()
    private var watcherRunning = false
    private var welcomeController: WelcomeWindowController?

    override init() {
        super.init()
        Self.shared = self
        // No window resume: launch always lands on the welcome window and
        // documents reopen via its recents list. Persisted (not registered)
        // because the restoration machinery reads it outside this process.
        if UserDefaults.standard.object(forKey: "NSQuitAlwaysKeepsWindows") == nil {
            UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.followXcodeKey: true])

        // Close the welcome window as soon as a document window comes up.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        // Bring the welcome window back when the last document window closes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        watcher.onFilePathChanged = { [weak self] path in
            self?.handleActiveFileChanged(to: path)
        }
        updateFollowMode()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(extensionTriggered),
            name: Self.toggleNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // DocumentGroup launch is suppressed; show the welcome window unless
        // a document window appeared (file opened or scene restored).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasDocumentWindow = NSApp.windows.contains {
                $0.isVisible && !($0 is NSPanel)
            }
            if !hasDocumentWindow { self.showWelcome() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // keep running for Xcode follow mode
    }

    // MARK: - Welcome window

    /// Launching with no document shows the welcome window instead of an
    /// untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showWelcome()
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }

    func showWelcome() {
        if welcomeController == nil {
            let controller = WelcomeWindowController()
            controller.onClose = { [weak self] in self?.welcomeController = nil }
            welcomeController = controller
        }
        welcomeController?.showWindow(nil)
        welcomeController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowBecameMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window !== welcomeController?.window else { return }
        welcomeController?.close()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window !== welcomeController?.window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasDocumentWindow = NSApp.windows.contains {
                $0.isVisible && !($0 is NSPanel) && $0 !== self.welcomeController?.window
            }
            if !hasDocumentWindow && NSApp.isRunning && !NSApp.isHidden {
                self.showWelcome()
            }
        }
    }

    // MARK: - Follow mode

    @objc private func defaultsChanged() {
        updateFollowMode()
    }

    private func updateFollowMode() {
        let enabled = UserDefaults.standard.bool(forKey: Self.followXcodeKey)
        guard enabled != watcherRunning else { return }
        watcherRunning = enabled
        if enabled {
            watcher.start()
        } else {
            watcher.stop()
            fileMonitor.stop()
            panel.orderOut(nil)
        }
    }

    private func handleActiveFileChanged(to path: String?) {
        if let path {
            panel.setFilename((path as NSString).lastPathComponent)
            panel.renderer.renderFile(at: path)
            fileMonitor.onChange = { [weak self] changedPath in
                self?.panel.renderer.renderFile(at: changedPath)
            }
            fileMonitor.start(watching: path)
            if !panel.isVisible { panel.orderFront(nil) }
        } else {
            fileMonitor.stop()
            panel.orderOut(nil)
        }
    }

    @objc private func extensionTriggered() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else if UserDefaults.standard.bool(forKey: Self.followXcodeKey) == false {
            // Follow mode off: turning the panel on via the Xcode command
            // re-enables following so the panel has content to show.
            UserDefaults.standard.set(true, forKey: Self.followXcodeKey)
        } else {
            panel.orderFront(nil)
        }
    }
}
