// awake - command line front end.
//
// Holds no privilege of its own. `on` and `off` post an event that the root
// helper acts on, then wait for pmset to confirm, so the command never reports
// a change it did not observe. It works whether or not the menu bar app is
// running, because the helper is an independent launchd daemon.

import AwakeCore
import Foundation

private let confirmTimeout: TimeInterval = 2.0
private let confirmStep: useconds_t = 50_000  // 50 ms

private let isTTY = isatty(STDOUT_FILENO) == 1
private func green(_ s: String) -> String { isTTY ? "\u{1B}[32m\(s)\u{1B}[0m" : s }
private func yellow(_ s: String) -> String { isTTY ? "\u{1B}[33m\(s)\u{1B}[0m" : s }
private func red(_ s: String) -> String { isTTY ? "\u{1B}[31m\(s)\u{1B}[0m" : s }

func printStatus() {
    if SleepState.isDisabled() {
        print("\(green("awake ON"))  (sleep disabled)")
    } else {
        print("\(yellow("awake OFF")) (sleep enabled)")
    }
}

func request(disable: Bool) -> Never {
    // Already there: report and succeed rather than waiting for an event that
    // would change nothing.
    if SleepState.isDisabled() == disable {
        printStatus()
        exit(0)
    }

    Channel.post(disable ? Channel.on : Channel.off)

    let deadline = Date().addingTimeInterval(confirmTimeout)
    while Date() < deadline {
        usleep(confirmStep)
        if SleepState.isDisabled() == disable {
            if disable {
                print("\(green("awake ON"))  -> Mac will not sleep, even with the lid closed")
            } else {
                print("\(yellow("awake OFF")) -> normal sleep restored")
            }
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

func usage() -> Never {
    print("""
        usage: awake [on|off|status]

          on      disable system sleep, including on lid close
          off     restore normal sleep
          status  report the current setting (default)
        """)
    exit(1)
}

switch CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "status" {
case "on":
    request(disable: true)
case "off":
    request(disable: false)
case "status":
    printStatus()
case "-h", "--help", "help":
    usage()
default:
    usage()
}
