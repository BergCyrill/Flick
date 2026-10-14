# Flick Settings Window and Drag + Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A settings window that turns each gesture and the live preview on or off and launches Flick at login (PR A), then a drag + scroll gesture: while a window is dragged by its titlebar, scrolling away fills it and scrolling towards you restores it under the pointer, applied on release (PR B).

**Architecture:** All logic stays in `FlickCore` behind the existing `@MainActor` protocols: a `FlickSettings` value (with `UserDefaults` persistence) read through closures by the recognizers and the controller, a new `DragScrollRecognizer` that emits the existing `GestureUpdate`s, an `InputRouter` in front of both recognizers, and a pure `DragRestore` geometry function. `Flick` gets a SwiftUI settings window, a `SettingsStore`, a `LoginItem` wrapper around `SMAppService`, and an event tap that also observes left-mouse events.

**Tech Stack:** Swift 6 (Xcode toolchain), SwiftPM, swift-testing, AppKit, SwiftUI, ServiceManagement, ApplicationServices; Nix flake dev shell (go-task, swiftlint, pre-commit); Task as task runner.

**Spec:** `docs/superpowers/specs/2026-10-14-flick-settings-and-drag-scroll-design.md` (design drivers: `docs/design/settings-window.png`, `docs/design/drag-scroll.png`; builds on `docs/superpowers/specs/2026-10-14-flick-v1-design.md`)

## Global Constraints

- `swift-tools-version: 6.0`, Swift 6 language mode, deployment target macOS 14 (`.macOS(.v14)`). No new package dependencies.
- `FlickCore` imports nothing but `Foundation`. AppKit, SwiftUI, ServiceManagement, ApplicationServices and CoreGraphics live in `Sources/Flick/` only.
- No private frameworks or private API.
- Constants (copied from the specs): drag + scroll threshold **1 line** (mouse wheel, no precise deltas) and **20 pt** (trackpad, precise deltas); titlebar zone **top 40 pt**; gap **8 pt**; swipe threshold **40 pt**; pinch threshold **±0.15**; accent **#2F6BFF**.
- Settings defaults: `swipeToSnap`, `pinchToFillRestore`, `scrollWhileDragging`, `livePreview` all **true**. Launch at login is never stored by Flick; it is read from `SMAppService.mainApp.status`.
- Settings closures have the type `@escaping @MainActor () -> FlickSettings` with the default `{ FlickSettings() }`, so existing call sites and tests compile unchanged.
- Each recognizer reads the settings once, when a gesture begins (swipe/pinch `began`, the first scroll of a drag).
- Mouse events are **never** swallowed. A disabled or paused gesture swallows nothing.
- Native fullscreen windows stay excluded (the existing `TitlebarHitTester` / `TitlebarZone` check); windows Flick filled are normal windows.
- Coordinates in `FlickCore` are global, top-left origin, y down (`GlobalPoint`, `GlobalRect`). Don't name types `Point`, `Rect` or `WindowRef`.
- Tests use swift-testing (`import Testing`, `@Test`, `#expect`). New test suites go in **new files**: swiftlint's `type_body_length` (250 lines, strict) would fail on the grown existing suites. Keep functions at **4 parameters or fewer** (`function_parameter_count`).
- Commands run inside the dev shell (`direnv allow`, or prefix with `nix develop -c`). `task test` and `task lint` must pass at the end of every task; app tasks also run `task build`.
- Git:
  - Part A (Tasks 1–3) on `feature/no-ref/settings-window` (exists; holds the spec commit).
  - Part B (Tasks 4–9) on `feature/no-ref/drag-scroll`, cut from an updated `main` after PR A is merged.
  - **Never run `git commit` yourself.** At each commit step, stage the listed files, hand the user the `gitcs '<message>'` command (signing alias, needs a hardware token), and wait for "done" before the next task. Conventional Commits. Never bypass signing. Pushing and opening PRs only when the user asks.

## Review Focus

Uncovered input classes a person will hit, most likely first. Each line names where it gets pinned:

1. **Holding the button for something other than a window drag** (text selection in an editor, a slider, a scrollbar, a file drag) and scrolling must scroll the app as usual. Pinned by `pointerOffEveryTitlebarIsNotClaimedAndNotRetried`, `aFrameReadFailureIsNotClaimed` and `scrollWithoutAPressPassesThrough` (Task 6); the accepted limitation (selection dragged onto a titlebar) is documented in the spec.
2. **Mouse wheel vs. trackpad, natural vs. classic scrolling** must give the same physical direction and sensible thresholds. Pinned by `scrollingAwayWhileDraggingPreviewsFillAndReleaseCommitsIt`, `naturalScrollingGivesTheSameDirection` and `aTrackpadNeedsTwentyPoints` (Task 6), confirmed on hardware in the spike (Task 4).
3. **Lost releases and a disabled tap** must not leave the preview up or a drag half-claimed. Pinned by `theNextPressCancelsADragWhoseReleaseWasLost`, `resetCancelsAClaimedDrag` (Task 6), `aTrackpadScrollDuringATrackedDragCancelsTheDrag` and `resetCancelsATrackedDrag` (Task 7).
4. **A switch turned off** must pass that gesture's events through untouched, and a gesture in progress must finish under its starting settings. Pinned by the `SettingsGatingTests` suite (Task 2) and `offInSettingsClaimsNothing` / `settingsAreReadOncePerDrag` (Task 6).
5. **Restore near screen edges, on a secondary display, or for a window bigger than the screen** must land fully inside the visible frame. Pinned by the `DragRestoreTests` suite (Task 5) and `dragRestorePutsTheRestoreSizeUnderThePointer` (Task 8).

---

## File structure

```text
Sources/FlickCore/
├── FlickSettings.swift          # NEW  settings value + UserDefaults persistence        (Task 1)
├── GestureRecognizer.swift      # MOD  settings gating (T2), drag events pass (T5), DragContext (T5)
├── FlickController.swift        # MOD  live-preview gating (T2), drag fill/restore + dedupe (T8)
├── InputEvent.swift             # MOD  mouse + dragScroll cases                           (Task 5)
├── DragRestore.swift            # NEW  restore-under-pointer geometry                     (Task 5)
├── DragScrollRecognizer.swift   # NEW  drag + scroll state machine                        (Task 6)
└── InputRouter.swift            # NEW  routes events to the two recognizers               (Task 7)
Sources/Flick/
├── SettingsStore.swift          # NEW  ObservableObject: settings, pause note, login item (Task 3)
├── LoginItem.swift              # NEW  SMAppService.mainApp wrapper                       (Task 3)
├── SettingsWindow.swift         # NEW  NSWindow + SwiftUI Form                (T3; drag switch T9)
├── MenuBarApp.swift             # MOD  Settings… item, store wiring (T3); router wiring (T9)
├── EventTap.swift               # MOD  mouse events, dragScroll translation, router       (Task 9)
└── PreviewOverlay.swift         # MOD  animate only size changes                          (Task 9)
Tests/FlickCoreTests/
├── FlickSettingsTests.swift     # NEW (Task 1)
├── SettingsGatingTests.swift    # NEW (Task 2)
├── DragRestoreTests.swift       # NEW (Task 5)
├── DragScrollRecognizerTests.swift  # NEW (Task 6)
├── InputRouterTests.swift       # NEW (Task 7)
├── FlickControllerDragTests.swift   # NEW (Task 8)
└── FlickControllerTests.swift   # MOD  FakePreview.showCount (Task 8)
README.md                        # MOD  usage + checklist (Tasks 3 and 9)
```

---

## Part A — Settings window (`feature/no-ref/settings-window`)

### Task 1: Settings value and persistence

**Files:**
- Create: `Sources/FlickCore/FlickSettings.swift`
- Test: `Tests/FlickCoreTests/FlickSettingsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public struct FlickSettings: Equatable, Sendable` with `var swipeToSnap`, `pinchToFillRestore`, `scrollWhileDragging`, `livePreview: Bool` (all `true`), `public init()`, `public init(defaults: UserDefaults)`, `public func save(to defaults: UserDefaults)`. Keys: `"swipeToSnap"`, `"pinchToFillRestore"`, `"scrollWhileDragging"`, `"livePreview"`.

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/FlickSettingsTests.swift`:

```swift
import Foundation
import Testing

@testable import FlickCore

@Suite struct FlickSettingsTests {
    /// Runs `body` with a private defaults domain and removes the domain afterwards.
    func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "local.personal.flick.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func everythingIsOnByDefault() {
        let settings = FlickSettings()
        #expect(settings.swipeToSnap)
        #expect(settings.pinchToFillRestore)
        #expect(settings.scrollWhileDragging)
        #expect(settings.livePreview)
    }

    @Test func keysThatWereNeverWrittenKeepTheirDefaults() {
        withDefaults { defaults in
            #expect(FlickSettings(defaults: defaults) == FlickSettings())
        }
    }

    @Test func savedSettingsReadBack() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.pinchToFillRestore = false
            settings.livePreview = false
            settings.save(to: defaults)
            #expect(FlickSettings(defaults: defaults) == settings)
        }
    }

    @Test func eachSwitchIsStoredUnderItsOwnKey() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.scrollWhileDragging = false
            settings.save(to: defaults)
            #expect(defaults.object(forKey: "scrollWhileDragging") as? Bool == false)
            #expect(defaults.object(forKey: "swipeToSnap") as? Bool == true)
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter FlickSettingsTests`
Expected: build FAILS with "cannot find 'FlickSettings' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/FlickCore/FlickSettings.swift`:

```swift
import Foundation

/// What the user turned on or off in the settings window. Launch at login isn't part of it:
/// macOS owns that state.
public struct FlickSettings: Equatable, Sendable {
    public var swipeToSnap = true
    public var pinchToFillRestore = true
    public var scrollWhileDragging = true
    public var livePreview = true

    public init() {}

    /// Reads the settings from `defaults`. Keys that were never written keep their default.
    public init(defaults: UserDefaults) {
        for (key, path) in Self.keys {
            if let value = defaults.object(forKey: key) as? Bool {
                self[keyPath: path] = value
            }
        }
    }

    public func save(to defaults: UserDefaults) {
        for (key, path) in Self.keys {
            defaults.set(self[keyPath: path], forKey: key)
        }
    }

    private static var keys: [(String, WritableKeyPath<FlickSettings, Bool>)] {
        [
            ("swipeToSnap", \.swipeToSnap),
            ("pinchToFillRestore", \.pinchToFillRestore),
            ("scrollWhileDragging", \.scrollWhileDragging),
            ("livePreview", \.livePreview),
        ]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FlickSettingsTests`
