import XCTest
@testable import TokenMeter

final class LanguageServerDiscoveryTests: XCTestCase {
    func testExtractsFlagValueWithSpaceOrEquals() {
        let command = "/x/language_server_macos_arm --csrf_token abc --extension_server_port=5"
        XCTAssertEqual(LanguageServerDiscovery.extractFlag(command: command, flag: "--csrf_token"), "abc")
        XCTAssertEqual(LanguageServerDiscovery.extractFlag(command: command, flag: "--extension_server_port"), "5")
        XCTAssertNil(LanguageServerDiscovery.extractFlag(command: "/x/language_server", flag: "--csrf_token"))
    }

    func testCandidatesMatchProcessNameAndMarker() {
        let ps = """
          123 /Applications/Antigravity.app/Contents/Resources/app/bin/language_server_macos_arm --app_data_dir antigravity --csrf_token t1
          456 /other/language_server_macos_arm --app_data_dir windsurf --csrf_token t2
          789 /Users/me/.gemini/antigravity-cli/bin/agy serve
        """
        let servers = LanguageServerDiscovery.candidates(psOutput: ps, processName: "language_server", markers: ["antigravity"])
        XCTAssertEqual(servers.map(\.pid), [123])
        XCTAssertEqual(LanguageServerDiscovery.extractFlag(command: servers[0].command, flag: "--csrf_token"), "t1")

        let agy = LanguageServerDiscovery.candidates(psOutput: ps, processName: "agy", markers: [])
        XCTAssertEqual(agy.map(\.pid), [789])
    }

    func testMarkerPathSubstringMatchesWhenNoIdeFlags() {
        let ps = "  42 /Users/me/.gemini/antigravity/bin/language_server_macos_arm --csrf_token t"
        let found = LanguageServerDiscovery.candidates(psOutput: ps, processName: "language_server", markers: ["antigravity"])
        XCTAssertEqual(found.map(\.pid), [42])
    }

