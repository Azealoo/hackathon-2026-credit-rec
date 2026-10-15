# Paywise: Design

Shared style reference for the iOS app, the Northbay Electronics demo store and the HTML claim verdict. It records the look of the concept film (SPEC.md §12; the film's code is local to the owner's Mac and is not in this repo) as tokens. Copy lives in SPEC.md §5.5, §6.3 and §15.4; this doc doesn't repeat it.

Values below are the film's. Where the film had no answer (e.g. art for two of the five cards), the text says **proposed**.

## 1. The one rule: light to buy, dark to claim

| Moment | Mode | Where |
|---|---|---|
| Paying: checkout, island, snippet | **Light** | Demo store, Live Activity, result snippet |
| "14 months later": Purchases, detail, claim, verdict | **Dark** | App screens, HTML verdict |

The contrast is the story: bright and quick at the till, calm and serious when something has gone wrong. Don't make the app follow the system setting for these screens; the verdict page is always dark, the demo store is always light. The snippet is system-presented, so it uses the system material (§4) and follows the phone.

## 2. Color

### Brand accent

| Token | Hex | Use |
|---|---|---|
| `accent` (light) | `#3f5bf6` | Primary button fill, links, glyph on light |
| `accentDark` | `#5b74ff` | Same roles on dark; glyph and ring in the island; selected chips |
| `iconFrom` / `iconTo` | `#6d7cff` → `#2a3fd8` | App icon gradient (160°) only |

Primary buttons carry white text. In SwiftUI define `accent` as a color-asset with Any/Dark appearances; don't use `.blue`.

### iOS system colors (use these, not new greys)

| Role | Light | Dark | SwiftUI |
|---|---|---|---|
| Background | `#ffffff` | `#000000` | `Color(.systemBackground)` |
| Grouped background | `#f2f2f7` | `#000000` | `Color(.systemGroupedBackground)` |
| Cell / card | `#ffffff` | `#1c1c1e` | `Color(.secondarySystemGroupedBackground)` |
| Label | `#000000` | `#ffffff` | `.primary` |
| Secondary label | `rgba(60,60,67,.6)` | `rgba(235,235,245,.6)` | `.secondary` |
| Tertiary label | `rgba(60,60,67,.3)` | `rgba(235,235,245,.3)` | `.tertiary` |
| Separator | `rgba(60,60,67,.18)` | `rgba(84,84,88,.6)` | `Color(.separator)` (0.5 pt) |
| Fill (secondary button) | `rgba(120,120,128,.14)` | `rgba(120,120,128,.32)` | `Color(.tertiarySystemFill)`-ish |
| Green (covered, ✓) | `#34c759` | `#30d158` | `.green` |
| Red (not covered) | `#ff3b30` | `#ff453a` | `.red` |
| Notice / deadline text (dark only) | n/a | `#ffd60a` | `.yellow` |

Color is never the only cue (SPEC §6.4): verdicts pair green with a filled shield + check and red with an ✗ circle.

### Store and stage

- Demo store: white page, black text, one store accent `#0d7a5f` (delivery line, "Change"), black `#111214` pill "Place order". Deliberately unlike Paywise's indigo so the two never blur.
- Concept-film stage (for the video and Devpost images only): white `#ffffff` for purchase and end card, black `#000000` for "14 months later"; ink `#1d1d1f` / `#6e6e73`, paper `#f5f5f7` / `#86868b`.

## 3. Type

SF Pro via the system font. SwiftUI: default `.system`. Web: `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif` (SF Pro only renders on Apple devices; fall back is fine). Mono (the "what we sent" text): `ui-monospace, "SF Mono", Menlo, monospace`. Money uses tabular figures (`.monospacedDigit()` / `font-variant-numeric: tabular-nums`).

Sizes are points (px on the web at 1:1). Tracking is in points, as the film uses it; SwiftUI `.tracking()` takes the same unit.

### Snippet and Live Activity (light)

| Element | Size / weight | Tracking | Color |
|---|---|---|---|
| Line 1, verdict ("Use Freedom ••1234") | 23 / bold | −0.5 | label |
| Line 2, gain ("Adds a warranty year…") | 16 / medium | −0.2 | label |
| Line 3, cost | 16 / regular | −0.2 | secondary |
| Instruction ("Change card to…") | 14 / regular, with a ↳ glyph | 0 | secondary |
| Saved lines 2–3 | 15 / medium | −0.3 | label |
| Saved footnote | 13 / regular, line 17 | 0 | secondary |
| Header app name / "now" | 14 semibold / 13 | 0 | secondary / tertiary |
| Button label | 16.5 / semibold | −0.2 | white on accent; label on fill |

