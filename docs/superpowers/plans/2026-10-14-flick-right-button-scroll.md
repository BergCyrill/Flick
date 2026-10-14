# Flick Right-Button Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the scroll-to-fill-and-restore gesture use the right mouse button too: hold right on a titlebar, scroll away to fill or towards you to restore, release to apply; a plain right-click on a titlebar is replayed so menus still open. A picker (Off / Left / Right / Both) chooses the button(s).

**Architecture:** `FlickCore` gets a `ScrollButton` setting (migrated from the old `scrollWhileDragging` switch), a shared `ScrollTarget` helper for the amount → fill/restore logic, a new `HoldScrollRecognizer` that swallows titlebar right presses and asks for a replay when no scroll followed, and an `InputRouter` that feeds it. `Flick` adds a third, active event tap for right-mouse events (enabled only while the picker includes Right), replays swallowed clicks with a marker so no tap claims them again, and shows the picker in the settings window.

**Tech Stack:** Swift 6 (Xcode toolchain), SwiftPM, swift-testing, AppKit, SwiftUI, Combine, ApplicationServices; Nix flake dev shell (go-task, swiftlint, pre-commit); Task as task runner.

**Spec:** `docs/superpowers/specs/2026-10-14-flick-right-button-scroll-design.md` (design driver: `docs/design/settings-window.png`; builds on `docs/superpowers/specs/2026-10-14-flick-settings-and-drag-scroll-design.md`)

## Global Constraints

