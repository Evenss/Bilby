import AppKit
import BarTidyCore
import Observation
@preconcurrency import NativeBridge

@MainActor @Observable final class AppModel {
    let ownBundle = Bundle.main.bundleIdentifier ?? "local.even.BarTidy"
    private(set) var items: [MenuBarItem] = []
    private(set) var ownStatusItemFrame: CGRect?
    var draft = LayoutProfile()
    private(set) var saved = LayoutProfile()
    private(set) var hasPermission: Bool
    private(set) var permissionWasGranted: Bool
    let visibility: BTVisibilityController
    let installation: InstallationLocation
    var isBusy = false
    private(set) var isLoading = false
    private(set) var isWaitingForInventory = false
    private(set) var isSuspended = false
    private(set) var unconfirmedBundles: Set<String> = []
    var isRevealed = false
    var isSettingsVisible = false
    var message = L10n.text("Reading the menu bar…")
    var error: String?
    var onStateChange: (() -> Void)?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var allowedProcesses: Set<String> = []
    private var isRefreshing = false
    private var isRecovering = false
    private var awaitingPosition: Set<String> = []
    private var pendingHides: Set<String> = []
    private var revision = 0
    private var foregroundRevision: Int?
    private var needsReapply = true
    private var stopped = false
    private var emptyReads = 0
    private var idleTicks = 0
    private var verificationFailedRevision: Int?
    private var pauseReasons: Set<String> = []
    private(set) var verificationTask: Task<Void, Never>?
    private(set) var recoveryTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private let store: ProfileStore
    private let environment: AppEnvironment
    private let timing: RecoveryTiming