Expected: 4 tests pass.

- [ ] **Step 5: Full suite and lint**

Run: `task test && task lint`
Expected: 60 tests pass (56 before + 4), lint clean.

- [ ] **Step 6: Commit**

Stage `Sources/FlickCore/FlickSettings.swift Tests/FlickCoreTests/FlickSettingsTests.swift` and hand over:

```sh
gitcs 'feat(core): add FlickSettings with UserDefaults persistence'
```

---

### Task 2: Settings gate the gestures and the preview

**Files:**
- Modify: `Sources/FlickCore/GestureRecognizer.swift` (init, `claim(at:)`, the two `began` call sites)
- Modify: `Sources/FlickCore/FlickController.swift` (init, `.preview` case)
- Test: `Tests/FlickCoreTests/SettingsGatingTests.swift`

**Interfaces:**
- Consumes: `FlickSettings` (Task 1); `FakeProbe` (`GestureRecognizerTests.swift`), `FakeWindows`, `FakeScreens`, `FakePreview` (`FlickControllerTests.swift`).
- Produces:
  - `GestureRecognizer.init(probe: TitlebarProbe, settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() }, onUpdate: @escaping (GestureUpdate) -> Void)`
  - `FlickController.init(windows:screens:preview:gap: Double = LayoutEngine.defaultGap, settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() })`

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/SettingsGatingTests.swift`:

```swift
import Testing

@testable import FlickCore

@MainActor
@Suite struct SettingsGatingTests {
    let window = WindowHandle("finder-1")
    let start = GlobalPoint(x: 600, y: 260)
    var context: GestureContext { GestureContext(window: window, pointer: start) }

    /// Natural scrolling: the deltas follow the fingers.
    func swipe(_ phase: GesturePhase, _ dx: Double = 0) -> InputEvent {
        .scroll(phase: phase, deltaX: dx, deltaY: 0, invertedFromDevice: true, location: start)
    }

    func pinch(_ phase: GesturePhase, _ magnification: Double = 0) -> InputEvent {
        .magnify(phase: phase, magnification: magnification, location: start)
    }

