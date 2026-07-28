import Foundation

/// Filesystem locations for a system-wide installation.
///
/// Awake installs globally rather than per user: the privileged helper is a
/// LaunchDaemon, which must live under /Library regardless, so putting the app
/// and CLI beside it keeps one coherent install instead of a root daemon
/// serving a binary hidden in one user's home directory.
public enum Paths {
    public static let appBundle = "/Applications/Awake.app"
    public static let cli = "/usr/local/bin/awake"

    public static let helperBinary = "/usr/local/libexec/awake-helper"
    public static let daemonPlist = "/Library/LaunchDaemons/com.awake.helper.plist"
    public static let daemonLabel = "com.awake.helper"

    public static let agentPlist = "/Library/LaunchAgents/com.awake.app.plist"
    public static let agentLabel = "com.awake.app"

    /// Both halves must be present; a plist without its binary is a daemon that
    /// launchd will fail to spawn.
    public static var helperIsInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: daemonPlist) && fm.fileExists(atPath: helperBinary)
    }
}
