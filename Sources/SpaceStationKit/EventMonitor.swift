import AppKit

@MainActor protocol EventMonitorDelegate: AnyObject {
    func isHolding()
    func didRelease()
    func closeFocused()
}

@MainActor final class EventMonitor {
    weak var delegate: (any EventMonitorDelegate)?
    var onScroll: ((ScrollIntent?) -> Void)?
    var overlayVisible = false { didSet { EventTapManager.shared.isConsumingWKeyPresses = overlayVisible } }
    private var monitors: [Any] = []
    private var timer: Timer?
    private var optionDown = false
    func start() {
        EventTapManager.shared.onScroll = { [weak self] in self?.onScroll?($0) }
        EventTapManager.shared.onClose = { [weak self] in self?.delegate?.closeFocused() }
        EventTapManager.shared.startTap()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] in self?.receive($0) }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in self?.receive(event); return event }) { monitors.append(local) }
    }
    private func receive(_ event: NSEvent) {
        if event.type == .keyDown { timer?.invalidate(); timer = nil; return }
        let down = event.modifierFlags.contains(.option)
        guard down != optionDown else { return }; optionDown = down
        timer?.invalidate(); timer = nil
        if down {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.delegate?.isHolding() }
            }
        } else { delegate?.didRelease() }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }; monitors = []
        EventTapManager.shared.stopTap()
        EventTapManager.shared.onScroll = nil; EventTapManager.shared.onClose = nil
        optionDown = false
    }
}
