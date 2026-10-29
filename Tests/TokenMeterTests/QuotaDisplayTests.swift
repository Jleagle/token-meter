import XCTest
@testable import TokenMeter

final class QuotaDisplayTests: XCTestCase {
    private func bucket(_ id: String = "official-claude-cli-5h", remaining: Double, resetIn: TimeInterval? = nil, reason: String? = nil) -> QuotaBucket {
        let reset = resetIn.map { ISO8601DateFormatter().string(from: Date().addingTimeInterval($0)) }
        return QuotaBucket(
            resetTime: reset,
            tokenType: "5h",
            modelId: id,
            remainingFraction: remaining,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: id,
            unavailableReason: reason
        )
    }

    func testPercentTextShowsPercentLeftWhenBurnRateIsOff() {
        XCTAssertEqual(QuotaDisplay.percentText(for: bucket(remaining: 0.25), paceMode: false), "25%")
        XCTAssertEqual(QuotaDisplay.percentText(for: bucket(remaining: 0, reason: "Not signed in"), paceMode: false), "—")
    }

    func testPercentTextShowsBurnRateWhenOn() {
        // 75% used halfway through a 5-hour window burns at 150% of pace
        XCTAssertEqual(QuotaDisplay.percentText(for: bucket(remaining: 0.25, resetIn: 2.5 * 3600), paceMode: true), "150%")
    }

    func testResetTextShowsCountdownAndShareOfWindowLeft() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func reset(_ type: String?, in interval: TimeInterval?) -> QuotaBucket {
            QuotaBucket(
                resetTime: interval.map { ISO8601DateFormatter().string(from: now.addingTimeInterval($0)) },
                tokenType: type,
                modelId: "official-claude-weekly",
                remainingFraction: 0.5,
                remainingAmount: nil,
                maxAmount: nil
            )
        }
        XCTAssertEqual(QuotaDisplay.resetText(for: reset("weekly", in: 6 * 86400 + 3 * 3600), now: now), "6d 3h (88%)")
        XCTAssertEqual(QuotaDisplay.resetText(for: reset("5h", in: 90 * 60), now: now), "1h 30m (30%)")
        XCTAssertEqual(QuotaDisplay.resetText(for: reset("5h", in: 45), now: now), "45s (0%)")
        XCTAssertEqual(QuotaDisplay.resetText(for: reset(nil, in: 90 * 60), now: now), "1h 30m")
        XCTAssertEqual(QuotaDisplay.resetText(for: reset("5h", in: -10), now: now), "Resetting now")
        XCTAssertEqual(QuotaDisplay.resetText(for: reset("5h", in: nil), now: now), "Reset time unknown")
    }

    func testMenuBarBucketFollowsSelectionAndMode() {
        let buckets = [
            bucket("gemini-5h", remaining: 0.6, resetIn: 4 * 3600),
            bucket("official-claude-cli-5h", remaining: 0.2, resetIn: 1 * 3600),
            bucket("official-codex-unavailable", remaining: 0, reason: "Not signed in"),
        ]
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "auto", paceMode: false)?.modelId, "official-claude-cli-5h")
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "", paceMode: false)?.modelId, "official-claude-cli-5h")
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "gemini-5h", paceMode: false)?.modelId, "gemini-5h")
        XCTAssertNil(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "none", paceMode: false))
        XCTAssertNil(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "official-codex-unavailable", paceMode: false))
        XCTAssertNil(QuotaDisplay.menuBarBucket(buckets: [], selection: "auto", paceMode: false))
        // Gemini: 40% used with 20% of the window elapsed burns fastest (200%)
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "auto", paceMode: true)?.modelId, "gemini-5h")
    }

    func testMenuBarBucketLatestFollowsTheLastUsedProvider() {
        let buckets = [
            bucket("gemini-5h", remaining: 0.1, resetIn: 4 * 3600),
            bucket("official-claude-cli-5h", remaining: 0.3, resetIn: 4 * 3600),
            bucket("official-claude-weekly", remaining: 0.5, resetIn: 2.5 * 3600),
            bucket("official-codex-unavailable", remaining: 0, reason: "Not signed in"),
        ]
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "latest", paceMode: false, lastUsedProvider: .claude)?.modelId, "official-claude-cli-5h")
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "latest", paceMode: false, lastUsedProvider: .gemini)?.modelId, "gemini-5h")
        // Claude 5h: 70% used with 20% elapsed (350%) beats Claude weekly at 100%
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "latest", paceMode: true, lastUsedProvider: .claude)?.modelId, "official-claude-cli-5h")
        // Nothing used yet, or the last used provider has no live window: same pick as Auto
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "latest", paceMode: false, lastUsedProvider: nil)?.modelId, "gemini-5h")
        XCTAssertEqual(QuotaDisplay.menuBarBucket(buckets: buckets, selection: "latest", paceMode: false, lastUsedProvider: .codex)?.modelId, "gemini-5h")
    }
}
