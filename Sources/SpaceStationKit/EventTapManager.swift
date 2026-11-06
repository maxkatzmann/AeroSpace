import Cocoa
import os

private func eventTapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>?
{
    guard let refcon else { return .passUnretained(event) }
    return Unmanaged<InputTapWorker>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

@MainActor final class EventTapManager {
    static let shared = EventTapManager()
    private var worker: InputTapWorker?
    var onScroll: ((ScrollIntent?) -> Void)?
    var onClose: (() -> Void)?
    private var consumeScroll = false
    private var consumeW = false
    var isConsumingScrollEvents: Bool {
        get { consumeScroll }
        set { consumeScroll = newValue; worker?.capture.withLock { $0.scroll = newValue } }
    }
    var isConsumingWKeyPresses: Bool {
        get { consumeW }
        set { consumeW = newValue; worker?.capture.withLock { $0.close = newValue } }
    }
    func startTap() {
        guard worker == nil, ProcessInfo.processInfo.environment["SPACESTATION_DISABLE_INPUT_TAP"] != "1" else { return }
        let worker = InputTapWorker { [weak self] source, intent, close in
            guard let self, self.worker === source else { return }
            if close { self.onClose?() } else { self.onScroll?(intent) }
        }
        self.worker = worker
        let initialCapture = (consumeScroll, consumeW)
        worker.capture.withLock { $0 = initialCapture }
        let thread = Thread { worker.run() }; thread.name = "SpaceStation input tap"; thread.start()
    }
    func stopTap() {
        let previous = worker; worker = nil
        consumeScroll = false; consumeW = false
        previous?.stop()
    }
}

// Each worker owns one interpreter and run loop. Only capture and lifecycle state
// cross threads, protected by their locks. Retired workers cannot deliver intents.
private final class InputTapWorker: @unchecked Sendable {
    let capture = OSAllocatedUnfairLock(initialState: (scroll: false, close: false))
    private let lifecycle = NSLock()
    private var cancelled = false
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var interpreter = ScrollInterpreter()
    private let deliver: @MainActor @Sendable (InputTapWorker, ScrollIntent?, Bool) -> Void
    init(deliver: @escaping @MainActor @Sendable (InputTapWorker, ScrollIntent?, Bool) -> Void) { self.deliver = deliver }
    func run() {
        let mask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let created = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: eventTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, created, 0)
        else {
            Logger(subsystem: "bobko.aerospace", category: "SpaceStation").error("Could not create input tap")
            return
        }
        let runLoop = CFRunLoopGetCurrent()!
        lifecycle.lock()
        guard !cancelled else { lifecycle.unlock(); CFMachPortInvalidate(created); return }
        tap = created; loop = runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
        lifecycle.unlock()
        CFRunLoopRun()
        lifecycle.lock()
        tap = nil; loop = nil
        lifecycle.unlock()
        CFRunLoopRemoveSource(runLoop, source, .commonModes); CFMachPortInvalidate(created)
    }
    func stop() {
        lifecycle.lock()
        cancelled = true
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
        lifecycle.unlock()
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        lifecycle.lock()
        let active = !cancelled
        if active && (type == .tapDisabledByTimeout || type == .tapDisabledByUserInput), let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        lifecycle.unlock()
        guard active else { return .passUnretained(event) }
        let state = capture.withLock { $0 }
        if type == .keyDown, state.close, event.getIntegerValueField(.keyboardEventKeycode) == 13 {
            DispatchQueue.main.async { self.deliver(self, nil, true) }; return nil
        }
        if type == .scrollWheel {
            if state.scroll { interpreter.reset(); return nil }
            if let e = NSEvent(cgEvent: event) {
                let result = interpreter.interpret(x: e.scrollingDeltaX, y: e.scrollingDeltaY, precise: e.hasPreciseScrollingDeltas,
                                                   option: e.modifierFlags.contains(.option), shift: e.modifierFlags.contains(.shift),
                                                   unrelatedModifier: !e.modifierFlags.isDisjoint(with: [.command, .control]),
                                                   momentum: !e.momentumPhase.isEmpty, ended: e.phase.contains(.ended) || e.phase.contains(.cancelled), time: e.timestamp)
                if result.consume {
                    DispatchQueue.main.async { self.deliver(self, result.intent, false) }; return nil
                }
            }
        }
        return .passUnretained(event)
    }
}
