//
//  ReleaseUpdateService.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 20/2/2026.
//

import Foundation

struct ReleaseUpdateService {
    private let owner = "mchigangawa"
    private let repository = "EmuHub"

    func checkForUpdates(currentVersion: String) async throws -> UpdateCheckResult {
        let release = try await fetchLatestRelease()
        let latestVersion = Self.normalizedVersion(from: release.tagName)
        let currentNormalized = Self.normalizedVersion(from: currentVersion)
        let comparison = Self.compareVersion(currentNormalized, latestVersion)
        let hasUpdate = comparison == .orderedAscending

        let preferredAsset = release.assets.first { asset in
            asset.name.localizedCaseInsensitiveContains("mac") ||
            asset.name.lowercased().hasSuffix(".zip") ||
            asset.name.lowercased().hasSuffix(".zim")
        } ?? release.assets.first

        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseName: release.name,
            releaseNotesURL: release.htmlURL,
            downloadURL: preferredAsset?.browserDownloadURL,
            hasUpdate: hasUpdate
        )
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repository)/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw UpdateError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EmuHub", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func normalizedVersion(from versionText: String) -> String {
        let cleaned = versionText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)

        // Ignore metadata suffixes like "-beta" and "+build.5" for update comparison.
        if let metadataStart = cleaned.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            return String(cleaned[..<metadataStart])
        }

        return cleaned
    }

    static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let maxCount = max(left.count, right.count)

        for index in 0..<maxCount {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0

            if leftPart < rightPart { return .orderedAscending }
            if leftPart > rightPart { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        normalizedVersion(from: version)
            .split(separator: ".")
            .map { chunk in
                Int(chunk.prefix { $0.isNumber }) ?? 0
            }
    }
}

struct UpdateCheckResult {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String?
    let releaseNotesURL: URL
    let downloadURL: URL?
    let hasUpdate: Bool
}

enum UpdateError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not check for updates right now. Please try again shortly."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
