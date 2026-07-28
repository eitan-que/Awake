import AwakeCore
import Foundation

/// Installs the privileged helper: the one moment Awake needs a password.
///
/// `make install` normally does this as root, in which case the app finds the
/// helper already present and never prompts at all. This path exists for the
/// other way in -- someone who drags a prebuilt Awake.app into /Applications.
public enum HelperInstaller {

    /// Asks for the password once, then re-runs this binary as root in
    /// `--install-daemon` mode.
    ///
    /// AppleScript rather than Authorization Services: the classic escalation
    /// call, AuthorizationExecuteWithPrivileges, is marked unavailable in the
    /// macOS 26 SDK, and its supported replacement (SMAppService) requires a
    /// Developer ID signature an open-source build cannot assume. `with prompt`
    /// at least puts Awake's own wording in the dialog.
    public static func requestInstall() -> Bool {
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
    public static func installAsRoot() -> Int32 {
        let fm = FileManager.default
        let selfPath = Bundle.main.executablePath ?? CommandLine.arguments[0]

        // .../Contents/MacOS/Awake -> .../Contents/Helpers/awake-helper.
        // Helpers get their own directory because the filesystem is
        // case-insensitive: "Awake" and "awake" cannot share a folder.
        let source = URL(fileURLWithPath: selfPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/awake-helper")
            .path

        guard fm.fileExists(atPath: source) else { return 1 }

        do {
            try fm.createDirectory(atPath: (Paths.helperBinary as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)

            if fm.fileExists(atPath: Paths.helperBinary) {
                try fm.removeItem(atPath: Paths.helperBinary)
            }
            try fm.copyItem(atPath: source, toPath: Paths.helperBinary)

            // launchd refuses to load anything writable by a non-root user.
            try fm.setAttributes([.ownerAccountID: 0,
                                  .groupOwnerAccountID: 0,
                                  .posixPermissions: 0o755],
                                 ofItemAtPath: Paths.helperBinary)

            try daemonPlist.write(toFile: Paths.daemonPlist, atomically: true, encoding: .utf8)
            try fm.setAttributes([.ownerAccountID: 0,
                                  .groupOwnerAccountID: 0,
                                  .posixPermissions: 0o644],
                                 ofItemAtPath: Paths.daemonPlist)
        } catch {
            return 1
        }

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
        \t\t<string>\(Paths.helperBinary)</string>
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
