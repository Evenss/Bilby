import Foundation
import Testing
@testable import BarTidyCore

private func app(_ bundle: String) -> ItemIdentity {
    ItemIdentity(id: "\(bundle)/icon", bundleID: bundle, name: bundle)
}

@Test func displayOrderSurvivesInventoryReordering() {
    var profile = LayoutProfile()
    profile.order = ["C/icon", "B/icon", "A/icon"]
    profile.registerDisplayApps(["A", "B", "C"])
    profile.registerDisplayApps(["C", "D", "B", "A", "D"])
    let shown = profile.displayedApps([app("D"), app("C"), app("B"), app("A"), app("B")])
    #expect(shown.map(\.bundleID) == ["A", "B", "C", "D"])
    #expect(profile.order == ["C/icon", "B/icon", "A/icon"])
}

@Test func visibilityChangesAppendToDestinationGroup() {
    var profile = LayoutProfile()
    profile.order = ["legacy"]
    profile.registerDisplayApps(["A", "B", "C", "D"])
    profile.hiddenBundles = ["B", "D"]
    profile.hiddenBundles.insert("A")
    profile.appendDisplayApp("A")
    var rows = profile.displayedApps([app("A"), app("B"), app("C"), app("D")])
    #expect(rows.filter { profile.hiddenBundles.contains($0.bundleID) }.map(\.bundleID) == ["B", "D", "A"])
    profile.hiddenBundles.remove("B")
    profile.appendDisplayApp("B")
    rows = profile.displayedApps(rows)
    #expect(rows.filter { !profile.hiddenBundles.contains($0.bundleID) }.map(\.bundleID) == ["C", "B"])
    #expect(rows.filter { profile.hiddenBundles.contains($0.bundleID) }.map(\.bundleID) == ["D", "A"])
    #expect(profile.order == ["legacy"])
    #expect(profile.allowedBundles(running: ["A", "B", "C", "D"], own: "self") == ["B", "C", "self"])
}

@Test func displayOrderRetainsOfflineApps() {
    var profile = LayoutProfile()
    profile.registerDisplayApps(["A", "B"])
    profile.registerDisplayApps(["B", "C"])
    #expect(profile.displayedApps([app("B"), app("C")]).map(\.bundleID) == ["B", "C"])
    #expect(profile.displayedApps([app("C"), app("A"), app("B")]).map(\.bundleID) == ["A", "B", "C"])
}

@Test func legacyProfilesMigrateDisplayOrderAndPersistIt() throws {
    let old = Data(#"{"version":2,"hiddenBundles":["A"],"order":["legacy"],"knownItems":[],"hidingEnabled":true}"#.utf8)
    var profile = try JSONDecoder().decode(LayoutProfile.self, from: old)
    #expect(profile.appDisplayOrder.isEmpty)
    profile.registerDisplayApps(["A", "B"])
    profile.appendDisplayApp("A")
    let restored = try JSONDecoder().decode(LayoutProfile.self, from: JSONEncoder().encode(profile))
    #expect(restored.appDisplayOrder == ["B", "A"])
    #expect(restored.hiddenBundles == ["A"])
    #expect(restored.order == ["legacy"])
}