    func run(_ events: [InputEvent], probe: FakeProbe, settings: FlickSettings)
        -> (decisions: [EventDecision], updates: [GestureUpdate])
    {
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: probe, settings: { settings }) { updates.append($0) }
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    @Test func swipeIsNotClaimedWhenSwipeToSnapIsOff() {
        var settings = FlickSettings()
        settings.swipeToSnap = false
        let probe = FakeProbe(window: window)
        let result = run([swipe(.began, -60), swipe(.ended)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func pinchStillWorksWhenOnlySwipeIsOff() {
        var settings = FlickSettings()
        settings.swipeToSnap = false
        let result = run([pinch(.began, 0.3), pinch(.ended)], probe: FakeProbe(window: window), settings: settings)
        #expect(result.decisions == [.swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func pinchIsNotClaimedWhenPinchIsOff() {
        var settings = FlickSettings()
        settings.pinchToFillRestore = false
        let probe = FakeProbe(window: window)
        let result = run([pinch(.began, 0.3), pinch(.ended)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func swipeStillWorksWhenOnlyPinchIsOff() {
        var settings = FlickSettings()
        settings.pinchToFillRestore = false
        let result = run([swipe(.began, -60), swipe(.ended)], probe: FakeProbe(window: window), settings: settings)
        #expect(result.decisions == [.swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.leftHalf)), .commit(context, .slot(.leftHalf))])
    }

    @Test func aGestureInProgressFinishesUnderTheSettingsItStartedWith() {
        var current = FlickSettings()
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: FakeProbe(window: window), settings: { current }) {
            updates.append($0)
        }
        _ = recognizer.handle(swipe(.began, -60))
        current.swipeToSnap = false
        let decisions = [swipe(.changed, -5), swipe(.ended)].map { recognizer.handle($0) }
        #expect(decisions == [.swallow, .swallow])
        #expect(updates.last == .commit(context, .slot(.leftHalf)))
    }
}

@MainActor
@Suite struct PreviewSettingTests {
    let window = WindowHandle("w")
    let windows = FakeWindows()
    let preview = FakePreview()
    var context: GestureContext { GestureContext(window: window, pointer: GlobalPoint(x: 400, y: 210)) }

    func makeController(livePreview: Bool) -> FlickController {
        windows.frames[window] = GlobalRect(x: 300, y: 200, width: 640, height: 480)
        var settings = FlickSettings()
        settings.livePreview = livePreview
        return FlickController(windows: windows, screens: FakeScreens(), preview: preview, settings: { settings })
    }

    @Test func previewOffOnlyHides() {
        let controller = makeController(livePreview: false)
        controller.handle(.preview(context, .slot(.leftHalf)))
        #expect(preview.shown == nil)
        #expect(preview.hideCount == 1)
    }

    @Test func previewOffStillMovesTheWindowOnCommit() {
        let controller = makeController(livePreview: false)
        controller.handle(.commit(context, .slot(.rightHalf)))
        #expect(windows.frames[window] == GlobalRect(x: 724, y: 33, width: 708, height: 859))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'SettingsGatingTests|PreviewSettingTests'`
Expected: build FAILS with "extra argument 'settings' in call" (or "incorrect argument label") for `GestureRecognizer` and `FlickController`.

- [ ] **Step 3: Gate the recognizer**

In `Sources/FlickCore/GestureRecognizer.swift`, replace the stored properties and init:

```swift
    private let probe: TitlebarProbe
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    public init(probe: TitlebarProbe, onUpdate: @escaping (GestureUpdate) -> Void) {
        self.probe = probe
        self.onUpdate = onUpdate
    }
```

with:

```swift
    private let probe: TitlebarProbe
    private let settings: @MainActor () -> FlickSettings
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    /// - Parameter settings: read once when a gesture begins.
    public init(
        probe: TitlebarProbe,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() },
        onUpdate: @escaping (GestureUpdate) -> Void
    ) {
        self.probe = probe
        self.settings = settings
        self.onUpdate = onUpdate
    }
```

In `handleScroll`, replace `guard let context = claim(at: location) else {` with:

```swift
            guard let context = claim(at: location, enabled: settings().swipeToSnap) else {
```

In `handleMagnify`, replace `guard let context = claim(at: location) else {` with:

```swift
            guard let context = claim(at: location, enabled: settings().pinchToFillRestore) else {
```

Replace `claim(at:)`:

```swift
    private func claim(at location: GlobalPoint) -> GestureContext? {
        guard !isPaused, let window = probe.window(atTitlebar: location) else { return nil }
        return GestureContext(window: window, pointer: location)
    }
```

with:

```swift
    /// A gesture that is switched off in the settings, or paused, is never claimed: the probe
    /// isn't even asked, and all of its events pass through.
    private func claim(at location: GlobalPoint, enabled: Bool) -> GestureContext? {
        guard !isPaused, enabled, let window = probe.window(atTitlebar: location) else { return nil }
        return GestureContext(window: window, pointer: location)
    }
```

- [ ] **Step 4: Gate the preview in the controller**

In `Sources/FlickCore/FlickController.swift`, replace the stored properties and init of `FlickController`:

```swift
    private let gap: Double
    private var history = FrameHistory()

    public init(
        windows: WindowAccess,
        screens: ScreenProvider,
        preview: PreviewPresenter,
        gap: Double = LayoutEngine.defaultGap
    ) {
        self.windows = windows
        self.screens = screens
        self.preview = preview
        self.gap = gap
    }
```

with:

```swift
    private let gap: Double
    private let settings: @MainActor () -> FlickSettings
    private var history = FrameHistory()

    public init(
        windows: WindowAccess,
        screens: ScreenProvider,
        preview: PreviewPresenter,
        gap: Double = LayoutEngine.defaultGap,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() }
    ) {
        self.windows = windows
        self.screens = screens
        self.preview = preview
        self.gap = gap
        self.settings = settings
    }
```

and in `handle(_:)` replace `if let target, let frame = frame(for: target, context: context) {` with:

```swift
            if settings().livePreview, let target, let frame = frame(for: target, context: context) {
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter 'SettingsGatingTests|PreviewSettingTests'`
Expected: 7 tests pass.

- [ ] **Step 6: Full suite and lint**

Run: `task format && task test && task lint`
Expected: 67 tests pass, lint clean.

- [ ] **Step 7: Commit**

Stage `Sources/FlickCore/GestureRecognizer.swift Sources/FlickCore/FlickController.swift Tests/FlickCoreTests/SettingsGatingTests.swift` and hand over:

```sh
gitcs 'feat(core): let settings switch off swipe, pinch and the live preview'
```

---

### Task 3: Settings window, launch at login and menu entry

App adapters; no unit tests (the `Flick` target has none). Verified by build, lint and the manual checklist.

**Files:**
- Create: `Sources/Flick/LoginItem.swift`, `Sources/Flick/SettingsStore.swift`, `Sources/Flick/SettingsWindow.swift`
- Modify: `Sources/Flick/MenuBarApp.swift`
- Modify: `README.md` (Usage, Manual test checklist)

**Interfaces:**
- Consumes: `FlickSettings` (Task 1); the `settings:` parameters of `GestureRecognizer` and `FlickController` (Task 2).
- Produces:
  - `@MainActor enum LoginItem { static var isEnabled: Bool; static var problem: String?; static func set(enabled: Bool) -> String?; static func openSystemSettings() }`
  - `@MainActor final class SettingsStore: ObservableObject { @Published var settings: FlickSettings; @Published var isPaused: Bool; @Published var launchAtLogin: Bool; @Published private(set) var loginProblem: String?; func refreshLoginItem() }`
  - `@MainActor final class SettingsWindow { init(store: SettingsStore); func show() }` and `struct SettingsView: View` (Task 9 adds one toggle to it).

- [ ] **Step 1: Login item wrapper**

`Sources/Flick/LoginItem.swift`:

```swift
import ServiceManagement

/// Launch at login through `SMAppService`. macOS owns the state; Flick only asks for changes
/// and reads the result back.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Why launch at login isn't active although it was asked for, or `nil`.
    static var problem: String? {
        SMAppService.mainApp.status == .requiresApproval
            ? "Requires approval in System Settings → Login Items." : nil
    }

    /// Registers or unregisters Flick. Returns the text to show under the switch if it didn't
    /// work out, or `nil`.
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return problem
        } catch {
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

- [ ] **Step 2: Settings store**

`Sources/Flick/SettingsStore.swift`:

```swift
import FlickCore
import Foundation

/// The state the settings window edits. Gesture settings are saved to UserDefaults on every
/// change; launch at login goes straight to macOS.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var settings: FlickSettings {
        didSet { settings.save(to: defaults) }
    }

    /// Mirrors *Pause gestures* from the menu so the window can show a note. Not saved.
    @Published var isPaused = false

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            loginProblem = LoginItem.set(enabled: launchAtLogin)
            // Flip the switch back if macOS didn't follow.
            launchAtLogin = LoginItem.isEnabled
        }
    }

    /// Shown under the launch-at-login switch instead of its hint.
    @Published private(set) var loginProblem: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = FlickSettings(defaults: defaults)
        launchAtLogin = LoginItem.isEnabled
        loginProblem = LoginItem.problem
    }

    /// Re-reads launch at login, which can change in System Settings while Flick runs.
    func refreshLoginItem() {
        launchAtLogin = LoginItem.isEnabled
        loginProblem = LoginItem.problem
    }
}
```

- [ ] **Step 3: Settings window**

`Sources/Flick/SettingsWindow.swift` (copy and layout from `docs/design/settings-window.png`):

```swift
import AppKit
import SwiftUI

/// The settings window from the design drawing. Created on first use and reused.
@MainActor
final class SettingsWindow {
    private let store: SettingsStore
    private var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        store.refreshLoginItem()
        let window = self.window ?? makeWindow()
        self.window = window
        // Flick has no Dock icon, so nothing else brings the window to the front.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
        window.title = "Flick Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            if store.isPaused {
                Section {
                    Label(
                        "Gestures are paused from the menu bar. Your switches keep their values.",
                        systemImage: "pause.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            Section("Gestures") {
                Toggle(isOn: $store.settings.swipeToSnap) {
                    Self.label("Swipe on titlebar to snap", hint: "Two fingers on a titlebar: halves and quarters.")
                }
                Toggle(isOn: $store.settings.pinchToFillRestore) {
                    Self.label(
                        "Pinch on titlebar to fill and restore", hint: "Pinch out fills the screen, pinch in restores.")
                }
            }
            Section("Feedback") {
                Toggle(isOn: $store.settings.livePreview) {
                    Self.label(
                        "Show live preview",
                        hint: "Blue outline of the target while you gesture. Off: the window just moves on release.")
                }
            }
            Section("General") {
                Toggle(isOn: $store.launchAtLogin) {
                    Self.label(
                        "Launch at login",
                        hint: store.loginProblem ?? "Shows the state from System Settings → General → Login Items.",
                        isProblem: store.loginProblem != nil)
                }
                if store.loginProblem != nil {
                    Button("Open Login Items…") { LoginItem.openSystemSettings() }
                }
            }
            Section {
                Text("Fullscreen windows are always left alone. Changes apply from the next gesture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: 480, height: 560)
    }

    private static func label(_ title: String, hint: String, isProblem: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(hint)
                .font(.caption)
                .foregroundStyle(isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }
}
```

- [ ] **Step 4: Wire the store and the menu entry**

In `Sources/Flick/MenuBarApp.swift`:

Add below `private var trustTimer: Timer?`:

```swift
    private let store = SettingsStore()
    private lazy var settingsWindow = SettingsWindow(store: store)
```

In `applicationDidFinishLaunching`, replace:

```swift
        let controller = FlickController(windows: WindowMover(), screens: ScreenAdapter(), preview: PreviewOverlay())
        // Updates are handled after the tap callback returns: moving a window takes several
        // Accessibility round-trips, and the swallow decision doesn't depend on them.
        let recognizer = GestureRecognizer(probe: TitlebarHitTester()) { update in
            DispatchQueue.main.async { controller.handle(update) }
        }
```

with:

```swift
        let store = self.store
        let controller = FlickController(
            windows: WindowMover(), screens: ScreenAdapter(), preview: PreviewOverlay(), settings: { store.settings })
        // Updates are handled after the tap callback returns: moving a window takes several
        // Accessibility round-trips, and the swallow decision doesn't depend on them.
        let recognizer = GestureRecognizer(probe: TitlebarHitTester(), settings: { store.settings }) { update in
            DispatchQueue.main.async { controller.handle(update) }
        }
```

In `buildMenu()`, replace:

```swift
        menu.addItem(pauseItem)
        menu.addItem(.separator())
```

with:

```swift
        menu.addItem(pauseItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
```

Replace `togglePause()`:

```swift
    @objc private func togglePause() {
        recognizer?.isPaused.toggle()
        refreshMenu()
    }
```

with:

```swift
    @objc private func togglePause() {
        recognizer?.isPaused.toggle()
        store.isPaused = recognizer?.isPaused ?? false
        refreshMenu()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
```

- [ ] **Step 5: README**

In `README.md`, replace:

```markdown
Swipe back to where you started to cancel. Gestures that start anywhere else go to the app as
usual. *Pause gestures* in the menu-bar item turns Flick off without quitting.
```

with:

```markdown
Swipe back to where you started to cancel. Gestures that start anywhere else go to the app as
usual. *Pause gestures* in the menu-bar item turns Flick off without quitting.

*Settings…* (⌘,) in the menu-bar item turns each gesture and the live preview on or off and
starts Flick at login. A gesture that is off swallows nothing: its scrolls and pinches reach the
app. Changes apply from the next gesture.
```

Append to the end of the *Manual test checklist*:

```markdown
- [ ] Settings: with *Swipe on titlebar to snap* off, a titlebar swipe scrolls the app (e.g. Safari's tab strip) and pinch still works; the same the other way round for *Pinch on titlebar*.
- [ ] Settings: with *Show live preview* off, no overlay appears and windows still move on lift.
- [ ] Settings survive a relaunch (`task run`).
- [ ] *Pause gestures* while the settings window is open shows the paused note; unpausing hides it.
- [ ] *Launch at login* on: Flick appears in System Settings → General → Login Items and starts after logging out and in; off removes it. If macOS wants approval, the hint says so and *Open Login Items…* opens the pane.
```

- [ ] **Step 6: Build, test, lint**

Run: `task format && task build && task test && task lint`
Expected: release build succeeds without warnings in the new files, 67 tests pass, lint clean.

- [ ] **Step 7: Manual check (user)**

Run: `task run`, re-grant Accessibility if macOS asks (ad-hoc signature), then ask the user to work through the five new checklist items plus "each of the 8 swipe directions" and "pinch out / in" as a regression check, and to compare the window with `docs/design/settings-window.png`.
Expected: all items pass. A failing item is fixed in this task before the commit.

- [ ] **Step 8: Commit**

Stage `Sources/Flick/LoginItem.swift Sources/Flick/SettingsStore.swift Sources/Flick/SettingsWindow.swift Sources/Flick/MenuBarApp.swift README.md` and hand over:

```sh
gitcs 'feat(app): add settings window with gesture switches and launch at login'
```

- [ ] **Step 9: Stop for PR A**

Part A is complete. Ask the user whether to push `feature/no-ref/settings-window` and open PR A against `main`. Part B starts only after the user says so; it branches from `main` once PR A is merged.

---

## Part B — Drag + scroll (`feature/no-ref/drag-scroll`)

Setup before Task 4: `git switch main && git pull --ff-only && git switch -c feature/no-ref/drag-scroll`.

### Task 4: Drag + scroll spike (throwaway, not committed)

Confirms the spec's riskiest assumptions on real hardware. **Nothing from this task goes into the repo.**

**Files:**
- Create (outside the repo): `$TMPDIR/flick-spike/DragScrollSpike.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a written finding in the ledger confirming or refuting each expectation below, with log excerpts.
  - If **E2** (direction) differs: flip the sign in `DragScrollRecognizer.accumulate` (Task 6) and the expectations of `scrollingAwayWhileDraggingPreviewsFillAndReleaseCommitsIt` and `naturalScrollingGivesTheSameDirection`.
  - If **E4** (frame sticks) fails for an app: Task 9 delays the drag + scroll commit by the smallest delay that works in the spike (try 50 ms, then 100 ms), documented in a ledger ruling.

- [ ] **Step 1: Write the spike**

```swift
// Throwaway: does drag + scroll work through a session event tap?
import AppKit
import ApplicationServices

var drags = 0
var scrolled = 0.0

func frame(_ window: AXUIElement) -> String {
    var position: CFTypeRef?
    var size: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
    var origin = CGPoint.zero
    var extent = CGSize.zero
    if let position { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
    if let size { AXValueGetValue(size as! AXValue, .cgSize, &extent) }
    return "\(origin) \(extent)"
}

/// Fills the primary display's visible frame with the window under `point`, right after release.
func fill(at point: CGPoint) {
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
        let hit
    else { return print("no element under the pointer") }
    var windowRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &windowRef) == .success, let windowRef
    else { return print("no window") }
    let window = windowRef as! AXUIElement
    let screen = NSScreen.screens[0]
    let visible = screen.visibleFrame
    var origin = CGPoint(x: visible.minX + 8, y: screen.frame.height - visible.maxY + 8)
    var size = CGSize(width: visible.width - 16, height: visible.height - 16)
    let position = AXValueCreate(.cgPoint, &origin)!
    let extent = AXValueCreate(.cgSize, &size)!
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    print("set:", origin, size, "read back:", frame(window))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { print("after 0.5 s:", frame(window)) }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .leftMouseDown:
        drags = 0
        scrolled = 0
        print("down at", event.location)
    case .leftMouseDragged:
        drags += 1
    case .leftMouseUp:
        print("up at", event.location, "after \(drags) drag events, scrolled \(scrolled)")
        if scrolled != 0 {
            let point = event.location
            DispatchQueue.main.async { fill(at: point) }
        }
    case .scrollWheel:
        let held = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard held, let ns = NSEvent(cgEvent: event), ns.momentumPhase.isEmpty else { break }
        scrolled += ns.scrollingDeltaY
        print(
            "scroll while held: dy=\(ns.scrollingDeltaY) precise=\(ns.hasPreciseScrollingDeltas)",
            "inverted=\(ns.isDirectionInvertedFromDevice) phase=\(ns.phase.rawValue)")
        return nil  // swallowed: does the drag carry on?
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
    | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
    eventsOfInterest: mask, callback: callback, userInfo: nil)
else { fatalError("tapCreate failed: grant Accessibility to the terminal app") }
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("listening; Ctrl-C to stop")
CFRunLoopRun()
```

- [ ] **Step 2: Build and run it**

Run: `mkdir -p $TMPDIR/flick-spike && swiftc -o $TMPDIR/flick-spike/spike $TMPDIR/flick-spike/DragScrollSpike.swift && $TMPDIR/flick-spike/spike`
Expected: "listening; Ctrl-C to stop". The terminal app needs Accessibility access.

- [ ] **Step 3: Hardware session (user)**

Ask the user to do the following while the spike runs, then read the log:

1. Drag a Finder window by its titlebar for a second and release without scrolling.
2. Drag it again and, while holding, roll the mouse wheel **away** once, then release.
3. Same with the wheel **towards** you.
4. With a trackpad: click-hold on a titlebar and scroll with two other fingers, both directions.
5. Repeat step 2 in Safari, Terminal and VS Code.
6. Switch natural scrolling off (System Settings → Trackpad / Mouse), repeat steps 2 and 4.

Expected:
- **E1:** steps 1–5 log `down`, many drag events, and `up` (mouse events reach the tap during a window drag).
- **E2:** wheel away with natural scrolling **on** logs `dy<0 inverted=true`; with it **off** `dy>0 inverted=false` (both mean "away", matching `DirectionClassifier.fingerDelta`).
- **E3:** the window keeps following the pointer while scroll events are swallowed.
- **E4:** after release, `after 0.5 s:` matches `read back:` in every app (the frame set after the drag ended sticks).
- **E5:** mouse wheel logs `precise=false`, trackpad logs `precise=true`.

- [ ] **Step 4: Record the findings and delete the spike**

Write E1–E5 into the ledger with log excerpts, then `rm -rf $TMPDIR/flick-spike`. No commit.

---

### Task 5: Input events, drag context and restore geometry

**Files:**
- Modify: `Sources/FlickCore/InputEvent.swift`
- Modify: `Sources/FlickCore/GestureRecognizer.swift` (`GestureContext`, new `DragContext`, `handle(_:)` switch)
- Create: `Sources/FlickCore/DragRestore.swift`
- Test: `Tests/FlickCoreTests/DragRestoreTests.swift`

**Interfaces:**
- Consumes: `GlobalPoint`, `GlobalRect`.
- Produces:
  - `InputEvent` cases `.mouseDown(location: GlobalPoint)`, `.mouseDragged(location: GlobalPoint)`, `.mouseUp(location: GlobalPoint)`, `.dragScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)`.
  - `public struct DragContext: Equatable, Sendable { frameAtPress: GlobalRect; pressPoint: GlobalPoint; init(frameAtPress:pressPoint:) }`
  - `GestureContext.init(window: WindowHandle, pointer: GlobalPoint, drag: DragContext? = nil)` and `public let drag: DragContext?`.
  - `public enum DragRestore { static func frame(restoring original: GlobalRect, drag: DragContext, pointer: GlobalPoint, visible: GlobalRect) -> GlobalRect }`.

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/DragRestoreTests.swift`:

```swift
import Testing

@testable import FlickCore

@Suite struct DragRestoreTests {
    let visible = GlobalRect(x: 0, y: 25, width: 1440, height: 875)
    /// The restore frame; only its 640×480 size matters.
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    /// A left-half window grabbed in the middle of its titlebar, 12 pt below its top edge.
    let drag = DragContext(
        frameAtPress: GlobalRect(x: 8, y: 33, width: 708, height: 859), pressPoint: GlobalPoint(x: 362, y: 45))

    func restored(at pointer: GlobalPoint) -> GlobalRect {
        DragRestore.frame(restoring: original, drag: drag, pointer: pointer, visible: visible)
    }

    @Test func keepsTheGrabbedSpotUnderThePointer() {
        #expect(restored(at: GlobalPoint(x: 700, y: 300)) == GlobalRect(x: 380, y: 288, width: 640, height: 480))
    }

    @Test func keepsTheRelativeHorizontalGrabPosition() {
        // Grabbed a quarter of the way along the titlebar.
        let quarter = DragContext(frameAtPress: drag.frameAtPress, pressPoint: GlobalPoint(x: 185, y: 45))
        let frame = DragRestore.frame(
            restoring: original, drag: quarter, pointer: GlobalPoint(x: 700, y: 300), visible: visible)
        #expect(frame == GlobalRect(x: 540, y: 288, width: 640, height: 480))
    }

    @Test func staysInsideTheRightEdge() {
        #expect(restored(at: GlobalPoint(x: 1400, y: 300)) == GlobalRect(x: 800, y: 288, width: 640, height: 480))
    }

    @Test func staysInsideTheLeftEdge() {
        #expect(restored(at: GlobalPoint(x: 100, y: 300)) == GlobalRect(x: 0, y: 288, width: 640, height: 480))
    }

    @Test func staysBelowTheMenuBar() {
        #expect(restored(at: GlobalPoint(x: 700, y: 20)) == GlobalRect(x: 380, y: 25, width: 640, height: 480))
    }

    @Test func staysAboveTheBottomEdge() {
        #expect(restored(at: GlobalPoint(x: 700, y: 880)) == GlobalRect(x: 380, y: 420, width: 640, height: 480))
    }

    @Test func topOffsetIsCappedToTheRestoredHeight() {
        // Grabbed 500 pt below the top of a filled window; the restored window is only 480 tall.
        let deep = DragContext(
            frameAtPress: GlobalRect(x: 0, y: 25, width: 1440, height: 875), pressPoint: GlobalPoint(x: 720, y: 525))
        let frame = DragRestore.frame(
            restoring: original, drag: deep, pointer: GlobalPoint(x: 720, y: 700), visible: visible)
        #expect(frame == GlobalRect(x: 400, y: 220, width: 640, height: 480))
    }

    @Test func aWindowLargerThanTheScreenAlignsTopLeft() {
        let huge = GlobalRect(x: 0, y: 0, width: 2000, height: 1000)
        let frame = DragRestore.frame(
            restoring: huge, drag: drag, pointer: GlobalPoint(x: 700, y: 300), visible: visible)
        #expect(frame == GlobalRect(x: 0, y: 25, width: 2000, height: 1000))
    }

    @Test func worksOnASecondaryDisplayWithNegativeOrigin() {
        let left = GlobalRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = DragRestore.frame(
            restoring: original, drag: drag, pointer: GlobalPoint(x: -960, y: 400), visible: left)
        #expect(frame == GlobalRect(x: -1280, y: 388, width: 640, height: 480))
    }

    @Test func roundsToWholePoints() {
        // Grabbed a third of the way along: 100 × 1/3 is not a whole number.
        let third = DragContext(
            frameAtPress: GlobalRect(x: 0, y: 25, width: 300, height: 400), pressPoint: GlobalPoint(x: 100, y: 35))
        let small = GlobalRect(x: 0, y: 0, width: 100, height: 100)
        let frame = DragRestore.frame(
            restoring: small, drag: third, pointer: GlobalPoint(x: 500, y: 300), visible: visible)
        #expect(frame == GlobalRect(x: 467, y: 290, width: 100, height: 100))
    }
}

@MainActor
@Suite struct DragEventsInTheTrackpadRecognizerTests {
    @Test func mouseAndDragScrollEventsPassThroughTheTrackpadRecognizer() {
        let point = GlobalPoint(x: 400, y: 210)
        var updates: [GestureUpdate] = []
        let recognizer = GestureRecognizer(probe: FakeProbe(window: WindowHandle("w"))) { updates.append($0) }
        let events: [InputEvent] = [
            .mouseDown(location: point), .mouseDragged(location: point),
            .dragScroll(deltaY: 1, precise: false, invertedFromDevice: false, location: point),
            .mouseUp(location: point),
        ]
        #expect(events.map { recognizer.handle($0) } == Array(repeating: .passThrough, count: 4))
        #expect(updates.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'DragRestoreTests|DragEventsInTheTrackpadRecognizerTests'`
Expected: build FAILS with "cannot find 'DragContext' in scope" and "type 'InputEvent' has no member 'mouseDown'".

- [ ] **Step 3: Add the input events**

In `Sources/FlickCore/InputEvent.swift`, replace:

```swift
    /// Pinch. `magnification` is the delta since the previous event.
    case magnify(phase: GesturePhase, magnification: Double, location: GlobalPoint)
}
```

with:

```swift
    /// Pinch. `magnification` is the delta since the previous event.
    case magnify(phase: GesturePhase, magnification: Double, location: GlobalPoint)
    /// Left mouse button pressed, moved while pressed, released. Only observed, never swallowed.
    case mouseDown(location: GlobalPoint)
    case mouseDragged(location: GlobalPoint)
    case mouseUp(location: GlobalPoint)
    /// A scroll while the left mouse button is held, momentum excluded. `deltaY` is the raw
    /// `NSEvent.scrollingDeltaY`: lines for a mouse wheel (`precise == false`), points for a
    /// trackpad.
    case dragScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)
}
```

- [ ] **Step 4: Add the drag context and keep the trackpad recognizer out of drags**

In `Sources/FlickCore/GestureRecognizer.swift`, replace `GestureContext`:

```swift
/// The window a claimed gesture acts on, and where the pointer was when it started.
public struct GestureContext: Equatable {
    public let window: WindowHandle
    public let pointer: GlobalPoint

    public init(window: WindowHandle, pointer: GlobalPoint) {
        self.window = window
        self.pointer = pointer
    }
}
```

with:

```swift
/// Where a dragged window was, and where it was grabbed, when the mouse button went down.
public struct DragContext: Equatable, Sendable {
    public let frameAtPress: GlobalRect
    public let pressPoint: GlobalPoint

    public init(frameAtPress: GlobalRect, pressPoint: GlobalPoint) {
        self.frameAtPress = frameAtPress
        self.pressPoint = pressPoint
    }
}

/// The window a claimed gesture acts on, and where the pointer is: where a trackpad gesture
/// started, or where the pointer is now during a drag.
public struct GestureContext: Equatable {
    public let window: WindowHandle
    public let pointer: GlobalPoint
    /// Set for drag + scroll, `nil` for trackpad gestures.
    public let drag: DragContext?

    public init(window: WindowHandle, pointer: GlobalPoint, drag: DragContext? = nil) {
        self.window = window
        self.pointer = pointer
        self.drag = drag
    }
}
```

In `GestureRecognizer.handle(_:)`, replace:

```swift
        case let .magnify(phase, magnification, location):
            return handleMagnify(phase: phase, magnification: magnification, location: location)
        }
```

with:

```swift
        case let .magnify(phase, magnification, location):
            return handleMagnify(phase: phase, magnification: magnification, location: location)
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            // Drag + scroll belongs to DragScrollRecognizer.
            return .passThrough
        }
```

- [ ] **Step 5: Write the restore geometry**

`Sources/FlickCore/DragRestore.swift`:

```swift
/// Where a window goes when it is restored during a drag: back to its restore size, under the
/// pointer, still held at the spot that was grabbed.
public enum DragRestore {
    /// - Parameters:
    ///   - original: the frame to restore. Only its size is used.
    ///   - drag: where the window was, and where it was grabbed, when the button went down.
    ///   - pointer: where the pointer is now.
    ///   - visible: visible frame of the screen under the pointer.
    public static func frame(
        restoring original: GlobalRect,
        drag: DragContext,
        pointer: GlobalPoint,
        visible: GlobalRect
    ) -> GlobalRect {
        let press = drag.frameAtPress
        let fraction = press.width > 0 ? (drag.pressPoint.x - press.x) / press.width : 0.5
        let top = min(drag.pressPoint.y - press.y, original.height)
        let x = pointer.x - fraction * original.width
        let y = pointer.y - top
        // Keep it inside `visible`; a window larger than `visible` aligns to its top-left corner.
        let clampedX = max(min(x, visible.maxX - original.width), visible.minX)
        let clampedY = max(min(y, visible.maxY - original.height), visible.minY)
        return GlobalRect(
            x: clampedX.rounded(), y: clampedY.rounded(), width: original.width, height: original.height)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter 'DragRestoreTests|DragEventsInTheTrackpadRecognizerTests'`
Expected: 11 tests pass.

- [ ] **Step 7: Full suite and lint**

Run: `task format && task test && task lint`
Expected: 78 tests pass (67 + 11), lint clean. `task build` also succeeds: the app's `EventTranslator` doesn't switch over `InputEvent`, so the new cases don't break it.

- [ ] **Step 8: Commit**

Stage `Sources/FlickCore/InputEvent.swift Sources/FlickCore/GestureRecognizer.swift Sources/FlickCore/DragRestore.swift Tests/FlickCoreTests/DragRestoreTests.swift` and hand over:

```sh
gitcs 'feat(core): add drag input events and restore-under-pointer geometry'
```

---

### Task 6: Drag + scroll recognizer

**Files:**
- Create: `Sources/FlickCore/DragScrollRecognizer.swift`
- Test: `Tests/FlickCoreTests/DragScrollRecognizerTests.swift`

**Interfaces:**
- Consumes: `InputEvent` drag cases, `DragContext`, `GestureContext(window:pointer:drag:)` (Task 5); `FlickSettings` (Task 1); `TitlebarProbe`, `GestureUpdate`, `EventDecision`, `Target`; `WindowAccess`; `DirectionClassifier.fingerDelta`; `FakeProbe`, `FakeWindows`.
- Produces:
  - `@MainActor public final class DragScrollRecognizer`
  - `init(probe: TitlebarProbe, windows: WindowAccess, settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() }, onUpdate: @escaping (GestureUpdate) -> Void)`
  - `var isPaused: Bool`, `var isTracking: Bool { get }`, `func handle(_ event: InputEvent) -> EventDecision`, `func reset()`
  - `static let wheelThreshold: Double = 1`, `static let preciseThreshold: Double = 20`

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/DragScrollRecognizerTests.swift`:

```swift
import Testing

@testable import FlickCore

@MainActor
@Suite struct DragScrollRecognizerTests {
    let window = WindowHandle("finder-1")
    /// The window when the button went down; its titlebar zone is y 200..<240.
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    let press = GlobalPoint(x: 400, y: 210)
    /// 50 pt right and down from the press.
    let pointer = GlobalPoint(x: 450, y: 260)
    /// The window has moved along with the pointer.
    static let dragged = GlobalRect(x: 350, y: 250, width: 640, height: 480)
    let windows = FakeWindows()

    var context: GestureContext {
        GestureContext(window: window, pointer: pointer, drag: DragContext(frameAtPress: original, pressPoint: press))
    }

    /// Classic scrolling mouse wheel: rolling it away from you gives positive deltas.
    func wheel(_ lines: Double) -> InputEvent {
        .dragScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: pointer)
    }

    func run(
        _ events: [InputEvent], probe: FakeProbe? = nil, windowFrame: GlobalRect? = DragScrollRecognizerTests.dragged,
        settings: FlickSettings = FlickSettings()
    ) -> (decisions: [EventDecision], updates: [GestureUpdate]) {
        windows.frames[window] = windowFrame
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(
            probe: probe ?? FakeProbe(window: window), windows: windows, settings: { settings }
        ) { updates.append($0) }
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    @Test func scrollingAwayWhileDraggingPreviewsFillAndReleaseCommitsIt() {
        let result = run([.mouseDown(location: press), .mouseDragged(location: pointer), wheel(1), .mouseUp(location: pointer)])
        #expect(result.decisions == [.passThrough, .passThrough, .swallow, .passThrough])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func scrollingTowardsYouTargetsRestore() {
        let result = run([.mouseDown(location: press), wheel(-1), .mouseUp(location: pointer)])
        #expect(result.updates == [.preview(context, .restore), .commit(context, .restore)])
    }

    @Test func naturalScrollingGivesTheSameDirection() {
        // Natural scrolling flips the deltas and says so.
        let away = InputEvent.dragScroll(deltaY: -1, precise: false, invertedFromDevice: true, location: pointer)
        let result = run([.mouseDown(location: press), away])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func aTrackpadNeedsTwentyPoints() {
        // Natural scrolling trackpad: fingers moving away give negative deltas.
        func fingers(_ points: Double) -> InputEvent {
            .dragScroll(deltaY: -points, precise: true, invertedFromDevice: true, location: pointer)
        }
        let result = run([.mouseDown(location: press), fingers(15), fingers(5)])
        #expect(result.decisions == [.passThrough, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func scrollingBackToNeutralCancels() {
        let result = run([.mouseDown(location: press), wheel(1), wheel(-1), .mouseUp(location: pointer)])
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(context, nil), .cancel])
    }

    @Test func pointerOffEveryTitlebarIsNotClaimedAndNotRetried() {
        let probe = FakeProbe(window: nil)
        windows.frames[window] = Self.dragged
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(probe: probe, windows: windows) { updates.append($0) }
        _ = recognizer.handle(.mouseDown(location: press))
        let first = recognizer.handle(wheel(1))
        probe.window = window
        let second = recognizer.handle(wheel(1))
        #expect([first, second] == [.passThrough, .passThrough])
        #expect(probe.probedPoints.count == 1)
        #expect(updates.isEmpty)
    }

    @Test func aFrameReadFailureIsNotClaimed() {
        let result = run([.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], windowFrame: nil)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
    }

    @Test func scrollWithoutAPressPassesThrough() {
        let probe = FakeProbe(window: window)
        let result = run([wheel(1)], probe: probe)
        #expect(result.decisions == [.passThrough])
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func theNextPressCancelsADragWhoseReleaseWasLost() {
        let result = run([.mouseDown(location: press), wheel(1), .mouseDown(location: press)])
        #expect(result.updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func resetCancelsAClaimedDrag() {
        windows.frames[window] = Self.dragged
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(probe: FakeProbe(window: window), windows: windows) {
            updates.append($0)
        }
        _ = recognizer.handle(.mouseDown(location: press))
        _ = recognizer.handle(wheel(1))
        recognizer.reset()
        _ = recognizer.handle(.mouseUp(location: pointer))
        #expect(updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func releaseWithoutScrollingDoesNothing() {
        let probe = FakeProbe(window: window)
        let result = run([.mouseDown(location: press), .mouseDragged(location: pointer), .mouseUp(location: pointer)], probe: probe)
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func offInSettingsClaimsNothing() {
        var settings = FlickSettings()
        settings.scrollWhileDragging = false
        let probe = FakeProbe(window: window)
        let result = run([.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func pausedClaimsNothing() {
        windows.frames[window] = Self.dragged
        var updates: [GestureUpdate] = []
        let recognizer = DragScrollRecognizer(probe: FakeProbe(window: window), windows: windows) {
            updates.append($0)
        }
        recognizer.isPaused = true
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)]
        #expect(events.map { recognizer.handle($0) } == [.passThrough, .passThrough, .passThrough])
        #expect(updates.isEmpty)
    }

    @Test func settingsAreReadOncePerDrag() {
        windows.frames[window] = Self.dragged
        var reads = 0
        let recognizer = DragScrollRecognizer(
            probe: FakeProbe(window: window), windows: windows,
            settings: {
                reads += 1
                return FlickSettings()
            }, onUpdate: { _ in })
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), wheel(1), wheel(-1), .mouseUp(location: pointer)]
        _ = events.map { recognizer.handle($0) }
        #expect(reads == 1)
    }

    @Test func thePreviewFollowsThePointer() {
        let later = GlobalPoint(x: 600, y: 400)
        let result = run([.mouseDown(location: press), wheel(1), .mouseDragged(location: later)])
        let moved = GestureContext(window: window, pointer: later, drag: context.drag)
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(moved, .slot(.fill))])
    }

    @Test func trackpadGesturesAndPinchesPassThrough() {
        let result = run([
            .mouseDown(location: press),
            .scroll(phase: .began, deltaX: 0, deltaY: -30, invertedFromDevice: true, location: pointer),
            .momentum(phase: .changed),
            .magnify(phase: .began, magnification: 0.3, location: pointer),
        ])
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
    }

    @Test func tracksFromPressToRelease() {
        let recognizer = DragScrollRecognizer(probe: FakeProbe(window: window), windows: windows) { _ in }
        #expect(!recognizer.isTracking)
        _ = recognizer.handle(.mouseDown(location: press))
        #expect(recognizer.isTracking)
        _ = recognizer.handle(.mouseUp(location: pointer))
        #expect(!recognizer.isTracking)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter DragScrollRecognizerTests`
Expected: build FAILS with "cannot find 'DragScrollRecognizer' in scope".

- [ ] **Step 3: Write the recognizer**

`Sources/FlickCore/DragScrollRecognizer.swift`:

```swift
/// Recognizes scrolling while a window is dragged by its titlebar and turns it into fill and
/// restore updates, committed on release. Mouse events are only observed, never swallowed.
@MainActor
public final class DragScrollRecognizer {
    /// Scroll away from or towards you needed before there is a target. Mouse wheels report
    /// lines, trackpads report points.
    public static let wheelThreshold: Double = 1
    public static let preciseThreshold: Double = 20

    /// While paused, new drags are not claimed. A drag already claimed finishes.
    public var isPaused = false

    private enum State {
        case idle
        /// Button down, no scroll yet.
        case pressed(at: GlobalPoint)
        /// Not a titlebar drag: its scrolls go to the app until release.
        case ignored
        /// Titlebar drag: its scrolls are swallowed. `amount` counts away from you as positive.
        case claimed(GestureContext, amount: Double, target: Target?)
    }

    private let probe: TitlebarProbe
    private let windows: WindowAccess
    private let settings: @MainActor () -> FlickSettings
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    /// - Parameter settings: read once per drag, at its first scroll.
    public init(
        probe: TitlebarProbe,
        windows: WindowAccess,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() },
        onUpdate: @escaping (GestureUpdate) -> Void
    ) {
        self.probe = probe
        self.windows = windows
        self.settings = settings
        self.onUpdate = onUpdate
    }

    /// Whether the left button is down as far as this recognizer knows.
    public var isTracking: Bool {
        if case .idle = state { return false }
        return true
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case let .mouseDown(location):
            // A press while a drag is tracked means its release was lost.
            reset()
            state = .pressed(at: location)
        case let .mouseDragged(location):
            follow(location)
        case .mouseUp:
            release()
        case let .dragScroll(deltaY, precise, inverted, location):
            return scroll(deltaY: deltaY, precise: precise, inverted: inverted, location: location)
        case .scroll, .momentum, .magnify:
            break
        }
        return .passThrough
    }

    /// Abandons a drag in progress, e.g. after the event tap was disabled and events were lost.
    public func reset() {
        if case .claimed = state {
            onUpdate(.cancel)
        }
        state = .idle
    }

    private func follow(_ location: GlobalPoint) {
        guard case let .claimed(context, amount, target) = state else { return }
        let moved = GestureContext(window: context.window, pointer: location, drag: context.drag)
        state = .claimed(moved, amount: amount, target: target)
        if target != nil {
            onUpdate(.preview(moved, target))
        }
    }

    private func release() {
        if case let .claimed(context, _, target) = state {
            if let target {
                onUpdate(.commit(context, target))
            } else {
                onUpdate(.cancel)
            }
        }
        state = .idle
    }

    private func scroll(deltaY: Double, precise: Bool, inverted: Bool, location: GlobalPoint) -> EventDecision {
        switch state {
        case .idle, .ignored:
            return .passThrough
        case let .pressed(press):
            guard let context = claim(press: press, pointer: location) else {
                state = .ignored
                return .passThrough
            }
            state = .claimed(context, amount: 0, target: nil)
        case .claimed:
            break
        }
        accumulate(deltaY: deltaY, precise: precise, inverted: inverted)
        return .swallow
    }

    private func claim(press: GlobalPoint, pointer: GlobalPoint) -> GestureContext? {
        guard !isPaused, settings().scrollWhileDragging,
            let window = probe.window(atTitlebar: pointer),
            let current = windows.frame(of: window)
        else { return nil }
        // A dragged window moves with the pointer, so shifting it back gives its frame at the press.
        let frameAtPress = GlobalRect(
            x: current.x - (pointer.x - press.x), y: current.y - (pointer.y - press.y),
            width: current.width, height: current.height)
        return GestureContext(
            window: window, pointer: pointer, drag: DragContext(frameAtPress: frameAtPress, pressPoint: press))
    }

    private func accumulate(deltaY: Double, precise: Bool, inverted: Bool) {
        guard case let .claimed(context, oldAmount, oldTarget) = state else { return }
        let finger = DirectionClassifier.fingerDelta(
            scrollingDeltaX: 0, scrollingDeltaY: deltaY, invertedFromDevice: inverted)
        // Fingers or wheel moving away from you is "up", a negative dy.
        let amount = oldAmount - finger.dy
        let threshold = precise ? Self.preciseThreshold : Self.wheelThreshold
        let target: Target?
        if amount >= threshold {
            target = .slot(.fill)
        } else if amount <= -threshold {
            target = .restore
        } else {
            target = nil
        }
        state = .claimed(context, amount: amount, target: target)
        if target != oldTarget {
            onUpdate(.preview(context, target))
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DragScrollRecognizerTests`
Expected: 17 tests pass.

- [ ] **Step 5: Full suite and lint**

Run: `task format && task test && task lint`
Expected: 95 tests pass (78 + 17), lint clean.

- [ ] **Step 6: Commit**

Stage `Sources/FlickCore/DragScrollRecognizer.swift Tests/FlickCoreTests/DragScrollRecognizerTests.swift` and hand over:

```sh
gitcs 'feat(core): recognize scrolling while dragging a window by its titlebar'
```

---

### Task 7: Input router

**Files:**
- Create: `Sources/FlickCore/InputRouter.swift`
- Test: `Tests/FlickCoreTests/InputRouterTests.swift`

**Interfaces:**
- Consumes: `GestureRecognizer` (with `isPaused`, `handle`, `reset`), `DragScrollRecognizer` (Task 6: `isPaused`, `isTracking`, `handle`, `reset`); fakes.
- Produces: `@MainActor public final class InputRouter { init(gestures: GestureRecognizer, dragScroll: DragScrollRecognizer); var isPaused: Bool; func handle(_ event: InputEvent) -> EventDecision; func reset() }`.

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/InputRouterTests.swift`:

```swift
import Testing

@testable import FlickCore

@MainActor
@Suite struct InputRouterTests {
    let window = WindowHandle("finder-1")
    let press = GlobalPoint(x: 400, y: 210)
    let pointer = GlobalPoint(x: 450, y: 260)
    let windows = FakeWindows()

    var dragContext: GestureContext {
        GestureContext(
            window: window, pointer: pointer,
            drag: DragContext(frameAtPress: GlobalRect(x: 300, y: 200, width: 640, height: 480), pressPoint: press))
    }
    var swipeContext: GestureContext { GestureContext(window: window, pointer: pointer) }

    func makeRouter(onUpdate: @escaping (GestureUpdate) -> Void) -> InputRouter {
        windows.frames[window] = GlobalRect(x: 350, y: 250, width: 640, height: 480)
        let probe = FakeProbe(window: window)
        return InputRouter(
            gestures: GestureRecognizer(probe: probe, onUpdate: onUpdate),
            dragScroll: DragScrollRecognizer(probe: probe, windows: windows, onUpdate: onUpdate))
    }

    func wheel(_ lines: Double) -> InputEvent {
        .dragScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: pointer)
    }

    func swipe(_ phase: GesturePhase, _ dx: Double = 0) -> InputEvent {
        .scroll(phase: phase, deltaX: dx, deltaY: 0, invertedFromDevice: true, location: pointer)
    }

    @Test func mouseEventsAndDragScrollsGoToTheDragRecognizer() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)]
        #expect(events.map { router.handle($0) } == [.passThrough, .swallow, .passThrough])
        #expect(updates == [.preview(dragContext, .slot(.fill)), .commit(dragContext, .slot(.fill))])
    }

    @Test func trackpadSwipesGoToTheGestureRecognizer() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        #expect([swipe(.began, -60), swipe(.ended)].map { router.handle($0) } == [.swallow, .swallow])
        #expect(updates == [.preview(swipeContext, .slot(.leftHalf)), .commit(swipeContext, .slot(.leftHalf))])
    }

    @Test func aTrackpadScrollDuringATrackedDragCancelsTheDrag() {
        // A trackpad scroll arrives without the button held: the release was lost.
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1), swipe(.began, -60)]
        _ = events.map { router.handle($0) }
        #expect(updates == [.preview(dragContext, .slot(.fill)), .cancel, .preview(swipeContext, .slot(.leftHalf))])
    }

    @Test func resetCancelsATrackedDrag() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.mouseDown(location: press), wheel(1)]
        _ = events.map { router.handle($0) }
        router.reset()
        #expect(updates == [.preview(dragContext, .slot(.fill)), .cancel])
    }

    @Test func resetCancelsASwipe() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        _ = router.handle(swipe(.began, -60))
        router.reset()
        #expect(updates == [.preview(swipeContext, .slot(.leftHalf)), .cancel])
    }

