import AppKit
import SwiftUI
import ApplicationServices
import OSLog

@main enum BarTidyMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var status: NSStatusItem!
    var fixtureItems: [NSStatusItem] = []
    private var panel: SettingsPanel?
    private var preparingPanel: Task<Void, Never>?
    private var hostedStatusAnchor: NSRect?
    private var panelPresentation = 0
    private var isClosingPanel = false
    private var panelFocusObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var panelKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pendingMenuBarButton: Int?
    private var brandAnimation: BrandIconAnimator?
    private let interactionLog = Logger(subsystem: "local.even.BarTidy", category: "StatusItem")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let label = Bundle.main.object(forInfoDictionaryKey: "BTFixture") as? String {
            createFixture(label)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--integration-test"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task {
                await IntegrationTests.run(output: URL(filePath: output))
                NSApp.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--diagnose"), CommandLine.arguments.count > index + 1 {
            let output = URL(filePath: CommandLine.arguments[index + 1])
            Task {
                await IntegrationTests.diagnose(output: output)
                NSApp.terminate(nil)
            }
            return
        }
        let duplicate = NSRunningApplication.runningApplications(withBundleIdentifier: model.ownBundle)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if duplicate { NSApp.terminate(nil); return }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        createStatusItem()
        createMainMenu()
        panelFocusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                     object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.panelWindowDidResignKey(window) }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isEscape = event.keyCode == 53 && modifiers.isEmpty
            let isClose = modifiers == .command && event.keyCode == 13
            guard isEscape || isClose else { return event }
            let handled = MainActor.assumeIsolated { self?.dismissPanelForKeyboard() ?? false }
            return handled ? nil : event
        }
        model.onStateChange = { [weak self] in self?.updateStatus() }
        let startupPresentation = panelPresentation
        model.start(onReady: { [weak self] in
            guard let self, self.panelPresentation == startupPresentation else { return }
            self.showPanel()
        })
    }

    private func createMainMenu() {
        let menu = NSMenu()
        let root = NSMenuItem(title: BrandIcon.name, action: nil, keyEquivalent: "")
        let application = NSMenu(title: BrandIcon.name)
        application.addItem(withTitle: L10n.text("About Bilby"), action: #selector(about), keyEquivalent: "").target = self
        application.addItem(.separator())
        application.addItem(withTitle: L10n.text("Settings…"), action: #selector(showPanel), keyEquivalent: ",").target = self
        application.addItem(.separator())
        application.addItem(withTitle: L10n.text("Hide Bilby"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = application.addItem(withTitle: L10n.text("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        application.addItem(withTitle: L10n.text("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: L10n.text("Quit Bilby"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = application
        menu.addItem(root)

        let fileRoot = NSMenuItem(title: L10n.text("File"), action: nil, keyEquivalent: "")
        let file = NSMenu(title: L10n.text("File"))
        file.addItem(withTitle: L10n.text("Close"), action: #selector(closeActiveInterface), keyEquivalent: "w").target = self
        fileRoot.submenu = file
        menu.addItem(fileRoot)
        NSApp.mainMenu = menu
    }

    private func createStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "BarTidy.Main"
        // Keep every activation on the button's regular mouse-up toggle.
        status.expandedInterfaceDelegate = nil
        if let button = status.button {
            button.image = BrandIcon.menuBarImage()
            brandAnimation = BrandIconAnimator(button: button)
            button.setAccessibilityLabel(BrandIcon.name)
            button.setAccessibilityIdentifier("BarTidy.Main")
            button.toolTip = L10n.text("Bilby: Click to open or close")
            button.target = self
            button.action = #selector(statusButtonActivated)
            button.sendAction(on: .leftMouseUp)
        }
    }

    private func updateStatus() {
        status?.button?.toolTip = L10n.text("Bilby: Click to open or close")
        if let frame = model.ownStatusItemFrame { hostedStatusAnchor = appKitRect(from: frame) }
        // Keep the live anchor for hit-testing, but position only on opening.
        // Hiding another status item must not move an already open panel.
        if let panel, panel.isVisible {
            interactionLog.debug("Panel refresh kept frame=\(NSStringFromRect(panel.frame), privacy: .public)")
        }
    }

    @objc private func statusButtonActivated() {
        interactionLog.info("Primary status button activation shown=\(self.panel?.isVisible == true, privacy: .public) event=\(NSApp.currentEvent?.type.rawValue ?? 0, privacy: .public)")
        if panel?.isVisible == true || preparingPanel != nil { closePanel() } else { showPanel() }
        brandAnimation?.play()
    }

    @objc func showPanel() {
        guard panel?.isVisible != true, preparingPanel == nil else { return }
        panelPresentation += 1
        if nativeStatusButtonScreenRect != nil {
            presentPanel()
            return
        }
        let presentation = panelPresentation
        let applications = AccessibilityInventory.applications()
        let bundle = model.ownBundle
        preparingPanel = Task { [weak self] in
            // The macOS 27 status button's proxy window can stay at (0, 0).
            // Resolve the real hosted item's geometry without touching input.
            let frame = await Task.detached(priority: .userInitiated) {
                AccessibilityInventory.scan(applications).first { $0.identity.bundleID == bundle }?.frame
            }.value
            guard let self, !Task.isCancelled, self.panelPresentation == presentation else { return }
            self.preparingPanel = nil
            if let frame { self.hostedStatusAnchor = self.appKitRect(from: frame) }
            self.presentPanel()
        }
        startOutsideClickMonitoring()
    }

    private func presentPanel() {
        guard let anchor = statusButtonScreenRect,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) else {
            stopOutsideClickMonitoring()
            return
        }
        if panel == nil { panel = SettingsPanel(model: model, dismiss: { [weak self] in self?.closePanel() }) }
        guard let panel else { return }
        panel.position(below: anchor, on: screen)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.isSettingsVisible = panel.isVisible
        if panel.isVisible { startOutsideClickMonitoring() }
        interactionLog.info("Panel presented visible=\(panel.isVisible, privacy: .public) key=\(panel.isKeyWindow, privacy: .public) active=\(NSApp.isActive, privacy: .public) x=\(panel.frame.minX, privacy: .public) y=\(panel.frame.minY, privacy: .public) anchor=\(NSStringFromRect(anchor), privacy: .public)")
        Task { await model.refresh(silently: true) }
    }

    private func closePanel() {
        guard !isClosingPanel, preparingPanel != nil || panel?.isVisible == true else { return }
        isClosingPanel = true
        defer { isClosingPanel = false }
        panelPresentation += 1
        preparingPanel?.cancel()
        preparingPanel = nil
        model.isSettingsVisible = false
        stopOutsideClickMonitoring()
        // A persistent panel has one synchronous visibility operation and no
        // popover teardown, expanded session, or delayed ordering callback.
        panel?.orderOut(nil)
        interactionLog.info("Panel closed visible=\(self.panel?.isVisible == true, privacy: .public)")
    }

    private func dismissPanelForKeyboard() -> Bool {
        guard let panel, panel.isVisible, NSApp.keyWindow === panel else { return false }
        interactionLog.info("Panel keyboard close")
        closePanel()
        return true
    }

    private var statusButtonScreenRect: NSRect? {
        nativeStatusButtonScreenRect ?? hostedStatusAnchor
    }

    private var nativeStatusButtonScreenRect: NSRect? {
        guard let button = status.button, let window = button.window else { return nil }
        // The supported macOS 27.2 host allocates 38pt for this 22pt button;
        // include its 8pt hit padding, not just the visible button content.
        let frame = window.convertToScreen(button.frame)
        guard isInMenuBar(NSPoint(x: frame.midX, y: frame.midY)) else { return nil }
        return frame.insetBy(dx: -8, dy: -8)
    }

    private func appKitRect(from axFrame: CGRect) -> NSRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: axFrame.minX, y: top - axFrame.maxY, width: axFrame.width, height: axFrame.height)
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let presentation = panelPresentation
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .leftMouseUp, .rightMouseUp, .otherMouseUp]
        // These callbacks only dismiss our own UI. Global monitoring receives
        // copies and cannot consume, alter, or redirect another app's click.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let location = event.locationInWindow
            let eventWindow = event.window
            let type = event.type
            let button = event.buttonNumber
            MainActor.assumeIsolated {
                guard let self, self.panelPresentation == presentation else { return }
                self.handleOutsideMouseEvent(at: eventWindow?.convertPoint(toScreen: location) ?? location,
                                             type: type, button: button)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let location = event.locationInWindow
            let eventWindow = event.window
            let type = event.type
            let button = event.buttonNumber
            MainActor.assumeIsolated {
                guard let self, self.panelPresentation == presentation else { return }
                self.handleOutsideMouseEvent(at: eventWindow?.convertPoint(toScreen: location) ?? location,
                                             type: type, button: button)
            }
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        pendingMenuBarButton = nil
    }

    private func handleOutsideMouseEvent(at pointer: NSPoint, type: NSEvent.EventType, button: Int) {
        guard preparingPanel != nil || panel?.isVisible == true else { return }
        if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(type) {
            guard pendingMenuBarButton == button else { return }
            interactionLog.info("Menu-bar mouse release dismissed panel")
            closePanel()
            return
        }
        // The anchor must reach the regular mouse-up toggle without an early
        // dismissal. All other menu-bar items are outside, even if they don't
        // activate an application or take keyboard focus.
        if statusButtonScreenRect?.contains(pointer) == true { return }
        if let window = panel, window.isVisible {
            if window.frame.contains(pointer) { return }
            if window.childWindows?.contains(where: { $0.isVisible && $0.frame.contains(pointer) }) == true { return }
        }
        // Other status items present on release. Closing on mouse-down leaves
        // a desktop frame between the outgoing panel and the incoming menu.
        if isInMenuBar(pointer) {
            pendingMenuBarButton = button
            return
        }
        interactionLog.info("Outside click dismissed panel")
        closePanel()
    }

    private func isInMenuBar(_ pointer: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else { return false }
        let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        return pointer.y >= screen.frame.maxY - height
    }

    func applicationDidResignActive(_ notification: Notification) {
        closePanel()
    }

    private func panelWindowDidResignKey(_ window: NSWindow) {
        guard panel?.isVisible == true, window === panel,
              window.attachedSheet == nil else { return }
        // Only our own anchor is exempt; another status item's menu must
        // dismiss this panel, including menus that leave the active app alone.
        if statusButtonScreenRect?.contains(NSEvent.mouseLocation) == true { return }
        closePanel()
    }

    @objc private func closeActiveInterface() {
        if let keyWindow = NSApp.keyWindow, keyWindow !== panel {
            keyWindow.performClose(nil)
        } else {
            closePanel()
        }
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: BrandIcon.name, .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.2",
            .credits: NSAttributedString(string: L10n.text("Native macOS 27.2 menu bar manager.\nVisibility bridge based on Hidden Bar (MIT)."))
        ])
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        brandAnimation?.stop()
        preparingPanel?.cancel()
        if let panelFocusObserver { NotificationCenter.default.removeObserver(panelFocusObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let panelKeyMonitor { NSEvent.removeMonitor(panelKeyMonitor) }
        stopOutsideClickMonitoring()
        model.stop()
        if let status { NSStatusBar.system.removeStatusItem(status) }
    }

    private func createFixture(_ label: String) {
        for number in 1...(label == "A" ? 2 : 1) {
            let item = NSStatusBar.system.statusItem(withLength: 34)
            item.autosaveName = "BTFixture.\(label).\(number)"
            let menu = NSMenu()
            menu.addItem(withTitle: L10n.format("Test icon %@", "\(label)\(number)"), action: nil, keyEquivalent: "")
            menu.addItem(withTitle: L10n.text("Quit test app"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            item.menu = menu
            item.behavior = [.removalAllowed]
            item.button?.title = "\(label)\(number)"
            item.button?.setAccessibilityIdentifier("BTFixture.\(label).\(number)")
            item.button?.toolTip = L10n.format("BarTidy test icon %@", "\(label)\(number)")
            item.isVisible = true
            fixtureItems.append(item)
        }
    }
}
