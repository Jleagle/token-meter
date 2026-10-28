import Foundation

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    /// Parses RFC 3339 timestamps with any fractional-second precision. Foundation only accepts
    /// millisecond fractions, while Go (the Antigravity CLI) writes nanoseconds and Anthropic
    /// writes microseconds, so longer fractions are truncated to milliseconds before parsing.
    static func date(from raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = fractional.date(from: value) ?? plain.date(from: value) {
            return date
        }
        guard let range = value.range(of: #"\.\d+"#, options: .regularExpression) else { return nil }
        let digits = value[range].dropFirst().prefix(3)
        return fractional.date(from: value.replacingCharacters(in: range, with: "." + digits))
    }
}
