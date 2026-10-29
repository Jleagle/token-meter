import Foundation
import Combine
import SwiftUI

@MainActor
class QuotaService: ObservableObject {
    static let shared = QuotaService()

    @Published var buckets: [QuotaBucket] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var autoRefreshRemaining: Int = QuotaService.pollIntervalSeconds

    private static let pollIntervalSeconds = 120

    private var timerCancellable: AnyCancellable?

    private let antigravity = AntigravityUsageProvider(
        discover: { await Task.detached { LanguageServerDiscovery.discover() }.value },
        keychainToken: {
            await Task.detached {
                guard let raw = Keychain().readGenericPassword(service: "gemini", account: "antigravity") else {
                    Diagnostics.log("antigravity: keychain item not readable")
                    return nil
                }
                let token = AntigravityKeychainToken.parse(raw: raw)
                if token == nil {
                    Diagnostics.log("antigravity: keychain item read (\(raw.count) chars) but not parseable")
                }
                return token
            }.value
        },
        loopbackTransport: LoopbackTransport(),
        transport: URLSessionTransport()
    )

    private let claude = ClaudeUsageProvider(
        store: ClaudeCredentialStore(),
        transport: URLSessionTransport(),
        installed: {
            FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
            )
        }
    )

    // The Codex usage endpoint rate-limits aggressively, so results are cached
    // and refetched at most once per minute regardless of poll rate; transient
    // failures keep serving the last good data
    private var cachedCodexBuckets: [QuotaBucket] = []
    private var cachedCodexFetchTime: Date?
    private let officialUsageMinInterval: TimeInterval = 60

    private init() {
        startAutoRefreshTimer()
        Task {
            await refresh()
        }
    }

    func startAutoRefreshTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.autoRefreshRemaining > 1 {
                    self.autoRefreshRemaining -= 1
                } else {
                    self.autoRefreshRemaining = QuotaService.pollIntervalSeconds
                    Task {
                        await self.refresh()
                    }
                }
            }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let geminiBuckets = await antigravity.fetch()
        let claudeBuckets = await claude.fetch()
        let codexBuckets = await fetchOfficialCodexBuckets()

        let combined = geminiBuckets + claudeBuckets + codexBuckets
        Diagnostics.log("cards: " + combined.map { "\($0.modelId) left \($0.remainingPercentage)% pace \($0.effectivePacePercentage)%\($0.unavailableReason.map { " (\($0))" } ?? "")" }.joined(separator: ", "))
        if combined.isEmpty {
            errorMessage = "No usage sources found. Sign in to Antigravity, Claude Code or the Codex CLI."
        } else {
            let used = UsageActivity.reducedProvider(from: buckets, to: combined)
            buckets = combined
            lastUpdated = Date()
            autoRefreshRemaining = QuotaService.pollIntervalSeconds
            if let used {
                Diagnostics.log("last used: \(used.name)")
                SettingsManager.shared.lastUsedProvider = used
            }
        }
        isLoading = false
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

    // MARK: - Official Codex / OpenAI Integration

    private func fetchOfficialCodexBuckets() async -> [QuotaBucket] {
        // Only plan accounts are supported. When the Codex CLI is installed but
        // no working session exists, a greyed-out placeholder card is shown
        let codexDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard FileManager.default.fileExists(atPath: codexDir.path) else { return [] }

        let authPath = codexDir.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            return [unavailableBucket(modelId: "official-codex-unavailable", name: "Codex", reason: "Not signed in to the Codex CLI")]
        }

        if let last = cachedCodexFetchTime, Date().timeIntervalSince(last) < officialUsageMinInterval,
           !cachedCodexBuckets.isEmpty {
            return cachedCodexBuckets
        }

        guard let (fraction, resetTimeStr) = await fetchCodexCliUsage(token: token) else {
            return cachedCodexBuckets.isEmpty
                ? [unavailableBucket(modelId: "official-codex-unavailable", name: "Codex", reason: "Usage currently unavailable")]
                : cachedCodexBuckets
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
        cachedCodexBuckets = buckets
        cachedCodexFetchTime = Date()
        return buckets
    }

    private func fetchCodexCliUsage(token: String) async -> (Double, String)? {
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
