import XCTest
@testable import TokenMeter

@MainActor
final class AntigravityUsageProviderTests: XCTestCase {
    private let allIDs = ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"]
    private let summary = """
    {"groups":[
      {"displayName":"Gemini Models","buckets":[
        {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.8,"resetTime":"2026-10-23T22:00:00Z"},
        {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.5,"resetTime":"2026-10-30T00:00:00Z"}]},
      {"displayName":"Claude and GPT models","buckets":[
        {"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.4,"resetTime":"2026-10-31T00:00:00Z"},
        {"bucketId":"3p-5h","window":"5h","remainingFraction":1.0,"resetTime":"2026-10-23T23:00:00Z"}]}
    ]}
    """
    private let partialSummary = """
    {"groups":[{"displayName":"Gemini models","buckets":[
      {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.8}]}]}
    """
    private let primarySummaryURL = "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
    private let fallbackSummaryURL = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"

    private func token(expired: Bool = false, refresh: String? = "rt") -> AntigravityKeychainToken {
        AntigravityKeychainToken(accessToken: "at", refreshToken: refresh, expiry: Date().addingTimeInterval(expired ? -60 : 3600))
    }

    private func provider(
        servers: [LanguageServerLocation] = [],
        keychain: AntigravityKeychainToken? = nil,
        loopback: StubTransport = StubTransport(responses: []),
        cloud: StubTransport = StubTransport(responses: [])
    ) -> AntigravityUsageProvider {
        AntigravityUsageProvider(
            discover: { servers },
            keychainToken: { keychain },
            loopbackTransport: loopback,
            transport: cloud
        )
    }

    func testUsesLanguageServerWhenRunning() async {
        let loopback = StubTransport(responses: [.init(status: 200, body: "{\"response\": \(summary)}")])
        let cloud = StubTransport(responses: [])
        let provider = provider(servers: [LanguageServerLocation(csrf: "token", ports: [5000], extensionPort: nil)], keychain: token(), loopback: loopback, cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.modelId), allIDs)
        XCTAssertTrue(cloud.requests.isEmpty)

