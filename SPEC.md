# Paywise — Product Spec

**Version:** 2.4 (Oct 16, 2026) · **Event:** DubHacks '26, UW Seattle, Oct 17–18 · **Track:** Visa: Reimagine Shopping (sponsored side track; prompt and rubric in §11.0)
**Status:** Product-form decision after a 7-reviewer product-form review (product manager, interaction designer, form-factor designer, student user, competitive analyst, hackathon/Visa judge, iOS engineering lead), a PM decision and a challenge round. Items marked **(u)** are unverified and must be tested before we rely on them.

## Changelog

**v2.4 (Oct 16, 2026): the spec matches the code after the product review**
- **Visa:** G4 failed on Cybersource's side (`docs/spikes.md`), so §11.2 and §12.1–12.3 script the demo payment on `PAY_MODE=mock` and make no Visa-API claim. §11.3 no longer says Visa built the benefit tiers: the demo card's protections are Chase's.
- **G1 fallback:** the iOS 27 screenshot automation is rejected (owner, Oct 16). §4.2 P1-14, §4.5 and §6.6 now say so; the first fallback is a Wait before Take Screenshot.
- **Contracts (§15.5):** now match `contracts/` and the engine: glyph `paywise` (R2), optional `amountOnCardUsd` (R3), Live Activity `line3` (R4) and `cardId` (R14), the coverage response's `incident` (R17), and the extended-warranty limit of $10,000 per item. `LLM_PROVIDER` and `PUBLIC_BASE_URL` are gone: nothing reads them.
- **Tracks (§14.3):** the 9:30 PM default is one title track plus Visa.
- **Team (§14.2):** the roster is settled at 4. **Interviews (§1):** the placeholder now says no results are in the repo yet.

**v2.3 (Oct 16, 2026): promotional offers (owner decisions D1–D4, `reports/Paywise offers schema.md`)**
- **D1:** per-user offer state never leaves the phone. `/v1/check`'s request is unchanged; the response adds a public `offerContext`, and the phone's `OfferResolver` applies the user's offers to cash decisions only (§7.2 rule 9, §15.5).
- **D2:** in for the hackathon: `cards.json` schemaVersion 2 (earn-rule windows and channels, `offers[]`, `programs[]`, `events[]`, `categoryAliases[]`) and one-tap questions per card. Out: capturing offers from screenshots (§15.3, §15.9).
- **D3:** when capture comes, a rules reader first; Apple's model only after an eval on real screenshots (§15.9).
- **D4:** the best applicable earn rate wins, replacing merchant > category > base tiers, and caps fill best rate first (§7.2 rule 1, rule 9).

**v2.2 (Oct 16, 2026): Back Tap is the main trigger (owner ruling)**
- **Trigger:** double-tap the back of the iPhone (Back Tap). The Action Button is an optional "Prefer a button?" alternative, because people keep it on Silent. Onboarding shows a Back Tap prompt, then Set Up Back Tap with an in-app "Try it now" (§5.1). §0, §3, §4.1, §4.5, §5.1, §5.2, §6.6, §9.1, §12.1–12.4, §13, §14.2, §14.4, §15.7 and §16 now match. §6.3 copy is unchanged.

