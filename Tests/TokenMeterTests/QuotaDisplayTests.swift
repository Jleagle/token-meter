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

    func testMenuBarTitleFollowsSelectionAndMode() {
        let buckets = [
            bucket("gemini-5h", remaining: 0.6, resetIn: 4 * 3600),
            bucket("official-claude-cli-5h", remaining: 0.2, resetIn: 1 * 3600),
            bucket("official-codex-unavailable", remaining: 0, reason: "Not signed in"),
        ]
        XCTAssertEqual(QuotaDisplay.menuBarTitle(buckets: buckets, selection: "auto", paceMode: false), "20%")
        XCTAssertEqual(QuotaDisplay.menuBarTitle(buckets: buckets, selection: "", paceMode: false), "20%")
        XCTAssertEqual(QuotaDisplay.menuBarTitle(buckets: buckets, selection: "gemini-5h", paceMode: false), "60%")
        XCTAssertNil(QuotaDisplay.menuBarTitle(buckets: buckets, selection: "none", paceMode: false))
        XCTAssertNil(QuotaDisplay.menuBarTitle(buckets: buckets, selection: "official-codex-unavailable", paceMode: false))
        XCTAssertNil(QuotaDisplay.menuBarTitle(buckets: [], selection: "auto", paceMode: false))
        // Gemini: 40% used with 20% of the window elapsed burns fastest (200%)
        XCTAssertEqual(QuotaDisplay.menuBarTitle(buckets: buckets, selection: "auto", paceMode: true), "200%")
    }
}
