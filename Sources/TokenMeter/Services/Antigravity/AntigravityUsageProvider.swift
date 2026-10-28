import Foundation

struct LanguageServerLocation: Equatable {
    let csrf: String
    let ports: [Int]
    let extensionPort: Int?
}

/// Gemini quota from Antigravity. The running language server is asked first; with the app
/// closed, Google's Cloud Code API is asked with the OAuth login Antigravity keeps in the keychain,
/// refreshed through Google OAuth when it has expired. A refreshed token lives in memory only;
/// Antigravity's keychain item is never written.
@MainActor
final class AntigravityUsageProvider {
    static let languageServerService = "exa.language_server_pb.LanguageServerService"
    static let summaryMethod = "RetrieveUserQuotaSummary"
    static let cloudCodeHosts = [
        "https://cloudcode-pa.googleapis.com",
        "https://daily-cloudcode-pa.googleapis.com",
    ]
    static let summaryPath = "/v1internal:retrieveUserQuotaSummary"
    static let googleTokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    // Google's OAuth client for the Antigravity app. Installed-app clients ship their secret in
    // every copy of the app, so Google does not treat it as confidential; the per-user secret is
    // the refresh token, which is read from the keychain at runtime and never stored here.
    static let googleClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let googleClientSecret = "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"
    private static let expiryMargin: TimeInterval = 60

    private let discover: () async -> [LanguageServerLocation]
    private let keychainToken: () async -> AntigravityKeychainToken?
    private let loopbackTransport: HTTPTransport
    private let transport: HTTPTransport
    private let now: () -> Date

    private struct CachedToken {
        let accessToken: String
        let expiresAt: Date
        let refreshToken: String
    }

    private var cachedToken: CachedToken?
    private var lastGood: [QuotaBucket] = []

    init(
        discover: @escaping () async -> [LanguageServerLocation],
        keychainToken: @escaping () async -> AntigravityKeychainToken?,
        loopbackTransport: HTTPTransport,
        transport: HTTPTransport,
        now: @escaping () -> Date = Date.init
    ) {
        self.discover = discover
        self.keychainToken = keychainToken
        self.loopbackTransport = loopbackTransport
        self.transport = transport
        self.now = now
    }

    func fetch() async -> [QuotaBucket] {
        if let buckets = await probeLanguageServer() {
            lastGood = buckets
            return buckets
        }
        guard let keychain = await keychainToken() else {
            cachedToken = nil
            lastGood = []
            return []
        }
        switch await probeCloudCode(keychain) {
        case .success(let buckets):
            lastGood = buckets
            return buckets
        case .signInExpired:
            cachedToken = nil
            lastGood = []
            return [placeholder("Antigravity sign-in expired — open Antigravity or run agy")]
        case .unavailable:
            return lastGood.isEmpty ? [placeholder("Usage currently unavailable")] : lastGood
        }
    }

    // MARK: - Language server

    private func probeLanguageServer() async -> [QuotaBucket]? {
        for server in await discover() {
            var endpoints: [(scheme: String, port: Int)] = []
            for port in server.ports {
                endpoints.append(("https", port))
                endpoints.append(("http", port))
            }
            if let extensionPort = server.extensionPort {
                endpoints.append(("http", extensionPort))
            }
            for endpoint in endpoints {
                let path = "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)/\(Self.languageServerService)/\(Self.summaryMethod)"
                guard let url = URL(string: path) else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 3
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
                if !server.csrf.isEmpty {
                    request.setValue(server.csrf, forHTTPHeaderField: "x-codeium-csrf-token")
                }
                request.httpBody = Data("{\"forceRefresh\": true}".utf8)
                guard let (data, http) = try? await loopbackTransport.send(request),
                      (200...299).contains(http.statusCode),
                      let buckets = AntigravitySummaryParser.buckets(from: [data]),
                      !buckets.isEmpty
                else { continue }
                return buckets
            }
        }
        return nil
    }

    // MARK: - Cloud Code

