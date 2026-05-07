import Foundation

struct ProfileManifestVersionScanner {
    static let currentManifestVersion = 5
    static let manifestFileName = "profile.json"

    private let rootURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func profilesNeedingRebuild(from profiles: [ProfileSnapshot]) -> [ProfileSnapshot] {
        profiles.filter { profile in
            guard let manifestVersion = manifestVersion(for: profile.profileName) else {
                return false
            }

            return manifestVersion < Self.currentManifestVersion
        }
    }

    func manifestVersion(for profileName: String) -> Int? {
        let manifestURL = rootURL
            .appendingPathComponent(profileName, isDirectory: true)
            .appendingPathComponent(Self.manifestFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(ProfileManifestVersion.self, from: data)
        else {
            return nil
        }

        return manifest.version
    }
}

private struct ProfileManifestVersion: Decodable {
    let version: Int
}
