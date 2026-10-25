import AppKit
import CryptoKit
import ScreenCaptureKit

/// Pictures of status items, captured while they are visible so the ink bar can draw them
/// after they are hidden. Kept on disk across launches.
final class IconStore {
    static let shared = IconStore()

    private var images: [String: CGImage] = [:]
    private var masks: [String: CGImage] = [:]
    private var inFlight: Set<String> = []
    private var capturedAt: [String: Date] = [:]
    private let directory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InkBar/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    static func key(_ entry: BarEntry, _ index: Int) -> String { "\(entry.id)#\(index)" }

    func image(_ key: String) -> CGImage? {
        if let image = images[key] { return image }
        guard let source = CGImageSourceCreateWithURL(file(key) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[key] = image
        return image
    }

    /// Uses a picture without capturing or saving it, for the README screenshots.
    func preload(_ image: CGImage, for key: String) {
        images[key] = image
        masks[key] = nil
    }

    /// The icon as an alpha mask: how far each pixel stands out from the menu bar behind it.
    func mask(_ key: String) -> CGImage? {
        if let mask = masks[key] { return mask }
        guard let image = image(key), let mask = Self.makeMask(image) else { return nil }
        masks[key] = mask
        return mask
    }

    /// Captures every element whose frame is really on screen. Items the system collapsed
    /// into its » menu keep reporting their last frame, so they are skipped.
    func capture(_ scan: ScanResult, isVisible: (BarEntry) -> Bool) {
        guard canCapture, #available(macOS 15.2, *) else { return }
        let notch = Self.notchGap()
        for entry in scan.entries where isVisible(entry) {
            for (index, element) in entry.elements.enumerated() {
                let frame = element.frame
                guard frame.width > 2, frame.minY < 40 else { continue }
                if let button = scan.overflowButton, frame.minX < button.maxX { continue }
                if let notch, frame.maxX > notch.minX, frame.minX < notch.maxX { continue }
                let key = Self.key(entry, index)
                // Live items such as meters change constantly; refreshing once a minute is enough.
                guard !inFlight.contains(key), Date().timeIntervalSince(capturedAt[key] ?? .distantPast) > 60 else { continue }
                inFlight.insert(key)
                Task { @MainActor in
                    defer { self.inFlight.remove(key) }
                    guard let image = try? await SCScreenshotManager.captureImage(in: frame) else { return }
                    self.store(image, key)
                }
            }
        }
    }

    /// Captures one item right away, for an item that's only briefly in the menu bar.
    @MainActor
    func captureNow(_ key: String, frame: CGRect, overflowButton: CGRect?) async {
        guard canCapture, #available(macOS 15.2, *), frame.width > 2, frame.minY < 40 else { return }
        if let overflowButton, frame.minX < overflowButton.maxX { return }
        if let notch = Self.notchGap(), frame.maxX > notch.minX, frame.minX < notch.maxX { return }
        guard let image = try? await SCScreenshotManager.captureImage(in: frame) else { return }
        store(image, key)
    }

    private func store(_ image: CGImage, _ key: String) {
        capturedAt[key] = Date()
        // An empty stretch of menu bar means the item wasn't really there; keep the old picture.
        guard let mask = Self.makeMask(image), Self.coverage(mask) > 0.01 else { return }
        images[key] = image
        masks[key] = mask
        guard let destination = CGImageDestinationCreateWithURL(file(key) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        NotificationCenter.default.post(name: .iconsChanged, object: nil)
    }

    private func file(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).png")
    }

    /// The area hidden behind the camera housing on the main screen, in top-left coordinates.
    static func notchGap() -> CGRect? {
        guard let screen = NSScreen.screens.first, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return CGRect(x: left.maxX, y: 0, width: right.minX - left.maxX, height: left.height)
    }

    /// The share of the mask that is mostly opaque.
    static func coverage(_ mask: CGImage) -> Double {
        guard let data = mask.dataProvider?.data as Data?, !data.isEmpty else { return 0 }
        return Double(data.reduce(0) { $0 + ($1 > 128 ? 1 : 0) }) / Double(data.count)
    }

    static func makeMask(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 2, h > 2,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func luminance(_ i: Int) -> Double {
            (0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])) / 255
        }
        var border: [Double] = []
        for x in 0..<w { border.append(luminance(x * 4)); border.append(luminance(((h - 1) * w + x) * 4)) }
        for y in 0..<h { border.append(luminance(y * w * 4)); border.append(luminance((y * w + w - 1) * 4)) }
        let background = border.sorted()[border.count / 2]

        var alpha = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            alpha[i] = UInt8(min(1, abs(luminance(i * 4) - background) * 2.2) * 255)
        }
        guard let provider = CGDataProvider(data: Data(alpha) as CFData) else { return nil }
        // A gray image (not an image mask), so clipping treats white as fully painted.
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

extension Notification.Name {
    static let iconsChanged = Notification.Name("InkBarIconsChanged")
}
