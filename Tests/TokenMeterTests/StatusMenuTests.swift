import XCTest
import AppKit
@testable import TokenMeter

@MainActor
final class StatusMenuBuilderTests: XCTestCase {
    private var settings: SettingsManager!
    private var builder: StatusMenuBuilder!

    override func setUp() {
        super.setUp()
        settings = SettingsManager(defaults: UserDefaults(suiteName: "TokenMeterTests.\(UUID().uuidString)")!)
        builder = StatusMenuBuilder(settings: settings)
    }

    private func bucket(_ id: String, name: String, remaining: Double = 0.6, type: String = "5h", reason: String? = nil) -> QuotaBucket {
        QuotaBucket(
            resetTime: "2026-10-23T22:00:00Z",
            tokenType: type,
            modelId: id,
            remainingFraction: remaining,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: name,
            unavailableReason: reason
        )
    }

    private var sample: [QuotaBucket] {
        [
            bucket("gemini-5h", name: "Gemini - 5 Hour"),
            bucket("official-claude-cli-5h", name: "Claude - 5 Hour"),
            bucket("official-claude-weekly", name: "Claude - Weekly", type: "weekly"),
            bucket("official-claude-weekly-fable", name: "Claude - Fable Weekly", type: "weekly"),
            bucket("official-codex-cli-5h", name: "Codex - 5 Hour"),
        ]
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "---" : $0.title }
    }

    func testGroupsRowsUnderProviderHeadersThenSettingsMenuBarAndQuit() {
        let menu = builder.makeMenu(buckets: sample, errorMessage: nil)
        XCTAssertEqual(titles(menu), ["Gemini", "5 Hour", "Claude", "5 Hour", "Weekly", "Fable Weekly", "Codex", "5 Hour", "---", "Settings", "Menu Bar", "Quit TokenMeter"])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertNotNil(menu.items[1].view)
        XCTAssertNotNil(menu.items[9].submenu)
        XCTAssertNotNil(menu.items[10].submenu)
        XCTAssertEqual(menu.items[11].keyEquivalent, "q")
    }

    func testPlaceholderRowIsDisabledAndTitledWithItsReason() {
        let menu = builder.makeMenu(buckets: [bucket("official-claude-unavailable", name: "Claude", remaining: 0, reason: "Not signed in to Claude Code")], errorMessage: nil)
        XCTAssertEqual(titles(menu).prefix(2), ["Claude", "Not signed in to Claude Code"])
        XCTAssertFalse(menu.items[1].isEnabled)
        XCTAssertNotNil(menu.items[1].view)
    }

    func testEmptyStateShowsLoadingOrErrorLine() {
        let loading = builder.makeMenu(buckets: [], errorMessage: nil)
        XCTAssertEqual(titles(loading), ["Loading usage…", "---", "Settings", "Menu Bar", "Quit TokenMeter"])
        XCTAssertFalse(loading.items[0].isEnabled)

        let failed = builder.makeMenu(buckets: [], errorMessage: "No usage sources found.")
        XCTAssertEqual(failed.items[0].title, "No usage sources found.")
        XCTAssertFalse(failed.items[0].isEnabled)
    }

    func testSettingsSubmenuHoldsTheBurnRateToggle() throws {
        settings.usePaceMode = true
        let settingsMenu = try XCTUnwrap(builder.makeMenu(buckets: sample, errorMessage: nil).items[9].submenu)
        XCTAssertEqual(settingsMenu.items.map(\.title), ["Show Burn Rate Instead"])
        XCTAssertEqual(settingsMenu.items[0].state, .on)
    }

    func testMenuBarSubmenuListsLiveWindowsAndChecksTheCurrentOne() throws {
        settings.toolbarDisplayModelId = "official-claude-weekly"
        let show = try XCTUnwrap(builder.makeMenu(buckets: sample, errorMessage: nil).items[10].submenu)
        XCTAssertEqual(titles(show), ["Auto", "None", "---", "Gemini - 5 Hour", "Claude - 5 Hour", "Claude - Weekly", "Claude - Fable Weekly", "Codex - 5 Hour"])
        XCTAssertEqual(show.items.map(\.state), [.off, .off, .off, .off, .off, .on, .off, .off])
    }

    func testMenuBarSubmenuOmitsPlaceholders() throws {
        let menu = builder.makeMenu(buckets: sample + [bucket("gemini-unavailable", name: "Gemini", reason: "Usage currently unavailable")], errorMessage: nil)
        let show = try XCTUnwrap(menu.items.first { $0.title == "Menu Bar" }?.submenu)
        XCTAssertFalse(show.items.contains { $0.title == "Gemini" })
    }

    func testTogglingBurnRateFlipsTheSetting() throws {
        let item = try XCTUnwrap(builder.makeMenu(buckets: sample, errorMessage: nil).items[9].submenu?.items[0])
        XCTAssertFalse(settings.usePaceMode)
        _ = item.target?.perform(item.action, with: item)
        XCTAssertTrue(settings.usePaceMode)
        _ = item.target?.perform(item.action, with: item)
        XCTAssertFalse(settings.usePaceMode)
    }

    func testChoosingAMenuBarItemStoresItsModelId() throws {
        let show = try XCTUnwrap(builder.makeMenu(buckets: sample, errorMessage: nil).items[10].submenu)
        let claudeWeekly = try XCTUnwrap(show.items.first { $0.title == "Claude - Weekly" })
        _ = claudeWeekly.target?.perform(claudeWeekly.action, with: claudeWeekly)
        XCTAssertEqual(settings.toolbarDisplayModelId, "official-claude-weekly")

        let none = try XCTUnwrap(show.items.first { $0.title == "None" })
        _ = none.target?.perform(none.action, with: none)
        XCTAssertEqual(settings.toolbarDisplayModelId, "none")

        let auto = try XCTUnwrap(show.items.first { $0.title == "Auto" })
        _ = auto.target?.perform(auto.action, with: auto)
        XCTAssertEqual(settings.toolbarDisplayModelId, "auto")
    }
}
