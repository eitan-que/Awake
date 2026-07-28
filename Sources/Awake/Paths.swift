import Foundation

/// Filesystem locations for a system-wide installation.
///
/// Awake installs globally rather than per user: the privileged helper is a
/// LaunchDaemon, which must live under /Library either way.
///
/// There is one executable. The daemon, the CLI and the menu bar app are the
/// same binary in three modes, so the daemon runs the app's own binary in place
/// and the CLI is a symlink to it -- nothing is copied anywhere.
enum Paths {
    static let appBundle = "/Applications/Awake.app"
    static let executable = "\(appBundle)/Contents/MacOS/Awake"
    static let cliDirectory = "/usr/local/bin"
    static let cli = "\(cliDirectory)/awake"

    static let daemonPlist = "/Library/LaunchDaemons/com.awake.helper.plist"
    static let daemonLabel = "com.awake.helper"

    static let agentPlist = "/Library/LaunchAgents/com.awake.app.plist"
    static let agentLabel = "com.awake.app"

    /// Whether the one privileged piece is in place. The CLI reports on this
    /// alone, because it is all `awake on` needs.
    static var helperIsInstalled: Bool {
        FileManager.default.fileExists(atPath: daemonPlist)
    }

    /// Everything `--install-daemon` puts in place. Deliberately stricter than
    /// `helperIsInstalled`: a version installed from the disk image before the
    /// command and the login agent were part of that step reads as incomplete,
    /// so opening the app once finishes the job.
    static var isFullyInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: daemonPlist)
            && fm.fileExists(atPath: agentPlist)
            && fm.fileExists(atPath: cli)
    }
}
