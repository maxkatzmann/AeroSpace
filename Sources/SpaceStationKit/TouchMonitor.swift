import Foundation
import OpenMultitouchSupport
import SwiftUI

enum Axis: String {
    case horizontal = "Horizontal"
    case vertical = "Vertical"
}

enum Direction {
    case left
    case right
    case up
    case down
}

@MainActor protocol TouchMonitorDelegate: AnyObject {
    // A slower movement in a given direction
    func didPan(_ direction: Direction)
    // A faster movement in a given direction
    func didSwipe(_ direction: Direction)
    // Fingers have been continuously touching
    // the trackpad for a given time.
    func isHolding()
    // Fingers have been lifted from the trackpad.
    func didRelease()

    func didScroll(_ axis: Axis, delta: CGFloat)
}

@MainActor final class TouchMonitor: ObservableObject {

    let manager = OMSManager.shared

    weak var delegate: (any TouchMonitorDelegate)? = nil

    // Tracks whether we are currently performing a 4-finger panning motion.
    private var releaseWork: DispatchWorkItem?

    func reset() {
        releaseWork?.cancel()
        isPanning = false
        releaseWork?.cancel()
        EventTapManager.shared.isConsumingScrollEvents = false
        startPoint = nil; startTime = nil; lastPoint = nil; lastTime = nil
        swipeRegisteredAlready = false; holdRegisteredAlready = false
        delegate?.didRelease()
    }