- `swift-tools-version: 6.0`, Swift 6 language mode, deployment target macOS 14. No new package dependencies.
- `FlickCore` imports nothing but `Foundation`. AppKit, SwiftUI, Combine, ApplicationServices and CoreGraphics live in `Sources/Flick/` only.
- No private frameworks or private API.
- Constants: scroll threshold **1 line** (mouse wheel, no precise deltas) and **20 pt** (trackpad, precise deltas); titlebar zone **top 40 pt**; Accessibility timeout **0.25 s** (existing); replay marker **`0x464C_4B52`** in `eventSourceUserData`.
- Settings defaults: `swipeToSnap`, `pinchToFillRestore`, `livePreview` **true**; `scrollButton` **`.left`**. New key `scrollButton` (string: `off`, `left`, `right`, `both`). Old key `scrollWhileDragging` is read only when `scrollButton` was never written: `true` → `.left`, `false` → `.off`; it is never written again.
- Picker copy (spec, verbatim): title **Scroll to fill and restore**; choices **Off**, **Left button**, **Right button**, **Both**; hints — Off: "Scrolling while a button is held always reaches the app." Left button: "Drag a window by its titlebar, scroll away to fill, towards you to restore." Right button: "Hold the right button on a titlebar, scroll away to fill, towards you to restore. Right-click menus on titlebars open on release." Both: "Either button works."
- Settings closures have the type `@escaping @MainActor () -> FlickSettings` with the default `{ FlickSettings() }`. Each recognizer reads settings once per gesture: `HoldScrollRecognizer` at the right press.
- Left-mouse events are **never** swallowed. Right-mouse events are swallowed **only** by `HoldScrollRecognizer` for a press on a titlebar (and that press's drags and release), and only while `scrollButton.includesRight` and not paused. With *Off* or *Left button* the right-mouse tap is disabled.
- Native fullscreen windows stay excluded (the existing `TitlebarHitTester` / `TitlebarZone` check).
- Coordinates in `FlickCore` are global, top-left origin, y down (`GlobalPoint`, `GlobalRect`).
- Tests use swift-testing (`import Testing`, `@Test`, `#expect`). New suites go in **new files** (swiftlint `type_body_length` 250, strict). Functions take **4 parameters or fewer**. Pass `onUpdate:` with its label whenever `settings:` is passed (swiftlint `multiple_closures_with_trailing_closure`). Never capture a `var` in a settings closure (Swift 6 Sendable error/warning): pass a `let` or use `SettingsBox` from `SettingsGatingTests.swift`.
- Commands run inside the dev shell: prefix with `nix develop -c` (direnv is blocked in this checkout). `task format`, `task test`, `task lint` and `task build` must pass at the end of every task.
- Git: branch `feature/no-ref/right-button-scroll` (exists; holds the spec commit 2de7f9b). **Never run `git commit` yourself.** At each commit step, stage the listed files, hand the user the `gitcs '<message>'` command (signing alias, needs a hardware token) and wait for "done". Conventional Commits. Pushing and opening the PR only when the user asks.

## Review Focus

1. **Right-clicks while the picker doesn't include Right** (the default *Left button*, and *Off*) must reach the app on press exactly as before. Pinned by `offClaimsNothing` and `leftOnlyClaimsNothing` (Task 3); the right-mouse tap stays disabled (Task 5, manual item "Right-clicks … with every picker value").
2. **A plain right-click on a titlebar** must open the app's menu exactly once: replayed, not lost, not claimed again by Flick's own taps. Pinned by `releaseWithoutScrollingAsksForAReplay` and `movingWithoutScrollingStillAsksForAReplay` (Task 3) and the manual items in Task 5.
3. **A lost release or a disabled tap during a hold** must not leave a preview up or a hold claimed. Pinned by `theNextPressCancelsAHoldWhoseReleaseWasLost` and `resetCancelsAHoldAndItsReleasePassesThrough` (Task 3), `aTrackpadScrollThatBeginsCancelsATrackedHold` and `resetCancelsATrackedHold` (Task 4). Disabling the right-mouse tap from the picker can deliver `tapDisabledByUserInput`; the handler must leave that tap disabled (Task 5, `enableTaps()`).
4. **People who had the old switch** must keep their choice. Pinned by `theOldSwitchOnBecomesTheLeftButton`, `theOldSwitchOffBecomesOff` and `theScrollButtonWinsOverTheOldSwitch` (Task 1) and the relaunch item in Task 5.
5. **Mouse wheel vs. trackpad, natural vs. classic scrolling** during a hold give the same physical direction and thresholds as drag + scroll. Pinned by `ScrollTargetTests` (Task 2), `naturalScrollingGivesTheSameDirection` and `aTrackpadNeedsTwentyPoints` (Task 3).

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/FlickCore/ScrollButton.swift` (new) | 1 | The picker's value and which buttons it includes |
| `Sources/FlickCore/FlickSettings.swift` | 1 | `scrollButton` replaces `scrollWhileDragging`, with the carry-over |
| `Sources/FlickCore/DragScrollRecognizer.swift` | 1, 2, 3 | Claims only with `includesLeft`; uses `ScrollTarget`; passes right-button events |
| `Sources/Flick/SettingsWindow.swift` | 1 | The picker and its copy |
| `Sources/FlickCore/ScrollTarget.swift` (new) | 2 | Amount → fill / restore / none, shared by both scroll recognizers |
| `Sources/FlickCore/InputEvent.swift` | 3 | Right-button cases, `.holdScroll`, `EventDecision.replayPress` |
| `Sources/FlickCore/HoldScrollRecognizer.swift` (new) | 3 | Right-button hold + scroll |
| `Sources/FlickCore/GestureRecognizer.swift` | 3 | Passes right-button events through |
| `Sources/FlickCore/InputRouter.swift` | 3, 4 | Routes to the third recognizer |
| `Sources/Flick/MenuBarApp.swift` | 4, 5 | Wiring; switches the right-mouse tap with the setting |
| `Sources/Flick/EventTap.swift` | 5 | Third tap, translation, replay |
| `README.md` | 5 | Usage and manual checklist |
| `Tests/FlickCoreTests/FlickSettingsTests.swift` | 1 | Setting and carry-over |
| `Tests/FlickCoreTests/DragScrollRecognizerTests.swift` | 1 | Picker values for the left button |
| `Tests/FlickCoreTests/ScrollTargetTests.swift` (new) | 2 | Thresholds and direction |
| `Tests/FlickCoreTests/HoldScrollRecognizerTests.swift` (new) | 3 | The new recognizer |
| `Tests/FlickCoreTests/InputRouterTests.swift` | 4 | Routing to the third recognizer |

Test counts: 108 now → 116 (Task 1) → 120 (Task 2) → 140 (Task 3) → 143 (Task 4) → 143 (Task 5).

---

### Task 1: Scroll button setting and picker

**Files:**
- Create: `Sources/FlickCore/ScrollButton.swift`
- Modify: `Sources/FlickCore/FlickSettings.swift` (whole file)
- Modify: `Sources/FlickCore/DragScrollRecognizer.swift:112` (`claim`)
- Modify: `Sources/Flick/SettingsWindow.swift` (imports, the third toggle, new private extension)
- Test: `Tests/FlickCoreTests/FlickSettingsTests.swift` (whole file), `Tests/FlickCoreTests/DragScrollRecognizerTests.swift` (`offInSettingsClaimsNothing`)

**Interfaces:**
- Consumes: `FlickSettings` (`init()`, `init(defaults:)`, `save(to:)`), `DragScrollRecognizerTests.run(_:probe:windowFrame:settings:)`.
- Produces: `public enum ScrollButton: String, CaseIterable, Equatable, Sendable { case off, left, right, both; var includesLeft: Bool; var includesRight: Bool }`; `FlickSettings.scrollButton: ScrollButton` (default `.left`); `FlickSettings.scrollWhileDragging` no longer exists.

- [ ] **Step 1: Write the failing tests**

Replace `Tests/FlickCoreTests/FlickSettingsTests.swift` with:

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

    @Test func gesturesAreOnByDefaultWithTheLeftButton() {
        let settings = FlickSettings()
        #expect(settings.swipeToSnap)
        #expect(settings.pinchToFillRestore)
        #expect(settings.scrollButton == .left)
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
            settings.scrollButton = .both
            settings.livePreview = false
            settings.save(to: defaults)
            #expect(FlickSettings(defaults: defaults) == settings)
        }
    }

    @Test func eachSwitchIsStoredUnderItsOwnKey() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.livePreview = false
            settings.save(to: defaults)
            #expect(defaults.object(forKey: "livePreview") as? Bool == false)
            #expect(defaults.object(forKey: "swipeToSnap") as? Bool == true)
        }
    }

    @Test func theScrollButtonIsStoredByName() {
        withDefaults { defaults in
            var settings = FlickSettings()
            settings.scrollButton = .right
            settings.save(to: defaults)
            #expect(defaults.string(forKey: "scrollButton") == "right")
        }
    }

    @Test func theOldSwitchOnBecomesTheLeftButton() {
        withDefaults { defaults in
            defaults.set(true, forKey: "scrollWhileDragging")
            #expect(FlickSettings(defaults: defaults).scrollButton == .left)
        }
    }

    @Test func theOldSwitchOffBecomesOff() {
        withDefaults { defaults in
            defaults.set(false, forKey: "scrollWhileDragging")
            #expect(FlickSettings(defaults: defaults).scrollButton == .off)
        }
    }

    @Test func theScrollButtonWinsOverTheOldSwitch() {
        withDefaults { defaults in
            defaults.set(false, forKey: "scrollWhileDragging")
            defaults.set("right", forKey: "scrollButton")
            #expect(FlickSettings(defaults: defaults).scrollButton == .right)
        }
    }

    @Test func anUnknownScrollButtonKeepsTheDefault() {
        withDefaults { defaults in
            defaults.set("middle", forKey: "scrollButton")
            #expect(FlickSettings(defaults: defaults).scrollButton == .left)
        }
    }

    @Test func eachChoiceIncludesItsButtons() {
        #expect(ScrollButton.allCases.map(\.includesLeft) == [false, true, false, true])
        #expect(ScrollButton.allCases.map(\.includesRight) == [false, false, true, true])
    }
}
```

In `Tests/FlickCoreTests/DragScrollRecognizerTests.swift`, replace:

```swift
    @Test func offInSettingsClaimsNothing() {
        var settings = FlickSettings()
        settings.scrollWhileDragging = false
        let probe = FakeProbe(window: window)
        let result = run(
            [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }
```

with:

```swift
    @Test func offClaimsNothing() {
        claimsNothing(with: .off)
    }

    @Test func rightOnlyClaimsNothing() {
        claimsNothing(with: .right)
    }

    func claimsNothing(with button: ScrollButton) {
        var settings = FlickSettings()
        settings.scrollButton = button
        let probe = FakeProbe(window: window)
        let result = run(
            [.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], probe: probe, settings: settings)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func bothClaimsTheDrag() {
        var settings = FlickSettings()
        settings.scrollButton = .both
        let result = run([.mouseDown(location: press), wheel(1), .mouseUp(location: pointer)], settings: settings)
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `nix develop -c swift test --filter 'FlickSettingsTests|DragScrollRecognizerTests'`
Expected: build FAILS with "value of type 'FlickSettings' has no member 'scrollButton'" and "cannot find 'ScrollButton' in scope".

- [ ] **Step 3: Add the setting**

Create `Sources/FlickCore/ScrollButton.swift`:

```swift
/// Which mouse button scroll to fill and restore listens to: the left one while a window is
/// dragged, the right one while it is held on a titlebar.
public enum ScrollButton: String, CaseIterable, Equatable, Sendable {
    case off, left, right, both

    public var includesLeft: Bool { self == .left || self == .both }
    public var includesRight: Bool { self == .right || self == .both }
}
```

Replace `Sources/FlickCore/FlickSettings.swift` with:

```swift
import Foundation

/// What the user turned on or off in the settings window. Launch at login isn't part of it:
/// macOS owns that state.
public struct FlickSettings: Equatable, Sendable {
    public var swipeToSnap = true
    public var pinchToFillRestore = true
    public var scrollButton = ScrollButton.left
    public var livePreview = true

    public init() {}

    /// Reads the settings from `defaults`. Keys that were never written keep their default.
    public init(defaults: UserDefaults) {
        for (key, path) in Self.keys {
            if let value = defaults.object(forKey: key) as? Bool {
                self[keyPath: path] = value
            }
        }
        if let name = defaults.string(forKey: Self.scrollButtonKey), let button = ScrollButton(rawValue: name) {
            scrollButton = button
        } else if let wasOn = defaults.object(forKey: Self.oldScrollKey) as? Bool {
            // Carried over from the switch the picker replaced.
            scrollButton = wasOn ? .left : .off
        }
    }

    public func save(to defaults: UserDefaults) {
        for (key, path) in Self.keys {
            defaults.set(self[keyPath: path], forKey: key)
        }
        defaults.set(scrollButton.rawValue, forKey: Self.scrollButtonKey)
    }

    private static let scrollButtonKey = "scrollButton"
    /// The switch that came before the picker: read once to carry its value over, never written.
    private static let oldScrollKey = "scrollWhileDragging"

    private static var keys: [(String, WritableKeyPath<FlickSettings, Bool>)] {
        [
            ("swipeToSnap", \.swipeToSnap),
            ("pinchToFillRestore", \.pinchToFillRestore),
            ("livePreview", \.livePreview),
        ]
    }
}
```

In `Sources/FlickCore/DragScrollRecognizer.swift`, in `claim(press:pointer:)`, replace `guard !isPaused, settings().scrollWhileDragging,` with `guard !isPaused, settings().scrollButton.includesLeft,`.

- [ ] **Step 4: Show the picker**

In `Sources/Flick/SettingsWindow.swift`, add `import FlickCore` between `import AppKit` and `import SwiftUI`, and replace:

```swift
                Toggle(isOn: $store.settings.scrollWhileDragging) {
                    Self.label(
                        "Scroll while dragging to fill and restore",
                        hint: "Drag a window by its titlebar, scroll away to fill, towards you to restore.")
                }
```

with:

```swift
                Picker(selection: $store.settings.scrollButton) {
                    ForEach(ScrollButton.allCases, id: \.self) { button in
                        Text(button.title).tag(button)
                    }
                } label: {
                    Self.label("Scroll to fill and restore", hint: store.settings.scrollButton.hint)
                }
```

Append to the end of the file:

```swift
/// Picker copy from the design drawing (board *Settings window*).
private extension ScrollButton {
    var title: String {
        switch self {
        case .off: "Off"
        case .left: "Left button"
        case .right: "Right button"
        case .both: "Both"
        }
    }

    var hint: String {
        switch self {
        case .off: "Scrolling while a button is held always reaches the app."
        case .left: "Drag a window by its titlebar, scroll away to fill, towards you to restore."
        case .right:
            "Hold the right button on a titlebar, scroll away to fill, towards you to restore. "
                + "Right-click menus on titlebars open on release."
        case .both: "Either button works."
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `nix develop -c swift test --filter 'FlickSettingsTests|DragScrollRecognizerTests'`
Expected: all pass (10 in `FlickSettingsTests`, 19 in `DragScrollRecognizerTests`).

- [ ] **Step 6: Full suite, lint, build**

Run: `nix develop -c sh -c 'task format && task test && task lint && task build'`
Expected: 116 tests pass (108 + 6 + 2), lint clean, build succeeds.

- [ ] **Step 7: Commit**

Stage `Sources/FlickCore/ScrollButton.swift Sources/FlickCore/FlickSettings.swift Sources/FlickCore/DragScrollRecognizer.swift Sources/Flick/SettingsWindow.swift Tests/FlickCoreTests/FlickSettingsTests.swift Tests/FlickCoreTests/DragScrollRecognizerTests.swift` and hand over:

```sh
gitcs 'feat(settings): choose the button for scroll to fill and restore'
```

---

### Task 2: Shared scroll target

**Files:**
- Create: `Sources/FlickCore/ScrollTarget.swift`
- Modify: `Sources/FlickCore/DragScrollRecognizer.swift` (remove `wheelThreshold`/`preciseThreshold`, rewrite `accumulate`)
- Test: `Tests/FlickCoreTests/ScrollTargetTests.swift`

**Interfaces:**
- Consumes: `DirectionClassifier.fingerDelta(scrollingDeltaX:scrollingDeltaY:invertedFromDevice:)`, `Target`.
- Produces: `public enum ScrollTarget { static let wheelThreshold: Double = 1; static let preciseThreshold: Double = 20; static func step(deltaY: Double, invertedFromDevice: Bool) -> Double; static func target(amount: Double, precise: Bool) -> Target? }`. `DragScrollRecognizer.wheelThreshold` / `.preciseThreshold` are removed (nothing else uses them).

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/ScrollTargetTests.swift`:

```swift
import Testing

@testable import FlickCore

@Suite struct ScrollTargetTests {
    @Test func aWheelRolledAwayFromYouCountsPositive() {
        #expect(ScrollTarget.step(deltaY: 1, invertedFromDevice: false) == 1)
        #expect(ScrollTarget.step(deltaY: -1, invertedFromDevice: false) == -1)
    }

    @Test func naturalScrollingFlipsTheSign() {
        #expect(ScrollTarget.step(deltaY: -1, invertedFromDevice: true) == 1)
    }

    @Test func oneWheelLineFillsOrRestores() {
        #expect(ScrollTarget.target(amount: 1, precise: false) == .slot(.fill))
        #expect(ScrollTarget.target(amount: -1, precise: false) == .restore)
        #expect(ScrollTarget.target(amount: 0.5, precise: false) == nil)
    }

    @Test func aTrackpadNeedsTwentyPoints() {
        #expect(ScrollTarget.target(amount: 19, precise: true) == nil)
        #expect(ScrollTarget.target(amount: 20, precise: true) == .slot(.fill))
        #expect(ScrollTarget.target(amount: -20, precise: true) == .restore)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `nix develop -c swift test --filter ScrollTargetTests`
Expected: build FAILS with "cannot find 'ScrollTarget' in scope".

- [ ] **Step 3: Write the helper and use it**

`Sources/FlickCore/ScrollTarget.swift`:

```swift
/// Turns scrolling while a mouse button is held into fill or restore: away from you fills,
/// towards you restores, once the amount passes the device's threshold.
public enum ScrollTarget {
    /// Mouse wheels report lines, trackpads report points.
    public static let wheelThreshold: Double = 1
    public static let preciseThreshold: Double = 20

    /// How far one scroll event moves the amount; away from you counts positive.
    public static func step(deltaY: Double, invertedFromDevice: Bool) -> Double {
        let finger = DirectionClassifier.fingerDelta(
            scrollingDeltaX: 0, scrollingDeltaY: deltaY, invertedFromDevice: invertedFromDevice)
        // Fingers or wheel moving away from you is "up", a negative dy.
        return -finger.dy
    }

    public static func target(amount: Double, precise: Bool) -> Target? {
        let threshold = precise ? preciseThreshold : wheelThreshold
        if amount >= threshold { return .slot(.fill) }
        if amount <= -threshold { return .restore }
        return nil
    }
}
```

In `Sources/FlickCore/DragScrollRecognizer.swift`, delete:

```swift
    /// Scroll away from or towards you needed before there is a target. Mouse wheels report
    /// lines, trackpads report points.
    public static let wheelThreshold: Double = 1
    public static let preciseThreshold: Double = 20

```

and replace `accumulate(deltaY:precise:inverted:)` with:

```swift
    private func accumulate(deltaY: Double, precise: Bool, inverted: Bool) {
        guard case let .claimed(context, oldAmount, oldTarget) = state else { return }
        let amount = oldAmount + ScrollTarget.step(deltaY: deltaY, invertedFromDevice: inverted)
        let target = ScrollTarget.target(amount: amount, precise: precise)
        state = .claimed(context, amount: amount, target: target)
        if target != oldTarget {
            onUpdate(.preview(context, target))
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nix develop -c swift test --filter 'ScrollTargetTests|DragScrollRecognizerTests'`
Expected: all pass (4 + 19); the drag tests prove the refactor kept thresholds and direction.

- [ ] **Step 5: Full suite, lint, build**

Run: `nix develop -c sh -c 'task format && task test && task lint && task build'`
Expected: 120 tests pass, lint clean, build succeeds.

- [ ] **Step 6: Commit**

Stage `Sources/FlickCore/ScrollTarget.swift Sources/FlickCore/DragScrollRecognizer.swift Tests/FlickCoreTests/ScrollTargetTests.swift` and hand over:

```sh
gitcs 'refactor(core): share the scroll target between scroll recognizers'
```

---

### Task 3: Hold + scroll recognizer

**Files:**
- Modify: `Sources/FlickCore/InputEvent.swift` (new cases, `EventDecision.replayPress`)
- Create: `Sources/FlickCore/HoldScrollRecognizer.swift`
- Modify: `Sources/FlickCore/GestureRecognizer.swift` (`handle(_:)` switch), `Sources/FlickCore/DragScrollRecognizer.swift` (`handle(_:)` switch), `Sources/FlickCore/InputRouter.swift` (`handle(_:)` switch, temporary)
- Test: `Tests/FlickCoreTests/HoldScrollRecognizerTests.swift`

**Interfaces:**
- Consumes: `ScrollButton.includesRight` (Task 1), `ScrollTarget.step`/`.target` (Task 2), `TitlebarProbe`, `GestureContext(window:pointer:)`, `GestureUpdate`, `FakeProbe`, `FakeWindows`, `SettingsBox`.
- Produces:
  - `InputEvent` cases `.rightMouseDown(location: GlobalPoint)`, `.rightMouseDragged(location: GlobalPoint)`, `.rightMouseUp(location: GlobalPoint)`, `.holdScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)`.
  - `EventDecision.replayPress`.
  - `@MainActor public final class HoldScrollRecognizer { init(probe: TitlebarProbe, settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() }, onUpdate: @escaping (GestureUpdate) -> Void); var isPaused: Bool; var isTracking: Bool { get }; func handle(_ event: InputEvent) -> EventDecision; func reset() }`.

- [ ] **Step 1: Write the failing tests**

`Tests/FlickCoreTests/HoldScrollRecognizerTests.swift`:

```swift
import Testing

@testable import FlickCore

@MainActor
@Suite struct HoldScrollRecognizerTests {
    let window = WindowHandle("finder-1")
    /// On the window's titlebar.
    let press = GlobalPoint(x: 400, y: 210)
    let later = GlobalPoint(x: 600, y: 400)
    static let right: FlickSettings = {
        var settings = FlickSettings()
        settings.scrollButton = .right
        return settings
    }()

    var context: GestureContext { GestureContext(window: window, pointer: press) }

    /// Classic scrolling mouse wheel: rolling it away from you gives positive deltas.
    func wheel(_ lines: Double) -> InputEvent {
        .holdScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: press)
    }

    func run(
        _ events: [InputEvent], probe: FakeProbe? = nil, settings: FlickSettings = HoldScrollRecognizerTests.right
    ) -> (decisions: [EventDecision], updates: [GestureUpdate]) {
        var updates: [GestureUpdate] = []
        let recognizer = HoldScrollRecognizer(
            probe: probe ?? FakeProbe(window: window), settings: { settings }, onUpdate: { updates.append($0) })
        let decisions = events.map { recognizer.handle($0) }
        return (decisions, updates)
    }

    func settings(_ button: ScrollButton) -> FlickSettings {
        var settings = FlickSettings()
        settings.scrollButton = button
        return settings
    }

    @Test func scrollingAwayWhileHoldingPreviewsFillAndReleaseCommitsIt() {
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)])
        #expect(result.decisions == [.swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .commit(context, .slot(.fill))])
    }

    @Test func scrollingTowardsYouTargetsRestore() {
        let result = run([.rightMouseDown(location: press), wheel(-1), .rightMouseUp(location: press)])
        #expect(result.updates == [.preview(context, .restore), .commit(context, .restore)])
    }

    @Test func naturalScrollingGivesTheSameDirection() {
        let away = InputEvent.holdScroll(deltaY: -1, precise: false, invertedFromDevice: true, location: press)
        let result = run([.rightMouseDown(location: press), away])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func aTrackpadNeedsTwentyPoints() {
        // Natural scrolling trackpad: fingers moving away give negative deltas.
        func fingers(_ points: Double) -> InputEvent {
            .holdScroll(deltaY: -points, precise: true, invertedFromDevice: true, location: press)
        }
        let result = run([.rightMouseDown(location: press), fingers(15), fingers(5)])
        #expect(result.decisions == [.swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill))])
    }

    @Test func releaseWithoutScrollingAsksForAReplay() {
        let result = run([.rightMouseDown(location: press), .rightMouseUp(location: press)])
        #expect(result.decisions == [.swallow, .replayPress])
        #expect(result.updates.isEmpty)
    }

    @Test func movingWithoutScrollingStillAsksForAReplay() {
        let result = run([
            .rightMouseDown(location: press), .rightMouseDragged(location: later), .rightMouseUp(location: later),
        ])
        #expect(result.decisions == [.swallow, .swallow, .replayPress])
        #expect(result.updates.isEmpty)
    }

    @Test func scrollingBackToNeutralCancelsWithoutAReplay() {
        let result = run([.rightMouseDown(location: press), wheel(1), wheel(-1), .rightMouseUp(location: press)])
        #expect(result.decisions == [.swallow, .swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(context, nil), .cancel])
    }

    @Test func aPressOffEveryTitlebarIsNotClaimed() {
        let probe = FakeProbe(window: nil)
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)], probe: probe)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints == [press])
    }

    @Test func offClaimsNothing() {
        let probe = FakeProbe(window: window)
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, probe: probe, settings: settings(.off))
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func leftOnlyClaimsNothing() {
        let probe = FakeProbe(window: window)
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, probe: probe, settings: settings(.left))
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func bothClaims() {
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, settings: settings(.both))
        #expect(result.decisions == [.swallow, .swallow, .swallow])
    }

    @Test func pausedClaimsNothing() {
        var updates: [GestureUpdate] = []
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { Self.right }, onUpdate: { updates.append($0) })
        recognizer.isPaused = true
        let events: [InputEvent] = [.rightMouseDown(location: press), wheel(1), .rightMouseUp(location: press)]
        #expect(events.map { recognizer.handle($0) } == [.passThrough, .passThrough, .passThrough])
        #expect(updates.isEmpty)
    }

    @Test func settingsAreReadOncePerHold() {
        let box = SettingsBox()
        box.settings.scrollButton = .right
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { box.read() }, onUpdate: { _ in })
        let events: [InputEvent] = [
            .rightMouseDown(location: press), wheel(1), wheel(1), wheel(-1), .rightMouseUp(location: press),
        ]
        _ = events.map { recognizer.handle($0) }
        #expect(box.reads == 1)
    }

    @Test func thePreviewFollowsThePointer() {
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseDragged(location: later)])
        let moved = GestureContext(window: window, pointer: later)
        #expect(result.updates == [.preview(context, .slot(.fill)), .preview(moved, .slot(.fill))])
    }

    @Test func eventsWithoutAPressPassThrough() {
        let probe = FakeProbe(window: window)
        let events: [InputEvent] = [.rightMouseDragged(location: later), wheel(1), .rightMouseUp(location: press)]
        let result = run(events, probe: probe)
        #expect(result.decisions == [.passThrough, .passThrough, .passThrough])
        #expect(result.updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }

    @Test func theNextPressCancelsAHoldWhoseReleaseWasLost() {
        let result = run([.rightMouseDown(location: press), wheel(1), .rightMouseDown(location: press)])
        #expect(result.decisions == [.swallow, .swallow, .swallow])
        #expect(result.updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func resetCancelsAHoldAndItsReleasePassesThrough() {
        var updates: [GestureUpdate] = []
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { Self.right }, onUpdate: { updates.append($0) })
        _ = recognizer.handle(.rightMouseDown(location: press))
        _ = recognizer.handle(wheel(1))
        recognizer.reset()
        #expect(recognizer.handle(.rightMouseUp(location: press)) == .passThrough)
        #expect(updates == [.preview(context, .slot(.fill)), .cancel])
    }

    @Test func otherEventsPassThroughWhileHolding() {
        let result = run([
            .rightMouseDown(location: press),
            .scroll(phase: .began, deltaX: -60, deltaY: 0, invertedFromDevice: true, location: press),
            .momentum(phase: .changed),
            .magnify(phase: .began, magnification: 0.3, location: press),
            .mouseDown(location: press),
            .dragScroll(deltaY: 1, precise: false, invertedFromDevice: false, location: press),
            .mouseUp(location: press),
        ])
        #expect(result.decisions == [.swallow] + Array(repeating: .passThrough, count: 6))
        #expect(result.updates.isEmpty)
    }

    @Test func tracksFromPressToRelease() {
        let recognizer = HoldScrollRecognizer(
            probe: FakeProbe(window: window), settings: { Self.right }, onUpdate: { _ in })
        #expect(!recognizer.isTracking)
        _ = recognizer.handle(.rightMouseDown(location: press))
        #expect(recognizer.isTracking)
        _ = recognizer.handle(.rightMouseUp(location: press))
        #expect(!recognizer.isTracking)
    }
}

@MainActor
@Suite struct RightButtonEventsInTheOtherRecognizersTests {
    @Test func rightButtonEventsPassThroughTheTrackpadAndDragRecognizers() {
        let point = GlobalPoint(x: 400, y: 210)
        let probe = FakeProbe(window: WindowHandle("w"))
        var updates: [GestureUpdate] = []
        let gestures = GestureRecognizer(probe: probe) { updates.append($0) }
        let drags = DragScrollRecognizer(probe: probe, windows: FakeWindows()) { updates.append($0) }
        let events: [InputEvent] = [
            .rightMouseDown(location: point), .rightMouseDragged(location: point),
            .holdScroll(deltaY: 1, precise: false, invertedFromDevice: false, location: point),
            .rightMouseUp(location: point),
        ]
        #expect(events.map { gestures.handle($0) } == Array(repeating: .passThrough, count: 4))
        #expect(events.map { drags.handle($0) } == Array(repeating: .passThrough, count: 4))
        #expect(updates.isEmpty)
        #expect(probe.probedPoints.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `nix develop -c swift test --filter 'HoldScrollRecognizerTests|RightButtonEventsInTheOtherRecognizersTests'`
Expected: build FAILS with "cannot find 'HoldScrollRecognizer' in scope" and "type 'InputEvent' has no member 'rightMouseDown'".

- [ ] **Step 3: Add the events and the decision**

In `Sources/FlickCore/InputEvent.swift`, replace:

```swift
    case dragScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)
}

/// What the event tap should do with an event.
public enum EventDecision: Equatable, Sendable {
    case passThrough
    case swallow
}
```

with:

```swift
    case dragScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)
    /// Right mouse button pressed, moved while pressed, released. Swallowed only for a press on a
    /// titlebar while hold + scroll is on.
    case rightMouseDown(location: GlobalPoint)
    case rightMouseDragged(location: GlobalPoint)
    case rightMouseUp(location: GlobalPoint)
    /// A scroll while the right (and not the left) mouse button is held, momentum excluded.
    /// Deltas as for `dragScroll`.
    case holdScroll(deltaY: Double, precise: Bool, invertedFromDevice: Bool, location: GlobalPoint)
}

/// What the event tap should do with an event.
public enum EventDecision: Equatable, Sendable {
    case passThrough
    case swallow
    /// For a release: swallow it, then post the swallowed press and this release again, in that
    /// order, so the app gets its click after all.
    case replayPress
}
```

In `Sources/FlickCore/GestureRecognizer.swift`, in `handle(_:)`, replace:

```swift
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            // Drag + scroll belongs to DragScrollRecognizer.
            return .passThrough
```

with:

```swift
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll,
            .rightMouseDown, .rightMouseDragged, .rightMouseUp, .holdScroll:
            // Drag + scroll and hold + scroll belong to their own recognizers.
            return .passThrough
```

In `Sources/FlickCore/DragScrollRecognizer.swift`, in `handle(_:)`, replace:

```swift
        case .scroll, .momentum, .magnify:
            break
```

with:

```swift
        case .scroll, .momentum, .magnify, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .holdScroll:
            break
```

In `Sources/FlickCore/InputRouter.swift`, in `handle(_:)`, after the `case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:` branch add (Task 4 replaces it):

```swift
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp, .holdScroll:
            // No recognizer for the right button is wired in yet.
            return .passThrough
```

- [ ] **Step 4: Write the recognizer**

`Sources/FlickCore/HoldScrollRecognizer.swift`:

```swift
/// Recognizes scrolling while the right button is held on a titlebar and turns it into fill and
/// restore updates, committed on release. The press is swallowed so the app shows no menu; a
/// release without any scroll asks for the click to be replayed.
@MainActor
public final class HoldScrollRecognizer {
    /// While paused, new presses are not claimed. A hold already claimed finishes.
    public var isPaused = false

    private enum State {
        case idle
        /// Not a claimed press: everything passes until the release.
        case ignored
        /// Titlebar press swallowed. `amount` counts away from you as positive.
        case holding(GestureContext, amount: Double, target: Target?, scrolled: Bool)
    }

    private let probe: TitlebarProbe
    private let settings: @MainActor () -> FlickSettings
    private let onUpdate: (GestureUpdate) -> Void
    private var state: State = .idle

    /// - Parameter settings: read once per hold, at the press.
    public init(
        probe: TitlebarProbe,
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() },
        onUpdate: @escaping (GestureUpdate) -> Void
    ) {
        self.probe = probe
        self.settings = settings
        self.onUpdate = onUpdate
    }

    /// Whether the right button is down as far as this recognizer knows.
    public var isTracking: Bool {
        if case .idle = state { return false }
        return true
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case let .rightMouseDown(location):
            // A press while a hold is tracked means its release was lost.
            reset()
            return press(at: location)
        case let .rightMouseDragged(location):
            return follow(location)
        case .rightMouseUp:
            return release()
        case let .holdScroll(deltaY, precise, inverted, _):
            return scroll(deltaY: deltaY, precise: precise, inverted: inverted)
        case .scroll, .momentum, .magnify, .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            return .passThrough
        }
    }

    /// Abandons a hold in progress, e.g. after the event tap was disabled and events were lost.
    /// Its press is dropped, not replayed.
    public func reset() {
        if case .holding = state {
            onUpdate(.cancel)
        }
        state = .idle
    }

    private func press(at location: GlobalPoint) -> EventDecision {
        guard !isPaused, settings().scrollButton.includesRight,
            let window = probe.window(atTitlebar: location)
        else {
            state = .ignored
            return .passThrough
        }
        let context = GestureContext(window: window, pointer: location)
        state = .holding(context, amount: 0, target: nil, scrolled: false)
        return .swallow
    }

    private func follow(_ location: GlobalPoint) -> EventDecision {
        guard case let .holding(context, amount, target, scrolled) = state else { return .passThrough }
        let moved = GestureContext(window: context.window, pointer: location)
        state = .holding(moved, amount: amount, target: target, scrolled: scrolled)
        if target != nil {
            onUpdate(.preview(moved, target))
        }
        return .swallow
    }

    private func release() -> EventDecision {
        defer { state = .idle }
        guard case let .holding(context, _, target, scrolled) = state else { return .passThrough }
        if let target {
            onUpdate(.commit(context, target))
            return .swallow
        }
        if scrolled {
            onUpdate(.cancel)
            return .swallow
        }
        return .replayPress
    }

    private func scroll(deltaY: Double, precise: Bool, inverted: Bool) -> EventDecision {
        guard case let .holding(context, oldAmount, oldTarget, _) = state else { return .passThrough }
        let amount = oldAmount + ScrollTarget.step(deltaY: deltaY, invertedFromDevice: inverted)
        let target = ScrollTarget.target(amount: amount, precise: precise)
        state = .holding(context, amount: amount, target: target, scrolled: true)
        if target != oldTarget {
            onUpdate(.preview(context, target))
        }
        return .swallow
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `nix develop -c swift test --filter 'HoldScrollRecognizerTests|RightButtonEventsInTheOtherRecognizersTests'`
Expected: 20 tests pass.

- [ ] **Step 6: Full suite, lint, build**

Run: `nix develop -c sh -c 'task format && task test && task lint && task build'`
Expected: 140 tests pass, lint clean, build succeeds (the app's `EventTranslator` switches over `NSEvent.EventType`, not `InputEvent`, and compares decisions with `==`, so the new cases don't break it).

- [ ] **Step 7: Commit**

Stage `Sources/FlickCore/InputEvent.swift Sources/FlickCore/HoldScrollRecognizer.swift Sources/FlickCore/GestureRecognizer.swift Sources/FlickCore/DragScrollRecognizer.swift Sources/FlickCore/InputRouter.swift Tests/FlickCoreTests/HoldScrollRecognizerTests.swift` and hand over:

```sh
gitcs 'feat(core): recognize scrolling while holding the right button on a titlebar'
```

---

### Task 4: Route to the hold recognizer

**Files:**
- Modify: `Sources/FlickCore/InputRouter.swift` (whole file)
- Modify: `Sources/Flick/MenuBarApp.swift` (`applicationDidFinishLaunching`, router construction)
- Test: `Tests/FlickCoreTests/InputRouterTests.swift`

**Interfaces:**
- Consumes: `HoldScrollRecognizer` (Task 3: `isPaused`, `isTracking`, `handle`, `reset`).
- Produces: `InputRouter.init(gestures: GestureRecognizer, dragScroll: DragScrollRecognizer, holdScroll: HoldScrollRecognizer)`.

- [ ] **Step 1: Write the failing tests**

In `Tests/FlickCoreTests/InputRouterTests.swift`, replace `makeRouter(onUpdate:)` with:

```swift
    /// Both buttons on, so either scroll recognizer claims.
    static let both: FlickSettings = {
        var settings = FlickSettings()
        settings.scrollButton = .both
        return settings
    }()

    func makeRouter(onUpdate: @escaping (GestureUpdate) -> Void) -> InputRouter {
        windows.frames[window] = GlobalRect(x: 350, y: 250, width: 640, height: 480)
        let probe = FakeProbe(window: window)
        return InputRouter(
            gestures: GestureRecognizer(probe: probe, onUpdate: onUpdate),
            dragScroll: DragScrollRecognizer(
                probe: probe, windows: windows, settings: { Self.both }, onUpdate: onUpdate),
            holdScroll: HoldScrollRecognizer(probe: probe, settings: { Self.both }, onUpdate: onUpdate))
    }

    var holdContext: GestureContext { GestureContext(window: window, pointer: press) }

    func held(_ lines: Double) -> InputEvent {
        .holdScroll(deltaY: lines, precise: false, invertedFromDevice: false, location: press)
    }
```

Replace `pausingPausesBoth()` with:

```swift
    @Test func pausingPausesAllThree() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        router.isPaused = true
        let events: [InputEvent] = [
            .mouseDown(location: press), wheel(1), .mouseUp(location: pointer), swipe(.began, -60), swipe(.ended),
            .rightMouseDown(location: press), held(1), .rightMouseUp(location: press),
        ]
        #expect(events.map { router.handle($0) } == Array(repeating: .passThrough, count: 8))
        #expect(updates.isEmpty)
    }
```

Add at the end of the suite:

```swift
    @Test func rightButtonEventsAndHoldScrollsGoToTheHoldRecognizer() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.rightMouseDown(location: press), held(1), .rightMouseUp(location: press)]
        #expect(events.map { router.handle($0) } == [.swallow, .swallow, .swallow])
        #expect(updates == [.preview(holdContext, .slot(.fill)), .commit(holdContext, .slot(.fill))])
    }

    @Test func aTrackpadScrollThatBeginsCancelsATrackedHold() {
        // A trackpad scroll arrives without the button held: the release was lost.
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.rightMouseDown(location: press), held(1), swipe(.began, -60)]
        _ = events.map { router.handle($0) }
        #expect(updates == [.preview(holdContext, .slot(.fill)), .cancel, .preview(swipeContext, .slot(.leftHalf))])
    }

    @Test func resetCancelsATrackedHold() {
        var updates: [GestureUpdate] = []
        let router = makeRouter { updates.append($0) }
        let events: [InputEvent] = [.rightMouseDown(location: press), held(1)]
        _ = events.map { router.handle($0) }
        router.reset()
        #expect(updates == [.preview(holdContext, .slot(.fill)), .cancel])
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `nix develop -c swift test --filter InputRouterTests`
Expected: build FAILS with "extra argument 'holdScroll' in call".

- [ ] **Step 3: Route the events**

Replace `Sources/FlickCore/InputRouter.swift` with:

```swift
/// The event tap's single entry point: hands each event to the recognizer it belongs to.
@MainActor
public final class InputRouter {
    private let gestures: GestureRecognizer
    private let dragScroll: DragScrollRecognizer
    private let holdScroll: HoldScrollRecognizer

    public init(gestures: GestureRecognizer, dragScroll: DragScrollRecognizer, holdScroll: HoldScrollRecognizer) {
        self.gestures = gestures
        self.dragScroll = dragScroll
        self.holdScroll = holdScroll
    }

    /// Pauses or resumes all three recognizers.
    public var isPaused: Bool {
        get { gestures.isPaused }
        set {
            gestures.isPaused = newValue
            dragScroll.isPaused = newValue
            holdScroll.isPaused = newValue
        }
    }

    public func handle(_ event: InputEvent) -> EventDecision {
        switch event {
        case .mouseDown, .mouseDragged, .mouseUp, .dragScroll:
            return dragScroll.handle(event)
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp, .holdScroll:
            return holdScroll.handle(event)
        case .scroll(phase: .began, _, _, _, _):
            // A new trackpad gesture without a button held: a drag or hold we track ended unseen.
            // Other phases may be a scroll that was in flight when the button went up; its release
            // follows.
            if dragScroll.isTracking {
                dragScroll.reset()
            }
            if holdScroll.isTracking {
                holdScroll.reset()
            }
            return gestures.handle(event)
        case .scroll, .momentum, .magnify:
            return gestures.handle(event)
        }
    }

    /// Abandons whatever is in progress, e.g. after the event tap was disabled.
    public func reset() {
        gestures.reset()
        dragScroll.reset()
        holdScroll.reset()
    }
}
```

In `Sources/Flick/MenuBarApp.swift`, replace:

```swift
            dragScroll: DragScrollRecognizer(
                probe: probe, windows: WindowMover(), settings: { store.settings }, onUpdate: onUpdate))
```

with:

```swift
            dragScroll: DragScrollRecognizer(
                probe: probe, windows: WindowMover(), settings: { store.settings }, onUpdate: onUpdate),
            holdScroll: HoldScrollRecognizer(probe: probe, settings: { store.settings }, onUpdate: onUpdate))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `nix develop -c swift test --filter InputRouterTests`