### App screens and verdict (dark)

| Element | Size / weight | Tracking |
|---|---|---|
| Large title ("Purchases") | 34 / bold | −0.8 |
| Detail title | 28 / bold | −0.6 |
| Section title | 20 / bold | −0.4 |
| Row title | 17 / semibold | −0.3 |
| Row meta | 13–14 / regular, secondary | 0 |
| Verdict title | 18 / bold, line 23 | −0.35 |
| Verdict body | 15 / regular, line 20, `rgba(235,235,245,.86)` | −0.2 |
| Notice line | 14, line 19, yellow | 0 |
| Checklist heading / items | 13 semibold secondary / 14.5 | 0 |
| Footer disclaimer | 12.5, line 16, tertiary | 0 |
| Primary button | 17 / semibold, white | 0 |
| Tab label | 10.5 / semibold | 0 |

Store checkout: title 30 bold (−0.7); wordmark "NORTHBAY" 17 extra-bold, +2.6 tracking, next to "Electronics" 13 medium; body 15; label 13 semibold; total 19 bold.

In SwiftUI prefer Dynamic Type styles near these (`.title`, `.headline`, `.subheadline`, `.footnote`) over fixed sizes; the table is the visual target. SPEC §6.4: Dynamic Type drops secondary lines first.

## 4. Shape, spacing, material

| Token | Value |
|---|---|
| Snippet | 40 pt radius, 9 pt side inset, 54 pt from top, 272 pt tall, 20 pt padding |
| Snippet material | ≈80% white glass (`.regularMaterial` in SwiftUI), 26 pt blur; soft shadow `0 22 60 rgba(10,20,60,.22)`. In dark system mode let the system choose |
| Buttons | 50 pt tall, fully round; 10 pt gap; secondary 92 pt wide, primary flexes |
| App grouped card | 22–26 pt radius; row padding 14–16; separator inset to text (80 pt left on rows with a thumbnail) |
| Verdict card | 28 pt radius, `#1c1c1e`, 20 pt padding, 16 pt screen inset, rises from the bottom |
| Chips | 38 pt tall, pill; selected = accentDark fill, white text, check at left |
| Icon tile (purchase row) | 11–14 pt radius |
| Hairline | 0.5 pt |
| Spacing scale in use | 3, 6, 8, 10, 12, 14, 16, 20, 26 |
| App icon | squircle radius 22.37% of side |

Motion (for parity in SwiftUI): springs, content cross-fades with a small blur (8–10 pt) and 10 pt vertical drift; snippet grows out of the island; screens push like normal iOS navigation. No UI sounds in v1 (see `silent.caf` below).

## 5. The glyph and app icon

**Glyph:** a shield outline made of lines of fine print. 24×24 grid; shield path `M12 2.6 19.4 5.4v5.9c0 4.5-3.1 8.1-7.4 10.1-4.3-2-7.4-5.6-7.4-10.1V5.4L12 2.6Z`, stroke 1.9, round joins; inside, three left-aligned text lines at y = 9.4, 12.4, 15.4 from x = 8.4, the first two to x = 15.6 and the last short, to x = 12.3, stroke 1.9, round caps. Single color: `accentDark` in the island, any foreground color elsewhere. It is the Checking glyph, the minimal presentation and the stale state (SPEC §6.4). Needs a template-rendered SF Symbol-style asset for the widget; keep strokes ≥1.9 on the 24 grid so it survives at 22 pt.

**App icon:** indigo squircle, gradient from `#6d7cff` (top) to `#2a3fd8` (bottom) at 160°; a soft white highlight from the top-left (radial, ≈35% white fading out by 60%); an inner top edge light and bottom edge shade for depth. On it, a *filled* white shield (≈62% of the icon) with the three lines cut out in `#2a3fd8`. Needs light, dark and tinted variants for iOS; the film only shows the standard one (dark and tinted: **proposed**, derive from the glyph).

**Progress ring** (island, trailing): 22 pt, 2.6 stroke, track `rgba(255,255,255,.16)`, arc `accentDark`, round cap, rotating; the arc length breathes between ≈28% and 46%.

## 6. Card art

Generic, team-made shapes. No issuer artwork, logos, network marks or real numbers (SPEC §6.4, CLAUDE.md rules). Every card shares one construction so the five read as a set:

