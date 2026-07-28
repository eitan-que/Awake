import AwakeCore
import Cocoa
import notify

/// The menu bar item: a mug that fills in while sleep is disabled.
///
/// The item is present the whole time the app runs, so its absence never has to
/// be interpreted -- an outline mug means sleep is normal, a filled one means
/// the Mac is being held awake.
final class MenuBarController: NSObject, NSApplicationDelegate {

    /// Catches changes made outside Awake, such as a direct pmset call. Wide
    /// tolerance lets the OS coalesce this wakeup with others instead of
    /// waking the CPU on its own schedule.
    private static let backstopInterval: TimeInterval = 60
    private static let backstopTolerance: TimeInterval = 15
    private static let invalidToken: Int32 = -1

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var backstop: Timer?
    private var changedToken = MenuBarController.invalidToken
    private var isDisabled = false

    private let work = DispatchQueue(label: "com.awake.app.work", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        statusItem.button?.imagePosition = .imageOnly

        // The helper announces every change, so the normal path is a push, not
        // a poll.
        notify_register_dispatch(Channel.changed, &changedToken, DispatchQueue.main) { [weak self] _ in
            self?.refresh()
        }

        let timer = Timer(timeInterval: Self.backstopInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = Self.backstopTolerance
        RunLoop.main.add(timer, forMode: .common)
        backstop = timer

        render(disabled: SleepState.isDisabled())
        ensureHelper()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if changedToken != Self.invalidToken {
            notify_cancel(changedToken)
        }
    }

    // MARK: - Helper

    private func ensureHelper() {
        guard !Paths.helperIsInstalled else { return }
        work.async { [weak self] in
            let installed = HelperInstaller.requestInstall()
            DispatchQueue.main.async {
                guard let self else { return }
                if installed {
                    self.refresh()
                } else {
                    self.reportMissingHelper()
                }
            }
        }
    }

    private func reportMissingHelper() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Awake could not install its helper"
        alert.informativeText = """
            Awake can still show whether sleep is disabled, but it cannot change \
            it. Quit and reopen Awake to try again.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - State

    private func refresh() {
        work.async { [weak self] in
            let disabled = SleepState.isDisabled()
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
