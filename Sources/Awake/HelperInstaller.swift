import Foundation

/// Installs everything that lives outside the app bundle: the one moment Awake
/// needs a password.
///
/// `make install` normally does this as root, in which case the app finds it
/// all present and never prompts at all. This path exists for the other way in
/// -- someone who drags a prebuilt Awake.app in from the disk image. Both
/// routes run the same `--install-daemon` code, so what the disk image gets is
/// what building from source gets.
enum HelperInstaller {

    /// Asks for the password once, then re-runs this binary as root in
    /// `--install-daemon` mode.
    ///
    /// AppleScript rather than Authorization Services: the classic escalation
    /// call, AuthorizationExecuteWithPrivileges, is marked unavailable in the
    /// macOS 26 SDK, and its supported replacement (SMAppService) requires a
    /// Developer ID signature an open-source build cannot assume. `with prompt`
    /// at least puts Awake's own wording in the dialog.
    static func requestInstall() -> Bool {
        let toolPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let command = "\(shellQuoted(toolPath)) --install-daemon"
        let prompt = "Awake needs to install a background helper so it can turn "
            + "system sleep on and off. You are asked for this only once."

        let script = "do shell script \"\(appleScriptQuoted(command))\""
            + " with prompt \"\(appleScriptQuoted(prompt))\""
            + " with administrator privileges"

        guard runSilently("/usr/bin/osascript", ["-e", script]) == 0 else { return false }

        // launchctl bootstrap is asynchronous; wait for the daemon to land
        // rather than reporting success the instant osascript returns.
        for _ in 0..<40 {
            if Paths.isFullyInstalled { return true }
            usleep(100_000)
        }
        return Paths.isFullyInstalled
    }

    /// Runs as root. Also invoked directly by `make install`, which is already
    /// privileged and therefore skips the dialog entirely.
    ///
    /// Nothing is copied: the daemon runs the app's own binary in `--helper`
    /// mode and the command is a symlink to it. launchd only insists the
    /// program and its path be root-owned and not writable by others, which the
    /// installed bundle already is.
    ///
    /// Requires the app to be in /Applications, because that path is baked into
    /// both plists and the symlink. Running it from anywhere else would install
    /// jobs pointing at a bundle the user is free to move or delete.
    static func installAsRoot() -> Int32 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.executable) else { return 1 }

        do {
            try install(daemonPlist, at: Paths.daemonPlist)
            try install(agentPlist, at: Paths.agentPlist)
            try linkCommand()
        } catch {
            return 1
        }

        // Left behind by installations before the binaries were merged.
        try? fm.removeItem(atPath: "/usr/local/libexec/awake-helper")

        // Replace any previous instance before loading the new one.
        runSilently("/bin/launchctl", ["bootout", "system/\(Paths.daemonLabel)"])
        let status = runSilently("/bin/launchctl", ["bootstrap", "system", Paths.daemonPlist])

        loadAgent()
        return status
    }

    private static func install(_ contents: String, at path: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.ownerAccountID: 0,
                                               .groupOwnerAccountID: 0,
                                               .posixPermissions: 0o644],
                                              ofItemAtPath: path)
    }

    private static func linkCommand() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Paths.cliDirectory,
                               withIntermediateDirectories: true,
                               attributes: [.ownerAccountID: 0, .groupOwnerAccountID: 0])
        // Replaced rather than skipped if present: an earlier install may have
        // left a link to a path that no longer exists, and creating a symlink
        // over an occupied name fails.
        try? fm.removeItem(atPath: Paths.cli)
        try fm.createSymbolicLink(atPath: Paths.cli, withDestinationPath: Paths.executable)
    }

    /// The menu bar agent belongs to a GUI session, which root is not in, so it
    /// has to be bootstrapped into the logged-in user's domain by uid.
    ///
    /// Skipped when there is no GUI user -- an install over SSH, say. The plist
    /// is on disk either way, so launchd starts the agent at the next login.
    private static func loadAgent() {
        guard let uid = guiUserID else { return }
        runSilently("/bin/launchctl", ["bootout", "gui/\(uid)/\(Paths.agentLabel)"])
        runSilently("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.agentPlist])
    }

    /// Under `sudo make install` the invoking user is the one to target. When
    /// the app escalates on first launch there is no such variable, and the
    /// owner of /dev/console is whoever holds the GUI session.
    private static var guiUserID: uid_t? {
        if let value = ProcessInfo.processInfo.environment["SUDO_UID"],
           let uid = uid_t(value), uid != 0 {
            return uid
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console")
        guard let owner = attributes?[.ownerAccountID] as? NSNumber else { return nil }
        let uid = uid_t(owner.uint32Value)
        return uid == 0 ? nil : uid
    }

    /// Embedded rather than shipped as a file next to the Makefile, so that an
    /// app dragged out of the disk image carries its own launchd jobs and there
    /// is one copy of each to keep correct.
    private static var agentPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(Paths.agentLabel)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(Paths.executable)</string>
        \t\t<string>--menubar</string>
        \t</array>
        \t<key>AssociatedBundleIdentifiers</key>
        \t<array>
        \t\t<string>com.awake.app</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<dict>
        \t\t<key>SuccessfulExit</key>
        \t\t<false/>
        \t</dict>
        </dict>
        </plist>

        """
    }

    private static var daemonPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(Paths.daemonLabel)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(Paths.executable)</string>
        \t\t<string>--helper</string>
        \t</array>
        \t<key>AssociatedBundleIdentifiers</key>
        \t<array>
        \t\t<string>com.awake.app</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<true/>
        </dict>
        </plist>

        """
    }
}

func shellQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptQuoted(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
