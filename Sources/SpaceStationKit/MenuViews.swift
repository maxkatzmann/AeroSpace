import SwiftUI

public struct SpaceStationLabel: View {
    @ObservedObject private var controller: SpaceStation
    public init(controller: SpaceStation) { self.controller = controller }
    public var body: some View {
        HStack {
            if let mode = controller.snapshot?.mode { Text("(\(mode.uppercased()))") }
            if let space = controller.spaces.first(where: \.isFocused) { SpaceStationMenuBarView(space: space) }
        }
    }
}
public struct SpaceStationWorkspaceMenu: View {
    @ObservedObject private var controller: SpaceStation
    public init(controller: SpaceStation) { self.controller = controller }
    public var body: some View {
        ForEach(controller.spaces, id: \.name) { space in
            Button { controller.submit(.switchWorkspace(space.name)) } label: { SpaceStationMenuBarView(space: space) }
        }
    }
}
public struct SpaceStationToggle: View {
    @ObservedObject private var controller: SpaceStation
    public init(controller: SpaceStation) { self.controller = controller }
    public var body: some View { Toggle("Enable SpaceStation", isOn: $controller.isEnabled) }
}
