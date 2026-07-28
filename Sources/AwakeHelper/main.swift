// awake-helper - the only privileged component of Awake.
//
// Installed at /usr/local/libexec/awake-helper and run as root by launchd
// (com.awake.helper). Because the daemon survives reboots, the password is
// asked for once at install time and never again.
//
// Deliberately free of AppKit: a root daemon has no business linking a GUI
// framework, and this one never draws anything.
//
// Its whole surface is one action with hardcoded arguments. The events that
// drive it carry no payload, so there is nothing for a caller to inject. Any
// local process can post those events, which makes this exactly as privileged
// as a passwordless sudoers rule for the same two commands -- no more.

import AwakeCore
import Foundation
import notify

private func apply(disable: Bool) {
    runSilently("/usr/bin/pmset", ["-a", "disablesleep", disable ? "1" : "0"])

    // Wake the menu bar and any CLI waiting for confirmation.
    Channel.post(Channel.changed)
}

var onToken: Int32 = -1
var offToken: Int32 = -1
let queue = DispatchQueue(label: "com.awake.helper")

notify_register_dispatch(Channel.on, &onToken, queue) { _ in apply(disable: true) }
notify_register_dispatch(Channel.off, &offToken, queue) { _ in apply(disable: false) }

// Idle until an event arrives; launchd keeps the process alive.
dispatchMain()
