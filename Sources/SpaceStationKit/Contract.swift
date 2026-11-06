import Foundation

public struct WindowSnapshot: Equatable, Sendable {
    public let id: UInt64
    public let pid: Int32
    public let bundleIdentifier: String?
    public init(id: UInt64, pid: Int32, bundleIdentifier: String?) {
        self.id = id; self.pid = pid; self.bundleIdentifier = bundleIdentifier
    }
}

public struct WorkspaceSnapshot: Equatable, Sendable {
    public let name: String
    public let windows: [WindowSnapshot]
    public init(name: String, windows: [WindowSnapshot]) { self.name = name; self.windows = windows }
}

public struct SpaceStationSnapshot: Equatable, Sendable {
    public let workspaces: [WorkspaceSnapshot]
    public let focusedWorkspace: String
    public let focusedWindow: UInt64?
    public let available: Bool
    public let mode: String?
    public let frame: CGRect
    public init(workspaces: [WorkspaceSnapshot], focusedWorkspace: String, focusedWindow: UInt64?, available: Bool, mode: String?, frame: CGRect) {
        self.workspaces = workspaces; self.focusedWorkspace = focusedWorkspace; self.focusedWindow = focusedWindow
        self.available = available; self.mode = mode; self.frame = frame
    }
}

public enum FocusDirection: String, Sendable { case left, right, up, down }
public enum SpaceStationAction: Equatable, Sendable {
    case focusWindow(UInt64), switchWorkspace(String), closeWindow(UInt64), focusDirection(FocusDirection), refreshState
}
public enum SpaceStationActionResult: Equatable, Sendable { case success, unavailable, failure(String) }