    private var isPanning: Bool = false {
        didSet {
            releaseWork?.cancel()
            if self.isPanning {
                // We are panning, so we need to consume scroll events.
                EventTapManager.shared.isConsumingScrollEvents = true
            } else {
                // We are not panning, so we need to stop consuming scroll events.
                // However, we only do so after a certain delay, to avoid that
                // fingers that are still on the trackpad after the gesture ended
                // trigger scrolling accidentally.
                let work = DispatchWorkItem { EventTapManager.shared.isConsumingScrollEvents = false }
                releaseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.33, execute: work)
            }
        }
    }

    // Keep track of where and when the current 4-finger pan started,
    var startPoint: CGPoint? = nil
    var startTime: TimeInterval? = nil

    // Keep track of where and when we got the touch.
    var lastPoint: CGPoint? = nil
    var lastTime: TimeInterval? = nil

    // How far we need to move until we consider the movement
    // to trigger an action.
    let actionDistanceThresholdVertical: CGFloat = 0.085
    let actionDistanceThresholdHorizontal: CGFloat = 0.075

    // Time before we have to reach the action threshold.
    // Everything below is a swipe, everything above is a pan.
    let swipeDurationThreshold: CGFloat = 0.2

    // How fast the first movements need to be to be considered
    // a swipe.
    let swipeVelocityThreshold: Double = 1.5

    // Whether we have already registered a swipe during this gesture.
    var swipeRegisteredAlready: Bool = false

    // Whether we have already registered a hold during this gesture.
    var holdRegisteredAlready: Bool = false

    private var listenerTask: Task<Void, Never>?

    func stop() {
        listenerTask?.cancel(); listenerTask = nil
        manager.stopListening(); reset()
    }

    init() {
        manager.startListening()
        EventTapManager.shared.startTap()

        listenerTask = Task.startUnstructured { [weak self, manager] in
            for await touches in manager.touchDataStream {
                if Task.isCancelled { break }
                // Only consider 4 finger touches
                self?.handleTouches(touches: touches)
            }
        }
    }

    @MainActor
    func handleTouches(touches: [OMSTouchData]) {
        // Update panning state here on @MainActor so that isPanning is never written
        // from a background Task and read here concurrently.
        let wasPanning = isPanning
        updatePanningStateIfNeeded(touches)

        guard self.isPanning else {
            self.updateStartPointIfNeeded(nil)
            self.updateLastPoint(nil)
            self.updateStartTimeIfNeeded(nil)
            self.updateLastTime(nil)
            self.swipeRegisteredAlready = false
            self.holdRegisteredAlready = false
            if wasPanning { self.delegate?.didRelease() }
            return
        }

        let point = self.averagePoint(forTouches: touches)
        let time = touches.first?.time
        var velocity: Double? = nil
        if let time {
            velocity = self.currentVelocity(
                to: point,
                at: time,
            )
        }

        self.updateStartPointIfNeeded(point)
        self.updateStartTimeIfNeeded(touches.first?.time)

        self.updateLastPoint(point)
        self.updateLastTime(touches)

        guard let startPoint else {
            return
        }

        let delta = (point - startPoint)

        if let velocity, let time {
            self.registerHoldIfNeeded(time: time)
            self.interpretMovement(delta.x, axis: .horizontal, velocity: velocity, time: time)
            self.interpretMovement(delta.y, axis: .vertical, velocity: velocity, time: time)
        }

        if abs(delta.x) > abs(delta.y) {
            self.delegate?.didScroll(.horizontal, delta: delta.x)
        } else {
            self.delegate?.didScroll(.vertical, delta: delta.y)
        }
    }

    func averagePoint(forTouches touches: [OMSTouchData]) -> CGPoint {
        let points = touches.map { $0.point }
        let normalization = 1.0 / CGFloat(touches.count)
        return
            points
                .reduce(CGPoint.zero, +)
                .applying(CGAffineTransform(scaleX: normalization, y: normalization))
    }

    func updateStartPointIfNeeded(_ point: CGPoint?) {
        guard point != nil else {
            // If the position is nil, we are not starting a new touch.
            // We reset the touchStartPosition to nil.
            self.startPoint = nil
            return
        }

        // We do not set a new touchStartPosition if we already have one.
        guard self.startPoint == nil else {
            return
        }

        self.startPoint = point
    }

    func updateStartTimeIfNeeded(_ time: TimeInterval?) {
        guard time != nil else {
            self.startTime = nil
            return
        }

        guard self.startTime == nil else {
            return
        }

        self.startTime = time
    }

    func updateLastPoint(_ point: CGPoint?) {
        self.lastPoint = point
    }

    func updatePanningStateIfNeeded(_ touches: [OMSTouchData]) {
        let states = touches.map { $0.state }
        let isPanning = touches.count == 4 && states.allSatisfy { $0 == .touching }

        guard isPanning != self.isPanning else {
            return
        }

        self.isPanning = isPanning
    }

    func updateLastTime(_ touches: [OMSTouchData]?) {
        guard let touches else {
            self.lastTime = nil
            return
        }

        guard let time = touches.first?.time else {
            return
        }

        self.lastTime = time
    }

    func currentVelocity(to currentPoint: CGPoint, at time: TimeInterval) -> Double? {
        guard let lastPoint = self.lastPoint,
              let lastTime = self.lastTime
        else {
            return nil
        }

        let deltaTime = time - lastTime
        let deltaLength = CGPoint.distance(from: lastPoint, to: currentPoint)

        return deltaLength / deltaTime
    }

    func interpretMovement(_ distance: CGFloat, axis: Axis, velocity: Double, time: TimeInterval) {
        let delta = Int(
            distance
                / (axis == .horizontal
                    ? self.actionDistanceThresholdHorizontal
                    : self.actionDistanceThresholdVertical))
        guard abs(delta) > 0 else {
            return
        }

        defer {
            self.updateStartPointIfNeeded(nil)
        }

        // If the time since the gesture start is less than 0.2, we
        // consider this to be a swipe.
        var isSwipe = velocity > self.swipeVelocityThreshold

        if let startTime = self.startTime {
            let durationSinceStart = time - startTime
            isSwipe = isSwipe && (durationSinceStart < self.swipeDurationThreshold)
        }

        // Don't register another swipe if we already did
        // during this gesture.
        guard !(isSwipe && self.swipeRegisteredAlready) else {
            return
        }

        if isSwipe {
            self.swipeRegisteredAlready = true
        }

        let direction =
            delta > 0
                ? (axis == .horizontal ? Direction.right : Direction.up)
                : (axis == .horizontal ? Direction.left : Direction.down)

        if isSwipe {
            self.delegate?.didSwipe(direction)
        } else {
            self.delegate?.didPan(direction)
        }
    }

    func registerHoldIfNeeded(time: TimeInterval) {
        guard !self.holdRegisteredAlready else {
            return
        }

        guard let startTime = self.startTime else {
            return
        }

        let durationSinceStart = time - startTime
        if durationSinceStart > self.swipeDurationThreshold {
            self.holdRegisteredAlready = true
            self.delegate?.isHolding()
        }
    }
}
