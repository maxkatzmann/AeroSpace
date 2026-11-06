import AppKit

struct DisplayGeometry: Equatable {
    // Used by synthesized Equatable to detect display replacements.
    // periphery:ignore
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect

    var isValid: Bool {
        [frame, visibleFrame].allSatisfy {
            !$0.isNull && !$0.isInfinite && $0.origin.x.isFinite && $0.origin.y.isFinite &&
                $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0
        }
    }

    @MainActor static func current() -> [Self] {
        var result: [Self] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return [] }
            result.append(Self(id: id.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        return result
    }
}

/// Environmental refreshes outlive input resets and never share the navigation queue.
@MainActor final class DisplayRecovery {
    var displays: @MainActor () -> [DisplayGeometry] = DisplayGeometry.current
    private let perform: @MainActor () async -> SpaceStationActionResult
    private let recovered: @MainActor () -> Void
    private var active = false
    private var available = false
    private var sleeping = false
    private var geometry: [DisplayGeometry]?
    private var valid = false
    private var pending = false
    private var revision = 0
    private var lifecycle = 0
    private var task: Task<Void, Never>?

    init(perform: @escaping @MainActor () async -> SpaceStationActionResult, recovered: @escaping @MainActor () -> Void) {
        self.perform = perform; self.recovered = recovered
    }

    func start() {
        guard !active else { return }
        active = true; pending = true
        check()
    }

    func stop() {
        active = false; pending = false; sleeping = false
        lifecycle += 1; task?.cancel()
    }

    func update(available: Bool) {
        if available, !self.available { revision += 1 }
        self.available = available
        check()
    }

    func setSleeping(_ value: Bool) {
        guard sleeping != value else { check(); return }
        sleeping = value; pending = true
        lifecycle += 1; task?.cancel()
        check()
    }

    func request() {
        pending = true; revision += 1
        check()
    }

    func check() {
        let current = displays()
        valid = !current.isEmpty && current.allSatisfy(\.isValid)
        if valid, geometry != current {
            geometry = current; revision += 1; pending = true
        }
        schedule()
    }

    private func schedule() {
        guard active, available, !sleeping, valid, pending, task == nil else { return }
        let token = lifecycle
        task = Task.startUnstructured { [weak self] in
            await Task.yield() // Coalesce notification bursts without a settling timer.
            guard let self else { return }
            defer {
                self.task = nil
                if token != self.lifecycle { self.schedule() }
            }
            while self.active, self.available, !self.sleeping, self.valid, self.pending,
                  token == self.lifecycle, !Task.isCancelled
            {
                let version = self.revision
                let result = await self.perform()
                guard token == self.lifecycle, !Task.isCancelled else { return }
                self.check()
                if result != .success {
                    if self.revision != version { continue } // A newer external trigger arrived during this attempt.
                    return
                }
                if self.available, self.valid, version == self.revision {
                    self.pending = false
                    self.recovered()
                }
                if !self.available { return }
            }
        }
    }
}