    @Test func pausingPausesBoth() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        router.isPaused = true
        let events: [InputEvent] = [
            .mouseDown(location: press), wheel(1), .mouseUp(location: pointer), swipe(.began, -60), swipe(.ended),
        ]
        #expect(events.map { router.handle($0) } == Array(repeating: .passThrough, count: 5))
        #expect(updates.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter InputRouterTests`
Expected: build FAILS with "cannot find 'InputRouter' in scope".

- [ ] **Step 3: Write the router**

`Sources/FlickCore/InputRouter.swift`:

```swift
/// The event tap's single entry point: hands each event to the recognizer it belongs to.
@MainActor
public final class InputRouter {
    private let gestures: GestureRecognizer
    private let dragScroll: DragScrollRecognizer

    public init(gestures: GestureRecognizer, dragScroll: DragScrollRecognizer) {
        self.gestures = gestures
        self.dragScroll = dragScroll
    }

    /// Pauses or resumes both recognizers.
    public var isPaused: Bool {
        get { gestures.isPaused }
        set {
            gestures.isPaused = newValue
            dragScroll.isPaused = newValue
        }
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            return dragScroll.handle(event)
        case .scroll:
            // A trackpad scroll without the button held: a drag we track ended unseen.
            if dragScroll.isTracking {
                dragScroll.reset()
            }
            return gestures.handle(event)
        case .momentum, .magnify:
            return gestures.handle(event)
        }
    }

    /// Abandons whatever is in progress, e.g. after the event tap was disabled.
    public func reset() {
        gestures.reset()
        dragScroll.reset()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter InputRouterTests`
Expected: 6 tests pass.

- [ ] **Step 5: Full suite and lint**

Run: `task format && task test && task lint`
Expected: 101 tests pass (95 + 6), lint clean.

- [ ] **Step 6: Commit**

Stage `Sources/FlickCore/InputRouter.swift Tests/FlickCoreTests/InputRouterTests.swift` and hand over:

```sh
gitcs 'feat(core): route events to the trackpad and drag + scroll recognizers'
```

---

### Task 8: Controller support for drags

**Files:**
- Modify: `Sources/FlickCore/FlickController.swift` (`handle`, `frame(for:context:)`, `commit`, new `show`/`hide` helpers)
- Modify: `Tests/FlickCoreTests/FlickControllerTests.swift` (`FakePreview.showCount`)
- Test: `Tests/FlickCoreTests/FlickControllerDragTests.swift`

**Interfaces:**
- Consumes: `DragContext`, `GestureContext.drag`, `DragRestore.frame(restoring:drag:pointer:visible:)` (Task 5); `FrameHistory`; fakes.
- Produces: no new API. Behaviour: drag restore goes under the pointer, drag commits record `frameAtPress` as the current frame, `PreviewPresenter.show` is called only when the frame changes.

- [ ] **Step 1: Count shows in the fake**

In `Tests/FlickCoreTests/FlickControllerTests.swift`, replace `FakePreview`:

```swift
@MainActor
final class FakePreview: PreviewPresenter {
    private(set) var shown: GlobalRect?
    private(set) var hideCount = 0

    func show(_ frame: GlobalRect) {
        shown = frame
    }
```

with:

```swift
@MainActor
final class FakePreview: PreviewPresenter {
    private(set) var shown: GlobalRect?
    private(set) var showCount = 0
    private(set) var hideCount = 0

    func show(_ frame: GlobalRect) {
        shown = frame
        showCount += 1
    }
```

- [ ] **Step 2: Write the failing tests**

`Tests/FlickCoreTests/FlickControllerDragTests.swift`:

```swift
import Testing

@testable import FlickCore

@MainActor
@Suite struct FlickControllerDragTests {
    let window = WindowHandle("w")
    let original = GlobalRect(x: 300, y: 200, width: 640, height: 480)
    let left = GlobalRect(x: 8, y: 33, width: 708, height: 859)
    let windows = FakeWindows()
    let preview = FakePreview()
    var plain: GestureContext { GestureContext(window: window, pointer: GlobalPoint(x: 400, y: 210)) }

    func makeController() -> FlickController {
        windows.frames[window] = original
        return FlickController(windows: windows, screens: FakeScreens(), preview: preview)
    }

    /// Dragging the left-half window, grabbed mid-titlebar, with the pointer now at `pointer`.
    func dragOutOfLeftHalf(pointer: GlobalPoint) -> GestureContext {
        GestureContext(
            window: window, pointer: pointer,
            drag: DragContext(frameAtPress: left, pressPoint: GlobalPoint(x: 362, y: 45)))
    }

    @Test func dragFillKeepsTheRestorePointFromBeforeTheFirstSnap() {
        let controller = makeController()
        controller.handle(.commit(plain, .slot(.leftHalf)))
        // The user drags the snapped window 100 pt right and 60 pt down, then scrolls away.
        windows.frames[window] = GlobalRect(x: 108, y: 93, width: 708, height: 859)
        controller.handle(.commit(dragOutOfLeftHalf(pointer: GlobalPoint(x: 462, y: 105)), .slot(.fill)))
        controller.handle(.commit(plain, .restore))
        #expect(windows.frames[window] == original)
    }

    @Test func dragFillOfAnUnsnappedWindowRestoresToItsFrameAtThePress() {
        let controller = makeController()
        windows.frames[window] = GlobalRect(x: 350, y: 250, width: 640, height: 480)
        let drag = GestureContext(
            window: window, pointer: GlobalPoint(x: 450, y: 260),
            drag: DragContext(frameAtPress: original, pressPoint: GlobalPoint(x: 400, y: 210)))
        controller.handle(.commit(drag, .slot(.fill)))
        controller.handle(.commit(plain, .restore))
        #expect(windows.frames[window] == original)
    }

    @Test func dragRestorePutsTheRestoreSizeUnderThePointer() {
        let controller = makeController()
        controller.handle(.commit(plain, .slot(.leftHalf)))
        let drag = dragOutOfLeftHalf(pointer: GlobalPoint(x: 700, y: 300))
        let expected = GlobalRect(x: 380, y: 288, width: 640, height: 480)
        controller.handle(.preview(drag, .restore))
        #expect(preview.shown == expected)
        controller.handle(.commit(drag, .restore))
        #expect(windows.frames[window] == expected)
        controller.handle(.preview(drag, .restore))
        #expect(preview.shown == nil)
    }

    @Test func dragRestoreWithoutHistoryShowsAndDoesNothing() {
        let controller = makeController()
        let drag = dragOutOfLeftHalf(pointer: GlobalPoint(x: 700, y: 300))
        controller.handle(.preview(drag, .restore))
        controller.handle(.commit(drag, .restore))
        #expect(preview.showCount == 0)
        #expect(windows.setCalls.isEmpty)
    }

    @Test func anUnchangedPreviewIsNotShownAgain() {
        let controller = makeController()
        controller.handle(.preview(plain, .slot(.fill)))
        controller.handle(.preview(plain, .slot(.fill)))
        #expect(preview.showCount == 1)
        controller.handle(.cancel)
        controller.handle(.preview(plain, .slot(.fill)))
        #expect(preview.showCount == 2)
    }

    @Test func aRestorePreviewFollowsThePointer() {
        let controller = makeController()
        controller.handle(.commit(plain, .slot(.leftHalf)))
        controller.handle(.preview(dragOutOfLeftHalf(pointer: GlobalPoint(x: 700, y: 300)), .restore))
        controller.handle(.preview(dragOutOfLeftHalf(pointer: GlobalPoint(x: 720, y: 300)), .restore))
        #expect(preview.showCount == 2)
        #expect(preview.shown == GlobalRect(x: 400, y: 288, width: 640, height: 480))
    }
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `swift test --filter FlickControllerDragTests`
Expected: 5 of 6 tests FAIL. `dragFillKeepsTheRestorePointFromBeforeTheFirstSnap` restores to `(108, 93, …)`, `dragFillOfAnUnsnappedWindowRestoresToItsFrameAtThePress` to `(350, 250, …)`, `dragRestorePutsTheRestoreSizeUnderThePointer` shows `original`, `anUnchangedPreviewIsNotShownAgain` counts 2 shows, and `aRestorePreviewFollowsThePointer` shows `original`. `dragRestoreWithoutHistoryShowsAndDoesNothing` already passes; it guards against a regression.

- [ ] **Step 4: Implement**

In `Sources/FlickCore/FlickController.swift`:

Add below `private var history = FrameHistory()`:

```swift
    /// The frame the preview shows right now, so an unchanged preview isn't redrawn.
    private var shownFrame: GlobalRect?
```

Replace `handle(_:)`:

```swift
    public func handle(_ update: GestureUpdate) {
        switch update {
        case let .preview(context, target):
            if settings().livePreview, let target, let frame = frame(for: target, context: context) {
                preview.show(frame)
            } else {
                preview.hide()
            }
        case let .commit(context, target):
            preview.hide()
            commit(target, context: context)
        case .cancel:
            preview.hide()
        }
    }
```

with:

```swift
    public func handle(_ update: GestureUpdate) {
        switch update {
        case let .preview(context, target):
            if settings().livePreview, let target, let frame = frame(for: target, context: context) {
                showPreview(frame)
            } else {
                hidePreview()
            }
        case let .commit(context, target):
            hidePreview()
            commit(target, context: context)
        case .cancel:
            hidePreview()
        }
    }

