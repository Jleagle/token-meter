import XCTest
@testable import TokenMeter

final class ClaudeUsageMapperTests: XCTestCase {
    func testMapsSessionAndWeeklyWindows() throws {
        let json = #"{"five_hour":{"utilization":25,"resets_at":"2026-10-23T22:00:00.123456Z"},"seven_day":{"utilization":50,"resets_at":"2026-10-30T00:00:00Z"}}"#
        let buckets = ClaudeUsageMapper.buckets(from: Data(json.utf8))
        XCTAssertEqual(buckets.map(\.modelId), ["official-claude-cli-5h", "official-claude-weekly"])
        XCTAssertEqual(buckets.map(\.displayName), ["Claude - 5 Hour", "Claude - Weekly"])
        XCTAssertEqual(buckets.map(\.tokenType), ["5h", "weekly"])
        XCTAssertEqual(buckets[0].remainingFraction, 0.75)
        let reset = try XCTUnwrap(buckets[0].resetDate)
        XCTAssertEqual(reset.timeIntervalSince1970, ISO8601DateFormatter().date(from: "2026-10-23T22:00:00Z")!.timeIntervalSince1970 + 0.123, accuracy: 0.001)
    }

    func testMapsScopedWeeklyLimitsAndSonnet() throws {
        let json = """
        {"five_hour":{"utilization":0,"resets_at":null},
         "seven_day":{"utilization":10,"resets_at":"2026-10-30T00:00:00Z"},
         "seven_day_sonnet":{"utilization":5,"resets_at":"2026-10-30T00:00:00Z"},
         "limits":[
           {"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":40,"resets_at":1761782400},
           {"kind":"other","percent":99}
         ]}
        """
        let buckets = ClaudeUsageMapper.buckets(from: Data(json.utf8))
        XCTAssertEqual(buckets.map(\.modelId), ["official-claude-cli-5h", "official-claude-weekly", "official-claude-weekly-fable", "official-claude-weekly-sonnet"])
        XCTAssertEqual(buckets[2].displayName, "Claude - Fable Weekly")
        XCTAssertEqual(buckets[2].remainingFraction, 0.6)
        XCTAssertEqual(buckets[2].tokenType, "weekly")
        XCTAssertEqual(try XCTUnwrap(buckets[2].resetDate).timeIntervalSince1970, 1761782400, accuracy: 0.5)
        XCTAssertEqual(buckets[3].displayName, "Claude - Sonnet Weekly")
        XCTAssertNil(buckets[0].resetDate)
    }

    func testScopedSonnetLimitAndSonnetWindowProduceOneBucket() {
        let json = """
        {"five_hour":{"utilization":0},
         "seven_day_sonnet":{"utilization":5},
         "limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Sonnet"}},"percent":40}]}
        """
        let buckets = ClaudeUsageMapper.buckets(from: Data(json.utf8))
        XCTAssertEqual(buckets.map(\.modelId), ["official-claude-cli-5h", "official-claude-weekly-sonnet"])
        XCTAssertEqual(buckets[1].remainingFraction, 0.6)
    }

    func testIgnoresNullWindows() {
        let json = #"{"five_hour":{"utilization":25,"resets_at":"2026-10-23T22:00:00Z"},"seven_day":null,"seven_day_sonnet":null,"limits":null}"#
        XCTAssertEqual(ClaudeUsageMapper.buckets(from: Data(json.utf8)).map(\.modelId), ["official-claude-cli-5h"])
    }
}

