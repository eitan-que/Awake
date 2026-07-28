import Foundation
import notify

/// notify(3) channels shared by the app, the CLI and the helper.
///
/// notify(3) is the lightest IPC macOS offers: registering costs nothing while
/// idle, and a post wakes only the processes that asked for that name.
///
/// The names are global to the machine and unauthenticated. Anything a request
/// could carry is therefore untrusted, which is why these events carry no
/// payload at all -- they name an intent, and the helper decides what to run.
public enum Channel {
    public static let on = "com.awake.on"
    public static let off = "com.awake.off"
    public static let changed = "com.awake.changed"

    public static func post(_ name: String) {
        notify_post(name)
    }
}