    private func showPreview(_ frame: GlobalRect) {
        guard frame != shownFrame else { return }
        shownFrame = frame
        preview.show(frame)
    }

    private func hidePreview() {
        shownFrame = nil
        preview.hide()
    }
```

Replace the `.restore` case of `frame(for:context:)`:

```swift
        case .restore:
            return history.peek(for: context.window)
```

with:

```swift
        case .restore:
            guard let original = history.peek(for: context.window) else { return nil }
            guard let drag = context.drag else { return original }
            // During a drag the window comes back at its restore size, under the pointer.
            guard let visible = screens.visibleFrame(containing: context.pointer) else { return nil }
            return DragRestore.frame(restoring: original, drag: drag, pointer: context.pointer, visible: visible)
```

Replace `commit(_:context:)`:

```swift
    private func commit(_ target: Target, context: GestureContext) {
        let window = context.window
        switch target {
        case .slot:
            guard let current = windows.frame(of: window),
                let next = frame(for: target, context: context),
                windows.setFrame(next, of: window)
            else { return }
            // Read back where the window actually ended up: apps may adjust the requested frame.
            let placed = windows.frame(of: window) ?? next
            history.recordMove(from: current, to: placed, for: window)
        case .restore:
            guard let previous = history.take(for: window) else { return }
            _ = windows.setFrame(previous, of: window)
        }
    }
```

with:

```swift
    private func commit(_ target: Target, context: GestureContext) {
        let window = context.window
        switch target {
        case .slot:
            guard let actual = windows.frame(of: window),
                let next = frame(for: target, context: context),
                windows.setFrame(next, of: window)
            else { return }
            // A dragged window counts as still being where it was when the button went down, so
            // dragging a snapped window out and filling it continues the run.
            let current = context.drag?.frameAtPress ?? actual
            // Read back where the window actually ended up: apps may adjust the requested frame.
            let placed = windows.frame(of: window) ?? next
            history.recordMove(from: current, to: placed, for: window)
        case .restore:
            guard let next = frame(for: target, context: context) else { return }
            _ = history.take(for: window)
            _ = windows.setFrame(next, of: window)
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter 'FlickControllerDragTests|FlickControllerTests|FrameHistoryTests'`
Expected: all pass, including the existing restore tests.

- [ ] **Step 6: Full suite and lint**

Run: `task format && task test && task lint`
Expected: 107 tests pass (101 + 6), lint clean.

- [ ] **Step 7: Commit**

Stage `Sources/FlickCore/FlickController.swift Tests/FlickCoreTests/FlickControllerTests.swift Tests/FlickCoreTests/FlickControllerDragTests.swift` and hand over:

```sh
gitcs 'feat(core): fill and restore dragged windows under the pointer'
```

---

### Task 9: Event tap, overlay, settings switch, wiring and docs

App adapters; verified by build, lint and the manual checklist.

**Files:**
- Modify: `Sources/Flick/EventTap.swift`
- Modify: `Sources/Flick/PreviewOverlay.swift` (`show(_:)`)
- Modify: `Sources/Flick/MenuBarApp.swift`
- Modify: `Sources/Flick/SettingsWindow.swift` (one toggle)
- Modify: `README.md`

**Interfaces:**
- Consumes: `InputRouter` (Task 7), `DragScrollRecognizer` (Task 6), `InputEvent` drag cases (Task 5), `SettingsStore` (Task 3), the E1–E5 findings from Task 4.
- Produces: `EventTap.init(router: InputRouter)`.

- [ ] **Step 1: Event tap**

In `Sources/Flick/EventTap.swift`:

Replace the doc comment, the type constants and the stored recognizer:

```swift
/// Session event tap for trackpad scroll and gesture events. Hands every event to the
/// recognizer and drops the ones it claims.
@MainActor
final class EventTap {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "EventTap")
    /// CGEventType raw values for gesture events, which have no named case in the SDK.
    private static let gestureTypes: [UInt32] = [29, 30]

    private let recognizer: GestureRecognizer
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(recognizer: GestureRecognizer) {
        self.recognizer = recognizer
    }
```

with:

```swift
/// Session event tap for scroll and trackpad gesture events, plus left-mouse events for drag +
/// scroll. Hands every event to the router and drops the ones it claims (never mouse events).
@MainActor
final class EventTap {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "EventTap")
    /// CGEventType raw values for gesture events, which have no named case in the SDK.
    private static let gestureTypes: [UInt32] = [29, 30]
    private static let mouseTypes: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]

    private let router: InputRouter
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(router: InputRouter) {
        self.router = router
    }
```

In `start()`, after the `for type in Self.gestureTypes { … }` loop add:

```swift
        for type in Self.mouseTypes {
            mask |= CGEventMask(1) << type.rawValue
        }
```

In `handle(type:input:)`, replace `recognizer.reset()` with `router.reset()` and `return recognizer.handle(input) == .swallow` with `return router.handle(input) == .swallow`.

Replace `EventTranslator` up to (not including) `private static func phase(`:

```swift
/// Converts CGEvents into FlickCore's InputEvent. Returns `nil` for anything Flick ignores
/// (mouse wheels, other gesture kinds).
enum EventTranslator {
    static func input(from cgEvent: CGEvent) -> InputEvent? {
        guard let event = NSEvent(cgEvent: cgEvent) else { return nil }
        let location = GlobalPoint(x: cgEvent.location.x, y: cgEvent.location.y)
        switch event.type {
        case .scrollWheel:
            guard event.hasPreciseScrollingDeltas else { return nil }
            if let momentum = phase(event.momentumPhase) {
                return .momentum(phase: momentum)
            }
            guard let phase = phase(event.phase) else { return nil }
            return .scroll(
                phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
        case .magnify:
            guard let phase = phase(event.phase) else { return nil }
            return .magnify(phase: phase, magnification: event.magnification, location: location)
        default:
            return nil
        }
    }
```

with:

```swift
/// Converts CGEvents into FlickCore's InputEvent. Returns `nil` for anything Flick ignores
/// (mouse wheels without a held button, other gesture kinds).
enum EventTranslator {
    static func input(from cgEvent: CGEvent) -> InputEvent? {
        guard let event = NSEvent(cgEvent: cgEvent) else { return nil }
        let location = GlobalPoint(x: cgEvent.location.x, y: cgEvent.location.y)
        switch event.type {
        case .leftMouseDown:
            return .mouseDown(location: location)
        case .leftMouseDragged:
            return .mouseDragged(location: location)
        case .leftMouseUp:
            return .mouseUp(location: location)
        case .scrollWheel:
            return scroll(event, location: location)
        case .magnify:
            guard let phase = phase(event.phase) else { return nil }
            return .magnify(phase: phase, magnification: event.magnification, location: location)
        default:
            return nil
        }
    }

    private static func scroll(_ event: NSEvent, location: GlobalPoint) -> InputEvent? {
        let momentum = phase(event.momentumPhase)
        // Left button held: a candidate for drag + scroll, mouse wheel and trackpad alike. Asking
        // the event source (not our own mouse-down tracking) means a lost mouse-up can't fool it.
        if momentum == nil, CGEventSource.buttonState(.combinedSessionState, button: .left) {
            return .dragScroll(
                deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
        }
        guard event.hasPreciseScrollingDeltas else { return nil }
        if let momentum {
            return .momentum(phase: momentum)
        }
        guard let phase = phase(event.phase) else { return nil }
        return .scroll(
            phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
    }
```

- [ ] **Step 2: Overlay follows the pointer without lag**

In `Sources/Flick/PreviewOverlay.swift`, replace `show(_:)`:

```swift
    func show(_ frame: GlobalRect) {
        let target = frame.flipped(primaryHeight: ScreenAdapter.primaryHeight).nsRect
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
        }
    }
```

with:

```swift
    func show(_ frame: GlobalRect) {
        let target = frame.flipped(primaryHeight: ScreenAdapter.primaryHeight).nsRect
        // Animate a change of slot; a preview that only moves (following the pointer during a
        // drag) jumps, so it doesn't trail behind.
        if panel.isVisible, panel.frame.size != target.size {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
        }
    }
```

- [ ] **Step 3: Wire the router**

In `Sources/Flick/MenuBarApp.swift`:

Replace `private var recognizer: GestureRecognizer?` with `private var router: InputRouter?`.

In `applicationDidFinishLaunching`, replace:

```swift
        let recognizer = GestureRecognizer(probe: TitlebarHitTester(), settings: { store.settings }) { update in
            DispatchQueue.main.async { controller.handle(update) }
        }
        self.recognizer = recognizer
        tap = EventTap(recognizer: recognizer)
```

with:

```swift
        let onUpdate: (GestureUpdate) -> Void = { update in
            DispatchQueue.main.async { controller.handle(update) }
        }
        let probe = TitlebarHitTester()
        let router = InputRouter(
            gestures: GestureRecognizer(probe: probe, settings: { store.settings }, onUpdate: onUpdate),
            dragScroll: DragScrollRecognizer(
                probe: probe, windows: WindowMover(), settings: { store.settings }, onUpdate: onUpdate))
        self.router = router
        tap = EventTap(router: router)
```

In `refreshMenu()`, replace `let paused = recognizer?.isPaused ?? false` with `let paused = router?.isPaused ?? false`.

In `togglePause()`, replace the two `recognizer?` lines with:

```swift
        router?.isPaused.toggle()
        store.isPaused = router?.isPaused ?? false
```

If the spike's **E4** failed for an app, apply the ledgered delay here: in `onUpdate`, dispatch `.commit` updates whose context has a `drag` with `DispatchQueue.main.asyncAfter(deadline: .now() + <delay>)` instead of `async`.

- [ ] **Step 4: Settings switch**

In `Sources/Flick/SettingsWindow.swift`, in the *Gestures* section after the pinch toggle, add:

```swift
                Toggle(isOn: $store.settings.scrollWhileDragging) {
                    Self.label(
                        "Scroll while dragging to fill and restore",
                        hint: "Drag a window by its titlebar, scroll away to fill, towards you to restore.")
                }
```

- [ ] **Step 5: README**

In `README.md`, replace:

```markdown
*Settings…* (⌘,) in the menu-bar item turns each gesture and the live preview on or off and
```

with:

```markdown
With a mouse (or a trackpad, keeping the click held), drag a window by its titlebar and scroll
while still holding the button:

| While dragging | Result |
|---|---|
| scroll away from you | fill the screen under the pointer |
| scroll towards you | restore the size from before the first snap, under the pointer |

The preview follows the pointer; the window changes when you release the button. Scroll back to
cancel.

*Settings…* (⌘,) in the menu-bar item turns each gesture and the live preview on or off and
```

Append to the end of the *Manual test checklist*:

```markdown
- [ ] Mouse wheel: drag a Finder, Safari, Terminal and VS Code window by its titlebar and scroll away: fill preview; release: the window fills and stays filled.
- [ ] Scroll towards you while dragging a window Flick snapped: original-size preview under the pointer that follows it; release: original size where you let go, fully on screen.
- [ ] Scroll away and back before releasing: no preview, the window stays where you dropped it.
- [ ] Natural scrolling off: same directions as with it on.
- [ ] Trackpad: click-hold a titlebar and scroll with two other fingers: same behaviour.
- [ ] Holding the button in a text area and scrolling (extending a selection) scrolls the app as usual.
- [ ] Second display: drag a window onto it and scroll away: it fills that display.
- [ ] With *Scroll while dragging* off in Settings, scrolling during a drag reaches the app.
```

- [ ] **Step 6: Build, test, lint**

Run: `task format && task build && task test && task lint`
Expected: release build succeeds, 107 tests pass, lint clean.

- [ ] **Step 7: Manual check (user)**

Run: `task run` (re-grant Accessibility if asked). Ask the user to work through the eight new checklist items plus the settings items from Task 3 and the 8 swipe directions as a regression check, and to compare against `docs/design/drag-scroll.png`.
Expected: all items pass. A failing item is fixed in this task before the commit.

- [ ] **Step 8: Commit**

Stage `Sources/Flick/EventTap.swift Sources/Flick/PreviewOverlay.swift Sources/Flick/MenuBarApp.swift Sources/Flick/SettingsWindow.swift README.md` and hand over:

```sh
gitcs 'feat(app): fill and restore by scrolling while dragging a window'
```

- [ ] **Step 9: Stop for PR B**

Part B is complete once the final whole-branch review is done. Ask the user whether to push `feature/no-ref/drag-scroll` and open PR B against `main`.
