import XCTest
import AppKit
@testable import TokenMeter

@MainActor
final class ProviderLogoTests: XCTestCase {
    func testClaudeAndGeminiHaveTemplateMarks() throws {
        for provider in [QuotaProvider.claude, .gemini] {
            let image = try XCTUnwrap(ProviderLogo.image(for: provider), provider.name)
            XCTAssertTrue(image.isTemplate, provider.name)
            XCTAssertGreaterThan(image.size.width, 0, provider.name)
            XCTAssertGreaterThan(image.size.height, 0, provider.name)
        }
    }

    func testCodexKeepsItsSymbol() {
        XCTAssertNil(ProviderLogo.image(for: .codex))
    }

    func testTheSameImageIsReusedAcrossRows() {
        XCTAssertTrue(ProviderLogo.image(for: .claude) === ProviderLogo.image(for: .claude))
    }

    func testEveryProviderHasAMenuBarTemplateImage() throws {
        for provider in QuotaProvider.allCases {
            let image = try XCTUnwrap(ProviderLogo.menuBarImage(for: provider), provider.name)
            XCTAssertTrue(image.isTemplate, provider.name)
        }
        XCTAssertEqual(ProviderLogo.menuBarImage(for: .claude)?.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(ProviderLogo.menuBarImage(for: .gemini)?.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(ProviderLogo.image(for: .claude)?.size, NSSize(width: 24, height: 24))
    }
}
