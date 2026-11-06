@testable import SpaceStationKit
import XCTest
import CoreGraphics

@MainActor final class SpaceStationTests: XCTestCase {
    func controller(_ actions: @escaping @MainActor (SpaceStationAction) async -> SpaceStationActionResult = { _ in .success }) -> SpaceStation {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let c = SpaceStation(defaults: defaults, liveInput: false, perform: actions)
        c.displayRecovery.displays = { [] }
        return c
    }
    func state(_ ids: [UInt64], workspace: String = "1", focus: UInt64? = nil) -> SpaceStationSnapshot {
        SpaceStationSnapshot(workspaces: [WorkspaceSnapshot(name: workspace, windows: ids.map { WindowSnapshot(id: $0, pid: 0, bundleIdentifier: "same.app") })], focusedWorkspace: workspace, focusedWindow: focus, available: true, mode: nil, frame: .zero)
    }
    func testIdentityAndPresentation() {
        let c = controller(); c.update(snapshot: state([UInt64.max, 2], focus: UInt64.max))
        XCTAssertEqual(c.spaces[0].windows.compactMap(\.windowId), [UInt64.max, 2])
        XCTAssertEqual(c.nextWorkspace, "2")
        let old = c.spaces[0]; c.update(snapshot: state([UInt64.max, 2], focus: UInt64.max))
        XCTAssertTrue(c.spaces[0] === old)
        c.update(snapshot: state([], workspace: "9"))
        XCTAssertEqual(c.spaces.count, 1); XCTAssertEqual(c.nextWorkspace, "10")
        XCTAssertFalse(c.spacesRepresentation.isEmpty)
    }
    func presentationState(_ ids: [UInt64], focusedWorkspace: String = "1", focus: UInt64? = 2) -> SpaceStationSnapshot {
        SpaceStationSnapshot(workspaces: state([1, 2, 3, 4]).workspaces + state(ids, workspace: "4").workspaces,
                             focusedWorkspace: focusedWorkspace, focusedWindow: focus, available: true, mode: nil, frame: .zero)
    }
    func testUnvisitedSingleWindowWorkspaceCentersFirstWindow() throws {
        let c = controller(); c.update(snapshot: presentationState([5]))
        let row = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "4" })
        XCTAssertEqual(row.windows.count, 7)
        XCTAssertEqual(row.windows[3].windowId, 5)
        XCTAssertTrue(row.windows.prefix(3).allSatisfy(\.isBlank))
        XCTAssertTrue(row.windows.suffix(3).allSatisfy(\.isBlank))
    }
    func testUnvisitedMultipleWindowWorkspaceCentersFirstWindowWithoutRememberingIt() throws {
        let c = controller(); c.update(snapshot: presentationState([5, 6]))
        let row = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "4" })
        XCTAssertEqual(row.windows.count, 7)
        XCTAssertEqual(row.windows[3].windowId, 5)
        XCTAssertEqual(row.windows.compactMap(\.windowId), [5, 6])

        c.update(snapshot: presentationState([6, 5]))
        let reordered = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "4" })
        XCTAssertEqual(reordered.windows[3].windowId, 6)
        XCTAssertEqual(reordered.windows.compactMap(\.windowId), [6, 5])
    }
    func testRememberedWindowStaysCenteredAfterSwitchingWorkspace() throws {
        let c = controller()
        c.update(snapshot: presentationState([5, 6], focusedWorkspace: "4", focus: 6))
        c.update(snapshot: presentationState([5, 6]))
        let row = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "4" })
        XCTAssertEqual(row.windows.count, 7)
        XCTAssertEqual(row.windows[3].windowId, 6)
        XCTAssertEqual(row.windows.compactMap(\.windowId), [5, 6])
    }
    func testRemovedRememberedWindowFallsBackToFirstWindow() throws {
        let c = controller()
        c.update(snapshot: presentationState([5, 6], focusedWorkspace: "4", focus: 6))
        c.update(snapshot: presentationState([5, 6]))
        c.update(snapshot: presentationState([5]))
        let row = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "4" })
        XCTAssertEqual(row.windows.count, 7)
        XCTAssertEqual(row.windows[3].windowId, 5)
        XCTAssertEqual(row.windows.compactMap(\.windowId), [5])
    }
    func testEmptyWorkspaceKeepsBlankSlots() throws {
        let c = controller()
        c.update(snapshot: presentationState([], focusedWorkspace: "4", focus: nil))
        let row = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "4" })
        XCTAssertEqual(row.windows.count, 7)
        XCTAssertTrue(row.windows.allSatisfy(\.isBlank))

        c.update(snapshot: state([]))
        let onlyRow = try XCTUnwrap(c.spacesRepresentation.first { $0.name == "1" })
        XCTAssertEqual(onlyRow.windows.count, 1)
        XCTAssertTrue(onlyRow.windows.allSatisfy(\.isBlank))
    }
    func testScrollBoundariesAndClose() async {
        var actions: [SpaceStationAction] = []
        let c = controller { actions.append($0); return .success }
        c.update(snapshot: state([1, 2], focus: 1)); c.start()
        c.navigate(ScrollIntent(target: .window, step: -1)); await Task.yield()
        XCTAssertTrue(actions.isEmpty)
        c.closeFocused(); await Task.yield(); await Task.yield()
        XCTAssertEqual(actions, [.closeWindow(1)])
        c.stop(); c.closeFocused(); await Task.yield()
        XCTAssertEqual(actions.count, 1)
    }
    func testDisableAndWakeInvalidation() async {
        var actions: [SpaceStationAction] = []
        let c = controller { actions.append($0); return .unavailable }
        c.update(snapshot: state([1, 2], focus: 1)); c.start()
        c.navigate(ScrollIntent(target: .window, step: 1)); c.isEnabled = false
        await Task.yield(); XCTAssertTrue(actions.isEmpty)
        c.isEnabled = true; c.setSleeping(true); c.closeFocused()
        await Task.yield(); XCTAssertTrue(actions.isEmpty)
        c.displayRecovery.displays = { [DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 90))] }
        c.setSleeping(false)
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(actions, [.refreshState])
        c.stop(); c.stop()
    }
    func testConsumedCloseDeliveryAndRetiredWorker() async {
        var delivered = 0
        let worker = InputTapWorker { _, _, close in if close { delivered += 1 } }
        worker.capture.withLock { $0.close = true }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true)!
        XCTAssertNil(worker.handle(.keyDown, event))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(delivered, 1)
        worker.stop()
        XCTAssertNotNil(worker.handle(.keyDown, event))
        XCTAssertEqual(delivered, 1)
    }
    func testInterpreterThresholdMomentumAndBoundary() {
        var s = ScrollInterpreter()
        XCTAssertNil(s.interpret(x: 0, y: -20, precise: true, option: true, shift: false, unrelatedModifier: false, momentum: false, ended: false, time: 1).intent)
        XCTAssertEqual(s.interpret(x: 0, y: -20, precise: true, option: true, shift: false, unrelatedModifier: false, momentum: false, ended: false, time: 1.1).intent?.step, 1)
        XCTAssertNil(s.interpret(x: 0, y: -100, precise: true, option: true, shift: false, unrelatedModifier: false, momentum: true, ended: false, time: 1.3).intent)
        XCTAssertNil(OrderedNavigation.target(in: [1, 2], current: 2, step: 1))
    }
}
