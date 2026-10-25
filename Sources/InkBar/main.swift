import AppKit

if CommandLine.arguments.contains("--scan") {
    let result = Scanner.scan()
    print("app menus end at \(Int(result.appMenuEnd)), » button: \(result.overflowButton.map { "\($0)" } ?? "none")")
    for entry in result.entries {
        let trusted = Notarization.isTrusted(entry.bundleURL) ? "" : "  [not notarized]"
        print("\(entry.id)  \(entry.name)\(trusted)")
        for element in entry.elements { print("    \(element.title)  \(element.frame)") }
    }
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--render-icon"), index + 1 < CommandLine.arguments.count {
    Fonts.registerBundled()
    let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    AppIcon.draw(ctx, size: CGFloat(size))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--render-screenshots"), index + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    Screenshots.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--render-settings"), index + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    SettingsPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    exit(0)
}

// Two copies would each hold their own allowlist and fight over the menu bar.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
