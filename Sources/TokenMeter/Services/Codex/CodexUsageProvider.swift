import Foundation

/// Codex plan usage read through the Codex CLI login in `~/.codex/auth.json`.
///
/// The usage endpoint rate-limits aggressively, so results are cached and refetched at most once
/// per minute regardless of poll rate; transient failures keep serving the last good data.
@MainActor
final class CodexUsageProvider {
    private static let minimumInterval: TimeInterval = 60

    private var cachedBuckets: [QuotaBucket] = []
    private var cachedFetchTime: Date?

    /// Only plan accounts are supported. When the Codex CLI is installed but no working session
    /// exists, a greyed-out placeholder card is shown.
    func fetch() async -> [QuotaBucket] {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard FileManager.default.fileExists(atPath: codexDir.path) else { return [] }

        let authPath = codexDir.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            return [unavailableBucket(modelId: "official-codex-unavailable", name: "Codex", reason: "Not signed in to the Codex CLI")]
        }

        if let last = cachedFetchTime, Date().timeIntervalSince(last) < Self.minimumInterval,
           !cachedBuckets.isEmpty {
            return cachedBuckets
        }

        guard let (fraction, resetTimeStr) = await fetchCliUsage(token: token) else {
            return cachedBuckets.isEmpty
                ? [unavailableBucket(modelId: "official-codex-unavailable", name: "Codex", reason: "Usage currently unavailable")]
                : cachedBuckets
        }

        let buckets = [QuotaBucket(
            resetTime: resetTimeStr,
            tokenType: "5h",
            modelId: "official-codex-cli-5h",
            remainingFraction: fraction,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: "Codex - 5 Hour"
        )]
        cachedBuckets = buckets
        cachedFetchTime = Date()
        return buckets
    }

    private func unavailableBucket(modelId: String, name: String, reason: String) -> QuotaBucket {
        QuotaBucket(
            resetTime: nil,
            tokenType: nil,
            modelId: modelId,
            remainingFraction: nil,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: name,
            unavailableReason: reason
        )
    }

    private func fetchCliUsage(token: String) async -> (Double, String)? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return nil
        }

        var fraction = 1.0
        var resetTimeStr = calculateFiveHourResetTime()

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 4.0

            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let usageJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                return nil
            }

            if let rateLimit = usageJson["rate_limit"] as? [String: Any] {
                if let primary = rateLimit["primary_window"] as? [String: Any] {
                    if let usedPct = (primary["used_percent"] as? NSNumber)?.doubleValue {
                        fraction = max(0.0, min(1.0, (100.0 - usedPct) / 100.0))
                    }
                    if let resetAt = (primary["reset_at"] as? NSNumber)?.doubleValue, resetAt > 0 {
                        let resetDate = Date(timeIntervalSince1970: resetAt)
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        resetTimeStr = formatter.string(from: resetDate)
                    }
                }
                if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                    if let usedPct = (secondary["used_percent"] as? NSNumber)?.doubleValue {
                        let secFraction = max(0.0, min(1.0, (100.0 - usedPct) / 100.0))
                        if secFraction < fraction {
                            fraction = secFraction
                            if let resetAt = (secondary["reset_at"] as? NSNumber)?.doubleValue, resetAt > 0 {
                                let resetDate = Date(timeIntervalSince1970: resetAt)
                                let formatter = ISO8601DateFormatter()
                                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                resetTimeStr = formatter.string(from: resetDate)
                            }
                        }
                    }
                }
            }
        } catch {
            return nil
        }

        return (fraction, resetTimeStr)
    }

    private func calculateFiveHourResetTime() -> String {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let currentHour = components.hour ?? 0
        let nextBlockHour = ((currentHour / 5) + 1) * 5

        if nextBlockHour >= 24 {
            components.day = (components.day ?? 0) + 1
            components.hour = nextBlockHour - 24
        } else {
            components.hour = nextBlockHour
        }
        components.minute = 0
        components.second = 0

        if let nextDate = calendar.date(from: components) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: nextDate)
        }
        return ""
    }
}
