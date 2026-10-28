import Foundation

enum OAuthResponse {
    /// Whether a token-endpoint error body reports a dead refresh token, the one 400 that means
    /// the user has to sign in again.
    static func isInvalidGrant(_ data: Data) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return json["error"] as? String == "invalid_grant"
    }
}