    private enum CloudOutcome {
        case success([QuotaBucket])
        case signInExpired
        case unavailable
    }

    private func probeCloudCode(_ keychain: AntigravityKeychainToken) async -> CloudOutcome {
        let usableAfter = now().addingTimeInterval(Self.expiryMargin)
        var tokens: [String] = []
        if let access = keychain.accessToken, keychain.expiry.map({ $0 > usableAfter }) ?? true {
            tokens.append(access)
        }
        if let cached = cachedToken, cached.refreshToken == keychain.refreshToken,
           cached.expiresAt > usableAfter, !tokens.contains(cached.accessToken) {
            tokens.append(cached.accessToken)
        }

        var sawAuthFailure = false
        for token in tokens {
            switch await fetchSummary(token: token) {
            case .ok(let buckets): return .success(buckets)
            case .authFailed: sawAuthFailure = true
            case .unavailable: break
            }
        }
        // Only an auth failure (or nothing left to try) justifies a refresh; a transient outage
        // must not turn every poll into a Google OAuth call
        guard sawAuthFailure || tokens.isEmpty else { return .unavailable }
        guard let refreshToken = keychain.refreshToken, !refreshToken.isEmpty else { return .signInExpired }

        switch await refreshGoogleToken(refreshToken) {
        case .refreshed(let accessToken, let expiresIn):
            cachedToken = CachedToken(accessToken: accessToken, expiresAt: now().addingTimeInterval(expiresIn), refreshToken: refreshToken)
            switch await fetchSummary(token: accessToken) {
            case .ok(let buckets): return .success(buckets)
            case .authFailed: return .signInExpired
            case .unavailable: return .unavailable
            }
        case .authFailed:
            return .signInExpired
        case .unavailable:
            return .unavailable
        }
    }

    private enum SummaryOutcome {
        case ok([QuotaBucket])
        case authFailed
        case unavailable
    }

    /// Asks production first and stops there when its answer carries both Gemini buckets; the daily
    /// host can omit a whole pool, so an incomplete answer is merged with the daily one.
    private func fetchSummary(token: String) async -> SummaryOutcome {
        var bodies: [Data] = []
        var authFailed = false
        for (index, host) in Self.cloudCodeHosts.enumerated() {
            guard let url = URL(string: host + Self.summaryPath) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
            request.httpBody = Data("{}".utf8)
            guard let (data, http) = try? await transport.send(request) else { continue }
            if http.statusCode == 401 || http.statusCode == 403 {
                authFailed = true
                break
            }
            guard (200...299).contains(http.statusCode) else { continue }
            bodies.append(data)
            if index == 0, AntigravitySummaryParser.isComplete(data) { break }
        }
        if let buckets = AntigravitySummaryParser.buckets(from: bodies) {
            return .ok(buckets)
        }
        return authFailed ? .authFailed : .unavailable
    }

    private enum RefreshOutcome {
        case refreshed(accessToken: String, expiresIn: TimeInterval)
        case authFailed
        case unavailable
    }

    private func refreshGoogleToken(_ refreshToken: String) async -> RefreshOutcome {
        let form = [
            "client_id": Self.googleClientID,
            "client_secret": Self.googleClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        .map { "\($0.key)=\(Self.formEncoded($0.value))" }
        .joined(separator: "&")

        var request = URLRequest(url: Self.googleTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)
        guard let (data, http) = try? await transport.send(request) else { return .unavailable }
        switch http.statusCode {
        case 200...299:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let accessToken = json["access_token"] as? String, !accessToken.isEmpty
            else { return .unavailable }
            return .refreshed(accessToken: accessToken, expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
        case 401:
            return .authFailed
        case 400 where OAuthResponse.isInvalidGrant(data):
            return .authFailed
        default:
            return .unavailable
        }
    }

    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func placeholder(_ reason: String) -> QuotaBucket {
        QuotaBucket(
            resetTime: nil,
            tokenType: nil,
            modelId: "gemini-unavailable",
            remainingFraction: nil,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: "Gemini",
            unavailableReason: reason
        )
    }
}