**v2.1 (Oct 15, 2026): decisions from the pre-build research docs**
- **Name:** Fine Print → **Paywise** (#12). The lowercase phrase "fine print" stays where it means card terms. App identifiers: bundle ID `com.azealoo.paywise`, App Group `group.com.azealoo.paywise` (§9.1, §15.2).
- **Benefits (G5, #11):** §8.1 now holds verified values. Active Cash and Apple Card have no purchase protection or extended warranty, and Freedom's $500 cap is per item. Notice deadlines are 90 days to notify and 120 days for documents. The payout cap includes the amount charged to the card. §5.5 has the theft checklist and a New York note. The Renewed beat is now "Renewed · no warranty", because Chase covers refurbished items that come with a warranty. Both license notes in §8.4 are resolved.
- **LLM (#6):** Claude Haiku 5.5 through the Anthropic API, with Sonnet 5.5 as the fallback. §10 privacy copy is rewritten for Anthropic (no training; 30-day default deletion, **(u)** until re-read).
- **Hosting (#7):** Render. A free Static Site on Thursday, then a paid Starter web service; never the Free web service.
- **Visa (#8):** the sandbox setup lives in `docs/visa-sandbox.md`. Hard stop is Fri Oct 16, 12 PM.
- **Rules (#9):** §11.0 has the published Visa prompt and the '26 rubric. Visa is a side track, so the team also needs a title track. Team size is capped at 4. The Sat 10:30 PM Devpost draft is now a gate. Deadline conflict: 10:00 vs 10:30 AM, treat 10:00 as hard.
- **Design (#5):** the "concept" label belongs to the demo and video only, not the app's verdict page (§12.3). `docs/` is listed in §15.2.

**v2.0 (Oct 15, 2026): product-form review**
- **Centre:** per-purchase protection (pick → proof → claim). Picking a card is the way in, not the product.
- **Trigger:** press and hold the **Action Button**. Back Tap is a second binding of the same Shortcut. "Check a screenshot" in the app needs no setup. *(Superseded in v2.2: Back Tap is the main trigger.)*
- **Surface:** an interactive **snippet** for answers you act on (Switch; Keep when your default already covers the item). A short, silent **Dynamic Island** alert for everything else. The island never lingers.
- **Copy:** protections are shown as facts with their caps ("$500 theft cover"). Expected-value math is removed.
- **Engine:** a protection-loss guard; cash thresholds of $3 (Apple Pay) and $5 (other paths); protection switches only for items of $100 or more in a relevant category; unreadable items → keep.
- **Scope:** 5 cards. Settings-screenshot onboarding, receipt press, claim PDF and the Why sheet move to P1. Cut: offline engine, money-leak audit, fee traps, order splitting.
- **Visa:** one Visa Acceptance sandbox authorization in the demo payment (P0, gated). VDBP moves to P1 (test data). "Visa-verified" is removed.
- **Plan:** code may now be written before the event. A Thu–Fri pre-event build with go/no-go gates replaces the "no code" prep list and the Saturday chain test. New §15 First build (v1).
- **Facts corrected:** demand stats, Apple Pay iOS 27 wording, Walmart/Amazon Apple Pay, CardPointers 8, the Freedom $500 cap, AI-provider retention, and the claim concierge fee (removed).
- **Metrics and demo:** user-value metrics added; the demo is one story arc with the judge pressing the button.

**v1.0 (Oct 14, 2026):** approved direction after a 7-judge review (Back Tap → Dynamic Island → "Pay as usual").

---

## 0. TL;DR

**One line:** Double-tap the back of your iPhone at checkout and Paywise tells you which of your cards covers this purchase if it breaks or gets stolen, and what that costs in cash back. When it does break, it tells you whether you can claim.

**Pitch (3 sentences):**
Your cards come with theft cover and extra warranty years buried in the fine print, but you never see them when you pay and almost never claim them afterwards. Double-tap the back of your iPhone on any checkout and Paywise reads the cart on your iPhone, then tells you, before you tap Pay, which card covers this item and what that costs in cash back. It keeps the purchase and its coverage dates, and if the item breaks or is stolen it tells you honestly whether you're covered, cites the clause, and lists what to send.

**Tagline:** *The perks buried in your card's fine print — at the moment you pay.*

**Product form at a glance**

| | |
|---|---|
| **What it is** | A per-purchase protection checker. At checkout it names the card whose fine print covers *this* item (theft/damage cover with its cap, an extra warranty year) and what that costs in cash back. It saves the purchase with its coverage dates. Later, "Can I claim?" answers *may be eligible* / *not covered* / *need more info*, citing the clause. |
| **Where it lives** | A native iOS 27 app plus one App Intent (`CheckCheckoutIntent`), run by a "Paywise" Shortcut that takes a screenshot of the current screen. Answers appear over whatever app or site you're in. Purchases and claims live in the app. A small backend reads the cart. |
| **How it's triggered** | On the checkout screen, double-tap the back of the iPhone (**Back Tap**). Prefer a button? The Action Button (iPhone 15 Pro and later) can run the same Shortcut instead. "Check a screenshot" in the app needs no setup. |
| **What you see when you pay** | **Switch:** a snippet at the top of the screen: "Use Freedom ••1234 / Adds a warranty year + $500 theft cover / $7.49 less cash back than Active Cash", plus [Paying with Freedom] to save the purchase. **Keep:** "✓ Keep Apple Card ••5678" flashes silently in the Dynamic Island and clears itself. Then you pay in the store's own flow. |

---

## 1. Problem

- Cardholders barely use their benefits: the average cardholder used **2.3 card benefits, down from 2.5** a year earlier. In the same study, about 29% say their card use maximizes rewards earning **(u)** (J.D. Power 2026 U.S. Credit Card Satisfaction Study, Aug 13, 2026).
- Card protections go so unused that Discover dropped extended warranty and purchase protection on Feb 28, 2018, citing "prolonged low usage".
- Smartphones drove 56.4% of 2025 holiday online sales (Adobe, Jan 2026). Many student checkouts happen inside shopping apps, where browser extensions can't run.
- iOS 27's Apple Pay sheet lets you swipe between cards and, for eligible cards, surfaces "rewards, balances, debit account balance, pay later options" (Apple). It doesn't recommend a card, says nothing about protections, and doesn't appear in saved-card checkouts.
- Our interviews (P0-16): no results are in the repo yet. Aggregates go in `docs/metrics.md`; the pitch uses an interview stat only once they are recorded and X ≥ 4 (§13).

**Our wedge:** per-purchase protection. That means the card that covers *this* item, the purchase saved when you pay, and an honest claim check later. The one-press trigger is how we get there, not the moat.

### 1.1 Competitors (as of Oct 15, 2026)

| Product | What it does at the moment of purchase | After purchase | Source status |
|---|---|---|---|
| Apple Pay (iOS 27 sheet) | Swipe between cards; shows rewards/balances/pay-later for eligible cards; with Automatic Selection, dynamic buttons surface co-brand cards. No recommendation found. | Order tracking only | Apple developer page (fetched) |
| CardPointers 8 (Sep 21, 2026) | Best card by merchant and offers. Visual Intelligence on a storefront, product, screenshot or receipt; 36 App Intents; location "AutoPilot" Live Activity; Safari extension | Offer sync, savings dashboard | 9to5Mac (search snippet); CardPointers help pages (reviewer) |
| MaxRewards | Best card by merchant; "Best Card Nearby" Live Activity; bank linking | Linked-account spend | Help center / changelog (reviewer) |
| Kudos | Best card + autofill in the browser and the iOS Safari extension; markets "hidden perks like purchase protection"; powers Samsung's checkout assistant | — | Press / investor posts (reviewer) |
| Norte (adjacent) | None (no purchase moment) | Per-card Protection Explorer and Claim Prep checklists | App Store / guides (reviewer) |

Nobody we found joins **this purchase → its coverage window → an incident check against the clause**. That rests on our own searches, which can only show absence.

---

## 2. Target user and scenarios

**Primary persona:** a UW student who pays in full and holds a Chase Freedom (Rise or Unlimited) plus a card without protections (Apple Card or Discover), buying electronics online or in apps. Secondary (P1): one-card students and cards not in our catalog.

**Honest frequency (team estimate, no source):** for this user, ~15–25% of checkouts beat the default card by more than $1 in a quarter where categories line up (~5–10% otherwise). The real value sits in 3–6 big purchases a year, in protections and in "how to pay". So the product must **always answer, and only interrupt when it matters.**

**Core scenarios (demo and tests):**

| # | Scenario | Expected answer |
|---|---|---|
| S1 | $1,499 laptop, Northbay Electronics (our fictional demo store), saved-card checkout. Wallet: Apple Card (default), Wells Fargo Active Cash, Chase Freedom Unlimited | **Switch → Freedom ••1234:** "Adds a warranty year + $500 theft cover · $7.49 less cash back than Active Cash" |
| S1-R | Same laptop, listed "Renewed · no warranty", $1,099 | **Switch → Active Cash** (cash): a renewed item with no maker's warranty gets no card cover |
| S1-K | S1 with Freedom as the default | **Keep Freedom** (already protected); snippet with save |
| S2 (engine / Q&A) | $180 shoes at Nike, Apple Pay visible | **Keep Apple Card: use Apple Pay** (3% vs 1% typed) |
| S3 | $249 earbuds stolen at week 6 | **May be eligible:** purchase protection; police report; deadline |
| S4 | Laptop shows lines at month 14, never dropped | **May be eligible:** extended warranty, clause cited. Contrast: dropped → **not covered** |

---

## 3. Product principles

1. **One press, not zero steps.** One double tap on the back of the iPhone, a ~3 s wait, at most one card change. Never claim "zero steps".
2. **Always answer visibly; vary loudness by sound and persistence, not visibility.** Answers you act on stay in a snippet. Everything else flashes silently in the island and clears.
3. **Show the trade as facts on separate lines.** Gain (with its cap) on one line, cash cost on another. Never one blended number; no expected-value math.
4. **Private by design.** We look only when you press. The screenshot is cropped, read and redacted on the phone. Only redacted order-summary text and card product names leave it. Your last 4 never leaves.
5. **Honest about coverage.** Say "may be eligible", cite the clause, and say "not covered" when that's the truth. We never file or submit a claim for the user.
6. **Neutral engine, cited fine print.** We recommend whatever card is truly best, and cite each benefit's Guide to Benefits section and version date.

---

## 4. Scope

Budget: ≈20–40 person-hours (ph) before Sat 12:30 PM plus ≈50–60 ph at the event, so 70–100 ph in total. P0 is ≈76 ph, which leaves **−6 to +24 ph** of slack. In the low case, the lean-P0 trims (§4.1) apply at once. About 30 ph of P0 needs a Mac (§15.1).

### 4.1 P0 (must ship)

| # | Item | Owner(s) | ph | Mac? |
|---|---|---|---|---|
| P0-1 | Spikes S0–S3 + S6: Action Button / Back Tap → Shortcut → `CheckCheckoutIntent` → Live Activity; snippet patterns A/B, button + reload; silent sound; capture rig; setup stopwatch | C | 7 | yes |
| P0-2 | Repo skeleton, contracts (JSON Schema + examples), `.env.example`, `THIRD_PARTY.md`, `.gitignore` | B | 2.5 | no |
| P0-3 | `data/cards.json`: 5 cards, ~10 merchants, item categories; protections with caps, citations and verification status | B 4 + D 1 (second check) | 5 | no |
| P0-4 | `fixtures/scenarios.json` (22) + `fixtures/coverage_cases.json` (13), written by D (who doesn't write the engine), committed before the engine merges | D | 4 | no |
| P0-5 | Engine (§7.2) + `POST /v1/check` + rules parser + pytest | B | 5 | no |
| P0-6 | LLM cart parser (schema-constrained JSON, no arithmetic) | A | 3 | no |
| P0-7 | On-device top-strip crop + OCR + checkout gate + redaction + os_signpost timings, inside the background intent | A | 5 | yes |
| P0-8 | `CheckResultSnippetIntent` + snippet views (Result / Saved / Sent) + Live Activity views (compact, expanded, minimal, limited, Lock Screen, stale) | C 4.5 + D 0.5 | 5 | yes |
| P0-9 | Intent → backend wiring (6.0 s timeout, last-4 fill, `CheckRecord` store) [C]; What-we-sent screen + replay keyed on merchant + total [A] | C 2.5 + A 2 | 4.5 | yes |
| P0-10 | App shell: wallet tiles + default + optional last 4 + seeded demo wallet; "Check a screenshot"; Purchases (planned/confirmed, "I bought this") | A | 4 | yes |
| P0-11 | `SavePurchaseIntent(checkId:)` → SwiftData `Purchase(status: planned)` | C | 2 | yes |
| P0-12 | Coverage: backend rules [B 2]; LLM cause classification [A 1]; HTML verdict template [D 2]; SwiftUI input + web view [A 1.5] | B, A, D | 6.5 | 1.5 h |
| P0-13 | Demo store, fictional "Northbay Electronics": static, deployed to HTTPS on Thursday [D 3.5]; also served by the backend with `/v1/store/pay` [B 0.5] | D, B | 4 | no |
| P0-14 | Visa Acceptance sandbox authorization on Place order; transaction ID on the confirmation page (gate G4) | B | 3 | no |
| P0-15 | Back Tap prompt + Set Up Back Tap screen (Shortcut link, Back Tap first, Try it now, optional Action Button card) | D | 1.5 | yes |
| P0-16 | 10–12 student interviews: card *products* held, mapped by us to protections; aggregate counts only | D | 2.5 | no |
| P0-17 | Metrics harness + runs + 10 clean runs | A 2.5, B 1, C 1, D 1 | 5.5 | partly |
| P0-18 | Devpost write-up + ≤2:00 video | D 4, C 1, B 0.5, A 0.5 | 6 | no |
| | **Total** (A 19.5 · B 18.5 · C 18 · D 20) | | **≈76** | ≈30 |

**Lean-P0 trims for the low case** (≈ −10 ph, decided in advance):
- P0-15 → P1; the demo phone is pre-bound.
- P0-16 → a 1-h hallway test with 5 students.
- P0-10 → seeded wallet only, no tile picker.
- P0-12 LLM cause classification → user-picked chips.
- P0-14 only if G4 passed before the event.
- P0-17 → 5 ph.
- Action Button card → Q&A mention only.

### 4.2 P1 (in this order; start only when the never-cut arc has run 5/5 clean)

| # | Item | ph |
|---|---|---|
| P1-1 | Renewed flip as a video beat + optional 20-s stage beat (the page is already in P0-13) | 0.5 |
| P1-2 | Claim packet PDF via the share sheet | 2 |
| P1-3 | Apple Pay path on the demo store (Stripe test mode + domain registration) + "In Apple Pay, swipe to this card"; only if teammates' real Wallet cards fit the story | 3 |
| P1-4 | Press on the order confirmation → confirmed purchase with order # and the Visa Acceptance transaction ID | 2.5 |
| P1-5 | "Skip the store's $X protection plan" line when an upsell is on screen | 1.5 |
| P1-6 | BNPL warning ("Paying with Afterpay drops this cover") | 1 |
| P1-7 | "Do you pay in full?" + balance guard ("Pay down your balance first") | 1 |
| P1-8 | Map the selected saved card on device + re-check "✓ Freedom ••1234 selected" | 2 |
| P1-9 | In-app Why sheet: cash rows, protection rows with caps, clause, sources; no expected-value math | 2 |
| P1-10 | Bounded island reminder after a Switch (`staleDate` 3 min; ended on the next press or app launch), only if S2 shows an acceptable stale state | 1 |
| P1-11 | One verified **non-Chase** protection card in the catalog | 2 |
| P1-12 | Settings-screenshot onboarding (on-device OCR of Settings › Wallet & Apple Pay) | 4 |
| P1-13 | VDBP sandbox call shown as the production path for benefit data (labeled test data) | 3 |
| P1-14 | Share Sheet trigger option (branched Shortcut) | 1 |
| P1-15 | Read-only footage of a real shopping app (masked on the phone) | 1 |
| P1-16 | "Other card" (not in the catalog): "We don't know this card's fine print yet" | 1 |

### 4.3 P2 (not planned for the event)
Visual Intelligence provider (unless promoted by §6.6) · on-device Foundation Models "Keep on device" mode · coverage widget · photo analysis in the coverage check · more cards · one-card "what your card covers" home · paste-a-link check · iOS 26 support · Action Button menu tip · push-based Live Activity end.

### 4.4 Cut
- **Rewards optimization:** money-leak audit; rotating categories, caps, activation, shared caps; FX/DCC/fee-trap guard; order splitting; expected-value formula and editable assumptions.
- **Engine and data:** on-device offline rules engine; Cybersource BIN lookup as separate work; 10 of 15 cards and ~30 of ~40 merchants.
- **Island:** push-to-start; separate Low-confidence and Offline states; a lingering island reminder in P0.
- **Copy:** "Visa-verified"; claim concierge fee.
- **Live demo:** onboarding speed-run; quiet montage.
- **Forms:** see §4.5.

### 4.5 Forms considered and rejected

| Alternative | Verdict | Why |
|---|---|---|
| Action Button as primary / demo trigger | Optional ("Prefer a button?") | People keep the Action Button on Silent and won't give that up (owner, Oct 16). It runs the same Shortcut. Back Tap's costs, accepted: buried in Accessibility settings (Set Up Back Tap shows the path); misfire and case-damping reports (anecdotal); no haptic feedback. |
| Action Button bound to an App Shortcut or Control that runs the intent directly | Rejected | Controls and App Shortcuts run an intent with no screen input, so the bare intent gets no screenshot. We do **not** register `CheckCheckoutIntent` in `AppShortcutsProvider`. |
| Screenshot → share sheet as primary | P1 option | 4–5 steps per checkout. Needs the Shortcut's input branch (§9.1). |
| iOS 27 screenshot automation | Rejected (owner, Oct 16) | Exists in iOS 27 ("runs when a screenshot is saved"), but it saves every checkout screenshot to Photos and runs on every screenshot (`docs/spikes.md`, G1 step). Not a G1 fallback. |
| Visual Intelligence | P2, gated fallback | Screenshot → highlight to search → choose our app; Apple decides the provider order; the result is a short row over a screenshot copy. CardPointers 8 already ships it. |
| Camera Control | Rejected | Camera / VI-camera only; doesn't read an in-app checkout. |
| Safari Web Extension | Rejected | Safari only, blind inside shopping apps, per-site permission. Kudos and CardPointers already ship one. |
| Share extension (app extension) | Rejected | 5–8 h; Live Activity from an extension unconfirmed. The branched Shortcut gives the same entry for ≈0 h. |
| Home / Lock Screen widget | P2 companion | No screen input. |
| Control Center / Lock Screen control | Rejected | No screen input, and opening Control Center covers the checkout. |
| Wallet / PassKit / FinanceKit | Rejected | FinanceKit needs a managed entitlement, an organization account and Apple review. No API to recommend or reorder Apple Pay cards. |
| App Clip | Rejected | App Intents and PhotoKit have no runtime function in App Clips. |
| Web app / PWA | Rejected | No system hook. |
| Location-triggered Live Activity / notification | Rejected | In-store only; CardPointers and MaxRewards already do it. |
| Shortcuts "App is opened" automation | Rejected | Sees the merchant, not the cart; fires on every open. |
| Siri / App Shortcut phrase | Rejected | No screen input; reads card choices aloud. |
| Notification banner as the result | Rejected | Apple's HIG: don't duplicate Live Activity updates with notifications; amounts would land in Notification Center. |
| Full-screen app result | Only for the in-app check | Takes the user out of the checkout. |
| ReplayKit always-on screen reading | Rejected | Breaks "only when you press". |

---

## 5. User flows

### 5.1 Onboarding (target ≤2:00 including the trigger; first result ≤60 s)
1. **Add my cards:** pick your cards from tiles and set your default. Last 4 is optional and stays on the phone. (P1: Settings-screenshot onboarding.)
2. **First result:** run the sample check on a built-in $1,499 laptop checkout → a real result with your own cards.
3. **Back Tap prompt** (skippable): a sheet, "Check any checkout with a double tap" / "Double-tap the back of your iPhone on any checkout, and Paywise tells you which card covers it.", with [Set Up Back Tap] / [Not Now]. **Set Up Back Tap:** get the Paywise Shortcut, then turn on Back Tap (Settings › Accessibility › Touch › Back Tap › Double Tap › Paywise). iOS has no link to that page, so the screen shows the path. A "Prefer a button?" card offers the Action Button instead (Settings › Action Button › Shortcut › Paywise) for people who don't use it for Silent. If setup was skipped, the prompt is offered once more after the 2nd in-app check; [Not Now] ends it.
4. **Try it now:** double-tap the back of the iPhone on a sample checkout inside Paywise. The first new check, whatever its answer, shows "Back Tap works ✓" and confirms setup; this also clears Shortcuts' first-run prompts. The store page in Safari is the fallback.

### 5.2 Payment moment (targets; unmeasured until spike S1)

**A. Switch on a saved-card checkout (S1).** The phone shows our store's checkout: "Pay with: Mastercard ••5678 [Change]", total $1,499.00.

| t (s) | Hand and eyes | Surface | What shows |
|---|---|---|---|
| 0.0 | Double-tap the back of the iPhone | — | — |
| ≤1.0 | Eyes at top | Island compact | Paywise glyph + progress ring (*Checking*, no alert) |
| 1.0–3.0 | — | On device | Crop the top strip, OCR, checkout gate, redaction (~0.4 s); upload, LLM parse, engine (~1.5–2 s); write `CheckRecord`; **end the Live Activity** |
| ≈3.0–3.5 | Eyes at top | **Snippet** (result) | §6.3 *Switch* |
| ≈3.5–4.5 | Reads line 1 (≈0.75 s), then line 2 | Snippet | — |
| ≈5 | Taps **[Paying with Freedom]** | `SavePurchaseIntent` runs; the snippet reloads in place | §6.3 *Saved* |
| ≈6 | Taps Done (or [What we sent], then Done) | Snippet gone; island empty | — |
| ≈7–10 | Store's Change → "Visa ••1234" → Place order | — | — |

**B. Keep, default already protects the item (S1-K).** Same as A, with the *Keep, protected* copy and no sound.

**C. Other Keep answers** (an $18 mug, or $180 Nike shoes with Apple Pay visible): press → *Checking* within 1.0 s → at ≈3 s the island **expands via an alerting update** (silent if gate G2 passes) with the *Keep* copy → `perform()` holds 4 s, ends the activity `.immediate`, and returns with no snippet. No tap needed.

**D. No checkout found** (pressed on a social feed): press → *Checking* → at ≈1.0–1.5 s the on-device gate finds no order total, so **nothing is uploaded** → the island expands with *No checkout* → held 4 s, then ended.

**E. Couldn't check:** the request times out at 6.0 s (≈7 s after the press). If demo replay is on and the replay key matches a fixture, that result is shown and logged as "replayed". Otherwise the island shows *Couldn't check*, held 4 s, then ended.

### 5.3 Paying (the instruction depends on the checkout)
- **Saved card in the store (primary):** "Change card to Visa ••1234, then place order."
- **Apple Pay (P1):** "In Apple Pay, swipe to this card."
- **Default is best:** "✓ Keep <card> ••<last4>" (+ "use Apple Pay" when the payment method changes the rate, S2).

### 5.4 After paying
- [Paying with …] in the snippet saves a **planned** purchase with its coverage dates.
- It becomes **confirmed** via "I bought this" in the app, or the first step of "Something happened".
- P1: press on the order confirmation to confirm it and attach the order # and transaction ID.
- Never say "warranty registered": card benefits need no registration; we save evidence and dates.

### 5.5 "Can I claim?" (P0; the demo climax)

**Input screen (SwiftUI):**
1. "Did you pay with Freedom ••1234 on Oct 17?" [Yes] [No, another card]. Yes sets `status = confirmed`.
2. "Maker's warranty: [1 year] [2 years] [Don't know]". "Don't know" uses 12 months and labels the result "assumed".
3. "What happened?" as free text, plus cause chips (Stopped working / Dropped or damaged / Stolen / Lost). The LLM pre-selects a chip; the user confirms.

**Verdict:** rendered by the backend as HTML (`POST /v1/coverage?format=html`) in an in-app web view. The checks run in order: still under the maker's warranty → card extended warranty → purchase protection (theft/damage, 120 days) → not covered.

| Verdict | Example (laptop bought Oct 17, 2026 with Freedom Unlimited) | Screen copy |
|---|---|---|
| may_be_eligible | "Lines across the screen. Never dropped." at 14 months | **May be eligible: Extended warranty (Freedom Unlimited).** The maker's 1-year warranty ended Oct 17, 2027; the extra year runs to Oct 17, 2028. **Notify by {incident date + 90 days}; send documents by {incident date + 120 days}, or as soon as reasonably possible** (Chase deadlines, verified in G5). Clause: {document} · {section} · version {date}. Checklist: itemized receipt · card statement showing the purchase · original warranty · repair estimate. You file it yourself at {administrator url}. |
| may_be_eligible, capped | "Stolen from my bag" at day 30 | **May be eligible: Purchase protection, up to $500 of the $1,499.** Theft is covered within 120 days (to Feb 14, 2027). The checklist adds a police report (made within 48 hours if you can); for porch theft, it adds "claim with the carrier or store first". |
| not_covered | "Cracked it when I dropped it" at 14 months | **Not covered.** Damage was covered for 120 days (to Feb 14, 2027). The extended warranty covers failures, not drops. |
| not_covered, maker route | Stops working at month 8 | **Not covered by your card yet: it's still under the maker's warranty.** Contact the manufacturer first. The card's extra year starts Oct 17, 2027. |
| need_more_info | "Left them on the bus" (earbuds, week 6) | **Need more info.** Theft and "involuntary and accidental parting" may be covered within 120 days; simply losing something may not be. See the cited clause. |

**Payout cap:** the lesser of the repair cost, the replacement cost, the amount charged to the card, and the benefit's cap ($500 per item for purchase protection, $10,000 per item for extended warranty). With `paidWith: card_partial`, the cap is the part paid on the card.

**New York:** purchase protection lasts 90 days for New York residents, not 120. The engine doesn't know the user's state, so the claim screen and the Why sheet say "120 days (90 in NY)". Asking for the state once in onboarding is P1.

Footer on every verdict: "Only the benefit administrator decides claims. Paywise never files for you." Photo analysis is P2; the claim PDF is P1.

---

## 6. Snippet, Dynamic Island & Live Activity

### 6.1 Constraints (Apple HIG / ActivityKit / App Intents)
- **Sizes:** compact 52.33×36.67 pt (393-pt-wide screens) / 62.33×36.67 pt (430-pt); minimal 36.67–45×36.67 pt; expanded and Lock Screen 371 or 408 × 84–160 pt; limited width 28-pt circle; landscape on iOS 27.
- **When the expanded view shows:** only on an alerting update or a long-press, and only "briefly"; the duration is undocumented. A quiet compact-only update never shows its text.
- **Lifetime and payload:** a Live Activity lives up to 8 h unless the app or the person ends it, so the intent always ends it. Data is ≤4 KB. Oversized art can make the start fail.
- **Taps:** tapping the island opens the app, so the island never carries information that needs a tap.
- **Snippets:** they appear at the top of the screen over other content and stay until confirmed, cancelled or swiped away. Buttons must run an App Intent. Interactive snippets need `ShowsSnippetIntent` + a `SnippetIntent`, which the system may re-perform, so it reads its data from a shared store.
- **HIG:** one Live Activity at a time; one interactive element; no sensitive info on the Lock Screen; don't duplicate updates with notifications.

### 6.2 Rules for every result
- **The 3-second rule:** line 1 is the verdict, at most 4 words plus `••last4`, next to the card art, starting with a verb. Lines 2 and 3 are ≤44 characters each. The instruction line is ≤48 characters, in secondary style. At most 2 numbers in lines 1–3 (not counting last 4).
- **Content:** never blend cash and protection into one number. Always state the protection cap when it's verified.
- **Cost line:** compares against the wallet's cash-best card. If the default ties for cash-best, it names the default. If the pick is also cash-best, it says "Also earns the most cash back here".
- **Island:** before each `Activity.request`, end every existing Paywise activity with `.immediate`. Every request and update sets `staleDate = now + 2 min`. **The intent always ends its activity before `perform()` returns.** On app launch, end any leftover activities.
- **Timing:** the backend request times out at **6.0 s**, and *Couldn't check* shows at once. The intent never runs past 30 s.

### 6.3 Copy and behaviour for every state

The phone fills `{last4:<cardId>}` from the wallet; with no stored last 4 it drops "••{…}". Card names come from `shortName` in `data/cards.json`. `{ppCap}` is the verified per-item (or per-claim) limit. If it isn't verified, line 2 reads "Adds a warranty year + theft cover".

| State / variant | When | Surface | Line 1 | Line 2 | Line 3 / instruction | Buttons | Sound | Ends |
|---|---|---|---|---|---|---|---|---|
| **Checking** | Intent starts | Island compact (long-press: expanded) | (expanded) Reading this screen… | Only the order summary leaves your phone | — | — | none | Replaced by the result; the intent ends it in every path |
| **Switch, protection** | Rule P | **Result snippet** | Use Freedom ••{last4} | Adds a warranty year + {ppCap} theft cover | $7.49 less cash back than Active Cash · *Change card to Visa ••{last4}, then place order* | [Paying with Freedom] + system Done | snippet presentation only | Done or swipe; the Live Activity is ended before the snippet appears |
| Switch, protection, pick also cash-best | Rule P | Same | Use Freedom ••{last4} | Adds a warranty year + {ppCap} theft cover | Also earns the most cash back here · *instruction* | Same | Same | Same |
| **Switch, cash** | Rule C | Same | Use Active Cash ••{last4} | $10.99 more cash back than Apple Card | Eligibility note if any ("Renewed, no warranty: no card covers it") · *Change card to Visa ••{last4}, then place order* | [Paying with Active Cash] + Done | Same | Same |
| Switch, Apple Pay path (P1) | Apple Pay button visible | Same | Use Freedom ••{last4} | (gain) | (cost) · *In Apple Pay, swipe to this card* | Same | Same | Same |
| **Keep, protected** | Guard G, or default protects | **Result snippet** | ✓ Keep Freedom ••{last4} | Adds a warranty year + {ppCap} theft cover | Save it so you can claim later | [Paying with Freedom] + Done | snippet presentation only | Same as Switch |
| **Saved** (reload) | `SavePurchaseIntent` done | Same snippet | ✓ Saved: Aero 14 · $1,499 | Theft & damage cover up to $500 to Feb 14, 2027 | Extra warranty year to Oct 17, 2028* · *If the maker's warranty is 1 year. Planned: confirm after you pay.* | [What we sent] + Done | none | Done or swipe |
| **Sent** (reload) | [What we sent] | Same snippet | What left your iPhone | The exact redacted text sent (scrolls; monospaced) | Cards sent as product names only. No screenshot, no last 4. | Done | none | Done or swipe |
| **Keep, default best** | No rule fires | Island, expanded via alert | ✓ Keep Apple Card ••{last4} | Best of your 3 cards here | — | — | silent `.named` (G2), else `.default` | Held 4 s, then `.immediate` |
| Keep, under threshold | Cash gain below threshold | Same | ✓ Keep Apple Card ••{last4} | Switching gains under ${threshold} here | — | — | Same | Same |
| Keep, method (S2) | Default earns more via Apple Pay | Same | ✓ Apple Card: use Apple Pay | 3% ($5.40) with Apple Pay vs 1% typed | — | — | Same | Same |
| Keep, items unreadable | Merchant + total read, items not | Same | ✓ Keep Apple Card ••{last4} | Couldn't read the items, so no switch | — | — | Same | Same |
| **No checkout, on device** | On-device gate fails (nothing sent) | Island, alert | No checkout total found | Nothing left your phone | Scroll to the total and press again | — | Same | Held 4 s, then `.immediate` |
| No checkout, from backend | Text was sent; screen is not a checkout or unreadable | Same | No checkout total found | Scroll to the total and press again | — | — | Same | Same |
| No checkout, already paid | Order confirmation screen | Same | Already paid? | Press on the checkout, before you pay | — | — | Same | Same |
| **Couldn't check** | 6.0 s timeout, no network or 5xx | Same | Couldn't check this time | No connection · press again *(or: Took too long · press again)* | — | — | Same | Held 4 s, then `.immediate` |
| Not set up | Intent ran with no image | Static snippet (`ShowsSnippetView`) | Use the Paywise shortcut | It reads the screen for you | Set it up in the Paywise app | Done | none | Done |
| Switch fallback (G2 fails) | Snippet doesn't appear | Island, alert | Lines 1–3 as Switch | | | none (save later with "I bought this") | `.default` | Held 8 s, then `.immediate` |
| Receipt saved (P1) | Press on an order confirmation | Island, alert | ✓ Receipt saved | Aero 14 · Freedom ••{last4} | Purchase confirmed | — | silent | Held 4 s |
| Balance guard (P1) | User said they carry a balance | Island, alert | Pay down your balance first | Interest costs more than any reward | — | — | silent | Held 4 s |

**Where S1's numbers come from:** Active Cash 2% = $29.98, Freedom 1.5% = $22.49, Apple Card typed 1% = $14.99. Each card's cash is rounded to cents (half-up) before subtracting, which gives −$7.49 vs Active Cash and +$7.50 vs the default. Renewed ($1,099): Active Cash $21.98 vs Apple Card typed $10.99. Nike ($180): 3% = $5.40. Purchase protection runs 120 days from Oct 17, 2026 to Feb 14, 2027. The warranty year runs to Oct 17, 2028, assuming a 12-month maker warranty. The comprehension test (§13) checks that users don't read the cost line as "earns less than my card".

### 6.4 Presentations and accessibility
- **Minimal** (another app's Live Activity is running): Paywise glyph during Checking, ✓ for Keep, ⚠ for errors.
- **Limited width / landscape** (28-pt circle): leading view only.
- **Lock Screen:** "Paywise is checking" / "Paywise checked this screen". No card, no amount, no store. Hide content when Always-On (`isLuminanceReduced`).
- **Stale** (`isStale`): bare Paywise glyph.
- **Card art:** generic team-made card shapes, not issuer artwork, exported @3x at the exact compact and expanded sizes and no larger. The snippet uses the same art.
- **VoiceOver (Switch):** "Use Freedom, card ending 1 2 3 4. Adds a warranty year and up to 500 dollars of theft cover. 7 dollars 49 less cash back than Active Cash."
- **Color** is never the only cue (art + digits + ✓ / ⚠ / shield). Dynamic Type drops secondary lines first.
- **Phones without a Dynamic Island:** the Lock Screen presentation shows as a banner on alert updates. No separate notification for the same update.

### 6.5 Explaining Apple's sheet
"Apple made switching cards one swipe and shows rewards and balances for eligible cards. It doesn't tell you which card covers this purchase, or help when it breaks."

### 6.6 Fallbacks decided in advance (applied when a gate in §14.2 fails)
- **G1 fails** (Take Screenshot from Back Tap / the Action Button doesn't capture the app underneath in ≥9/10 runs):
  1. That evening, add a Wait before Take Screenshot in the Shortcut and re-run the presses.
  2. If that fails, use the branched Shortcut in the Share Sheet plus the in-app check; the demo opens on "screenshot → share → answer".
  3. Only if both fail: Visual Intelligence moves from P2 to P1.

  Never the iOS 27 screenshot automation: the owner ruled it out on Oct 16 (§4.5).
- **G2 fails on appearance** (the snippet doesn't appear over Safari and ≥1 third-party app in ≥9/10 Back Tap runs): Switch and Keep-protected become alerting island updates with the `.default` sound, held 8 s. Users save later with "I bought this".
- **G2 fails on the button** ([Paying with …] doesn't save and reload in ≥9/10): try Pattern B (`requestConfirmation` with a custom verb, §15.5). If that fails too, show a static snippet and save via "I bought this".
- **G2 fails on sound** (`.named("silent.caf")` makes a sound or doesn't expand): use `.default` for every alert.
- **The Live Activity can't start from the intent** (`visibility` or `unsupportedTarget` error): every state uses snippets; *Checking* is skipped, and the Shortcut's own running indicator is the only progress cue.

---

## 7. Recommendation and coverage engine

### 7.1 Inputs
The `/v1/check` request (§15.5): redacted OCR text, wallet card IDs with the default flag, and the client date. The LLM turns the text into a Cart (merchant, items with category / condition / seller, total, visible payment options, upsells, BNPL). The engine never sees last 4. Card rules come from `data/cards.json` (§8, §15.3).

### 7.2 Rules (v1; `backend/app/engine.py`, thresholds in `backend/app/policy.py`)

**Thresholds:** `PROTECTION_MIN_ITEM_USD = 100` · `CASH_SWITCH_MIN_USD = {apple_pay: 3, saved_card: 5, card_form: 5, unknown: 5}` · `ITEM_CONFIDENCE_MIN = 0.8`.

**Rules, applied in order:**
0. **Screen type.** If the screen isn't a checkout, return `no_checkout`: not_checkout → reason `not_checkout`; unreadable → `unreadable`; order_confirmation → `already_paid`.
1. **Cash per card.** Use `Decimal` throughout.
   - Rate precedence (offers decision D4): the **best applicable rate wins**. An earn rule applies when its payment method and its merchant or category match, its `window` contains `clientDate`, and one of its `channels` is one a phone checkout can be (online / in_app / any; never in_store). The base rate is always a candidate. Ties go to the more specific rule (merchant > category > payment method > base), then file order. On every merchant and category the catalog can produce this equals the old merchant > category > base tiers (`test_earn_precedence.py`); it differs only where a narrower rule pays less, and then it pays more.
   - Payment-method requirements apply. The path is `apple_pay` if an Apple Pay button is visible (every wallet card is assumed to be in Wallet). Otherwise it's the saved-card or card-form path, and cards earn their "card" rates.
   - Round each card's cash to cents (half-up) before any subtraction.
   - `cashBest` is the card with the most cash; ties go to the default, then to wallet order.
2. **Items unreadable.** If items are missing or `confidence.items < ITEM_CONFIDENCE_MIN` → `keep / items_unreadable`. No protection switch and no cash switch.
3. **Eligible protections** per card. Only purchase_protection and extended_warranty count, and only when:
   - the item condition is allowed (v1: new only);
   - the item isn't a gift card or a service plan;
   - the payment requirement is met;
   - the category isn't excluded;
   - extended warranty: the category is `warrantyRelevant`; purchase protection: the category is `theftDamageRelevant`.

   An item **qualifies** if its price ≥ `PROTECTION_MIN_ITEM_USD` and its category is relevant to that protection type.
4. **Rule P (protection gain).** For a qualifying item, find a card that has an eligible protection type the default lacks **and** keeps every eligible protection type the default has. Pick the card with the most such types, breaking ties by cash → `switch / protection`.
5. **Guard G (protection loss).** For a qualifying item, if the default has an eligible protection type that `cashBest` lacks → `keep / already_protected`. The cash gain isn't shown at checkout (P1 Why sheet).
6. **Rule C (cash).** If `cashBest ≠ default` and its gain over the default ≥ `CASH_SWITCH_MIN_USD[path]` → `switch / cash`.
7. **Rule M (method).** If the default earns more via Apple Pay than typed, and an Apple Pay button is visible → `keep / method`.
8. **Keep.** If the default has an eligible protection on a qualifying item → `keep / already_protected` (presentation: snippet). Else if `cashBest ≠ default` → `keep / below_threshold`. Else → `keep / default_best`.
9. **Offers are applied on the phone (D1–D4).** Anything capped, activated, targeted, tied to account age or to an issuer event is an `offers[]` entry in `data/cards.json` (§15.3), never an earn rule, and the user's answers about it never leave the phone (the `/v1/check` request is unchanged and rejects extra fields). The response adds a public `offerContext` (the same for every user with this cart: amount, merchant, rule category, path, method, each card's public rate, the cash threshold, `allowedCashPicks`, a purchase draft per allowed card, `deviceMayOverride`). The phone's deterministic `OfferResolver` (Decimal) then:
   - adds the user's answered `device` offers to each card's cash. Rate offers fill **best rate first**: each earns on up to its cap left (never below 0), then the next, then the card's public rate. An unknown cap use counts the whole cap at medium confidence, and copy states no dollar figure;
   - may move a **cash** decision (switch/cash, keep/default_best, keep/below_threshold, keep/method) to another card in `allowedCashPicks` (cards that keep every protection the default has), with the same thresholds and device copy that names the offer ("With your Q4 5%");
   - **never** changes switch/protection, keep/already_protected, items_unreadable, no_checkout or an error;
   - leaves `hint` offers (links, portals, memberships, thresholds) out of cash.

   **Not in v1:** expected value, FX, order splitting, balance logic, and capturing personal offers from screenshots (§15.9).

### 7.3 Where AI is used (and why it isn't a lookup table)
1. Reading arbitrary checkout screens into a Cart.
2. Eligibility from the screen: Renewed / refurbished (P0); third-party seller, gift card, protection plan in the cart, BNPL (P1). Demo beat: the same laptop listed "Renewed · no warranty" flips the pick and says why ("Renewed, no warranty: no card covers it"). Chase does cover refurbished items that come with a warranty (G5), so the demo listing must say "no warranty". For real carts (P1), add a condition value such as `refurbished_with_warranty` so the engine doesn't wrongly refuse cover.
3. Turning Guide to Benefits text into cited, structured rules **before the event (gate G5)**, reviewed by a human.
4. Coverage: classifying the incident's cause (the user confirms). The verdict comes from date and window rules in code.

The LLM never does arithmetic. Money and date math happen in code.

### 7.4 Output
The `/v1/check` response (§15.5): `decision` (kind, reason, presentation, recommended card, cash by card, protections gained/lost with limits, copy), `purchaseDraft` with coverage dates, sources with version dates, and the public `offerContext` the phone's offer resolver uses (§7.2 rule 9).

---

## 8. Data

### 8.1 Card set (v1: 5 cards)

| id | shortName | Network | Earn | Protections | Status |
|---|---|---|---|---|---|
| `apple-card` | Apple Card | Mastercard | 3% on purchases directly from Apple (any method); 3% via Apple Pay at select merchants (Nike, Walgreens, …); 2% via Apple Pay; 1% with the titanium card or virtual card number | None (no purchase protection or extended warranty) | Verified 2026-10-14 (`docs/benefits-verification.md`) |
| `wf-active-cash` | Active Cash | Visa Signature | 2% flat | Cell phone protection only ($600/claim, $25 deductible, 2 claims and $1,200 per 12 months). **No** extended warranty or purchase protection (WF Guide, in effect 09/15/2025) | Verified |
| `chase-freedom-unlimited` | Freedom | Visa | 1.5% base; 3% dining and drugstores (P2); 5% Chase Travel (not modeled) | Purchase protection: 120 days (90 in NY); **$500 per item**, $50,000 per account; theft, damage, involuntary and accidental parting. Extended warranty: +1 yr on U.S. manufacturer warranties if all warranties total ≤3 yr; ≤4 yr from purchase; $10,000 per item, $50,000 per account. Charging all or part of the price (or using rewards) qualifies. Refurbished items with a warranty are covered. **Notify within 90 days** of the loss or failure; **documents within 120 days** | Verified (Chase Guide BGC11366, in effect 10/1/24) |
| `chase-freedom-rise` | Freedom Rise | Visa | 1.5% flat | Same guide and terms as Freedom Unlimited | Verified |
| `discover-it-student-cash-back` | Discover | Discover | 1% base (5% rotating with activation not modeled) | None (removed Feb 28, 2018, per secondary sources) | Earn and absence verified; removal date partial |

Networks matter: Apple Card is Mastercard, so its perks aren't Visa benefits. P1: one verified non-Chase protection card. P2: more cards (Savor Student, Double Cash, …) after verification.

### 8.2 Card catalog fields
Everything lives in **one data file**, `data/cards.json`: cards, earn rules, protections with limits and citations, merchants, item categories. The field list and schema are in §15.3. **Display rule:** the copy and the demo state a value as fact only when its `verification.status` is `verified`. The engine may use `partial` values, but responses then carry `confidence: "medium"` and drop the cap from the copy. Per-user data (last 4, default card) stays on the device only.

### 8.3 Merchants (v1: ~10)
- Demo: `northbay-electronics` (electronics); `stride-athletics` (apparel, P1).
- `nike` (apparel; Apple Card 3% via Apple Pay).
- `amazon` (general; "no Apple Pay" is weakly sourced, (u)).
- `target`, `best-buy`, `walgreens` (pharmacy), `doordash` (dining), `apple`.
- `walmart` (Apple Pay in U.S. stores since Aug 24, 2026; online/in-app (u)).

### 8.4 Sources & licenses
- Seed earn rates from `novus-tech-tw/CardWise` `cards.json` (MIT) — data only, with the notice in `THIRD_PARTY.md`. Hand-verify every demo card against issuer pages.
- Benefits: public Guide to Benefits PDFs, dated and cited. VDBP sandbox is P1 and returns test data only.
- MCC reference: `greggles/mcc-codes` (Unlicense).

---

## 9. Architecture

### 9.1 iOS app (SwiftUI, iOS 27 only)
- **Identifiers (decided Oct 15, 2026):** app name **Paywise**; bundle ID `com.azealoo.paywise`; App Group `group.com.azealoo.paywise`. Extension bundle IDs go under the app's ID (for example `com.azealoo.paywise.widgets`).
- **The "Paywise" Shortcut:** if it has input (shared from the Share Sheet) → Check Checkout(input); otherwise → Take Screenshot → Check Checkout. Bound to Back Tap (Double Tap), and optionally to the Action Button.
- **`CheckCheckoutIntent`** (`AppIntent` + `LiveActivityIntent`, `supportedModes = [.background]`, `IntentFile` image parameter):
  1. End any Paywise activity.
  2. Start *Checking*.
  3. Crop the top strip, run OCR, the checkout gate and redaction.
  4. POST `/v1/check` (6.0 s timeout; replay lookup on failure).
  5. Write a `CheckRecord`.
  6. Return an interactive snippet (Switch / Keep-protected) after ending the activity, or show an alerting island update, hold 4 s, end it, and return.

  Details: §15.5.
- **Other intents:** `CheckResultSnippetIntent`, `SavePurchaseIntent`, `ShowSentIntent` (§15.5).
- **Target and config:** intents live in the main app target only (`allowedExecutionTargets`). `NSSupportsLiveActivities = YES`; check `areActivitiesEnabled` in onboarding. One activity at a time. Do **not** register `CheckCheckoutIntent` in `AppShortcutsProvider`.
- **Widget extension:** Live Activity views per §6.4. Card art is bundled in the asset catalog; send a `cardId`, not an image.
- **App screens:** onboarding, wallet, Purchases, What we sent, claim input + HTML verdict. The Why sheet and claim PDF are P1.
- **Storage:** wallet, `CheckRecord`s (pruned after 24 h) and purchases live on the device (App Group `group.com.azealoo.paywise` + SwiftData). A purchase is sent to the backend only when the user runs a coverage check.

### 9.2 Backend (FastAPI)
- `POST /v1/check`: redacted text + card IDs → LLM (Claude Haiku 5.5 `claude-haiku-5-5` via the Anthropic API, schema-constrained JSON; Claude Sonnet 5.5 is the one-line fallback; `docs/llm-provider.md`) or the rules parser → engine → result. Before locking in, measure ~20 parses: pass bar p50 ≤1.5 s, p90 ≤3 s **(u: unmeasured)**. The server answers or fails by ~4.5 s (override the SDK's retries and timeout), then falls back to the rules parser.
- `POST /v1/coverage` (`?format=json|html`): purchase + incident → verdict, citations, checklist, deadline.
- `POST /v1/store/pay`: the demo store's payment (Visa Acceptance sandbox or mock).
- No request-body logging. Returns 400 `privacy_rejected` for any body with a run of ≥12 digits. API keys only on the server. Per-device rate limit and budget cap.
- **Hosting:** Render (`docs/hosting.md`). From Friday, one paid **Starter** web service (about $7/month **(u)**) serves `/v1/*` and `/store/`. Never the Free web service: it sleeps after 15 minutes and takes about a minute to wake, past the phone's 6.0 s timeout. Secrets go in the dashboard as environment variables.

### 9.3 Demo store (mobile web)
- Fictional "Northbay Electronics": static HTML with laptop, renewed laptop (listed "Renewed · no warranty", §7.3), earbuds and mug checkouts and a saved-card selector. Deployed to HTTPS on Thursday as a free Render Static Site, later served by the backend at `/store/`.
- Payment: Visa Acceptance sandbox (P0, gated) or a mock.
- Apple Pay via Stripe test mode is P1 (needs a real card in Wallet and a registered domain).

### 9.4 Latency budget (unmeasured; these are targets until spike S1 measures them)
Press + Shortcut start + screenshot + intent launch ~0.5–1.0 s · crop + OCR + redaction ~0.4 s · network + LLM ~1.5 s · engine + snippet/island ~0.2 s. Targets: press → *Checking* ≤1.0 s; press → result p50 ≤3.5 s, p90 ≤5 s. Say "about 3 seconds" only if the measured p50 is ≤3.0 s. Replay is keyed on merchant + total (§15.7 step 10).

---

## 10. Privacy & safety

- **What leaves the phone:** only redacted order-summary text (e.g. "Northbay Electronics · Aero 14 Laptop (New) · $1,499.00 · Mastercard [CARD]") and card product IDs. Never the screenshot, never last 4. The status-bar strip is cropped before reading.
- **"What we sent":** shows the exact payload for every check, in the app and inside the Saved snippet.
- **Consent screen:** names the AI provider and its retention. A "Keep on device" mode is P2. Copy:
  > Paywise sends only a redacted order summary, such as "Northbay Electronics, Aero 14 Laptop (New), $1,499.00, Mastercard", to Anthropic's Claude API so it can read the items and prices. Card numbers, names and addresses are removed on your iPhone first, and your screenshot never leaves your phone. Anthropic doesn't use this text to train its models. It deletes API inputs and outputs within 30 days, and can keep them longer, up to 2 years, if its safety systems flag them. Tap "What we sent" any time to see exactly what was sent.
- **Retention copy:** "Screenshots are processed in memory and never saved. Purchases you save stay until you delete them. Our AI provider, Anthropic, may keep the redacted order text for up to 30 days, and longer if its safety systems flag it. It isn't used for model training." (Anthropic API: not used for training; 30-day default deletion; up to 2 years if flagged.) **(u)** Before shipping this copy, re-read Anthropic's commercial data retention article to confirm 30 days still holds (so far seen only in a search snippet). Also confirm the Console org is on the standard commercial API terms with no ZDR or other agreement that changes the wording (`docs/llm-provider.md`).
- **Accidental presses:** an on-device checkout test runs first, and nothing is uploaded from non-checkout screens.
- **Lock Screen:** no amounts, cards or store names.
- **Claims:** free; uses only facts the user confirms; the user submits. Wording is "may be eligible", never "you're covered", "filed", "guaranteed" or "best card".
- **Disclaimer:** "Estimates only, not financial, legal or insurance advice. Values use public card terms (last checked [date]) and the assumptions shown. Paywise can't see your caps, activations or balances. Warranty and purchase protection are insurance benefits with limits and exclusions; only your card's benefit administrator decides claims. If you carry a balance, interest will likely cost more than any reward. Not affiliated with or paid by any issuer."
- **Test data:** real-app screenshots used for accuracy testing never live in the repo (§15.2).
- **Onboarding privacy copy:**
  > We only look when you press. Never in the background.
  > Card numbers, names and addresses are removed on your iPhone first.
  > Only that redacted order summary is sent for analysis; our AI provider (Anthropic) deletes it within 30 days and doesn't train on it.
- **Judge answer — "Aren't you sending my payment screen to an AI company?"** "No. The screenshot never leaves your phone. On-device OCR removes anything that identifies you; only something like 'Northbay Electronics, $1,499, 1 laptop' goes to Anthropic's Claude API, which doesn't train on it and deletes it within 30 days. Tap 'What we sent' to see it." *(Say this only if on-device redaction is actually built.)*

---

## 11. Visa track fit

### 11.0 Published criteria
- **Track:** "Visa: Reimagine Shopping", $5,000 cash, 1 winner (Devpost overview, checked 2026-10-14; `docs/dubhacks-2026-rules.md`).
- **'26 Visa prompt (verbatim, [dh26.dubhacks.co Tracks](https://dh26.dubhacks.co/#tracks), checked 2026-10-14):**
  > Use generative AI to craft smarter, effortless commerce experiences. Design and build a commerce experience that makes shopping more intuitive and personalized, transforming one or more stages of the journey: discovery, decision-making, personalization, checkout, payments, loyalty and rewards, or post-purchase.
- **'26 rubric (event-wide; Devpost overview):** Functionality 30%, Track Applicability 30%, Design 20%, Creativity 20%. No Visa-specific rubric is published. The point breakdowns are in the '26 Hacker Guide, which we couldn't read **(u)**.
- **Generative AI is required by the prompt:** keep the LLM path (cart parsing, cause classification) in the demo, not only `PARSER_MODE=rules`.
- **Title track:** Visa is a sponsored side track, so the team also needs exactly one title track. Cook Smarter is the suggested fit; the team confirms.

### 11.1 Commerce journey covered
Decision (which card covers this) → checkout (change card / pay) → post-purchase (saved purchase, coverage check). Generative AI does the reading, the eligibility judgment and the cause classification.

### 11.2 Visa APIs
- **G4 failed (Oct 16), so this P0 is off:** the sandbox merchant's processor (`fdiglobal`) has no USD outlet or terminal IDs, and only Cybersource support can add them (`docs/spikes.md`, `docs/overnight-report.md`). The demo runs on `PAY_MODE=mock` and makes no Visa-API claim. The client stays in the code (`PAY_MODE=visa_acceptance`) in case the account is fixed.
- **Planned P0 (gated by G4):** a Visa Acceptance (Cybersource) sandbox authorization runs the demo merchant's payment; the confirmation shows the transaction ID. Sign-up, keys, test cards and the stall plan are in `docs/visa-sandbox.md`. It's an authorization only (`capture: false`, no money moves). Hard stop: if the account can't log in and make a key by Fri Oct 16, 12 PM, set `PAY_MODE=mock` and remove every Visa-API claim.
- **P1:** the Visa Digital Benefits Platform (VDBP) sandbox, shown as the production path for benefit data (test data, labeled).
- Skip the VDBP Card Account endpoints (they need the full card number and PCI scope).
- Never say "Visa-verified". Devpost line (mock payment): "The demo store's payment is a mock; no money moves. In production, benefit data would come from Visa's benefits APIs (VDBP; sandbox shown if P1 ships)."

### 11.3 Neutrality framing
The engine recommends whatever is truly best. The demo's winning card is a Visa (Freedom Unlimited vs Active Cash, both Visa; tiers to re-verify): "same network, different fine print." The protections are the issuer's: Freedom Unlimited's come from Chase's Guide to Benefits (`docs/benefits-verification.md`), so we never credit them to Visa.

### 11.4 Why Visa benefits
Benefits get used (engagement), fewer misfiled claims, and an inclusive story: free for students, no paid ranking.

### 11.5 Roadmap line only
The same engine could pick the credential for AI shopping agents (Visa Intelligent Commerce) or set rules for Visa Flexible Credential. Not built.

---

## 12. Demo & video

### 12.1 Live table demo (≤3:00; planned 2:20 + optional 0:20 + buffer)
**Setup:**
- The phone is mirrored to a laptop facing the judges (rig chosen at gate G3).
- Seeded wallet, all with fake last 4: Apple Card ••5678 (default), Active Cash ••4321, Freedom Unlimited ••1234.
- Safari tab 1: laptop checkout. Tab 2: renewed-laptop checkout.

| Time | Beat | On screen | Real / simulated |
|---|---|---|---|
| 0:00–0:15 | Hook: "This $1,499 laptop: cash back says Active Cash. The fine print says something else." Hand the judge the phone. | Northbay Electronics checkout, "Pay with Mastercard ••5678 [Change]" | Store is ours (fictional) |
| 0:15–0:30 | Coach: "Double-tap the back of the phone." **Judge double-taps.** | *Checking* → snippet: Use Freedom ••1234 / Adds a warranty year + $500 theft cover / $7.49 less cash back than Active Cash | Real: screenshot, on-device OCR + redaction, cloud parse, engine |
| 0:30–0:45 | Judge taps **[Paying with Freedom]** → Saved. Presenter taps **[What we sent]**: "That's all that left the phone." Done. | Saved: dates + "up to $500". Sent: the redacted summary | Real |
| 0:45–1:05 | Presenter: Change → Visa ••1234 → Place order | "Approved · Mock payment, no money moved · txn MOCK-…" | Simulated: mock payment (`PAY_MODE=mock`; G4 failed); fake saved card; no money moves |
| 1:05–1:35 | "14 months later" (said aloud as staged): Purchases → Aero 14 (Planned) → Something happened → paid with Freedom? Yes → maker's warranty 1 year → "Lines across the screen. Never dropped." | **May be eligible: Extended warranty** + clause + version date + checklist + notify-by | Date override simulated; verdict is real engine output |
| 1:35–1:50 | Contrast: "Cracked when I dropped it" | **Not covered**: damage was covered for 120 days only | Real |
| 1:50–2:05 | Why Visa / why us: "Card benefits are how cards like this Visa differ, yet cardholders use about 2 of them (J.D. Power 2026). We show them at checkout and turn them into a claim. Free for students, no paid ranking." | One slide or app screen | — |
| 2:05–2:20 | Close: tagline + one numbers line (measured p50, scenarios including misses, interview stat) | Tagline | Measured |
| 2:20–2:40 (optional) | **Renewed flip**, only if rehearsals finish by 2:20: tab 2, press | "Use Active Cash ••4321 / $10.99 more cash back than Apple Card / Renewed, no warranty: no card covers it" | Real |
| → 3:00 | Buffer / Q&A | — | — |

**Q&A backup cards, in order:**
1. Renewed flip (if not shown).
2. Keep with Apple Pay ("✓ Apple Card: use Apple Pay").
3. No checkout found ("Nothing left your phone").
4. Prefer a button? The Action Button runs the same Shortcut.
5. iOS 27 Apple Pay sheet and CardPointers 8 comparison.
6. How the catalog generalizes: per-card protection fields + cited sources; a non-Chase protection card is the next to verify.
7. Read-only real-app footage (P1).
8. Interview numbers.
9. What's simulated.

### 12.2 Video (≤2:00, captions burned in; one continuous real-time take for 0:08–0:45)

| Time | Beat |
|---|---|
| 0:00 | Hook |
| 0:08 | Back Tap double tap (hand in picture-in-picture, timer on screen) → snippet |
| 0:20 | [Paying with Freedom] → Saved → [What we sent] |
| 0:32 | Change card → Place order → mock approval ("Mock payment, no money moved") |
| 0:45 | "14 months later" → may be eligible + clause |
| 1:05 | Drop → not covered |
| 1:15 | Renewed flip |
| 1:30 | Why Visa + free / no paid ranking |
| 1:45 | Real-vs-simulated card + tagline |

First footage at 7:30 PM Sat; final takes by 3:00 AM Sun.

### 12.3 Real vs simulated (say it on Devpost and in the video)
- **Real:** the Back Tap double tap and Shortcut screenshot; on-device crop, OCR and redaction; the cloud cart parse and engine; the snippet and island; the saved (planned) purchase; the coverage verdict from stored clause data.
- **Simulated or staged:** the store (a fictional merchant we built); the payment (`PAY_MODE=mock`: the confirmation says "Mock payment, no money moved"; the Visa Acceptance sandbox, gate G4, failed on Cybersource's side, so we make no Visa-API claim); the cards (fake saved cards with fake last 4; the processor's test card numbers live only on the server); no money moves; "14 months later" is a date override; no claim is ever submitted; replay mode, if used, is labeled "replayed" in What we sent.
- **Where the disclosure goes:** Devpost, the video and the live demo say what is real and what is simulated. The app's own screens, including the HTML verdict page, don't call themselves a concept. `docs/design.md` §8 says the verdict page "states it is a concept"; that applies to the demo and video only.

### 12.4 Table kit
- Demo iPhone and a spare, both with the build, the seeded wallet, Shortcut first-run prompts cleared, and Back Tap set to Paywise (Try it now passed).
- Cable + laptop mirroring, or an external camera if G3 fails.
- Two hotspots. Replay on-when-offline.
- No other Live Activities running (music and timers off). Do Not Disturb on.
- Tab 2 pre-loaded with the renewed checkout. Devpost QR code.
- At least one person at the table during judging (Sun 11:30 AM–2:00 PM, dh26 schedule; whether Visa judges in person or by video is **(u)**).

---

## 13. Success metrics

| Metric | Kind | Target | How measured (owner) |
|---|---|---|---|
| Card **products** held by interviewed students, mapped by us to purchase protection / extended warranty | Demand | Report counts per product family (n = 10–12). The pitch uses "X of N hold a card with protection" only if X ≥ 4 | Pre-event interviews; aggregates only (D) |
| Awareness: knows their card's protections; ≥$100 online purchases in the last 12 months; ever filed a benefit claim; would turn on Back Tap | Demand | Report counts | Same interviews (D) |
| 3-second comprehension | UX | ≥8/10 non-teammates name the card after a 3 s view of the Switch snippet; ≥6/10 name one reason; ≤2/10 say "it earns less than my card" | Sat 8–9 PM at the venue (D) |
| Stranger trigger | UX | ≥9/10 first-time presses by non-teammates start a check | Same session (D) |
| Right card used | UX | ≥9/10 trials end with the recommended card selected on the demo store | Same session (D) |
| Time to "am I covered + what do I send?" | User value | Paywise ≤60 s vs a measured manual baseline | Stopwatch, 3 non-teammates (D) |
| Correct pick | User value | ≥20/22 scenarios | `pytest` over `fixtures/scenarios.json` (B runs; D wrote it) |
| **False switches** | Trust | 0/22 scenarios; ≤1/30 real screenshots | Same + accuracy set (A) |
| **Protection drops** | Trust | 0: never recommend a card that loses a protection the default has on a qualifying item | Scenarios 5, 21, 22 + harness (B) |
| Coverage verdicts | User value | ≥12/13 correct; every not_covered case right; 13/13 cite section + version date; capped cases show the cap | `pytest` over `fixtures/coverage_cases.json` (B) |
| Press → *Checking* | Tech | p50 ≤1.0 s | os_signpost, 20 runs (A) |
| Press → result | Tech | p50 ≤3.5 s, p90 ≤5 s on venue Wi-Fi or hotspot | os_signpost + screen recording (A) |
| Chain reliability | Tech | ≥19/20 presses capture the right screen and show a result | S1 log + rehearsal (C) |
| Snippet save | Tech | ≥9/10 taps on [Paying with …] create a planned Purchase and reload to Saved | G2 log (C) |
| Checkout read (merchant + total) | Tech | ≥95% on 30 screenshots: 10 demo-store images in the repo + 20 real-app images kept outside the repo | Accuracy harness; aggregates only (A) |
| Items + condition | Tech | ≥85% on the same set | Same (A) |
| Replay robustness | Tech | Replay hits after ≥2 min, at a different battery %, and with another Live Activity in the island | §15.7 step 10 (A) |
| Unaided setup | Adoption | ≥4/5 non-teammates finish in ≤2:00; first result ≤60 s | Stopwatch (D) |
| Demo reliability | Tech | 10 consecutive clean runs of the full arc | Rehearsal log (all) |
| Privacy | Trust | 0 screenshots, last 4 or card numbers in any request; the backend rejects ≥12-digit runs; no real-app file in the repo | Backend test + `test_privacy.py` + What-we-sent review (B, A) |

---

## 14. Plan

### 14.1 Team
- **A — ML/CV:** on-device crop/OCR/redaction, checkout gate, LLM cart parser, cause classification, replay + What we sent, app shell, claim input, metrics harness.
- **B — Backend/engine:** catalog + merchant table, engine, `/v1/check`, `/v1/coverage`, `/v1/store/pay` (Visa Acceptance), benefit verification (G5).
- **C — iOS lead:** Shortcut, App Intents, snippets, Live Activity/widget, chain spikes and gates G1–G3.
- **D — Design/web/story:** demo store, snippet/island design with C, HTML verdict template, trigger setup screen, interviews, Devpost (owner), pitch, video. D writes `scenarios.json` and `coverage_cases.json` (non-engine).

### 14.2 Before Saturday: pre-event build (Thu Oct 15 evening → Sat 12:30 PM, ≈40 ph)

**Tonight, first 15 minutes (B):** submit the Visa Acceptance (Cybersource) sandbox sign-up (activation can stall); create the Anthropic API key on the Console credits (owner: @Azealoo), kept only in the deployed environment and local, uncommitted `.env` files; set up Render (`docs/hosting.md`).

| When | A: ML/CV (≈8.5 ph) | B: Backend/engine (≈10.5 ph) | C: iOS lead (≈11 ph) | D: Design/web/story (≈10.5 ph) |
|---|---|---|---|---|
| **Thu 6–9 PM** | Redaction rules + tests on `fixtures/ocr` text, as portable regexes (2) | Sign-ups (0.25); repo skeleton, contracts, `cards.json` skeleton (3) | S0: project, signing, widget extension, App Group (1) | Demo store: 4 checkouts + saved-card selector + confirmation, fake data, client-side mock payment (2.5) |
| **Thu 9–11 PM** | OCR on the 7 captured screenshots on a Mac; top-strip crop (1.5) | — | **S1:** chain with a fake result over the *deployed* store (3) | Deploy the static store to HTTPS (0.25); capture the 7 fixture screenshots (0.5); book interviews |
| **Fri 9 AM–12 PM** | — | Verify demo-card protections against the Guide to Benefits PDFs (2); Visa hello-world **if activated** (1.5) | **Gate G1** runs (1) | `scenarios.json` (2) |
| **Fri 12–6 PM** | OCR + gate + redaction inside the background intent, with C; label 30 screenshots (real-app ones kept outside the repo) (3) | Engine + `/v1/check` + rules parser + tests (3) | **S2** (snippet patterns A/B, button + reload, silent sound, `.transient` probe, island 5 min after Done, Shortcuts indicator during the Keep hold); **S3** capture rig; **S6** setup + Share Sheet branch (3.5) | `coverage_cases.json` + second check of B's data (2); interviews (2.5) |
| **Fri 6:00–6:30 PM** | **Gate review (all):** G1–G5. D reports what the '26 Hacker Guide and Discord say about tracks, deadlines and pre-event work. | ← | ← | ← |
| **Fri 7–10 PM** | LLM parser prompt + eval on `fixtures/ocr` (1.5) | Deploy the backend; serve `/store/` + `/v1/store/pay` (0.5) | Snippet + Live Activity views skeleton (2) | Copy/design pass with C (0.5) |
| **Sat 8:30–10:30 AM** | Smoke test (0.5) | Smoke test (0.25) | Wire `/v1/check` into the proven chain (0.5) | Table-kit check (0.25) |

**Gates (pass rule → on fail):**
- **G1 chain** (C, Fri 12 PM): Back Tap double taps capture the right underlying screen and show the island in ≥9/10 runs, over the deployed store in Safari and over 2 real apps (read-only). On fail → §6.6.
- **G2 surface** (C, Fri 6 PM). All four must pass, otherwise → §6.6:
  - the snippet appears in ≥9/10 runs over Safari and ≥1 third-party app;
  - [Paying with …] creates a planned Purchase and reloads to Saved in ≥9/10;
  - the island is empty 5 min after Done;
  - silent `.named` expands the island without a sound.
- **G3 capture** (C, Fri 6 PM): wired QuickTime or AirPlay shows the island and the snippet. On fail → external camera + overlay.
- **G4 Visa** (B, Fri 6 PM): the sandbox returns an approved transaction ID. If the account isn't activated by Fri 12 PM, stop spending time on it. On fail → P2; remove every Visa-API claim; keep the benefits story.
- **G5 data** (B + D, Fri 6 PM): demo-card protections verified against the PDFs (Active Cash extended warranty / purchase protection; Apple Card; Freedom cap per item vs per claim; notice deadlines). On fail → change the S1 copy to what is verified.

**Low case (~20 ph):** C: S0–S3 + G1/G2 (8) · B: sign-ups + contracts + `cards.json` + G5 (5) · D: store + deploy + screenshots + `scenarios.json` (5) · A: redaction regexes (2). Apply the lean-P0 trims (§4.1).

**Single-Mac plan (if we have only one Mac):** C owns the Mac. A writes redaction and replay-key logic as portable regexes with tests on any machine, then ports them in two Mac slots (Thu 9–11 PM, Fri 12–3 PM). The P0-10 tile picker is cut (seeded wallet only) and P0-15 moves to P1. The coverage verdict is HTML (no Mac); only its SwiftUI input screen needs the Mac (1.5 h).

**Also before Saturday:**
- **Roster:** settled at 4, the maximum (Devpost rules): @Azealoo, @Carolzhxxx, @Michelle111213, @xiuyuan114514 (owner, Oct 16; README).
- **Signing:** done (paid Apple Developer account). Install Xcode 27; enable Developer Mode on the demo iPhones.
- **Accounts:** Visa Acceptance sandbox (`docs/visa-sandbox.md`) and the Anthropic API key tonight; Render for hosting; Stripe only for P1.
- **Discord questions** (full list in `docs/dubhacks-2026-rules.md`): where the '26 Hacker Guide is (its Devpost link is broken); the rubric point breakdowns, and whether Visa uses the same four criteria; is Visa judged in person or by video, and do Visa judges visit tables; final deadline (Devpost overview 10:00 AM vs schedules 10:30 AM; treat 10:00 as hard); video length and format; are "Chef's Kitchen" (Devpost) and "Chef's Choice" (dh26) the same track; are external APIs and sandboxes allowed; are power and Wi-Fi guaranteed at tables for a phone + Mac demo.
- **Repo hygiene:** add Xcode entries (`xcuserdata/`, `DerivedData/`, `*.xcuserstate`) to `.gitignore`; add `THIRD_PARTY.md`; rewrite the README for Paywise (it still describes a different product). Real-app screenshots live in `~/paywise-private/`, never in the repo.

### 14.3 Event timeline (Sat 12:30 PM → Sun; internal hard deadline 10:00 AM)

| Time | Milestone | Kill switch |
|---|---|---|
| 12:30 PM Sat | Contracts frozen; P0 board; gate recap | — |
| 1:30 PM | D at the Visa workshop, if there is one (u) | — |
| **2:30 PM** | **G6:** real pipeline on the store (press → crop + OCR → LLM → engine → snippet → save) in 4/5 runs | `PARSER_MODE=rules` for the demo pages |
| 5:00 PM | Purchases + "I bought this"; `/v1/coverage` ≥11/13; HTML verdict in the web view | `COVERAGE_MODE=rules` (user picks the cause) |
| 7:30 PM | Full arc end to end; first footage | Snippet unreliable → island alerts (§6.6) |
| 8:00–9:00 PM | Comprehension, stranger-trigger, right-card and setup tests with 10 non-teammates (D) | — |
| 9:30 PM | Track decision | Default: one title track (Cook Smarter, §11.0's suggested fit) + Visa |
| **10:00 PM** | **Devpost draft submitted** (D; B backup); all members accepted invites | **Gate: Sat 10:30 PM draft** (published): declare tracks (one title track + Visa) and add all 4 members with their Discords. No draft means no judging on Sunday. |
| 10:00 PM–1:00 AM | P1 window, **only if the arc ran 5/5 clean** | — |
| 1:00 AM | P0 freeze | — |
| 1:30–5:30 AM | A & B sleep. C & D film until 3:00, then sleep 3:30–7:30 | — |
| 3:00 AM | Feature freeze, including P1 | — |
| 5:30 AM | A & B: latency runs, scenario + coverage tests, 10 clean runs, numbers for the close | — |
| 7:30 AM | C & D: video edit | — |
| 8:45 AM | Video final | — |
| 9:00 AM | Upload over hotspot | — |
| 9:30 AM | Submit | **10:00 AM internal hard deadline** (Devpost overview: before 10:00 AM; Devpost and dh26 schedules: 10:30 AM; treat 10:00 as hard) |
| 11:30 AM–2:00 PM | Judging: at least one person at the table, table kit, replay armed | — |

### 14.4 Cut order (first → last)
1. Anything P2.
2. P1 items in reverse order (P1-16 first … P1-1 last).
3. Visa Acceptance live call → mocked confirmation; remove every Visa-API claim. (Applied Oct 16: G4 failed.)
4. The "Prefer a button?" Action Button card.
5. The [What we sent] snippet button (keep the in-app screen and redaction).
6. Claim checklist and deadline styling (keep the verdict and the clause).
7. Snippet → island alerts for every state (§6.6).
8. LLM cart parser → rules parser for the demo pages.
9. LLM cause classification → user-picked chips.

**Never cut:**
- Press → screenshot → on-device crop, OCR and redaction (only text leaves the phone).
- A protection-aware pick with the cash trade, readable in about 3 s.
- A saved (planned) purchase with coverage dates.
- A "Can I claim?" verdict citing the clause, including one honest "not covered".
- The Keep answer, replay mode, and the real-vs-simulated disclosure.

### 14.5 GitHub hygiene
Everyone commits at least hourly from their own account; merge commits, not squash; no API keys in the app or repo; real-app test data never in the repo.

---

## 15. First build (v1)

This section lists exactly what to build first. A separate session can start from here. It uses §6.3 (copy for every state) and §7.2 (engine rules) from this file. Fixture data must be obviously fake; card data lives in one file; no secrets in the repo.

### 15.1 What runs where

| Step (§15.7) | Any machine (Linux / Claude Code OK) | Needs Mac + Xcode 27 + iPhone |
|---|---|---|
| 0–5 (skeleton, contracts, data, fixtures, engine, store) | yes | — |
| 6–8 (iOS chain, snippet/surface spikes, OCR) | redaction regexes and tests only | yes |
| 9 (LLM parser) | yes | — |
| 10–11 (wiring, app shell) | — | yes |
| 12a (`SavePurchaseIntent`) | — | yes |
| 12b (`/v1/coverage`), 12c (HTML verdict), 13 (Visa Acceptance) | yes | — |
| 12d (SwiftUI claim input + web view), 14 (trigger setup) | — | yes |
| 15 (metrics) | scripts and aggregation | device runs |

### 15.2 Repo layout

```
README.md            rewrite: Paywise; how to run backend, store, tests
THIRD_PARTY.md       licenses for any seeded data
.env.example         placeholders only (§15.5)
.gitignore           + xcuserdata/, DerivedData/, *.xcuserstate (.env is already ignored)

data/
  cards.json           THE ONE card-data file (cards, merchants, item categories)
  cards.schema.json    JSON Schema (structure, not data)

contracts/             JSON Schema + example for each of:
  check.request · check.response · coverage.request · coverage.response
  store-pay.request · store-pay.response · live-activity-content-state
  check-record · purchase

fixtures/
  wallets.json         7 demo wallets; fake last 4 only
  scenarios.json       22 scenarios (author: D)
  coverage_cases.json  13 cases (author: D)
  screenshots/*.png    demo-store pages only (fake names, addresses, cards)
  ocr/*.txt            expected redacted OCR text (top strip already cropped)
  carts/*.json         expected parsed Cart per screenshot
  replay/<merchantId>_<totalCents>.json   cached /v1/check responses

backend/
  pyproject.toml       Python 3.12, fastapi, uvicorn, pydantic v2, httpx, jinja2, pytest
  app/main.py          /health, /v1/check, /v1/coverage (?format=html), /v1/store/pay, static /store/
  app/models.py        pydantic models mirroring contracts/
  app/catalog.py       loads + validates data/cards.json (fail fast)
  app/parser_rules.py  regex parser for demo-store pages
  app/parser_llm.py    LLM parser (schema-constrained JSON)
  app/engine.py        §7.2 rules; Decimal math
  app/copy.py          §6.3 templates with {last4:<cardId>} and {ppCap} placeholders
  app/coverage.py      window/date rules + LLM cause classification
  app/templates/verdict.html
  app/visa_acceptance.py   PAY_MODE=mock|visa_acceptance
  app/policy.py        thresholds (not card data)
  tests/               test_catalog, test_contracts, test_scenarios, test_coverage, test_privacy

demo-store/            index.html, checkout.html, confirm.html, store.css, store.js
                       (fictional "Northbay Electronics"; page header starts below 80 pt)

ios/
  Paywise.xcodeproj    bundle ID com.azealoo.paywise · App Group group.com.azealoo.paywise (§9.1)
  Paywise/             app target: intents, onboarding, wallet, purchases, claim input, What we sent
  Shared/              App Group code: CheckStore, Purchase model, CheckResultView (app + widget)
  PaywiseWidgets/      widget extension (Live Activity views)
  PaywiseTests/
  Shortcut/README.md   how to rebuild and share the "Paywise" iCloud Shortcut (with the input branch)

docs/
  spikes.md            S0–S6 results, timings, gate decisions
  metrics.md
  design.md            style tokens and the asset list (D)
  llm-provider.md      Claude Haiku 5.5 decision, settings, latency check
  hosting.md           Render setup
  visa-sandbox.md      Visa Acceptance sandbox sign-up and keys (G4)
  dubhacks-2026-rules.md   published rules, Visa prompt, rubric, deadlines
  benefits-verification.md G5 answers and verified card values
```

- The iOS app bundles `data/cards.json` as a **file reference** (Copy Bundle Resources). There is no second copy.
- Real-app screenshots and their labels **never live inside the repo directory**. Keep them in `~/paywise-private/`, mask them on the phone before export, and delete them after the event.

### 15.3 The one card-data file: `data/cards.json`
- **Format:** JSON, UTF-8, validated against `data/cards.schema.json` at backend start and in `test_catalog.py`. A Swift `Codable` model mirrors it.
- **Top level:** `schemaVersion` (2), `catalogVersion` (date), `cards[]`, `merchants[]`, `itemCategories[]`, `offers[]`, `programs[]`, `events[]`, `categoryAliases[]`.
- **Card fields:**
  - `id`, `issuer`, `product`, `displayName`, `shortName`; `network` (visa / mastercard / discover / amex); `networkTier` {value, status}; `annualFeeUsd`; `rewardCurrency` (cash_back / points); `pointValueCents` (null for cash back); `foreignTransactionFeePct`; `art` {assetName, color}.
  - `earn`: {`baseRatePct`, `rules[]`}. Each rule: `id`, `category` (itemCategory id or null), `merchantIds` (array or null), `paymentMethods[]` (apple_pay / card / any), `ratePct`, `cap` (always null), `needsActivation` (always false), `status` (verified / partial / unverified); optional `window` {startsOn, endsOn, endsOnStatus}, `channels[]` (online / in_app / in_store / any; missing = any), `excludes[]` (fine print, not read by the engine) and `sources[]`. An earn rule is public and unconditional; the server applies it (§7.2 rule 1).
  - `protections[]`. Each protection:
    - `type` (purchase_protection / extended_warranty / cell_phone_protection), `summary`, `covers[]` (theft / accidental_damage / involuntary_parting / failure), `excludes[]`.
    - Purchase protection: `windowDays`, `windowDaysByState` (e.g. {"NY": 90}).
    - Extended warranty: `extendsByMonths`, `maxOriginalWarrantyMonths`, `maxTotalFromPurchaseMonths`.
    - `limits`: {`perItemUsd`, `perClaimUsd`, `perAccountUsd`, `appliesTo` (item / claim)}. **Required for any protection shown in copy.**
    - `eligibility`: {`conditionsAllowed[]` (new), `paymentRequirement` (some_portion / full), `excludedCategories[]`}.
    - `notice`: {`notifyWithinDays`, `submitDocsWithinDays`} (null until verified).
    - `claim`: {administrator, url, phone}; `source`: {document, section, versionDate, url, quote}; `verification`: {`status` (verified / partial / unverified), checkedBy, checkedOn, note}.
  - `sources[]`.
- **Merchant fields:** `id`, `names[]`, `domains[]`, `category`, `acceptsApplePay` {value, status}, `isDemo`.
- **Item category fields:** `id`, `warrantyRelevant`, `theftDamageRelevant`.
  - Both true: electronics, computers, phones, audio, cameras, appliances, tools, bikes, instruments.
  - Both false: apparel, home, dining, grocery, pharmacy, gift_card, services, travel, general, gas, entertainment, utilities.
- **`offers[]`** (evaluated on the phone only, §7.2 rule 9): `id` (one per period, e.g. `discover-5pct-2026q4`), `cardIds[]`, `programId`, `title`, `evaluation` (device: may change cash; hint: shown, never changes cash), `match` {merchantIds, categories, categoryBasis (rule / items), excludeMerchantIds[], paymentMethods[], channels[]}, `reward` {kind (rate / statement_credit / checkout_discount / cashback_match / membership / spend_bonus / count_bonus / partner_credit / price_perk), ratePct, basis (total / extra), amountUsd, matchPct, countsAsCash}, `limits` {minSpendUsd, spendCapUsd, capPeriod (offer_window / calendar_quarter / account_window / per_booking), afterCapRatePct, maxRewardUsd, usesPerPeriod}, `window`, `requires[]` (activation {deadline, retroactive} / enrollment / targeted / account_age {months} / acquisition_offer {openedFrom, openedThrough} / event {eventId} / link_or_portal, which forces hint), `whenUnknown` (exclude / medium), `exclusiveGroup`, `confirmQuestion` (the one-tap question, e.g. "Activated your Q4 5%?"), `display.short`, `status`, `sources[]`. The schema forces memberships, thresholds and link-only offers to `hint`, and a question on any offer that needs the user's answer.
- **`programs[]`:** personal-offer programs (Chase Offers, Capital One Offers, My Wells Fargo Deals, Apple Card special offers): `cardMatters` (always / in_store_and_in_app_only / never), `applePay` (counts / required / may_not_count / excluded / unknown), `stacking`, `needsAddStep`, `oneTimeDefault`, `layout`, `screenWords[]`, `availableAfterEventId`, `status`, `sources[]`. Their offers are only visible to the cardholder; capturing them comes later (§15.9).
- **`events[]`:** issuer changes the user confirms for their card (Discover → Capital One, about 2026-10-19; Apple Card → Chase, about 2028): `expectedOn`, `askFrom`, `confirmQuestion`, `effects` {enablesOfferIds, enablesProgramIds, carriesOver, otherChanges}. Offers gated on an event stay off until the user says Yes.
- **`categoryAliases[]`:** screen wording → item category ("grocery stores" → grocery), for the offer reader later.
- **Sources:** primary pages only. Archived copies (web.archive.org) stay in research notes; their 14-digit timestamps also fail `test_privacy.py`.
- **v1 content:** the 5 cards in §8.1, the ~10 merchants in §8.3 plus 12 offer merchants, and the item categories above. Offers (2026-10-16): Apple Card's 3% with Apple Pay at Duane Reade (in store only), Ace, ChargePoint, Exxon/Mobil, Hertz, Uber and Uber Eats as earn rules, Booking.com as a hint; Freedom Unlimited's 5% on Chase Travel and its and Rise's 2% on Lyft in the app (to 2027-09-30, card only); Discover's Q4 2026 5% on restaurants (not DoorDash or Uber Eats), entertainment and utilities up to $1,500 with activation; Capital One Travel and Entertainment 5% after the Discover move; Rise's 3% new-account dining; a 3% foreign transaction fee on Active Cash, Freedom Unlimited and Rise. Display rule: §8.2.
- **Not in the shape yet:** a deductible, a per-period cap (Active Cash: 2 claims and $1,200 per 12 months), and the "or as soon as reasonably possible" softening on notice deadlines. Until fields exist, these go in `summary` and `verification.note` (as in `docs/benefits-verification.md` §7).

### 15.4 Fixtures (all obviously fake)
- **Fake identity:** name "Alex Doe"; address "123 Example St, Seattle, WA 98000"; email "alex@example.com"; phone "(555) 010-0000"; last 4 only 1234, 5678 or 4321. No real card numbers anywhere. Processor test card numbers live only in the deployed environment (`DEMO_TEST_CARD_MAP`).
- **`fixtures/wallets.json`** (the first card listed is the default):

| Wallet | Cards |
|---|---|
| `demo-3card` | apple-card ••5678, wf-active-cash ••4321, chase-freedom-unlimited ••1234 |
| `apple-ac` | apple-card ••5678, wf-active-cash ••4321 |
| `no-protection` | apple-card ••5678, discover-it-student-cash-back ••4321 |
| `rise-2card` | apple-card ••5678, chase-freedom-rise ••1234 |
| `fu-default` | chase-freedom-unlimited ••1234, wf-active-cash ••4321, apple-card ••5678 |
| `discover-fu` | discover-it-student-cash-back ••4321, chase-freedom-unlimited ••1234 |
| `rise-ac` | chase-freedom-rise ••1234, wf-active-cash ••4321 |

- **Screenshots** (393×852 pt @3x, captured on a phone Thursday night), each with a matching `ocr/*.txt` (top strip cropped) and `carts/*.json`:
  - `laptop-checkout`: Aero 14 Laptop, new, $1,499.00, saved Mastercard ••5678.
  - `laptop-renewed-checkout`: $1,099.00, listed "Renewed · no warranty".
  - `earbuds-checkout`: $249.00.
  - `mug-checkout`: $18.00.
  - `laptop-confirmation`: order #NB-100234.
  - `feed-not-checkout`: a fake social feed page.
  - `blurry-unreadable`.
  - P1: `laptop-with-protection-plan`, `shoes-bnpl`.
- **`fixtures/scenarios.json`** (D writes and hand-computes; draft below matches §7.2). Each entry: `{id, wallet, paymentPath, cart, expected: {kind, reason, recommendedCardId, cashDeltaVsCashBest, protectionsGained[]}}`. AC = Active Cash, FU = Freedom Unlimited.

| # | Wallet | Cart / path | Expected |
|---|---|---|---|
| 1 | demo-3card | laptop $1,499, saved card | switch / protection → FU; −$7.49 vs AC; gains [purchase_protection, extended_warranty] |
| 2 | demo-3card | renewed laptop $1,099, no warranty | switch / cash → AC; +$10.99 vs Apple Card; note "Renewed, no warranty: no card covers it" |
| 3 | demo-3card | earbuds $249 (audio) | switch / protection → FU; −$1.24 vs AC |
| 4 | demo-3card | mug $18 (home) | keep / below_threshold |
| 5 | fu-default | laptop $1,499, saved card | **keep / already_protected** (guard; snippet) |
| 6 | no-protection | laptop | keep / default_best (tie) |
| 7 | apple-ac | laptop | switch / cash → AC; +$14.99 |
| 8 | demo-3card | Nike $180 shoes, Apple Pay visible | keep / method |
| 9 | demo-3card | Nike $180, card form only | keep / below_threshold ($1.80) |
| 10 | demo-3card | headphones $120 (audio) | switch / protection → FU; −$0.60 |
| 11 | demo-3card | headphones $90 | keep / below_threshold |
| 12 | demo-3card | gift card $100 only | keep / below_threshold |
| 13 | demo-3card | text with no total | no_checkout / not_checkout |
| 14 | demo-3card | garbage OCR | no_checkout / unreadable |
| 15 | demo-3card | order confirmation | no_checkout / already_paid |
| 16 | discover-fu | laptop | switch / protection → FU; pick is also cash-best |
| 17 | rise-2card | earbuds $249 | switch / protection → Freedom Rise; also cash-best |
| 18 | demo-3card | laptop, items unreadable, total readable | **keep / items_unreadable** |
| 19 | demo-3card | Walgreens $40, Apple Pay visible | keep / method |
| 20 | demo-3card | Amazon $38 household, saved card | keep / below_threshold |
| 21 | rise-ac | laptop $1,200, saved card | **keep / already_protected** (guard: AC +$6.00 would otherwise switch) |
| 22 | fu-default | laptop $1,499, Apple Pay visible | **keep / already_protected** (guard on the Apple Pay path) |

- **`fixtures/coverage_cases.json`** (D; draft). Each case: `{id, purchase, incident, asOf, expected: {verdict, benefit, route, payoutCapUsd, citesSection}}`.

| # | Purchase | Incident | Expected |
|---|---|---|---|
| 1 | FU laptop | lines at month 14, not dropped | may_be_eligible / extended_warranty / card_extended_warranty |
| 2 | FU laptop | dropped at month 14 | not_covered / none |
| 3 | FU laptop | dropped at day 30 | may_be_eligible / purchase_protection; cap $500 of $1,499 |
| 4 | FU earbuds | stolen at week 6 | may_be_eligible / purchase_protection; full $249; police report in the checklist |
| 5 | FU earbuds | left on a bus at week 6 | need_more_info |
| 6 | Apple Card laptop | failure at month 14 | not_covered / none |
| 7 | FU laptop | failure at month 8 | **not_covered / route manufacturer** ("still under the maker's warranty") |
| 8 | FU renewed laptop, no manufacturer warranty | failure at month 14 | not_covered (no maker's warranty, so nothing for the extended warranty to extend; G5) |
| 9 | FU earbuds | stolen at day 200 | not_covered |
| 10 | AC headphones | failure at month 14 | not_covered (confirmed in G5: Active Cash has no extended warranty) |
| 11 | FU laptop | failure at month 30 | not_covered (after the extra year ends) |
| 12 | FU laptop, `paidWith` card_partial | failure at month 14 | may_be_eligible (charging part of the price qualifies, G5); payout capped at the part paid on the card |
| 13 | FU laptop | stolen at day 30 | may_be_eligible / purchase_protection; **cap $500 of $1,499** |

### 15.5 API contracts, on-device records and intents

**`POST /v1/check`** (sent by the intent; no last 4, no images)

Request:
```json
{
  "requestId": "5f0c…uuid",
  "client": {"app": "paywise-ios", "version": "0.1.0"},
  "clientDate": "2026-10-17",
  "screen": {
    "ocrText": "Northbay Electronics\nCheckout\nAero 14 Laptop, 14-inch (New)  $1,499.00\nTotal  $1,499.00\nPay with Mastercard [CARD]\nChange\nShip to [ADDRESS]\nPlace order",
    "redactions": ["card_number", "address", "email", "phone"],
    "ocrConfidence": 0.93
  },
  "wallet": {"cards": [
    {"cardId": "apple-card", "isDefault": true},
    {"cardId": "wf-active-cash", "isDefault": false},
    {"cardId": "chase-freedom-unlimited", "isDefault": false}
  ]},
  "prefs": {"paysInFull": null}
}
```

Response:
```json
{
  "requestId": "5f0c…uuid",
  "screenType": "checkout",
  "cart": {
    "merchant": {"name": "Northbay Electronics", "merchantId": "northbay-electronics"},
    "items": [{"name": "Aero 14 Laptop, 14-inch", "priceUsd": 1499.00, "quantity": 1,
               "category": "computers", "condition": "new", "seller": "merchant",
               "isGiftCard": false, "isServicePlan": false}],
    "totalUsd": 1499.00, "currency": "USD",
    "paymentOptionsVisible": ["saved_card"],
    "selectedPayment": {"kind": "saved_card", "network": "mastercard"},
    "upsells": {"protectionPlanUsd": null}, "bnplVisible": false,
    "confidence": {"merchant": 0.97, "total": 0.98, "items": 0.92}
  },
  "decision": {
    "kind": "switch",
    "reason": "protection",
    "presentation": "snippet",
    "recommendedCardId": "chase-freedom-unlimited",
    "defaultCardId": "apple-card",
    "cashBestCardId": "wf-active-cash",
    "paymentPath": "saved_card",
    "instruction": "change_saved_card",
    "cash": {"byCard": {"apple-card": 14.99, "wf-active-cash": 29.98, "chase-freedom-unlimited": 22.49},
             "deltaVsCashBest": -7.49, "deltaVsDefault": 7.50},
    "protectionsGained": [
      {"type": "purchase_protection", "windowDays": 120,
       "limit": {"amountUsd": 500, "appliesTo": "item"}, "verification": "verified"},
      {"type": "extended_warranty", "extendsByMonths": 12,
       "limit": {"amountUsd": 10000, "appliesTo": "item"}, "verification": "verified"}
    ],
    "protectionsLost": [],
    "eligibilityNotes": [],
    "confidence": "high",
    "copy": {
      "line1": "Use Freedom ••{last4:chase-freedom-unlimited}",
      "line2": "Adds a warranty year + $500 theft cover",
      "line3": "$7.49 less cash back than Active Cash",
      "instruction": "Change card to Visa ••{last4:chase-freedom-unlimited}, then place order",
      "primaryButton": "Paying with Freedom"
    }
  },
  "purchaseDraft": {
    "merchant": "Northbay Electronics", "item": "Aero 14 Laptop, 14-inch", "category": "computers",
    "condition": "new", "priceUsd": 1499.00, "purchaseDate": "2026-10-17",
    "cardId": "chase-freedom-unlimited",
    "coverage": [
      {"type": "purchase_protection", "until": "2027-02-14", "limitUsd": 500},
      {"type": "extended_warranty", "until": "2028-10-17", "assumesManufacturerWarrantyMonths": 12}
    ]
  },
  "sources": [{"cardId": "chase-freedom-unlimited", "document": "…Guide to Benefits",
               "section": "Purchase Protection", "versionDate": "…", "verification": "verified"}],
  "offerContext": {
    "catalogVersion": "2026-10-16", "amountUsd": 1499.00, "merchantId": "northbay-electronics",
    "ruleCategory": "electronics", "itemCategories": ["computers"], "paymentPath": "saved_card", "method": "card",
    "thresholdUsd": 5, "publicRates": {"apple-card": {"ratePct": 1, "status": "verified", "ruleId": null}, "…": {}},
    "allowedCashPicks": ["apple-card"], "purchaseDraftByCard": {}, "deviceMayOverride": false
  },
  "timingMs": {"parse": 900, "engine": 3}
}
```

`offerContext` is null for no_checkout. It is a function of the cart and the public catalog only (§7.2 rule 9). `deviceMayOverride` is true only for switch/cash, keep/default_best, keep/below_threshold and keep/method; then `allowedCashPicks` lists the cards that keep every protection the default has, and `purchaseDraftByCard` holds the draft for each.

**Enum values (every enum field)**

| Field | Values |
|---|---|
| `screenType` | checkout / order_confirmation / not_checkout / unreadable |
| `decision.kind` | switch / keep / no_checkout / error |
| `decision.reason` | protection / cash / method / default_best / below_threshold / items_unreadable / already_protected / already_paid / not_checkout / unreadable / error |
| `decision.presentation` | snippet / island (snippet for switch and for keep/already_protected) |
| `paymentPath` | apple_pay / saved_card / card_form / unknown |
| `instruction` | change_saved_card / enter_card / apple_pay_swipe / use_apple_pay / none |
| `confidence` | high / medium / low |
| `item.category` | ids from `itemCategories` |
| `item.condition` | new / renewed / used / unknown |
| `item.seller` | merchant / third_party / unknown |
| `paymentOptionsVisible[]` | apple_pay / saved_card / card_form / bnpl / paypal / other |
| `selectedPayment.kind` | saved_card / card_form / apple_pay / unknown |
| `selectedPayment.network` | visa / mastercard / discover / amex / unknown |
| protection `type` | purchase_protection / extended_warranty / cell_phone_protection |
| `limit.appliesTo` | item / claim |
| `verification` | verified / partial / unverified |

**Errors:** shape `{"requestId", "decision": {"kind": "error", "reason": "error", "presentation": "island", "copy": {...}}, "error": {"code", "message"}}`. `error.code`: parse_failed / timeout / bad_request / privacy_rejected / server_error. The backend returns **400 privacy_rejected** for any body with a run of ≥12 digits, and never logs request bodies.

**On-device records** (App Group container, shared by the app process and the widget extension)

`CheckRecord`, stored at `<AppGroup>/checks/<checkId>.json` and written by `CheckCheckoutIntent`. Records older than 24 h are pruned. `view`: result / saved / sent.
```json
{
  "checkId": "5f0c…uuid",
  "createdAt": "2026-10-17T14:02:11-07:00",
  "sentPayload": { "...": "the exact /v1/check request JSON" },
  "response": { "...": "the /v1/check response JSON" },
  "filledCopy": {"line1": "Use Freedom ••1234", "line2": "…", "line3": "…", "instruction": "…"},
  "replayed": false,
  "savedPurchaseId": null,
  "view": "result",
  "offerAdjustment": null
}
```

`offerAdjustment` (optional, device only): the decision and purchase draft the phone's `OfferResolver` produced, the offers it applied and whether the decision changed. The app shows and saves it in place of the server's; `response` stays as received, so "What we sent" proves no offer data left. The answers behind it live in `<AppGroup>/offers/state.json` (`OfferStore`: per card, `OfferState` {answer yes / no / not_sure, answeredOn, activatedOn, spentTowardCapUsd, chosenVariant} by offer id, event answers, and `CardFacts.openedOn` as yyyy-MM), set from Settings › Card offers with one tap per question.

`Purchase`, a SwiftData model in the App Group container. `status`: planned / confirmed.
```json
{
  "id": "p_…", "checkId": "5f0c…uuid", "status": "planned",
  "merchant": "Northbay Electronics", "item": "Aero 14 Laptop, 14-inch", "category": "computers",
  "condition": "new", "priceUsd": 1499.00, "purchaseDate": "2026-10-17",
  "cardId": "chase-freedom-unlimited",
  "coverage": [{"type": "purchase_protection", "until": "2027-02-14", "limitUsd": 500},
               {"type": "extended_warranty", "until": "2028-10-17", "assumesManufacturerWarrantyMonths": 12}],
  "manufacturerWarrantyMonths": null, "orderNumber": null, "transactionId": null
}
```

**Intents** (main app target only via `allowedExecutionTargets`; none registered in `AppShortcutsProvider`)
- **`CheckCheckoutIntent : AppIntent, LiveActivityIntent`** — `supportedModes = [.background]`; `@Parameter(title: "Screenshot") var image: IntentFile?`; `perform() -> some IntentResult & ShowsSnippetIntent` (the not-set-up path returns a static `ShowsSnippetView` result). Steps, in order:
  1. End all Paywise activities.
  2. Request *Checking*.
  3. Crop the top strip.
  4. OCR, gate, redaction.
  5. POST `/v1/check` with a 6.0 s timeout; on failure, look up replay.
  6. Write the `CheckRecord`.
  7. If `presentation == "snippet"`: end the activity (`.immediate`) and return `.result(snippetIntent: CheckResultSnippetIntent(checkId:))`. Otherwise: update the activity with an alert, sleep 4 s, end it `.immediate`, and return `.result()`.
- **`CheckResultSnippetIntent : SnippetIntent`** — `@Parameter var checkId: String`. `perform()` reads the `CheckRecord` and returns `ShowsSnippetView` with `CheckResultView(record:)`. **No side effects:** the system may re-perform it.
- **`SavePurchaseIntent : AppIntent`** — `@Parameter var checkId: String`. Loads the record; if `savedPurchaseId` is already set it does nothing (idempotent). Otherwise it inserts `Purchase(status: planned)` from `purchaseDraft`, sets `savedPurchaseId` and `view = saved`, and returns `.result()`. The system then re-performs the snippet intent, which shows Saved.
- **`ShowSentIntent : AppIntent`** — `@Parameter var checkId: String`. Sets `view = sent` and returns `.result()`.
- The snippet's buttons are `Button(intent: SavePurchaseIntent(checkId:))` and `Button(intent: ShowSentIntent(checkId:))`. **Done is the system button.**
- **Pattern B** (only if G2's button test fails): inside `CheckCheckoutIntent`, `try await requestConfirmation(actionName: <custom "Paying with Freedom">, snippetIntent: CheckResultSnippetIntent(checkId:))`. On confirm: save, then return the Saved result. On cancel: return.

**Live Activity** (Swift `Codable`, well under 4 KB). `phase`: checking / keep / no_checkout / error / switch_fallback. `glyph`: paywise / check / warning / card. `cardId` (optional, R14) names the card whose bundled art the island draws (§9.1); `line3` (optional, R4) is the third line of the switch fallback and of the on-device No checkout. `staleDate` = start + 2 min on every request and update.
```json
// ActivityAttributes (static)
{"checkId": "5f0c…uuid"}
// ContentState (dynamic)
{
  "phase": "keep",
  "glyph": "check",
  "cardId": "apple-card",
  "cardShortName": "Apple Card",
  "last4": "5678",
  "line1": "✓ Keep Apple Card ••5678",
  "line2": "Best of your 3 cards here",
  "line3": null,
  "lockScreenText": "Paywise checked this screen"
}
```

**`POST /v1/coverage`** (only when the user runs a check on one purchase)

Request:
```json
{
  "purchase": {"cardId": "chase-freedom-unlimited", "merchant": "Northbay Electronics",
               "item": "Aero 14 Laptop, 14-inch", "category": "computers", "condition": "new",
               "priceUsd": 1499.00, "purchaseDate": "2026-10-17", "status": "confirmed",
               "manufacturerWarrantyMonths": 12, "manufacturerWarrantySource": "user",
               "paidWith": "card_full"},
  "incident": {"date": "2027-12-17", "description": "Lines across the screen. Never dropped.",
               "cause": "failure", "causeSource": "user_confirmed"},
  "asOf": "2027-12-18"
}
```
`manufacturerWarrantySource`: user / assumed ("Don't know" → 12 months, assumed). `paidWith`: card_full / card_partial / bnpl / unknown. `amountOnCardUsd` (optional, R3): the part of the price charged to the card, for `card_partial`; null or absent means unknown, and with `card_full` the amount charged is `priceUsd`. `cause`: failure / accidental_damage / theft / loss / cosmetic / unknown; null means the server classifies it. `causeSource`: user_confirmed / llm.

Response (`?format=json`; `?format=html` renders the same data through `templates/verdict.html`):
```json
{
  "verdict": "may_be_eligible",
  "benefit": "extended_warranty",
  "route": "card_extended_warranty",
  "headline": "May be eligible: Extended warranty (Freedom Unlimited).",
  "why": "The maker's 1-year warranty ended Oct 17, 2027; the extra year runs to Oct 17, 2028.",
  "limit": {"perItemUsd": 10000, "perClaimUsd": null, "perAccountUsd": 50000, "payoutCapUsd": 1499, "appliesTo": "item"},
  "assumptions": [],
  "citations": [{"document": "…Guide to Benefits", "section": "Extended Warranty Protection",
                 "versionDate": "…", "quote": "…", "verification": "verified"}],
  "checklist": ["Itemized receipt", "Card statement showing the purchase", "Original warranty", "Repair estimate"],
  "deadline": {"type": "notify_by", "date": "2028-03-16", "note": "Notify by Mar 16, 2028; send documents by Apr 15, 2028, or as soon as reasonably possible."},
  "contact": {"administrator": "…", "url": "…"},
  "disclaimer": "Only the benefit administrator decides claims. Paywise never files for you.",
  "incident": {"cause": "failure", "causeSource": "user_confirmed"}
}
```
`verdict`: may_be_eligible / not_covered / need_more_info. `benefit`: purchase_protection / extended_warranty / none. `route`: card_extended_warranty / card_purchase_protection / manufacturer / none. `deadline.type`: notify_by / file_by / unknown. `incident` (R17) echoes the cause the verdict used and where it came from, so the claim screen can pre-select the LLM's chip; the backend always sends it (optional in the schema), and with a null cause `causeSource` is null too. `payoutCapUsd` here is the $1,499 price, under the $10,000 per-item cap. For case 13: `"limit": {"perItemUsd": 500, "payoutCapUsd": 500, "appliesTo": "item"}`, and the headline adds "up to $500 of the $1,499". `payoutCapUsd` is the lesser of the benefit cap and the amount charged to the card, so with `card_partial` (case 12) it is at most the part paid on the card, `amountOnCardUsd` (§5.5). Date and window math happens in code; the LLM only classifies the cause (the user confirms) and drafts `why`.

**`POST /v1/store/pay`** (demo store only)
- Request: `{"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 1499.00}`
- Response: `{"status": "approved", "processor": "visa_acceptance_sandbox", "transactionId": "…", "cardLabel": "Visa ••1234"}`
- `status`: approved / declined / error. `processor`: visa_acceptance_sandbox / mock. `savedCardId` maps to a processor test card only through `DEMO_TEST_CARD_MAP` in the deployed environment.

**`.env.example`** (placeholders only):
```
LLM_API_KEY=changeme
LLM_MODEL=changeme
PARSER_MODE=rules|llm
COVERAGE_MODE=rules|llm
PAY_MODE=mock|visa_acceptance
VISA_ACCEPTANCE_MERCHANT_ID=changeme
VISA_ACCEPTANCE_KEY_ID=changeme
VISA_ACCEPTANCE_SECRET_KEY=changeme
DEMO_TEST_CARD_MAP=changeme
```

### 15.6 Engine
Implement §7.2 exactly (rules 0–9, thresholds in `policy.py`). The copy templates come from §6.3.

### 15.7 Ordered build steps

| # | What | Owner | h | Machine | Done when … |
|---|---|---|---|---|---|
| 0 | Repo skeleton (§15.2), `.gitignore`, `.env.example`, `THIRD_PARTY.md`, README, `pyproject.toml` | B | 1 | any | `pytest` runs green; `uvicorn app.main:app` serves `/health` → `{"ok": true}` |
| 1 | Contracts: Schemas + examples (§15.5); pydantic models | B | 1.5 | any | `test_contracts.py`: every example validates, and every enum in §15.5 appears in a schema |
| 2 | `data/cards.json` + schema (5 cards, ~10 merchants, categories); `catalog.py` | B (+D check) | 3 + 2 (G5) | any | `test_catalog.py` passes; every protection has `limits`, `source` and `verification`; demo-card protections `verified` by Fri 6 PM |
| 3 | Fixtures (§15.4): 7 wallets, 22 scenarios, 13 cases, demo OCR text + carts, replay files | D | 4 | any | Committed **before** step 4 merges; each expectation hand-computed; `test_privacy.py` finds no real names, addresses or ≥12-digit runs, and no file matching the real-app pattern (`realapp-*`, `*-private*`) |
| 4 | `engine.py` (§7.2) + `copy.py` (§6.3) + `parser_rules.py` + `POST /v1/check` | B | 5 | any | `test_scenarios.py` ≥20/22 with **0 false switches and 0 protection drops** (5, 21, 22 pass); S1 returns the exact §6.3 copy; ≥12-digit bodies → 400 privacy_rejected; p50 < 50 ms locally |
| 5 | Demo store: `checkout.html?item=` laptop / laptop-renewed / earbuds / mug, saved-card selector (Mastercard ••5678 default, Visa ••4321, Visa ••1234), `confirm.html`; static deploy Thu; served by the backend at `/store/` on Fri | D | 3.5 (+B 0.5) | any | Loads over HTTPS on cellular by Thu 11 PM; Change card works; the 7 screenshots captured; page header starts below 80 pt |
| 6 | iOS **S1 chain**: app + widget extension + App Group; `CheckCheckoutIntent` as in §15.5 with a fake result; Shortcut "Paywise" with the input branch, bound to the Action Button and Back Tap; os_signpost per link | C | 4 | Mac | **G1:** ≥9/10 Back Tap double taps over the deployed store and 2 real apps show the correct underlying screenshot in a debug list and show the island; Action Button tallied; timings in `docs/spikes.md` |
| 7 | **S2/S3/S6**: Pattern A (`ShowsSnippetIntent` + `CheckResultSnippetIntent` + `SavePurchaseIntent` button + reload) and Pattern B; `.named("silent.caf")` alert; `.transient` probe; island state 5 min after Done; Shortcuts indicator during the 4-s Keep hold; capture via wired QuickTime / AirPlay; Share Sheet branch | C | 3.5 | Mac | `docs/spikes.md` records Y/N + counts for each item; G2/G3 decided per §6.6 |
| 8 | On-device top-strip crop (`TOP_CROP_PT = 62` × scale, tuned here) + OCR (Vision `RecognizeDocumentsRequest` or `VNRecognizeTextRequest`) + checkout gate (money total + a checkout keyword) + redaction (Luhn-valid runs, any ≥12-digit run, "ending in dddd" → `[CARD]`, emails, phones, lines after "Ship to" / "Deliver to" / "Name") | A | 5 | Mac (regexes: any) | On the 7 demo screenshots: merchant + total kept 7/7; no status-bar text in the output; 0 digit runs ≥12, 0 emails, 0 phones, 0 "Alex Doe" or address lines; p50 ≤400 ms inside the background intent; the feed is rejected on device |
| 9 | `parser_llm.py`: schema-constrained Cart JSON; reads numbers, never computes; Σ items vs total checked in code | A | 3 | any | On `fixtures/ocr/*`: merchant + total 100%, items + condition ≥85%; latency logged; `PARSER_MODE` switch works |
| 10 | Wiring: POST with a 6.0 s timeout → *Couldn't check*; `{last4:…}` and `{ppCap}` filled on device; `CheckRecord` written [C]. Replay: key = `merchantId` (a merchant name from the bundled `cards.json` found in the OCR text) + total cents (regex on "Total") → `fixtures/replay/<merchantId>_<totalCents>.json`, labeled "replayed"; What-we-sent screen lists `CheckRecord.sentPayload` [A] | C 2.5 + A 2 | 4.5 | Mac | Press on the demo laptop → real Switch snippet with the §6.3 copy; airplane mode → *Couldn't check* within 7 s, or a replay hit when replay is on; **replay still hits after ≥2 min, at a different battery %, and with another Live Activity running** |
| 11 | App shell: onboarding (tiles from the bundled `cards.json`, default, optional last 4, "Use demo wallet"); "Check a screenshot" (PhotosPicker → same pipeline → in-app `CheckResultView`); Purchases (planned / confirmed, "I bought this") | A | 4 | Mac | A non-teammate sets up 3 cards in ≤60 s; an in-app check matches the press result |
| 12a | `SavePurchaseIntent` + `ShowSentIntent` + Saved / Sent views | C | 2 | Mac | **G2 button test:** ≥9/10 taps over Safari create one planned Purchase (idempotent on a double tap) and reload to Saved; Purchases shows "Aero 14 · Freedom ••1234 · Planned · theft & damage up to $500 to Feb 14, 2027 · warranty year to Oct 17, 2028" |
| 12b | `POST /v1/coverage` (`coverage.py`; `COVERAGE_MODE`; LLM cause classification by A) | B 2 + A 1 | 3 | any | `test_coverage.py` ≥12/13; every not_covered case right; cases 3 and 13 return `payoutCapUsd: 500`; every verdict cites section + version date |
| 12c | `templates/verdict.html` + `?format=html` (the §5.5 copy) | D | 2 | any | Cases 1, 2, 7 and 13 render correctly in a phone-width browser |
| 12d | SwiftUI claim input (confirm card + date → `confirmed`; maker's warranty 1 yr / 2 yr / don't know; text + cause chips) + `WKWebView` showing the HTML verdict | A | 1.5 | Mac | Cases 1 and 2 work end to end on the device with a date override |
| 13 | `visa_acceptance.py` + `/v1/store/pay`; `confirm.html` shows the transaction ID | B | 3 | any | **G4:** the sandbox approves the demo Visa ••1234 order with a transaction ID; `PAY_MODE=mock` works offline |
| 14 | Back Tap prompt + Set Up Back Tap screen (Shortcut link, Back Tap first, Try it now, optional Action Button card) | D | 1.5 | Mac | On a clean phone: install → turn on Back Tap → Try it now with no surprise prompt, in ≤2:00 |
| 15 | Metrics harness + rehearsal script (latency, accuracy on 30 screenshots with aggregates only, scenario/coverage runs, 10 clean arcs) | A + all | 5.5 | scripts any; runs on device | Numbers in `docs/metrics.md`; the harness prints aggregates only |

### 15.8 Stubs and mocks allowed in v1
- **Allowed:** `PARSER_MODE=rules`, `COVERAGE_MODE=rules`, `PAY_MODE=mock`; replay for demo fixtures (always labeled); placeholder card art; seeded demo wallet; date override for "14 months later"; the client-side mock payment in Thursday's static store; a fake result in the S1 spike.
- **Not allowed:** faking a live press on stage with a recording; showing `partial` or `unverified` values as fact; saying "Visa-verified"; saying "Nothing left your phone" when text was sent; saying the Visa transaction is attached to the purchase in P0.

### 15.9 Do NOT build yet
Settings-screenshot onboarding · receipt press on the confirmation · Why sheet · claim PDF · Apple Pay / Stripe path · VDBP · Visual Intelligence · Safari or share extension · widget · on-device Foundation Models (D3: when offer capture comes, a rules reader first; Apple's model only after a 30-real-screenshot eval on Carol reads more offers right with no more wrong pairs) · capturing personal offers from screenshots or emails (D2: after the event) · rewards-optimizer features beyond the catalog offers of §7.2 rule 9 (money-leak audit, FX/DCC, order splitting, expected value, cap tracking from purchases) · offline rules engine · push notifications or a push-based Live Activity end · the lingering island reminder · accounts / login · analytics · iOS 26 support · more than 5 cards · photo analysis in the coverage check · an `AppShortcutsProvider` entry for `CheckCheckoutIntent`.

---

## 16. Risks & open questions

| Risk | Mitigation |
|---|---|
| **Pre-event code vs the rules.** The '26 Devpost rules (read Oct 14, 2026) say "Any projects submitted must be started and completed during the duration of DubHacks '26". The rules page has no 30% allowance; the '26 Hacker Guide, which we couldn't read, may still have one **(u)**. The required public repo's commit history shows pre-event commits. | Decided: the team builds before the event, with no disclosure. The owner confirmed this on Oct 14, 2026 after reading the '26 rule. |
| Take Screenshot from a hardware trigger on iOS 27 captures the app underneath (u) | Gate G1 + §6.6 |
| Snippet appearance and buttons from a Back Tap-run Shortcut (u) | Gate G2 + Pattern B + §6.6 |
| Silent alert sound (u) | G2; fall back to `.default` |
| Island / snippet capture for the video (u) | G3; external camera |
| Visa Acceptance sandbox activation | Sign up Thursday night; G4 |
| Demo-card benefit data | G5 answered from primary sources on Oct 14 (`docs/benefits-verification.md`): Active Cash and Apple Card have no purchase protection or extended warranty; Freedom's $500 cap is per item; notify within 90 days, documents within 120. B or D reviews it before the Fri 6 PM gate. Copy shows verified values only. |
| Few students hold a protection-bearing card | Interviews map card products; P1 non-Chase card; Q&A card on how the catalog generalizes |
| Apple or wallets add best-card hints (Automatic Selection already surfaces co-brand cards) | Moat = protections + saved purchase + claim check |
| Latency on venue Wi-Fi | On-device OCR, text-only upload, replay keyed on merchant + total, two hotspots |
| Only one Mac | Single-Mac plan (§14.2) |
| Judges: "CardPointers / iOS 27 already do this" | "CardPointers picks by merchant and offers (including Visual Intelligence on screenshots); Apple shows rewards and balances. We read the cart, weigh protections and eligibility, save the purchase and check the claim." |
| Judges: "Is this just a Chase reminder?" | The engine and data are card-agnostic; v1's 5-card catalog is narrow because each card's benefits are hand-verified. P1 adds a non-Chase card. |
| Track structure and judging mode in '26 | Visa is a sponsored side track, so we also need one title track (Cook Smarter suggested; team decides). Judging is Sun 11:30 AM–2:00 PM. Whether Visa judges in person or by video is **(u)**: ask on Discord. If Visa is a video track, the video becomes the main judged artifact. |
| Final-deadline conflict and the Saturday draft | The Devpost overview says before 10:00 AM Sunday; the Devpost and dh26 schedules say 10:30 AM. Treat 10:00 AM as hard. The Sat 10:30 PM draft (tracks + all 4 members) is mandatory and is a gate in §14.3. |
| Live Activity start from a Shortcut-run intent | Apple docs say a `LiveActivityIntent` can start one from the background; spike S1 confirms on device |

**Unverified (test or confirm):** snippet appearance and buttons from a hardware-run Shortcut; Take Screenshot from a hardware trigger on iOS 27; whether the iOS 27 screenshot automation runs without a prompt; Amazon in-app Apple Pay; Walmart online/in-app Apple Pay; the '26 Hacker Guide (point breakdowns, video limit); Claude Haiku 5.5 latency for the cart parse; Anthropic's 30-day retention figure (seen only in a search snippet); Walgreens/DoorDash MCCs for Chase bonus categories (P2); our island during the Apple Pay sheet / Face ID (P1 only); QuickTime/AirPlay capture of the island and snippet; the J.D. Power "29%" figure.

### 16.1 Open questions for the team
1. **Macs:** how many Macs with Xcode 27, and whose? About 30 ph of P0 needs a Mac. With one, the single-Mac plan applies.
2. **Tonight's sign-ups (B, ~15 min):** Visa Acceptance sandbox (`docs/visa-sandbox.md`); Anthropic Console credits (owner: @Azealoo); Render (`docs/hosting.md`).
3. **Rules vs pre-event code:** decided (§16 table). No action.
4. **Track:** "Visa: Reimagine Shopping" is a sponsored side track (prompt and rubric in §11.0). Which title track do we enter? (Cook Smarter is suggested.) Do Visa judges visit tables, or is it a video track?
5. **Roster:** the README lists 5 handles; teams are capped at 4 (Devpost rules). Who are the 4?
6. **Hours:** the plan assumes ≈8.5–11 ph each before Saturday (≈40 total). If anyone has less, say so tonight so the low-case plan applies.
7. **Demo phone:** may we bind its Action Button to Paywise? Case or mount? Laptop + USB-C cable for mirroring?
8. **Real Wallet cards (P1 only):** does any teammate's phone hold cards that fit an Apple Pay version of S1?
9. **Interviews:** may D approach 10–12 UW students on Thu/Fri for 5 minutes, asking only which card *products* they hold and recording aggregate counts?

---

## 17. Business model (one line)
Free for consumers; no referral fees or paid ranking. Future revenue: issuers/Visa paying for benefit engagement, never for ranking.

---

## 18. Sources

Notes on access: most of these were checked on Oct 15, 2026. support.apple.com, 9to5mac.com and several issuer and competitor sites weren't reachable from our research environment, so those items rest on search-result summaries and are marked as such where they matter. The DubHacks '26 Devpost and dh26 pages and the demo cards' benefit guides were read in a browser on Oct 14 (`docs/dubhacks-2026-rules.md`, `docs/benefits-verification.md`).

- **Apple (fetched from developer.apple.com):** [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities) · [Action button HIG](https://developer.apple.com/design/human-interface-guidelines/action-button) · [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) · [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent) · [App Intents supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes) · [Displaying static and interactive snippets](https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets) · [Creating controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system) · [Visual Intelligence integration](https://developer.apple.com/documentation/visualintelligence/integrating-your-app-with-visual-intelligence) · [Foundation Models](https://developer.apple.com/documentation/foundationmodels) · [FinanceKit](https://developer.apple.com/documentation/financekit) · [App Clip functionality](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip) · [Vision RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) · [What's new in Apple Pay](https://developer.apple.com/apple-pay/whats-new/) · WWDC25 session 281 (snippets) · WWDC26 sessions 223 (Live Activities), 297 (Visual Intelligence), 310 (Shortcuts)
- **Apple (search summaries):** [Back Tap with Shortcuts](https://support.apple.com/guide/shortcuts/run-shortcuts-tapping-iphone-apd897693606/ios) · [Apple Card Daily Cash merchants](https://support.apple.com/en-us/120400) · [Pay with rewards](https://support.apple.com/120479)
- **iOS 27 Apple Pay (secondary):** [9to5Mac (Sep 27, 2026; a re-dated copy of a Jun 13 story)](https://9to5mac.com/2026/09/27/ios-27-makes-it-easier-to-switch-between-apple-pay-cards/) · [Digital Trends](https://www.digitaltrends.com/phones/ios-27s-apple-pay-fix-wont-have-you-hunting-for-the-right-card-before-checkout/) · [switchingtomac](https://www.switchingtomac.com/ios-27-apple-pay-card-switching-iphone/)
- **Visa / payments:** [Digital Benefits Platform](https://developer.visa.com/capabilities/vdbp) · [VDBP how-to](https://developer.visa.com/capabilities/vdbp/docs-how-to) · [Cybersource BIN Lookup](https://developer.cybersource.com/docs/cybs/en-us/bin-lookup/developer/all/rest/bin-lookup.html) · Cybersource developer community threads on sandbox activation (search) · [Visa Intelligent Commerce](https://developer.visa.com/capabilities/visa-intelligent-commerce) · [DCC](https://www.visa.com/en-us/personal/travel/dynamic-currency-conversion) · Stripe "Testing Apple Pay" and domain registration docs (search)
- **Benefits (primary, read Oct 14, 2026 for G5; details in `docs/benefits-verification.md`):** [Chase Guide to Benefits BGC11366 (PDF)](https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf) · [Wells Fargo Active Cash Guide to Benefits](https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/) · [Apple Card Customer Agreement (PDF)](https://www.goldmansachs.com/terms-and-conditions/Apple-Card-Customer-Agreement.pdf) · [Mastercard Benefits for Apple Card](https://www.mastercard.com/us/en/personal/find-a-card/card-benefits/apple-card-benefits.html)
- **Benefits (earlier, secondary):** [Chase Freedom benefits](https://www.chase.com/personal/credit-cards/education/chase-cards/chase-freedom-benefits-guide) and Chase Freedom Unlimited card page (search: 120 days, $500 per item; +1 yr warranty) · [Wells Fargo Active Cash guide](https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/) · [Discover cuts benefits (NerdWallet)](https://www.nerdwallet.com/article/credit-cards/discover-to-cut-some-card-benefits-2018) · [Doctor of Credit](https://www.doctorofcredit.com/discover-remove-many-card-benefits-february-28th-2018/) · [Visa Extended Warranty](https://usa.review.visa.com/supporting-info/extended-warranty-protection.html)
- **Demand:** [J.D. Power 2026 U.S. Credit Card Satisfaction Study](https://www.jdpower.com/business/press-releases/2026-u-s-credit-card-satisfaction-study/) ([BusinessWire, Aug 13, 2026](https://www.businesswire.com/news/home/20260813093708/en/Financial-Stress-Deepens-Divide-among-U.S.-Credit-Card-Customers-According-to-JD-Power)) · Adobe 2025 holiday shopping results (Jan 2026; search summary) · [UW tuition payment fees](https://finance.uw.edu/sfs/tuition/payment)
- **Competitors:** [CardPointers 8 (9to5Mac, Sep 21, 2026)](https://9to5mac.com/2026/09/21/cardpointers-updated-for-ios-27-with-siri-ai-automatic-offer-syncing-and-much-more/) · [CardPointers AutoPilot](https://help.cardpointers.com/article/5-autopilot) · [MaxRewards Best Card Live Activity](https://help.maxrewards.com/en/articles/15880013-introducing-the-best-card-live-activity-tracker) · [Kudos × Samsung (PR Newswire)](https://www.prnewswire.com/news-releases/kudos-partners-with-samsung-to-power-the-new-samsung-pay-benefits-shopping-assistant-302620794.html) · [Samsung Next on Kudos](https://www.samsungnext.com/blog/why-we-invested-in-kudos) · [Norte purchase protection guide](https://norteapp.io/guide/purchase-protection-credit-cards)
- **Merchants:** [Walmart Apple Pay (iclarified)](https://www.iclarified.com/101840/walmart-to-roll-out-apple-pay-at-us-stores-starting-august-24) · [Modern Retail](https://www.modernretail.co/technology/walmart-finally-starts-supporting-apple-pay-and-google-pay/) · Amazon Apple Pay: third-party blogs only (u)
- **Privacy:** [Anthropic API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) · [Anthropic: how long do you store my organization's data](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data) (30 days; search snippet only, (u)) · Gemini, not chosen: [Gemini API terms](https://ai.google.dev/gemini-api/terms) · [Gemini abuse monitoring](https://ai.google.dev/gemini-api/docs/abuse-monitoring) · [PCI truncated PAN FAQ](https://www.pcisecuritystandards.org/faq/articles/Frequently_Asked_Question/are-truncated-primary-account-numbers-pan-required-to-be-protected-in-accordance-with-pci-dss)
- **Rules:** [DubHacks '24 Hacker Guide](https://dubhacks.notion.site/The-DubHacks-24-Hacker-Guide-16da323fc21b4c6c8c0c2fbca1b7755e) (search summary) · DubHacks '25 Devpost (rubric and rules, reported by the judge reviewer via search; (u)) · [DubHacks '26 Devpost rules](https://dubhacks-2026.devpost.com/rules), [overview](https://dubhacks-2026.devpost.com/) and [dh26 tracks and schedule](https://dh26.dubhacks.co/) (read and confirmed Oct 14, 2026) · unofficial '26 schedule mirror: github.com/syedjafri06193/DubHacks-2026-Hack
- **Data:** [CardWise (MIT)](https://github.com/novus-tech-tw/CardWise) · [mcc-codes](https://github.com/greggles/mcc-codes)
