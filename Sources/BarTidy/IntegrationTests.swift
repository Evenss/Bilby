import AppKit
import ApplicationServices
import BarTidyCore
@preconcurrency import NativeBridge

/// Read-only inventory and direct visibility checks. No input is synthesized.
@MainActor enum IntegrationTests {
    static func inventory() async -> [MenuBarItem] {
        let apps = AccessibilityInventory.applications()
        return await Task.detached { AccessibilityInventory.scan(apps) }.value
    }

    static func describe(_ item: MenuBarItem) -> [String: Any] {
        ["id": item.id, "name": item.identity.name, "bundle": item.identity.bundleID,
         "x": item.frame.minX, "y": item.frame.minY, "width": item.frame.width, "system": item.isSystem]
    }

    static func write(_ object: [String: Any], to output: URL) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
        } catch { NSLog("BarTidy diagnostics: %@", error.localizedDescription) }
    }

    static func diagnose(output: URL) async {
        let controller = BTVisibilityController()
        let found = await inventory()
        write(["system": ProcessInfo.processInfo.operatingSystemVersionString,
               "accessibility": AXIsProcessTrusted(), "nativeVisibility": controller.available,
               "items": found.map(describe)], to: output)
    }

    static func run(output: URL) async {
        let controller = BTVisibilityController()
        var result: [String: Any] = ["accessibility": AXIsProcessTrusted(), "nativeVisibility": controller.available]
        defer { controller.restore(); write(result, to: output) }
        guard AXIsProcessTrusted() else { result["error"] = "Accessibility permission required"; return }
        let original = await inventory().filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }
        result["before"] = original.map(describe)
        guard original.count == 3 else { result["error"] = "Expected three fixture icons"; return }
        result["overflowInventoryPassed"] = true
        do {
            let running = Set(AccessibilityInventory.applications().map(\.bundleID))
            let allowed = Array(running.subtracting(["com.bartidy.fixture.A"]))
            let activity = PointerActivity()
            activity.start()
            defer { activity.stop() }
            // A live desktop may be in use. Observe movement without blocking
            // events or taking control of the pointer; prefer a quiet sample.
            await activity.waitForQuietPointer()
            let pointer = NSEvent.mouseLocation
            let inputBefore = activity.movements
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.applyAllowedBundles(allowed) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            result["visibilityApplied"] = controller.active
            try await Task.sleep(for: .milliseconds(650))
            let pointerAfter = NSEvent.mouseLocation
            result["pointerUnchanged"] = pointerAfter == pointer
            result["pointerBefore"] = [pointer.x, pointer.y]
            result["pointerAfter"] = [pointerAfter.x, pointerAfter.y]
            result["pointerInputEvents"] = activity.movements - inputBefore
            let hiddenSnapshot = await authoritativeInventory()
            result["hideConfirmedInInventory"] = hiddenSnapshot.isReadable &&
                !hiddenSnapshot.items.contains { $0.identity.bundleID == "com.bartidy.fixture.A" }
            if ProcessInfo.processInfo.environment["BARTIDY_INTEGRATION_HOLD"] == "1" {
                result["stage"] = "hidden"
                write(result, to: output)
                try await Task.sleep(for: .seconds(20))
                result.removeValue(forKey: "stage")
            }
            controller.restore()
            try await Task.sleep(for: .milliseconds(300))
            result["restorePassed"] = !controller.active
            var restored: [MenuBarItem] = []
            for _ in 0..<20 {
                restored = await inventory().filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }
                if restored.map(\.id) == original.map(\.id) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            result["afterRestore"] = restored.map(describe)
            result["systemOrderUnchanged"] = restored.map(\.id) == original.map(\.id)
            let cancellationText = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                controller.applyAllowedBundles(allowed) { error in
                    continuation.resume(returning: error?.localizedDescription)
                }
                controller.restore()
            }
            let cancellation = cancellationText != nil
            result["lateActivationCancelled"] = cancellation && !controller.active
            result["nativeErrorLocalized"] = cancellationText == L10n.text("The menu bar request was cancelled.")
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controller.applyAllowedBundles(allowed) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            let pendingCancelled = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                controller.applyAllowedBundles(allowed) { error in continuation.resume(returning: error != nil) }
                controller.cancelPendingActivations()
            }
            result["cancelPendingKeepsActiveAssertion"] = pendingCancelled && controller.active
            controller.restore()
            // Assertion completion precedes MenuBarAgent's AX scene update.
            // Start the editor-order regression from a fully restored scene.
            for _ in 0..<20 {
                let visible = await inventory().filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }
                if visible.map(\.id) == original.map(\.id) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let editorChecks = try await editorRegression(items: original, outputDirectory: output.deletingLastPathComponent())
            result.merge(editorChecks) { _, new in new }
            result["completed"] = result["systemOrderUnchanged"] as? Bool == true &&
                result["hideConfirmedInInventory"] as? Bool == true && pendingCancelled &&
                cancellation && !controller.active && editorChecks.values.allSatisfy { $0 }
        } catch { result["error"] = error.localizedDescription }
    }

    @MainActor private final class PointerActivity {
        private var monitor: Any?
        private(set) var movements = 0

        func start() {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated {
                    if event.deltaX != 0 || event.deltaY != 0 { self?.movements += 1 }
                }
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        func waitForQuietPointer() async {
            var previous = NSEvent.mouseLocation
            var quiet = 0
            for _ in 0..<30 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                let current = NSEvent.mouseLocation
                quiet = current == previous ? quiet + 1 : 0
                if quiet >= 4 { return }
                previous = current
            }
        }
    }

    private static func authoritativeInventory() async -> AccessibilityInventory.Snapshot {
        let apps = AccessibilityInventory.applications()
        return await Task.detached { AccessibilityInventory.read(apps) }.value
    }

    /// Exercise the real editor methods, with an isolated profile directory.
    /// This catches a reveal override masking a visibility switch change.
    private static func editorRegression(items: [MenuBarItem], outputDirectory: URL) async throws -> [String: Bool] {
        let directory = outputDirectory.appending(path: "integration-editor-\(UUID().uuidString)")
        let store = ProfileStore(directory: directory)
        var profile = LayoutProfile()
        profile.merge(items.map(\.identity))
        // Deliberately conflict with macOS. Legacy icon IDs must not reorder
        // inventory or seed the independent app-list ordering.
        profile.order.reverse()
        profile.hiddenBundles = ["com.bartidy.fixture.A"]
        try store.save(profile)
        let controller = BTVisibilityController()
        var environment = AppEnvironment.live(controller: controller)
        // The integration binary is deliberately outside /Applications. Its
        // isolated editor exercises visibility, independently of first-run UI.
        environment.installation = .installed
        let editor = AppModel(store: store, environment: environment)
        defer {
            editor.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        await editor.refresh()
        let expectedBundles = items.reduce(into: [String]()) { bundles, item in
            if !bundles.contains(item.identity.bundleID) { bundles.append(item.identity.bundleID) }
        }
        let displayedBundles = editor.managedApps.filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }.map { $0.identity.bundleID }
        var checks = ["editorIgnoresLegacyOrder": displayedBundles == expectedBundles]
        await editor.apply()
        await editor.verificationTask?.value
        checks["editorInitialHide"] = controller.active && !editor.isRevealed && editor.error == nil
        checks["editorBackgroundConfirmation"] = editor.error == nil && editor.unconfirmedBundles.isEmpty &&
            editor.saved.hiddenBundles.contains("com.bartidy.fixture.A")
        checks["oneSwitchPerApp"] = editor.managedApps.filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }.count == 2
        checks["hiddenAppsOutsideSystemOrder"] = !editor.statusBarApps.contains { $0.identity.bundleID == "com.bartidy.fixture.A" } &&
            editor.otherApps.contains { $0.identity.bundleID == "com.bartidy.fixture.A" }
        let originalOrder = editor.saved.order

        await editor.toggleReveal()
        checks["editorTemporaryReveal"] = editor.isRevealed && !controller.active
        var revealedOrder = editor.statusBarApps.filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }.map { $0.identity.bundleID }
        // Releasing the native assertion completes before MenuBarAgent always
        // publishes the restored AX positions. Wait for the same read-only
        // inventory updates that the open settings window receives.
        for _ in 0..<10 where revealedOrder != expectedBundles {
            try await Task.sleep(for: .milliseconds(100))
            await editor.refresh(silently: true)
            revealedOrder = editor.statusBarApps.filter { $0.identity.bundleID.hasPrefix("com.bartidy.fixture.") }.map { $0.identity.bundleID }
        }
        checks["revealedOrderMatchesSystem"] = revealedOrder == expectedBundles
        if revealedOrder != expectedBundles {
            NSLog("BarTidy revealed order mismatch: expected %@, observed %@", expectedBundles.description, revealedOrder.description)
        }
        await editor.toggleReveal()
        checks["restoreEndsReveal"] = !editor.isRevealed && controller.active && editor.error == nil

        await editor.toggleReveal()
        guard let b = editor.items.first(where: { $0.identity.bundleID == "com.bartidy.fixture.B" }) else {
            throw NSError(domain: "BarTidy.Integration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture B missing from editor"])
        }
        await editor.setHidden(b.identity.bundleID, hidden: true)
        await editor.verificationTask?.value
        let afterHide = try store.load()
        checks["switchAppliesHide"] = controller.active && editor.saved.hiddenBundles.contains("com.bartidy.fixture.B") &&
            afterHide.hiddenBundles.contains("com.bartidy.fixture.B") && !editor.hasChanges && editor.error == nil
        checks["switchExitsReveal"] = !editor.isRevealed

        await editor.setHidden(b.identity.bundleID, hidden: false)
        let afterShow = try store.load()
        checks["switchAppliesShow"] = !editor.saved.hiddenBundles.contains("com.bartidy.fixture.B") &&
            !afterShow.hiddenBundles.contains("com.bartidy.fixture.B") &&
            !editor.hasChanges && controller.active && editor.error == nil
        checks["switchPreservesStoredOrder"] = editor.saved.order == originalOrder
        checks["switchAppendsDisplayOrder"] = afterHide.appDisplayOrder.last == b.identity.bundleID &&
            afterShow.appDisplayOrder.last == b.identity.bundleID
        let displayOrder = editor.saved.appDisplayOrder
        // Position diagnostics refresh explicitly; switches no longer wait
        // for a full AX inventory scan before completing.
        await editor.refresh(silently: true)
        checks["refreshPreservesDisplayOrder"] = editor.saved.appDisplayOrder == displayOrder
        let actualShown = await inventory().filter { $0.identity.bundleID == "com.bartidy.fixture.B" }
        let displayedShown = editor.statusBarApps.filter { $0.identity.bundleID == "com.bartidy.fixture.B" }
        checks["shownPositionRefreshed"] = displayedShown.first?.frame == actualShown.first?.frame && !displayedShown.isEmpty

        await editor.toggleReveal()
        await editor.setHidden("com.bartidy.fixture.A", hidden: true)
        checks["unchangedHiddenSelectionEndsReveal"] = !editor.isRevealed && controller.active && editor.error == nil
        await editor.verificationTask?.value
        let savedBeforeSleep = editor.saved.hiddenBundles
        editor.setSuspended(true, reason: "integrationSleep")
        controller.restore() // Simulate a lost system assertion, without locking this Mac.
        editor.setSuspended(false, reason: "integrationSleep")
        for _ in 0..<30 {
            if controller.active { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        await editor.verificationTask?.value
        checks["resumeReappliesSavedVisibility"] = controller.active && editor.error == nil &&
            editor.saved.hiddenBundles == savedBeforeSleep
        let resumed = await authoritativeInventory()
        checks["resumeHideConfirmedInInventory"] = resumed.isReadable &&
            !resumed.items.contains { $0.identity.bundleID == "com.bartidy.fixture.A" }
        return checks
    }
}
