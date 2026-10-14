# Flick right-button scroll — design

- **Date:** 2026-10-14
- **Status:** draft, awaiting review
- **Builds on:** [Flick settings window and drag + scroll](2026-10-14-flick-settings-and-drag-scroll-design.md)
- **Design drawing:** [Flick design canvas](https://claude.ai/artifact/8NszVx1Eqce2uHPLTWRneV)
  (board *Settings window*, updated for the picker)

## Design drivers

| Settings window |
|---|
| ![Settings window](../../design/settings-window.png) |

The editable source is the design canvas linked above; the PNG in `docs/design/` is a render of
it. If code and drawing disagree, the drawing wins until it is updated.

## Goal

A mouse user asked to use the right button instead of the left for drag + scroll: holding the
left button and rolling the wheel at the same time is awkward, often with the same finger.
Holding the right button frees the index finger for the wheel.

The right button can't drag a window on macOS, so the right-button gesture is **hold on the
titlebar, scroll, release**: the window stays where it is until the release applies fill or
restore. Which button(s) the gesture uses becomes a setting.

## Feasibility (spike, 2026-10-14)

A throwaway event-tap probe swallowed right presses on titlebars, filled or restored on release
after a scroll, and replayed the click when no scroll followed. On hardware:

- Fill and restore worked in Finder, Safari, VS Code and cmux; every frame read back unchanged
  0.5 s later.
- Plain right-clicks on titlebars and toolbars (Finder, Safari incl. the tab menu, VS Code,
  cmux) still opened their menu, on release instead of on press.
- No tap timeouts, no stuck clicks. All scrolls came from a mouse wheel; the trackpad was not
  tried.

## Delivery

One PR (PR C) on `feature/no-ref/right-button-scroll`, branched from `main` after PR #4.

## Scope

### In this iteration

- A picker replacing the *Scroll while dragging* switch: **Off / Left button / Right button /
  Both**, default *Left button*.
- The right-button gesture described under *Behaviour*.
- Carrying over the existing `scrollWhileDragging` value.

### Not in this iteration

- Middle or extra mouse buttons, modifier keys.
- A right-button gesture anywhere but the titlebar zone.
- Snapping to halves or quarters with the mouse.

## Behaviour

### Settings

- `FlickSettings.scrollWhileDragging: Bool` becomes `scrollButton: ScrollButton` with cases
  `off`, `left`, `right`, `both`, stored as a string under the new key `scrollButton`.
- If `scrollButton` was never written but the old `scrollWhileDragging` key exists, it is
  carried over: `true` → `left`, `false` → `off`. Once `scrollButton` exists it wins; the old
  key is no longer read or written.
- The settings window shows the picker **Scroll to fill and restore** in the *Gestures* section
  in place of the switch. The hint under it follows the choice:

  | Choice | Hint |
  |---|---|
  | Off | Scrolling while a button is held always reaches the app. |
  | Left button | Drag a window by its titlebar, scroll away to fill, towards you to restore. |
  | Right button | Hold the right button on a titlebar, scroll away to fill, towards you to restore. Right-click menus on titlebars open on release. |
  | Both | Either button works. |
- Settings are read once per gesture, at its start, as before.

### Right-button gesture

1. **Press.** A right press on a window's titlebar zone (top 40 pt of a standard window,
   fullscreen windows excluded — the same zone as every other gesture) is swallowed, but only
   when the picker includes *Right* and Flick isn't paused. Right presses anywhere else are never
   touched.
2. **Hold.** While the button is held, scrolling away from you previews fill and towards you
   previews restore. Thresholds and direction handling are those of drag + scroll: 1 line for a
   mouse wheel, 20 pt for a trackpad, physical direction whatever the scrolling setting.
   Scrolling back to neutral removes the preview. Moving the pointer doesn't move the window; the
   fill preview follows the screen under the pointer.
3. **Release.**
   - With a target: the target is applied.
   - Scrolled, but back to neutral: nothing happens.
   - Never scrolled: the original right-click is replayed, so the app shows its menu.
4. **Fill and restore** share the history of the other gestures. Fill uses the screen under the
   pointer at release; restore returns the window to its frame from before the first snap, at
   its old position (it never moved, so nothing goes under the pointer).

### Accepted limitations

- On titlebars, a right-click menu opens on release instead of on press.
- Press-drag-release menu selection on titlebars (press, drag to an item, release on it) no
  longer works there. Click, then choose, still works.
