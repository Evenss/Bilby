import SwiftUI

/// Animation frames stay inside this image view, without updating the form.
struct PanelBrandIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelBrandImageView {
        let view = PanelBrandImageView()
        view.image = BrandIcon.menuBarImage()
        view.imageScaling = .scaleNone
        view.contentTintColor = .labelColor
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: PanelBrandImageView, context: Context) {}

    static func dismantleNSView(_ view: PanelBrandImageView, coordinator: ()) {
        view.stopObserving()
    }
}

@MainActor final class PanelBrandImageView: NSImageView {
    private lazy var animator = BrandIconAnimator(imageView: self)
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        let center = NotificationCenter.default
        // Observe the existing panel's key events. SwiftUI can coalesce hidden
        // view updates, so a presentation Boolean can miss a quick reopening.
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.animator.play() }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.animator.stop() }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.animator.stop() }
        })
        if window.isVisible, window.isKeyWindow { animator.play() }
    }

    func stopObserving() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        animator.stop()
    }
}
