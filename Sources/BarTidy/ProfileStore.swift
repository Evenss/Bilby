import Foundation
import BarTidyCore

struct ProfileStore {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "BarTidy")) {
        self.directory = directory
    }

    var url: URL { directory.appending(path: "layout.json") }

    func load() throws -> LayoutProfile {
        guard FileManager.default.fileExists(atPath: url.path) else { return LayoutProfile() }
        return try JSONDecoder().decode(LayoutProfile.self, from: Data(contentsOf: url))
    }

    func save(_ profile: LayoutProfile) throws {
        try write(profile, to: url)
    }

    var draftURL: URL { directory.appending(path: "draft.json") }

    func loadDraft() throws -> LayoutProfile? {
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
        return try JSONDecoder().decode(LayoutProfile.self, from: Data(contentsOf: draftURL))
    }

    func clearDraft() throws {
        if FileManager.default.fileExists(atPath: draftURL.path) { try FileManager.default.removeItem(at: draftURL) }
    }

    private func write(_ profile: LayoutProfile, to destination: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: destination, options: .atomic)
    }
}
