import AppKit
import ApplicationServices
import CoreWLAN
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    struct Row: Identifiable {
        let id: String
        let name: String
        let icon: CGImage?
        let running: Bool
        let trusted: Bool
        let overflowed: Bool
    }

    struct LayoutRow: Identifiable {
        let element: ElementID
        let name: String
        let icon: CGImage?
        var id: ElementID { element }
    }

    @Published var rows: [Row] = []
    @Published var layout: [LayoutRow] = []
    @Published var moving = false
    @Published var moveFailed = false
    @Published var accessibility = AXIsProcessTrusted()
    @Published var screenRecording = CGPreflightScreenCaptureAccess()
    @Published var locationDenied = false
    @Published var error: String?
    @Published var hidingActive = false
    @Published var selfTrusted = Notarization.isTrusted(Bundle.main.bundleURL)

    weak var app: AppDelegate?
    weak var visibility: VisibilityController?

    func refresh() {
        guard let app, let visibility else { return }
        var seen = Set<String>()
        var rows: [Row] = app.lastScan.entries.map { entry in
            seen.insert(entry.id)
            return Row(id: entry.id, name: entry.name, icon: IconStore.shared.image(IconStore.key(entry, 0)), running: true,
                       trusted: Notarization.isTrusted(entry.bundleURL), overflowed: visibility.overflowed.contains(entry.id))
        }
        for (id, name) in Settings.shared.knownNames where !seen.contains(id) {
            rows.append(Row(id: id, name: name, icon: nil, running: false, trusted: true, overflowed: false))
        }
        self.rows = rows
        if !moving {
            layout = app.lastScan.order(drawn: app.drawnEntryIDs).compactMap { id in
                guard let entry = app.lastScan.entries.first(where: { $0.id == id.entry }) else { return nil }
                let name = entry.elements.count > 1 ? "\(entry.name) · \(entry.elements[id.index].title)" : entry.name
                return LayoutRow(element: id, name: name, icon: IconStore.shared.image(IconStore.key(entry, id.index)))
            }
        }
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        locationDenied = app.triggers.locationDenied
        error = visibility.lastError
        hidingActive = visibility.isRestricting
    }

    func name(of entryID: String) -> String {
        Settings.shared.knownNames[entryID] ?? entryID
    }

    func move(_ index: Int, by offset: Int) {
        guard let app, layout.indices.contains(index + offset) else { return }
        let row = layout[index], target = layout[index + offset]
        moving = true
        moveFailed = false
        app.move(row.element, nextTo: target.element, before: offset < 0) { [weak self] ok in
            self?.moving = false
            self?.moveFailed = !ok
            self?.refresh()
        }
    }
}

final class SettingsWindowController {
    private let window: NSWindow
    private let model = SettingsModel()

    init(app: AppDelegate, visibility: VisibilityController) {
        model.app = app
        model.visibility = visibility
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "InkBar"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.center()
    }

    func show() {
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        if window.isVisible { model.refresh() }
    }
}

private func changed() {
    NotificationCenter.default.post(name: .settingsChanged, object: nil)
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            ItemsSettings(model: model).tabItem { Text("Items") }
            LayoutSettings(model: model).tabItem { Text("Layout") }
            TriggerSettings(model: model).tabItem { Text("Triggers") }
            ProfileSettings(model: model).tabItem { Text("Profiles") }
            AppearanceSettings().tabItem { Text("Appearance") }
            GeneralSettings().tabItem { Text("General") }
            PermissionSettings(model: model).tabItem { Text("Permissions") }
        }
        .padding(16)
        .frame(width: 640, height: 560)
    }
}

private struct ItemIcon: View {
    let icon: CGImage?

    var body: some View {
        Group {
            if let icon {
                Image(decorative: icon, scale: 2).resizable().aspectRatio(contentMode: .fit)
                    .padding(2).background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Color.clear
            }
        }
        .frame(width: 56, height: 20)
    }
}

// MARK: Items

