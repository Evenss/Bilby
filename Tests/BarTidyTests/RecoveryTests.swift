import AppKit
import BarTidyCore
import Testing
@testable import BarTidy

@MainActor private final class SystemStub {
    let a = "test.bilby.A", b = "test.bilby.B"
    let ownBundle = Bundle.main.bundleIdentifier ?? "local.even.BarTidy"
    var trusted = true
    var usable = true
    var remembered = false
    var prompts = 0
    var active = false
    var applyCalls = 0
    var readCalls = 0
    var restores = 0
    var readable = true
    var obeysVisibility = true
    var visible: Set<String> = ["test.bilby.A", "test.bilby.B"]
    var running: Set<String> = ["test.bilby.A", "test.bilby.B"]
    var holdNextApply = false
    var heldApply: CheckedContinuation<Void, Error>?
    var holdNextRead = false
    var heldRead: CheckedContinuation<AccessibilityInventory.Snapshot, Never>?

    var apps: [AccessibilityInventory.Application] {
        (Array(running).sorted() + ["com.apple.MenuBarAgent", ownBundle]).enumerated().map {
            .init(pid: Int32($0.offset + 10), bundleID: $0.element, name: $0.element, url: nil)
        }
    }
    func item(_ bundle: String, system: Bool = false) -> MenuBarItem {
        MenuBarItem(identity: ItemIdentity(id: "\(bundle)/icon", bundleID: bundle, name: bundle), pid: 10,
                    frame: CGRect(x: bundle == a ? 100 : 130, y: 0, width: 20, height: 24), appURL: nil, isSystem: system)
    }
    var snapshot: AccessibilityInventory.Snapshot {
        .init(items: readable ? Array(visible.intersection(running)).sorted().map { item($0) } +
              [item("com.apple.MenuBarAgent", system: true), item(ownBundle)] : [], isReadable: readable)
    }
    func environment(installation: InstallationLocation = .installed) -> AppEnvironment {
        AppEnvironment(installation: installation, isTrusted: { self.trusted },
            requestTrust: { self.prompts += 1; return self.trusted },
            previouslyTrusted: { self.remembered }, rememberTrust: { self.remembered = true },
            applications: { self.apps }, readInventory: { _ in
                self.readCalls += 1
                if self.holdNextRead {
                    self.holdNextRead = false
                    return await withCheckedContinuation { self.heldRead = $0 }
                }
                return self.snapshot
            }, apply: { allowed in
                self.applyCalls += 1
                if self.holdNextApply {
                    self.holdNextApply = false
                    try await withCheckedThrowingContinuation { self.heldApply = $0 }
                }
                self.active = true
                if self.obeysVisibility { self.visible = self.running.intersection(allowed) }
            }, restore: {
                self.restores += 1; self.active = false; self.visible = self.running
            }, cancelPending: {
                self.heldApply?.resume(throwing: CancellationError()); self.heldApply = nil
            }, isActive: { self.active }, isAvailable: { true }, sessionIsUsable: { self.usable })
    }
}

@MainActor private final class Scenario {
    let system = SystemStub()
    let directory = FileManager.default.temporaryDirectory.appending(path: "Bilby-recovery-tests-\(UUID().uuidString)")
    let model: AppModel
    let store: ProfileStore

    init(hidden: Set<String> = [], installation: InstallationLocation = .installed) throws {
        store = ProfileStore(directory: directory)
        var profile = LayoutProfile()
        profile.hiddenBundles = hidden
        profile.merge([system.item(system.a).identity, system.item(system.b).identity])
        profile.registerDisplayApps([system.a, system.b])
        try store.save(profile)
        model = AppModel(store: store, environment: system.environment(installation: installation),
            timing: RecoveryTiming(verificationInterval: .milliseconds(1), samplesPerAttempt: 3, inventoryDelays: [.seconds(60)]))
    }
    func close() { model.stop(); try? FileManager.default.removeItem(at: directory) }
    func wait(until condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for background recovery")
    }
}

