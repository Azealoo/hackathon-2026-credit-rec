#!/usr/bin/env python3
"""Paywise logo option 08 — Monoline ("Drawn").

Regenerates every SVG in this folder:  python3 generate.py
Standard library only. The wordmark is outlined from the macOS system font
(/System/Library/Fonts/SFNS.ttf) by ttf.py, so run it on a Mac.

Geometry: a file of cards recedes toward a vanishing point above (one-point
perspective: each card is the one in front scaled toward the VP). The front
card has been drawn out of the file and tilted toward the viewer. Every line is
the same stroke with round caps. Hidden edges are removed analytically and each
line stops one stroke-width short of the edge that hides it, so line ends are
true round caps rather than clipped ends.

mark-island*.svg is the same idea at the Dynamic Island's optical size (22 pt): two cards of the file instead of six,
strokes of at least 1.7 pt there, the chip filled.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# Palette (see README). Light / dark / icon.
INK = '#1d1d1f'
PAPER = '#f5f5f7'
ACCENT = '#3f5bf6'
ACCENT_DARK = '#5b74ff'
ICON_FROM = '#6d7cff'
ICON_TO = '#2a3fd8'

CARD_RATIO = 85.6 / 53.98      # ISO/IEC 7810 ID-1
CORNER = 0.055                 # corner radius as a fraction of card width


# ---------------------------------------------------------------- geometry --
# Segments: ('L', p0, p1) or ('A', centre, r, a0, a1), angles in radians,
# screen coordinates (y down, so increasing angle runs clockwise).

def seg_point(s, t):
    if s[0] == 'L':
        (x0, y0), (x1, y1) = s[1], s[2]
        return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
    (cx, cy), r, a0, a1 = s[1], s[2], s[3], s[4]
    a = a0 + (a1 - a0) * t
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def sub_seg(s, t0, t1):
    if s[0] == 'L':
        return ('L', seg_point(s, t0), seg_point(s, t1))
    c, r, a0, a1 = s[1], s[2], s[3], s[4]
    return ('A', c, r, a0 + (a1 - a0) * t0, a0 + (a1 - a0) * t1)


def seg_len(s):
    if s[0] == 'L':
        (x0, y0), (x1, y1) = s[1], s[2]
        return math.hypot(x1 - x0, y1 - y0)
    return abs(s[4] - s[3]) * s[2]


class Card:
    """Rounded rectangle, optionally rotated (degrees) about its centre."""

    def __init__(self, cx, cy, w, h=None, r=None, rot=0.0):
        self.cx, self.cy, self.w = cx, cy, w
        self.h = w / CARD_RATIO if h is None else h
        self.r = w * CORNER if r is None else r
        self.rot = math.radians(rot)

    def world(self, p):
        c, s = math.cos(self.rot), math.sin(self.rot)
        return (p[0] * c - p[1] * s + self.cx, p[0] * s + p[1] * c + self.cy)

    def local(self, p):
        x, y = p[0] - self.cx, p[1] - self.cy
        c, s = math.cos(-self.rot), math.sin(-self.rot)
        return (x * c - y * s, x * s + y * c)

    def sd(self, p):
        """Signed distance to the outline (negative inside)."""
        x, y = self.local(p)
        qx = abs(x) - (self.w / 2 - self.r)
        qy = abs(y) - (self.h / 2 - self.r)
        return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - self.r

    def segs(self):
        w, h, r, P = self.w / 2, self.h / 2, self.r, math.pi
        loc = [
            ('L', (-w + r, -h), (w - r, -h)),
            ('A', (w - r, -h + r), r, -P / 2, 0),
            ('L', (w, -h + r), (w, h - r)),
            ('A', (w - r, h - r), r, 0, P / 2),
            ('L', (w - r, h), (-w + r, h)),
            ('A', (-w + r, h - r), r, P / 2, P),
            ('L', (-w, h - r), (-w, -h + r)),
            ('A', (-w + r, -h + r), r, P, 1.5 * P),
        ]
        out = []
        for s in loc:
            if s[0] == 'L':
                out.append(('L', self.world(s[1]), self.world(s[2])))
            else:
                out.append(('A', self.world(s[1]), s[2], s[3] + self.rot, s[4] + self.rot))
        return out

    def chip(self):
        """The contact chip: a small rounded rectangle left of centre."""
        w = self.w * 0.155
        h = w * 0.78
        cx, cy = self.world((-self.w / 2 + self.w * 0.2, -self.h * 0.06))
        return Card(cx, cy, w, h, w * 0.24, math.degrees(self.rot))


def visible_runs(segs, visible, minlen):
    """Split a closed outline into the runs where visible(p) holds."""
    pieces, N = [], 200
    for i, s in enumerate(segs):
        ts = [k / N for k in range(N + 1)]
        vs = [visible(seg_point(s, t)) for t in ts]

        def refine(ta, tb, va):
            for _ in range(40):
                tm = (ta + tb) / 2
                if visible(seg_point(s, tm)) == va:
                    ta = tm
                else:
                    tb = tm
            return (ta + tb) / 2

        start = 0.0 if vs[0] else None
        for k in range(1, N + 1):
            if vs[k] != vs[k - 1]:
                tc = refine(ts[k - 1], ts[k], vs[k - 1])
                if vs[k]:
                    start = tc
                else:
                    pieces.append((i, start, tc))
                    start = None
        if start is not None:
            pieces.append((i, start, 1.0))
    runs = []
    for i, t0, t1 in pieces:
        sub = sub_seg(segs[i], t0, t1)
        if runs and t0 == 0.0 and runs[-1]['end'] == (i - 1, 1.0):
            runs[-1]['segs'].append(sub)
            runs[-1]['end'] = (i, t1)
        else:
            runs.append({'segs': [sub], 'start': (i, t0), 'end': (i, t1)})
    n = len(segs)
    if len(runs) == 1 and runs[0]['start'] == (0, 0.0) and runs[0]['end'] == (n - 1, 1.0):
        return [(runs[0]['segs'], True)]
    if len(runs) > 1 and runs[0]['start'] == (0, 0.0) and runs[-1]['end'] == (n - 1, 1.0):
        runs[-1]['segs'].extend(runs[0]['segs'])
        runs = runs[1:]
    return [(r['segs'], False) for r in runs if sum(seg_len(s) for s in r['segs']) >= minlen]


def fmt(v):
    s = f'{v:.2f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def path_d(segs, closed, k=1.0, ox=0.0, oy=0.0):
    T = lambda p: (ox + p[0] * k, oy + p[1] * k)
    x, y = T(seg_point(segs[0], 0))
    d = [f'M{fmt(x)} {fmt(y)}']
    for s in segs:
        x1, y1 = T(seg_point(s, 1))
        if s[0] == 'L':
            d.append(f'L{fmt(x1)} {fmt(y1)}')
        else:
            r = s[2] * k
            sweep = 1 if s[4] > s[3] else 0
            large = 1 if abs(s[4] - s[3]) > math.pi else 0
            d.append(f'A{fmt(r)} {fmt(r)} 0 {large} {sweep} {fmt(x1)} {fmt(y1)}')
    if closed:
        d.append('Z')
    return ''.join(d)


# ------------------------------------------------------------------ design --

def design(depth=6, recede=0.86, sw=2.4, gap=None, vp=(90.0, -30.0), front=(50.0, 52.0, 58.0),
           drawn=(40.0, 70.0, 60.0, -8.0), solid_chip=None):
    """Return {'stack': [runs], 'card': [runs]} in a ~100-unit design space.

    depth      : cards left in the file behind the drawn card
    recede     : scale from one card to the next one back (perspective)
    vp         : vanishing point, up and to the right
    front      : first card of the file: cx, cy, width
    drawn      : the drawn card: cx, cy, width, rotation (degrees)
    solid_chip : None draws the chip as an outline in 'card'; a number puts it under 'chip' instead, scaled by
                 that factor and moved in to clear the card's stroke by `gap`, for drawing filled (the island
                 mark: at 22 pt an outlined chip closes up)
    """
    gap = sw * 0.9 if gap is None else gap
    stack = []
    for k in range(depth):
        f = recede ** k
        stack.append(Card(vp[0] + (front[0] - vp[0]) * f,
                          vp[1] + (front[1] - vp[1]) * f, front[2] * f))
    drawn = Card(drawn[0], drawn[1], drawn[2], rot=drawn[3])
    thr = sw + gap                     # cap radius + neighbour half-stroke + air
    out = {'stack': [], 'card': []}
    order = [drawn] + stack            # nearest first
    for k, c in enumerate(order):
        nearer = order[:k]
        vis = lambda p, nearer=nearer: all(o.sd(p) > thr for o in nearer)
        runs = visible_runs(c.segs(), vis, minlen=sw * 0.8)
        out['card' if c is drawn else 'stack'].extend(runs)
    chip = drawn.chip()
    if solid_chip is None:
        out['card'].append((chip.segs(), True))
    else:
        w, h = chip.w * solid_chip, chip.h * solid_chip
        cx, cy = drawn.world((-drawn.w / 2 + sw / 2 + gap + w / 2, -drawn.h * 0.06))
        out['chip'] = [(Card(cx, cy, w, h, chip.r * solid_chip, math.degrees(drawn.rot)).segs(), True)]
    return out


def bbox(runs_by_role, sw):
    xs, ys = [], []
    for runs in runs_by_role.values():
        for segs, _ in runs:
            for s in segs:
                for t in (0, 0.25, 0.5, 0.75, 1):
                    x, y = seg_point(s, t)
                    xs.append(x)
                    ys.append(y)
    h = sw / 2
    return min(xs) - h, min(ys) - h, max(xs) + h, max(ys) + h


def paths(runs, k, ox, oy):
    return [path_d(segs, closed, k, ox, oy) for segs, closed in runs]


def group(ds, color, sw, extra=''):
    body = ''.join(f'<path d="{d}"/>' for d in ds)
    return (f'<g fill="none" stroke="{color}" stroke-width="{fmt(sw)}" stroke-linecap="round" '
            f'stroke-linejoin="round"{extra}>{body}</g>')


def fit(geo, sw, size, pad):
    """Scale + offset that fit the geometry's bbox into a size×size box with padding."""
    x0, y0, x1, y1 = bbox(geo, sw)
    k = (size - 2 * pad) / max(x1 - x0, y1 - y0)
    ox = (size - (x1 - x0) * k) / 2 - x0 * k
    oy = (size - (y1 - y0) * k) / 2 - y0 * k
    return k, ox, oy