- With *Right button* or *Both*, every right press waits for one Accessibility titlebar check
  (bounded by Flick's 0.25 s Accessibility timeout) before it continues.
- This gives up v1's rule that Flick never swallows mouse events, for right presses on titlebars
  only and only while the picker includes *Right*.
- Mouse only. A trackpad's two-finger click is not seen as a held right button by the hardware
  state Flick reads (manual check, 2026-10-15), so two-finger-click-and-hold plus scroll on a
  titlebar does nothing: no fill and no menu. A plain two-finger click is replayed as usual.

## Architecture

### `FlickCore`

- **`ScrollButton`**: `off`, `left`, `right`, `both`, with `includesLeft` / `includesRight`.
  `FlickSettings.scrollButton` replaces `scrollWhileDragging`, with the migration above in
  `init(defaults:)`.
- **`InputEvent`** gains `.rightMouseDown(location:)`, `.rightMouseDragged(location:)`,
  `.rightMouseUp(location:)` and `.holdScroll(deltaY:precise:invertedFromDevice:location:)`
  (a scroll while the right button and not the left is held, momentum excluded).
- **`EventDecision.replayPress`**: on a release — swallow it, then post the swallowed press and
  this release, in that order.
- **Shared scroll target**: the amount → fill / restore / none logic (thresholds and direction)
  moves out of `DragScrollRecognizer` into a small shared helper used by both recognizers.
- **`HoldScrollRecognizer`** (`init(probe:settings:onUpdate:)`, `isPaused`, `isTracking`,
  `handle(_:)`, `reset()`):

  | Event | idle | ignored (not a titlebar) | holding |
  |---|---|---|---|
  | right press | titlebar + *Right* + not paused → holding, `.swallow`; else → ignored, pass | re-check as from idle (release was lost) | cancel the hold, re-check as from idle |
  | right drag | pass | pass | `.swallow`; preview follows the pointer |
  | hold scroll | pass | pass | `.swallow`; add to the amount, preview when the target changes |
  | right release | pass | → idle, pass | target: commit, `.swallow`; scrolled, no target: cancel, `.swallow`; never scrolled: `.replayPress` |

  The titlebar is probed once, at the press; settings are read once, at the press. `reset()`
  cancels a hold; its press is dropped, not replayed. The context has no `drag`, so
  `FlickController` handles it unchanged.
- **`DragScrollRecognizer`** claims only when `scrollButton.includesLeft`.
- **`InputRouter`** takes the hold recognizer too: right-button events and `.holdScroll` go to
  it; a trackpad `.scroll(.began)` while it tracks a hold cancels the hold (lost release), as for
  drags; `isPaused` and `reset()` cover all three recognizers.

### `Flick`

- **Right-button tap**: a third session tap, active (it swallows), for right press, drag and
  release. It is enabled only while the picker includes *Right*; `SettingsStore` switches it when
  the picker changes. With *Off* or *Left* no right-click ever passes through Flick.
- **`EventTranslator`**: right-button events map to the new cases. A scroll maps to
  `.dragScroll` when the left button is held, else to `.holdScroll` when the right button is
  held, else as before. Both arrive through the existing scroll tap.
- **Replay**: when the router swallows a right press, the tap keeps a copy of it. On
  `.replayPress` the tap swallows the release and posts copies of the press and the release with
  a marker in `eventSourceUserData`. Every tap passes marked events through untouched, without
  routing them.
- **Settings window**: the picker replaces the switch.

## Error handling

| Situation | Result |
|---|---|
| A tap is disabled by the system | `router.reset()`: the hold is cancelled, its press dropped; the later release passes through |
| Release lost | The next right press, or a trackpad `.scroll(.began)`, cancels the hold |
| Titlebar check fails or times out | Not claimed: the press reaches the app as usual |
| No restore history, no screen under the pointer | The release is swallowed and nothing happens, like the trackpad gestures |
| Posting the replayed click fails | Logged; the click is lost once |

## Testing

- **`FlickSettingsTests`**: default `left`; old key `true` → `left`, `false` → `off`; the new key
  wins over the old one; a saved value reads back.
- **`HoldScrollRecognizerTests`** (new file): one test per table cell above, plus pause, *Off* and
  *Left* claiming nothing, settings read once per hold, fullscreen excluded via the probe, and the
  preview following the pointer.
- **`InputRouterTests`**: right-button events and `.holdScroll` reach the hold recognizer;
  `.scroll(.began)` cancels a hold; pause covers all three.
- **`DragScrollRecognizerTests`**: the existing "off" test uses `.off` and `.right`.
- **Manual checklist** (README): fill, restore and a plain right-click on titlebars in Finder,
  Safari (incl. the tab menu), Terminal and VS Code; right-clicks elsewhere unchanged; each picker
  value; the old setting carried over after a relaunch; fullscreen windows ignored; a slow
  right-click; a plain trackpad two-finger click.
