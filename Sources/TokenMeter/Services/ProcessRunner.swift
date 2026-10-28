import Foundation

enum ProcessRunner {
    struct Output {
        let status: Int32
        let stdout: String
    }

    /// Runs an executable to completion and captures its standard output. Nil when it cannot be
    /// launched. A process still running after `timeout` is terminated.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return Output(status: process.terminationStatus, stdout: String(decoding: data, as: UTF8.self))
    }
}
