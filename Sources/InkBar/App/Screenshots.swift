import InkKit
import AppKit
import ApplicationServices

/// `InkBar --render-screenshots <folder>` writes the README slides from demo items drawn with
/// SF Symbols, so no real apps or personal settings appear.
enum Screenshots {
    private struct Demo {
        let name: String
        let symbol: String
    }

    private static let shown = [Demo(name: "Wi-Fi", symbol: "wifi"), Demo(name: "Battery", symbol: "battery.75percent"),
                                Demo(name: "Control Center", symbol: "switch.2")]
    private static let hidden = [Demo(name: "Cloud Sync", symbol: "icloud"), Demo(name: "VPN", symbol: "lock.shield"),
                                 Demo(name: "Music", symbol: "music.note"), Demo(name: "Timer", symbol: "timer"),
                                 Demo(name: "Clipboard", symbol: "doc.on.clipboard"), Demo(name: "Screen Recorder", symbol: "record.circle"),
                                 Demo(name: "Weather", symbol: "cloud.sun"), Demo(name: "Notes", symbol: "note.text")]

    static func run(output: URL) {
        Fonts.registerBundled()
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let settings = Settings.shared
        let saved = (settings.triggers, settings.profiles, settings.inkIcons)
        defer { settings.triggers = saved.0; settings.profiles = saved.1; settings.inkIcons = saved.2 }
        settings.inkIcons = true

        let cells = hidden.enumerated().map { index, demo -> BarCell in
            let entry = BarEntry(kind: .app("demo.\(index)"), name: demo.name, pid: getpid(), bundleURL: nil,
                                 elements: [StatusElement(element: AXUIElementCreateApplication(getpid()), title: demo.name, frame: .zero)])
            if let image = statusImage(demo.symbol) { IconStore.shared.preload(image, for: IconStore.key(entry, 0)) }
            return BarCell(entry: entry, index: 0, alwaysHidden: false)
        }
        // Rendered before any slide makes its own drawing context current.
        let (inkBar, hoverRect) = hoveredBar(cells, theme: .ink, dark: false, index: 2)
        let nameTag = tag(cells[2].name, theme: .ink, dark: false)
        let sketchSearch = bar(cells, theme: .sketch, dark: false, query: "cl")
        let (sketchDark, sketchHover) = hoveredBar(cells, theme: .sketch, dark: true, index: 0)
        let sketchTag = tag(cells[0].name, theme: .sketch, dark: true)
        let overflowBar = bar(Array(cells.prefix(3)), theme: .ink, dark: false, query: nil)

        let model = SettingsModel()
        model.rows = (cells.map { ($0.entry.id, $0.entry.name) } + [("system:2", "Clock")]).map {
            SettingsModel.Row(id: $0.0, name: $0.1, icon: nil, running: true, trusted: true, overflowed: false)
        }
        settings.profiles = ["Work": [:], "Presenting": [:]]
        settings.triggers = [
            Trigger(condition: .batteryBelow(20), action: .show("app:demo.6")),
            Trigger(condition: .offline, action: .show("app:demo.1")),
            Trigger(condition: .appFrontmost("com.apple.finder"), action: .profile("Presenting")),
            Trigger(condition: .timeBetween(9 * 60, 18 * 60), action: .profile("Work")),
        ]
        let triggers = SettingsPreview.image("triggers", size: CGSize(width: 720, height: 470), model: model)
        let appearance = SettingsPreview.image("appearance", size: CGSize(width: 560, height: 520))

        let icon = NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? URL(fileURLWithPath: "/nonexistent"))

        Promo.slide(title: "A quiet menu bar", subtitle: "Hidden items wait in a floating ink bar, one click away",
                    icon: icon, to: output.appendingPathComponent("1-ink-bar.png")) { ctx in
            let desk = CGRect(x: Promo.content.minX, y: Promo.content.minY + 150, width: Promo.content.width, height: 700), height: CGFloat = 60
            Promo.desktop(ctx, desk, menuBar: height)
            appMenus(desk, height: height, app: "Finder", menus: "File    Edit    View    Go    Window    Help")
            _ = rightItems(desk, height: height, withEnso: true)
            let scale: CGFloat = 3
            let size = CGSize(width: inkBar.size.width * scale, height: inkBar.size.height * scale)
            let frame = CGRect(x: desk.maxX - 40 - size.width, y: desk.minY + height + 30, width: size.width, height: size.height)
            shadowed(ctx) { Promo.image(inkBar, in: frame) }
            let tagSize = CGSize(width: nameTag.size.width * scale, height: nameTag.size.height * scale)
            let tagX = frame.minX + hoverRect.midX * scale - tagSize.width / 2
            shadowed(ctx) { Promo.image(nameTag, in: CGRect(x: tagX, y: frame.maxY + 12, width: tagSize.width, height: tagSize.height)) }
            note(ctx, "click any item to open its menu", from: CGPoint(x: frame.minX - 40, y: frame.maxY + 250),
                 to: CGPoint(x: tagX - 10, y: frame.maxY + 12 + tagSize.height / 2))
        }

