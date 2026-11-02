import XCTest
@testable import TokenMeter

final class SettingsManagerTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TokenMeterTests.\(UUID().uuidString)")!
    }

    func testLastUsedProviderPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let settings = SettingsManager(defaults: defaults)
        XCTAssertNil(settings.lastUsedProvider)
        settings.lastUsedProvider = .claude
        XCTAssertEqual(SettingsManager(defaults: defaults).lastUsedProvider, .claude)
    }

    func testMenuBarChoiceStartsOnLatest() {
        XCTAssertEqual(SettingsManager(defaults: freshDefaults()).toolbarDisplayModelId, "latest")
    }

    func testEveryProviderIsEnabledUntilOneIsSwitchedOff() {
        let settings = SettingsManager(defaults: freshDefaults())
        XCTAssertEqual(settings.enabledProviders, Set(QuotaProvider.allCases))
    }

    func testEnabledProvidersPersistAcrossLaunches() {
        let defaults = freshDefaults()
        SettingsManager(defaults: defaults).enabledProviders = [.gemini, .codex]
        XCTAssertEqual(SettingsManager(defaults: defaults).enabledProviders, [.gemini, .codex])
    }

    func testSwitchingOffEveryProviderIsRememberedAsNone() {
        let defaults = freshDefaults()
        SettingsManager(defaults: defaults).enabledProviders = []
        XCTAssertEqual(SettingsManager(defaults: defaults).enabledProviders, [])
    }
}
