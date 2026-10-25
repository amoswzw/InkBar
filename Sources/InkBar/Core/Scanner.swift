import AppKit
import ApplicationServices

/// What the system lets us hide on its own: each system item separately, other apps only as a whole.
enum EntryKind: Hashable {
    case system(Int)
    case app(String)
}

/// One status item in the menu bar, as Accessibility reports it.
struct StatusElement {
    let element: AXUIElement
    let title: String
    let frame: CGRect
}

/// A unit the allowlist can show or hide: one system item, or all status items of one app.
struct BarEntry: Identifiable {
    let kind: EntryKind
    let name: String
    let pid: pid_t
    let bundleURL: URL?
    var elements: [StatusElement]

    var id: String {
        switch kind {
        case .system(let raw): return "system:\(raw)"
        case .app(let bundle): return "app:\(bundle)"
        }
    }

    var bundleID: String? {
        if case .app(let bundle) = kind { return bundle }
        return nil
    }
}

struct ScanResult {
    var entries: [BarEntry] = []
    /// The system's own » button, present only while some items don't fit.
    var overflowButton: CGRect?
    /// Right edge of the frontmost app's menus.
    var appMenuEnd: CGFloat = 0
}

enum SystemItem {
    /// MBSystemItemIdentifier raw values in MenuBarClientCore, keyed by Accessibility identifier.
    static let byIdentifier: [String: Int] = [
        "com.apple.menuextra.battery": 0,
        "com.apple.menuextra.bluetooth": 1,
        "com.apple.menuextra.clock": 2,
        "com.apple.menuextra.display": 3,
        "com.apple.menuextra.textinput": 4,
        "com.apple.menuextra.sound": 5,
        "com.apple.menuextra.wifi": 6,
        "com.apple.menuextra.screenmirroring": 7,
        "com.apple.menuextra.controlcenter": 8,
    ]
    static let all = Array(0...8)

    static func name(_ raw: Int) -> String {
        ["Battery", "Bluetooth", "Clock", "Displays", "Keyboard", "Sound", "Wi-Fi", "Screen Mirroring", "Control Center"][raw]
    }
}

enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        (attribute(element, name) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let v = attribute(element, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &origin) }
        if let v = attribute(element, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    /// Status items sit directly in the extras bar, or one level down inside a hosting group.
    static func statusItems(in bar: AXUIElement) -> [AXUIElement] {
        children(bar).flatMap { child -> [AXUIElement] in
            switch string(child, kAXRoleAttribute) {
            case kAXMenuBarItemRole: return [child]
            case kAXGroupRole: return children(child).filter { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }
            default: return []
            }
        }
    }
}

enum Scanner {
    static func scan() -> ScanResult {
        var result = ScanResult()
        let own = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.25)
            if app.isActive, let menus = AX.attribute(root, kAXMenuBarAttribute) {
                result.appMenuEnd = AX.children(menus as! AXUIElement).map { AX.frame($0).maxX }.max() ?? 0
            }
            guard let bar = AX.attribute(root, "AXExtrasMenuBar") else { continue }
            let bundle = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
            guard bundle != own else { continue }

            if bundle == "com.apple.MenuBarAgent" {
                for child in AX.children(bar as! AXUIElement) where AX.string(child, kAXRoleAttribute) == kAXButtonRole {
                    result.overflowButton = AX.frame(child)
                }
            }
            var appElements: [StatusElement] = []
            for item in AX.statusItems(in: bar as! AXUIElement) {
                let identifier = AX.string(item, "AXIdentifier")
                let title = AX.string(item, kAXTitleAttribute) ?? AX.string(item, kAXDescriptionAttribute) ?? AX.string(item, kAXHelpAttribute) ?? app.localizedName ?? bundle
                let element = StatusElement(element: item, title: title, frame: AX.frame(item))
                if let raw = identifier.flatMap({ SystemItem.byIdentifier[$0] }) {
                    result.entries.append(BarEntry(kind: .system(raw), name: SystemItem.name(raw), pid: app.processIdentifier,
                                                   bundleURL: nil, elements: [element]))
                } else if bundle != "com.apple.MenuBarAgent" {
                    appElements.append(element)
                }
            }
            if !appElements.isEmpty {
                result.entries.append(BarEntry(kind: .app(bundle), name: app.localizedName ?? bundle, pid: app.processIdentifier,
                                               bundleURL: app.bundleURL, elements: appElements.sorted { $0.frame.minX < $1.frame.minX }))
            }
        }
        result.entries.sort { ($0.elements.first?.frame.minX ?? 0) < ($1.elements.first?.frame.minX ?? 0) }
        return result
    }
}