        let request = loopback.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://127.0.0.1:5000/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codeium-csrf-token"), "token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
    }

    func testTriesHttpAndExtensionPortWhenHttpsFails() async {
        let loopback = StubTransport(responses: [
            StubTransport.connectionFailure,
            StubTransport.connectionFailure,
            .init(status: 200, body: summary),
        ])
        let provider = provider(servers: [LanguageServerLocation(csrf: "", ports: [5000], extensionPort: 5001)], loopback: loopback)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(loopback.requests.map { $0.url!.absoluteString.prefix(22) }, ["https://127.0.0.1:5000", "http://127.0.0.1:5000/", "http://127.0.0.1:5001/"])
        XCTAssertNil(loopback.requests[2].value(forHTTPHeaderField: "x-codeium-csrf-token"))
    }

    func testFallsBackToCloudCodeWithKeychainToken() async {
        let cloud = StubTransport(responses: [.init(status: 200, body: summary)])
        let provider = provider(keychain: token(), cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.modelId), allIDs)
        XCTAssertEqual(cloud.requests.count, 1)
        let request = cloud.requests[0]
        XCTAssertEqual(request.url?.absoluteString, primarySummaryURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer at")
        // Google leaves the Gemini pool out of the summary unless the caller presents the
        // Antigravity client's own User-Agent shape
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        XCTAssertTrue(userAgent.hasPrefix("antigravity/"), userAgent)
        XCTAssertTrue(userAgent.contains("(aidev_client; os_type=darwin; arch="), userAgent)
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
    }

    func testAsksFallbackHostWhenPrimaryAnswerIsIncomplete() async {
        let cloud = StubTransport(responses: [
            .init(status: 200, body: partialSummary),
            .init(status: 200, body: summary),
        ])
        let provider = provider(keychain: token(), cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.modelId), allIDs)
        XCTAssertEqual(cloud.requests.map { $0.url!.absoluteString }, [primarySummaryURL, fallbackSummaryURL])
    }

    func testRefreshesExpiredGoogleTokenAndReusesIt() async throws {
        let cloud = StubTransport(responses: [
            .init(status: 200, body: #"{"access_token":"fresh","expires_in":3600}"#),
            .init(status: 200, body: summary),
            .init(status: 200, body: summary),
        ])
        let provider = provider(keychain: token(expired: true), cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.count, 4)
        let refresh = cloud.requests[0]
        XCTAssertEqual(refresh.url?.absoluteString, "https://oauth2.googleapis.com/token")
        let form = String(decoding: try XCTUnwrap(refresh.httpBody), as: UTF8.self)
        XCTAssertTrue(form.contains("grant_type=refresh_token"))
        XCTAssertTrue(form.contains("refresh_token=rt"))
        XCTAssertTrue(form.contains("client_id=1071006060591-"))
        XCTAssertEqual(cloud.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fresh")

        _ = await provider.fetch()
        XCTAssertEqual(cloud.requests.count, 3)
        XCTAssertEqual(cloud.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
    }

    func testRefreshesWhenStoredTokenIsRejected() async {
        let cloud = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 200, body: #"{"access_token":"fresh","expires_in":3600}"#),
            .init(status: 200, body: summary),
        ])
        let provider = provider(keychain: token(), cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(cloud.requests[1].url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(cloud.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
    }

    func testSignInExpiredWhenRefreshIsRejected() async {
        let cloud = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 400, body: #"{"error":"invalid_grant"}"#),
        ])
        let provider = provider(keychain: token(), cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.unavailableReason), ["Antigravity sign-in expired — open Antigravity or run agy"])
    }

    func testEmptyLanguageServerSummaryFallsThroughToCloudCode() async {
        let empty = "{\"response\": {\"groups\": []}}"
        let loopback = StubTransport(responses: [
            .init(status: 200, body: empty),
            .init(status: 200, body: empty),
        ])
        let cloud = StubTransport(responses: [.init(status: 200, body: summary)])
        let provider = provider(servers: [LanguageServerLocation(csrf: "token", ports: [5000], extensionPort: nil)], keychain: token(), loopback: loopback, cloud: cloud)

        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.modelId), allIDs)
        XCTAssertEqual(loopback.requests.count, 2)
        XCTAssertEqual(cloud.requests.count, 1)
    }

    func testGoogleRefreshOutageKeepsLastGood() async {
        let cloud = StubTransport(responses: [
            .init(status: 200, body: summary),
            .init(status: 401, body: "{}"),
            .init(status: 500, body: ""),
        ])
        let provider = provider(keychain: token(), cloud: cloud)

        let first = await provider.fetch()
        XCTAssertEqual(first.count, 4)
        let second = await provider.fetch()
        XCTAssertEqual(second.map(\.modelId), first.map(\.modelId))
        XCTAssertNil(second[0].unavailableReason)
        XCTAssertEqual(cloud.requests.count, 3)
    }

    func testNothingWhenNoServerAndNoKeychainToken() async {
        let cloud = StubTransport(responses: [])
        let provider = provider(cloud: cloud)
        let buckets = await provider.fetch()
        XCTAssertTrue(buckets.isEmpty)
        XCTAssertTrue(cloud.requests.isEmpty)
    }

    func testServesLastGoodWhenCloudCodeIsUnavailable() async {
        let cloud = StubTransport(responses: [
            .init(status: 200, body: summary),
            .init(status: 503, body: ""),
            .init(status: 503, body: ""),
        ])
        let provider = provider(keychain: token(), cloud: cloud)

        let first = await provider.fetch()
        let second = await provider.fetch()
        XCTAssertEqual(second.map(\.modelId), first.map(\.modelId))
        XCTAssertEqual(cloud.requests.count, 3)
    }

    func testShowsClaudeAndGPTPoolWhenGeminiPoolIsMissing() async {
        let onlyThirdParty = """
        {"groups":[{"displayName":"Claude and GPT models","buckets":[
          {"bucketId":"3p-5h","window":"5h","remainingFraction":1.0},
          {"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.3}]}]}
        """
        let cloud = StubTransport(responses: [.init(status: 200, body: onlyThirdParty), .init(status: 200, body: onlyThirdParty)])
        let provider = provider(keychain: token(), cloud: cloud)
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.modelId), ["3p-5h", "3p-weekly"])
        XCTAssertEqual(buckets.map(\.unavailableReason), [nil, nil])
        XCTAssertEqual(cloud.requests.count, 2)
    }

    func testPlaceholderWhenSummaryHasNoKnownPool() async {
        let unknown = """
        {"groups":[{"displayName":"Other models","buckets":[
          {"bucketId":"other-5h","window":"5h","remainingFraction":1.0}]}]}
        """
        let cloud = StubTransport(responses: [.init(status: 200, body: unknown), .init(status: 200, body: unknown)])
        let provider = provider(keychain: token(), cloud: cloud)
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.unavailableReason), ["No quota reported"])
        XCTAssertEqual(buckets.map(\.displayName), ["Gemini"])
    }

    func testPlaceholderWhenUnavailableWithoutLastGood() async {
        let cloud = StubTransport(responses: [.init(status: 503, body: ""), .init(status: 503, body: "")])
        let provider = provider(keychain: token(), cloud: cloud)
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.unavailableReason), ["Usage currently unavailable"])
    }
}
