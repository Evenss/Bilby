import Foundation
import Testing
@testable import BarTidyCore

private func item(_ id: String, bundle: String? = nil) -> ItemIdentity {
    ItemIdentity(id: id, bundleID: bundle ?? id, name: id)
}

@Test func refreshPreservesOfflineChoicesAndOrder() {
    var profile = LayoutProfile()
    profile.merge([item("A"), item("B")])
    profile.hiddenBundles = ["A"]
    profile.move("B", before: "A")
    profile.merge([item("B"), item("C")])
    #expect(profile.order == ["B", "A", "C"])
    #expect(profile.knownItems.count == 3)
    #expect(profile.hiddenBundles == ["A"])
}

@Test func refreshDoesNotDuplicateIdentifiers() {
    var profile = LayoutProfile()
    profile.merge([item("A"), item("A"), item("B")])
    profile.merge([item("A")])
    #expect(profile.order == ["A", "B"])
    #expect(profile.knownItems.count == 2)
}

@Test func visibilityIsPerAppAndKeepsUnseenAppsAndSelf() {
    var profile = LayoutProfile()
    profile.hiddenBundles = ["hidden", "self"]
    #expect(profile.allowedBundles(running: ["hidden", "shown", "new"], own: "self") == ["new", "self", "shown"])
}

@Test func revealOverridesHiddenPreferencesWithoutErasingThem() {
    var profile = LayoutProfile()
    profile.hiddenBundles = ["A"]
    profile.hidingEnabled = false
    #expect(profile.allowedBundles(running: ["A", "B"], own: "self") == ["A", "B", "self"])
    #expect(profile.hiddenBundles == ["A"])
}

@Test func reorderHasDefinedBoundaries() {
    var profile = LayoutProfile()
    profile.merge([item("A"), item("B"), item("C")])
    profile.move("A", offset: -1)
    profile.move("C", offset: 1)
    #expect(profile.order == ["A", "B", "C"])
    profile.move("C", before: "A")
    #expect(profile.order == ["C", "A", "B"])
    profile.move("A", before: "A")
    profile.move("unknown", before: "A")
    #expect(profile.order == ["C", "A", "B"])
}

@Test func profileRoundTrips() throws {
    var profile = LayoutProfile()
    profile.merge([item("A", bundle: "app")])
    profile.hiddenBundles = ["app"]
    let saved = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(LayoutProfile.self, from: saved) == profile)
}

@Test func unknownItemsKeepDiscoveryOrderAfterSavedItems() {
    var profile = LayoutProfile()
    profile.merge([item("B"), item("A")])
    #expect(profile.sorted([item("C"), item("A"), item("D"), item("B")]).map(\.id) == ["B", "A", "C", "D"])
}

@Test func localSortingDoesNotChangeVisibilityChoices() {
    var profile = LayoutProfile()
    profile.merge([item("A"), item("B"), item("C")])
    profile.hiddenBundles = ["B"]
    let allowed = profile.allowedBundles(running: ["A", "B", "C"], own: "self")
    profile.move("C", before: "A")
    #expect(profile.order == ["C", "A", "B"])
    #expect(profile.hiddenBundles == ["B"])
    #expect(profile.allowedBundles(running: ["A", "B", "C"], own: "self") == allowed)
}

@Test func existingProfilesKeepChoicesAfterRemovingPhysicalMoveMetadata() throws {
    let json = """
    {"version":2,"hiddenBundles":["app"],"order":["icon"],"knownItems":[{"id":"icon","bundleID":"app","name":"App","movable":false}],"hidingEnabled":true}
    """
    let profile = try JSONDecoder().decode(LayoutProfile.self, from: Data(json.utf8))
    #expect(profile.knownItems == [ItemIdentity(id: "icon", bundleID: "app", name: "App")])
    #expect(profile.hiddenBundles == ["app"])
    #expect(profile.order == ["icon"])
}

@Test func hiddenRunningIconsRemainAvailableForShowingAgain() {
    var profile = LayoutProfile()
    profile.merge([item("hidden"), item("shown"), item("offline"), item("discovered")])
    profile.hiddenBundles = ["hidden", "offline", "discovered"]
    let retained = profile.retainedHiddenItems(runningBundles: ["hidden", "shown", "discovered"], discoveredBundles: ["discovered"])
    #expect(retained.map(\.id) == ["hidden"])
}
