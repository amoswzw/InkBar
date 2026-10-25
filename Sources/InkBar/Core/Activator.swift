import InkKit
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
            let items = Self.currentElements(entry)
            guard let element = index < items.count ? items[index] : items.last else { return release() }
            Task { @MainActor in
                // Items that were never in sight when InkBar looked have no picture yet. This
                // is the moment they're drawn and not yet highlighted by the press.
                if wasHidden {
                    let button = Scanner.overflowButton()
                    for (i, item) in items.enumerated() {
                        await IconStore.shared.captureNow(IconStore.key(entry, i), frame: AX.frame(item), overflowButton: button)
                    }
                }
                let baseline = Set(Self.raisedWindows(pid: entry.pid).keys)
                // Pressing blocks until the menu closes, so it can't run on the main thread.
                DispatchQueue.global(qos: .userInitiated).async { AXUIElementPerformAction(element, kAXPressAction as CFString) }
                self.watchMenu(pid: entry.pid, ignoring: baseline, release: release)
            }
        }
    }

    /// Accessibility elements of a hidden item can be stale, so look the items up again,
    /// in the same order the scanner gives them.
    private static func currentElements(_ entry: BarEntry) -> [AXUIElement] {
        let root = AXUIElementCreateApplication(entry.pid)
        guard let bar = AX.attribute(root, "AXExtrasMenuBar") else { return [] }
        let items = AX.statusItems(in: bar as! AXUIElement)
        if case .system(let raw) = entry.kind {
            return items.filter { AX.string($0, "AXIdentifier").flatMap { SystemItem.byIdentifier[$0] } == raw }
        }
        return items.filter { AX.string($0, "AXIdentifier").flatMap { SystemItem.byIdentifier[$0] } == nil }
            .sorted { AX.frame($0).minX < AX.frame($1).minX }
    }

    /// Waits for the app's menu or popover to appear and then close. Gives up waiting for it
    /// to appear after a few seconds, for items that open a regular window instead.
    private func watchMenu(pid: pid_t, ignoring baseline: Set<Int>, release: @escaping () -> Void) {
        var seen = false
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            ticks += 1
            let menus = Self.raisedWindows(pid: pid).filter { !baseline.contains($0.key) }
            let open = !menus.isEmpty
            // The item opens its menu where it sits in the menu bar, which can be far from the
            // ink bar; bring the pointer to it once, as it appears.
            if open, !seen, Settings.shared.followMenu,
               let menu = menus.values.max(by: { $0.width * $0.height < $1.width * $1.height }),
               let pointer = CGEvent(source: nil)?.location,
               let target = Self.pointerTarget(menu: menu, pointer: pointer) {
                CGWarpMouseCursorPosition(target)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
            seen = seen || open
            if (seen && !open) || (!seen && ticks > 12) || ticks > 2400 {
                timer.invalidate()
                release()
            }
        }
    }

    /// Where to put the pointer for a menu that just opened: over its first row, or nil when the
    /// pointer is already at it. Both in global coordinates with the origin top-left.
    static func pointerTarget(menu: CGRect, pointer: CGPoint) -> CGPoint? {
        guard !menu.insetBy(dx: -40, dy: -40).contains(pointer) else { return nil }
        return CGPoint(x: menu.minX + min(24, menu.width / 2), y: menu.minY + min(14, menu.height / 2))
    }

    /// Windows above the normal level, where menus and popovers live, by number with their
    /// frames. Some apps keep one open all the time, so only windows new since the press count.
    private static func raisedWindows(pid: pid_t) -> [Int: CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [Int: CGRect] = [:]
        for window in windows where (window[kCGWindowOwnerPID as String] as? pid_t) == pid && (window[kCGWindowLayer as String] as? Int ?? 0) > 0 {
            guard let number = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            result[number] = frame
        }
        return result
    }
}
