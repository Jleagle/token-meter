import XCTest
@testable import TokenMeter

@MainActor
final class QuotaServiceTests: XCTestCase {
    private var settings: SettingsManager!
    private var fetched: [QuotaProvider] = []

    override func setUp() {
        super.setUp()
        settings = SettingsManager(defaults: UserDefaults(suiteName: "TokenMeterTests.\(UUID().uuidString)")!)
        fetched = []
    }

    private func bucket(_ id: String) -> QuotaBucket {
        QuotaBucket(
            resetTime: "2026-10-23T22:00:00Z",
            tokenType: "5h",
            modelId: id,
            remainingFraction: 0.6,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: id
        )
    }

    private func fetcher(_ provider: QuotaProvider, _ id: String) -> QuotaService.Fetcher {
        { [self] in
            fetched.append(provider)
            return [bucket(id)]
        }
    }

    private func makeService() -> QuotaService {
        QuotaService(
            fetchers: [
                .gemini: fetcher(.gemini, "gemini-5h"),
                .claude: fetcher(.claude, "official-claude-cli-5h"),
                .codex: fetcher(.codex, "official-codex-cli-5h"),
            ],
            settings: settings
        )
    }

    func testRefreshPollsOnlyTheEnabledProvidersInMenuOrder() async {
        settings.enabledProviders = [.gemini, .codex]
        let service = makeService()
        await service.refresh()
        XCTAssertEqual(fetched, [.gemini, .codex])
        XCTAssertEqual(service.buckets.map(\.modelId), ["gemini-5h", "official-codex-cli-5h"])
    }

    func testHidingAProviderDropsItsCardsWithoutPolling() async {
        let service = makeService()
        await service.refresh()
        fetched = []
        settings.enabledProviders = [.gemini, .codex]
        XCTAssertEqual(service.buckets.map(\.modelId), ["gemini-5h", "official-codex-cli-5h"])
        XCTAssertEqual(fetched, [])
    }

    func testShowingAProviderAgainPollsStraightAway() async {
        settings.enabledProviders = [.gemini]
        let service = makeService()
        await service.refresh()
        fetched = []
        settings.enabledProviders = [.gemini, .claude]
        for _ in 0..<200 where !fetched.contains(.claude) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(fetched, [.gemini, .claude])
        XCTAssertEqual(service.buckets.map(\.modelId), ["gemini-5h", "official-claude-cli-5h"])
    }

    func testAProviderHiddenDuringAPollStaysHidden() async {
        final class Gate { var release: CheckedContinuation<Void, Never>? }
        let gate = Gate()
        let service = QuotaService(
            fetchers: [
                .gemini: fetcher(.gemini, "gemini-5h"),
                .claude: { [self] in
                    await withCheckedContinuation { gate.release = $0 }
                    return [bucket("official-claude-cli-5h")]
                },
            ],
            settings: settings
        )
        let poll = Task { await service.refresh() }
        while gate.release == nil { await Task.yield() }
        settings.enabledProviders = [.gemini]
        gate.release?.resume()
        await poll.value
        XCTAssertEqual(service.buckets.map(\.modelId), ["gemini-5h"])
    }

    func testEveryProviderHiddenPollsNothingAndReportsNoError() async {
        settings.enabledProviders = []
        let service = makeService()
        await service.refresh()
        XCTAssertEqual(fetched, [])
        XCTAssertTrue(service.buckets.isEmpty)
        XCTAssertNil(service.errorMessage)
    }
}