    func testParsesListeningPortsOnly() {
        let lsof = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        language_ 123 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:52168 (LISTEN)
        language_ 123 me 11u IPv4 0x2 0t0 TCP *:52169 (LISTEN)
        language_ 123 me 12u IPv4 0x3 0t0 TCP 127.0.0.1:52170->127.0.0.1:1 (ESTABLISHED)
        """
        XCTAssertEqual(LanguageServerDiscovery.parseListeningPorts(lsof), [52168, 52169])
    }
}

final class ISO8601Tests: XCTestCase {
    func testParsesFractionsOfAnyLength() {
        let base = ISO8601DateFormatter().date(from: "2026-10-23T20:00:00Z")!.timeIntervalSince1970
        XCTAssertEqual(ISO8601.date(from: "2026-10-23T20:00:00.5Z")?.timeIntervalSince1970 ?? 0, base + 0.5, accuracy: 0.001)
        XCTAssertEqual(ISO8601.date(from: "2026-10-23T20:00:00.12Z")?.timeIntervalSince1970 ?? 0, base + 0.12, accuracy: 0.001)
        XCTAssertEqual(ISO8601.date(from: "2026-10-23T20:00:00.123456Z")?.timeIntervalSince1970 ?? 0, base + 0.123, accuracy: 0.001)
        XCTAssertEqual(ISO8601.date(from: "2026-10-23T20:00:00Z")?.timeIntervalSince1970 ?? 0, base, accuracy: 0.001)
        XCTAssertNil(ISO8601.date(from: "yesterday"))
    }
}

final class AntigravityKeychainTokenTests: XCTestCase {
    func testParsesGoKeyringWrappedToken() {
        let json = #"{"token":{"access_token":"at","refresh_token":"rt","expiry":"2026-10-23T20:00:00.123456789+01:00"}}"#
        let raw = "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
        let token = AntigravityKeychainToken.parse(raw: raw)
        XCTAssertEqual(token?.accessToken, "at")
        XCTAssertEqual(token?.refreshToken, "rt")
        let expected = ISO8601DateFormatter().date(from: "2026-10-23T19:00:00Z")!.timeIntervalSince1970 + 0.123
        XCTAssertEqual(token?.expiry?.timeIntervalSince1970 ?? 0, expected, accuracy: 0.001)
    }

    func testParsesBareJSONWithRootFields() {
        let token = AntigravityKeychainToken.parse(raw: #"{"access_token":"at","refresh_token":"rt"}"#)
        XCTAssertEqual(token?.accessToken, "at")
        XCTAssertEqual(token?.refreshToken, "rt")
        XCTAssertNil(token?.expiry)
    }

    func testRejectsMalformedValue() {
        XCTAssertNil(AntigravityKeychainToken.parse(raw: "{not json"))
        XCTAssertNil(AntigravityKeychainToken.parse(raw: ""))
    }
}

final class AntigravitySummaryParserTests: XCTestCase {
    private let bare = """
    {"groups":[
      {"displayName":"Gemini models","buckets":[
        {"bucketId":"gemini-5h","displayName":"Gemini 5h","window":"5h","remainingFraction":0.8,"resetTime":"2026-10-23T22:00:00Z"},
        {"bucketId":"gemini-weekly","displayName":"Gemini weekly","window":"weekly","remainingFraction":0.5,"resetTime":"2026-10-30T00:00:00Z"}]},
      {"displayName":"Claude models","buckets":[
        {"bucketId":"3p-5h","window":"5h","remainingFraction":0.1},
        {"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.2}]},
      {"displayName":"Gemini 4 Argon","buckets":[
        {"bucketId":"argon-weekly","window":"weekly","remainingFraction":0.9,"resetTime":"2026-10-30T00:00:00Z"}]}
    ]}
    """

    func testKeepsGeminiPoolAndArgonWeeklyOnly() throws {
        let buckets = try XCTUnwrap(AntigravitySummaryParser.buckets(from: [Data(bare.utf8)]))
        XCTAssertEqual(buckets.map(\.modelId), ["gemini-5h", "gemini-weekly", "argon-weekly"])
        XCTAssertEqual(buckets.map(\.displayName), ["Gemini - 5 Hour", "Gemini - Weekly", "Gemini - Argon Weekly"])
        XCTAssertEqual(buckets.map(\.tokenType), ["5h", "weekly", "weekly"])
        XCTAssertEqual(buckets[0].remainingFraction, 0.8)
        XCTAssertEqual(buckets[0].resetTime, "2026-10-23T22:00:00Z")
    }

    func testAcceptsLanguageServerEnvelope() throws {
        let wrapped = "{\"response\": \(bare)}"
        let buckets = try XCTUnwrap(AntigravitySummaryParser.buckets(from: [Data(wrapped.utf8)]))
        XCTAssertEqual(buckets.map(\.modelId), ["gemini-5h", "gemini-weekly", "argon-weekly"])
    }

    func testReturnsNilWhenBodyIsNotASummary() {
        XCTAssertNil(AntigravitySummaryParser.buckets(from: [Data("{\"foo\":1}".utf8)]))
        XCTAssertNil(AntigravitySummaryParser.buckets(from: [Data("not json".utf8)]))
    }

    func testDropsBucketsWithoutUsableFractionAndDisabledArgon() throws {
        let body = """
        {"groups":[
          {"displayName":"Gemini models","buckets":[
            {"bucketId":"gemini-5h","window":"5h"},
            {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.5}]},
          {"displayName":"Gemini 4 Argon","buckets":[
            {"bucketId":"argon-weekly","window":"weekly","remainingFraction":0.9,"disabled":true}]}
        ]}
        """
        let buckets = try XCTUnwrap(AntigravitySummaryParser.buckets(from: [Data(body.utf8)]))
        XCTAssertEqual(buckets.map(\.modelId), ["gemini-weekly"])
    }

    func testMergesSeveralBodiesFirstUsableWins() throws {
        let first = """
        {"groups":[{"displayName":"Gemini models","buckets":[
          {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.8}]}]}
        """
        let second = """
        {"groups":[{"displayName":"Gemini models","buckets":[
          {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.1},
          {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.5}]}]}
        """
        let buckets = try XCTUnwrap(AntigravitySummaryParser.buckets(from: [Data(first.utf8), Data(second.utf8)]))
        XCTAssertEqual(buckets.map(\.modelId), ["gemini-5h", "gemini-weekly"])
        XCTAssertEqual(buckets[0].remainingFraction, 0.8)
    }
}
