import AppKit

enum Hue {
    case ink, a, b, c, green, violet, red
}

/// Draws chart primitives in the active theme. All coordinates are top-left origin.
struct Painter {
    let theme: ThemeID
    let palette: Palette
    let texture: CGFloat

    var fonts: ThemeFonts { ThemeFonts(theme: theme) }

    func stroke(_ hue: Hue) -> CGColor {
        switch hue {
        case .ink: return palette.ink
        case .a: return palette.a
        case .b: return palette.b
        case .c: return palette.c
        case .green: return palette.green
        case .violet: return palette.violet
        case .red: return palette.red
        }
    }

    func fill(_ hue: Hue) -> CGColor {
        switch hue {
        case .ink: return theme == .ink ? palette.ink : palette.aFill
        case .a: return palette.aFill
        case .b: return palette.bFill
        case .c: return palette.cFill
        case .green: return palette.greenFill
        case .violet: return palette.violetFill
        case .red: return palette.bFill
        }
    }

    private func rough(seed: Int, small: Bool, roughness: CGFloat? = nil, width: CGFloat = 1, gap: CGFloat = -1) -> RoughGenerator {
        var o = RoughOptions()
        o.roughness = roughness ?? texture * (small ? 0.5 : 1)
        o.strokeWidth = width
        o.hachureGap = gap
        o.seed = Int32(truncatingIfNeeded: seed)
        return RoughGenerator(o)
    }

    func line(_ ctx: CGContext, _ points: [CGPoint], hue: Hue, width: CGFloat, seed: Int, small: Bool = false) {
        switch theme {
        case .ink:
            InkBrush.stroke(ctx, points, width: width, color: stroke(hue), paper: small ? nil : palette.paper, seed: seed, texture: texture)
        case .sketch:
            var g = rough(seed: seed, small: small, roughness: texture * (small ? 0.35 : 0.7))
            g.o.bowing = 0.5
            ctx.strokeRough(g.curve(points), color: stroke(hue), width: width * 0.75)
        }
    }

    func outline(_ ctx: CGContext, _ rect: CGRect, color: CGColor, width: CGFloat = 1, seed: Int, small: Bool = false, roughness: CGFloat? = nil) {
        var g = rough(seed: seed, small: small, roughness: roughness)
        ctx.strokeRough(g.polyline(corners(rect), closed: true), color: color, width: width)
    }

    func dot(_ ctx: CGContext, _ center: CGPoint, radius: CGFloat, seed: Int) {
        switch theme {
        case .ink:
            InkBrush.dot(ctx, center, radius: radius, color: palette.red, texture: texture)
        case .sketch:
            ctx.saveGState()
            ctx.setFillColor(palette.red)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ctx.restoreGState()
            let ring = (0...10).map { i -> CGPoint in
                let a = CGFloat(i) / 10 * 2 * .pi
                return CGPoint(x: center.x + cos(a) * radius * 1.25, y: center.y + sin(a) * radius * 1.25)
            }
            var g = rough(seed: seed, small: true, roughness: 0.6)
            g.o.disableMultiStroke = true
            ctx.strokeRough(g.curve(ring), color: palette.red, width: 1)
        }
    }

    func rule(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, seed: Int) {
        switch theme {
        case .ink:
            InkBrush.stroke(ctx, [a, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 0.5), b], width: 0.9,
                            color: palette.ink.copy(alpha: 0.45)!, paper: nil, seed: seed, texture: texture)
        case .sketch:
            var g = rough(seed: seed, small: false, roughness: 0.8)
            ctx.strokeRough(g.doubleLine(a, b), color: palette.ink.copy(alpha: 0.45)!, width: 1)
        }
    }

    private func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }
}

extension NSAttributedString {
    static func styled(_ string: String, _ font: NSFont, _ color: CGColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .labelColor])
    }
}
