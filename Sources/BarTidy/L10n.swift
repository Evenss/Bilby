import Foundation

enum L10n {
    /// The assembled app keeps its localizations in the main bundle so AppKit
    /// and the Objective-C bridge use the same macOS language selection.
    /// SwiftPM's resource bundle serves command-line runs and isolated tests.
    static let bundle: Bundle = {
        if Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en") != nil {
            return .main
        }
        return .module
    }()

    static func text(_ key: String, bundle: Bundle = L10n.bundle) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg..., bundle: Bundle = L10n.bundle) -> String {
        String(format: text(key, bundle: bundle), locale: Locale.current, arguments: arguments)
    }
}
