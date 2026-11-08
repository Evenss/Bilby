import AppKit
@preconcurrency import ApplicationServices
import BarTidyCore
import Observation
@preconcurrency import NativeBridge

@MainActor @Observable final class AppModel {
    let ownBundle = Bundle.main.bundleIdentifier ?? "local.even.BarTidy"
    private(set) var items: [MenuBarItem] = []
    private(set) var ownStatusItemFrame: CGRect?
    var draft = LayoutProfile()
    private(set) var saved = LayoutProfile()
    var hasPermission = AXIsProcessTrusted()
    let visibility = BTVisibilityController()
    var isBusy = false
    var isRevealed = false
    var isSettingsVisible = false
    var message = "正在读取状态栏…"
    var error: String?
    var onStateChange: (() -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var allowedRunningBundles: Set<String> = []
    private var isRefreshing = false
    private var awaitingPosition: Set<String> = []
    private let store: ProfileStore

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        do { saved = try store.load(); draft = try store.loadDraft() ?? saved }
        catch { self.error = "无法读取已保存的设置：\(error.localizedDescription)" }
    }

    var hasChanges: Bool {
        draft.hiddenBundles != saved.hiddenBundles || draft.order != saved.order ||
            draft.appDisplayOrder != saved.appDisplayOrder || draft.hidingEnabled != saved.hidingEnabled
    }
    var nativeAvailable: Bool { visibility.available }
    var hiddenCount: Int { managedApps.filter { draft.hiddenBundles.contains($0.identity.bundleID) }.count }
    var managedApps: [MenuBarItem] {
        var seen = Set<String>()
        // Inventory order comes from macOS. Legacy profile.order is storage
        // compatibility only and must never determine the displayed order.
        return items.filter { seen.insert($0.identity.bundleID).inserted }
    }
    var statusBarApps: [MenuBarItem] {
        managedApps.filter {
            $0.frame.width > 0 && $0.frame.height > 0 &&
                (isRevealed || !draft.hiddenBundles.contains($0.identity.bundleID))
        }.sorted { $0.frame.midX < $1.frame.midX }
    }
    var otherApps: [MenuBarItem] {
        let positioned = Set(statusBarApps.map { $0.identity.bundleID })
        return managedApps.filter { !positioned.contains($0.identity.bundleID) }.sorted {
            let comparison = $0.identity.name.localizedStandardCompare($1.identity.name)
            return comparison == .orderedSame ? $0.identity.bundleID < $1.identity.bundleID : comparison == .orderedAscending
        }
    }

