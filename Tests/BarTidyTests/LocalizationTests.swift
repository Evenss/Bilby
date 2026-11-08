import Foundation
import Testing
@testable import BarTidy

private enum TranslationFixtures {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func languageBundle(_ language: String) throws -> Bundle {
        let resources = try #require(L10n.bundle.resourceURL)
        return try #require(Bundle(url: resources.appending(path: "\(language).lproj")))
    }

    static func table(_ language: String) throws -> [String: String] {
        let bundle = try languageBundle(language)
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    static func matches(_ pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: text) else { return nil }
            return String(text[range])
        }
    }
}

@Test func englishAndChineseTablesAreCompleteAndPreserveFormatArguments() throws {
    let english = try TranslationFixtures.table("en")
    let chinese = try TranslationFixtures.table("zh-Hans")
    #expect(!english.isEmpty && Set(english.keys) == Set(chinese.keys))
    for (key, value) in english {
        let translated = try #require(chinese[key])
        #expect(value == key)
        #expect(!translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let pattern = #"%(?:\d+\$)?(?:@|ld)"#
        #expect(try TranslationFixtures.matches(pattern, in: key).sorted() == TranslationFixtures.matches(pattern, in: translated).sorted())
    }
}

@Test func appOwnedTextAndBridgeErrorsHaveTranslations() throws {
    let table = try TranslationFixtures.table("en")
    let sources = TranslationFixtures.root.appending(path: "Sources")
    let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var keys = Set<String>()
    for case let url as URL in enumerator where ["swift", "m"].contains(url.pathExtension) {
        let source = try String(contentsOf: url, encoding: .utf8)
        // English literals are the keys, including format strings and AppKit
        // strings outside SwiftUI. Prevent a new call from silently falling back.
        let swift = try TranslationFixtures.matches(#"L10n\.(?:text|format)\("((?:[^"\\]|\\.)*)""#, in: source)
        let bridge = try TranslationFixtures.matches(#"BTError\(@"((?:[^"\\]|\\.)*)""#, in: source)
        for key in swift + bridge {
            keys.insert(key.replacingOccurrences(of: #"\n"#, with: "\n"))
        }
    }
    #expect(keys.count > 40)
    for key in keys { #expect(table[key] != nil, "Missing translation: \(key)") }
    // The Objective-C exception fallback is selected dynamically.
    #expect(table["The menu bar request failed."] != nil)
}

@Test func localizedLabelsKeepAppNamesAndCountsIntact() throws {
    let english = try TranslationFixtures.languageBundle("en")
    let chinese = try TranslationFixtures.languageBundle("zh-Hans")
    #expect(L10n.text("Visible", bundle: english) == "Visible")
    #expect(L10n.text("Visible", bundle: chinese) == "显示中")
    #expect(L10n.text("Quit", bundle: english) == "Quit")
    #expect(L10n.text("Quit", bundle: chinese) == "退出")
    let name = "微信 100% 🐇"
    #expect(L10n.format("Show %@ in the menu bar", name, bundle: english) == "Show \(name) in the menu bar")
    #expect(L10n.format("Show %@ in the menu bar", name, bundle: chinese) == "\(name)，在状态栏显示")
    #expect(L10n.format("Apps found: %ld. Changes are saved automatically.", 7, bundle: chinese) == "已读取 7 个应用，修改会自动保存。")
    #expect(L10n.text("Unknown fallback text", bundle: chinese) == "Unknown fallback text")
}

@Test func macOSResolvesRegionalLanguagePreferences() {
    let available = ["en", "zh-Hans"]
    #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["zh-Hans-CN"]).first == "zh-Hans")
    #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["zh-CN"]).first == "zh-Hans")
    #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["en-GB"]).first == "en")
    #expect(Bundle.preferredLocalizations(from: available, forPreferences: ["ja", "en"]).first == "en")
}
