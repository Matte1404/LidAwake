import XCTest
@testable import LidAwakeCore

final class UpdateTests: XCTestCase {
    private func release(_ version: String = "v1.10", url: String = "https://github.com/TurboKach/LidAwake/releases/tag/v1.10", prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": version, "html_url": url, "draft": false, "prerelease": prerelease])
    }

    func testNewerVersionUsesNumericComparisonAndReturnsReleasePage() throws {
        XCTAssertEqual(try GitHubUpdates.evaluate(data: release(), status: 200, currentVersion: "1.9"),
                       .available(version: "v1.10", url: URL(string: "https://github.com/TurboKach/LidAwake/releases/tag/v1.10")!))
    }
    func testSameOlderAndDevelopmentVersionsDoNotOfferDowngrades() throws {
        for current in ["1.10", "1.10.0", "1.11", "2.0"] {
            XCTAssertEqual(try GitHubUpdates.evaluate(data: release(), status: 200, currentVersion: current), .current)
        }
    }
    func testNoReleasesRateLimitAndServerFailures() throws {
        XCTAssertEqual(try GitHubUpdates.evaluate(data: Data(), status: 404, currentVersion: "1.0"), .noReleases)
        for status in [403, 429, 500] {
            XCTAssertThrowsError(try GitHubUpdates.evaluate(data: Data(), status: status, currentVersion: "1.0"))
        }
    }
    func testUntrustedLinksPrereleasesAndMalformedVersionsAreRejected() throws {
        for data in [try release(url: "https://example.com/download"), try release(prerelease: true),
                     try release("v1.2-rc1"), try release("1..2"), Data("invalid".utf8)] {
            XCTAssertThrowsError(try GitHubUpdates.evaluate(data: data, status: 200, currentVersion: "1.0"))
        }
    }
}