def mark_svg(stack_color, card_color, title):
    sw = 2.4
    geo = design(sw=sw)
    size = 512
    k, ox, oy = fit(geo, sw, size, pad=12)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" '
            f'height="{size}" role="img" aria-label="{title}"><title>{title}</title>'
            + group(paths(geo['stack'], k, ox, oy), stack_color, sw * k)
            + group(paths(geo['card'], k, ox, oy), card_color, sw * k)
            + '</svg>\n')


def app_icon_svg():
    # Optical size for the home screen: heavier stroke, fewer, wider-spaced cards
    # so the file still reads as separate cards at 29 px.
    sw = 4.6
    geo = design(depth=4, recede=0.86, sw=sw, gap=sw * 0.75)
    size = 1024
    k, ox, oy = fit(geo, sw, size, pad=184)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" '
            f'height="{size}"><title>Paywise app icon</title>'
            f'<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{ICON_FROM}"/><stop offset="1" stop-color="{ICON_TO}"/>'
            f'</linearGradient></defs>'
            f'<rect width="{size}" height="{size}" fill="url(#bg)"/>'
            + group(paths(geo['stack'], k, ox, oy), '#ffffff', sw * k, ' stroke-opacity="0.62"')
            + group(paths(geo['card'], k, ox, oy), '#ffffff', sw * k)
            + '</svg>\n')


