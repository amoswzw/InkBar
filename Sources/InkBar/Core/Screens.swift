import AppKit

/// Which display is which. Accessibility and CoreGraphics measure from the top-left corner of
/// the primary display, y going down; AppKit from its bottom-left corner, y going up.
enum Screens {
    static func containing(axPoint point: CGPoint) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoa = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        return NSScreen.screens.first { $0.frame.contains(cocoa) }
    }

    /// The display macOS reports the status items on, judged by the clock or Control Center,
    /// which are always in the menu bar.
    static func menuBar(_ scan: ScanResult) -> NSScreen? {
        let anchor = scan.entries.first { $0.kind == .system(2) || $0.kind == .system(8) }?.elements.first?.frame
        if let anchor, anchor.minX > 0, let screen = containing(axPoint: CGPoint(x: anchor.midX, y: anchor.midY)) { return screen }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func withPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    static func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        screen.frame.maxY - screen.visibleFrame.maxY
    }

    /// Whether an Accessibility frame lies in the menu bar of the display it's on.
    static func isInMenuBar(_ frame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first,
              let screen = containing(axPoint: CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        let top = primary.frame.maxY - screen.frame.maxY
        return frame.minY >= top - 2 && frame.maxY <= top + menuBarHeight(screen) + 2
    }

    /// Whether a frame overlaps the camera housing of the display it's on.
    static func underNotch(_ frame: CGRect) -> Bool {
        guard let gap = notchGap(containing(axPoint: CGPoint(x: frame.midX, y: frame.midY))) else { return false }
        return frame.maxX > gap.lowerBound && frame.minX < gap.upperBound
    }

    /// The span hidden behind the camera housing, in global x; nil on displays without one.
    static func notchGap(_ screen: NSScreen?) -> ClosedRange<CGFloat>? {
        guard let screen, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return left.maxX...right.minX
    }
}
