import Foundation

public struct ItemIdentity: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var bundleID: String
    public var name: String
    public init(id: String, bundleID: String, name: String) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
    }
}

/// User intent is independent of temporary screen coordinates and process IDs.
public struct LayoutProfile: Codable, Equatable, Sendable {
    public var version = 2
    public var hiddenBundles: Set<String> = []
    public var order: [String] = []
    /// Bundle IDs in the app's list, independent of physical menu-bar order.
    public var appDisplayOrder: [String] = []
    public var knownItems: [ItemIdentity] = []
    public var hidingEnabled = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, hiddenBundles, order, appDisplayOrder, knownItems, hidingEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 2
        hiddenBundles = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenBundles) ?? []
        order = try values.decodeIfPresent([String].self, forKey: .order) ?? []
        appDisplayOrder = try values.decodeIfPresent([String].self, forKey: .appDisplayOrder) ?? []
        knownItems = try values.decodeIfPresent([ItemIdentity].self, forKey: .knownItems) ?? []
        hidingEnabled = try values.decodeIfPresent(Bool.self, forKey: .hidingEnabled) ?? true
    }

    public mutating func registerDisplayApps(_ bundleIDs: [String]) {
        var seen = Set<String>()
        appDisplayOrder = (appDisplayOrder + bundleIDs).filter { seen.insert($0).inserted }
    }

    public mutating func appendDisplayApp(_ bundleID: String) {
        appDisplayOrder.removeAll { $0 == bundleID }
        appDisplayOrder.append(bundleID)
    }

    public func displayedApps(_ apps: [ItemIdentity]) -> [ItemIdentity] {
        let positions = Dictionary(appDisplayOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return apps.enumerated().filter { seen.insert($0.element.bundleID).inserted }.sorted {
            let a = positions[$0.element.bundleID] ?? (appDisplayOrder.count + $0.offset)
            let b = positions[$1.element.bundleID] ?? (appDisplayOrder.count + $1.offset)
            return a < b
        }.map(\.element)
    }

    /// Refresh metadata without losing preferences for apps that are not running.
    public mutating func merge(_ discovered: [ItemIdentity]) {
        var byID = Dictionary(knownItems.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for item in discovered { byID[item.id] = item }
        var seen = Set<String>()
        order = (order + discovered.map(\.id)).filter { seen.insert($0).inserted }
        knownItems = order.compactMap { byID[$0] }
    }

    public func sorted(_ items: [ItemIdentity]) -> [ItemIdentity] {
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted {
            let a = positions[$0.element.id] ?? (order.count + $0.offset)
            let b = positions[$1.element.id] ?? (order.count + $1.offset)
            return a < b
        }.map(\.element)
    }

    public mutating func move(_ id: String, before target: String) {
        guard id != target, order.contains(id), order.contains(target) else { return }
        order.removeAll { $0 == id }
        if let index = order.firstIndex(of: target) { order.insert(id, at: index) }
    }

    public mutating func move(_ id: String, offset: Int) {
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    public func allowedBundles(running: Set<String>, own: String) -> [String] {
        Array(running.subtracting(hidingEnabled ? hiddenBundles : []).union([own])).sorted()
    }

    /// A hidden app can vanish from macOS's accessibility inventory while it is
    /// still running. Retain its known tiles so the user can show it again.
    public func retainedHiddenItems(runningBundles: Set<String>, discoveredBundles: Set<String>) -> [ItemIdentity] {
        knownItems.filter {
            hiddenBundles.contains($0.bundleID) && runningBundles.contains($0.bundleID) && !discoveredBundles.contains($0.bundleID)
        }
    }
}