@Test @MainActor func installGuidePrecedesPermissionAndNativeWork() async throws {
    let s = try Scenario(installation: .readOnlyVolume)
    defer { s.close() }
    s.model.requestPermission()
    await s.model.refresh()
    await s.model.apply()
    await s.model.tick()
    #expect(!s.model.hasPermission)
    #expect(s.system.prompts == 0 && s.system.readCalls == 0 && s.system.applyCalls == 0)
    #expect(!s.system.remembered)
}

@Test @MainActor func overflowItemsSharingCoordinatesKeepStableInventoryOrder() {
    let system = SystemStub()
    var a = system.item(system.a), b = system.item(system.b)
    a.frame = b.frame // MenuBarAgent uses this shape for overflow scenes.
    let first = AccessibilityInventory.sortByPosition([b, a])
    let next = AccessibilityInventory.sortByPosition([a, b])
    #expect(first.map(\.id) == next.map(\.id))
    b.frame.origin.x += 40
    #expect(AccessibilityInventory.sortByPosition([b, a]).map(\.id) == [a.id, b.id])
}

@Test @MainActor func emptyInventoryPreservesRowsAnchorChoicesAndOrder() async throws {
    let s = try Scenario(hidden: ["test.bilby.B"])
    defer { s.close() }
    await s.model.refresh()
    #expect(s.model.ownStatusItemFrame != nil)
    let rows = s.model.items.map(\.id), anchor = s.model.ownStatusItemFrame, order = s.model.saved.appDisplayOrder
    s.system.readable = false
    #expect(await s.model.refresh() == false)
    #expect(s.model.items.map(\.id) == rows)
    #expect(s.model.ownStatusItemFrame == anchor)
    #expect(s.model.saved.hiddenBundles == [s.system.b])
    #expect(s.model.saved.appDisplayOrder == order && s.model.isWaitingForInventory)
    s.system.readable = true
    s.system.running.remove(s.system.a)
    await s.model.refresh()
    #expect(!s.model.managedApps.contains { $0.identity.bundleID == s.system.a })
    #expect(!s.model.isWaitingForInventory)
}

@Test @MainActor func startupWithUnreadableInventoryStillOffersKnownHiddenSwitches() async throws {
    let s = try Scenario(hidden: ["test.bilby.A"])
    defer { s.close() }
    s.system.readable = false
    await s.model.refresh()
    #expect(s.model.managedApps.map { $0.identity.bundleID } == [s.system.a])
    await s.model.setHidden(s.system.a, hidden: false)
    #expect(s.model.saved.hiddenBundles.isEmpty && s.model.error == nil)
    #expect(try s.store.load().hiddenBundles.isEmpty)
    #expect(!s.model.isBusy && s.model.recoveryTask != nil)
}

@Test @MainActor func verificationUsesRawInventoryRatherThanRetainedHiddenRows() async throws {
    let s = try Scenario()
    defer { s.close() }
    await s.model.refresh()
    await s.model.setHidden(s.system.a, hidden: true)
    #expect(s.model.saved.hiddenBundles.contains(s.system.a))
    #expect(!s.model.isBusy)
    await s.model.verificationTask?.value
    #expect(s.system.applyCalls == 1)
    #expect(s.model.managedApps.contains { $0.identity.bundleID == s.system.a && $0.frame == .zero })
    #expect(s.model.saved.hiddenBundles.contains(s.system.a) && s.model.error == nil)
}