Expected: 10 tests pass.

- [ ] **Step 5: Full suite, lint, build**

Run: `nix develop -c sh -c 'task format && task test && task lint && task build'`
Expected: 143 tests pass, lint clean, build succeeds. (The app now builds the hold recognizer, but no right-button events reach it until Task 5.)

- [ ] **Step 6: Commit**

Stage `Sources/FlickCore/InputRouter.swift Sources/Flick/MenuBarApp.swift Tests/FlickCoreTests/InputRouterTests.swift` and hand over:

```sh
gitcs 'feat(core): route right-button events to the hold recognizer'
```

---

### Task 5: Right-mouse tap, replay, wiring and docs

App adapters; verified by build, lint and the manual checklist.

**Files:**
- Modify: `Sources/Flick/EventTap.swift` (whole file)
- Modify: `Sources/Flick/MenuBarApp.swift` (import, subscription)
- Modify: `README.md`

**Interfaces:**
- Consumes: `InputEvent` right-button cases and `.holdScroll`, `EventDecision.replayPress` (Task 3); `InputRouter` (Task 4); `ScrollButton.includesRight` (Task 1); `SettingsStore.$settings`.
- Produces: `EventTap.isRightButtonEnabled: Bool`.

- [ ] **Step 1: Event tap**

Replace `Sources/Flick/EventTap.swift` with:

