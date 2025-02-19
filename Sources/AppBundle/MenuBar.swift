import Common
import Foundation
import SwiftUI

public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") { identification.copyToClipboard() }
            .keyboardShortcut("C", modifiers: .command)
        Divider()
        if viewModel.isEnabled {
            Text("Workspaces:")
            ForEach(viewModel.workspaces, id: \.name) { workspace in
                Button {
                    refreshSession(.menuBarButton, screenIsDefinitelyUnlocked: true) {
                        _ = Workspace.get(byName: workspace.name).focusWorkspace()
                    }
                } label: {
                    Toggle(isOn: .constant(workspace.isFocused)) {
                        Text(workspace.name + workspace.suffix).font(
                            .system(.body, design: .monospaced)
                        )
                    }
                }
            }
            Divider()
        }
        Button(viewModel.isEnabled ? "Disable" : "Enable") {
            refreshSession(.menuBarButton, screenIsDefinitelyUnlocked: true) {
                _ = EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle)).run(
                    .defaultEnv,
                    .emptyStdin
                )
            }
        }.keyboardShortcut("E", modifiers: .command)
        let editor = getTextEditorToOpenConfig()
        Button("Open config in '\(editor.lastPathComponent)'") {
            let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(
                path: configDotfileName
            )
            switch findCustomConfigUrl() {
            case .file(let url):
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(
                    atPath: defaultConfigUrl.path,
                    toPath: fallbackConfig.path
                )
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
            }
        }.keyboardShortcut("O", modifiers: .command)
        if viewModel.isEnabled {
            Button("Reload config") {
                refreshSession(.menuBarButton, screenIsDefinitelyUnlocked: true) {
                    _ = reloadConfig()
                }
            }.keyboardShortcut("R", modifiers: .command)
        }
        Button("Quit \(aeroSpaceAppName)") {
            terminationHandler.beforeTermination()
            terminateApp()
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        if viewModel.isEnabled {
            WindowIconList(
                workspaceDisplayInfo: Workspace.get(byName: viewModel.trayText).displayInfo
            )
        }
        else {
            Text("?")
        }
    }
}

struct SpaceIndicator: View {
    let name: String

    var body: some View {
        switch name {
        case "1":
            Image(systemName: "house")
                .font(.system(.largeTitle))
        case "2":
            Image(systemName: "message")
                .font(.system(.largeTitle))
        case "3":
            Image(systemName: "hammer")
                .font(.system(.largeTitle))
        case "4":
            Image(systemName: "hourglass")
                .font(.system(.largeTitle))
        case _: Text(name).font(.system(.largeTitle))
        }
    }
}

struct WindowIconList: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var workspaceDisplayInfo: WorkspaceDisplayInfo

    var name: String { workspaceDisplayInfo.name }
    var bundleIdentifiers: [String] { workspaceDisplayInfo.bundleIdentifiers }
    var focussedIndex: Int? { workspaceDisplayInfo.indexOfFocussed }

    var body: some View {
        let renderer = ImageRenderer(
            content:
                HStack {
                    SpaceIndicator(name: name)
                    Spacer(minLength: 20.0)
                    ForEach(Array(bundleIdentifiers.enumerated()), id: \.offset) {
                        index,
                        bundleIdentifier in
                        WindowIndicator(
                            bundleIdentifier: bundleIdentifier,
                            focussed: index == focussedIndex
                        )
                    }
                }
                .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
        )
        if let cgImage = renderer.cgImage {
            // Using scale: 1 results in a blurry image for unknown reasons
            Image(cgImage, scale: 2, label: Text("?"))
        }
        else {
            // In case image can't be rendered fallback to plain text
            Text("?")
        }
    }
}

struct WindowIndicator: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    let bundleIdentifier: String
    let focussed: Bool

    var body: some View {
        VStack(spacing: 2.5) {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
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

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(
        toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl
    )?
    .takeIf { $0.lastPathComponent != "Xcode.app" }  // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