@Test @MainActor func successfulCallbackWithVisibleIconRetriesThenRollsBackOnlyNewHide() async throws {
    let s = try Scenario(hidden: ["test.bilby.B"])
    defer { s.close() }
    s.system.obeysVisibility = false
    await s.model.refresh()
    await s.model.setHidden(s.system.a, hidden: true)
    await s.model.verificationTask?.value
    #expect(s.system.applyCalls == 3) // initial, one repair, corrected profile
    #expect(s.model.saved.hiddenBundles == [s.system.b])
    #expect(try s.store.load().hiddenBundles == [s.system.b])
    #expect(s.model.saved.appDisplayOrder.last == s.system.a)
    #expect(s.model.unconfirmedBundles == [s.system.b])
    #expect(s.model.error != nil && !s.model.isBusy)
    s.model.error = nil
    for _ in 0..<5 { await s.model.tick() }
    #expect(s.system.applyCalls == 3 && s.model.error == nil)
}

@Test @MainActor func unreadableSamplesCannotConfirmOrRejectHiding() async throws {
    let s = try Scenario()
    defer { s.close() }
    await s.model.refresh()
    s.system.readable = false
    await s.model.setHidden(s.system.a, hidden: true)
    await s.model.verificationTask?.value
    #expect(s.model.saved.hiddenBundles == [s.system.a])
    #expect(s.model.error == nil && s.model.isWaitingForInventory)
    #expect(s.system.applyCalls == 1 && s.model.recoveryTask != nil)
    let reads = s.system.readCalls
    for _ in 0..<5 { await s.model.tick() }
    #expect(s.system.readCalls == reads) // heartbeat must respect the retry delay
    s.model.setSuspended(true, reason: "lock")
    #expect(s.model.recoveryTask == nil && s.model.verificationTask == nil)
}

@Test @MainActor func wakeWithoutObservedSleepStillRepairsTheAssertion() async throws {
    let s = try Scenario(hidden: ["test.bilby.A"])
    defer { s.close() }
    await s.model.refresh()
    await s.model.apply()
    await s.model.verificationTask?.value
    let applies = s.system.applyCalls
    s.system.visible = s.system.running
    s.model.resumeAfterSystemEvent(reason: "sleep")
    try await s.wait { s.system.applyCalls > applies }
    await s.model.verificationTask?.value
    #expect(!s.system.visible.contains(s.system.a) && s.model.error == nil)
}

@Test @MainActor func newShowSupersedesPendingHideVerification() async throws {
    let s = try Scenario()
    defer { s.close() }
    s.system.obeysVisibility = false
    await s.model.refresh()
    await s.model.setHidden(s.system.a, hidden: true)
    let obsolete = s.model.verificationTask
    await s.model.setHidden(s.system.a, hidden: false)
    await obsolete?.value
    #expect(s.model.saved.hiddenBundles.isEmpty)
    #expect(try s.store.load().hiddenBundles.isEmpty)
    #expect(s.model.error == nil && s.model.unconfirmedBundles.isEmpty)
    #expect(!s.system.active && s.system.applyCalls == 1)
}

@Test @MainActor func inFlightInventoryCannotOverwriteNewVisibility() async throws {
    let s = try Scenario()
    defer { s.close() }
    await s.model.refresh()
    let oldSnapshot = s.system.snapshot
    s.system.holdNextRead = true
    let read = Task { await s.model.refresh(silently: true) }
    try await s.wait { s.system.heldRead != nil }
    await s.model.setHidden(s.system.a, hidden: true)
    s.system.heldRead?.resume(returning: oldSnapshot); s.system.heldRead = nil
    #expect(await read.value == false)
    await s.model.verificationTask?.value
    #expect(s.model.saved.hiddenBundles == [s.system.a])
    #expect(s.model.managedApps.first { $0.identity.bundleID == s.system.a }?.frame == .zero)
}

