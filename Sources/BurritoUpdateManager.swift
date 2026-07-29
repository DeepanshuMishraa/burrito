import AppKit
import Foundation
import Observation
import Sparkle

struct BurritoAvailableUpdate: Equatable {
    let version: String
    let downloadURL: URL
}

struct BurritoUpdateFailure: Equatable {
    let message: String
    let recovery: String
}

@MainActor
@Observable
final class BurritoUpdateManager {
    enum Status {
        case idle
        case checking
        case upToDate
        case available(BurritoAvailableUpdate)
        case failed(BurritoUpdateFailure)
    }

    static let shared = BurritoUpdateManager()

    private static let owner = "DeepanshuMishraa"
    private static let repository = "burrito"
    private static let lastCheckKey = "updater.lastCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var status: Status = .idle

    private let controller: SPUStandardUpdaterController
    private let session: URLSession
    private let defaults: UserDefaults

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.session = session
        self.defaults = defaults
    }

    var availableUpdate: BurritoAvailableUpdate? {
        switch status {
        case .available(let update):
            update
        case .idle, .checking, .upToDate, .failed:
            nil
        }
    }

    var isChecking: Bool {
        if case .checking = status { true } else { false }
    }

    var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    func start() {
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func checkIfDue() async {
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        if let lastCheck,
           Date.now.timeIntervalSince(lastCheck) < Self.checkInterval {
            return
        }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        status = .checking

        do {
            let release = try await latestRelease()

            guard let current = BurritoReleaseVersion(currentVersion),
                  let latest = BurritoReleaseVersion(release.tagName)
            else {
                status = .failed(
                    BurritoUpdateFailure(
                        message: "Burrito could not compare app versions.",
                        recovery: "The installed version or latest release tag is not a semantic version."
                    )
                )
                return
            }

            guard latest > current else {
                defaults.set(Date.now, forKey: Self.lastCheckKey)
                status = .upToDate
                return
            }

            guard let downloadURL = release.downloadURL(
                repository: Self.repository,
                version: latest.description
            ) else {
                status = .failed(
                    BurritoUpdateFailure(
                        message: "Version \(latest) is still being packaged.",
                        recovery: "Try checking again after the release workflow finishes."
                    )
                )
                return
            }

            defaults.set(Date.now, forKey: Self.lastCheckKey)
            status = .available(
                BurritoAvailableUpdate(
                    version: latest.description,
                    downloadURL: downloadURL
                )
            )
        } catch {
            status = .failed(
                BurritoUpdateFailure(
                    message: "Burrito could not check for updates.",
                    recovery: error.localizedDescription
                )
            )
        }
    }

    func performPrimaryAction() async {
        switch status {
        case .available(let update):
            install(update)
        case .idle, .checking, .upToDate, .failed:
            break
        }
    }

    private func install(_: BurritoAvailableUpdate) {
        #if DEBUG
        status = .failed(
            BurritoUpdateFailure(
                message: "Updates are disabled in development builds.",
                recovery: "Run a release build to test the signed update flow."
            )
        )
        #else
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }

    private func latestRelease() async throws -> GitHubRelease {
        guard let url = URL(
            string: "https://api.github.com/repos/\(Self.owner)/\(Self.repository)/releases/latest"
        ) else {
            throw BurritoUpdateClientError.invalidRepositoryURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw BurritoUpdateClientError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw BurritoUpdateClientError.invalidRelease
        }
    }
}

private enum BurritoUpdateClientError: LocalizedError {
    case invalidRepositoryURL
    case invalidResponse
    case invalidRelease

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            "The Burrito release URL is invalid."
        case .invalidResponse:
            "GitHub did not return a successful release response."
        case .invalidRelease:
            "GitHub returned release information Burrito could not read."
        }
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    func downloadURL(repository: String, version: String) -> URL? {
        let acceptedNames = [
            "Burrito.dmg",
            "\(repository)-\(version).dmg",
        ]
        return assets.first { acceptedNames.contains($0.name) }?.browserDownloadURL
    }
}

struct BurritoReleaseVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v")
            ? String(rawValue.dropFirst())
            : rawValue
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.count <= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }
        let parsed = parts.compactMap { Int($0) }
        guard parsed.count == parts.count else { return nil }
        components = parsed
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: BurritoReleaseVersion, rhs: BurritoReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        return (0..<count).allSatisfy {
            lhs.component(at: $0) == rhs.component(at: $0)
        }
    }

    static func < (lhs: BurritoReleaseVersion, rhs: BurritoReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = lhs.component(at: index)
            let right = rhs.component(at: index)
            if left != right { return left < right }
        }
        return false
    }

    private func component(at index: Int) -> Int {
        index < components.count ? components[index] : 0
    }
}