```swift
import AppKit
import FlickCore
import os

/// Marks the right-clicks Flick replays itself, so none of its taps claims them again.
private let replayMarker: Int64 = 0x464C_4B52  // "FLKR"

/// The right press Flick swallowed last, kept until its release decides whether to replay it.
/// Only touched by tap callbacks, which all run on the main run loop.
nonisolated(unsafe) private var heldPress: CGEvent?

/// Session event taps:
/// - an active one for scroll and trackpad gesture events;
/// - a listen-only one for left-mouse events (drag + scroll), so left clicks never wait for Flick;
/// - an active one for right-mouse events (hold + scroll), which swallows titlebar presses and is
///   enabled only while the setting includes the right button.
/// Hands every event to the router and acts on its decision.
@MainActor
final class EventTap {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "EventTap")
    /// CGEventType raw values for gesture events, which have no named case in the SDK.
    private static let gestureTypes: [UInt32] = [29, 30]
    private static let mouseTypes: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
    private static let rightMouseTypes: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp]

    private let router: InputRouter
    private var port: CFMachPort?
    private var mousePort: CFMachPort?
    private var rightPort: CFMachPort?
    private var sources: [CFRunLoopSource] = []

    /// Whether right-mouse events reach Flick at all. Off: right-clicks never wait for it.
    var isRightButtonEnabled = false {
        didSet { enableTaps() }
    }

    init(router: InputRouter) {
        self.router = router
    }

    var isRunning: Bool { port != nil }

    /// Returns `false` if the taps could not be created (usually: no Accessibility access).
    func start() -> Bool {
        guard port == nil else { return true }
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureTypes {
            mask |= CGEventMask(1) << type
        }
        let port = makeTap(mask, options: .defaultTap)
        let mousePort = makeTap(Self.mask(Self.mouseTypes), options: .listenOnly)
        let rightPort = makeTap(Self.mask(Self.rightMouseTypes), options: .defaultTap)
        guard let port, let mousePort, let rightPort else {
            Self.logger.error("CGEvent.tapCreate failed")
            // Don't leave a tap enabled without a run loop to serve it.
            for created in [port, mousePort, rightPort].compactMap({ $0 }) {
                CFMachPortInvalidate(created)
            }
            return false
        }
        for created in [port, mousePort, rightPort] {
            let source = CFMachPortCreateRunLoopSource(nil, created, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            if let source { sources.append(source) }
        }
        self.port = port
        self.mousePort = mousePort
        self.rightPort = rightPort
        enableTaps()
        return true
    }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
    }

    private func makeTap(_ mask: CGEventMask, options: CGEventTapOptions) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
            eventsOfInterest: mask, callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
    }

    /// Enables the scroll and left-mouse taps, and the right-mouse tap only while it is wanted.
    /// Disabling a tap ourselves can come back as `tapDisabledByUserInput`; this keeps it off.
    private func enableTaps() {
        for tap in [port, mousePort].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        if let rightPort {
            CGEvent.tapEnable(tap: rightPort, enable: isRightButtonEnabled)
        }
    }

    fileprivate func handle(type: CGEventType, input: InputEvent?) -> EventDecision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.warning("Event tap disabled (type \(type.rawValue)), re-enabling")
            enableTaps()
            // Events were lost while disabled; don't wait for an `ended` that may never come.
            router.reset()
            return .passThrough
        }
        guard let input else { return .passThrough }
        return router.handle(input)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let pass = Unmanaged.passUnretained(event)
    // Clicks Flick replays itself pass untouched.
    guard let userInfo, event.getIntegerValueField(.eventSourceUserData) != replayMarker else { return pass }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    // Translate before hopping onto the main actor: CGEvent is not Sendable, InputEvent is.
    let input = EventTranslator.input(from: event)
    // The taps' run-loop sources are on the main run loop, so this runs on the main thread.
    let decision = MainActor.assumeIsolated { tap.handle(type: type, input: input) }
    switch decision {
    case .passThrough:
        return pass
    case .swallow:
        if type == .rightMouseDown {
            heldPress = event.copy()
        }
        return nil
    case .replayPress:
        replay(press: heldPress, release: event)
        heldPress = nil
        return nil
    }
}

/// Posts the swallowed right press and its release again, in that order, marked so Flick's taps
/// let them through: the app gets its right-click after all, on release.
private func replay(press: CGEvent?, release: CGEvent) {
    guard let press, let release = release.copy() else {
        Logger(subsystem: "local.personal.flick", category: "EventTap").error("No right press to replay")
        return
    }
    for event in [press, release] {
        event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
        event.post(tap: .cgSessionEventTap)
    }
}

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
        case .rightMouseDown:
            return .rightMouseDown(location: location)
        case .rightMouseDragged:
            return .rightMouseDragged(location: location)
        case .rightMouseUp:
            return .rightMouseUp(location: location)
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
        // A held button makes a scroll a candidate for drag + scroll (left) or hold + scroll
        // (right), mouse wheel and trackpad alike. Asking the event source (not our own press
        // tracking) means a lost release can't fool it.
        if momentum == nil, CGEventSource.buttonState(.combinedSessionState, button: .left) {
            return .dragScroll(
                deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
        }
        if momentum == nil, CGEventSource.buttonState(.combinedSessionState, button: .right) {
            return .holdScroll(
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

    private static func phase(_ phase: NSEvent.Phase) -> GesturePhase? {
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) { return .changed }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.mayBegin) { return .mayBegin }
        return nil
    }
}
```

