#!/usr/bin/env python3
"""Writes docs/readme/demo.svg, the README's animation: a drawn desktop where a window is
snapped with a trackpad swipe, filled and restored with pinches, then dragged with a mouse,
filled by scrolling away and restored by scrolling towards you. Plain SVG with SMIL animations, so it stays sharp, small and plays on
GitHub. Run: python3 docs/readme/demo.py"""

from pathlib import Path

T = 18.5  # seconds per loop
FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
BLUE, ORANGE, INK, SUB = "#2F6BFF", "#E8792F", "#15181D", "#5B6270"
EASE = "0.4 0 0.2 1"

# Window frames: original, left half, filled (8 pt gaps inside the area below the menu bar).
O = (300, 150, 420, 300)
L = (8, 36, 468, 556)
F = (8, 36, 944, 556)
DRAGGED = (440, 240, 420, 300)
FILLED_DRAGGED = (48, 106, 944, 556)
# Back to the original size under the pointer, the grabbed spot keeping its place in the titlebar.
RESTORED = (354, 106, 420, 300)


def track(initial, changes):
    """Keyframes for a value that holds, then moves to `v` between `t0` and `t1`."""
    frames = [(0.0, initial)]
    current = initial
    for t0, t1, v in changes:
        if t0 > frames[-1][0]:
            frames.append((t0, current))
        frames.append((t1, v))
        current = v
    if frames[-1][0] < T:
        frames.append((T, current))
    return frames


def fmt(v):
    if isinstance(v, tuple):
        return " ".join(f"{x:g}" for x in v)
    return f"{v:g}"


def animate(attr, frames, transform=False):
    times = ";".join(f"{t / T:.4f}" for t, _ in frames)
    values = ";".join(fmt(v) for _, v in frames)
    splines = ";".join([EASE] * (len(frames) - 1))
    common = (
        f'dur="{T:g}s" repeatCount="indefinite" calcMode="spline" '
        f'keyTimes="{times}" values="{values}" keySplines="{splines}"'
    )
    if transform:
        return f'<animateTransform attributeName="transform" type="translate" {common}/>'
    return f'<animate attributeName="{attr}" {common}/>'


def opacity(windows, initial=0):
    """Fades in and out: `windows` holds (start, end) pairs, each with a 0.3 s fade."""
    changes = []
    for start, end in windows:
        changes += [(start, start + 0.3, 1), (end, end + 0.3, 0)]
    return animate("opacity", track(initial, changes))


def frame_track(index, changes, initial=O):
    """One coordinate (0 x, 1 y, 2 width, 3 height) of a frame that changes over time."""
    return track(initial[index], [(t0, t1, f[index]) for t0, t1, f in changes])


out = []
add = out.append

# Desktop and menu bar.
add('<defs><linearGradient id="desk" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#D3DAE4"/><stop offset="1" stop-color="#B7C2D1"/></linearGradient>'
    '<filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">'
    '<feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#000" flood-opacity="0.18"/></filter>'
    '<clipPath id="screen"><rect width="960" height="600" rx="18"/></clipPath></defs>')
add('<g clip-path="url(#screen)">')
add('<rect width="960" height="600" fill="url(#desk)"/>')
add('<rect width="960" height="28" fill="#FFFFFF" fill-opacity="0.72"/>')
for x, w in [(16, 28), (56, 34), (102, 30), (144, 36)]:
    add(f'<rect x="{x}" y="10" width="{w}" height="8" rx="4" fill="#9AA2AE"/>')
add('<path d="M870 20 L876 14 M874 21 L881 14 M878 12 L882 12 L882 16" fill="none" stroke="#15181D" '
    'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>')
add(f'<text x="944" y="19" font-size="12" font-weight="600" fill="{INK}" text-anchor="end">9:41</text>')

# The window, moved by its group and resized by its rectangles.
moves = [(2.9, 3.3, L), (5.9, 6.3, F), (8.1, 8.5, O), (10.1, 11.0, DRAGGED), (11.9, 12.3, F),
         (13.6, 14.2, FILLED_DRAGGED), (15.3, 15.7, RESTORED), (16.8, 17.8, O)]
