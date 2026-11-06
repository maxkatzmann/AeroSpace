import AppKit
import SwiftUI
import os

final class Space: Identifiable, ObservableObject {
    let name: String
    var windows: [Window]
    var isFocused: Bool
    init(name: String, windows: [Window], isFocused: Bool = false) {
        self.name = name; self.windows = windows; self.isFocused = isFocused
    }
    static func blanks(count: Int, windowCount: Int) -> [Space] {
        (0 ..< max(0, count)).map { _ in Space(name: "", windows: Window.blanks(count: windowCount)) }
    }
}

final class Window: Identifiable {
    enum Kind { case managed(UInt64), blank, add(String) }
    let kind: Kind
    let appBundleId: String
    let pid: Int32
    let isFocused: Bool
    var windowId: UInt64? { if case .managed(let id) = kind { id } else { nil } }
    var isBlank: Bool { if case .blank = kind { true } else { false } }
    var isAddButton: Bool { if case .add = kind { true } else { false } }
    init(kind: Kind, appBundleId: String = "", pid: Int32 = 0, isFocused: Bool = false) {
        self.kind = kind; self.appBundleId = appBundleId; self.pid = pid; self.isFocused = isFocused
    }
    static func blanks(count: Int) -> [Window] { (0 ..< max(0, count)).map { _ in Window(kind: .blank) } }
}