- [ ] **Step 2: Switch the right-mouse tap with the setting**

In `Sources/Flick/MenuBarApp.swift`, add `import Combine` after `import AppKit`; add below `private lazy var settingsWindow = SettingsWindow(store: store)`:

```swift
    private var subscriptions: Set<AnyCancellable> = []
```

and replace:

```swift
        tap = EventTap(router: router)
```

with:

```swift
        tap = EventTap(router: router)
        // Right-clicks only pass through Flick while the setting uses the right button.
        store.$settings
            .map(\.scrollButton.includesRight)
            .removeDuplicates()
            .sink { [weak self] enabled in self?.tap?.isRightButtonEnabled = enabled }
            .store(in: &subscriptions)
```

- [ ] **Step 3: README**

In `README.md`, replace:

```markdown
The preview follows the pointer; the window changes when you release the button. Scroll back to
cancel.

*Settings…* (⌘,) in the menu-bar item turns each gesture and the live preview on or off and
starts Flick at login.
```

with:

```markdown
The preview follows the pointer; the window changes when you release the button. Scroll back to
cancel.

With *Right button* (or *Both*) chosen under *Scroll to fill and restore* in Settings, hold the
right button on a titlebar instead and scroll: the window stays where it is and fills or restores
when you let go. A right-click without scrolling still opens the app's menu, on release.

*Settings…* (⌘,) in the menu-bar item turns each gesture and the live preview on or off, chooses
the button for scroll to fill and restore, and starts Flick at login.
```

