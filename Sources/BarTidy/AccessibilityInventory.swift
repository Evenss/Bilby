import AppKit
import ApplicationServices
import BarTidyCore

struct MenuBarItem: Identifiable, Sendable {
    let identity: ItemIdentity
    let pid: pid_t
    var frame: CGRect
    let appURL: URL?
    let isSystem: Bool
    var id: String { identity.id }
}

enum AXReader {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    static func string(_ element: AXUIElement, _ key: String) -> String? {
        guard let text = value(element, key) as? String, !text.isEmpty else { return nil }
        return text
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute),
              let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// macOS 27 wraps system items in AXGroups. Stop at menu bar items so an
    /// application's actual menu contents never become inventory entries.
    static func statusChildren(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 4 else { return [] }
        return children(element).flatMap { child in
            if string(child, kAXRoleAttribute) == kAXMenuBarItemRole { return [child] }
            if string(child, kAXRoleAttribute) == kAXGroupRole { return statusChildren(child, depth: depth + 1) }
            return []
        }
    }
}

enum AccessibilityInventory {
    struct Snapshot: Sendable {
        var items: [MenuBarItem]
        var isReadable: Bool
    }

    struct Application: Sendable {
        let pid: pid_t
        let bundleID: String
        let name: String
        let url: URL?
    }

    @MainActor static func applications() -> [Application] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundle = app.bundleIdentifier else { return nil }
            return Application(pid: app.processIdentifier, bundleID: bundle,
                               name: app.localizedName ?? bundle, url: app.bundleURL)
        }
    }

    static func scan(_ apps: [Application]) -> [MenuBarItem] {
        if let agent = apps.first(where: { $0.bundleID == "com.apple.MenuBarAgent" }) {
            let hosted = hostedItems(agent: agent, apps: apps)
            if !hosted.isEmpty { return hosted }
        }
        var items: [MenuBarItem] = []
        for app in apps {
            let root = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root, 0.12)
            guard let raw = AXReader.value(root, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let elements = AXReader.statusChildren(raw as! AXUIElement)
            var occurrences: [String: Int] = [:]
            for element in elements {
                guard let frame = AXReader.frame(element), frame.width > 0, frame.height > 0 else { continue }
                let identifier = AXReader.string(element, kAXIdentifierAttribute)
                // Titles often contain live counts, song names or network rates.
                // A structural ordinal is more durable when no identifier exists.
                let token = identifier ?? "status"
                let ordinal = occurrences[token, default: 0]
                occurrences[token] = ordinal + 1
                let isSystem = app.bundleID.hasPrefix("com.apple.")
                let description = AXReader.string(element, kAXDescriptionAttribute)
                let systemName = systemNames[identifier ?? ""] ?? description ?? app.name
                let name = isSystem ? systemName : app.name + (elements.count > 1 ? " · \(ordinal + 1)" : "")
                let id = "\(app.bundleID)/\(token)/\(ordinal)"
                items.append(MenuBarItem(identity: ItemIdentity(id: id, bundleID: app.bundleID, name: name),
                                         pid: app.pid, frame: frame, appURL: app.url, isSystem: isSystem))
            }
        }
        return sortByPosition(items)
    }

    static func sortByPosition(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted {
            // Overflow scenes can report one shared rectangle for several
            // items. AX child enumeration then has no physical order; use a
            // stable identity rather than let each refresh reshuffle ties.
            $0.frame.midX == $1.frame.midX ? $0.id < $1.id : $0.frame.midX < $1.frame.midX
        }
    }

    /// A missing menu-bar scene is not evidence that its icons disappeared.
    /// Only the hosted scene is authoritative on the supported macOS version;
    /// per-app fallback inventories can still include an already hidden icon.
    static func read(_ apps: [Application]) -> Snapshot {
        guard let agent = apps.first(where: { $0.bundleID == "com.apple.MenuBarAgent" }) else {
            return Snapshot(items: [], isReadable: false)
        }
        let items = hostedItems(agent: agent, apps: apps)
        return Snapshot(items: items, isReadable: items.contains { $0.isSystem || $0.identity.bundleID == "local.even.BarTidy" })
    }

    /// On macOS 27 MenuBarAgent owns the status-item scenes, including overflow
    /// items whose original app no longer exposes AXExtrasMenuBar. Read only its
    /// top-level scene groups, and identify each remote child by its actual PID.
    /// Never descend into the remote application's menus or document windows.
    private static func hostedItems(agent: Application, apps: [Application]) -> [MenuBarItem] {
        let root = AXUIElementCreateApplication(agent.pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        let windows = AXReader.value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let byPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var best: [(app: Application, group: AXUIElement, child: AXUIElement, frame: CGRect)] = []
        var bestScore = -1
        for window in windows {
            guard let frame = AXReader.frame(window), frame.height <= 60,
                  AXReader.string(window, kAXIdentifierAttribute) != "MenuBarRevealShield" else { continue }
            var entries: [(app: Application, group: AXUIElement, child: AXUIElement, frame: CGRect)] = []
            var score = 0
            for group in AXReader.children(window) {
                guard AXReader.string(group, kAXRoleAttribute) == kAXGroupRole,
                      let groupFrame = AXReader.frame(group), groupFrame.width > 0 else { continue }
                for child in AXReader.children(group) {
                    var pid: pid_t = 0
                    AXUIElementGetPid(child, &pid)
                    if pid != agent.pid, let app = byPID[pid] {
                        entries.append((app, group, child, groupFrame))
                        if AXReader.string(child, kAXRoleAttribute) == kAXButtonRole { score += 10 }
                        else { score += 1 }
                        break
                    }
                    let systemItems = AXReader.string(child, kAXRoleAttribute) == kAXMenuBarItemRole ? [child] : AXReader.statusChildren(group)
                    if let system = systemItems.first {
                        entries.append((agent, group, system, groupFrame))
                        score += 1
                        break
                    }
                }
            }
            if score > bestScore { best = entries; bestScore = score }
        }
        var occurrences: [String: Int] = [:]
        let ordered = best.sorted { $0.frame.midX < $1.frame.midX }
        var result: [MenuBarItem] = []
        for entry in ordered {
            let identifier = AXReader.string(entry.child, kAXIdentifierAttribute)
            let token = identifier ?? "status"
            let base = "\(entry.app.bundleID)/\(token)"
            let ordinal = occurrences[base, default: 0]
            occurrences[base] = ordinal + 1
            let system = entry.app.bundleID.hasPrefix("com.apple.")
            let name = system ? (systemNames[identifier ?? ""] ?? AXReader.string(entry.child, kAXDescriptionAttribute) ?? entry.app.name) : entry.app.name
            result.append(MenuBarItem(identity: ItemIdentity(id: "\(base)/\(ordinal)", bundleID: entry.app.bundleID, name: name),
                                      pid: entry.app.pid, frame: entry.frame, appURL: entry.app.url, isSystem: system))
        }
        return sortByPosition(result)
    }

    static let systemNames = [
        "com.apple.menuextra.battery": L10n.text("Battery"), "com.apple.menuextra.wifi": "Wi-Fi",
        "com.apple.menuextra.controlcenter": L10n.text("Control Center"), "com.apple.menuextra.clock": L10n.text("Clock"),
        "com.apple.menuextra.bluetooth": L10n.text("Bluetooth"), "com.apple.menuextra.volume": L10n.text("Sound"),
        "com.apple.menuextra.focusmode": L10n.text("Focus"), "com.apple.menuextra.audiovideo": L10n.text("Audio and video controls")
    ]
}
