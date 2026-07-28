import Foundation

/// The `SleepDisabled` power-management setting, and the published copy of it
/// that keeps every component in step.
///
/// Two sources, deliberately ranked:
///
/// 1. **Published state** -- what the helper wrote after confirming the change
///    actually took. Free to read and always settled.
/// 2. **pmset** -- the underlying truth. Used to seed the published value, to
///    catch changes made by something other than Awake, and whenever nothing
///    has published yet.
///
/// Reading pmset immediately after writing it can still report the old value
/// for a moment, which is the whole reason the published copy exists: without
/// it, an observer woken by the change event samples a setting mid-flight and
/// renders a stale answer until the next backstop.
enum SleepState {

    // MARK: Published

    /// Encoded so that "nothing has published yet" is distinguishable from
    /// "published as off". notify hands back 0 for a name no one has written.
    private enum Published: UInt64 {
        case unset = 0
        case enabled = 1   // sleep works normally
        case disabled = 2  // sleep is suppressed
    }

    /// The helper's confirmed value, or nil if it has not published one.
    static func published(via token: NotifyToken) -> Bool? {
        switch token.state.flatMap(Published.init(rawValue:)) {
        case .disabled: return true
        case .enabled: return false
        case .unset, nil: return nil
        }
    }

    /// Only the helper calls this; a single writer is what makes the value
    /// authoritative rather than one more opinion.
    static func publish(_ disabled: Bool, via token: NotifyToken) {
        token.state = (disabled ? Published.disabled : .enabled).rawValue
    }

    // MARK: pmset

    /// Reads the setting from pmset.
    ///
    /// Shelling out is deliberate. The in-process alternative,
    /// IOPMCopySystemPowerSettings, is private SPI absent from the public IOKit
    /// headers, and the cached copy in the preferences plist lags a write by
    /// seconds. This costs about 0.3 ms of CPU and is off the fast path.
    static func fromPmset() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return false }

        // Drain before waiting: the reverse order deadlocks once output fills
        // the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return false }
        for line in output.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
        }
        return false
    }

    /// Best available answer: the settled value when there is one.
    static func current(via token: NotifyToken?) -> Bool {
        if let token, let value = published(via: token) { return value }
        return fromPmset()
    }
}

/// Runs a command to completion, discarding its output.
@discardableResult
func runSilently(_ path: String, _ arguments: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    } catch {
        return -1
    }
}
