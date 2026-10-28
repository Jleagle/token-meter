import Foundation

/// The Google OAuth tokens the Antigravity app and `agy` CLI keep in the login keychain
/// (service `gemini`, account `antigravity`). Go's keyring library stores the JSON wrapped as
/// `go-keyring-base64:<base64>`; the JSON is `{"token": {access_token, refresh_token, expiry}}`.
struct AntigravityKeychainToken: Equatable {
    var accessToken: String?
    var refreshToken: String?
    var expiry: Date?

    static func parse(raw: String) -> AntigravityKeychainToken? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "go-keyring-base64:"
        if text.hasPrefix(prefix) {
            let encoded = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: encoded),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty,
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        else { return nil }

        let source = (object["token"] as? [String: Any]) ?? object
        let access = string(in: source, keys: ["access_token", "accessToken"])
        let refresh = string(in: source, keys: ["refresh_token", "refreshToken"])
        guard access != nil || refresh != nil else { return nil }
        let expiry = string(in: source, keys: ["expiry", "expires_at", "expiresAt"]).flatMap(ISO8601.date(from:))
        return AntigravityKeychainToken(accessToken: access, refreshToken: refresh, expiry: expiry)
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