@Test @MainActor func lockPausesWorkAndUnlockReappliesEvenIfAssertionStillActive() async throws {
    let s = try Scenario(hidden: ["test.bilby.A"])
    defer { s.close() }
    await s.model.refresh()
    await s.model.apply()
    await s.model.verificationTask?.value
    let reads = s.system.readCalls, applies = s.system.applyCalls
    s.system.visible = s.system.running // compositor lost the effect, handle remains active
    s.system.usable = false
    s.model.setSuspended(true, reason: "lock")
    await s.model.tick()
    #expect(s.system.readCalls == reads && s.system.applyCalls == applies)
    #expect(s.system.active && s.model.saved.hiddenBundles == [s.system.a])
    s.system.usable = true
    s.model.setSuspended(false, reason: "lock")
    await s.model.tick()
    try await s.wait { s.system.applyCalls > applies }
    await s.model.verificationTask?.value
    #expect(!s.model.isSuspended && !s.system.visible.contains(s.system.a))
    #expect(s.model.error == nil && s.model.saved.hiddenBundles == [s.system.a])
}

@Test @MainActor func interruptedActivationKeepsLatestSavedChoiceForResume() async throws {
    let s = try Scenario()
    defer { s.close() }
    await s.model.refresh()
    s.system.holdNextApply = true
    let change = Task { await s.model.setHidden(s.system.a, hidden: true) }
    try await s.wait { s.system.heldApply != nil }
    s.model.setSuspended(true, reason: "sleep")
    await change.value
    #expect(!s.model.isBusy && s.model.error == nil)
    #expect(try s.store.load().hiddenBundles == [s.system.a])
    s.model.setSuspended(false, reason: "sleep")
    try await s.wait { s.system.applyCalls == 2 }
    await s.model.verificationTask?.value
    #expect(s.model.saved.hiddenBundles == [s.system.a] && !s.system.visible.contains(s.system.a))
}

@Test @MainActor func newUserChoicePreemptsAnInFlightBackgroundRepair() async throws {
    let s = try Scenario(hidden: ["test.bilby.A"])
    defer { s.close() }
    await s.model.refresh()
    await s.model.apply()
    await s.model.verificationTask?.value
    s.system.holdNextApply = true
    s.model.resumeAfterSystemEvent(reason: "sleep")
    try await s.wait { s.system.heldApply != nil }
    #expect(!s.model.isBusy)
    await s.model.setHidden(s.system.a, hidden: false)
    for _ in 0..<10 { await Task.yield() }
    #expect(s.model.saved.hiddenBundles.isEmpty && s.model.draft.hiddenBundles.isEmpty)
    #expect(try s.store.load().hiddenBundles.isEmpty)
    #expect(s.model.error == nil && !s.system.active && !s.model.isBusy)
}

@Test @MainActor func revokedPermissionRestoresIconsAndKeepsChoicesUntilRegrant() async throws {
    let s = try Scenario(hidden: ["test.bilby.A"])
    defer { s.close() }
    await s.model.refresh()
    await s.model.apply()
    await s.model.verificationTask?.value
    #expect(s.system.remembered)
    s.system.trusted = false
    await s.model.tick()
    #expect(!s.model.hasPermission && s.model.permissionWasGranted && !s.system.active)
    #expect(s.model.saved.hiddenBundles == [s.system.a])
    // A queued switch from the old form must not create an unsaved draft or
    // reopen System Settings after permission has already been withdrawn.
    await s.model.setHidden(s.system.b, hidden: true)
    #expect(s.model.draft.hiddenBundles == [s.system.a] && s.system.prompts == 0)
    s.system.trusted = true
    await s.model.tick()
    try await s.wait { s.system.active }
    await s.model.verificationTask?.value
    #expect(s.model.hasPermission && !s.system.visible.contains(s.system.a))
}

@Test @MainActor func stopCancelsPendingVerificationAndRecovery() async throws {
    let s = try Scenario()
    defer { s.close() }
    await s.model.refresh()
    s.system.readable = false
    await s.model.setHidden(s.system.a, hidden: true)
    let pending = s.model.verificationTask
    s.model.stop()
    await pending?.value
    await s.model.tick()
    #expect(s.model.verificationTask == nil && s.model.recoveryTask == nil)
    #expect(!s.system.active && s.system.applyCalls == 1)
}
