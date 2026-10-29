import XCTest
@testable import TokenMeter

final class UsageActivityTests: XCTestCase {
    private func bucket(_ id: String, remaining: Double?, reason: String? = nil) -> QuotaBucket {
        QuotaBucket(
            resetTime: nil,
            tokenType: "5h",
            modelId: id,
            remainingFraction: remaining,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: id,
            unavailableReason: reason
        )
    }

    func testNamesTheProviderWhoseWindowDropped() {
        let before = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.5)]
        let after = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.45)]
        XCTAssertEqual(UsageActivity.reducedProvider(from: before, to: after), .claude)
    }

    func testNothingDroppedGivesNil() {
        let before = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.5)]
        XCTAssertNil(UsageActivity.reducedProvider(from: before, to: before))
        XCTAssertNil(UsageActivity.reducedProvider(from: [], to: before))
    }

    func testAWindowResettingIsNotUse() {
        let before = [bucket("official-claude-cli-5h", remaining: 0.2)]
        let after = [bucket("official-claude-cli-5h", remaining: 1.0)]
        XCTAssertNil(UsageActivity.reducedProvider(from: before, to: after))
    }

    func testPlaceholdersAndNewWindowsAreIgnored() {
        let before = [bucket("official-claude-cli-5h", remaining: 0.5), bucket("official-codex-unavailable", remaining: nil, reason: "Not signed in")]
        let after = [bucket("official-claude-unavailable", remaining: nil, reason: "Session expired"), bucket("official-codex-cli-5h", remaining: 0.3)]
        XCTAssertNil(UsageActivity.reducedProvider(from: before, to: after))
    }

    func testTheLargerDropWinsWhenTwoProvidersWereUsed() {
        let before = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.5)]
        let after = [bucket("gemini-5h", remaining: 0.4), bucket("official-claude-cli-5h", remaining: 0.45)]
        XCTAssertEqual(UsageActivity.reducedProvider(from: before, to: after), .gemini)
    }
}

final class SettingsManagerTests: XCTestCase {
    func testLastUsedProviderPersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "TokenMeterTests.\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        XCTAssertNil(settings.lastUsedProvider)
        settings.lastUsedProvider = .claude
        XCTAssertEqual(SettingsManager(defaults: defaults).lastUsedProvider, .claude)
    }
}
