# Flick

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
docs/superpowers/        spec and implementation plan
```