xs, ys = frame_track(0, moves), frame_track(1, moves)
ws, hs = frame_track(2, moves), frame_track(3, moves)
add('<g filter="url(#shadow)">')
add(animate(None, [(t, (x, y)) for (t, x), (_, y) in zip(xs, ys)], transform=True))
add(f'<rect width="{O[2]}" height="{O[3]}" rx="10" fill="#FFFFFF">'
    + animate("width", ws) + animate("height", hs) + "</rect>")
add(f'<rect width="120" height="{O[3] - 28}" y="28" fill="#F1F3F6">'
    + animate("height", [(t, h - 28) for t, h in hs]) + "</rect>")
add(f'<rect width="{O[2]}" height="28" rx="10" fill="#ECEEF2">' + animate("width", ws) + "</rect>")
add(f'<rect width="{O[2]}" height="10" y="18" fill="#ECEEF2">' + animate("width", ws) + "</rect>")
for i, color in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
    add(f'<circle cx="{16 + i * 16}" cy="14" r="5" fill="{color}"/>')
add(f'<text x="72" y="18.5" font-size="12" font-weight="600" fill="{SUB}">Notes</text>')
for i, w in enumerate([72, 56, 64]):
    add(f'<rect x="16" y="{48 + i * 20}" width="{w}" height="8" rx="4" fill="#D5DAE1"/>')
for i, w in enumerate([220, 250, 190, 236, 160]):
    add(f'<rect x="140" y="{50 + i * 22}" width="{w}" height="8" rx="4" fill="#E3E7EC"/>')
add("</g>")

# The preview: its frame changes only while it is hidden.
previews = [(0.0, 0.1, L), (3.6, 3.7, F), (6.5, 6.6, O), (9.0, 9.1, F), (12.5, 12.6, RESTORED)]
px, py = frame_track(0, previews, L), frame_track(1, previews, L)
pw, ph = frame_track(2, previews, L), frame_track(3, previews, L)
add(f'<rect rx="10" fill="{BLUE}" fill-opacity="0.22" stroke="{BLUE}" stroke-width="2.5" opacity="0">'
    + animate("x", px) + animate("y", py) + animate("width", pw) + animate("height", ph)
    + opacity([(2.0, 3.0), (5.2, 6.0), (7.4, 8.2), (11.3, 12.0), (14.6, 15.3)]) + "</rect>")


def pill(cx, cy, text, windows):
    w = 12 + len(text) * 8.2
    add(f'<g opacity="0">{opacity(windows)}'
        f'<rect x="{cx - w / 2}" y="{cy - 15}" width="{w}" height="30" rx="15" fill="#FFFFFF"/>'
        f'<text x="{cx}" y="{cy + 5}" font-size="14" font-weight="600" fill="#1D3FA8" '
        f'text-anchor="middle">{text}</text></g>')


pill(242, 314, "Left half", [(2.0, 3.0)])
pill(480, 314, "Fill", [(5.2, 6.0)])
pill(240, 260, "Fill", [(11.3, 12.0)])
pill(510, 300, "Original size", [(7.4, 8.2)])
pill(564, 256, "Original size", [(14.6, 15.3)])

# Trackpad inset with two fingers.
add('<g>')
add(animate("opacity", track(1, [(8.8, 9.1, 0), (17.3, 17.6, 1)])))
add('<rect x="24" y="436" width="184" height="140" rx="14" fill="#FFFFFF" fill-opacity="0.94"/>')
add(f'<text x="40" y="460" font-size="11" font-weight="700" fill="{SUB}" letter-spacing="1.2">TRACKPAD</text>')
add('<rect x="40" y="470" width="152" height="92" rx="10" fill="#E3E7EC"/>')
fingers = [
    # (cx changes, cy changes, start cx, start cy) per finger
    ([(1.8, 2.8, 70), (4.6, 4.7, 108), (5.0, 5.8, 88), (7.2, 8.0, 108), (8.4, 8.5, 106)],
     [(4.6, 4.7, 518), (8.4, 8.5, 516)], 106, 516),
    ([(1.8, 2.8, 90), (4.6, 4.7, 124), (5.0, 5.8, 144), (7.2, 8.0, 124), (8.4, 8.5, 126)],
     [(4.6, 4.7, 514), (5.0, 5.8, 506), (7.2, 8.0, 514), (8.4, 8.5, 511)], 126, 511),
]
for cx_changes, cy_changes, cx0, cy0 in fingers:
    add(f'<circle r="9" fill="{INK}" opacity="0" cx="{cx0}" cy="{cy0}">'
        + animate("cx", track(cx0, cx_changes)) + animate("cy", track(cy0, cy_changes))
        + opacity([(1.5, 2.8), (4.8, 5.8), (6.9, 8.0)]) + "</circle>")
