import XCTest
@testable import InkBar

final class InkBarTests: XCTestCase {
    func testMaskKeepsIconAndDropsMenuBar() throws {
        // A dark menu bar with a white 4×4 glyph in the middle.
        let w = 12, h = 12
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let glyph = (4..<8).contains(x) && (4..<8).contains(y)
                let v: UInt8 = glyph ? 250 : 30
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let mask = try XCTUnwrap(IconStore.makeMask(image))
        let data = try XCTUnwrap(mask.dataProvider?.data) as Data
        XCTAssertEqual(data[0], 0, "menu bar background becomes transparent")
        XCTAssertEqual(data[5 * w + 5], 255, "the glyph stays opaque")
    }

    func testSectionsRoundTrip() {
        let settings = Settings.shared
        let saved = settings.sections
        defer { settings.sections = saved }
        settings.setSection(.hidden, for: "app:test.one")
        settings.setSection(.alwaysHidden, for: "system:2")
        XCTAssertEqual(settings.section("app:test.one"), .hidden)
        XCTAssertEqual(settings.section("system:2"), .alwaysHidden)
        settings.setSection(.shown, for: "app:test.one")
        XCTAssertNil(settings.sections["app:test.one"], "shown is the default and isn't stored")
    }

    func testAdHocAppIsNotTrusted() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("InkBarTest-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: app) }
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Probe").path)
        let plist: [String: Any] = ["CFBundleIdentifier": "dev.inkbar.test.adhoc", "CFBundleExecutable": "Probe"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--sign", "-", "--force", app.path]
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)
        XCTAssertFalse(Notarization.isTrusted(app))
    }

    func testAppleAppsCountAsTrusted() {
        XCTAssertTrue(Notarization.isTrusted(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        XCTAssertTrue(Notarization.isTrusted(nil))
    }

    func testSystemItemIdentifiers() {
        XCTAssertEqual(SystemItem.byIdentifier["com.apple.menuextra.clock"], 2)
        XCTAssertEqual(SystemItem.byIdentifier["com.apple.menuextra.controlcenter"], 8)
        XCTAssertEqual(SystemItem.all.count, 9)
    }

    func testBlankCaptureHasNoCoverage() throws {
        let w = 10, h = 10
        let pixels = [UInt8](repeating: 30, count: w * h * 4).enumerated().map { $0.offset % 4 == 3 ? 255 : $0.element }
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        XCTAssertEqual(IconStore.coverage(try XCTUnwrap(IconStore.makeMask(image))), 0)
    }

    func testTriggerConditions() {
        var context = TriggerContext()
        context.batteryPercent = 15
        context.onBattery = true
        context.online = false
        context.wifiName = "Home"
        context.running = ["com.apple.Safari"]
        context.frontmost = "com.apple.Safari"
        context.minuteOfDay = 23 * 60 + 30
        XCTAssertTrue(context.holds(.batteryBelow(20)))
        XCTAssertFalse(context.holds(.batteryBelow(10)))
        XCTAssertTrue(context.holds(.onBattery))
        XCTAssertTrue(context.holds(.offline))
        XCTAssertTrue(context.holds(.wifiNamed("Home")))
        XCTAssertFalse(context.holds(.wifiNamed("Office")))
        XCTAssertTrue(context.holds(.appRunning("com.apple.Safari")))
        XCTAssertTrue(context.holds(.appFrontmost("com.apple.Safari")))
        XCTAssertFalse(context.holds(.timeBetween(9 * 60, 18 * 60)))
        XCTAssertTrue(context.holds(.timeBetween(22 * 60, 7 * 60)), "ranges may wrap past midnight")
        context.minuteOfDay = 6 * 60
        XCTAssertTrue(context.holds(.timeBetween(22 * 60, 7 * 60)))
        XCTAssertFalse(context.holds(.timeBetween(22 * 60, 6 * 60)), "the end is exclusive")
    }

    func testTriggersRoundTrip() {
        let settings = Settings.shared
        let saved = settings.triggers
        defer { settings.triggers = saved }
        let trigger = Trigger(condition: .timeBetween(60, 120), action: .profile("Work"))
        settings.triggers = [trigger]
        XCTAssertEqual(settings.triggers, [trigger])
    }

    func testProfiles() {
        let settings = Settings.shared
        let saved = (settings.sections, settings.profiles, settings.activeProfile)
        defer { settings.sections = saved.0; settings.profiles = saved.1; settings.activeProfile = saved.2 }
        settings.sections = ["app:a": .hidden]
        settings.saveProfile("Focus")
        settings.sections = ["app:b": .alwaysHidden]
        settings.applyProfile("Focus")
        XCTAssertEqual(settings.sections, ["app:a": .hidden])
        XCTAssertEqual(settings.activeProfile, "Focus")
    }

    func testShortcutDisplay() {
        XCTAssertEqual(Shortcut.defaultBar.display, "⌥⌘B")
        XCTAssertEqual(Shortcut(keyCode: 49, modifiers: 0x1000).display, "⌃Space")
    }

    func testKnownNamesDropPidEntries() {
        let settings = Settings.shared
        let saved = settings.knownNames
        defer { settings.knownNames = saved }
        settings.knownNames = ["app:dev.inkstats.InkStats": "InkStats", "app:pid.22048": "InkStats", "system:2": "Clock"]
        XCTAssertEqual(settings.knownNames["app:dev.inkstats.InkStats"], "InkStats")
        XCTAssertEqual(settings.knownNames["system:2"], "Clock")
        XCTAssertNil(settings.knownNames["app:pid.22048"], "a pid-keyed entry can't match a later session")
    }
}
