import XCTest
@testable import TokenMeter

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStandardOutputAndExitStatus() {
        let output = ProcessRunner.run("/bin/echo", ["hello", "world"])
        XCTAssertEqual(output?.status, 0)
        XCTAssertEqual(output?.stdout, "hello world\n")
        XCTAssertEqual(ProcessRunner.run("/usr/bin/false", [])?.status, 1)
        XCTAssertNil(ProcessRunner.run("/nonexistent/binary", []))
    }
}

final class KeychainTests: XCTestCase {
    func testRoundTripsGenericPasswordInTemporaryKeychain() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmeter-test-\(UUID().uuidString).keychain-db").path
        XCTAssertEqual(ProcessRunner.run("/usr/bin/security", ["create-keychain", "-p", "test", path])?.status, 0)
        defer { _ = ProcessRunner.run("/usr/bin/security", ["delete-keychain", path]) }

        let keychain = Keychain(path: path)
        XCTAssertNil(keychain.readGenericPassword(service: "tokenmeter-test", account: "tester"))
        XCTAssertNil(keychain.accountOfGenericPassword(service: "tokenmeter-test"))
        XCTAssertTrue(keychain.writeGenericPassword(service: "tokenmeter-test", account: "tester", value: "go-keyring-base64:abc"))
        XCTAssertEqual(keychain.readGenericPassword(service: "tokenmeter-test", account: "tester"), "go-keyring-base64:abc")
        XCTAssertEqual(keychain.accountOfGenericPassword(service: "tokenmeter-test"), "tester")
        XCTAssertTrue(keychain.writeGenericPassword(service: "tokenmeter-test", account: "tester", value: "{\"second\":true}"))
        XCTAssertEqual(keychain.readGenericPassword(service: "tokenmeter-test", account: "tester"), "{\"second\":true}")
    }
}
