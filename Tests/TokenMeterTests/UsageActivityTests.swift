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

    func testNamesTheWindowThatDropped() {
        let before = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.5)]
        let after = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.45)]
        XCTAssertEqual(UsageActivity.reducedWindow(from: before, to: after), "official-claude-cli-5h")
    }

    func testAnExhaustedWindowIsNotTheOneInUse() {
        let before = [bucket("gemini-pro", remaining: 0), bucket("gemini-flash", remaining: 0.7)]
        let after = [bucket("gemini-pro", remaining: 0), bucket("gemini-flash", remaining: 0.65)]
        XCTAssertEqual(UsageActivity.reducedWindow(from: before, to: after), "gemini-flash")
    }

    func testNothingDroppedGivesNil() {
        let before = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.5)]
        XCTAssertNil(UsageActivity.reducedWindow(from: before, to: before))
        XCTAssertNil(UsageActivity.reducedWindow(from: [], to: before))
    }

    func testAWindowResettingIsNotUse() {
        let before = [bucket("official-claude-cli-5h", remaining: 0.2)]
        let after = [bucket("official-claude-cli-5h", remaining: 1.0)]
        XCTAssertNil(UsageActivity.reducedWindow(from: before, to: after))
    }

    func testPlaceholdersAndNewWindowsAreIgnored() {
        let before = [bucket("official-claude-cli-5h", remaining: 0.5), bucket("official-codex-unavailable", remaining: nil, reason: "Not signed in")]
        let after = [bucket("official-claude-unavailable", remaining: nil, reason: "Session expired"), bucket("official-codex-cli-5h", remaining: 0.3)]
        XCTAssertNil(UsageActivity.reducedWindow(from: before, to: after))
    }

    func testTheLargerDropWinsWhenTwoWindowsWereUsed() {
        let before = [bucket("gemini-5h", remaining: 0.6), bucket("official-claude-cli-5h", remaining: 0.5)]
        let after = [bucket("gemini-5h", remaining: 0.4), bucket("official-claude-cli-5h", remaining: 0.45)]
        XCTAssertEqual(UsageActivity.reducedWindow(from: before, to: after), "gemini-5h")
    }
}
