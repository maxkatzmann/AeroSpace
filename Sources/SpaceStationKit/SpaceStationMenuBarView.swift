import SwiftUI

struct SpaceStationMenuBarView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var space: Space

    var name: String { space.name }
    var windows: [Window] { space.windows }

    var body: some View {
        let renderer = ImageRenderer(
            content:
            HStack {
                SpaceIndicator(name: name)
                Spacer(minLength: 20.0)
                ForEach(Array(windows.enumerated()), id: \.offset) {
                    index,
                    window in
                    WindowIndicator(
                        bundleIdentifier: window.appBundleId,
                        pid: window.pid,
                        focussed: window.isFocused,
                    )
                }
            }
            .foregroundStyle(colorScheme == .light ? Color.black : Color.white),
        )
        if let cgImage = renderer.cgImage {
            // Using scale: 1 results in a blurry image for unknown reasons
            Image(cgImage, scale: 2, label: Text("?"))
        } else {
            // In case image can't be rendered fallback to plain text
            Text("?")
        }
    }
}

struct SpaceIndicator: View {
    let name: String

    var body: some View {
        Group {
            switch name {
                case "1":
                    Image(systemName: "house")
                case "2":
                    Image(systemName: "message")
                case "3":
                    Image(systemName: "hammer")
                case "4":
                    Image(systemName: "hourglass")
                case _: Text(name)
            }
        }
        .font(.system(.largeTitle))
        .foregroundStyle(Color.white)
    }
}

struct WindowIndicator: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    let bundleIdentifier: String
    let pid: Int32
    let focussed: Bool

    var body: some View {
        VStack(spacing: 2.5) {
            if let app = NSRunningApplication(processIdentifier: pid) ?? NSWorkspace.shared.runningApplications.first(where: {
                   $0.bundleIdentifier == bundleIdentifier
               }),
               let icon = app.icon
            {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            Rectangle()
                .fill(focussed ? Color.white : Color.white.opacity(0.25))
                .frame(height: 5)
                .cornerRadius(2)
        }
    }
}
