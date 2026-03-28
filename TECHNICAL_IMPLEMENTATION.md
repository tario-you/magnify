# Magnify Technical Implementation

## Product Summary

Magnify is a macOS menu bar utility with one job:

- In `Edit Mode`, show a movable and resizable floating glass pane that defines a capture region.
- In `Presentation Mode`, hide the pane and show a second full-screen window that renders the selected region live, enlarged to fill the display.
- Toggle between modes with `Command + Option + M`.

This is not a cursor-following magnifier. It is a fixed-region live presenter.

The selected region is defined by the edit-mode window frame. Presentation mode then treats that frame as the source crop and scales it to the active display.

## User Experience

### Launch

- The app launches as a menu bar utility.
- No Dock icon is required.
- On first launch, if Screen Recording permission is missing, the app shows a single permission window and blocks mode entry until permission is granted.

### Edit Mode

Edit mode is the setup state.

- Show a borderless floating window with a very light translucent fill.
- No title bar, buttons, toolbar, or visible controls.
- The pane is draggable from anywhere inside it.
- The pane is resizable from invisible edge and corner hit zones.
- The pane stays above normal windows so the user can place it precisely.
- The pane should look like a plane of glass, not a normal app window.

Recommended styling:

- Background: white or neutral tint at low alpha
- Border: 1 px or 2 px subtle stroke
- Shadow: soft and shallow
- Corner radius: small, not fully rounded

This is the only visible UI in edit mode.

### Presentation Mode

Presentation mode is the output state.

- Hide the edit pane.
- Show a full-screen borderless window on the target display.
- Render the selected region from edit mode live into that window.
- The presentation window ignores mouse events so the user can keep interacting with the underlying app.
- No overlays, no buttons, no status text in the presentation window.

The presentation output should use `aspectFill` by default so the selected region fills the display cleanly. Do not stretch the content.

### Toggle

`Command + Option + M` performs a strict two-state toggle:

1. `Edit Mode` -> `Presentation Mode`
2. `Presentation Mode` -> `Edit Mode`

There is no third mode in v1.

## Product Constraints

- The app must not capture its own windows.
- The presentation window must be click-through.
- The edit pane must remain easy to grab even though it has no chrome.
- The selected region should persist between launches.
- The transition must be fast enough to feel immediate.

## Platform and Frameworks

- Language: Swift
- UI framework: AppKit
- Capture framework: ScreenCaptureKit
- Rendering: Core Animation for v1, Metal optional later
- Hotkey registration: HIToolbox `RegisterEventHotKey`
- Persistence: `UserDefaults`

Recommended deployment target:

- macOS 13.0+

That gives a practical baseline for ScreenCaptureKit without carrying legacy support complexity.

## App Structure

Recommended modules:

- `App/AppDelegate.swift`
- `App/AppCoordinator.swift`
- `Mode/ModeController.swift`
- `Hotkey/GlobalHotkeyManager.swift`
- `Permissions/PermissionsManager.swift`
- `Selection/SelectionWindowController.swift`
- `Selection/SelectionView.swift`
- `Presentation/PresentationWindowController.swift`
- `Presentation/PresentationView.swift`
- `Capture/CaptureEngine.swift`
- `Capture/ScreenCaptureKitEngine.swift`
- `Display/DisplayResolver.swift`
- `State/AppState.swift`
- `Persistence/SettingsStore.swift`

## Architecture Overview

### Core Objects

#### `AppCoordinator`

Owns top-level lifecycle.

Responsibilities:

- App startup
- Permission gate
- Creating the menu bar item
- Wiring the hotkey manager
- Creating the mode controller

#### `ModeController`

Owns application mode and transitions.

Responsibilities:

- Track current mode
- Enter edit mode
- Enter presentation mode
- Validate source region before transition
- Coordinate the two windows and the capture engine

#### `SelectionWindowController`

Owns the edit-mode pane.

Responsibilities:

- Create the frameless floating window
- Support drag and resize
- Publish current selected screen rect
- Persist frame changes

#### `PresentationWindowController`

