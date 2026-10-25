import InkKit
import Foundation

enum Section: String, CaseIterable {
    /// Stays in the menu bar.
    case shown
    /// Lives in the ink bar.
    case hidden
    /// Lives in the ink bar too, but only appears there when you ask for everything.
    case alwaysHidden

    func title(chinese: Bool) -> String {
        switch self {
        case .shown: return chinese ? "常显" : "Shown"
        case .hidden: return chinese ? "隐藏" : "Hidden"
        case .alwaysHidden: return chinese ? "永远隐藏" : "Always hidden"
        }
    }
}

enum PanelAppearance: String, CaseIterable {
    case system, light, dark
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    var theme: ThemeID {
        get { value("theme", ThemeID.ink) }
        set { defaults.set(newValue.rawValue, forKey: "theme") }
    }

    var appearance: PanelAppearance {
        get { value("appearance", PanelAppearance.system) }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }

    var texture: Double {
        get { defaults.object(forKey: "texture") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "texture") }
    }

    /// Opacity of the ink bar's paper background; below 1 the desktop shows through it.
    var barOpacity: Double {
        get { defaults.object(forKey: "barOpacity") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "barOpacity") }
    }

    /// Entry id → section. Entries missing here are shown.
    var sections: [String: Section] {
        get {
            (defaults.dictionary(forKey: "sections") as? [String: String] ?? [:]).compactMapValues(Section.init(rawValue:))
        }
        set { defaults.set(newValue.mapValues(\.rawValue), forKey: "sections") }
    }

    func section(_ id: String) -> Section { sections[id] ?? .shown }

    func setSection(_ section: Section, for id: String) {
        var all = sections
        all[id] = section == .shown ? nil : section
        sections = all
    }

    /// Names of entries seen before, so the settings list can show apps that aren't running.
    /// pid-keyed entries can never match a later session, so they don't persist.
    var knownNames: [String: String] {
        get { defaults.dictionary(forKey: "knownNames") as? [String: String] ?? [:] }
        set { defaults.set(newValue.filter { !$0.key.hasPrefix("app:pid.") }, forKey: "knownNames") }
    }

    var showOnHover: Bool {
        get { defaults.bool(forKey: "showOnHover") }
        set { defaults.set(newValue, forKey: "showOnHover") }
    }

    /// Moves shown items into the ink bar while they don't fit, so the system never needs its » button.
    var autoOverflow: Bool {
        get { defaults.object(forKey: "autoOverflow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoOverflow") }
    }

    var triggers: [Trigger] {
        get { decode("triggers") ?? [] }
        set { encode(newValue, "triggers") }
    }

    /// Profile name → saved sections.
    var profiles: [String: [String: String]] {
        get { defaults.dictionary(forKey: "profiles") as? [String: [String: String]] ?? [:] }
        set { defaults.set(newValue, forKey: "profiles") }
    }

    var activeProfile: String? {
        get { defaults.string(forKey: "activeProfile") }
        set { defaults.set(newValue, forKey: "activeProfile") }
    }

    func saveProfile(_ name: String) {
        var all = profiles
        all[name] = sections.mapValues(\.rawValue)
        profiles = all
        activeProfile = name
    }

    func applyProfile(_ name: String) {
        guard let saved = profiles[name] else { return }
        sections = saved.compactMapValues(Section.init(rawValue:))
        activeProfile = name
    }

    var barShortcut: Shortcut {
        get { decode("barShortcut") ?? .defaultBar }
        set { encode(newValue, "barShortcut") }
    }

    var searchShortcut: Shortcut {
        get { decode("searchShortcut") ?? .defaultSearch }
        set { encode(newValue, "searchShortcut") }
    }

    var style: MenuBarStyle {
        get { decode("menuBarStyle") ?? MenuBarStyle() }
        set { encode(newValue, "menuBarStyle") }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// Draws captured icons in the theme's ink instead of their own colors.
    var inkIcons: Bool {
        get { defaults.object(forKey: "inkIcons") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "inkIcons") }
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("InkBarSettingsChanged")
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags.
    var modifiers: UInt32

    static let defaultBar = Shortcut(keyCode: 11, modifiers: 0x0900)     // ⌥⌘B
    static let defaultSearch = Shortcut(keyCode: 3, modifiers: 0x0900)   // ⌥⌘F
}

struct MenuBarStyle: Codable, Equatable {
    enum Fill: String, Codable, CaseIterable { case none, tint, paper }
    var fill = Fill.none
    /// sRGB hex.
    var tint: UInt32 = 0xB8322A
    /// Fills sit over the items, so stronger fills dim them.
    var strength = 0.15
    var brushLine = false
    var shadow = false

    var isPlain: Bool { fill == .none && !brushLine && !shadow }
}

/// Space around status items. AppKit reads these when an app starts, so a change reaches each
/// app the next time it opens, and every app after logging out and back in.
enum ItemSpacing {
    private static let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]

    static var current: Int? {
        CFPreferencesCopyValue(keys[0] as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }

    /// nil restores the system default.
    static func set(_ value: Int?) {
        for key in keys {
            CFPreferencesSetValue(key as CFString, value.map { $0 as CFNumber }, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
