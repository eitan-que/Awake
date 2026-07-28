// Awake - keep a Mac from sleeping, from the menu bar or the command line.
//
// One executable, four modes. The menu bar app, the `awake` command and the
// privileged daemon are the same binary invoked differently, so there is
// nothing to keep in sync between separate builds and nothing to copy at
// install time: the daemon runs this file in place and the CLI is a symlink to
// it.

import Cocoa

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--helper":
    // Privileged mode, launched by launchd as root.
    Helper.run()

case "--install-daemon":
    // Privileged one-shot, from `make install` or the app's authorization.
    exit(HelperInstaller.installAsRoot())

case "--menubar":
    break

case nil where isatty(STDOUT_FILENO) != 1:
    // No arguments and no terminal means a Finder or LaunchServices open,
    // which wants the app rather than a status line printed into the void.
    break

default:
    CommandLineInterface.run(arguments)
}

let application = NSApplication.shared
let controller = MenuBarController()
application.delegate = controller
application.run()
