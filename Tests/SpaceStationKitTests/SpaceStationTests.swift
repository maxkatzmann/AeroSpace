@testable import SpaceStationKit
import XCTest

@MainActor final class SpaceStationTests: XCTestCase {
    func controller(_ actions: @escaping @MainActor (SpaceStationAction) async -> SpaceStationActionResult = { _ in .success }) -> SpaceStation {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return SpaceStation(defaults: defaults, liveInput: false, perform: actions)
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
        c.setSleeping(false); await Task.yield(); await Task.yield()
        XCTAssertEqual(actions, [.refreshState])
        c.stop(); c.stop()
    }
    func testInterpreterThresholdMomentumAndBoundary() {
        var s = ScrollInterpreter()
        XCTAssertNil(s.interpret(x: 0, y: -20, precise: true, option: true, shift: false, unrelatedModifier: false, momentum: false, ended: false, time: 1).intent)
        XCTAssertEqual(s.interpret(x: 0, y: -20, precise: true, option: true, shift: false, unrelatedModifier: false, momentum: false, ended: false, time: 1.1).intent?.step, 1)
        XCTAssertNil(s.interpret(x: 0, y: -100, precise: true, option: true, shift: false, unrelatedModifier: false, momentum: true, ended: false, time: 1.3).intent)
        XCTAssertNil(OrderedNavigation.target(in: [1, 2], current: 2, step: 1))
    }
}
