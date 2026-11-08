import Foundation
import Testing
@testable import BarTidyCore

@Test func installationRequiresAnApplicationsDirectoryOnAWritableVolume() {
    let home = URL(filePath: "/Users/test")
    func location(_ path: String, readOnly: Bool = false) -> InstallationLocation {
        InstallationLocation(appURL: URL(filePath: path), homeURL: home, volumeIsReadOnly: readOnly)
    }
    #expect(location("/Applications/Bilby.app") == .installed)
    #expect(location("/Users/test/Applications/Bilby.app") == .installed)
    #expect(location("/Applications-old/Bilby.app") == .outsideApplications)
    #expect(location("/Users/test/Downloads/Bilby.app") == .outsideApplications)
    #expect(location("/Volumes/Bilby/Bilby.app", readOnly: true) == .readOnlyVolume)
    #expect(location("/private/var/folders/AppTranslocation/id/d/Bilby.app", readOnly: true) == .translocated)
    #expect(location("/Applications/Bilby.app", readOnly: true) == .readOnlyVolume)
}
