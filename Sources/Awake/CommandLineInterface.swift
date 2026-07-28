import Foundation

/// The `awake` command.
///
/// Holds no privilege. `on` and `off` post a request the helper acts on, then
/// wait for the helper to publish a confirmed result, so the command never
/// reports a change it did not observe. Works whether or not the menu bar app
/// is running, because the helper is an independent launchd daemon.
enum CommandLineInterface {

    private static let confirmTimeout: TimeInterval = 3.0
    private static let confirmStep: useconds_t = 10_000  // 10 ms

    private static let isTTY = isatty(STDOUT_FILENO) == 1
    private static func green(_ s: String) -> String { isTTY ? "\u{1B}[32m\(s)\u{1B}[0m" : s }
    private static func yellow(_ s: String) -> String { isTTY ? "\u{1B}[33m\(s)\u{1B}[0m" : s }
    private static func red(_ s: String) -> String { isTTY ? "\u{1B}[31m\(s)\u{1B}[0m" : s }
    private static func dim(_ s: String) -> String { isTTY ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
    private static func bold(_ s: String) -> String { isTTY ? "\u{1B}[1m\(s)\u{1B}[0m" : s }

    static func run(_ arguments: [String]) -> Never {
        let token = NotifyToken(checking: Channel.changed)

        switch arguments.first ?? "" {
        case "on":
            request(disable: true, token: token)
        case "off":
            request(disable: false, token: token)
        case "status":
            print(statusLine(token: token))
            exit(0)
        case "", "help", "-h", "--help":
            overview(token: token)
        default:
            FileHandle.standardError.write(Data("awake: unknown command '\(arguments[0])'\n".utf8))
            overview(token: token, exitCode: 1)
        }
    }

    // MARK: Output

    private static func statusLine(token: NotifyToken?) -> String {
        SleepState.current(via: token)
            ? "\(green("ON"))  \(dim("sleep disabled, including on lid close"))"
            : "\(yellow("OFF")) \(dim("this Mac sleeps normally"))"
    }

    /// Shown when `awake` is run with no arguments: where things stand, and
    /// what can be done about it, without having to remember a subcommand.
    private static func overview(token: NotifyToken?, exitCode: Int32 = 0) -> Never {
        var lines = [
            "",
            "  \(bold("Awake"))  \(dim("keep this Mac from sleeping"))",
            "",
            "  Status   \(statusLine(token: token))",
            "",
            "  \(bold("awake on"))       disable sleep, even with the lid closed",
            "  \(bold("awake off"))      restore normal sleep",
            "  \(bold("awake status"))   print just the status line",
            "  \(bold("awake help"))     show this",
            "",
        ]

        if !Paths.helperIsInstalled {
            lines.append("  \(red("The helper is not installed."))"
                + " Open Awake once to install it.")
            lines.append("")
        }

        print(lines.joined(separator: "\n"))
        exit(exitCode)
    }

    // MARK: Requests

    private static func request(disable: Bool, token: NotifyToken?) -> Never {
        if SleepState.current(via: token) == disable {
            print(statusLine(token: token))
            exit(0)
        }

        Channel.post(disable ? Channel.on : Channel.off)

        // The helper publishes only after the change is observable, so seeing
        // the value flip here means it has genuinely landed.
        let deadline = Date().addingTimeInterval(confirmTimeout)
        while Date() < deadline {
            usleep(confirmStep)
            if SleepState.current(via: token) == disable {
                print(statusLine(token: token))
                exit(0)
            }
        }

        let message = """
            \(red("awake: no response from the Awake helper."))
            Inspect it with: launchctl print system/\(Paths.daemonLabel)
            If it is missing, open Awake once and it will reinstall the helper.

            """
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
}