Owns the presentation output window.

Responsibilities:

- Create a borderless screen-sized window
- Keep it above normal content
- Ignore mouse events
- Host the rendering view

#### `CaptureEngine`

Abstract protocol around live screen capture.

Responsibilities:

- Start capture for a display
- Update crop source rect
- Deliver frames
- Stop capture cleanly

#### `ScreenCaptureKitEngine`

Primary implementation of `CaptureEngine`.

Responsibilities:

- Build the display capture stream
- Exclude app windows from capture
- Deliver the latest frame to the presenter

#### `DisplayResolver`

Maps app geometry to display geometry.

Responsibilities:

- Resolve which display contains most of the selection rect
- Convert `NSScreen` and `CGDisplay` coordinates
- Clamp crop rects to display bounds

#### `GlobalHotkeyManager`

Registers and handles the global toggle shortcut.

Responsibilities:

- Register `Cmd + Opt + M`
- Deliver a callback into `ModeController`
- Re-register cleanly if future shortcut customization is added

## State Model

Use a small explicit state machine.

```swift
enum AppMode {
    case blockedByPermissions
    case edit
    case presenting
}
```

Rules:

- The app starts in `blockedByPermissions` if Screen Recording is not granted.
- Otherwise it starts in `edit`.
- The hotkey toggles only between `edit` and `presenting`.
- If capture fails while presenting, fall back to `edit` and surface the error in the menu bar or a lightweight alert.

## Window Design

### Selection Window

Use an `NSPanel` or `NSWindow` configured as:

- `styleMask`: `.borderless`
- `isOpaque = false`
- `backgroundColor = .clear`
- `hasShadow = false` at the window level; draw shadow in view layers for control
- `level = .floating`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`

The content view supplies the visible glass treatment.

The window should accept mouse events in edit mode because the user must drag and resize it.

#### Selection View Interaction Model

The selection view handles hit testing manually.

Zones:

- Interior: drag
- Left, right, top, bottom edges: edge resize
- Four corners: corner resize

Suggested edge thickness:

- 12 pt hit zone

Suggested behavior:

- Cursor updates for resize directions are optional for v1 but useful
- Minimum size should be enforced to prevent degenerate rects
- The pane frame should snap only by normal AppKit behavior; no custom magnetic snapping in v1

### Presentation Window

Use a second `NSWindow` configured as:

- `styleMask`: `.borderless`
- `isOpaque = true`
- `backgroundColor = .black`
- `level = .screenSaver` or tested equivalent high level
- `ignoresMouseEvents = true`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`

Important:

- Use a normal borderless full-screen-sized window, not macOS native full-screen Spaces mode.
- This makes toggling faster and avoids Space transitions.

The presentation window should size itself to the target screen's frame, not merely the visible frame, because the output should cover the entire display.

## Mode Transition Logic

### Enter Edit Mode

1. Stop or pause presentation rendering.
2. Hide the presentation window.
3. Show the selection window using the last saved frame.
4. Make the selection window key if needed for immediate drag/resize behavior.
5. Keep capture stopped unless you explicitly choose to keep a warm stream alive.

### Enter Presentation Mode

1. Read the current selection window frame in global screen coordinates.
2. Resolve the target display from that frame.
3. Validate that the selected rect intersects the target display with a non-zero size.
4. Hide the selection window.
5. Create or show the presentation window on that display.
6. Start the capture engine for the target display.
7. Feed the selected crop rect into the renderer.
8. Present the scaled output full-screen.

### Toggle Pseudocode

```swift
func toggleMode() {
    switch appMode {
    case .blockedByPermissions:
        permissionsManager.promptForScreenRecording()
    case .edit:
        enterPresentationMode()
    case .presenting:
        enterEditMode()
    }
}
```

## Screen Capture Design

### Why ScreenCaptureKit

This app needs a live, low-latency display stream. ScreenCaptureKit is the right primary backend because it is the current Apple framework for high-performance screen capture on macOS.

The app should capture the full target display and crop in-process rather than trying to rebuild capture configuration every time the selected rect changes.