@MainActor
public final class SpaceStation: ObservableObject {
    @Published var spaces: [Space] = []
    @Published var spacesRepresentation: [Space] = []
    @Published var shouldDisplay = false {
        didSet { input?.overlayVisible = shouldDisplay; presentOverlay() }
    }
    @Published var scrollOffset: CGPoint = .zero
    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "spaceStation.enabled"); reconcileInput() }
    }
    @Published public private(set) var snapshot: SpaceStationSnapshot?
    private let defaults: UserDefaults
    private let handler: @MainActor (SpaceStationAction) async -> SpaceStationActionResult
    private let liveInput: Bool
    lazy var displayRecovery = DisplayRecovery(perform: { [weak self] in
        guard let self else { return .unavailable }
        return await self.handler(.refreshState)
    }, recovered: { [weak self] in
        self?.awaitingWakeSnapshot = false
        self?.reconcileInput()
    })
    private var started = false
    private var sleeping = false
    private var awaitingWakeSnapshot = false
    private var generation = 0
    private var input: EventMonitor?
    private var touch: TouchMonitor?
    private var observers: [NSObjectProtocol] = []
    private var panel: NSPanel?
    private var remembered: [String: UInt64] = [:]
    private var pending: SpaceStationAction?
    private var navigation: Task<Void, Never>?
    private var navigationWindow: UInt64?
    private var navigationSpace: String?
    private let logger = Logger(subsystem: "bobko.aerospace", category: "SpaceStation")

    public init(defaults: UserDefaults = .standard, liveInput: Bool = true,
                perform: @escaping @MainActor (SpaceStationAction) async -> SpaceStationActionResult)
    {
        self.defaults = defaults; self.liveInput = liveInput; self.handler = perform
        isEnabled = defaults.object(forKey: "spaceStation.enabled") as? Bool ?? true
    }
    public var isPresenting: Bool { isEnabled && snapshot?.available == true }
    var selectedSpace: Int? { spaces.firstIndex(where: \.isFocused) }
    var nextWorkspace: String {
        let largest = spaces.compactMap { Int($0.name) }.filter { $0 >= 0 }.max() ?? 0
        return largest < Int.max ? String(largest + 1) : "1"
    }
    public func start() {
        guard !started else { return }; started = true
        if liveInput {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                         NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]
            {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let waking = note.name == NSWorkspace.didWakeNotification || note.name == NSWorkspace.screensDidWakeNotification
                    Task.startUnstructured { @MainActor in self?.setSleeping(!waking) }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task.startUnstructured { @MainActor in self?.displayRecovery.check() }
            })
        }
        displayRecovery.start()
        reconcileInput()
    }
    public func stop() {
        started = false; sleeping = false; awaitingWakeSnapshot = false
        displayRecovery.stop(); resetInput()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer); NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
    func setSleeping(_ value: Bool) {
        guard sleeping != value else { displayRecovery.check(); return }
        sleeping = value; resetInput()
        awaitingWakeSnapshot = true
        displayRecovery.setSleeping(value)
    }
    public func update(snapshot: SpaceStationSnapshot) {
        if self.snapshot != snapshot {
            self.snapshot = snapshot
            spaces = snapshot.workspaces.map { ws in
                Space(name: ws.name, windows: ws.windows.map {
                    Window(kind: .managed($0.id), appBundleId: $0.bundleIdentifier ?? "", pid: $0.pid, isFocused: $0.id == snapshot.focusedWindow)
                }, isFocused: ws.name == snapshot.focusedWorkspace)
            }
            if let id = snapshot.focusedWindow { remembered[snapshot.focusedWorkspace] = id }
            remembered = remembered.filter { name, id in spaces.contains { $0.name == name && $0.windows.contains { $0.windowId == id } } }
            updateSpacesRepresentation()
        }
        displayRecovery.update(available: snapshot.available)
        reconcileInput()
        if shouldDisplay { presentOverlay() }
    }
    private func resetInput() {
        generation += 1; pending = nil; navigation?.cancel(); navigationWindow = nil; navigationSpace = nil
        shouldDisplay = false; scrollOffset = .zero
        input?.stop(); input = nil
        touch?.stop(); touch = nil
    }
    private func reconcileInput() {
        guard started, isPresenting, !sleeping, !awaitingWakeSnapshot else { resetInput(); return }
        guard liveInput, input == nil else { return }
        let monitor = EventMonitor()
        monitor.delegate = self
        monitor.onScroll = { [weak self] intent in
            guard let self else { return }; self.shouldDisplay = true
            if let intent { self.navigate(intent) }
        }
        input = monitor; monitor.start()
        let touch = TouchMonitor(); touch.delegate = self; self.touch = touch
    }
    func navigate(_ intent: ScrollIntent) {
        guard let focused = spaces.first(where: \.isFocused) else { return }
        switch intent.target {
            case .window:
                navigationSpace = nil
                let current = navigationWindow ?? focused.windows.first(where: \.isFocused)?.windowId
                guard let id = OrderedNavigation.target(in: focused.windows.compactMap(\.windowId), current: current, step: intent.step) else { return }
                navigationWindow = id; submit(.focusWindow(id))
            case .workspace:
                navigationWindow = nil
                guard let name = OrderedNavigation.target(in: spaces.map(\.name), current: navigationSpace ?? focused.name, step: intent.step) else { return }
                navigationSpace = name; submit(.switchWorkspace(name))
        }
    }
    func submit(_ action: SpaceStationAction) {
        if action == .refreshState { if started { displayRecovery.request() }; return }
        guard started, isPresenting, !sleeping, !awaitingWakeSnapshot else { return }
        pending = action
        guard navigation == nil else { return }
        let token = generation
        navigation = Task.startUnstructured { [weak self] in
            guard let self else { return }
            defer {
                self.navigation = nil
                self.navigationWindow = nil; self.navigationSpace = nil
                if token != self.generation, let pending = self.pending { self.submit(pending) }
            }
            while !Task.isCancelled, token == self.generation, let action = self.pending {
                self.pending = nil
                let result = await self.handler(action)
                guard token == self.generation, !Task.isCancelled else { break }
                if result != .success {
                    self.pending = nil
                    self.logger.error("SpaceStation action failed: \(String(describing: result), privacy: .public)")
                }
            }
        }
    }
    func focus(window: Window) {
        switch window.kind {
            case .managed(let id): submit(.focusWindow(id))
            case .add(let name): submit(.switchWorkspace(name))
            case .blank: break
        }
    }
    func updateSpacesRepresentation() {
        guard let selectedSpace else { spacesRepresentation = []; return }
        let add = !(spaces.last?.windows.isEmpty ?? true)
        let count = spaces.count + (add ? 1 : 0)
        let slots = max(1, 2 * (spaces.lazy.map { $0.windows.count }.max() ?? 0) - 1)
        var result = Space.blanks(count: count - 1 - selectedSpace, windowCount: slots)
        for space in spaces {
            let index = remembered[space.name].flatMap { id in space.windows.firstIndex { $0.windowId == id } } ?? space.windows.indices.first
            var windows = Window.blanks(count: index.map { max(0, slots / 2 - $0) } ?? 0) + space.windows
            windows += Window.blanks(count: max(space.windows.isEmpty ? 1 : 0, slots - windows.count))
            result.append(Space(name: space.name, windows: windows, isFocused: space.isFocused))
        }
        if add { result.append(Space(name: nextWorkspace, windows: [Window(kind: .add(nextWorkspace), appBundleId: "plus")])) }
        result += Space.blanks(count: 2 * count - 1 - result.count, windowCount: slots)
        spacesRepresentation = result
    }
    private func presentOverlay() {
        guard liveInput else { return }
        guard shouldDisplay, let snapshot else { panel?.orderOut(nil); return }
        if panel == nil {
            let panel = NSPanel(contentRect: snapshot.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: SpaceStationView().environmentObject(self))
            self.panel = panel
        }
        panel?.setFrame(snapshot.frame, display: true); panel?.orderFrontRegardless()
    }
}

extension SpaceStation: EventMonitorDelegate {
    func isHolding() { shouldDisplay = true }
    func didRelease() { shouldDisplay = false; scrollOffset = .zero }
    func closeFocused() { if let id = snapshot?.focusedWindow { submit(.closeWindow(id)) } }
}
extension SpaceStation: TouchMonitorDelegate {
    func didPan(_ direction: Direction) { move(in: direction) }
    func didSwipe(_ direction: Direction) { move(in: direction) }
    func move(in direction: Direction) {
        guard let selectedSpace else { return }
        switch direction {
            case .left: submit(.focusDirection(.right))
            case .right: submit(.focusDirection(.left))
            case .up: submit(.switchWorkspace(selectedSpace + 1 < spaces.count ? spaces[selectedSpace + 1].name : nextWorkspace))
            case .down: if selectedSpace > 0 { submit(.switchWorkspace(spaces[selectedSpace - 1].name)) }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }
    func didScroll(_ axis: Axis, delta: CGFloat) { scrollOffset = axis == .horizontal ? CGPoint(x: delta, y: 0) : CGPoint(x: 0, y: delta) }
}
