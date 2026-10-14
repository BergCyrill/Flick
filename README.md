<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/flick-logo-dark.svg">
    <img alt="Flick" src="docs/logo/flick-logo-light.svg" height="64">
  </picture>
</h1>

Two-finger trackpad gestures on a window's titlebar that snap macOS windows: swipe for halves
and quarters, pinch out to fill, pinch in to restore. A free, minimal take on
[Swish](https://highlyopinionated.co/swish/).

![Gesture map](docs/design/gesture-map.png)

## Getting started

Prerequisites: macOS 14 or later, Xcode (provides Swift 6, `swift format` and `sourcekit-lsp`),
Nix with flakes enabled, and [direnv](https://direnv.net/).

```sh
direnv allow          # or: nix develop
pre-commit install    # once per clone
task test             # unit tests
task lint             # swiftlint + swift format, strict
task format           # rewrite sources with swift format
task run              # build, bundle to build/Flick.app, (re)launch
```

On first launch Flick asks for Accessibility access. Enable it under **System Settings →
Privacy & Security → Accessibility**; Flick picks it up within a few seconds. The bundle is
ad-hoc signed, so after a rebuild macOS may stop trusting it: remove Flick from that list,
run `task run` again and re-enable it.

## Project layout

```text
Sources/FlickCore/       pure logic: geometry, layout, gesture recognition (unit-tested)
Sources/Flick/           macOS adapters: event tap, Accessibility, overlay, menu-bar app
Tests/FlickCoreTests/    swift-testing suites for FlickCore
support/Info.plist       app bundle metadata used by `task bundle`
docs/design/             design drivers (gesture map, live preview)
docs/logo/               logo lockups (light/dark), mark, social preview
docs/superpowers/        spec and implementation plan
```

## Usage

Put the pointer on a window's titlebar (the top 40 pt, toolbars included), then:

| Gesture (two fingers) | Result |
|---|---|
| swipe ← / → | left / right half |
| swipe ↑ / ↓ | top / bottom half |
| swipe ↖ ↗ ↙ ↘ | matching quarter |
| pinch out | fill the screen (8 pt margin) |
| pinch in | restore the frame from before the first snap |

A blue preview shows the target while your fingers move. The window moves when you lift them.
Swipe back to where you started to cancel. Gestures that start anywhere else go to the app as
usual. *Pause gestures* in the menu-bar item turns Flick off without quitting.

With a mouse (or a trackpad, keeping the click held), drag a window by its titlebar and scroll
while still holding the button:

| While dragging | Result |
|---|---|
| scroll away from you | fill the screen under the pointer |
| scroll towards you | restore the size from before the first snap, under the pointer |

The preview follows the pointer; the window changes when you release the button. Scroll back to
cancel.

*Settings…* (⌘,) in the menu-bar item turns each gesture and the live preview on or off and
starts Flick at login. A gesture that is off swallows nothing: its scrolls and pinches reach the
app. Changes apply from the next gesture.

## Manual test checklist

Run after changes to `Sources/Flick/`, with `task run`, on the built-in trackpad and, if
available, a Magic Trackpad:

- [ ] Finder, Safari, Terminal, VS Code: each of the 8 swipe directions snaps to the right slot with 8 pt gaps.
- [ ] The preview appears after a short swipe, follows direction changes, and disappears on lift.
- [ ] Swiping back to the start before lifting leaves the window where it was.
- [ ] Pinch out fills; pinch in afterwards restores the previous frame; a second pinch in does nothing.
- [ ] Snap ←, then →, then pinch out, then pinch in: the window returns to its size and position from before the first snap.
- [ ] Scrolling inside a window, a Safari tab strip below the titlebar zone, and the desktop behaves normally.
- [ ] Pinch-to-zoom inside Safari and Preview still zooms.
- [ ] In a fullscreen app (e.g. Safari or Terminal), scrolling and pinch-zooming near the top edge behave normally and Flick shows no preview.
- [ ] With natural scrolling switched off (System Settings → Trackpad), ↖ still snaps top-left.
- [ ] *Pause gestures* stops all snapping; unpausing brings it back.
- [ ] Remove Flick from Accessibility while running: the menu shows "Waiting for Accessibility access" after a relaunch.
- [ ] Second display (if available): snapping uses the display under the pointer.
- [ ] Settings: with *Swipe on titlebar to snap* off, a titlebar swipe scrolls the app (e.g. Safari's tab strip) and pinch still works; the same the other way round for *Pinch on titlebar*.
- [ ] Settings: with *Show live preview* off, no overlay appears and windows still move on lift.
- [ ] Settings survive a relaunch (`task run`).
- [ ] *Pause gestures* while the settings window is open shows the paused note; unpausing hides it.
- [ ] *Launch at login* on: Flick appears in System Settings → General → Login Items and starts after logging out and in; off removes it. If macOS wants approval, the hint says so and *Open Login Items…* opens the pane.
- [ ] Mouse wheel: drag a Finder, Safari, Terminal and VS Code window by its titlebar and scroll away: fill preview; release: the window fills and stays filled.
- [ ] Scroll towards you while dragging a window Flick snapped: original-size preview under the pointer that follows it; release: original size where you let go, fully on screen.
- [ ] Scroll away and back before releasing: no preview, the window stays where you dropped it.
- [ ] Natural scrolling off: same directions as with it on.
- [ ] Trackpad: click-hold a titlebar and scroll with two other fingers: same behaviour.
- [ ] Holding the button in a text area and scrolling (extending a selection) scrolls the app as usual.
- [ ] Second display: drag a window onto it and scroll away: it fills that display.
- [ ] With *Scroll while dragging* off in Settings, scrolling during a drag reaches the app.
