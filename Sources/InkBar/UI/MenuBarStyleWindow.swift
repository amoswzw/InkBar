import InkKit
import AppKit

/// Decorates the menu bar. Its background is opaque on many setups, so a window behind it
/// would never show; this sits just above it, lets every click through, and keeps its fills
/// light enough that the items stay readable.
final class MenuBarStyleController {
    private var windows: [NSWindow] = []
    private let shadowDepth: CGFloat = 10

    func apply(_ style: MenuBarStyle, painter: Painter) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard !style.isPlain else { return }
        for screen in NSScreen.screens {
            let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
            guard barHeight > 0 else { continue }
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight - shadowDepth,
                               width: screen.frame.width, height: barHeight + shadowDepth)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            // Not on full-screen spaces, where the menu bar hides itself.
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.contentView = MenuBarStyleView(style: style, painter: painter, barHeight: barHeight, shadowDepth: shadowDepth)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

private final class MenuBarStyleView: NSView {
    let style: MenuBarStyle
    let painter: Painter
    let barHeight: CGFloat
    let shadowDepth: CGFloat

    init(style: MenuBarStyle, painter: Painter, barHeight: CGFloat, shadowDepth: CGFloat) {
        self.style = style
        self.painter = painter
        self.barHeight = barHeight
        self.shadowDepth = shadowDepth
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bar = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        let strength = CGFloat(min(max(style.strength, 0.05), 0.4))
        switch style.fill {
        case .none:
            break
        case .tint:
            let c = style.tint
            ctx.setFillColor(CGColor(srgbRed: CGFloat((c >> 16) & 255) / 255, green: CGFloat((c >> 8) & 255) / 255,
                                     blue: CGFloat(c & 255) / 255, alpha: strength))
            ctx.fill(bar)
        case .paper:
            ctx.saveGState()
            ctx.clip(to: bar)
            ctx.setAlpha(strength)
            ctx.setFillColor(painter.palette.paper)
            ctx.fill(bar)
            if let tile = InkBrush.paperTile(painter.palette) {
                ctx.draw(tile, in: CGRect(x: 0, y: 0, width: tile.width, height: tile.height), byTiling: true)
            }
            ctx.restoreGState()
        }
        if style.shadow {
            let colors = [CGColor(gray: 0, alpha: 0.28), CGColor(gray: 0, alpha: 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: barHeight), end: CGPoint(x: 0, y: barHeight + shadowDepth), options: [])
            }
        }
        if style.brushLine {
            let y = barHeight - 1.5
            let points = stride(from: CGFloat(0), through: bounds.width, by: bounds.width / 12).map { CGPoint(x: $0, y: y) }
            painter.line(ctx, points, hue: .ink, width: 1.6, seed: 77, small: true)
        }
    }
}
