import AppKit

/// Updates only the status item's template image; panel actions never wait.
@MainActor final class BrandIconAnimator {
    private weak var button: NSStatusBarButton?
    private let restingImage = BrandIcon.menuBarImage()
    private let frames = (0...31).map { BrandIcon.menuBarImage(pose: BrandIcon.earPose(at: Double($0) / 31)) }
    private var animation: Task<Void, Never>?

    init(button: NSStatusBarButton) { self.button = button }

    func play() {
        // A second click still toggles the panel immediately, while one short
        // wiggle finishes instead of competing with another animation task.
        guard animation == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let started = ContinuousClock.now
        animation = Task { [weak self] in
            guard let self else { return }
            for index in self.frames.indices {
                let deadline = started.advanced(by: .seconds(BrandIcon.wiggleDuration * Double(index) / 31))
                do { try await Task.sleep(until: deadline, clock: .continuous) }
                catch { return }
                guard !Task.isCancelled else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { break }
                self.button?.image = self.frames[index]
            }
            self.button?.image = self.restingImage
            self.animation = nil
        }
    }

    func stop() {
        animation?.cancel()
        animation = nil
        button?.image = restingImage
    }
}
