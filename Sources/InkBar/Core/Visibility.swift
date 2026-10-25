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

    init() {
        // A newly launched app is missing from the allowlist, so it would start out hidden.
        NotificationCenter.default.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
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

    func overflow(_ id: String) {
        guard !overflowed.contains(id) else { return }
        overflowed.append(id)
        update()
    }

    func releaseOverflow(_ id: String) {
        overflowed.removeAll { $0 == id }
        update()
    }

    func update() {
        var bundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
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
