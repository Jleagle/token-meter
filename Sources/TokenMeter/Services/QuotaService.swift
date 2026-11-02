import Foundation
import Combine
import SwiftUI

/// Polls each enabled provider for its quota cards and publishes the combined list.
@MainActor
class QuotaService: ObservableObject {
    typealias Fetcher = @MainActor () async -> [QuotaBucket]

    static let shared: QuotaService = {
        let service = QuotaService(fetchers: liveFetchers(), settings: SettingsManager.shared)
        service.start()
        return service
    }()

    @Published var buckets: [QuotaBucket] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var autoRefreshRemaining: Int = QuotaService.pollIntervalSeconds

    private static let pollIntervalSeconds = 120

    private let fetchers: [QuotaProvider: Fetcher]
    private var enabledProviders: Set<QuotaProvider>
    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?

    init(fetchers: [QuotaProvider: Fetcher], settings: SettingsManager) {
        self.fetchers = fetchers
        self.enabledProviders = settings.enabledProviders
        settingsCancellable = settings.$enabledProviders
            .dropFirst()
            .sink { [weak self] enabled in self?.setEnabledProviders(enabled) }
    }

    /// Polls now and on every tick of the auto-refresh timer after.
    func start() {
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
        defer { isLoading = false }

        guard !enabledProviders.isEmpty else {
            if !buckets.isEmpty { buckets = [] }
            return
        }

        var fetched: [QuotaBucket] = []
        for provider in QuotaProvider.allCases where enabledProviders.contains(provider) {
            fetched += await fetchers[provider]?() ?? []
        }
        // A provider switched off while its poll was in flight stays hidden
        let combined = fetched.filter { enabledProviders.contains(QuotaProvider.of($0)) }
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
    }

    /// Drops the cards of a provider switched off and polls one switched on.
    private func setEnabledProviders(_ enabled: Set<QuotaProvider>) {
        let revealed = enabled.subtracting(enabledProviders)
        enabledProviders = enabled
        let kept = buckets.filter { enabled.contains(QuotaProvider.of($0)) }
        if kept.count != buckets.count { buckets = kept }
        if !revealed.isEmpty {
            Task {
                await refresh()
            }
        }
    }

    private static func liveFetchers() -> [QuotaProvider: Fetcher] {
        let antigravity = AntigravityUsageProvider(
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
        let claude = ClaudeUsageProvider(
            store: ClaudeCredentialStore(),
            transport: URLSessionTransport(),
            installed: {
                FileManager.default.fileExists(
                    atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
                )
            }
        )
        let codex = CodexUsageProvider()
        return [.gemini: antigravity.fetch, .claude: claude.fetch, .codex: codex.fetch]
    }
}
