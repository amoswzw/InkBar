import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let visibility = VisibilityController()
    private lazy var activator = Activator(visibility: visibility)
    private lazy var overflow = OverflowGuard(visibility: visibility)
    private(set) lazy var triggers = TriggerEngine(visibility: visibility)
    private let style = MenuBarStyleController()
    private let bar = BarPanelController()
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private var hotKeys: [HotKey] = []
    private var hoverMonitor: Any?
    private var hoverStart: Date?
    private var openedByHover = false
    private var scanning = false
    private var hidingStarted = false
    private(set) var lastScan = ScanResult()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundled()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "inkbar.main"
        if let button = statusItem.button {
            button.image = Self.icon()
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("InkBar")
        }

        bar.onActivate = { [weak self] cell in self?.activator.activate(cell.entry, index: cell.index) }
        visibility.onChange = { [weak self] in self?.settingsWindow?.refresh() }

        triggers.onProfile = { [weak self] name in self?.applyProfile(name) }
        registerHotKeys()
        applyStyle()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyStyle()
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.applyStyle()
        }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.hoverMoved() }

        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Give the menu bar a moment to relayout for the new app's menus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.scan() }
            }
        }
        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKeys()
            self?.applyStyle()
            self?.triggers.requestLocationIfNeeded()
            self?.triggers.evaluate()
            self?.visibility.update()
            self?.scan()
        }
        NotificationCenter.default.addObserver(forName: .iconsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.bar.refresh(self.cells(includeAlwaysHidden: false))
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }

        if !AXIsProcessTrusted() || !IconStore.shared.canCapture { openSettings(page: "permissions") }
        else if !VisibilityController.isSupported { openSettings(page: nil) }
        scan()
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibility.stop()
    }

    // MARK: Scanning

    func scan() {
        guard !scanning, AXIsProcessTrusted() else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let result = Scanner.scan()
            DispatchQueue.main.async { self.finishScan(result) }
        }
    }

    private func finishScan(_ result: ScanResult) {
        scanning = false
        lastScan = result
        var names = settings.knownNames
        // pid-keyed entries aren't stored, so counting them would rewrite the settings every scan.
        for entry in result.entries where names[entry.id] != entry.name && !entry.id.hasPrefix("app:pid.") { names[entry.id] = entry.name }
        if names != settings.knownNames { settings.knownNames = names }

        IconStore.shared.capture(result) { entry in
            // A revealed item is usually highlighted with its menu open, which shouldn't become its picture.
            !visibility.isConcealed(entry.id) && !visibility.isRevealed(entry.id)
                && (!visibility.isRestricting || Notarization.isTrusted(entry.bundleURL))
        }
        // Picture everything once before the first hiding, so the ink bar has icons to draw.
        guard hidingStarted else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.hidingStarted = true
                self.visibility.update()
                self.scan()
            }
            return
        }
        triggers.evaluate()
        overflow.check(result)
        visibility.update()
        bar.refresh(cells(includeAlwaysHidden: bar.isVisible && showingEverything))
        settingsWindow?.refresh()
    }

    // MARK: Ink bar

    private var showingEverything = false

    func cells(includeAlwaysHidden: Bool) -> [BarCell] {
        var cells: [BarCell] = []
        for alwaysHidden in [false, true] where !alwaysHidden || includeAlwaysHidden {
            for entry in lastScan.entries {
                let section = settings.section(entry.id)
                let hiddenBySystem = visibility.isRestricting && !Notarization.isTrusted(entry.bundleURL)
                let belongs = alwaysHidden ? section == .alwaysHidden
                    : section == .hidden || (section == .shown && (visibility.overflowed.contains(entry.id) || hiddenBySystem))
                // A trigger holding it in the menu bar puts it there instead.
                guard belongs, !triggers.shownEntries.contains(entry.id) else { continue }
                cells += entry.elements.indices.map { BarCell(entry: entry, index: $0, alwaysHidden: alwaysHidden) }
            }
        }
        return cells
    }

    private var painter: Painter {
        let dark: Bool
        switch settings.appearance {
        case .system: dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .light: dark = false
        case .dark: dark = true
        }
        return Painter(theme: settings.theme, palette: .make(settings.theme, dark: dark), texture: CGFloat(settings.texture))
    }

    private var panelAppearance: NSAppearance? {
        switch settings.appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Option shows the always-hidden section too.
    func toggleBar(search: Bool, everything: Bool = NSEvent.modifierFlags.contains(.option)) {
        if bar.isVisible && !search { return bar.hide() }
        showingEverything = everything || search
        openedByHover = false
        bar.show(cells(includeAlwaysHidden: showingEverything), painter: painter, appearance: panelAppearance, search: search)
    }

    private func hoverMoved() {
        guard settings.showOnHover, let screen = NSScreen.screens.first else { return }
        let point = NSEvent.mouseLocation
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let inMenuBar = point.y >= screen.frame.maxY - menuBarHeight && screen.frame.contains(CGPoint(x: point.x, y: point.y - 1))
        // Only the empty stretch between the app menus and the first item, so hovering an item still works normally.
        let firstItem = lastScan.entries.filter { !visibility.isConcealed($0.id) }.flatMap(\.elements).map(\.frame.minX).filter { $0 > 0 }.min() ?? screen.frame.maxX
        let inGap = inMenuBar && point.x > lastScan.appMenuEnd + 8 && point.x < firstItem - 4

        if bar.isVisible {
            if openedByHover && !inMenuBar && !bar.contains(point) { bar.hide() }
            return
        }
        guard inGap else { hoverStart = nil; return }
        if let start = hoverStart {
            if Date().timeIntervalSince(start) > 0.35 {
                hoverStart = nil
                toggleBar(search: false, everything: false)
                openedByHover = true
            }
        } else {
            hoverStart = Date()
        }
    }

    // MARK: Menu

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return toggleBar(search: false) }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Hidden Items  \(settings.barShortcut.display)", action: #selector(showBar), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Search  \(settings.searchShortcut.display)", action: #selector(showSearch), keyEquivalent: "").target = self
        let pause = menu.addItem(withTitle: "Show Everything in the Menu Bar", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = visibility.paused ? .on : .off
        if !settings.profiles.isEmpty {
            let profiles = NSMenu()
            for name in settings.profiles.keys.sorted() {
                let item = profiles.addItem(withTitle: name, action: #selector(profileChosen(_:)), keyEquivalent: "")
                item.target = self
                item.state = name == settings.activeProfile ? .on : .off
            }
            menu.addItem(withTitle: "Profile", action: nil, keyEquivalent: "").submenu = profiles
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit InkBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showBar() { toggleBar(search: false) }
    @objc private func showSearch() { toggleBar(search: true) }
    @objc private func togglePause() { visibility.paused.toggle() }
    @objc private func profileChosen(_ sender: NSMenuItem) { applyProfile(sender.title) }

    func applyProfile(_ name: String) {
        settings.applyProfile(name)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    private func registerHotKeys() {
        let bar = settings.barShortcut, search = settings.searchShortcut
        hotKeys = []
        hotKeys = [
            HotKey(keyCode: bar.keyCode, modifiers: bar.modifiers, id: 1) { [weak self] in self?.toggleBar(search: false) },
            HotKey(keyCode: search.keyCode, modifiers: search.modifiers, id: 2) { [weak self] in self?.toggleBar(search: true) },
        ]
    }

    private func applyStyle() {
        // The decoration follows the menu bar's own appearance, not the ink bar's setting.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        style.apply(settings.style, painter: Painter(theme: settings.theme, palette: .make(settings.theme, dark: dark), texture: CGFloat(settings.texture)))
    }

    /// Entries drawn in the menu bar right now, which are the only ones that can be dragged.
    var drawnEntryIDs: Set<String> {
        Set(lastScan.entries.filter { !visibility.isConcealed($0.id) && (!visibility.isRestricting || Notarization.isTrusted($0.bundleURL)) }.map(\.id))
    }

    /// Moves a menu bar item next to another by dragging it, off the main thread since it waits on the menu bar.
    func move(_ id: ElementID, nextTo target: ElementID, before: Bool, done: @escaping (Bool) -> Void) {
        let drawn = drawnEntryIDs
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Mover.move(id, nextTo: target, before: before, drawn: drawn)
            DispatchQueue.main.async {
                self.scan()
                done(ok)
            }
        }
    }

    @objc func openSettingsFromMenu() { openSettings(page: nil) }

    func openSettings(page: String?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(app: self, visibility: visibility)
        }
        settingsWindow?.show(page: page)
    }

    /// An ensō, the single brush circle, drawn as a template so the menu bar tints it.
    static func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let points = (0...26).map { i -> CGPoint in
                let a = (-70 + CGFloat(i) * 12.5) * .pi / 180
                let r = 6.6 + CGFloat(i) * 0.03
                return CGPoint(x: rect.midX + r * cos(a), y: rect.midY + r * sin(a))
            }
            InkBrush.stroke(ctx, points, width: 2.4, color: .black, paper: nil, seed: 3, texture: 0.6)
            return true
        }
        image.isTemplate = true
        return image
    }
}