That is the right trade:

- simpler stream lifecycle
- less configuration churn
- better transition behavior
- easier future support for animating the selection rect

### Capture Flow

1. Query shareable content.
2. Resolve the selected `SCDisplay` for the target screen.
3. Build an `SCContentFilter` for that display.
4. Exclude the app's own windows from capture.
5. Create an `SCStreamConfiguration`.
6. Create and start `SCStream`.
7. Receive frames on a dedicated sample queue.
8. Hand the latest frame to the presentation renderer.

### Frame Ownership Rule

Use a `latest frame wins` policy.

- Never queue many frames.
- If rendering is behind, drop older frames.
- This app values freshness over completeness.

## Crop and Scale Logic

### Source Rect

The source rect is the selection window frame expressed in the target display's coordinate space.

Important:

- `NSWindow` frame coordinates and Core Graphics display coordinates are not identical in orientation.
- Centralize conversion logic in `DisplayResolver`.
- Do not scatter coordinate transforms across the codebase.

### Scaling

Render with `aspectFill` by default.

Algorithm:

1. Compute source crop aspect ratio.
2. Compute destination display aspect ratio.
3. Scale the source until the destination is fully covered.
4. Center the result.
5. Crop any overflow evenly.

This avoids distortion and gives the user the “full-screen display” behavior they asked for.

### Example

- Edit pane: `800 x 500`
- Display: `1728 x 1117`

Presentation mode scales the 800x500 live crop until the display is fully covered, then crops the excess in the longer dimension.

## Rendering Design

### v1 Renderer

Use a layer-backed custom `NSView` in the presentation window.

Recommended path:

- Convert incoming frame data into a `CGImage`
- Crop to the selected rect
- Set the result into a backing `CALayer`
- Use `contentsGravity` or explicit geometry to achieve `aspectFill`

This is enough for a working v1.

### Later Optimization

If profiling shows the `CGImage` path is too expensive:

- move to a Metal-backed renderer
- consume `CVPixelBuffer` directly
- do crop and scale in the GPU path

That should be treated as a performance phase, not a day-one requirement.

## Global Hotkey

AppKit does not provide a first-class API for a global shortcut like `Cmd + Opt + M`.

Use `RegisterEventHotKey` via HIToolbox.

Requirements:

- Register once at startup
- Route the callback into `ModeController.toggleMode()`
- Unregister on termination

Shortcut rules for v1:

- Fixed shortcut: `Cmd + Opt + M`
- No customization UI

That keeps the interaction model simple and avoids settings complexity until the core product works.

## Permissions

### Required

- Screen Recording permission

Use:

- `CGPreflightScreenCaptureAccess()`
- `CGRequestScreenCaptureAccess()`

### Not Required for v1

- Accessibility permission

This design does not need accessibility because:

- it is not reading UI element trees
- it is not driving other apps
- it is not installing a privileged key event tap

If future features add richer global input handling or app introspection, reassess this.

## App Lifecycle

### Startup

1. Launch as menu bar app.
2. Load persisted selection frame.
3. Check Screen Recording permission.
4. If missing, show permission flow.
5. If granted, create selection window and enter edit mode.
6. Register global hotkey.

### Termination

1. Stop stream.
2. Unregister hotkey.
3. Persist selection frame and any future settings.

## Persistence

Persist the minimum state:

- Last app mode is not necessary; always start in edit mode
- Last selection rect
- Last target display identifier if useful for restore

Use `UserDefaults` in v1.

Recommended key:

- `selectionFrame`

Store as serialized `CGRect` or four scalar values.

## Menu Bar UX

Even though the main product has no visible UI chrome, the app still needs a small management surface.

The menu bar menu should contain:

- `Toggle Presentation`
- `Reset Selection Size`
- `Open Selection`
- `Quit`

Optional later:

- `Launch at Login`
- `Output Display`
- `Remember Last Region`

Do not build a large preferences window in v1. It is unnecessary for the described interaction model.

## Error Handling

### Missing Permission

Behavior:

