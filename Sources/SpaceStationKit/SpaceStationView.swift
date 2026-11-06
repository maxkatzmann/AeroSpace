import SwiftUI

private enum SwitcherMetrics {
    static let appIconSize: CGFloat = 124
    static let appIconPadding: CGFloat = 0
    static let appSlotSize: CGFloat = 128
    static let addSlotSize: CGFloat = 56
    static let selectedIndicatorCornerRadius: CGFloat = 28
}

enum WorkspaceLayer {
    case groupIndicators
    case icons
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct WindowView: View {
    let window: Window
    let spaceStation: SpaceStation
    @State private var isHovering = false
    private var iconSize: CGFloat { window.isAddButton ? 32 : SwitcherMetrics.appIconSize }
    private var iconPadding: CGFloat { window.isAddButton ? 0 : SwitcherMetrics.appIconPadding }
    private var slotSize: CGFloat {
        window.isAddButton ? SwitcherMetrics.addSlotSize : SwitcherMetrics.appSlotSize
    }

    // Since clicks can turn into a drag easily, we additionally
    // enable selection upon drag end.
    var drag: some Gesture {
        DragGesture()
            .onEnded { _ in
                didClick()
            }
    }

    var body: some View {
        if window.isBlank {
            Color.clear
        } else {
            Button {
                didClick()
            } label: {
                appIcon
                    .frame(width: iconSize, height: iconSize)
                    .padding(iconPadding)
                    .brightness(isHovering ? 0.12 : 0)
                    .scaleEffect(isHovering ? 1.03 : 1)
                    .animation(.easeOut(duration: 0.12), value: isHovering)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(window.appBundleId)
            .frame(width: slotSize, height: slotSize)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(drag)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let app = NSRunningApplication(processIdentifier: window.pid) ?? NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == window.appBundleId
        }), let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: window.appBundleId)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(window.isAddButton ? 0 : 18)
        }
    }

    private func didClick() {
        spaceStation.focus(window: window)
        spaceStation.didRelease()
    }
}

struct CurrentAppIndicator: View {
    var body: some View {
        Color.clear
            .frame(
                width: SwitcherMetrics.appIconSize + (2 * SwitcherMetrics.appIconPadding),
                height: SwitcherMetrics.appIconSize + (2 * SwitcherMetrics.appIconPadding),
            )
            .glassEffect(
                .regular.tint(Color.white.opacity(0.95)),
                in: .rect(cornerRadius: SwitcherMetrics.selectedIndicatorCornerRadius),
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: SwitcherMetrics.selectedIndicatorCornerRadius,
                    style: .continuous,
                )
                .strokeBorder(.white.opacity(0.12))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct WindowGroupView: View {
    let windows: [Window]
    let spaceStation: SpaceStation
    let layer: WorkspaceLayer

    private var containsAppWindows: Bool {
        windows.contains(where: { !$0.isBlank && !$0.isAddButton })
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                groupSlot(for: window)
                    .frame(width: window.isAddButton ? SwitcherMetrics.addSlotSize : SwitcherMetrics.appSlotSize,
                           height: window.isAddButton ? SwitcherMetrics.addSlotSize : SwitcherMetrics.appSlotSize)
            }
        }
        .background {
            if layer == .groupIndicators && containsAppWindows {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(.white.opacity(0.10))
                    }
                    // This expands the visible platter without changing the slot layout.
                    .padding(-12)
            }
        }
    }

    @ViewBuilder
    private func groupSlot(for window: Window) -> some View {
        if layer == .icons {
            WindowView(window: window, spaceStation: spaceStation)
        } else {
            Color.clear
        }
    }
}

struct SpaceView: View {
    @ObservedObject var space: Space
    @Binding var scrollOffset: CGPoint
    let spaceStation: SpaceStation
    let layer: WorkspaceLayer
    let scrollFactor: CGFloat = 50.0

    var body: some View {
        HStack(spacing: 12) {
            let groups = groupContinuousWindows(space.windows)

            ForEach(Array(groups.enumerated()), id: \.offset) { _, windowGroup in
                WindowGroupView(
                    windows: windowGroup,
                    spaceStation: spaceStation,
                    layer: layer,
                )
            }
        }
        .frame(height: SwitcherMetrics.appSlotSize)
        .offset(x: space.isFocused ? scrollOffset.x * scrollFactor : 0)
    }

    private func groupContinuousWindows(_ windows: [Window]) -> [[Window]] {
        let firstNonBlankIndex = windows.firstIndex(where: { !$0.isBlank })
        let lastNonBlankIndex = windows.lastIndex(where: { !$0.isBlank })

        guard let firstNonBlankIndex, let lastNonBlankIndex else {
            return [windows]
        }

        var groups: [[Window]] = []
        if firstNonBlankIndex > 0 {
            groups.append(Array(windows[0 ..< firstNonBlankIndex]))
        }

        groups.append(Array(windows[firstNonBlankIndex ... lastNonBlankIndex]))

        if lastNonBlankIndex < windows.count - 1 {
            groups.append(Array(windows[(lastNonBlankIndex + 1)...]))
        }

        return groups
    }
}

struct SpaceStationView: View {
    @EnvironmentObject var spaceStation: SpaceStation
    let scrollFactor: CGFloat = 75.0

    private var hasFocusedWindow: Bool {
        spaceStation.spaces.contains { space in
            space.windows.contains { $0.isFocused }
        }
    }

    @ViewBuilder
    private func workspaceContent(layer: WorkspaceLayer, geometry: GeometryProxy) -> some View {
        VStack(spacing: 40) {
            ForEach(Array(spaceStation.spacesRepresentation.enumerated()), id: \.offset) { _, space in
                SpaceView(
                    space: space,
                    scrollOffset: $spaceStation.scrollOffset,
                    spaceStation: spaceStation,
                    layer: layer,
                )
            }
        }
        .offset(y: -spaceStation.scrollOffset.y * scrollFactor)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        .clipped()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)

                workspaceContent(layer: .groupIndicators, geometry: geometry)

                // The selected app scrolls with its workspace; its glass well stays fixed at center.
                if hasFocusedWindow {
                    CurrentAppIndicator()
                }

                workspaceContent(layer: .icons, geometry: geometry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
