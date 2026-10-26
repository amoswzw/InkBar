import InkKit
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

/// System items left off the allowlist aren't created at all, so Accessibility stops reporting
/// them, unlike hidden apps' items. The last entry each had while it was there stands in for it.
struct SystemItemMemory {
    private var seen: [Int: (entry: BarEntry, owner: String)] = [:]

    mutating func remember(_ scan: ScanResult,
                           owner: (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }) {
        for entry in scan.entries {
            guard case .system(let raw) = entry.kind, let bundle = owner(entry.pid) else { continue }
            seen[raw] = (entry, bundle)
        }
    }

    /// Adds the remembered entries the scan is missing that `keep` accepts, under their owner's
    /// process now, which is new if it restarted since.
    func restore(_ scan: inout ScanResult, keep: (String) -> Bool,
                 pid: (String) -> pid_t? = { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier }) {
        let present = Set(scan.entries.map(\.id))
        for (_, item) in seen where !present.contains(item.entry.id) && keep(item.entry.id) {
            guard let pid = pid(item.owner) else { continue }
            let entry = item.entry
            scan.entries.append(BarEntry(kind: entry.kind, name: entry.name, pid: pid, bundleURL: nil, elements: entry.elements))
        }
        scan.entries.sort { ($0.elements.first?.frame.minX ?? 0) < ($1.elements.first?.frame.minX ?? 0) }
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
    /// The system's » button, if it's showing, without scanning every app.
    static func overflowButton() -> CGRect? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first,
              let bar = AX.attribute(AXUIElementCreateApplication(agent.processIdentifier), "AXExtrasMenuBar") else { return nil }
        return AX.children(bar as! AXUIElement).first { AX.string($0, kAXRoleAttribute) == kAXButtonRole }.map(AX.frame)
    }

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
