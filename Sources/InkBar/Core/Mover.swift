import AppKit

/// Rearranges menu bar items the way a person does: by dragging them with ⌘ held.
/// Only items drawn in the menu bar can be moved, so hidden ones are placed by their section.
enum Mover {
    /// Moves the element so it sits directly left of (`before`) or right of the target.
    /// Returns whether the new scan shows it there.
    @discardableResult
    static func move(_ id: ElementID, nextTo target: ElementID, before: Bool, drawn: Set<String>) -> Bool {
        for _ in 0..<2 {
            let scan = Scanner.scan()
            guard let from = scan.frame(of: id), let to = scan.frame(of: target) else { return false }
            if isPlaced(scan, id, target, before: before, drawn: drawn) { return true }
            // Dropping just inside the target's near edge puts the item on that side of it.
            let dropX = before ? to.minX + 3 : to.maxX - 3
            drag(from: CGPoint(x: from.midX, y: from.midY), to: CGPoint(x: dropX, y: from.midY))
            Thread.sleep(forTimeInterval: 0.6)
        }
        return isPlaced(Scanner.scan(), id, target, before: before, drawn: drawn)
    }

    private static func isPlaced(_ scan: ScanResult, _ id: ElementID, _ target: ElementID, before: Bool, drawn: Set<String>) -> Bool {
        let order = scan.order(drawn: drawn)
        guard let i = order.firstIndex(of: id), let j = order.firstIndex(of: target) else { return false }
        return before ? i == j - 1 : i == j + 1
    }

    private static func drag(from: CGPoint, to: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let restore = CGEvent(source: nil)?.location ?? from
        func post(_ type: CGEventType, _ point: CGPoint, command: Bool = true) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            if command { event.flags = .maskCommand }
            event.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, from)
        usleep(80_000)
        post(.leftMouseDown, from)
        usleep(150_000)
        for step in 1...20 {
            let t = CGFloat(step) / 20
            post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y))
            usleep(15_000)
        }
        usleep(150_000)
        post(.leftMouseUp, to)
        usleep(50_000)
        post(.mouseMoved, restore, command: false)
    }
}

/// One status item, identified across scans by its owner and its position among the owner's items.
struct ElementID: Hashable, Codable {
    let entry: String
    let index: Int
}

extension ScanResult {
    func frame(of id: ElementID) -> CGRect? {
        guard let entry = entries.first(where: { $0.id == id.entry }), id.index < entry.elements.count else { return nil }
        return entry.elements[id.index].frame
    }

    /// Items of the given entries left to right. Hidden items keep reporting stale frames,
    /// so callers pass only the entries really drawn.
    func order(drawn: Set<String>) -> [ElementID] {
        entries.filter { drawn.contains($0.id) }.flatMap { entry in entry.elements.indices.map { (ElementID(entry: entry.id, index: $0), entry.elements[$0].frame.minX) } }
            .sorted { $0.1 < $1.1 }.map(\.0)
    }
}
