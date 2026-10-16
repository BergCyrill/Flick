# Contributing to Flick

## Setup

You need macOS 14 or later, Xcode (for Swift 6, `swift format` and `sourcekit-lsp`), Nix with
flakes enabled, and [direnv](https://direnv.net/).

```sh
direnv allow          # or: nix develop
pre-commit install    # once per clone
task run              # build, bundle to build/Flick.app and (re)launch it
```

| Task | What it does |
|---|---|
| `task test` | unit tests |
| `task lint` | swiftlint, swift format (strict), shellcheck, actionlint |
| `task format` | rewrites the Swift sources with swift format |
| `task bundle` | builds and signs `build/Flick.app` |
| `task icon` | renders `support/AppIcon.svg` into `support/AppIcon.icns` |
| `task release DRY=1` | the whole release locally, without publishing |

On first launch, grant Flick Accessibility access in **System Settings → Privacy & Security →
Accessibility**. Builds are signed with the *Flick Code Signing* certificate when your keychain
has it, so the permission survives rebuilds. Without it, `task bundle` signs ad-hoc and says so:
then remove Flick from that list after each rebuild, run `task run` again and re-enable it.

## Project layout

```text
Sources/FlickCore/       pure logic: geometry, layout, gesture recognition, settings (unit-tested)
Sources/Flick/           macOS side: event tap, Accessibility, overlay, menu bar, settings, updates
Tests/FlickCoreTests/    swift-testing suites for FlickCore
support/                 Info.plist, app icon, release-notes template
scripts/                 signing, appcast and release scripts
docs/readme/             README pictures; `python3 docs/readme/demo.py` regenerates the animation
docs/design/             design boards
docs/superpowers/        specs and implementation plans
```

## Pull requests

Every merge to `main` with a `feat`, `fix` or breaking commit publishes a release (see
[docs/releasing.md](docs/releasing.md)), so commit messages follow
[Conventional Commits](https://www.conventionalcommits.org/): `fix` → patch, `feat` → minor;
`docs`, `chore`, `ci`, `build`, `test`, `refactor` and `style` release nothing. With squash
merges the PR title becomes the commit, so it has to follow the same rules.

Pull requests run `task test`, `task lint` and `task build`; branches of this repository also
run `task release DRY=1` with the signing certificate and the update key.

## Manual test checklist

Run the parts you touched with `task run`, on the built-in trackpad, a Magic Trackpad and a
mouse where available.

**Trackpad**

- [ ] Finder, Safari, Terminal, VS Code: each of the 8 swipe directions snaps to the right slot, edge to edge.
- [ ] With *Tiled windows have margins* on (System Settings → Desktop & Dock), the next snap leaves 8 pt gaps, without relaunching Flick; off again, edge to edge.
- [ ] The preview appears after a short swipe, follows direction changes, and disappears on lift.
- [ ] Swiping back to the start before lifting leaves the window where it was.
- [ ] Pinch out fills; pinch in afterwards restores the previous frame; a second pinch in does nothing.
- [ ] Snap ←, then →, then pinch out, then pinch in: the window returns to its size and position from before the first snap.
- [ ] Scrolling inside a window, a Safari tab strip below the titlebar zone, and the desktop behaves normally.
- [ ] Pinch-to-zoom inside Safari and Preview still zooms.
- [ ] In a fullscreen app (e.g. Safari or Terminal), scrolling and pinch-zooming near the top edge behave normally and Flick shows no preview.
- [ ] With natural scrolling switched off (System Settings → Trackpad), ↖ still snaps top-left.
- [ ] Second display (if available): snapping uses the display under the pointer.

**Mouse: drag and scroll**

- [ ] Drag a Finder, Safari, Terminal and VS Code window by its titlebar and scroll away: fill preview; release: the window fills and stays filled.
- [ ] Scroll towards you while dragging a window Flick snapped: original-size preview under the pointer that follows it; release: original size where you let go, fully on screen.
- [ ] Scroll away and back before releasing: no preview, the window stays where you dropped it.
- [ ] Natural scrolling off: same directions as with it on.
- [ ] Trackpad: click-hold a titlebar and scroll with two other fingers: same behaviour.
- [ ] Holding the button in a text area and scrolling (extending a selection) scrolls the app as usual.
- [ ] Second display: drag a window onto it and scroll away: it fills that display.
- [ ] With *Scroll to fill and restore* set to *Off* or *Right button*, scrolling during a left drag reaches the app.

**Mouse: right button held**

- [ ] *Right button*: hold right on a Finder, Safari, Terminal and VS Code titlebar and scroll away: fill preview; release: the window fills and stays filled. Towards you on a window Flick snapped: restores to its frame from before the first snap.
- [ ] *Right button*: a plain right-click on a titlebar or toolbar (Finder *Customize Toolbar…*, a Safari tab, VS Code's title bar) opens the menu once, on release, also after holding the button for a second; choosing an item works.
- [ ] *Right button*: hold, scroll away and back, release: no menu, nothing moves.
- [ ] Right-clicks in window contents, on the desktop and in the Dock behave as usual with every picker value.
- [ ] *Left button* and *Off*: holding right and scrolling on a titlebar opens the menu on press as usual and scrolls nothing special.
- [ ] Fullscreen window: right-click and right-hold + scroll near the top edge behave as usual.
- [ ] Trackpad, *Right button*: a plain two-finger click on a titlebar opens the menu as usual.

**Menu bar and settings**

- [ ] *Pause gestures* stops all snapping; unpausing brings it back.
- [ ] Remove Flick from Accessibility while running: the menu shows "Waiting for Accessibility access" after a relaunch.
- [ ] Settings: with *Swipe on titlebar to snap* off, a titlebar swipe scrolls the app (e.g. Safari's tab strip) and pinch still works; the same the other way round for *Pinch on titlebar*.
- [ ] Settings: with *Show live preview* off, no overlay appears and windows still move on lift.
- [ ] Settings survive a relaunch (`task run`).
- [ ] Rebuild after a code change (`task run`): Accessibility stays granted, no prompt.
- [ ] The menu's first line shows *Flick &lt;version&gt;*; the settings window's footer shows *Version &lt;version&gt; (&lt;build&gt;)* without scrolling.
- [ ] *Pause gestures* while the settings window is open shows the paused note; unpausing hides it.
- [ ] *Launch at login* on: Flick appears in System Settings → General → Login Items and starts after logging out and in; off removes it. If macOS wants approval, the hint says so and *Open Login Items…* opens the pane.

**Updates and releases**

- [ ] *Check for updates automatically* off: `defaults read io.github.bergcyrill.flick SUEnableAutomaticChecks` prints 0; on again prints 1.
- [ ] *Check every* offers 1, 4, 8 and 24 hours (24 by default) and is greyed out while automatic checks are off; choosing 4 hours makes `defaults read io.github.bergcyrill.flick SUScheduledCheckInterval` print 14400.
- [ ] Update waiting (serve a newer build's DMG and appcast on localhost and point `SUFeedURL` at it): a blue dot right of the glyph in light and dark menu bars, one notification that opens Sparkle's dialog. *Remind Me Later* keeps the dot and *Update to …*; quitting and relaunching brings the dot back within seconds without a new notification; *Skip This Version* or installing removes it.
- [ ] *Check for Updates…* when up to date says so.
- [ ] Updating from the previous release: no *Open Anyway*, Accessibility still granted.
- [ ] Release DMG: opening it shows *Flick* and an *Applications* link; after dragging and *Open Anyway*, the menu shows the release's version.