private struct ItemsSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !VisibilityController.isSupported {
                Text("Hiding needs macOS 27 or later.").foregroundStyle(.red)
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
            Text("Hidden items live in the ink bar: click the ensō in the menu bar, press \(Settings.shared.barShortcut.display), or search with \(Settings.shared.searchShortcut.display). Always-hidden items appear there when you hold ⌥ or search.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(Section.allCases, id: \.self) { section in
                    SwiftUI.Section(section.title(chinese: false)) {
                        ForEach(model.rows.filter { Settings.shared.section($0.id) == section }) { row in
                            ItemRow(row: row) { new in
                                Settings.shared.setSection(new, for: row.id)
                                changed()
                                revision += 1
                                model.refresh()
                            }
                        }
                    }
                }
            }
            .id(revision)
            if model.hidingActive && model.rows.contains(where: { $0.running && !$0.trusted }) {
                Text("● Apps marked with a red dot aren't notarized. While anything is hidden, macOS hides their items too; they wait in the ink bar and still open from there.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ItemRow: View {
    let row: SettingsModel.Row
    let move: (Section) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(icon: row.icon)
            Text(row.name).foregroundStyle(row.running ? .primary : .secondary)
            if !row.trusted { Text("●").foregroundStyle(.red).help("Not notarized") }
            if row.overflowed { Text("moved to the ink bar to make room").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Picker("", selection: Binding(get: { Settings.shared.section(row.id) }, set: move)) {
                ForEach(Section.allCases, id: \.self) { Text($0.title(chinese: false)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)
        }
    }
}

// MARK: Layout

private struct LayoutSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The items in the menu bar, left to right. Moving one drags it with ⌘ held, as you would by hand, so the pointer jumps for a moment. Hidden items keep their place and return to it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(Array(model.layout.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) {
                        ItemIcon(icon: row.icon)
                        Text(row.name)
                        Spacer()
                        Button { model.move(index, by: -1) } label: { Image(systemName: "arrow.left") }
                            .disabled(index == 0 || model.moving)
                            .help("Move left")
                        Button { model.move(index, by: 1) } label: { Image(systemName: "arrow.right") }
                            .disabled(index == model.layout.count - 1 || model.moving)
                            .help("Move right")
                    }
                }
            }
            if model.moving { Text("Moving…").font(.caption).foregroundStyle(.secondary) }
            if model.moveFailed { Text("That move didn't take. The menu bar may have been busy; try again.").font(.caption).foregroundStyle(.red) }
        }
    }
}

// MARK: Triggers

private enum ConditionKind: String, CaseIterable {
    case batteryBelow, onBattery, offline, wifiNamed, appRunning, appFrontmost, timeBetween

    var title: String {
        switch self {
        case .batteryBelow: return "Battery is below"
        case .onBattery: return "Running on battery"
        case .offline: return "No internet connection"
        case .wifiNamed: return "Connected to Wi-Fi named"
        case .appRunning: return "App is open"
        case .appFrontmost: return "App is in front"
        case .timeBetween: return "Time is between"
        }
    }

    init(_ condition: TriggerCondition) {
        switch condition {
        case .batteryBelow: self = .batteryBelow
        case .onBattery: self = .onBattery
        case .offline: self = .offline
        case .wifiNamed: self = .wifiNamed
        case .appRunning: self = .appRunning
        case .appFrontmost: self = .appFrontmost
        case .timeBetween: self = .timeBetween
        }
    }

    var defaultCondition: TriggerCondition {
        switch self {
        case .batteryBelow: return .batteryBelow(20)
        case .onBattery: return .onBattery
        case .offline: return .offline
        case .wifiNamed: return .wifiNamed(CWName.current ?? "")
        case .appRunning: return .appRunning("")
        case .appFrontmost: return .appFrontmost("")
        case .timeBetween: return .timeBetween(9 * 60, 18 * 60)
        }
    }
}

private enum CWName {
    static var current: String? { CWWiFiClient.shared().interface()?.ssid() }
}

