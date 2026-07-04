import Foundation

enum AuthError: Error, LocalizedError {
    case missingTokenFile
    case invalidTokenFormat
    case missingRefreshToken
    case refreshRequestFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingTokenFile:
            return "Antigravity OAuth token file not found at ~/.gemini/antigravity-cli/antigravity-oauth-token."
        case .invalidTokenFormat:
            return "Unable to parse OAuth token JSON format."
        case .missingRefreshToken:
            return "No refresh token found in credentials. Please log in with `agy`."
        case .refreshRequestFailed(let msg):
            return "Failed to refresh OAuth token: \(msg)"
        }
    }
}

class AuthManager {
    static let shared = AuthManager()
    
    // These are Google's public OAuth client credentials for Antigravity, not personal
    // secrets. They identify the Antigravity application to Google's OAuth server and are
    // baked into every copy of the Antigravity CLI. For installed/desktop apps Google
    // treats the client_secret as non-confidential. The actual per-user secret is the
    // refresh token, which is read from ~/.gemini at runtime and never stored here.
    private let clientId = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private let clientSecret = "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"
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    
    private var cachedAccessToken: String?
    private var tokenExpiry: Date?
    
    private init() {}
    
    private var tokenFilePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
    }
    
    private var fallbackCredsPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".gemini/oauth_creds.json")
    }
    
    func getValidAccessToken() async throws -> String {
        // Return cached if valid for at least 2 more minutes
        if let token = cachedAccessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(120) {
            return token
        }
        
        let refreshToken = try loadRefreshToken()
        let newToken = try await refreshAccessToken(refreshToken: refreshToken)
        return newToken
    }
    
    private func loadRefreshToken() throws -> String {
        let path: URL
        if FileManager.default.fileExists(atPath: tokenFilePath.path) {
            path = tokenFilePath
        } else if FileManager.default.fileExists(atPath: fallbackCredsPath.path) {
            path = fallbackCredsPath
        } else {
            throw AuthError.missingTokenFile
        }
        
        let data = try Data(contentsOf: path)
        
        // Try OAuthTokenFile format (cli format)
        if let file = try? JSONDecoder().decode(OAuthTokenFile.self, from: data),
           let refresh = file.token.refresh_token, !refresh.isEmpty {
            // Also check if existing access token in file is still valid
            if let access = file.token.access_token, let expiryStr = file.token.expiry {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = formatter.date(from: expiryStr) ?? ISO8601DateFormatter().date(from: expiryStr)
                if let expiry = date, expiry > Date().addingTimeInterval(120) {
                    self.cachedAccessToken = access
                    self.tokenExpiry = expiry
                    return refresh
                }
            }
            return refresh
        }
        
        // Try raw dict format
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let tokenDict = dict["token"] as? [String: Any], let refresh = tokenDict["refresh_token"] as? String {
                return refresh
            }
            if let refresh = dict["refresh_token"] as? String {
                return refresh
            }
        }
        
        throw AuthError.missingRefreshToken
    }
    
    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = [
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let errStr = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw AuthError.refreshRequestFailed(errStr)
        }
        
        let tokenRes = try JSONDecoder().decode(OAuthRefreshResponse.self, from: data)
        let token = tokenRes.access_token
        let expiresIn = TimeInterval(tokenRes.expires_in ?? 3600)
        
        self.cachedAccessToken = token
        self.tokenExpiry = Date().addingTimeInterval(expiresIn)
        
        return token
    }
}
