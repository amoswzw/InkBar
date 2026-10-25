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
            visibility.overflowed.forEach(visibility.releaseOverflow)
            return
        }
        // Each change relays the menu bar out; wait for it before judging again.
        guard Date().timeIntervalSince(lastChange) > 1 else { return }

        if scan.overflowButton != nil {
            let candidates = scan.entries.filter { entry in
                isDrawn(entry) && entry.kind != .system(2) && entry.kind != .system(8)
            }
            guard let victim = candidates.first else { return }
            var width = victim.elements.reduce(0) { $0 + $1.frame.width }
            // Brought back too early last time: ask for more room before trying again.
            if let at = released[victim.id], Date().timeIntervalSince(at) < 10 { width = max(width, widths[victim.id] ?? 0) + 40 }
            widths[victim.id] = width
            visibility.overflow(victim.id)
            lastChange = Date()
        } else if let last = visibility.overflowed.last, freeSpace(scan) > (widths[last] ?? 60) + margin {
            released[last] = Date()
            visibility.releaseOverflow(last)
            lastChange = Date()
        }
    }

    private func isDrawn(_ entry: BarEntry) -> Bool {
        !visibility.isConcealed(entry.id) && !(visibility.isRestricting && !Notarization.isTrusted(entry.bundleURL))
    }

    private func freeSpace(_ scan: ScanResult) -> CGFloat {
        let left = scan.entries.filter(isDrawn)
            .flatMap(\.elements).map(\.frame.minX).filter { $0 > 0 }.min() ?? NSScreen.screens.first?.frame.width ?? 0
        guard let notch = IconStore.notchGap(), left > notch.minX else { return left - scan.appMenuEnd }
        return (left - notch.maxX) + max(0, notch.minX - scan.appMenuEnd - margin)
    }
}
