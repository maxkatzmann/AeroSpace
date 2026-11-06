# Integrated SpaceStation

This fork requires macOS 27. SpaceStation is enabled by default; AeroSpace's menu
contains a saved **Enable SpaceStation** toggle. Disabling it stops input capture
and restores AeroSpace's original label and workspace menu.

Hold Option for 500 ms to show the overlay. Option-scroll selects windows;
Option-Shift-scroll selects occupied workspaces plus the focused workspace, in
name order. Scrolling stops at the ends. Four-finger gestures retain their
existing navigation and haptic behavior. Press W while the overlay is visible to
close the focused window. Keep Option-W unbound in AeroSpace's configuration.
Clicking the plus switches to the next numeric workspace.

## Internal boundary

SpaceStationKit depends only on Apple frameworks and OpenMultitouchSupport 3.0.3.
The main-actor controller consumes immutable snapshots and emits typed actions;
its UInt64 window tokens are opaque. Presentation, gestures, input lifecycle,
remembered window selection, and preferences belong to the module. Snapshots
contain occupied workspaces plus the focused workspace, ordered by name, with
inhabited windows in AeroSpace tree traversal order. Blank/add slots are separate
presentation values. Repeated snapshots do not rebuild presentation state.

SpaceStationBridge is the only translator of AeroSpace model and command types.
Refresh completion hooks publish after normalization/layout. Startup and shutdown
hooks control the feature; UI helpers embed it into the existing menu. Actions
run through normal command sessions and revalidate window existence before use.
Wake and display changes request an ordinary host refresh. No command subprocess,
notification helper, extra Accessibility observer, or polling timer is involved.

For upstream syncs, review the bridge, refresh completion hooks, startup/termination
hooks, menu composition, session reason, and package/build wiring. Run both target
test suites and release validation. Keep the ordering and cache-waiter patches.
Do not introduce Common/AppBundle dependencies into SpaceStationKit.

## Migration and rollback

Before activation, back up the app/CLI, current workspace/window assignments and
order, configuration, and login-item setup. Quit standalone SpaceStation and
remove its login item and the on-focus-changed hook invoking its main helper.
Preserve other callbacks and the unbound Option-W setting. Launch the integrated
release and verify order and focus, the overlay, physical gestures, multiple
monitors, and repeated sleep/wake cycles. Automated tests cannot establish input
feel or wake recovery. Keep the standalone repository and binaries for rollback;
restore the old pair, callback, and login item together if necessary.

The release builder shares SwiftPM's resolved checkout directory with Xcode. A
pin-checked helper disables swift-collections 1.6.0's legacy Swift 6.0 manifest
in that ignored checkout, allowing Xcode to read the trait declarations in its
Swift 6.2 manifest. Keep the required UnstableHashedContainers trait; remove the
workaround when the dependency fixes its versioned manifest selection.
