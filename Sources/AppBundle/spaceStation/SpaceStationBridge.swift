import AppKit
import Common
import SpaceStationKit
import SwiftUI

@MainActor final class SpaceStationBridge {
    static let shared = SpaceStationBridge()
    let controller: SpaceStation
    private var started = false
    private init() {
        controller = SpaceStation { action in await SpaceStationBridge.perform(action) }
    }
    func start() { started = true; publish(); controller.start() }
    func stop() { started = false; controller.stop() }
    func publish() { if started { controller.update(snapshot: Self.makeSnapshot()) } }
    static func makeSnapshot() -> SpaceStationSnapshot {
        let focus = globalFocus
        let monitor = focus.workspace.workspaceMonitorInfo
        let screen = NSScreen.screens.getOrNil(atIndex: monitor.monitorAppKitNsScreenScreensId - 1)
        let workspaces = Workspace.all.map { workspace in
            WorkspaceSnapshot(name: workspace.name, windows: workspace.allInhabitedLeafWindowsRecursive.filter(\.isBound).map {
                WindowSnapshot(id: $0.windowId.rawId, pid: $0.app.pid, bundleIdentifier: $0.app.rawAppBundleId)
            })
        }.filter { !$0.windows.isEmpty || $0.name == focus.workspace.name }.sorted(using: KeyPathComparator(\.name))
        return SpaceStationSnapshot(workspaces: workspaces, focusedWorkspace: focus.workspace.name,
                                    focusedWindow: focus.windowOrNil?.windowId.rawId,
                                    available: TrayMenuModel.shared.isEnabled && !serverArgs.isReadOnly && TrayMenuModel.shared.axPermissionStatus == .granted,
                                    mode: activeMode.flatMap { $0 == mainModeId ? nil : $0 },
                                    frame: screen?.visibleFrame ?? .zero)
    }
    static func commandArguments(_ action: SpaceStationAction) -> [String]? {
        switch action {
            case .focusWindow(let id): ["focus", "--window-id", String(id)]
            case .closeWindow(let id): ["close", "--window-id", String(id)]
            case .switchWorkspace(let name): ["workspace", name]
            case .focusDirection(let direction): ["focus", direction.rawValue]
            case .refreshState: nil
        }
    }
    private static func perform(_ action: SpaceStationAction) async -> SpaceStationActionResult {
        guard let token = RunSessionGuard.isServerEnabled, !serverArgs.isReadOnly else { return .unavailable }
        if action == .refreshState {
            guard TrayMenuModel.shared.axPermissionStatus == .granted, !Task.isCancelled else { return .unavailable }
            let infos = globalUnsortedMonitorInfos
            guard !infos.isEmpty, infos.allSatisfy({ $0.width > 0 && $0.height > 0 && $0.visibleRect.width > 0 && $0.visibleRect.height > 0 }) else { return .unavailable }
            gcMonitors(force: true, monitorInfos: infos)
            let completed = await runHeavyCompleteRefreshSession(.spaceStation, assumeCancellable: true)
            return completed && !Task.isCancelled ? .success : .unavailable
        }
        guard let args = commandArguments(action), let command = parseCommand(args).cmdOrNil else { return .failure("Invalid action") }
        do {
            return try await runLightSession(.spaceStation, token) {
                guard TrayMenuModel.shared.isEnabled, !serverArgs.isReadOnly else { return .unavailable }
                switch action {
                    case .focusWindow(let id), .closeWindow(let id):
                        guard let window = Window.get(byId: OpaqueWindowId(id)), window.isBound, window.lifeStatus.isInhabited else { return .unavailable }
                    default: break
                }
                let result = await command.run(.defaultEnv, .emptyStdin)
                return result.exitCode.rawValue == 0 ? .success : .failure(result.stderr.joined(separator: "\n"))
            }
        } catch { return .failure(error.localizedDescription) }
    }
}

@MainActor struct IntegratedSpaceStationLabel: View {
    @ObservedObject var controller = SpaceStationBridge.shared.controller
    var body: some View {
        if controller.isPresenting { SpaceStationLabel(controller: controller) }
        else { MenuBarLabel().environmentObject(TrayMenuModel.shared) }
    }
}
@MainActor struct IntegratedSpaceStationMenu: View {
    @ObservedObject var controller = SpaceStationBridge.shared.controller
    @ObservedObject var model = TrayMenuModel.shared
    var body: some View {
        if controller.isPresenting { SpaceStationWorkspaceMenu(controller: controller) }
        else {
            ForEach(model.workspaces, id: \.name) { workspace in
                Button {
                    Task.startUnstructured {
                        guard let token = RunSessionGuard.isServerEnabled else { return }
                        try await runLightSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
                    }
                } label: {
                    Toggle(isOn: .constant(workspace.isFocused)) {
                        Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }
}
@MainActor struct IntegratedSpaceStationToggle: View {
    var body: some View { SpaceStationToggle(controller: SpaceStationBridge.shared.controller) }
}
