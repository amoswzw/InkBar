import AppKit
import ApplicationServices

/// Opens a concealed item's menu: puts the item back in the menu bar, presses it, and hides
/// it again once its menu or popover is gone.
final class Activator {
    private let visibility: VisibilityController

    init(visibility: VisibilityController) {
        self.visibility = visibility
    }

    func activate(_ entry: BarEntry, index: Int) {
        // Apps macOS hides for not being notarized can't be revealed, but still open when pressed.
        let wasHidden = visibility.isConcealed(entry.id) && Notarization.isTrusted(entry.bundleURL)
        let release = wasHidden ? visibility.reveal(entry.id) : {}
        // The menu bar needs a moment to lay the item out again before it can open a menu there.
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasHidden ? 0.6 : 0)) {
            guard let element = Self.currentElement(entry, index: index) else { return release() }
            let baseline = Self.raisedWindows(pid: entry.pid)
            // Pressing blocks until the menu closes, so it can't run on the main thread.
            DispatchQueue.global(qos: .userInitiated).async { AXUIElementPerformAction(element, kAXPressAction as CFString) }
            self.watchMenu(pid: entry.pid, ignoring: baseline, release: release)
        }
    }

    /// Accessibility elements of a hidden item can be stale, so look the item up again.
    private static func currentElement(_ entry: BarEntry, index: Int) -> AXUIElement? {
        let root = AXUIElementCreateApplication(entry.pid)
        guard let bar = AX.attribute(root, "AXExtrasMenuBar") else { return nil }
        var items = AX.statusItems(in: bar as! AXUIElement)
        if case .system(let raw) = entry.kind {
            items = items.filter { AX.string($0, "AXIdentifier").flatMap { SystemItem.byIdentifier[$0] } == raw }
            return items.first
        }
        items = items.filter { AX.string($0, "AXIdentifier").flatMap { SystemItem.byIdentifier[$0] } == nil }
        items.sort { AX.frame($0).minX < AX.frame($1).minX }
        return index < items.count ? items[index] : items.last
    }

    /// Waits for the app's menu or popover to appear and then close. Gives up waiting for it
    /// to appear after a few seconds, for items that open a regular window instead.
    private func watchMenu(pid: pid_t, ignoring baseline: Set<Int>, release: @escaping () -> Void) {
        var seen = false
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            ticks += 1
            let open = !Self.raisedWindows(pid: pid).subtracting(baseline).isEmpty
            seen = seen || open
            if (seen && !open) || (!seen && ticks > 12) || ticks > 2400 {
                timer.invalidate()
                release()
            }
        }
    }

    /// Windows above the normal level, where menus and popovers live. Some apps keep one open
    /// all the time, so only windows that appear after the press count.
    private static func raisedWindows(pid: pid_t) -> Set<Int> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
                ? $0[kCGWindowNumber as String] as? Int : nil
        })
    }
}