        Promo.slide(title: "No more »", subtitle: "Items that don't fit move to the ink bar instead of behind the system's chevron",
                    icon: icon, to: output.appendingPathComponent("2-overflow.png")) { ctx in
            let top = CGRect(x: Promo.content.minX, y: Promo.content.minY + 150, width: Promo.content.width, height: 230)
            let bottom = CGRect(x: Promo.content.minX, y: Promo.content.minY + 600, width: Promo.content.width, height: 400)
            caption("Without InkBar: three items vanish behind »", at: CGPoint(x: top.minX + 8, y: top.minY - 64))
            Promo.desktop(ctx, top, menuBar: 60)
            appMenus(top, height: 60, app: "Xcode", menus: "File    Edit    View    Find    Navigate    Editor    Product    Debug    Integrate    Window    Help")
            let chevronLeft = rightItems(top, height: 60, withEnso: false)
            Promo.menuText("»", at: CGPoint(x: chevronLeft - 58, y: top.minY + 6), bold: true, size: 38)

            caption("With InkBar: they wait in the ink bar until there's room", at: CGPoint(x: bottom.minX + 8, y: bottom.minY - 64))
            Promo.desktop(ctx, bottom, menuBar: 60)
            appMenus(bottom, height: 60, app: "Xcode", menus: "File    Edit    View    Find    Navigate    Editor    Product    Debug    Integrate    Window    Help")
            let left = rightItems(bottom, height: 60, withEnso: true)
            let scale: CGFloat = 2.2
            let size = CGSize(width: overflowBar.size.width * scale, height: overflowBar.size.height * scale)
            shadowed(ctx) { Promo.image(overflowBar, in: CGRect(x: min(left - 40, bottom.maxX - 40 - size.width), y: bottom.minY + 84, width: size.width, height: size.height)) }
        }

        Promo.slide(title: "Find any item", subtitle: "Press ⌥⌘F, type a few letters, press Return",
                    icon: icon, to: output.appendingPathComponent("3-search.png")) { ctx in
            let search = CGSize(width: sketchSearch.size.width * 4, height: sketchSearch.size.height * 4)
            let searchFrame = CGRect(x: Promo.content.midX - search.width / 2, y: Promo.content.minY + 280, width: search.width, height: search.height)
            shadowed(ctx) { Promo.image(sketchSearch, in: searchFrame) }
            note(ctx, "typing filters by name", from: CGPoint(x: searchFrame.maxX + 80, y: searchFrame.maxY + 120),
                 to: CGPoint(x: searchFrame.maxX + 16, y: searchFrame.midY + 20))
            let full = CGSize(width: sketchDark.size.width * 2.6, height: sketchDark.size.height * 2.6)
            let fullFrame = CGRect(x: Promo.content.midX - full.width / 2, y: searchFrame.maxY + 300, width: full.width, height: full.height)
            caption("The whole ink bar, hand-drawn theme in dark", at: CGPoint(x: fullFrame.minX, y: fullFrame.minY - 76))
            shadowed(ctx) { Promo.image(sketchDark, in: fullFrame) }
            let tagSize = CGSize(width: sketchTag.size.width * 2.6, height: sketchTag.size.height * 2.6)
            shadowed(ctx) {
                Promo.image(sketchTag, in: CGRect(x: fullFrame.minX + sketchHover.midX * 2.6 - tagSize.width / 2, y: fullFrame.maxY + 10,
                                                  width: tagSize.width, height: tagSize.height))
            }
        }