Replace the checklist item:

```markdown
- [ ] With *Scroll while dragging* off in Settings, scrolling during a drag reaches the app.
```

with:

```markdown
- [ ] With *Scroll to fill and restore* set to *Off* or *Right button*, scrolling during a left drag reaches the app.
- [ ] After updating from a build with the *Scroll while dragging* switch: the picker shows *Left button* if the switch was on, *Off* if it was off; the choice survives a relaunch.
- [ ] *Right button*: hold right on a Finder, Safari, Terminal and VS Code titlebar and scroll away: fill preview; release: the window fills and stays filled. Towards you on a window Flick snapped: restores to its frame from before the first snap.
- [ ] *Right button*: a plain right-click on a titlebar or toolbar (Finder *Customize Toolbar…*, a Safari tab, VS Code's title bar) opens the menu once, on release; choosing an item works.
- [ ] *Right button*: hold, scroll away and back, release: no menu, nothing moves.
- [ ] Right-clicks in window contents, on the desktop and in the Dock behave as usual with every picker value.
- [ ] *Left button* and *Off*: holding right and scrolling on a titlebar opens the menu on press as usual and scrolls nothing special.
- [ ] Fullscreen window: right-click and right-hold + scroll near the top edge behave as usual.
- [ ] Trackpad: two-finger-click and hold on a titlebar, scroll with two other fingers: same as with the mouse.
```

