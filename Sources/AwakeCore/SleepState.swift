import Foundation

/// Reads and describes the system's `SleepDisabled` power-management setting.
public enum SleepState {
    /// Ground truth for every component, so the menu bar, the CLI and the
    /// helper can never disagree about what the current state is.
    ///
    /// This shells out to pmset on purpose. The in-process alternative,
    /// IOPMCopySystemPowerSettings, is private SPI and absent from the public
    /// IOKit headers; the cached copy in the preferences plist lags behind a
    /// write by seconds. pmset costs roughly 0.3 ms of CPU and is only consulted
    /// on an event or on the slow backstop timer.
    public static func isDisabled() -> Bool {
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
}

/// Runs a command to completion, discarding its output.
@discardableResult
public func runSilently(_ path: String, _ arguments: [String]) -> Int32 {
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
