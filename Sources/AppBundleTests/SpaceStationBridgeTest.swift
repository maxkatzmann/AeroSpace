@testable import AppBundle
import Common
import SpaceStationKit
import XCTest

@MainActor final class SpaceStationBridgeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    func testSnapshotPreservesTraversalAndWideIds() {
        let workspace = Workspace.get(byName: "1")
        config.accordionPadding = 0
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        let first = TestWindow.new(id: OpaqueWindowId(UInt64.max), parent: root)
        let nested = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1)
        TestWindow.new(id: 6, parent: nested)
        TestWindow.new(id: 5, parent: nested)
        TestWindow.new(id: 2, parent: root).lifeStatus = .dead
        TestWindow.new(id: 3, parent: root).lifeStatus = .invisible
        TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer)
        TestWindow.new(id: 7, parent: workspace.macOsNativeFullscreenWindowsContainer)
        XCTAssertTrue(first.focusWindow())
        let snapshot = SpaceStationBridge.makeSnapshot()
        XCTAssertEqual(snapshot.focusedWindow, UInt64.max)
        XCTAssertEqual(snapshot.workspaces.first { $0.name == "1" }?.windows.map(\.id), [UInt64.max, 6, 5, 4, 7])
        XCTAssertEqual(SpaceStationBridge.commandArguments(.focusWindow(UInt64.max)), ["focus", "--window-id", String(UInt64.max)])
    }
    func testEmptyFocusedWorkspaceAndNameOrder() {
        let w = TestWindow.new(id: 1, parent: Workspace.get(byName: "2").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "10").rootTilingContainer)
        XCTAssertTrue(w.focusWindow())
        XCTAssertEqual(SpaceStationBridge.makeSnapshot().workspaces.map(\.name), ["2", "10"])
        XCTAssertTrue(Workspace.get(byName: "3").focusWorkspace())
        XCTAssertEqual(SpaceStationBridge.makeSnapshot().workspaces.map(\.name), ["2", "3", "10"])
    }
}