- [ ] **Step 4: Format, build, test, lint**

Run: `nix develop -c sh -c 'task format && task build && task test && task lint'`
Expected: build succeeds, 143 tests pass, lint clean. If Swift 6 rejects the `.sink` closure's access to `self?.tap` as not main-actor isolated, wrap its body in `MainActor.assumeIsolated { … }` (`@Published` emits on the mutating thread, the main thread) and ledger the ruling.

- [ ] **Step 5: Manual check (user)**

Run: `nix develop -c task run` (re-grant Accessibility if asked). Ask the user to work through the new checklist items with the picker on *Right button*, *Both*, *Left button* and *Off*, plus the left drag + scroll items as a regression check, and to compare the settings window against `docs/design/settings-window.png`.
Expected: all items pass. A failing item is fixed in this task before the commit.

- [ ] **Step 6: Commit**

Stage `Sources/Flick/EventTap.swift Sources/Flick/MenuBarApp.swift README.md` and hand over:

```sh
gitcs 'feat(app): fill and restore by holding the right button and scrolling'
```

- [ ] **Step 7: Final review, then PR C**

Run the final whole-branch review (fresh reviewer on the most capable model, this plan's Review Focus verbatim). Then ask the user whether to push `feature/no-ref/right-button-scroll` and open PR C against `main`.
