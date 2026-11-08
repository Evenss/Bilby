import AppKit
@preconcurrency import ApplicationServices
import BarTidyCore
@preconcurrency import NativeBridge

/// System boundaries are injectable so recovery can be tested without changing
/// the user's permissions, locking their Mac, or hiding their real applications.
@MainActor struct AppEnvironment {
    var installation: InstallationLocation
    var isTrusted: () -> Bool
    var requestTrust: () -> Bool
    var previouslyTrusted: () -> Bool
    var rememberTrust: () -> Void
    var applications: () -> [AccessibilityInventory.Application]
    var readInventory: ([AccessibilityInventory.Application]) async -> AccessibilityInventory.Snapshot
    var apply: ([String]) async throws -> Void
    var restore: () -> Void
    var cancelPending: () -> Void
    var isActive: () -> Bool
    var isAvailable: () -> Bool
    var sessionIsUsable: () -> Bool

    static func live(controller: BTVisibilityController) -> Self {
        let appURL = Bundle.main.bundleURL
        let readOnly = (try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return Self(
            installation: InstallationLocation(appURL: appURL, homeURL: .homeDirectory, volumeIsReadOnly: readOnly),
            isTrusted: { AXIsProcessTrusted() },
            requestTrust: {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            },
            previouslyTrusted: { UserDefaults.standard.bool(forKey: "hasGrantedAccessibility") },
            rememberTrust: { UserDefaults.standard.set(true, forKey: "hasGrantedAccessibility") },
            applications: { AccessibilityInventory.applications() },
            readInventory: { apps in
                await Task.detached(priority: .utility) { AccessibilityInventory.read(apps) }.value
            },
            apply: { bundles in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    controller.applyAllowedBundles(bundles) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
            },
            restore: { controller.restore() },
            cancelPending: { controller.cancelPendingActivations() },
            isActive: { controller.active }, isAvailable: { controller.available },
            sessionIsUsable: {
                guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
                return session[kCGSessionOnConsoleKey as String] as? Bool == true &&
                    session["CGSSessionScreenIsLocked"] as? Bool != true
            }
        )
    }
}

struct RecoveryTiming {
    var verificationInterval: Duration = .milliseconds(400)
    var samplesPerAttempt = 6
    var inventoryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]
}
