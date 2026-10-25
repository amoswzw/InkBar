import AppKit

/// One status item drawn in the ink bar.
struct BarCell {
    let entry: BarEntry
    let index: Int
    let alwaysHidden: Bool

    var key: String { IconStore.key(entry, index) }
    var name: String { entry.elements.count > 1 ? "\(entry.name) · \(entry.elements[index].title)" : entry.name }
    /// Shown in place of a picture that hasn't been captured yet.
    var label: String { entry.elements.count > 1 ? entry.elements[index].title : entry.name }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The floating ink bar under the menu bar that holds hidden items.
final class BarPanelController {
    private let panel: KeyPanel
    private let view: BarView
    private var outsideClick: Any?
    var onActivate: ((BarCell) -> Void)?
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: BarView.height),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        view = BarView(frame: panel.contentLayoutRect)
        panel.contentView = view
        view.onActivate = { [weak self] cell in
            self?.hide()
            self?.onActivate?(cell)
        }
        view.onClose = { [weak self] in self?.hide() }
    }

    func show(_ cells: [BarCell], painter: Painter, appearance: NSAppearance?, search: Bool) {
        panel.appearance = appearance
        view.painter = painter
        view.cells = cells
        view.query = search ? "" : nil
        let size = view.fittingSize
        guard let screen = NSScreen.screens.first else { return }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let origin = NSPoint(x: screen.frame.maxX - size.width - 8, y: screen.frame.maxY - menuBarHeight - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        if search { panel.makeKey() }
        if outsideClick == nil {
            outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
        }
    }

    func refresh(_ cells: [BarCell]) {
        guard isVisible else { return }
        view.cells = cells
        let size = view.fittingSize
        var frame = panel.frame
        frame.origin.x = frame.maxX - size.width
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    func hide() {
        panel.orderOut(nil)
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
    }

    /// Whether the pointer is over the bar, for closing it after a hover.
    func contains(_ point: NSPoint) -> Bool { isVisible && panel.frame.insetBy(dx: -6, dy: -6).contains(point) }
}

final class BarView: NSView {
    static let height: CGFloat = 46
    private let pad: CGFloat = 12, gap: CGFloat = 6, iconHeight: CGFloat = 22

    var painter = Painter(theme: .ink, palette: .make(.ink, dark: false), texture: 1)
    var cells: [BarCell] = [] { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var query: String? { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var onActivate: ((BarCell) -> Void)?
    var onClose: (() -> Void)?

    private var hovered: Int?
    private var rects: [CGRect] = []
    private var paper: (dark: Bool, image: CGImage)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var visibleCells: [BarCell] {
        guard let query, !query.isEmpty else { return cells }
        return cells.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var chinese: Bool { painter.theme == .ink }

    override var fittingSize: NSSize { NSSize(width: layout(nil), height: Self.height) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if painter.palette.isDark != dark {
            painter = Painter(theme: painter.theme, palette: .make(painter.theme, dark: dark), texture: painter.texture)
        }
        drawBackground(ctx)
        _ = layout(ctx)
    }

    /// Lays the bar out from left to right, drawing when given a context. Returns the width.
    private func layout(_ ctx: CGContext?) -> CGFloat {
        let p = painter, pal = p.palette
        var x = pad
        let midY = Self.height / 2
        if ctx != nil { rects = [] }

        if let query {
            let label = NSAttributedString.styled((chinese ? "寻 " : "Find ") + query, p.fonts.text(12), query.isEmpty ? pal.sub : pal.ink)
            if let ctx {
                label.draw(at: CGPoint(x: x, y: midY - label.size().height / 2))
                p.rule(ctx, from: CGPoint(x: x, y: midY + 10), to: CGPoint(x: x + max(60, label.size().width), y: midY + 10), seed: 7)
            }
            x += max(60, label.size().width) + gap * 2
        }

        let shown = visibleCells
        if shown.isEmpty {
            let searching = !(query ?? "").isEmpty
            let empty = searching ? (chinese ? "没有匹配" : "No match") : (chinese ? "没有隐藏的图标" : "Nothing hidden")
            let text = NSAttributedString.styled(empty, p.fonts.text(12), pal.sub)
            text.draw(at: CGPoint(x: x, y: midY - text.size().height / 2))
            return x + text.size().width + pad
        }
        var previous: BarCell?
        for (i, cell) in shown.enumerated() {
            if let previous {
                if previous.alwaysHidden != cell.alwaysHidden, let ctx {
                    p.line(ctx, [CGPoint(x: x + gap, y: 12), CGPoint(x: x + gap - 0.5, y: Self.height - 12)], hue: .c, width: 1.4, seed: 90, small: true)
                }
                x += previous.entry.id == cell.entry.id ? 2 : (previous.alwaysHidden != cell.alwaysHidden ? gap * 3 : gap)
            }
            let width = cellWidth(cell)
            let rect = CGRect(x: x, y: midY - iconHeight / 2, width: width, height: iconHeight)
            if let ctx {
                rects.append(rect)
                drawCell(ctx, cell, rect: rect, hovered: hovered == i)
            }
            x += width
            previous = cell
        }
        return x + pad
    }

    private func cellWidth(_ cell: BarCell) -> CGFloat {
        if let image = IconStore.shared.image(cell.key) {
            return min(140, CGFloat(image.width) / CGFloat(image.height) * iconHeight)
        }
        return NSAttributedString.styled(cell.label, painter.fonts.text(11), painter.palette.ink).size().width + 8
    }

    private func drawCell(_ ctx: CGContext, _ cell: BarCell, rect: CGRect, hovered: Bool) {
        let p = painter, pal = p.palette
        if hovered {
            switch p.theme {
            case .ink:
                ctx.saveGState()
                ctx.setFillColor(pal.ink.copy(alpha: 0.07)!)
                ctx.fill(rect.insetBy(dx: -3, dy: -3))
                ctx.restoreGState()
            case .sketch:
                p.outline(ctx, rect.insetBy(dx: -3, dy: -3), color: pal.a, seed: 31, small: true)
            }
            p.rule(ctx, from: CGPoint(x: rect.minX, y: rect.maxY + 5), to: CGPoint(x: rect.maxX, y: rect.maxY + 5), seed: 11)
        }
        let flipped = { (draw: () -> Void) in
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rect.maxY + rect.minY)
            ctx.scaleBy(x: 1, y: -1)
            draw()
            ctx.restoreGState()
        }
        if Settings.shared.inkIcons, let mask = IconStore.shared.mask(cell.key) {
            flipped {
                ctx.clip(to: rect, mask: mask)
                ctx.setFillColor(pal.ink)
                ctx.fill(rect)
            }
        } else if let image = IconStore.shared.image(cell.key) {
            flipped { ctx.draw(image, in: rect) }
        } else {
            let text = NSAttributedString.styled(cell.label, p.fonts.text(11), pal.ink)
            text.draw(at: CGPoint(x: rect.minX + 4, y: rect.midY - text.size().height / 2))
            p.outline(ctx, rect, color: pal.ink.copy(alpha: 0.3)!, seed: Int(rect.minX), small: true)
        }
        if !Notarization.isTrusted(cell.entry.bundleURL) {
            p.dot(ctx, CGPoint(x: rect.maxX, y: rect.minY), radius: 2, seed: 5)
        }
        if hovered {
            let label = NSAttributedString.styled(cell.name, p.fonts.text(10), pal.sub)
            label.draw(at: CGPoint(x: min(rect.minX, bounds.width - label.size().width - 6), y: 1))
        }
    }

    private func drawBackground(_ ctx: CGContext) {
        let pal = painter.palette
        switch painter.theme {
        case .ink:
            let shape = CGPath(roundedRect: bounds, cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.setFillColor(pal.paper)
            ctx.fill(bounds)
            if paper?.dark != pal.isDark, let tile = InkBrush.paperTile(pal) { paper = (pal.isDark, tile) }
            if let tile = paper?.image { ctx.draw(tile, in: CGRect(x: 0, y: 0, width: tile.width, height: tile.height), byTiling: true) }
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setStrokeColor(pal.ink.copy(alpha: 0.12)!)
            ctx.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 5, cornerHeight: 5, transform: nil))
            ctx.strokePath()
            ctx.restoreGState()
        case .sketch:
            ctx.setFillColor(pal.paper)
            ctx.fill(bounds)
            painter.outline(ctx, bounds.insetBy(dx: 3, dy: 3), color: pal.ink, width: 1.6, seed: 400, roughness: min(1.2, painter.texture))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = rects.firstIndex { $0.insetBy(dx: -3, dy: -6).contains(point) }
        if index != hovered { hovered = index; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = rects.firstIndex(where: { $0.insetBy(dx: -3, dy: -6).contains(point) }) else { return }
        onActivate?(visibleCells[index])
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onClose?()
        case 36, 76: if let first = visibleCells.first { onActivate?(first) }
        case 51: if var q = query, !q.isEmpty { q.removeLast(); query = q }
        default:
            // The ⌥ of the shortcut may still be down, which would turn letters into symbols.
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty, chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                query = (query ?? "") + chars
            }
        }
        guard let window else { return }
        var frame = window.frame
        frame.origin.x = frame.maxX - fittingSize.width
        frame.size.width = fittingSize.width
        window.setFrame(frame, display: true)
    }
}
