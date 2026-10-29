import Foundation
import os

/// Provider diagnostics: what was found and which calls answered how. Messages carry identifiers
/// and statuses, never token contents. They go to the unified log, and to stderr when the
/// `TOKENMETER_DEBUG` environment variable is set.
enum Diagnostics {
    private static let logger = Logger(subsystem: "com.token.meter", category: "usage")
    private static let echoToStderr = ProcessInfo.processInfo.environment["TOKENMETER_DEBUG"] != nil

    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if echoToStderr {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    }
}