private struct TriggerSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var triggers = Settings.shared.triggers

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("While a condition holds, a hidden item comes back to the menu bar, or InkBar switches to a profile when it starts to hold.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach($triggers) { $trigger in
                    TriggerRow(trigger: $trigger, model: model) {
                        triggers.removeAll { $0.id == trigger.id }
                        save()
                    }
                    .onChange(of: trigger) { _, _ in save() }
                }
            }
            HStack {
                Button("Add Trigger") {
                    let first = model.rows.first(where: { Settings.shared.section($0.id) != .shown })?.id ?? model.rows.first?.id ?? ""
                    triggers.append(Trigger(condition: .batteryBelow(20), action: .show(first)))
                    save()
                }
                Spacer()
                if model.locationDenied && triggers.contains(where: { $0.condition.needsLocation }) {
                    Text("Wi-Fi names need Location access for InkBar in System Settings → Privacy.").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func save() {
        Settings.shared.triggers = triggers
        changed()
    }
}

private struct TriggerRow: View {
    @Binding var trigger: Trigger
    @ObservedObject var model: SettingsModel
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: $trigger.enabled).labelsHidden()
                Picker("When", selection: Binding(get: { ConditionKind(trigger.condition) }, set: { trigger.condition = $0.defaultCondition })) {
                    ForEach(ConditionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 280)
                conditionDetail
                Spacer()
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            HStack {
                Picker("Then", selection: $trigger.action) {
                    ForEach(model.rows) { row in Text("Show \(row.name)").tag(TriggerAction.show(row.id)) }
                    ForEach(Settings.shared.profiles.keys.sorted(), id: \.self) { name in Text("Switch to profile \(name)").tag(TriggerAction.profile(name)) }
                    if case .show(let id) = trigger.action, !model.rows.contains(where: { $0.id == id }) {
                        Text("Show \(model.name(of: id))").tag(trigger.action)
                    }
                }
                .frame(width: 400)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var conditionDetail: some View {
        switch trigger.condition {
        case .batteryBelow(let percent):
            Stepper("\(percent)%", value: Binding(get: { percent }, set: { trigger.condition = .batteryBelow($0) }), in: 5...95, step: 5)
                .fixedSize()
        case .wifiNamed(let name):
            TextField("Network", text: Binding(get: { name }, set: { trigger.condition = .wifiNamed($0) })).frame(width: 140)
        case .appRunning(let bundle):
            AppPicker(bundle: bundle) { trigger.condition = .appRunning($0) }
        case .appFrontmost(let bundle):
            AppPicker(bundle: bundle) { trigger.condition = .appFrontmost($0) }
        case .timeBetween(let start, let end):
            MinutePicker(minutes: start) { trigger.condition = .timeBetween($0, end) }
            Text("–")
            MinutePicker(minutes: end) { trigger.condition = .timeBetween(start, $0) }
        default:
            EmptyView()
        }
    }
}

private struct AppPicker: View {
    let bundle: String
    let set: (String) -> Void

    var body: some View {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.1 < $1.1 }
        Picker("", selection: Binding(get: { bundle }, set: set)) {
            Text("Choose an app").tag("")
            ForEach(apps, id: \.0) { Text($0.1).tag($0.0) }
            if !bundle.isEmpty && !apps.contains(where: { $0.0 == bundle }) { Text(bundle).tag(bundle) }
        }
        .labelsHidden()
        .frame(width: 160)
    }
}

private struct MinutePicker: View {
    let minutes: Int
    let set: (Int) -> Void

    var body: some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minutes) * 60) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
    }
}

// MARK: Profiles