    init(store: ProfileStore = ProfileStore(), environment: AppEnvironment? = nil, timing: RecoveryTiming = RecoveryTiming()) {
        let controller = BTVisibilityController()
        self.visibility = controller
        let environment = environment ?? .live(controller: controller)
        self.environment = environment
        self.installation = environment.installation
        self.hasPermission = environment.installation == .installed && environment.isTrusted()
        self.permissionWasGranted = environment.previouslyTrusted()
        self.store = store
        self.timing = timing
        do { saved = try store.load(); draft = try store.loadDraft() ?? saved }
        catch { self.error = L10n.format("Couldn't read saved settings: %@", error.localizedDescription) }
        // A first scan can also be temporarily unavailable after login. Keep
        // switches for known, hidden, running apps usable from the saved profile.
        if hasPermission {
            let byBundle = Dictionary(environment.applications().map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            var retention = draft
            retention.hiddenBundles.formUnion(saved.hiddenBundles)
            items = retention.retainedHiddenItems(runningBundles: Set(byBundle.keys), discoveredBundles: []).compactMap { identity in
                guard identity.bundleID != ownBundle, !identity.bundleID.hasPrefix("com.apple."),
                      let app = byBundle[identity.bundleID] else { return nil }
                return MenuBarItem(identity: identity, pid: app.pid, frame: .zero, appURL: app.url, isSystem: false)
            }
        }
    }

    var hasChanges: Bool {
        draft.hiddenBundles != saved.hiddenBundles || draft.order != saved.order ||
            draft.appDisplayOrder != saved.appDisplayOrder || draft.hidingEnabled != saved.hidingEnabled
    }
    var nativeAvailable: Bool { environment.isAvailable() }
    var hiddenCount: Int { managedApps.filter { draft.hiddenBundles.contains($0.identity.bundleID) }.count }
    var managedApps: [MenuBarItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.identity.bundleID).inserted }
    }
    var statusBarApps: [MenuBarItem] {
        AccessibilityInventory.sortByPosition(managedApps.filter {
            $0.frame.width > 0 && $0.frame.height > 0 &&
                (isRevealed || !draft.hiddenBundles.contains($0.identity.bundleID))
        })
    }
    var otherApps: [MenuBarItem] {
        let positioned = Set(statusBarApps.map { $0.identity.bundleID })
        return managedApps.filter { !positioned.contains($0.identity.bundleID) }.sorted {
            let comparison = $0.identity.name.localizedStandardCompare($1.identity.name)
            return comparison == .orderedSame ? $0.identity.bundleID < $1.identity.bundleID : comparison == .orderedAscending
        }
    }
    private var canWork: Bool { !stopped && installation == .installed && hasPermission && !isSuspended }

    func start(onReady: (() -> Void)? = nil) {
        updatePermission()
        setSuspended(!environment.sessionIsUsable(), reason: "sessionState")
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(center, event) { model in
                model.needsReapply = true
                model.scheduleRecovery(after: .milliseconds(350))
            }
        }
        for (pause, resume, reason) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ] {
            observe(center, pause) { $0.setSuspended(true, reason: reason) }
            observe(center, resume) { $0.resumeAfterSystemEvent(reason: reason) }
        }
        // Lock/unlock is distinct from sleep and fast user switching.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.setSuspended(true, reason: "lock") }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.resumeAfterSystemEvent(reason: "lock") }
        startupTask = Task { [weak self] in
            guard let self else { return }
            if await refresh() { await apply() }
            guard !Task.isCancelled, !stopped else { return }
            onReady?()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor (AppModel) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self, !self.stopped { action(self) } }
        }
        observers.append((center, observer))
    }

    func requestPermission() {
        guard installation == .installed else { return }
        hasPermission = environment.requestTrust()
        if hasPermission { rememberPermission() }
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard installation == .installed else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    func openApplicationsFolder() { NSWorkspace.shared.open(URL(filePath: "/Applications")) }

    private func rememberPermission() {
        if !permissionWasGranted { environment.rememberTrust(); permissionWasGranted = true }
    }

    private func updatePermission() {
        guard installation == .installed, !stopped else { return }
        let granted = environment.isTrusted()
        if granted { rememberPermission() }
        guard granted != hasPermission else { return }
        hasPermission = granted
        supersede()
        foregroundRevision = nil
        isBusy = false
        needsReapply = true
        if granted { scheduleRecovery() }
        else { environment.restore(); message = L10n.text("Accessibility access was disabled. Your choices are saved.") }
        onStateChange?()
    }

    /// Tests use this same state transition without locking the user's Mac.
    func setSuspended(_ suspended: Bool, reason: String) {
        if suspended { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        let next = !pauseReasons.isEmpty
        guard next != isSuspended else { return }
        isSuspended = next
        supersede()
        foregroundRevision = nil
        isBusy = false
        needsReapply = true
        if !next { updatePermission(); scheduleRecovery() }
        onStateChange?()
    }

    func tick() async {
        guard !stopped, installation == .installed else { return }
        updatePermission()
        let usable = environment.sessionIsUsable()
        // Polling also repairs a missed unlock/session notification.
        if usable {
            setSuspended(false, reason: "lock")
            setSuspended(false, reason: "session")
        }
        setSuspended(!usable, reason: "sessionState")
        guard canWork, !isBusy else { return }
        let processes = processKeys(environment.applications())
        if processes != allowedProcesses { needsReapply = true }
        if needsReapply { if recoveryTask == nil { scheduleRecovery() }; return }
        if isSettingsVisible { await refresh(silently: true) }
        idleTicks += 1
        if idleTicks >= 5, verificationTask == nil { idleTicks = 0; scheduleVerification() }
    }

    func resumeAfterSystemEvent(reason: String) {
        guard !stopped else { return }
        setSuspended(false, reason: reason)
        setSuspended(!environment.sessionIsUsable(), reason: "sessionState")
        // Wake can arrive without a matching pause (for example at startup).
        // A live assertion handle does not prove its effect survived sleep.
        supersede()
        foregroundRevision = nil
        isBusy = false
        needsReapply = true
        scheduleRecovery()
    }

    @discardableResult func refresh(silently: Bool = false) async -> Bool {
        updatePermission()
        guard canWork, !isBusy, !isRefreshing else { return false }
        isRefreshing = true
        isLoading = items.isEmpty
        let token = revision
        defer { isRefreshing = false; isLoading = false }
        let apps = environment.applications()
        let snapshot = await environment.readInventory(apps)
        guard canWork, token == revision, !Task.isCancelled else { return false }
        guard snapshot.isReadable else {
            isWaitingForInventory = true
            needsReapply = true
            message = L10n.text("Waiting for the menu bar to recover. Your choices are saved.")
            scheduleInventoryRetry()
            return false
        }
        consume(snapshot, applications: apps)
        if !silently { message = L10n.format("Apps found: %ld. Changes are saved automatically.", managedApps.count) }
        return true
    }

    private func consume(_ snapshot: AccessibilityInventory.Snapshot, applications: [AccessibilityInventory.Application]) {
        if isWaitingForInventory { recoveryTask?.cancel(); recoveryTask = nil }
        isWaitingForInventory = false
        emptyReads = 0
        if let own = snapshot.items.first(where: { $0.identity.bundleID == ownBundle }) { ownStatusItemFrame = own.frame }
        let discovered = snapshot.items.filter { $0.identity.bundleID != ownBundle && !$0.isSystem }
        let runningByBundle = Dictionary(applications.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let discoveredBundles = Set(discovered.map { $0.identity.bundleID })
        awaitingPosition.subtract(discoveredBundles)
        awaitingPosition.formIntersection(runningByBundle.keys)
        var retention = draft
        retention.hiddenBundles.formUnion(saved.hiddenBundles)
        retention.hiddenBundles.formUnion(awaitingPosition)
        let retained = retention.retainedHiddenItems(runningBundles: Set(runningByBundle.keys), discoveredBundles: discoveredBundles)
        items = discovered + retained.compactMap { identity in
            guard !identity.bundleID.hasPrefix("com.apple."), let app = runningByBundle[identity.bundleID] else { return nil }
            return MenuBarItem(identity: identity, pid: app.pid, frame: .zero, appURL: app.url, isSystem: false)
        }
        if saved.version < 2 {
            let liveIDs = discovered.map(\.id)
            let live = Set(liveIDs)
            saved.order = liveIDs + saved.order.filter { !live.contains($0) }
            saved.version = 2
            draft.order = saved.order
            draft.version = 2
        }
        saved.merge(discovered.map(\.identity))
        draft.merge(discovered.map(\.identity))
        let displayBundles = (statusBarApps + otherApps).map { $0.identity.bundleID }
        saved.registerDisplayApps(displayBundles)
        draft.registerDisplayApps(displayBundles)
        onStateChange?()
    }

    func setHidden(_ bundleID: String, hidden: Bool) async {
        guard !stopped, hasPermission, !isBusy,
              managedApps.contains(where: { $0.identity.bundleID == bundleID && !$0.isSystem }) else { return }
        guard draft.hiddenBundles.contains(bundleID) != hidden || isRevealed else { return }
        if hidden { draft.hiddenBundles.insert(bundleID); awaitingPosition.remove(bundleID) }
        else { draft.hiddenBundles.remove(bundleID); awaitingPosition.insert(bundleID); pendingHides.remove(bundleID) }
        draft.appendDisplayApp(bundleID)
        await apply()
    }

    func apply() async {
        guard !stopped, !isBusy, installation == .installed else { return }
        guard hasPermission else { requestPermission(); return }
        let previous = saved
        let candidate = draft
        let wasRevealed = isRevealed
        supersede()
        let token = revision
        foregroundRevision = token
        isBusy = true
        isRevealed = false
        error = nil
        pendingHides.formUnion(candidate.hiddenBundles.subtracting(previous.hiddenBundles))
        onStateChange?()
        defer {
            if foregroundRevision == token { foregroundRevision = nil; isBusy = false; onStateChange?() }
        }
        do {
            // Save the latest intent before awaiting the system, including when
            // a lock or sleep interrupts that activation. UI regrouping is immediate.
            try store.save(candidate)
            saved = candidate
            draft = candidate
            try? store.clearDraft()
            guard canWork else { needsReapply = true; return }
            if candidate.hiddenBundles != previous.hiddenBundles || candidate.hidingEnabled != previous.hidingEnabled || wasRevealed || !environment.isActive() {
                try await setVisibility(candidate)
            }
            guard token == revision, canWork else { return }
            needsReapply = isWaitingForInventory
            message = L10n.text("Changes are saved automatically.")
            if isWaitingForInventory { scheduleInventoryRetry() }
            else { scheduleVerification() }
        } catch {
            guard token == revision, canWork else { return }
            saved = previous
            draft = previous
            pendingHides.formIntersection(previous.hiddenBundles)
            try? store.save(previous)
            try? await setVisibility(previous)
            guard token == revision else { return }
            self.error = error.localizedDescription
            message = L10n.text("The change didn't take effect. Your previous settings have been restored.")
        }
    }

    private func setVisibility(_ profile: LayoutProfile) async throws {
        let apps = environment.applications()
        let processes = processKeys(apps)
        guard !isRevealed, profile.hidingEnabled, !profile.hiddenBundles.isEmpty else {
            environment.restore(); allowedProcesses = processes; return
        }
        guard nativeAvailable else {
            environment.restore()
            throw NSError(domain: "BarTidy", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("Menu bar visibility is unavailable on this system. All icons remain visible.")])
        }
        try await environment.apply(profile.allowedBundles(running: Set(apps.map(\.bundleID)), own: ownBundle))
        allowedProcesses = processes
    }

    private func processKeys(_ apps: [AccessibilityInventory.Application]) -> Set<String> {
        Set(apps.map { "\($0.bundleID):\($0.pid)" })
    }

    private func supersede() {
        revision += 1
        verificationTask?.cancel(); verificationTask = nil
        recoveryTask?.cancel(); recoveryTask = nil
        environment.cancelPending()
    }

    private func scheduleInventoryRetry() {
        let delays = timing.inventoryDelays
        let delay = delays[min(emptyReads, delays.count - 1)]
        emptyReads += 1
        scheduleRecovery(after: delay)
    }

    private func scheduleRecovery(after delay: Duration = .zero) {
        guard canWork else { return }
        recoveryTask?.cancel()
        let token = revision
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, token == revision, canWork else { return }
            recoveryTask = nil
            await recover()
        }
    }

    private func recover() async {
        guard canWork, !isBusy, !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        // Recovery and verification share the native assertion. A repair
        // supersedes an older audit, while a user edit can supersede either.
        supersede()
        let token = revision
        guard await refresh(silently: true), token == revision, canWork, !isBusy else { return }
        guard needsReapply else { return }
        do {
            try await setVisibility(saved)
            guard token == revision, canWork else { return }
            needsReapply = false
            verificationFailedRevision = nil
            scheduleVerification()
        } catch {
            guard token == revision, canWork else { return }
            needsReapply = false
            allowedProcesses = processKeys(environment.applications())
            unconfirmedBundles = saved.hiddenBundles
            self.error = error.localizedDescription
        }
    }

    private func scheduleVerification() {
        verificationTask?.cancel(); verificationTask = nil
        guard canWork, !isRevealed, saved.hidingEnabled, !saved.hiddenBundles.isEmpty else { unconfirmedBundles = []; return }
        guard verificationFailedRevision != revision else { return }
        let token = revision
        verificationTask = Task { [weak self] in
            guard let self else { return }
            await verifyVisibility(token: token)
            if token == revision { verificationTask = nil }
        }
    }

    private func verifyVisibility(token: Int) async {
        var visible: Set<String> = []
        for attempt in 0..<2 {
            var absentReadings = 0
            var readableReadings = 0
            for _ in 0..<timing.samplesPerAttempt {
                do { try await Task.sleep(for: timing.verificationInterval) } catch { return }
                guard canWork, token == revision, !isRevealed else { return }
                let apps = environment.applications()
                let snapshot = await environment.readInventory(apps)
                guard canWork, token == revision, !Task.isCancelled else { return }
                guard snapshot.isReadable else { absentReadings = 0; continue }
                readableReadings += 1
                consume(snapshot, applications: apps)
                let running = Set(apps.map(\.bundleID))
                let targets = saved.hiddenBundles.intersection(running)
                visible = targets.intersection(snapshot.items.filter { !$0.isSystem }.map { $0.identity.bundleID })
                absentReadings = visible.isEmpty ? absentReadings + 1 : 0
                if absentReadings >= 2 {
                    pendingHides.subtract(targets)
                    unconfirmedBundles.subtract(targets)
                    return
                }
            }
            guard readableReadings >= 2 else {
                isWaitingForInventory = true
                needsReapply = true
                scheduleInventoryRetry()
                return
            }
            if visible.isEmpty { needsReapply = true; scheduleInventoryRetry(); return }
            guard attempt == 0 else { break }
            do { try await setVisibility(saved) }
            catch {
                guard canWork, token == revision else { return }
                break
            }
        }
        guard canWork, token == revision else { return }
        verificationFailedRevision = token
        // Never discard older hidden preferences because of a system outage.
        // A new hide that the system demonstrably rejected is rolled back.
        let rejected = visible.intersection(pendingHides)
        var corrected = saved
        corrected.hiddenBundles.subtract(rejected)
        for bundle in corrected.appDisplayOrder where rejected.contains(bundle) { corrected.appendDisplayApp(bundle) }
        do {
            try store.save(corrected)
            saved = corrected; draft = corrected
            pendingHides.subtract(rejected)
            unconfirmedBundles = visible.subtracting(rejected)
            try await setVisibility(corrected)
            guard token == revision else { return }
            error = rejected.isEmpty ? L10n.text("Some icons could not be hidden. Your choices are saved. Please try again later.") : L10n.text("The selected icons could not be hidden. Their switches have been restored to visible. Please try again later.")
        } catch {
            guard token == revision else { return }
            self.error = error.localizedDescription
        }
        onStateChange?()
    }

    func toggleReveal() async {
        guard canWork, !isBusy else { return }
        supersede()
        let token = revision
        isRevealed.toggle()
        do { try await setVisibility(saved) }
        catch { if token == revision { self.error = error.localizedDescription } }
        guard token == revision else { return }
        await refresh(silently: true)
        if !isRevealed { scheduleVerification() }
    }

    func stop() {
        stopped = true
        supersede()
        startupTask?.cancel(); startupTask = nil
        timer?.invalidate(); timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        environment.restore()
    }
}
