import AppKit

/// Keeps the menu bar from overflowing. macOS shows its » button when items don't fit and
/// collapses the leftmost ones into it; this moves those into the ink bar instead, one at a
/// time, and brings them back when the frontmost app's menus leave room again.
final class OverflowGuard {
    private let visibility: VisibilityController
    private var widths: [String: CGFloat] = [:]
    private var released: [String: Date] = [:]
    private var lastChange = Date.distantPast
    /// Space left between the app menus and the first item before bringing one back.
    private let margin: CGFloat = 24

    init(visibility: VisibilityController) {
        self.visibility = visibility
    }

    func check(_ scan: ScanResult) {
        guard Settings.shared.autoOverflow, !visibility.paused else {
            visibility.releaseOverflow(visibility.overflowed)
            return
        }
        // Each change relays the menu bar out; wait for it before judging again.
        guard Date().timeIntervalSince(lastChange) > 1 else { return }

        if let button = scan.overflowButton {
            let candidates = scan.entries.filter { entry in
                isDrawn(entry) && entry.kind != .system(2) && entry.kind != .system(8)
            }
            // Items left of the » are the ones the system has already collapsed into it.
            var victims = candidates.filter { entry in entry.elements.allSatisfy { $0.frame.maxX <= button.minX } }
            if victims.isEmpty, let first = candidates.first { victims = [first] }
            guard !victims.isEmpty else { return }
            for victim in victims {
                var width = victim.elements.reduce(0) { $0 + $1.frame.width }
                // Brought back too early last time: ask for more room before trying again.
                if let at = released[victim.id], Date().timeIntervalSince(at) < 10 { width = max(width, widths[victim.id] ?? 0) + 40 }
                widths[victim.id] = width
            }
            visibility.overflow(victims.map(\.id))
            lastChange = Date()
        } else if !visibility.overflowed.isEmpty, Date().timeIntervalSince(lastChange) > 5 {
            // Bring back, newest first, everything that fits in the room there is, in one change.
            var room = freeSpace(scan) - margin
            var back: [String] = []
            for id in visibility.overflowed.reversed() {
                // Prefer the width the entry has now: it may have shrunk or grown since it
                // was moved in, and the recorded width would trap a shrunken one in the bar.
                let current = scan.entries.first(where: { $0.id == id })?.elements.reduce(0) { $0 + $1.frame.width }
                let width = current ?? widths[id] ?? 60
                if let current { widths[id] = current }
                guard width + 8 <= room else { continue }
                room -= width + 8
                back.append(id)
            }
            guard !back.isEmpty else { return }
            back.forEach { released[$0] = Date() }
            visibility.releaseOverflow(back)
            lastChange = Date()
        }
    }

    private func isDrawn(_ entry: BarEntry) -> Bool {
        !visibility.isConcealed(entry.id) && !(visibility.isRestricting && !Notarization.isTrusted(entry.bundleURL))
    }

    private func freeSpace(_ scan: ScanResult) -> CGFloat {
        let left = scan.entries.filter(isDrawn)
            .flatMap(\.elements).map(\.frame.minX).filter { $0 > 0 }.min() ?? NSScreen.screens.first?.frame.width ?? 0
        // macOS 27 doesn't reliably put items beside the app menus left of the camera housing;
        // it often collapses them into » instead, so only the room right of it counts.
        guard let notch = IconStore.notchGap() else { return left - scan.appMenuEnd }
        return left - notch.maxX
    }
}
