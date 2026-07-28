// Awake - menu bar control for macOS system sleep.
//
// Two entry points live here. Run with --install-daemon (as root, either from
// `make install` or from the app's own one-time authorization) the process
// installs the privileged helper and exits. Run with no arguments it becomes
// the menu bar app.

import AwakeCore
import Cocoa

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--install-daemon" {
    exit(HelperInstaller.installAsRoot())
}

let application = NSApplication.shared
let controller = MenuBarController()
application.delegate = controller
application.run()
