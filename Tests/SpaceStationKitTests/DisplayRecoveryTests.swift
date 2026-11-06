@testable import SpaceStationKit
import AppKit
import XCTest

@MainActor final class DisplayRecoveryTests: XCTestCase {
    func geometry(_ id: UInt32 = 1, width: CGFloat = 1920, visibleHeight: CGFloat = 1000) -> DisplayGeometry {
        DisplayGeometry(id: id, frame: CGRect(x: 0, y: 0, width: width, height: 1080),
                        visibleFrame: CGRect(x: 0, y: 0, width: width, height: visibleHeight))
    }

    @MainActor final class Host {
        var displays: [DisplayGeometry] = []
        var calls = 0
        var recovered = 0
        var completion: CheckedContinuation<SpaceStationActionResult, Never>?
        var arrival: CheckedContinuation<Void, Never>?
        lazy var recovery = DisplayRecovery(perform: { [self] in
            calls += 1
            return await withCheckedContinuation { continuation in
                completion = continuation
                arrival?.resume(); arrival = nil
            }
        }, recovered: { [self] in recovered += 1 })

        func start() {
            recovery.displays = { [self] in displays }
            recovery.update(available: true)
            recovery.start()
        }
        func nextCall() async {
            if completion != nil { return }
            await withCheckedContinuation { arrival = $0 }
        }
        func finish(_ result: SpaceStationActionResult = .success) async {
            let continuation = completion; completion = nil
            continuation?.resume(returning: result)
            for _ in 0 ..< 10 { await Task.yield() }
        }
    }

    func testGeometryChangesAndInvalidSnapshots() async {
        let h = Host(); h.displays = [geometry()]; h.start()
        await h.nextCall(); await h.finish()
        XCTAssertEqual(h.recovered, 1)
        h.recovery.check(); await Task.yield()
        XCTAssertEqual(h.calls, 1)
        for displays in [[geometry(2)], [geometry(2, width: 1440)],
                         [geometry(2, width: 1440, visibleHeight: 900)],
                         [geometry(2), geometry(3)], [geometry(3), geometry(2)]]
        {
            h.displays = displays; h.recovery.check()
            await h.nextCall(); await h.finish()
        }
        XCTAssertEqual(h.calls, 6)
        h.displays = []; h.recovery.request(); await Task.yield()
        XCTAssertEqual(h.calls, 6)
        h.displays = [geometry(width: .infinity)]; h.recovery.check(); await Task.yield()
        XCTAssertEqual(h.calls, 6)
        h.displays = [geometry()]; h.recovery.check()
        await h.nextCall(); await h.finish()
        XCTAssertEqual(h.recovered, 7)
        h.recovery.stop()
    }

    func testChangesDuringRefreshAndFailedAttempt() async {
        let h = Host(); h.displays = [geometry()]; h.start(); await h.nextCall()
        h.displays = [geometry(width: 1440)]; h.recovery.check()
        await h.finish(); await h.nextCall()
        XCTAssertEqual(h.calls, 2); XCTAssertEqual(h.recovered, 0)
        await h.finish(.unavailable)
        XCTAssertEqual(h.calls, 2)
        h.recovery.update(available: false); h.recovery.check(); await Task.yield()
        XCTAssertEqual(h.calls, 2)
        h.recovery.update(available: true); await h.nextCall(); await h.finish()
        XCTAssertEqual(h.recovered, 1)
        h.recovery.check(); await Task.yield(); XCTAssertEqual(h.calls, 3)
        h.recovery.stop()
    }

    func testSleepCancellationAndRestartIgnoreRetiredCompletions() async {
        let h = Host(); h.displays = [geometry()]; h.start(); await h.nextCall()
        h.recovery.setSleeping(true)
        h.displays = [geometry(width: 1440)]; h.recovery.check()
        await h.finish()
        XCTAssertEqual(h.recovered, 0); XCTAssertEqual(h.calls, 1)
        h.recovery.setSleeping(false); h.recovery.setSleeping(false)
        await h.nextCall()
        h.recovery.stop(); h.recovery.start()
        await h.finish(); await h.nextCall()
        XCTAssertEqual(h.recovered, 0); XCTAssertEqual(h.calls, 3)
        await h.finish(); XCTAssertEqual(h.recovered, 1)
        h.recovery.stop()
    }

    func testRecoveryWithInterfaceDisabledAndIndependentNavigation() async {
        let h = Host(); h.displays = [geometry()]
        var navigation = 0
        let c = SpaceStation(defaults: UserDefaults(suiteName: UUID().uuidString)!, liveInput: false) { action in
            if action == .refreshState { return await h.recoveryPerform() }
            navigation += 1
            return .success
        }
        c.displayRecovery.displays = { h.displays }
        c.update(snapshot: SpaceStationSnapshot(workspaces: [], focusedWorkspace: "1", focusedWindow: nil,
                                                available: true, mode: nil, frame: .zero))
        c.start(); c.isEnabled = false
        await h.nextCall()
        c.isEnabled = true
        c.submit(.focusDirection(.right))
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(navigation, 1) // Navigation can proceed while recovery is suspended in the host.
        c.update(snapshot: c.snapshot!) // An unrelated host publication cannot finish wake recovery.
        c.setSleeping(true); c.setSleeping(false)
        await h.finish(); await h.nextCall()
        c.update(snapshot: c.snapshot!)
        c.submit(.focusDirection(.right))
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(navigation, 1) // Host publications do not release the wake gate.
        await h.finish()
        c.submit(.focusDirection(.right))
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(navigation, 2)
        XCTAssertEqual(h.calls, 2)
        c.stop()
    }
}

extension DisplayRecoveryTests.Host {
    fileprivate func recoveryPerform() async -> SpaceStationActionResult {
        calls += 1
        return await withCheckedContinuation { continuation in
            completion = continuation
            arrival?.resume(); arrival = nil
        }
    }
}
