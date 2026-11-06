import Foundation

struct ScrollIntent: Equatable {
    enum Target { case window, workspace }
    let target: Target
    let step: Int
}

/// Pure input state; owned exclusively by the event-tap thread.
struct ScrollInterpreter {
    private var target: ScrollIntent.Target?
    private var horizontal: Bool?
    private var accumulated = 0.0
    private var lastEvent = -Double.infinity
    private var lastStep = -Double.infinity
    private var claimed = false

    mutating func reset() { self = Self() }

    mutating func interpret(x: Double, y: Double, precise: Bool, option: Bool,
                            shift: Bool, unrelatedModifier: Bool, momentum: Bool,
                            ended: Bool, time: Double) -> (consume: Bool, intent: ScrollIntent?)
    {
        if momentum { return (claimed, nil) }
        guard option && !unrelatedModifier else {
            target = nil; horizontal = nil; accumulated = 0
            if !ended { claimed = false }
            return (false, nil)
        }
        let nextTarget: ScrollIntent.Target = shift ? .workspace : .window
        if time - lastEvent > 0.2 || target != nextTarget {
            horizontal = nil; accumulated = 0; lastStep = -Double.infinity
        }
        target = nextTarget
        lastEvent = time
        claimed = true
        if ended { horizontal = nil; accumulated = 0; return (true, nil) }
        if horizontal == nil && (x != 0 || y != 0) { horizontal = abs(x) > abs(y) }
        let delta = horizontal == true ? -x : -y
        if delta * accumulated < 0 { accumulated = 0 }
        accumulated += delta
        let threshold = precise ? 40.0 : 1.0
        guard abs(accumulated) >= threshold, time - lastStep >= 0.1 else { return (true, nil) }
        let step = accumulated > 0 ? 1 : -1
        accumulated = 0
        lastStep = time
        return (true, ScrollIntent(target: nextTarget, step: step))
    }
}

/// Missing or removed selections never silently choose a different item.
enum OrderedNavigation {
    static func target<T: Equatable>(in items: [T], current: T?, step: Int) -> T? {
        guard let current, let index = items.firstIndex(of: current),
              items.indices.contains(index + step) else { return nil }
        return items[index + step]
    }
}
