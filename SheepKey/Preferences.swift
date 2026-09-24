import Foundation

/// An app in which SheepKey rewrites the modifier keys.
struct TargetApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var isEnabled: Bool = true

    var id: String { bundleID }
}

/// How ⌘ and ⌃ are rewritten while a target app is frontmost.
enum RemapMode: String, CaseIterable, Codable {
    /// ⌘ becomes ⌃ and ⌃ becomes ⌘ (⌘ reaches Windows as the Win key), so
    /// both keys stay reachable.
    case swap
    /// ⌘ becomes ⌃; ⌃ is left alone. The Win key is unreachable, but a
    /// habit of pressing either key for a Windows shortcut keeps working.
    case commandAsControl

    var title: String {
        switch self {
        case .swap:             "Swap ⌘ and ⌃  (⌃ acts as Win)"
        case .commandAsControl: "⌘ acts as ⌃  (⌃ unchanged)"
        }
    }
}

/// UserDefaults-backed settings. Everything is read on demand so the menu
/// and the remapper never disagree about what is stored.
enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let enabledKey = "SheepKey.enabled"
    private static let modeKey = "SheepKey.mode"
    private static let targetsKey = "SheepKey.targets"

    /// Remote-desktop clients that forward ⌘ as the Win key. Windows App
    /// (Microsoft) is deliberately absent: it translates ⌘ to ⌃ itself.
    static let defaultTargets: [TargetApp] = [
        TargetApp(bundleID: "com.philandro.anydesk", name: "AnyDesk"),
        TargetApp(bundleID: "com.teamviewer.TeamViewer", name: "TeamViewer"),
        TargetApp(bundleID: "com.carriez.rustdesk", name: "RustDesk"),
    ]

    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var mode: RemapMode {
        get {
            defaults.string(forKey: modeKey).flatMap(RemapMode.init(rawValue:)) ?? .swap
        }
        set { defaults.set(newValue.rawValue, forKey: modeKey) }
    }

    static var targets: [TargetApp] {
        get {
            guard let data = defaults.data(forKey: targetsKey),
                  let list = try? JSONDecoder().decode([TargetApp].self, from: data)
            else { return defaultTargets }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: targetsKey)
            }
        }
    }
}