ISLAND_SLOT_PT = 22             # the Dynamic Island's compact leading / minimal glyph
ISLAND_MIN_STROKE_PT = 1.7
ISLAND_MIN_CLEAR_PT = 1.2       # black between two strokes (or a stroke and the chip), edge to edge
ISLAND_STACK_OPACITY = 0.62     # the app icon's stack opacity


def min_clearance(geo, sw):
    """Smallest edge-to-edge distance between two different lines, or between the filled chip and the card."""
    def samples(segs):
        return [seg_point(s, t / 100) for s in segs for t in range(101)]
    lines = [samples(segs) for role in ('stack', 'card') for segs, _ in geo[role]]
    pairs = [(a, b, sw) for i, a in enumerate(lines) for b in lines[i + 1:]]
    pairs += [(samples(segs), line, sw / 2) for segs, _ in geo.get('chip', []) for line in lines]
    return min(min(math.dist(p, q) for p in a for q in b) - inset for a, b, inset in pairs)


def island_svg(stack_color, card_color, title):
    # Optical size for the Dynamic Island (22 pt): the drawn card, its chip filled (an outlined chip closes up at
    # this size) and only the two nearest cards of the file, spaced wider so 1.8-pt strokes stay apart. Laid out in
    # points of the 22-pt slot; fit() scales it to the viewBox. Same rules as the mark: one-point perspective toward a
    # vanishing point up and to the right, hidden edges removed, round caps.
    sw = 1.9
    geo = design(depth=2, recede=0.89, sw=sw, gap=1.4, vp=(30.0, -34.0), front=(12.5, 9.0, 14.0),
                 drawn=(8.6, 15.3, 15.0, -8.0), solid_chip=1.6)
    size = 512
    k, ox, oy = fit(geo, sw, size, pad=6)
    pt = k * ISLAND_SLOT_PT / size
    stroke_pt, clear_pt = sw * pt, min_clearance(geo, sw) * pt
    if stroke_pt < ISLAND_MIN_STROKE_PT or clear_pt < ISLAND_MIN_CLEAR_PT:
        raise SystemExit(f'island mark at {ISLAND_SLOT_PT} pt: strokes {stroke_pt:.2f} pt (min {ISLAND_MIN_STROKE_PT}), '
                         f'clearance {clear_pt:.2f} pt (min {ISLAND_MIN_CLEAR_PT})')
    chip = ''.join(f'<path d="{d}"/>' for d in paths(geo['chip'], k, ox, oy))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" '
           f'height="{size}" role="img" aria-label="{title}"><title>{title}</title>'
           + group(paths(geo['stack'], k, ox, oy), stack_color, sw * k,
                   f' stroke-opacity="{fmt(ISLAND_STACK_OPACITY)}"')
           + group(paths(geo['card'], k, ox, oy), card_color, sw * k)
           + f'<g fill="{card_color}">{chip}</g>'
           + '</svg>\n')
    return svg, stroke_pt, clear_pt


