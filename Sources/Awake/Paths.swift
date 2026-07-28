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
    static let cli = "/usr/local/bin/awake"

    static let daemonPlist = "/Library/LaunchDaemons/com.awake.helper.plist"
    static let daemonLabel = "com.awake.helper"

    static let agentPlist = "/Library/LaunchAgents/com.awake.app.plist"
    static let agentLabel = "com.awake.app"

    static var helperIsInstalled: Bool {
        FileManager.default.fileExists(atPath: daemonPlist)
    }
}
