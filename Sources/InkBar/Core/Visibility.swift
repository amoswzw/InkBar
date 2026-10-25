import InkKit
import AppKit
import CMenuBar

/// Decides which entries are concealed and keeps the system allowlist in step.
final class VisibilityController {
    private let restriction = IBVisibilityRestriction()
    private var applied: (system: [Int], bundles: [String])?
    private var reveals: [String: Int] = [:]

    /// Entries moved out of the menu bar because they didn't fit, oldest first.
    private(set) var overflowed: [String] = []
    var paused = false { didSet { update() } }
    private(set) var lastError: String?
    var onChange: (() -> Void)?

    /// While anything is concealed, macOS also hides apps that aren't notarized.
    var isRestricting: Bool { applied != nil }

    static var isSupported: Bool { IBVisibilityRestriction.isAvailable() }

    /// Every installed app is on the list from the start, so launching one doesn't change the
    /// list, and each change makes the menu bar rebuild all of its items.
    private lazy var installed: Set<String> = Self.installedBundleIDs()

    init() {
        // An app that isn't installed, run from a disk image say, is missing from the list and would start out hidden.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                  !self.installed.contains(bundle) else { return }
            self.update()
        }
    }

    private static func installedBundleIDs() -> Set<String> {
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       "/System/Library/CoreServices", NSHomeDirectory() + "/Applications"]
        var ids = Set<String>()
        for folder in folders {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                if let id = Bundle(path: folder + "/" + name)?.bundleIdentifier { ids.insert(id) }
            }
        }
        return ids
    }

    func isRevealed(_ id: String) -> Bool { reveals[id] != nil }

    func isConcealed(_ id: String) -> Bool {
        guard !paused, reveals[id] == nil else { return false }
        return Settings.shared.section(id) != .shown || overflowed.contains(id)
    }

    /// Shows an entry in the menu bar until the returned closure is called.
    func reveal(_ id: String) -> () -> Void {
        reveals[id, default: 0] += 1
        update()
        var released = false
        return { [weak self] in
            guard let self, !released else { return }
            released = true
            self.reveals[id]! -= 1
            if self.reveals[id] == 0 { self.reveals[id] = nil }
            self.update()
        }
    }

    /// Every change makes the menu bar rebuild all its items, so overflow arrives in one batch.
    func overflow(_ ids: [String]) {
        let new = ids.filter { !overflowed.contains($0) }
        guard !new.isEmpty else { return }
        overflowed += new
        update()
    }

    func releaseOverflow(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        overflowed.removeAll { ids.contains($0) }
        update()
    }

    func update() {
        var bundles = installed.union(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        bundles.formUnion(Settings.shared.knownNames.keys.compactMap { $0.hasPrefix("app:") ? String($0.dropFirst(4)) : nil })
        let concealedApps = bundles.filter { isConcealed("app:\($0)") }
        let concealedSystem = SystemItem.all.filter { isConcealed("system:\($0)") }

        // Lifting the allowlist while an item is revealed would bring back every app macOS hides
        // for not being notarized, and the » button with them, so keep it until the reveal ends.
        if concealedApps.isEmpty && concealedSystem.isEmpty && reveals.isEmpty {
            if restriction.isActive { restriction.invalidate() }
            applied = nil
            onChange?()
            return
        }
        let system = SystemItem.all.filter { !concealedSystem.contains($0) }
        let allowed = bundles.subtracting(concealedApps).sorted()
        if let applied, applied.system == system, applied.bundles == allowed { return }
        applied = (system, allowed)
        restriction.allowSystemItems(system.map { NSNumber(value: $0) }, bundleIdentifiers: allowed) { [weak self] error in
            self?.lastError = error?.localizedDescription
            self?.onChange?()
        }
    }

    func stop() {
        restriction.invalidate()
        applied = nil
    }
}