def lockup_svg(stack_color, card_color, ink, title):
    from ttf import Font, text_path
    font = Font('/System/Library/Fonts/SFNS.ttf')
    sw = 2.4
    geo = design(sw=sw)
    mh = 200.0                                    # mark height in lockup units
    m = 6.0                                       # margin so round caps never touch the edge
    x0, y0, x1, y1 = bbox(geo, sw)
    k = mh / (y1 - y0)
    ox, oy = m - x0 * k, m - y0 * k
    mw = (x1 - x0) * k
    # Wordmark: SF Pro Display Medium, optical size 96. Cap height ≈ 0.705 em.
    size = 128.0
    cap = 0.705 * size
    baseline = m + mh / 2 + cap / 2
    gap = 0.34 * mh
    d, tw = text_path(font, 'Paywise', size, {'wght': 520, 'opsz': 96}, tracking=-0.012,
                      x=m + mw + gap, baseline=baseline)
    W, H = m + mw + gap + tw + m, mh + 2 * m
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(W)} {fmt(H)}" '
            f'width="{fmt(W * 2)}" height="{fmt(H * 2)}" role="img" aria-label="{title}">'
            f'<title>{title}</title>'
            + group(paths(geo['stack'], k, ox, oy), stack_color, sw * k)
            + group(paths(geo['card'], k, ox, oy), card_color, sw * k)
            + f'<path d="{d}" fill="{ink}"/></svg>\n')


def main():
    island, island_stroke, island_clear = island_svg(INK, ACCENT, 'Paywise')
    island_dark, _, _ = island_svg(PAPER, ACCENT_DARK, 'Paywise')
    files = {
        'mark.svg': mark_svg(INK, ACCENT, 'Paywise'),
        'mark-dark.svg': mark_svg(PAPER, ACCENT_DARK, 'Paywise'),
        'mark-island.svg': island,
        'mark-island-dark.svg': island_dark,
        'app-icon.svg': app_icon_svg(),
        'lockup.svg': lockup_svg(INK, ACCENT, INK, 'Paywise'),
        'lockup-dark.svg': lockup_svg(PAPER, ACCENT_DARK, PAPER, 'Paywise'),
    }
    for name, svg in files.items():
        with open(os.path.join(HERE, name), 'w') as fh:
            fh.write(svg)
        print(f'wrote {name} ({len(svg)} bytes)')
    print(f'mark-island at {ISLAND_SLOT_PT} pt: {island_stroke:.2f} pt strokes, {island_clear:.2f} pt clear between them')


if __name__ == '__main__':
    main()
