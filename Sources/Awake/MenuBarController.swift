import Cocoa

/// The menu bar item: a mug that fills in while sleep is disabled.
///
/// The item is present the whole time the app runs, so its absence never has to
/// be interpreted -- an outline mug means sleep is normal, a filled one means
/// the Mac is being held awake.
final class MenuBarController: NSObject, NSApplicationDelegate {

    /// Only catches changes made by something other than Awake. Everything
    /// Awake does arrives as an event, so this can be slow and wide: the
    /// tolerance lets the OS coalesce the wakeup with others instead of waking
    /// the CPU on its own schedule.
    private static let backstopInterval: TimeInterval = 60
    private static let backstopTolerance: TimeInterval = 15

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var backstop: Timer?
    private var reader: NotifyToken?
    private var watcher: NotifyToken?
    private var isDisabled = false

    private let work = DispatchQueue(label: "com.awake.app.work", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        statusItem.button?.imagePosition = .imageOnly

        // Separate tokens: one to read the published state, one to be woken.
        reader = NotifyToken(checking: Channel.changed)
        watcher = NotifyToken(watching: Channel.changed, on: .main) { [weak self] in
            self?.adoptPublishedState()
        }

        let timer = Timer(timeInterval: Self.backstopInterval, repeats: true) { [weak self] _ in
            self?.resyncFromPmset()
        }
        timer.tolerance = Self.backstopTolerance
        RunLoop.main.add(timer, forMode: .common)
        backstop = timer

        render(disabled: SleepState.current(via: reader))
        ensureInstalled()
    }

    // MARK: - State

    /// The fast path. The helper publishes only values it has confirmed, so
    /// this needs no pmset call and cannot render a half-applied change --
    /// which is what used to make the menu bar trail the CLI.
    private func adoptPublishedState() {
        guard let reader, let disabled = SleepState.published(via: reader) else {
            resyncFromPmset()
            return
        }
        render(disabled: disabled)
    }

    private func resyncFromPmset() {
        work.async { [weak self] in
            let disabled = SleepState.fromPmset()
            DispatchQueue.main.async { self?.render(disabled: disabled) }
        }
    }

    private func render(disabled: Bool) {
        isDisabled = disabled

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        statusItem.button?.image = NSImage(
            systemSymbolName: disabled ? "mug.fill" : "mug",
            accessibilityDescription: disabled ? "Sleep disabled" : "Sleep enabled"
        )?.withSymbolConfiguration(configuration)

        statusItem.button?.toolTip = disabled
            ? "Awake is on. This Mac will not sleep."
            : "Awake is off. This Mac sleeps normally."

        toggleItem.title = disabled ? "Turn Awake Off" : "Turn Awake On"
    }

    // MARK: - Installation

    private func ensureInstalled() {
        guard !Paths.isFullyInstalled else { return }

        // The launchd jobs and the `awake` symlink all name
        // /Applications/Awake.app, so installing from anywhere else -- most
        // often straight out of the mounted disk image -- would register a
        // helper against a bundle that is about to go away.
        guard (Bundle.main.bundlePath as NSString).standardizingPath == Paths.appBundle else {
            report(title: "Move Awake to Applications",
                   detail: """
                       Awake installs a background helper that refers to it at \
                       /Applications/Awake.app, so it has to live there before \
                       it can turn sleep off. Drag Awake to Applications and \
                       open it again.
                       """)
            // Quit rather than linger: a copy still running out of the disk
            // image is the one thing that would stop the copy in /Applications
            // from starting, since that one stands aside for a running
            // instance.
            NSApp.terminate(nil)
            return
        }

        work.async { [weak self] in
            let installed = HelperInstaller.requestInstall()
            DispatchQueue.main.async {
                guard let self else { return }
                if installed {
                    self.adoptPublishedState()
                } else {
                    self.report(title: "Awake could not finish installing",
                                detail: """
                                    Awake can still show whether sleep is \
                                    disabled, but it cannot change it. Quit and \
                                    reopen Awake to try again.
                                    """)
                }
            }
        }
    }

    private func report(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        toggleItem = NSMenuItem(title: "Turn Awake On",
                                action: #selector(toggle),
                                keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Awake",
                              action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggle() {
        Channel.post(isDisabled ? Channel.off : Channel.on)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