private struct ProfileSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var profiles = Settings.shared.profiles
    @State private var active = Settings.shared.activeProfile
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A profile remembers which items are shown, hidden and always hidden. Switch from the ensō's right-click menu, or let a trigger switch for you.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(profiles.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(name).fontWeight(name == active ? .semibold : .regular)
                        if name == active { Text("active").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Apply") {
                            model.app?.applyProfile(name)
                            reload()
                        }
                        Button("Update") {
                            Settings.shared.saveProfile(name)
                            reload()
                        }
                        .help("Save the current sections into this profile")
                        Button(role: .destructive) {
                            var all = Settings.shared.profiles
                            all[name] = nil
                            Settings.shared.profiles = all
                            if Settings.shared.activeProfile == name { Settings.shared.activeProfile = nil }
                            reload()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField("New profile name", text: $newName).frame(width: 200)
                Button("Save Current Layout") {
                    Settings.shared.saveProfile(newName.trimmingCharacters(in: .whitespaces))
                    newName = ""
                    reload()
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func reload() {
        profiles = Settings.shared.profiles
        active = Settings.shared.activeProfile
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @AppStorage("theme") private var theme = ThemeID.ink.rawValue
    @AppStorage("appearance") private var appearance = PanelAppearance.system.rawValue
    @AppStorage("inkIcons") private var inkIcons = true
    @State private var style = Settings.shared.style
    @State private var spacing = ItemSpacing.current

    var body: some View {
        Form {
            SwiftUI.Section("Ink bar") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeID.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .onChange(of: theme) { _, _ in changed() }
                Picker("Appearance", selection: $appearance) {
                    Text("Follow system").tag(PanelAppearance.system.rawValue)
                    Text("Light").tag(PanelAppearance.light.rawValue)
                    Text("Dark").tag(PanelAppearance.dark.rawValue)
                }
                Toggle("Draw icons in ink", isOn: $inkIcons)
            }
            SwiftUI.Section("Menu bar") {
                Picker("Fill", selection: $style.fill) {
                    Text("None").tag(MenuBarStyle.Fill.none)
                    Text("Tint").tag(MenuBarStyle.Fill.tint)
                    Text("Paper").tag(MenuBarStyle.Fill.paper)
                }
                if style.fill == .tint {
                    ColorPicker("Tint", selection: Binding(get: { Color(hex: style.tint) }, set: { style.tint = $0.hex }), supportsOpacity: false)
                }
                if style.fill != .none {
                    Slider(value: $style.strength, in: 0.05...0.4) { Text("Strength") }
                    Text("The fill lies over the items, so a strong one dims them.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Brush line along the bottom", isOn: $style.brushLine)
                Toggle("Shadow below", isOn: $style.shadow)
            }
            .onChange(of: style) { _, new in
                Settings.shared.style = new
                changed()
            }
            SwiftUI.Section("Item spacing") {
                Picker("Spacing", selection: $spacing) {
                    Text("System default").tag(Int?.none)
                    ForEach([0, 2, 4, 6, 8, 10, 12, 16], id: \.self) { Text("\($0) pt").tag(Int?.some($0)) }
                }
                .onChange(of: spacing) { _, new in ItemSpacing.set(new) }
                Text("Apps read this when they open: each app picks it up the next time it starts, and all of them after you log out and back in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }

    var hex: UInt32 {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 0 }
        return UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @AppStorage("showOnHover") private var showOnHover = false
    @AppStorage("autoOverflow") private var autoOverflow = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var barShortcut = Settings.shared.barShortcut
    @State private var searchShortcut = Settings.shared.searchShortcut

    var body: some View {
        Form {
            Toggle("Show the ink bar when hovering the empty part of the menu bar", isOn: $showOnHover)
            Toggle("Move items that don't fit into the ink bar", isOn: $autoOverflow)
                .onChange(of: autoOverflow) { _, _ in changed() }
            Text("Instead of collapsing them behind the system's » button, InkBar keeps them in the ink bar and puts them back when the menu bar has room.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Show hidden items") {
                ShortcutRecorder(shortcut: $barShortcut).frame(width: 120, height: 24)
            }
            .onChange(of: barShortcut) { _, new in
                Settings.shared.barShortcut = new
                changed()
            }
            LabeledContent("Search") {
                ShortcutRecorder(shortcut: $searchShortcut).frame(width: 120, height: 24)
            }
            .onChange(of: searchShortcut) { _, new in
                Settings.shared.searchShortcut = new
                changed()
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
        }
        .formStyle(.grouped)
    }
}

/// Click, then press the new shortcut. Esc cancels.
private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { shortcut = $0 }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut = shortcut
    }

    final class RecorderButton: NSButton {
        var onRecord: ((Shortcut) -> Void)?
        var shortcut = Shortcut.defaultBar { didSet { if !recording { title = shortcut.display } } }
        private var recording = false { didSet { title = recording ? "Press keys…" : shortcut.display } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            target = self
            action = #selector(start)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }

        @objc private func start() {
            recording = true
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            if event.keyCode == 53 { recording = false; return }
            if let new = Shortcut(event: event) {
                shortcut = new
                recording = false
                onRecord?(new)
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return super.resignFirstResponder()
        }
    }
}

// MARK: Permissions

private struct PermissionSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            LabeledContent("Accessibility") {
                if model.accessibility { Text("Granted") } else {
                    Button("Grant…") {
                        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    }
                }
            }
            Text("Reads the menu bar's items, opens their menus when you click them in the ink bar, and drags them when you rearrange the layout.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Screen Recording") {
                if model.screenRecording { Text("Granted") } else {
                    Button("Grant…") { CGRequestScreenCaptureAccess() }
                }
            }
            Text("Captures each item's picture while it's visible, so the ink bar can draw it after it's hidden. Only the menu bar is captured, and the pictures stay on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Location") {
                Text(model.locationDenied ? "Denied" : "Asked only for Wi-Fi triggers")
            }
            Text("macOS treats Wi-Fi network names as location data, so a trigger on a network name needs it.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.selfTrusted {
                Text("This copy of InkBar isn't notarized, so macOS hides its own ensō while anything is hidden. Use \(Settings.shared.barShortcut.display) to open the ink bar.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button("Check Again") { model.refresh() }
        }
        .formStyle(.grouped)
    }
}

/// Renders each settings tab to a PNG without showing a window, for checking the layout.
enum SettingsPreview {
    static func render(to directory: URL) {
        let model = SettingsModel()
        model.rows = [
            .init(id: "app:com.example.one", name: "Example", icon: nil, running: true, trusted: true, overflowed: false),
            .init(id: "app:com.example.two", name: "Unsigned Tool", icon: nil, running: true, trusted: false, overflowed: true),
            .init(id: "system:2", name: "Clock", icon: nil, running: true, trusted: true, overflowed: false),
        ]
        model.layout = model.rows.map { .init(element: ElementID(entry: $0.id, index: 0), name: $0.name, icon: nil) }
        model.hidingActive = true
        let tabs: [(String, AnyView)] = [
            ("items", AnyView(ItemsSettings(model: model))),
            ("layout", AnyView(LayoutSettings(model: model))),
            ("triggers", AnyView(TriggerSettings(model: model))),
            ("profiles", AnyView(ProfileSettings(model: model))),
            ("appearance", AnyView(AppearanceSettings())),
            ("general", AnyView(GeneralSettings())),
            ("permissions", AnyView(PermissionSettings(model: model))),
        ]
        for (name, view) in tabs {
            let host = NSHostingView(rootView: view.padding(16).frame(width: 640, height: 520))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings-\(name).png"))
        }
    }
}
