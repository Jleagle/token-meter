import Foundation

enum RetryAfter {
    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter
    }()

    static func seconds(header: String?, now: Date) -> Int? {
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let seconds = Int(raw), seconds >= 0 { return seconds }
        if let date = httpDate.date(from: raw) { return max(0, Int(ceil(date.timeIntervalSince(now)))) }
        return nil
    }
}

/// Claude plan usage read through the Claude Code OAuth session.
///
/// The usage endpoint rate-limits aggressively, so results are reused for a minute, a 429 starts a
/// cooldown during which the last good cards are served with a stale note, and an expired access
/// token is refreshed with the stored refresh token and written back so Claude Code keeps working.
@MainActor
final class ClaudeUsageProvider {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    // Claude Code's public OAuth client; the per-user secret is the refresh token
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let userAgent = "claude-cli/2.1.309 (external, cli)"
    static let minimumInterval: TimeInterval = 60
    static let defaultCooldown: TimeInterval = 300
    // Refresh ahead of expiry so a request never goes out with a token about to lapse
    private static let expiryMargin: TimeInterval = 60

    private let store: ClaudeCredentialStoring
    private let transport: HTTPTransport
    private let installed: () -> Bool
    private let now: () -> Date

    private var lastGood: [QuotaBucket] = []
    private var lastFetch: Date?
    private var cooldownUntil: Date?
    // A rotation the store could not persist yet. The old refresh token is dead once Anthropic
    // rotates it, so the rotated document must survive until the write succeeds.
    private var pendingRotation: (replacedAccessToken: String, document: ClaudeCredentialDocument)?

    init(store: ClaudeCredentialStoring, transport: HTTPTransport, installed: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.transport = transport
        self.installed = installed
        self.now = now
    }

    func fetch() async -> [QuotaBucket] {
        guard var document = await store.load() else {
            lastGood = []
            lastFetch = nil
            return installed() ? [placeholder("Not signed in to Claude Code")] : []
        }
        if let pending = pendingRotation {
            if document.accessToken == pending.replacedAccessToken {
                document = pending.document
                if (try? await store.save(pending.document)) != nil {
                    pendingRotation = nil
                }
            } else {
                pendingRotation = nil
            }
        }
        let now = self.now()
        if let last = lastFetch, now.timeIntervalSince(last) < Self.minimumInterval, !lastGood.isEmpty {
            return lastGood
        }
        if let until = cooldownUntil, until > now {
            return limited(until: until)
        }
        cooldownUntil = nil

        if let expiresAt = document.expiresAt, expiresAt <= now.addingTimeInterval(Self.expiryMargin) {
            switch await refresh(document) {
            case .rotated(let rotated): document = rotated
            case .rejected: return sessionExpired()
            case .unavailable: return unavailable()
            }
        }

        var outcome = await usage(token: document.accessToken)
        if case .unauthorized = outcome {
            switch await refresh(document) {
            case .rotated(let rotated):
                document = rotated
                outcome = await usage(token: document.accessToken)
            case .rejected: return sessionExpired()
            case .unavailable: return unavailable()
            }
        }

        switch outcome {
        case .ok(let data):
            lastGood = ClaudeUsageMapper.buckets(from: data)
            lastFetch = now
            return lastGood
        case .unauthorized:
            return sessionExpired()
        case .rateLimited(let retryAfter):
            let until = now.addingTimeInterval(TimeInterval(retryAfter ?? Int(Self.defaultCooldown)))
            cooldownUntil = until
            return limited(until: until)
        case .failed:
            return unavailable()
        }
    }

    // MARK: - Requests

    private enum UsageOutcome {
        case ok(Data)
        case unauthorized
        case rateLimited(retryAfter: Int?)
        case failed
    }

    private func usage(token: String) async -> UsageOutcome {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Self.applyClientHeaders(to: &request)
        guard let (data, http) = try? await transport.send(request) else { return .failed }
        switch http.statusCode {
        case 200...299: return .ok(data)
        case 401, 403: return .unauthorized
        case 429: return .rateLimited(retryAfter: RetryAfter.seconds(header: http.value(forHTTPHeaderField: "Retry-After"), now: now()))
        default: return .failed
        }
    }

    private enum RefreshOutcome {
        case rotated(ClaudeCredentialDocument)
        case rejected
        case unavailable
    }

    private func refresh(_ document: ClaudeCredentialDocument) async -> RefreshOutcome {
        guard let refreshToken = document.refreshToken else { return .rejected }
        var body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        if !document.scopes.isEmpty {
            body["scope"] = document.scopes.joined(separator: " ")
        }
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        Self.applyClientHeaders(to: &request)

        guard let (data, http) = try? await transport.send(request) else { return .unavailable }
        switch http.statusCode {
        case 200...299:
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let accessToken = json["access_token"] as? String, !accessToken.isEmpty
            else { return .unavailable }
            let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
            guard let rotated = document.mergingRotated(
                accessToken: accessToken,
                refreshToken: json["refresh_token"] as? String,
                expiresAt: now().addingTimeInterval(expiresIn)
            ) else { return .unavailable }
            do {
                try await store.save(rotated)
                pendingRotation = nil
            } catch {
                pendingRotation = (document.accessToken, rotated)
            }
            return .rotated(rotated)
        case 401:
            return .rejected
        case 400 where OAuthResponse.isInvalidGrant(data):
            return .rejected
        default:
            return .unavailable
        }
    }

    private static func applyClientHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }

    // MARK: - Results

    private func sessionExpired() -> [QuotaBucket] {
        lastGood = []
        lastFetch = nil
        return [placeholder("Session expired — open Claude Code to sign in")]
    }

    private func unavailable() -> [QuotaBucket] {
        lastGood.isEmpty ? [placeholder("Usage currently unavailable")] : lastGood
    }

    private func limited(until: Date) -> [QuotaBucket] {
        let minutes = max(1, Int(ceil(until.timeIntervalSince(now()) / 60)))
        if lastGood.isEmpty {
            return [placeholder("Rate limited by Anthropic, retry in ~\(minutes)m")]
        }
        return lastGood.map { bucket in
            var stale = bucket
            stale.staleNote = "Rate limited, retry in ~\(minutes)m"
            return stale
        }
    }

    private func placeholder(_ reason: String) -> QuotaBucket {
        QuotaBucket(
            resetTime: nil,
            tokenType: nil,
            modelId: "official-claude-unavailable",
            remainingFraction: nil,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: "Claude",
            unavailableReason: reason
        )
    }
}