    func start(onReady: (() -> Void)? = nil) {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                if granted != self.hasPermission {
                    self.hasPermission = granted
                    if granted { await self.refresh(); await self.applyVisibility(self.saved) }
                    else { self.visibility.restore(); self.onStateChange?() }
                } else if granted, !self.isBusy {
                    if !self.isRevealed, !self.saved.hiddenBundles.isEmpty {
                        let running = Set(AccessibilityInventory.applications().map(\.bundleID))
                        if running != self.allowedRunningBundles { await self.applyVisibility(self.saved) }
                    }
                    if self.isSettingsVisible { await self.refresh(silently: true) }
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard let self, !self.isBusy else { return }
                    await self.refresh()
                    await self.applyVisibility(self.saved)
                }
            })
        }
        Task {
            await refresh()
            // Commit a draft from an older version and retain discovered apps.
            // All subsequent edits are saved by their visibility switch.
            if hasPermission { await apply() }
            await refresh(silently: true)
            onReady?()
        }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasPermission = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func refresh(silently: Bool = false) async {
        hasPermission = AXIsProcessTrusted()
        guard hasPermission, !isBusy, !isRefreshing else {
            if !hasPermission { message = "开启辅助功能后，即可选择显示哪些应用。" }
            return
        }
        isRefreshing = true
        if !silently { isBusy = true }
        defer {
            isRefreshing = false
            if !silently { isBusy = false }
        }
        let applications = AccessibilityInventory.applications()
        let scanned = await Task.detached(priority: .userInitiated) { AccessibilityInventory.scan(applications) }.value
        ownStatusItemFrame = scanned.first { $0.identity.bundleID == ownBundle }?.frame
        let discovered = scanned.filter { $0.identity.bundleID != ownBundle && !$0.isSystem }
        // A background read must not overwrite a visibility change in flight.
        guard !silently || !isBusy else { return }
        let runningByBundle = Dictionary(applications.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let discoveredBundles = Set(discovered.map { $0.identity.bundleID })
        awaitingPosition.subtract(discoveredBundles)
        awaitingPosition.formIntersection(runningByBundle.keys)
        var retention = draft
        retention.hiddenBundles.formUnion(saved.hiddenBundles)
        // A just-shown item may need a compositor update before AX exposes its
        // position. Retain its switch without changing its displayed group.
        retention.hiddenBundles.formUnion(awaitingPosition)
        let retained = retention.retainedHiddenItems(runningBundles: Set(runningByBundle.keys),
                                                     discoveredBundles: discoveredBundles)
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
        // Seed the existing layout once; later scans can only append new apps.
        // Physical movement must never reorder a list the user has interacted with.
        let displayBundles = (statusBarApps + otherApps).map { $0.identity.bundleID }
        saved.registerDisplayApps(displayBundles)
        draft.registerDisplayApps(displayBundles)
        if !silently { message = "已读取 \(managedApps.count) 个应用，修改会自动保存。" }
        onStateChange?()
    }

    func setHidden(_ bundleID: String, hidden: Bool) async {
        guard !isBusy, managedApps.contains(where: { $0.identity.bundleID == bundleID && !$0.isSystem }) else { return }
        guard draft.hiddenBundles.contains(bundleID) != hidden || isRevealed else { return }
        if hidden { draft.hiddenBundles.insert(bundleID); awaitingPosition.remove(bundleID) }
        else { draft.hiddenBundles.remove(bundleID); awaitingPosition.insert(bundleID) }
        draft.appendDisplayApp(bundleID)
        // Only visibility is sent to macOS; the app's list order is saved
        // separately. End any temporary reveal so hiding takes effect now.
        await apply()
        // The list no longer needs fresh screen coordinates after a switch.
        // The normal background refresh updates inventory without delaying clicks.
    }

    func apply() async {
        guard !isBusy else { return }
        guard hasPermission else { requestPermission(); return }
        isBusy = true
        error = nil
        message = "正在更新显示设置…"
        onStateChange?()
        let candidate = draft
        let wasRevealed = isRevealed
        isRevealed = false
        defer { isBusy = false; onStateChange?() }
        let visibilityChanged = candidate.hiddenBundles != saved.hiddenBundles || candidate.hidingEnabled != saved.hidingEnabled
        do {
            // Only visibility is sent to macOS. No item positions are changed.
            if visibilityChanged || wasRevealed || (!candidate.hiddenBundles.isEmpty && !visibility.active) {
                try await setVisibility(candidate)
            }
            try store.save(candidate)
            saved = candidate
            draft = candidate
            try? store.clearDraft()
            message = "设置已自动保存。"
        } catch {
            // Keep switches aligned with the last successful settings.
            draft = saved
            try? store.clearDraft()
            try? await setVisibility(saved)
            self.error = error.localizedDescription
            message = "修改未生效，已恢复之前的设置。"
        }
    }

    private func setVisibility(_ profile: LayoutProfile) async throws {
        guard !isRevealed, !profile.hiddenBundles.isEmpty else { visibility.restore(); return }
        guard nativeAvailable else { throw NSError(domain: "BarTidy", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前系统的隐藏接口不可用，所有图标保持显示。"] ) }
        let running = Set(AccessibilityInventory.applications().map(\.bundleID))
        let allowed = profile.allowedBundles(running: running, own: ownBundle)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            visibility.applyAllowedBundles(allowed) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        allowedRunningBundles = running
    }

    private func applyVisibility(_ profile: LayoutProfile) async {
        guard hasPermission, !isBusy else { return }
        isBusy = true
        defer { isBusy = false; onStateChange?() }
        do { try await setVisibility(profile) }
        catch { self.error = error.localizedDescription }
        onStateChange?()
    }

    func toggleReveal() async {
        guard !isBusy else { return }
        isRevealed.toggle()
        await applyVisibility(saved)
        await refresh(silently: true)
        message = isRevealed ? "正在临时显示全部图标。点击“恢复隐藏”或修改开关后结束。" : "已恢复保存的显示设置。"
    }

    func stop() {
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        visibility.restore()
    }
}
