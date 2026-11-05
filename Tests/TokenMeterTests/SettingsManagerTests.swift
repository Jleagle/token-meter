import XCTest
@testable import TokenMeter

final class SettingsManagerTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TokenMeterTests.\(UUID().uuidString)")!
    }

    func testLastUsedWindowPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let settings = SettingsManager(defaults: defaults)
        XCTAssertNil(settings.lastUsedModelId)
        settings.lastUsedModelId = "official-claude-cli-5h"
        XCTAssertEqual(SettingsManager(defaults: defaults).lastUsedModelId, "official-claude-cli-5h")
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
