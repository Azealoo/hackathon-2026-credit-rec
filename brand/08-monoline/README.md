# 08 · Monoline — "Drawn"

**Idea.** A file of cards recedes into the distance in true one-point perspective, so the stack reads as deeper than you can count. One card has been drawn out of it toward you, tilted as if in your fingers. It is the only closed outline, the only one with a chip, and the only one in colour.

"Drawn" has two meanings here: the card is drawn out of the file, and the whole mark is drawn with one pen. Every line uses the same stroke with round caps. Where a card passes behind another, its line stops one stroke-width short instead of being clipped, so every line end is a true round cap.

## Files

| File | What it is |
|---|---|
| `mark.svg` | Symbol for light backgrounds (ink stack, indigo card) |
| `mark-dark.svg` | Symbol for dark backgrounds (paper stack, light-indigo card) |
| `mark-island.svg` / `mark-island-dark.svg` | The symbol at the Dynamic Island's 22 pt: two cards behind instead of six, heavier stroke, solid chip. The iOS Live Activity's glyph |
| `app-icon.svg` | 1024 × 1024, full bleed, square corners, opaque |
| `lockup.svg` / `lockup-dark.svg` | Symbol plus the "Paywise" wordmark, with the text outlined |
| `generate.py` | Regenerates every SVG. Standard library only: `python3 generate.py` |
| `ttf.py` | A small TrueType reader (glyf + gvar) used to outline the wordmark from the Mac's own SF Pro |

## Palette

| Role | Hex |
|---|---|
| Stack lines on light | `#1d1d1f` (brand ink) |
| Drawn card on light | `#3f5bf6` (brand accent) |
| Stack lines on dark | `#f5f5f7` (brand paper) |
| Drawn card on dark | `#5b74ff` (brand accent, dark variant) |
| App icon background | `#6d7cff` → `#2a3fd8`, diagonal (brand icon gradient) |
| App icon lines | `#ffffff`; stack at 62% opacity over the opaque gradient |

All colours are the brand palette in `docs/design.md` §2. Nothing new was added.

## Type

The wordmark is SF Pro Display at weight 520 (between Regular and Medium), optical size 96, with tracking of −1.2%. It is outlined to paths from `/System/Library/Fonts/SFNS.ttf` by `ttf.py`, so the SVGs contain no `<text>` and need no font. Kerning (GPOS) is not applied. Spacing for "Paywise" looked even at display size, but check it before you ship.

## Construction

- Cards use the ISO ID-1 proportion (85.6 × 53.98 mm, about 1.586:1). The corner radius is 5.5% of the card width. That is tighter than icon-set radii, which gives a drafted rather than a clip-art feel.
- Stroke: 2.4 units on a ~100-unit design, for the mark and the lockup.
- The stack has 6 cards. Each one is the card in front scaled by 0.86 toward a vanishing point up and to the right.
- The drawn card is turned −8° and sits lower-left, overlapping the front of the file.
- App icon: the same design at a separate optical size. The stroke is heavier (4.6) and the stack has only 4 cards, so the lines stay apart at 29 px.
- Island mark: a third optical size, for the Dynamic Island's 22-pt glyph slot. Only the 2 nearest cards of the file, spaced wider (each 0.89 of the one in front), so 1.82-pt strokes keep at least 1.34 pt of black between any two lines (2.2 pt between the two cards' top edges). The stack is paper (or ink) at 62% so the drawn card leads. The chip is filled, because an outlined chip closes up at this size. At 22 pt, `generate.py` stops if a stroke is under 1.7 pt or the black between two lines under 1.2 pt.

## Known weaknesses

- **It is not one continuous line.** It uses 8 strokes: 6 stack lines, the card and the chip. Wherever a card is hidden behind another, two lines meet in a T. Each card behind the first adds two loose ends, so a stack drawn with its hidden edges removed can't be traced in one stroke. I kept the depth reading and gave up the single line.
- **The mark, the app icon and the island mark are not identical.** Below about 40 px, the six stack lines of `mark.svg` blur into grey. For small sizes, use the app-icon geometry (4 cards, heavier stroke). At 29 px @1x the chip becomes a dot, but the card and the two lines behind it still read. At @2x (58 px, the real Settings size) it is clean. At 22 pt (66 px @3x, the Dynamic Island) use `mark-island*.svg`.
- **Stacked cards are a familiar motif.** The perspective, the tight corners and the single coloured card set it apart from stock "cards" icons, but it is still the least surprising part of the idea.
- **"Pulled out" reads as "taken off the front", not "pulled from the middle".** The version where the card is pulled from the middle looked like a camera or a briefcase in testing, so I dropped it.
- **It depends on colour.** The story ("this one") is clearest in two tones. For a one-colour version, set both stroke groups to ink. The card still stands out because it is the only closed shape with a chip.
- **SF Pro licence: not confirmed.** I believe Apple's SF Pro licence covers mock-ups of Apple-platform UI, which may not include a logo wordmark. I couldn't check the licence text from here. Check it, or swap the wordmark to a licensed face, before the logo is used outside the app.
