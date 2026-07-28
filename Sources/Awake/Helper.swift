import Foundation
import notify

/// The privileged mode: the only code in Awake that changes anything.
///
/// Runs as root under launchd (com.awake.helper). Because the daemon survives
/// reboots, the password is asked for once at install time and never again.
///
/// Its whole surface is one action with hardcoded arguments. The events that
/// drive it carry no payload, so there is nothing for a caller to inject. Any
/// local process can post those events, which makes this exactly as privileged
/// as a passwordless sudoers rule for the same two commands -- no more.
enum Helper {

    /// How long to wait for pmset to actually reflect a write before publishing.
    private static let settleTimeout: TimeInterval = 2.0
    private static let settleStep: useconds_t = 20_000  // 20 ms

    /// Catches changes made by something other than Awake, so the published
    /// value cannot drift from reality indefinitely.
    private static let driftInterval: TimeInterval = 60
    private static let driftTolerance: TimeInterval = 15

    static func run() -> Never {
        let queue = DispatchQueue(label: "com.awake.helper")

        guard let publisher = NotifyToken(checking: Channel.changed) else {
            exit(1)
        }

        // Seed the published value before anyone can ask for it.
        SleepState.publish(SleepState.fromPmset(), via: publisher)

        let onToken = NotifyToken(watching: Channel.on, on: queue) {
            apply(disable: true, publisher: publisher)
        }
        let offToken = NotifyToken(watching: Channel.off, on: queue) {
            apply(disable: false, publisher: publisher)
        }
        guard onToken != nil, offToken != nil else { exit(1) }

        let drift = Timer(timeInterval: driftInterval, repeats: true) { _ in
            let actual = SleepState.fromPmset()
            if SleepState.published(via: publisher) != actual {
                SleepState.publish(actual, via: publisher)
                Channel.post(Channel.changed)
            }
        }
        drift.tolerance = driftTolerance
        RunLoop.main.add(drift, forMode: .common)

        // Idle until an event arrives; launchd keeps the process alive.
        RunLoop.main.run()
        exit(0)
    }

    /// Applies the change, waits for it to be observable, then publishes.
    ///
    /// The wait is the point. Announcing as soon as pmset returns is what made
    /// the menu bar lag: observers woke, sampled a setting that had not landed
    /// yet, and showed the old value until the next backstop. Publishing only a
    /// confirmed value means anything reading the announcement is never wrong.
    private static func apply(disable: Bool, publisher: NotifyToken) {
        runSilently("/usr/bin/pmset", ["-a", "disablesleep", disable ? "1" : "0"])

        let deadline = Date().addingTimeInterval(settleTimeout)
        while Date() < deadline {
            if SleepState.fromPmset() == disable { break }
            usleep(settleStep)
        }

        SleepState.publish(SleepState.fromPmset(), via: publisher)
        Channel.post(Channel.changed)
    }
}