add("</g>")

# Mouse inset.
add(f'<g opacity="0">{opacity([(9.1, 16.8)])}')
add('<rect x="24" y="436" width="184" height="140" rx="14" fill="#FFFFFF" fill-opacity="0.94"/>')
add(f'<text x="40" y="460" font-size="11" font-weight="700" fill="{SUB}" letter-spacing="1.2">MOUSE</text>')
add(f'<rect x="96" y="474" width="40" height="64" rx="20" fill="none" stroke="{INK}" stroke-width="2.5"/>')
add(f'<path d="M116 474 V502 H136 V494 A20 20 0 0 0 116 474 Z" fill="{INK}" opacity="0">'
    + opacity([(10.0, 11.9), (13.5, 15.3)]) + "</path>")
add(f'<rect x="113" y="484" width="6" height="12" rx="3" fill="{BLUE}"/>')
add(f'<g opacity="0">{opacity([(11.0, 11.8)])}'
    f'<path d="M160 520 V486 M152 494 L160 486 L168 494" fill="none" stroke="{BLUE}" stroke-width="3" '
    f'stroke-linecap="round" stroke-linejoin="round"/>'
    f'<text x="160" y="556" font-size="11" font-weight="600" fill="{BLUE}" text-anchor="middle">scroll</text></g>')
add(f'<g opacity="0">{opacity([(14.3, 15.1)])}'
    f'<path d="M160 486 V520 M152 512 L160 520 L168 512" fill="none" stroke="{BLUE}" stroke-width="3" '
    f'stroke-linecap="round" stroke-linejoin="round"/>'
    f'<text x="160" y="556" font-size="11" font-weight="600" fill="{BLUE}" text-anchor="middle">scroll</text></g>')
add(f'<text x="116" y="560" font-size="11" fill="{SUB}" text-anchor="middle" opacity="0">'
    + opacity([(10.0, 11.9), (13.5, 15.3)]) + "held</text>")
add("</g>")

# Pointer.
pointer = track((720, 420), [(0.6, 1.4, (440, 164)), (4.0, 4.6, (300, 50)), (9.2, 9.9, (500, 164)),
                             (10.1, 11.0, (640, 254)), (12.8, 13.4, (560, 50)), (13.6, 14.2, (600, 120)),
                             (16.8, 17.8, (720, 420))])
add("<g>" + animate(None, pointer, transform=True))
add(f'<circle r="13" fill="{BLUE}" fill-opacity="0.18" stroke="{BLUE}" stroke-width="1.5" opacity="0">'
    + opacity([(10.0, 11.9), (13.5, 15.3)]) + "</circle>")
add('<path d="M0 0 L0 18 L4.6 13.6 L7.8 20.4 L10.6 19.2 L7.5 12.6 L13 12.6 Z" fill="#111" stroke="#FFF" '
    'stroke-width="1.4" stroke-linejoin="round"/>')
add("</g>")


def caption(text, windows):
    w = 36 + len(text) * 8.0
    add(f'<g opacity="0">{opacity(windows)}'
        f'<rect x="{480 - w / 2}" y="540" width="{w}" height="36" rx="18" fill="{INK}" fill-opacity="0.88"/>'
        f'<text x="480" y="563" font-size="15" font-weight="600" fill="#FFFFFF" text-anchor="middle">{text}</text></g>')


caption("Swipe on a titlebar to snap", [(0.3, 3.9)])
caption("Pinch out to fill, pinch in to restore", [(4.2, 8.8)])
caption("Mouse: drag, scroll away to fill", [(9.1, 12.5)])
caption("Scroll towards you to restore", [(12.9, 16.6)])
add("</g>")

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="960" height="600" viewBox="0 0 960 600" '
       f'font-family="{FONT}" role="img" aria-label="Flick snapping, filling and restoring a window">\n'
       + "\n".join(out) + "\n</svg>\n")
Path(__file__).with_name("demo.svg").write_text(svg)
