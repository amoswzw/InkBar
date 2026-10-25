import AppKit
import CoreLocation
import CoreWLAN
import IOKit.ps
import Network

enum TriggerCondition: Codable, Hashable {
    case batteryBelow(Int)
    case onBattery
    case offline
    case wifiNamed(String)
    case appRunning(String)
    case appFrontmost(String)
    /// Minutes after midnight; the range may wrap past midnight.
    case timeBetween(Int, Int)

    var needsLocation: Bool {
        if case .wifiNamed = self { return true }
        return false
    }
}

enum TriggerAction: Codable, Hashable {
    /// Puts a hidden entry in the menu bar while the condition holds.
    case show(String)
    /// Switches to a profile when the condition starts to hold.
    case profile(String)
}

struct Trigger: Codable, Identifiable, Hashable {
    var id = UUID()
    var condition: TriggerCondition
    var action: TriggerAction
    var enabled = true
}

/// The current state of the things triggers look at.
struct TriggerContext {
    var batteryPercent: Int?
    var onBattery = false
    var online = true
    var wifiName: String?
    var running: Set<String> = []
    var frontmost: String?
    var minuteOfDay = 0

    func holds(_ condition: TriggerCondition) -> Bool {
        switch condition {
        case .batteryBelow(let limit): return (batteryPercent ?? 100) < limit
        case .onBattery: return onBattery
        case .offline: return !online
        case .wifiNamed(let name): return wifiName == name
        case .appRunning(let bundle): return running.contains(bundle)
        case .appFrontmost(let bundle): return frontmost == bundle
        case .timeBetween(let start, let end):
            return start <= end ? (start..<end).contains(minuteOfDay) : minuteOfDay >= start || minuteOfDay < end
        }
    }
}

final class TriggerEngine {
    private let visibility: VisibilityController
    private var releases: [UUID: () -> Void] = [:]
    private var held: Set<UUID> = []
    private let path = NWPathMonitor()
    private var online = true
    private let location = CLLocationManager()
    var onProfile: ((String) -> Void)?

    init(visibility: VisibilityController) {
        self.visibility = visibility
        path.pathUpdateHandler = { [weak self] update in
            DispatchQueue.main.async { self?.online = update.status == .satisfied }
        }
        path.start(queue: .global(qos: .utility))
    }

    /// Wi-Fi names are location data, so macOS only shares them once Location access is granted.
    func requestLocationIfNeeded() {
        guard Settings.shared.triggers.contains(where: { $0.enabled && $0.condition.needsLocation }),
              location.authorizationStatus == .notDetermined else { return }
        location.requestWhenInUseAuthorization()
    }

    var locationDenied: Bool {
        [.denied, .restricted].contains(location.authorizationStatus)
    }

    func context(now: Date = Date()) -> TriggerContext {
        var context = TriggerContext()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                context.batteryPercent = current * 100 / max
                context.onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            }
        }
        context.online = online
        context.wifiName = CWWiFiClient.shared().interface()?.ssid()
        context.running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        context.frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        context.minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return context
    }

    func evaluate() {
        let context = context()
        let triggers = Settings.shared.triggers
        for trigger in triggers {
            let holds = trigger.enabled && context.holds(trigger.condition)
            let was = held.contains(trigger.id)
            guard holds != was else { continue }
            if holds { held.insert(trigger.id) } else { held.remove(trigger.id) }
            switch trigger.action {
            case .show(let entry):
                if holds { releases[trigger.id] = visibility.reveal(entry) } else { releases.removeValue(forKey: trigger.id)?() }
            case .profile(let name):
                if holds { onProfile?(name) }
            }
        }
        // Triggers that were deleted or edited let go of what they held.
        let ids = Set(triggers.map(\.id))
        for id in held.subtracting(ids) {
            held.remove(id)
            releases.removeValue(forKey: id)?()
        }
    }

    /// Ids of entries a trigger is holding in the menu bar right now.
    var shownEntries: Set<String> {
        Set(Settings.shared.triggers.compactMap { trigger in
            guard held.contains(trigger.id), case .show(let entry) = trigger.action else { return nil }
            return entry
        })
    }
}
