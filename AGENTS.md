# Repository Guidelines

## Project Structure & Fork Policy

AeroSpace is a Swift 6.4 macOS tiling window manager. `Sources/AppBundle/` contains the app, commands, tree, and configuration; `Sources/Common/` is shared by the app and CLI; `Sources/Cli/` is the command-line entry point; and `Sources/AppBundleTests/` contains XCTest coverage. `xcode/` holds the generated Xcode project configuration, while `docs/`, `resources/`, and `script/` contain documentation, assets, and build helpers. Do not edit `ShellParserGenerated/` or `*Generated.swift` files directly.

This fork intentionally differs from `upstream/main` only by removing the app/title sort in `Sources/AppBundle/command/impl/ListWindowsCommand.swift`. That preserves tree traversal order for left-to-right tiling integrations. Keep this patch minimal; the `disable-window-sorting` stash is retained solely as historical reference. Sync upstream into a clean worktree and verify the final diff before promoting `main`.

## Build, Test, and Development Commands

- `./build-debug.sh` builds debug binaries in `.debug/`.
- `./test.sh` runs the Swift tests.
- `./format.sh` applies SwiftFormat and SwiftLint; `./lint.sh` also runs Periphery where supported.
- `./generate.sh` refreshes generated source and `xcode/AeroSpace.xcodeproj`.
- `./build-release.sh --codesign-identity '<identity>'` produces and validates `.release/` artifacts.

Release builds require a clean Git worktree: the script generates files and runs `git checkout .` before packaging. Use a separate worktree if the regular checkout has edits. Do not bypass the cleanliness check or hard-code a Homebrew Bash path.

## Local Toolchain Requirements

Use Bash 5+; upstream resolves it through `#!/usr/bin/env bash`. Install and initialize Swiftly, then install the version in `.swift-version` (currently `6.4.0`): `brew install swiftly`, `swiftly init --no-modify-profile --skip-install -y`, and `swiftly install 6.4.0`. Ensure Ruby 3.x precedes Ruby 4 on `PATH` for Bundler. On this Mac, release builds use Xcode 27.1 Beta and the existing Apple Development identity:

`DEVELOPER_DIR=/Applications/Xcode-27.1.0-Beta.app/Contents/Developer ./build-release.sh --codesign-identity 'Apple Development: Maximilian Katzmann (F9MNP366T2)'`

## Style, Tests, and Commits

Use four-space Swift indentation, PascalCase types, camelCase members, and repository formatting rules. Add focused XCTest coverage for new behavior, but avoid tests or refactors for this fork-only one-line ordering patch. Use atomic imperative commits, such as `Disable sorting in ListWindowsCommand`; keep unrelated generated or local build changes out of upstream-sync commits.
