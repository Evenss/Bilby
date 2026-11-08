import Foundation

public enum InstallationLocation: Equatable, Sendable {
    case installed, readOnlyVolume, translocated, outsideApplications

    public init(appURL: URL, homeURL: URL, volumeIsReadOnly: Bool) {
        let path = appURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        if path.contains("AppTranslocation") { self = .translocated; return }
        if volumeIsReadOnly { self = .readOnlyVolume; return }
        let roots = [URL(filePath: "/Applications"), homeURL.appending(path: "Applications")]
        self = roots.contains { root in
            let components = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            return path.count > components.count && Array(path.prefix(components.count)) == components
        } ? .installed : .outsideApplications
    }
}
