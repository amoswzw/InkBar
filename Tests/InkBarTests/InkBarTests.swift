import AppKit
import InkKit
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

    private func systemEntry(_ raw: Int, pid: pid_t, x: CGFloat) -> BarEntry {
        BarEntry(kind: .system(raw), name: SystemItem.name(raw), pid: pid, bundleURL: nil,
                 elements: [StatusElement(element: AXUIElementCreateSystemWide(), title: "", frame: CGRect(x: x, y: 0, width: 30, height: 24))])
    }

    func testConcealedSystemItemIsRestoredUnderItsOwnersCurrentProcess() {
        var memory = SystemItemMemory()
        memory.remember(ScanResult(entries: [systemEntry(2, pid: 10, x: 900), systemEntry(8, pid: 10, x: 950)]),
                        owner: { $0 == 10 ? "com.apple.controlcenter" : nil })

        var scan = ScanResult(entries: [systemEntry(2, pid: 20, x: 900)])
        memory.restore(&scan, keep: { $0 == "system:8" }, pid: { $0 == "com.apple.controlcenter" ? 20 : nil })
        XCTAssertEqual(scan.entries.map(\.id), ["system:2", "system:8"])
        XCTAssertEqual(scan.entries.last?.pid, 20, "Control Center may have restarted since it was seen")
    }

    func testSystemItemIsOnlyRestoredWhenWantedAndRunning() {
        var memory = SystemItemMemory()
        memory.remember(ScanResult(entries: [systemEntry(8, pid: 10, x: 950)]), owner: { _ in "com.apple.controlcenter" })

        var scan = ScanResult()
        memory.restore(&scan, keep: { _ in false }, pid: { _ in 10 })
        XCTAssertTrue(scan.entries.isEmpty, "an item that isn't concealed was removed by the user")
        memory.restore(&scan, keep: { _ in true }, pid: { _ in nil })
        XCTAssertTrue(scan.entries.isEmpty, "its owner isn't running")
    }

    private func capture(width w: Int, height h: Int, glyph columns: Range<Int>) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let v: UInt8 = columns.contains(x) && (4..<h - 4).contains(y) ? 250 : 30
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testGlyphColumnsLeaveOutTheAppsPadding() throws {
        let mask = try XCTUnwrap(IconStore.makeMask(capture(width: 40, height: 46, glyph: 12..<30)))
        XCTAssertEqual(IconStore.glyphColumns(mask), 12...29)
        XCTAssertFalse(IconStore.isClipped(mask))
    }

    func testCaptureCutAtItsEdgeIsClipped() throws {
        let mask = try XCTUnwrap(IconStore.makeMask(capture(width: 44, height: 46, glyph: 0..<18)))
        XCTAssertTrue(IconStore.isClipped(mask), "the glyph runs off the left edge")
    }

    func testCaptureScaleFollowsItsHeight() {
        XCTAssertEqual(IconStore.pixelsPerPoint(capture(width: 68, height: 50, glyph: 18..<50)), 2)
        XCTAssertEqual(IconStore.pixelsPerPoint(capture(width: 44, height: 46, glyph: 8..<30)), 2)
        XCTAssertEqual(IconStore.pixelsPerPoint(capture(width: 34, height: 24, glyph: 9..<25)), 1)
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

    func testAccessibilityPointsMapToTheirDisplay() throws {
        let primary = try XCTUnwrap(NSScreen.screens.first, "needs a display")
        let height = Screens.menuBarHeight(primary)
        try XCTSkipIf(height <= 0, "the menu bar is hidden")
        XCTAssertEqual(Screens.containing(axPoint: CGPoint(x: primary.frame.minX + 20, y: 5)), primary)
        let item = CGRect(x: primary.frame.maxX - 120, y: (height - 22) / 2, width: 30, height: 22)
        XCTAssertTrue(Screens.isInMenuBar(item))
        XCTAssertFalse(Screens.isInMenuBar(item.offsetBy(dx: 0, dy: primary.frame.height / 2)), "the middle of the screen isn't the menu bar")
    }

    func testDroppedRowsLandBesideTheRightNeighbour() {
        // Rows a b c d; SwiftUI reports the insertion index in the original order.
        XCTAssertNil(SettingsModel.placement(from: 1, to: 1), "dropped where it was")
        XCTAssertNil(SettingsModel.placement(from: 1, to: 2), "dropped just after itself")
        XCTAssertTrue(SettingsModel.placement(from: 3, to: 0)! == (0, true), "d before a")
        XCTAssertTrue(SettingsModel.placement(from: 0, to: 4)! == (3, false), "a after d")
        XCTAssertTrue(SettingsModel.placement(from: 0, to: 2)! == (1, false), "a after b")
        XCTAssertTrue(SettingsModel.placement(from: 2, to: 1)! == (1, true), "c before b")
    }

    func testPointerGoesToTheMenuOnlyWhenFarFromIt() {
        let menu = CGRect(x: 400, y: 30, width: 220, height: 180)
        XCTAssertEqual(Activator.pointerTarget(menu: menu, pointer: CGPoint(x: 1800, y: 60)), CGPoint(x: 424, y: 44),
                       "lands on the first row")
        XCTAssertNil(Activator.pointerTarget(menu: menu, pointer: CGPoint(x: 450, y: 15)), "already at the menu")
        let tiny = CGRect(x: 0, y: 30, width: 30, height: 20)
        XCTAssertEqual(Activator.pointerTarget(menu: tiny, pointer: CGPoint(x: 900, y: 500)), CGPoint(x: 15, y: 40), "stays inside a small popover")
    }

    func testPidKeyedNamesAreNeverRemembered() {
        let settings = Settings.shared
        let saved = settings.knownNames
        defer { settings.knownNames = saved }
        UserDefaults.standard.set(["app:pid.42": "probe", "app:com.example.one": "One"], forKey: "knownNames")
        XCTAssertEqual(settings.knownNames, ["app:com.example.one": "One"], "old pid-keyed entries are ignored when read")
    }
}
