import AppKit
import SwiftUI

/// A menu-bar surface that takes keyboard focus without activating the app.
@MainActor final class SettingsPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(model: AppModel, dismiss: @escaping () -> Void) {
        super.init(contentRect: NSRect(origin: .zero, size: StatusPanelView.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        onDismiss = dismiss
        title = BrandIcon.name
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .vibrantDark)

        let controller = NSHostingController(rootView: StatusPanelView(
            model: model, close: dismiss, quit: { NSApp.terminate(nil) }
        ))
        controller.sizingOptions = []
        controller.view.setFrameSize(StatusPanelView.size)
        controller.view.wantsLayer = true
        controller.view.layer?.cornerRadius = 12
        controller.view.layer?.masksToBounds = true
        contentViewController = controller
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func performClose(_ sender: Any?) { onDismiss?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            onDismiss?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func position(below anchor: NSRect, on screen: NSScreen) {
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = StatusPanelView.size
        let x = min(max(anchor.midX - size.width / 2, available.minX), available.maxX - size.width)
        let top = min(anchor.minY - 6, screen.visibleFrame.maxY - 6)
        let y = min(max(top - size.height, available.minY), available.maxY - size.height)
        let target = NSRect(origin: NSPoint(x: x, y: y), size: size)
        guard frame != target else { return }
        setFrame(target, display: false)
        contentView?.layoutSubtreeIfNeeded()
        invalidateShadow()
    }
}
