import Foundation

/// The credentials document Claude Code keeps in the login keychain (or `~/.claude/.credentials.json`).
/// Claude Code owns the document and stores more than its own OAuth login in it, so the original
/// bytes are kept and only the rotated fields are rewritten on save.
struct ClaudeCredentialDocument {
    let data: Data
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let subscriptionType: String?
    let scopes: [String]

    init?(data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        self.data = data
        accessToken = token
        refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        subscriptionType = oauth["subscriptionType"] as? String
        scopes = oauth["scopes"] as? [String] ?? []
    }

    /// The document with the fields a token refresh returns replaced. A refresh that omits the
    /// refresh token keeps the stored one.
    func mergingRotated(accessToken: String, refreshToken: String?, expiresAt: Date) -> ClaudeCredentialDocument? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var oauth = object["claudeAiOauth"] as? [String: Any]
        else { return nil }
        oauth["accessToken"] = accessToken
        if let refreshToken, !refreshToken.isEmpty {
            oauth["refreshToken"] = refreshToken
        }
        oauth["expiresAt"] = Int64(expiresAt.timeIntervalSince1970 * 1000)
        object["claudeAiOauth"] = oauth
        guard let merged = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return ClaudeCredentialDocument(data: merged)
    }
}

protocol ClaudeCredentialStoring {
    func load() async -> ClaudeCredentialDocument?
    func save(_ document: ClaudeCredentialDocument) async throws
}
