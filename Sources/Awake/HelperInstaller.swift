import Foundation

/// Installs the privileged helper: the one moment Awake needs a password.
///
/// `make install` normally does this as root, in which case the app finds the
/// helper already present and never prompts at all. This path exists for the
/// other way in -- someone who drags a prebuilt Awake.app into /Applications.
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
            if Paths.helperIsInstalled { return true }
            usleep(100_000)
        }
        return Paths.helperIsInstalled
    }

    /// Runs as root. Also invoked directly by `make install`, which is already
    /// privileged and therefore skips the dialog entirely.
    ///
    /// Nothing is copied: the daemon runs the app's own binary in `--helper`
    /// mode. launchd only insists the program and its path be root-owned and
    /// not writable by others, which the installed bundle already is.
    static func installAsRoot() -> Int32 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Paths.executable) else { return 1 }

        do {
            try daemonPlist.write(toFile: Paths.daemonPlist, atomically: true, encoding: .utf8)
            try fm.setAttributes([.ownerAccountID: 0,
                                  .groupOwnerAccountID: 0,
                                  .posixPermissions: 0o644],
                                 ofItemAtPath: Paths.daemonPlist)
        } catch {
            return 1
        }

        // Left behind by installations before the binaries were merged.
        try? fm.removeItem(atPath: "/usr/local/libexec/awake-helper")

        // Replace any previous instance before loading the new one.
        runSilently("/bin/launchctl", ["bootout", "system/\(Paths.daemonLabel)"])
        return runSilently("/bin/launchctl", ["bootstrap", "system", Paths.daemonPlist])
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