        Promo.slide(title: "Triggers and profiles", subtitle: "Bring items back when the battery runs low, you go offline, or an app comes to the front",
                    icon: icon, to: output.appendingPathComponent("4-triggers.png")) { ctx in
            let scale: CGFloat = 1.75
            var x = Promo.content.midX - (720 + 560 + 40) * scale / 2
            let tallest = ([triggers, appearance].compactMap { $0?.size.height }.max() ?? 0) * scale + 56
            for image in [triggers, appearance].compactMap({ $0 }) {
                let rect = CGRect(x: x, y: Promo.content.minY + 30, width: image.size.width * scale, height: tallest)
                Promo.card(ctx, rect, radius: 22) { r in
                    ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
                    ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 56))
                    for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                        ctx.setFillColor(CGColor(srgbRed: CGFloat(color >> 16) / 255, green: CGFloat((color >> 8) & 255) / 255, blue: CGFloat(color & 255) / 255, alpha: 1))
                        ctx.fillEllipse(in: CGRect(x: r.minX + 24 + CGFloat(i) * 34, y: r.minY + 18, width: 22, height: 22))
                    }
                    Promo.image(image, in: CGRect(x: r.minX, y: r.minY + 56, width: image.size.width * scale, height: image.size.height * scale))
                }
                x += rect.width + 40 * scale
            }
        }
    }

    /// A status item as the menu bar draws it: a white glyph on the dark bar, at 2×.
    private static func statusImage(_ symbol: String) -> CGImage? {
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .regular).applying(.init(paletteColors: [.white]))) else { return nil }
        let size = CGSize(width: 76, height: 48)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        glyph.draw(in: CGRect(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// The bar with one item hovered, and where that item sits in it.
    private static func hoveredBar(_ cells: [BarCell], theme: ThemeID, dark: Bool, index: Int) -> (NSImage, CGRect) {
        let view = BarView(frame: .zero)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.painter = Painter(theme: theme, palette: .make(theme, dark: dark), texture: 1)
        view.cells = cells
        view.hovered = index
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        return (image, view.rects.indices.contains(index) ? view.rects[index] : .zero)
    }

    private static func tag(_ name: String, theme: ThemeID, dark: Bool) -> NSImage {
        let view = NameTagView()
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.painter = Painter(theme: theme, palette: .make(theme, dark: dark), texture: 1)
        view.name = name
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    private static func bar(_ cells: [BarCell], theme: ThemeID, dark: Bool, query: String?) -> NSImage {
        let view = BarView(frame: .zero)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.painter = Painter(theme: theme, palette: .make(theme, dark: dark), texture: 1)
        view.cells = cells
        view.query = query
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    private static func appMenus(_ desk: CGRect, height: CGFloat, app: String, menus: String) {
        if let apple = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .regular).applying(.init(paletteColors: [.white]))) {
            Promo.image(apple, in: CGRect(x: desk.minX + 40, y: desk.minY + (height - apple.size.height) / 2, width: apple.size.width, height: apple.size.height))
        }
        Promo.menuText(app, at: CGPoint(x: desk.minX + 92, y: desk.minY + 14), bold: true)
        Promo.menuText(menus, at: CGPoint(x: desk.minX + 92 + CGFloat(app.count) * 17 + 40, y: desk.minY + 14))
    }

    /// The clock and the few items left shown, right to left. Returns the left edge.
    private static func rightItems(_ desk: CGRect, height: CGFloat, withEnso: Bool) -> CGFloat {
        var x = desk.maxX - 250
        Promo.menuText("Sun Oct 25  10:41", at: CGPoint(x: x, y: desk.minY + 14))
        var images = shown.reversed().compactMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 28, weight: .regular).applying(.init(paletteColors: [.white]))) }
        if withEnso { images.append(tinted(AppDelegate.icon(), scale: 2)) }
        for image in images {
            x -= image.size.width + 34
            Promo.image(image, in: CGRect(x: x, y: desk.minY + (height - image.size.height) / 2, width: image.size.width, height: image.size.height))
        }
        return x
    }

    private static func tinted(_ template: NSImage, scale: CGFloat) -> NSImage {
        let size = NSSize(width: template.size.width * scale, height: template.size.height * scale)
        return NSImage(size: size, flipped: false) { rect in
            template.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func caption(_ text: String, at point: CGPoint) {
        NSAttributedString.styled(text, Fonts.serif(46), Palette.make(.ink, dark: false).ink).draw(at: point)
    }

    /// A handwritten vermilion note with a brushed arrow pointing at something.
    private static func note(_ ctx: CGContext, _ text: String, from: CGPoint, to: CGPoint) {
        let red = Palette.make(.ink, dark: false).red
        let label = NSAttributedString.styled(text, Fonts.hand(64), red)
        label.draw(at: CGPoint(x: from.x - 20, y: from.y))
        let mid = CGPoint(x: (from.x + to.x) / 2 + 40, y: (from.y + to.y) / 2)
        InkBrush.stroke(ctx, [CGPoint(x: from.x, y: from.y - 10), mid, to], width: 7, color: red, paper: nil, seed: 12, texture: 0.6)
        let angle = atan2(to.y - mid.y, to.x - mid.x)
        for side: CGFloat in [-1, 1] {
            let a: CGFloat = angle + .pi + side * 0.45
            InkBrush.stroke(ctx, [to, CGPoint(x: to.x + cos(a) * 46, y: to.y + sin(a) * 46)], width: 7, color: red, paper: nil, seed: 13, texture: 0.6)
        }
    }

    private static func shadowed(_ ctx: CGContext, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 44, color: CGColor(gray: 0, alpha: 0.3))
        draw()
        ctx.restoreGState()
    }
}
