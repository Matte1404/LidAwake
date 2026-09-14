import Foundation

public enum ProjectInfo {
    public static let developer = "TurboKach"
    public static let repository = URL(string: "https://github.com/TurboKach/LidAwake")!
    public static let releases = repository.appendingPathComponent("releases")
}

struct ReleaseVersion: Comparable {
    let parts: [Int]
    init?(_ string: String) {
        let raw = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let fields = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public enum UpdateResult: Equatable {
    case available(version: String, url: URL)
    case current
    case noReleases
}

public struct GitHubUpdates {
    public init() {}
    public func check(currentVersion: String) async throws -> UpdateResult {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/TurboKach/LidAwake/releases/latest")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LidAwake/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ControlError.message("GitHub returned an invalid response.")
        }
        return try Self.evaluate(data: data, status: response.statusCode, currentVersion: currentVersion)
    }

    static func evaluate(data: Data, status: Int, currentVersion: String) throws -> UpdateResult {
        if status == 404 { return .noReleases }
        if status == 403 || status == 429 {
            throw ControlError.message("GitHub is limiting requests. Please try again later.")
        }
        guard status == 200 else { throw ControlError.message("GitHub could not check for updates (HTTP \(status)).") }
        struct Release: Decodable {
            var tag_name: String
            var html_url: URL
            var draft: Bool
            var prerelease: Bool
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let latest = ReleaseVersion(release.tag_name), let current = ReleaseVersion(currentVersion) else {
            throw ControlError.message("The release version could not be compared with this app.")
        }
        guard latest > current else { return .current }
        guard release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.path.hasPrefix("/TurboKach/LidAwake/releases/tag/") else {
            throw ControlError.message("GitHub returned an unexpected release link.")
        }
        return .available(version: release.tag_name, url: release.html_url)
    }
}
