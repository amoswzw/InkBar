import AppKit

/// The app icon: an ensō on xuan paper with a vermilion seal, in the macOS rounded-square shape.
enum AppIcon {
    static func draw(_ ctx: CGContext, size: CGFloat) {
        let palette = Palette.make(.ink, dark: false)
        // Apple's grid leaves a margin around the rounded square.
        let tile = CGRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
        let shape = CGPath(roundedRect: tile, cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.025, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(palette.paper)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        if let paper = InkBrush.paperTile(palette) {
            ctx.draw(paper, in: CGRect(x: 0, y: 0, width: size, height: size), byTiling: true)
        }
        // The brush's wobble and dry streaks are tuned for small strokes, so paint on a
        // 128-unit canvas and scale it up, top-down like the rest of the renderer.
        let unit = size / 128
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: unit, y: -unit)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let center = CGPoint(x: 62, y: 63)
        let points = (0...30).map { i -> CGPoint in
            let a = (-75 + CGFloat(i) * 11) * .pi / 180
            let r = 31.5 + CGFloat(i) * 0.08
            return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        }
        InkBrush.stroke(ctx, points, width: 9.5, color: palette.ink, paper: palette.paper, seed: 3, texture: 1)
        InkBrush.seal(ctx, rect: CGRect(x: 89, y: 89, width: 15, height: 15), character: "墨", color: palette.red,
                      font: Fonts.brush(11), seed: 9, texture: 0.6)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
}