- Do not create a broken presenter
- Show a direct permission explanation
- Offer a button to open System Settings if needed

### Invalid Selection

Behavior:

- Enforce minimum pane size in edit mode so this should be rare
- If it still occurs, refuse transition and keep the app in edit mode

### Capture Failure

Behavior:

- Tear down presentation mode
- Return to edit mode
- Expose the failure in the menu bar or an alert

### Display Change

Cases:

- monitor unplugged
- display arrangement changed
- Retina scale changed

Behavior:

- listen for screen-configuration changes
- if presenting, recompute target display and restart capture if needed
- if edit mode selection becomes off-screen, clamp it onto an available screen

## Self-Capture Avoidance

This is a critical requirement.

If the app captures either:

- the presentation window, or
- the selection window

then the output will recurse visually.

The capture layer must exclude the app's own windows from ScreenCaptureKit content filtering.

Treat this as a hard correctness requirement, not a polish item.

## Performance Goals

Initial target:

- mode toggle feels immediate
- live presentation appears smooth to the eye
- no noticeable lag for typical coding and demo workflows

Practical v1 goal:

- stable 30 to 60 fps perceived output on normal desktop usage

Do not optimize prematurely beyond that. Build the simple architecture first, then profile.

## Recommended Implementation Order

### Phase 1: Skeleton

- App launches as menu bar utility
- Selection window exists and can be dragged and resized
- Global hotkey toggles a stub mode flag

### Phase 2: Real Mode Switching

- Presentation window fills selected screen
- Edit window hides and reappears correctly
- State machine is stable

### Phase 3: Live Capture

- ScreenCaptureKit stream starts successfully
- Selected region renders live in presentation window
- App windows are excluded from capture

### Phase 4: Hardening

- Persist selection rect
- Handle display changes
- Improve failure paths
- Verify Zoom, Meet, and screen share behavior

## Testing Plan

### Functional

- Edit pane can be dragged from anywhere inside
- Edit pane resizes from all edges and corners
- `Cmd + Opt + M` toggles reliably while other apps are frontmost
- Presentation fills the target display
- Toggling back restores the edit pane at the same frame

### Capture Correctness

- Output matches the selected region
- Output updates live
- No hall-of-mirrors recursion
- Window content under the selection updates correctly during interaction

### Multi-Display

- Selection entirely on display A presents on display A
- Selection moved to display B presents on display B
- Selection straddling displays resolves predictably

Recommended rule:

- choose the display containing the largest area of the selection rect

### Conferencing

- Presentation window is visible during desktop share
- Presentation output is readable when shared over Zoom and Google Meet
- Underlying app remains interactive while presenting

## Open Decisions

These should be decided early, but they are not blockers for v1.

### 1. Pane Visibility

Recommendation:

- not fully invisible
- use a faint glass treatment so the region is still operable

### 2. Output Scaling

Recommendation:

- default to `aspectFill`
- consider adding `aspectFit` only if a real use case appears

### 3. Warm Capture While Editing

Recommendation:

- do not keep capture running in edit mode for v1
- start capture only when entering presentation mode

This keeps implementation simpler and reduces idle overhead.

## Reference APIs

- `NSWindow`
- `NSPanel`
- `NSView`
- `CALayer`
- `SCShareableContent`
- `SCContentFilter`
- `SCStream`
- `SCStreamConfiguration`
- `CGPreflightScreenCaptureAccess()`
- `CGRequestScreenCaptureAccess()`
- `RegisterEventHotKey`

Official Apple documentation:

- https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents
- https://developer.apple.com/documentation/screencapturekit/scstream
- https://developer.apple.com/documentation/screencapturekit/sccontentfilter
- https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29
- https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess%28%29

## Final Recommendation

The simplest correct product is:

- a menu bar app
- one borderless editable glass selection window
- one click-through full-screen presentation window
- a strict two-state toggle on `Cmd + Opt + M`
- ScreenCaptureKit for live display capture

That matches the requested UX directly and avoids the complexity of cursor tracking, lens rendering, or traditional settings-heavy utility design.
