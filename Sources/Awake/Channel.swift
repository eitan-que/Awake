import Foundation
import notify

/// notify(3) channels shared by every mode of the binary.
///
/// notify(3) is the lightest IPC macOS offers: registering costs nothing while
/// idle, and a post wakes only the processes that asked for that name.
///
/// The names are global to the machine and unauthenticated. Anything a request
/// could carry is therefore untrusted, which is why request events carry no
/// payload -- they name an intent, and the helper decides what to run.
enum Channel {
    /// Requests. Posted by the menu bar and the CLI, acted on by the helper.
    static let on = "com.awake.on"
    static let off = "com.awake.off"

    /// Announcement plus authoritative state. Only the helper writes it.
    ///
    /// The payload lives in notify's own 64-bit state slot rather than in a
    /// file or a re-read of pmset, which is what keeps every component exactly
    /// in step: observers wake and read the value the helper already confirmed,
    /// instead of racing to sample a setting that has not finished propagating.
    static let changed = "com.awake.changed"

    static func post(_ name: String) {
        notify_post(name)
    }
}

/// A registration held for the lifetime of a component.
///
/// notify tokens are not interchangeable: state is read and written through a
/// token, so a component that wants both has to keep one around.
final class NotifyToken {
    private(set) var token: Int32 = NOTIFY_TOKEN_INVALID
    private let name: String

    init?(checking name: String) {
        self.name = name
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return nil }
    }

    init?(watching name: String, on queue: DispatchQueue, handler: @escaping () -> Void) {
        self.name = name
        let status = notify_register_dispatch(name, &token, queue) { _ in handler() }
        guard status == NOTIFY_STATUS_OK else { return nil }
    }

    var state: UInt64? {
        get {
            var value: UInt64 = 0
            guard notify_get_state(token, &value) == NOTIFY_STATUS_OK else { return nil }
            return value
        }
        set {
            guard let newValue else { return }
            notify_set_state(token, newValue)
        }
    }

    deinit {
        if token != NOTIFY_TOKEN_INVALID {
            notify_cancel(token)
        }
    }
}