final class ClaudeCredentialDocumentTests: XCTestCase {
    func testReadsOAuthFields() {
        let document = claudeCredentialDocument(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(document.accessToken, "a")
        XCTAssertEqual(document.refreshToken, "r")
        XCTAssertEqual(document.expiresAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(document.subscriptionType, "max")
    }

    func testRejectsDocumentWithoutAccessToken() {
        XCTAssertNil(ClaudeCredentialDocument(data: Data(#"{"claudeAiOauth":{"refreshToken":"r"}}"#.utf8)))
        XCTAssertNil(ClaudeCredentialDocument(data: Data("nope".utf8)))
    }

    func testMergingRotatedTokensPreservesOtherFields() throws {
        let original = claudeCredentialDocument()
        let rotated = try XCTUnwrap(original.mergingRotated(accessToken: "new", refreshToken: "r2", expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(rotated.accessToken, "new")
        XCTAssertEqual(rotated.refreshToken, "r2")
        XCTAssertEqual(rotated.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: rotated.data) as? [String: Any])
        let oauth = try XCTUnwrap(object["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:profile", "user:inference"])
        XCTAssertNotNil(object["mcpOAuth"])
    }

    func testMergingKeepsRefreshTokenWhenServerOmitsIt() throws {
        let rotated = try XCTUnwrap(claudeCredentialDocument(refreshToken: "keep").mergingRotated(accessToken: "new", refreshToken: nil, expiresAt: Date()))
        XCTAssertEqual(rotated.refreshToken, "keep")
    }
}

final class RetryAfterTests: XCTestCase {
    func testParsesSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(RetryAfter.seconds(header: "120", now: now), 120)
        XCTAssertEqual(RetryAfter.seconds(header: "Tue, 14 Nov 2023 22:13:40 GMT", now: now), 20)
        XCTAssertNil(RetryAfter.seconds(header: nil, now: now))
        XCTAssertNil(RetryAfter.seconds(header: "soon", now: now))
    }
}

@MainActor
final class ClaudeUsageProviderTests: XCTestCase {
    private let usageJSON = #"{"five_hour":{"utilization":25,"resets_at":"2026-10-23T22:00:00Z"},"seven_day":{"utilization":50,"resets_at":"2026-10-30T00:00:00Z"}}"#
    private let refreshJSON = #"{"access_token":"new","refresh_token":"r2","expires_in":3600}"#

    func testSendsClaudeCodeClientHeaders() async {
        let transport = StubTransport(responses: [.init(status: 200, body: usageJSON)])
        let provider = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: claudeCredentialDocument()), transport: transport, installed: { true })
        _ = await provider.fetch()
        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("claude-cli/") ?? false)
    }

    func testRefreshesOn401AndPersistsRotatedToken() async throws {
        let store = StubClaudeCredentialStore(document: claudeCredentialDocument())
        let transport = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 200, body: refreshJSON),
            .init(status: 200, body: usageJSON),
        ])
        let provider = ClaudeUsageProvider(store: store, transport: transport, installed: { true })
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.modelId), ["official-claude-cli-5h", "official-claude-weekly"])

        let refresh = transport.requests[1]
        XCTAssertEqual(refresh.url?.absoluteString, "https://platform.claude.com/v1/oauth/token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(refresh.httpBody)) as? [String: Any])
        XCTAssertEqual(body["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(body["refresh_token"] as? String, "r1")
        XCTAssertEqual(body["client_id"] as? String, "9d1c250a-e61b-44d9-88ed-5944d1962f5e")

        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(store.saved?.accessToken, "new")
        XCTAssertEqual(store.saved?.refreshToken, "r2")
    }

    func testRefreshesBeforeRequestWhenStoredTokenHasExpired() async {
        let store = StubClaudeCredentialStore(document: claudeCredentialDocument(expiresAt: Date().addingTimeInterval(-60)))
        let transport = StubTransport(responses: [
            .init(status: 200, body: refreshJSON),
            .init(status: 200, body: usageJSON),
        ])
        let provider = ClaudeUsageProvider(store: store, transport: transport, installed: { true })
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://platform.claude.com/v1/oauth/token")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new")
    }

    func testSessionExpiredWhenRefreshIsRejected() async {
        let store = StubClaudeCredentialStore(document: claudeCredentialDocument())
        let transport = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 400, body: #"{"error":"invalid_grant"}"#),
        ])
        let provider = ClaudeUsageProvider(store: store, transport: transport, installed: { true })
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].unavailableReason, "Session expired — open Claude Code to sign in")
        XCTAssertNil(store.saved)
    }

    func testRateLimitStartsCooldownAndServesLastGoodBuckets() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = StubTransport(responses: [
            .init(status: 200, body: usageJSON),
            .init(status: 429, body: "{}", headers: ["Retry-After": "120"]),
            .init(status: 200, body: usageJSON),
        ])
        let provider = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: claudeCredentialDocument()), transport: transport, installed: { true }, now: { now })

        let first = await provider.fetch()
        XCTAssertEqual(first.count, 2)
        XCTAssertNil(first[0].staleNote)

        now = now.addingTimeInterval(61)
        let limited = await provider.fetch()
        XCTAssertEqual(limited.map(\.modelId), first.map(\.modelId))
        XCTAssertEqual(limited[0].staleNote, "Rate limited, retry in ~2m")

        now = now.addingTimeInterval(61)
        let stillLimited = await provider.fetch()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(stillLimited[0].staleNote, "Rate limited, retry in ~1m")

        now = now.addingTimeInterval(60)
        let recovered = await provider.fetch()
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertNil(recovered[0].staleNote)
    }

    func testRateLimitWithoutLastGoodShowsPlaceholder() async {
        let transport = StubTransport(responses: [.init(status: 429, body: "{}")])
        let provider = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: claudeCredentialDocument()), transport: transport, installed: { true })
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].unavailableReason, "Rate limited by Anthropic, retry in ~5m")
    }

    func testNotSignedInShowsPlaceholderOnlyWhenClaudeCodeIsInstalled() async {
        let transport = StubTransport(responses: [])
        let installed = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: nil), transport: transport, installed: { true })
        let placeholders = await installed.fetch()
        XCTAssertEqual(placeholders.map(\.unavailableReason), ["Not signed in to Claude Code"])

        let absent = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: nil), transport: transport, installed: { false })
        let nothing = await absent.fetch()
        XCTAssertTrue(nothing.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRetriesPersistingRotatedTokenWhenSaveFails() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = StubClaudeCredentialStore(document: claudeCredentialDocument())
        store.failNextSave = true
        let transport = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 200, body: refreshJSON),
            .init(status: 200, body: usageJSON),
            .init(status: 200, body: usageJSON),
        ])
        let provider = ClaudeUsageProvider(store: store, transport: transport, installed: { true }, now: { now })

        let first = await provider.fetch()
        XCTAssertEqual(first.count, 2)
        XCTAssertNil(store.saved)
        XCTAssertEqual(store.document?.accessToken, "old")

        now = now.addingTimeInterval(61)
        let second = await provider.fetch()
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(transport.requests[3].url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(store.saved?.accessToken, "new")
        XCTAssertEqual(store.saved?.refreshToken, "r2")
    }

    func testDropsPendingRotationWhenStoreDocumentChanges() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = StubClaudeCredentialStore(document: claudeCredentialDocument())
        store.failNextSave = true
        let transport = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 200, body: refreshJSON),
            .init(status: 200, body: usageJSON),
            .init(status: 200, body: usageJSON),
        ])
        let provider = ClaudeUsageProvider(store: store, transport: transport, installed: { true }, now: { now })
        _ = await provider.fetch()

        store.document = claudeCredentialDocument(accessToken: "relogin", refreshToken: "r9")
        now = now.addingTimeInterval(61)
        _ = await provider.fetch()
        XCTAssertEqual(transport.requests.count, 4)
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer relogin")
        XCTAssertNil(store.saved)
    }

    func testTokenEndpointOutageKeepsLastGoodCards() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = StubTransport(responses: [
            .init(status: 200, body: usageJSON),
            .init(status: 401, body: "{}"),
            .init(status: 404, body: "not found"),
        ])
        let provider = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: claudeCredentialDocument()), transport: transport, installed: { true }, now: { now })

        let first = await provider.fetch()
        XCTAssertEqual(first.count, 2)

        now = now.addingTimeInterval(61)
        let second = await provider.fetch()
        XCTAssertEqual(second.map(\.modelId), first.map(\.modelId))
        XCTAssertNil(second[0].unavailableReason)
    }

    func testTokenEndpointOutageWithoutLastGoodShowsUnavailable() async {
        let transport = StubTransport(responses: [
            .init(status: 401, body: "{}"),
            .init(status: 500, body: ""),
        ])
        let provider = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: claudeCredentialDocument()), transport: transport, installed: { true })
        let buckets = await provider.fetch()
        XCTAssertEqual(buckets.map(\.unavailableReason), ["Usage currently unavailable"])
    }

    func testReusesResultWithinMinimumInterval() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = StubTransport(responses: [.init(status: 200, body: usageJSON)])
        let provider = ClaudeUsageProvider(store: StubClaudeCredentialStore(document: claudeCredentialDocument()), transport: transport, installed: { true }, now: { now })
        _ = await provider.fetch()
        now = now.addingTimeInterval(30)
        let again = await provider.fetch()
        XCTAssertEqual(again.count, 2)
        XCTAssertEqual(transport.requests.count, 1)
    }
}