- ID-1 ratio, 1.586 : 1. Corner radius 8.5% of the width.
- A large soft circle, 110% of the width, clipped by the card, its center near the top right (left edge at 35% of the width, top at −55%). White at 13% (60% on the light card) as a sheen.
- A small chip: 16% of the width × 24% of the height, 11% in from the left, 36% down, radius 3% of the width, gold gradient `#f1d796` → `#c9a54f`.
- No text on the art. The last 4 and the name sit beside it in live text.
- Edge: 1 px soft shadow `rgba(0,0,0,.18)`; the light card gets a 0.6 pt `rgba(0,0,0,.12)` inner stroke so it doesn't vanish on white.

| Card (`id`) | Gradient (135°) | In the film |
|---|---|---|
| Freedom (`chase-freedom-unlimited`) | `#3f7ff0` → `#1b4fb8` 55% → `#10306f` | yes |
| Apple Card (`apple-card`) | `#fbfbfc` → `#e4e5ea` 60% → `#cfd1d8` | yes ("default") |
| Active Cash (`wf-active-cash`) | `#ef6a5b` → `#c23a3f` 60% → `#8e2232` | yes |
| Freedom Rise (`chase-freedom-rise`) | **proposed:** teal `#35b6a8` → `#1a7f86` → `#0f4f57` | no |
| Discover (`discover-it-student-cash-back`) | **proposed:** amber `#f6a54a` → `#e07a2b` → `#a84f1a` | no |

Make the three film colors distinct from each other and from the issuers' real brand art; the two new ones follow the same rule. The `art.assetName` and `art.color` fields in `data/cards.json` (SPEC §15.3) should point at these.

## 7. Assets D must make

SPEC §6.4 (card art, minimal/stale glyph), §9.1 (art bundled in the asset catalog; send a `cardId`, not an image), §6.1 and §16 (silent alert sound, gate G2).

| Asset | Spec | Notes |
|---|---|---|
| **Card art ×5**, compact | @3x PNG (or vector, rasterized to the exact size), **52.33 × 36.67 pt = 157 × 110 px** (393-pt screens); 62.33 × 36.67 pt = **187 × 110 px** for 430-pt | SPEC §6.1 sizes. The compact slot is wider (1.43) than a card (1.586), so crop or letterbox. Don't ship larger; oversize art can make Live Activity start fail |
| **Card art ×5**, expanded | @3x, exact size of the expanded leading slot | §6.1 gives only the container (371 or 408 × 84–160 pt), not the art. **C to give the slot size before D exports.** The film draws it at 52 × 32.8 pt |
| **Card art ×5**, snippet | Same files as expanded (SPEC §6.4: "the snippet uses the same art") | Film size 52 pt wide |
| **Paywise glyph** | Template (single-color) PDF/SVG vector at 24×24 grid, plus @3x PNGs at 22 pt and 36.67 pt for island/minimal | Section 5 |
| **App icon** | 1024×1024 standard, dark and tinted variants; no transparency | Section 5 |
| **`silent.caf`** | Silent audio, ≤30 s as Apple requires for notification sounds (a few ms of true silence is fine), linear PCM or IMA4, mono 44.1 kHz, in the app *and* widget bundle as the spike needs | Used by `.named("silent.caf")` for the Keep and error island alerts (SPEC §6.3). Check on a device that the island expands with no sound; if not, SPEC §6.6 falls back to `.default` |

Not confirmed: the expanded art size (above), the exact `.caf` format the island accepts (check in spike S2), and whether the app needs the sound in the main bundle, the widget bundle or both.

## 8. Using this on the web

CSS tokens for the store and verdict, same values as above:

```css
:root {
  --fp-accent: #3f5bf6; --fp-accent-dark: #5b74ff;
  --bg: #ffffff; --grouped: #f2f2f7; --cell: #ffffff; --label: #000;
  --secondary: rgba(60,60,67,.6); --separator: rgba(60,60,67,.18);
  --green: #34c759; --red: #ff3b30;
}
.verdict { /* always dark */
  --bg: #000; --cell: #1c1c1e; --label: #fff;
  --secondary: rgba(235,235,245,.6); --separator: rgba(84,84,88,.6);
  --green: #30d158; --red: #ff453a; --notice: #ffd60a;
  --accent: var(--fp-accent-dark);
}
```

Verdict page keeps the film's footer verbatim from SPEC §5.5 and states it is a concept (SPEC §12.3).
