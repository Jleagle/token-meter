import Foundation
@testable import TokenMeter

final class StubTransport: HTTPTransport {
    struct Response {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private(set) var requests: [URLRequest] = []
    var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    /// A queued response with status 0 is delivered as a transport error.
    static let connectionFailure = Response(status: 0, body: "")

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
        let response = responses.removeFirst()
        guard response.status > 0 else { throw URLError(.cannotConnectToHost) }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: response.headers)!
        return (Data(response.body.utf8), http)
    }
}

final class StubClaudeCredentialStore: ClaudeCredentialStoring {
    struct SaveFailed: Error {}

    var document: ClaudeCredentialDocument?
    var failNextSave = false
    private(set) var saved: ClaudeCredentialDocument?

    init(document: ClaudeCredentialDocument?) {
        self.document = document
    }

    func load() async -> ClaudeCredentialDocument? { document }

    func save(_ document: ClaudeCredentialDocument) async throws {
        if failNextSave {
            failNextSave = false
            throw SaveFailed()
        }
        saved = document
        self.document = document
    }
}

func claudeCredentialDocument(accessToken: String = "old", refreshToken: String = "r1", expiresAt: Date = Date().addingTimeInterval(3600)) -> ClaudeCredentialDocument {
    let json: [String: Any] = [
        "claudeAiOauth": [
            "accessToken": accessToken,
            "refreshToken": refreshToken,
            "expiresAt": expiresAt.timeIntervalSince1970 * 1000,
            "subscriptionType": "max",
            "scopes": ["user:profile", "user:inference"],
        ],
        "mcpOAuth": ["server": ["accessToken": "mcp"]],
    ]
    return ClaudeCredentialDocument(data: try! JSONSerialization.data(withJSONObject: json))!
}
