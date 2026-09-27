import Foundation

struct SIUVersion: Comparable, Equatable {
    let raw: String
    let major: Int
    let minor: Int
    let patch: Int
    let prereleaseRank: Int
    let prereleaseNumber: Int

    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count) else { return nil }
        let core = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        var rank = 3
        var number = 0
        if pieces.count == 2 {
            let pre = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard pre.count == 2, let parsed = Int(pre[1]), parsed >= 0 else { return nil }
            switch pre[0] {
            case "alpha": rank = 0
            case "beta": rank = 1
            case "rc": rank = 2
            default: return nil
            }
            number = parsed
        }
        raw = value
        self.major = major
        self.minor = minor
        self.patch = patch
        prereleaseRank = rank
        prereleaseNumber = number
    }

    static func < (lhs: SIUVersion, rhs: SIUVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prereleaseRank != rhs.prereleaseRank { return lhs.prereleaseRank < rhs.prereleaseRank }
        return lhs.prereleaseNumber < rhs.prereleaseNumber
    }

    static func == (lhs: SIUVersion, rhs: SIUVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch &&
            lhs.prereleaseRank == rhs.prereleaseRank &&
            lhs.prereleaseNumber == rhs.prereleaseNumber
    }
}

struct SIUAvailableUpdate {
    let version: SIUVersion
    var releaseURL: URL {
        URL(string: "https://github.com/ddingddong9/homebrew-siu/releases/tag/v\(version.raw)")!
    }
}

enum AppUpdateChecker {
    private struct Release: Decodable {
        struct Asset: Decodable { let name: String }
        let tag_name: String
        let draft: Bool
        let assets: [Asset]
    }

    enum CheckError: Error {
        case invalidResponse
    }

    static func newestUpdate(in data: Data, installed: SIUVersion) -> SIUAvailableUpdate? {
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return nil }
        return releases.compactMap { release -> SIUAvailableUpdate? in
            guard !release.draft, let version = SIUVersion(release.tag_name), version > installed,
                  release.assets.contains(where: { $0.name == "siu-v\(version.raw)-macos-app.zip" }) else {
                return nil
            }
            return SIUAvailableUpdate(version: version)
        }.max { $0.version < $1.version }
    }

    static func check(installed: SIUVersion,
                      completion: @escaping (Result<SIUAvailableUpdate?, Error>) -> Void) {
        let url = URL(string: "https://api.github.com/repos/ddingddong9/homebrew-siu/releases?per_page=30")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SIU-macOS/\(installed.raw)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<SIUAvailableUpdate?, Error>
            if let error { result = .failure(error) }
            else if let response = response as? HTTPURLResponse, response.statusCode == 200,
                    let data, (try? JSONDecoder().decode([Release].self, from: data)) != nil {
                result = .success(newestUpdate(in: data, installed: installed))
            } else { result = .failure(CheckError.invalidResponse) }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
