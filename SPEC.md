# Fine Print — Product Spec

**Version:** 1.0 (Oct 14, 2026) · **Event:** DubHacks '26, UW Seattle, Oct 17–18 · **Track:** Visa: Reimagine Shopping
**Status:** Approved direction after a 7-judge review (Visa lead, iOS engineer, interaction designer, rewards expert, privacy/App Review, hackathon veteran, student user). Items marked **(u)** are unverified and must be tested before we rely on them.

> This document is a plan, not code. Per DubHacks rules, all code is written during the event (12:30 PM Sat → 10:00 AM Sun).

---

## 0. TL;DR

**One line:** One tap on the back of your iPhone at any checkout, and the Dynamic Island tells you which of your cards is worth the most — cashback *and* the protections hidden in the fine print — then helps you actually use those protections later.

**Pitch (3 sentences):**
Every time you check out on your phone, you guess which card to use, and you never see the warranty, theft cover and fees buried in your card's fine print. Fine Print lets you double-tap the back of your iPhone on any checkout screen; within about 3 seconds the Dynamic Island shows the card (and how to pay) that's worth the most, with the trade-off spelled out, and you pay as usual. After you pay it saves the receipt and coverage dates, and if something breaks or is stolen it tells you honestly whether you're covered and builds the claim packet.

**Tagline:** *The perks buried in your card's fine print — at the moment you pay.*

---

## 1. Problem

- People don't know which card to use, and they almost never know their card's protections. Only ~30% of cardholders say they always maximize rewards (J.D. Power 2025). The CFPB estimates ~$500M in rewards forfeited per year.
- Rewards skew to the wealthy: an HBS working paper (Aug 2026) finds rewards move ~$9.2B/yr to households earning >$150K while lower-income households lose ~$88/yr. Students and first-gen/international students lose the most to fees and traps.
- Most online shopping happens on phones (~56% of 2025 holiday online spend was mobile, Adobe). Browser extensions (Kudos, CardPointers, MaxRewards) don't run inside shopping apps.
- iOS 27's Apple Pay sheet now shows rewards per card, but it doesn't recommend a card, ignores protections and fees, and doesn't help with saved-card checkouts or claims.

**Our wedge:** the moment of payment *inside mobile apps* + the *fine print* (protections, fees, how-to-pay) + *after-purchase follow-through*.

---

## 2. Target user and scenarios

**Primary persona:** a 21-year-old UW student with 2–3 cards (e.g., Apple Card as default, a Chase or Wells Fargo Visa, maybe Discover), shopping mostly in apps (Amazon, Target, Best Buy, Nike, DoorDash, StubHub, Shein/Temu, Expedia).

**Honest frequency:** for this user, ~15–25% of checkouts beat the default card by more than $1 in a quarter where categories line up (~5–10% otherwise). The real value is concentrated in 3–6 big purchases a year (protections), fee traps, and "how to pay" (e.g., Apple Card earns 3% / 2% / 1% depending on Apple Pay vs card number). Therefore the product must **always answer, but stay quiet when it doesn't matter.**

**Core scenarios (used in demo and tests):**

| # | Scenario | Expected answer |
|---|---|---|
| S1 | $1,499 laptop, electronics store checkout; wallet = Apple Card (default), Wells Fargo Active Cash, Chase Freedom Unlimited | **Switch:** Freedom Unlimited — $7.49 less cash, but +1 yr extended warranty and 120-day damage/theft cover (Active Cash and Apple Card have neither) |
| S2 | $180 shoes in the Nike app, Apple Pay visible | **Pay as usual — with Apple Pay:** Apple Card via Apple Pay earns 3% ($5.40) vs 1% as a typed card number |
| S3 | $249 AirPods, then "stolen at 6 weeks" | Purchase protection (theft) claim packet: receipt, card statement, police report, deadline |
| S4 | 14 months later: laptop display shows lines, no impact | **Covered** by extended warranty (manufacturer year expired); packet + notice deadline. Contrast: "Cracked from a drop → not covered" |
| S5 (engine only) | Foreign hotel booked direct (¥48,000 ≈ live rate), "pay in USD" offered | Pay in local currency with a no-foreign-fee card; Active Cash's 3% FTF makes it net negative |
| S6 (engine only) | User carries a balance | "Interest outweighs any reward — pay with debit or pay down the balance" |

---

## 3. Product principles

1. **One tap, not zero steps.** Be honest: one back-tap, a ~3 s wait, at most one swipe or card change. Never claim "zero steps."
2. **Always answer; vary the loudness.** The user asked, so silence feels broken. Loud (expand + sound) only when switching is worth it; a quiet ✓ when the default is best.
3. **Show the trade, never a blended number.** Cash on one line; protection as an estimate on another. Never add cash and expected value into one "+$".
4. **Private by design.** We look only when you tap. The screenshot is read and redacted on the phone; only order-summary text leaves it. Your card list stays on the phone.
5. **Honest about coverage.** Say "may be eligible," cite the clause, and say "not covered" when that's the truth. We never file or submit a claim for the user.
6. **Neutral engine, Visa-verified fine print.** We recommend whatever card is truly best; Visa cards get clause-level verification via the Visa Digital Benefits Platform.

---

## 4. Scope

| Priority | Feature |
|---|---|
| **P0 (must ship)** | Onboarding from a Settings → Wallet & Apple Pay screenshot (on-device OCR, confirm grid) · Back Tap → Shortcut → `CheckCheckoutIntent` → Live Activity in Dynamic Island with result in ≤3 s · Engine: cashback + protections (EV, differential) + fees + payment method, one card per order · Island states (§6) incl. "Pay as usual" and errors · Receipt capture (double-tap the order confirmation) · "What can I claim?" coverage check + claim packet PDF for S3/S4 · Demo store (mobile web, Stripe test mode + Apple Pay) · "What we sent" privacy sheet |
| **P1 (should)** | Visa Digital Benefits Platform (VDBP) as the source for Visa card benefits/Guide to Benefits clauses (fallback: public Guide to Benefits PDFs, labeled) · Read-only test on 2 real app checkouts (no purchase) · Money-leak audit at onboarding (3 questions: pay in full?, Q4 categories activated?, which card for foreign purchases) · AI eligibility checks (Renewed/refurbished, third-party seller, gift cards, AppleCare in cart) · Interactive snippet fallback (iOS 26 `SnippetIntent`) |
| **P2 (stretch)** | Visa Acceptance (Cybersource) sandbox payments + BIN lookup on the demo store to confirm which card product paid · Fee-trap guard (tuition 2.95%/4.25%, Venmo 3%, FX/DCC) beyond S5 · Visual Intelligence `IntentValueQuery` entry · Action Button setup flow |
| **Cut** | Browser extension · iMessage/Photon · Share extension · On-stage FX and rotating-category demos (engine only) · Push-to-start Live Activities |

---

## 5. User flows

### 5.1 Onboarding (~17 taps, first result ≤60 s, full setup ≤2.5 min)
1. **Add my cards:** app deep-links the user toward Settings (1 tap) → Wallet & Apple Pay (1) → take a screenshot → swipe back (1). *(Verified Oct 14 on a real iPhone: this screen lists each card's product name, thumbnail and last 4 on one screen.)*
2. **Choose screenshot** with the system photo picker (2 taps; no Photos permission). On-device OCR matches names to our local card catalog; Apple Cash and transit cards (Suica, Clipper) are dropped automatically → **Looks right** (1). Ambiguous cards: two thumbnails, one tap. The onboarding screenshot is never uploaded.
3. **First result before any setup:** a built-in sample checkout ($1,499 laptop) → **Check** (1) → a real island with the user's own cards.
4. **Money-leak audit (P1, 3 taps):** "Do you usually pay in full?" · "Activated this quarter's 5% categories?" · "Any card with foreign fees?" (pre-filled from catalog).
5. **Add shortcut:** "Add shortcut" (1) → Shortcuts "Add Shortcut" (1).
6. **Set up Back Tap:** looping 3 s clip of a finger double-tapping the back + path *Accessibility › Touch › Back Tap › Double Tap* (~6 taps).
7. **Practice tap:** on return, the sample checkout says "Double-tap the back now." Success → done.

### 5.2 Payment moment
1. User reaches the checkout screen in any app or mobile site (before tapping Apple Pay).
2. Double-tap the back → Shortcut: **Take Screenshot → Check Checkout** (our App Intent, runs in background).
3. Island shows **Checking…** within 0.5 s. On-device: OCR + "is this a checkout?" test. If not a checkout → "No checkout here · nothing uploaded."
4. Redacted order-summary text + the user's card **product IDs** (no last 4) go to our backend → structured cart → engine → result.
5. Island updates with an alert (auto-expands briefly) when a switch is recommended; quiet ✓ when the default is best.

### 5.3 Paying (instruction depends on what the screenshot shows)
- **Apple Pay visible:** "Tap Apple Pay, swipe to ••1234." The island shows the same card art and last 4 the Apple Pay sheet shows.
- **Saved card in the app (e.g., Amazon, which we believe doesn't take Apple Pay (u)):** "Change card to ••1234."
- **Default already best:** "✓ Pay as usual" (+ "use Apple Pay" when the payment method matters, S2).

### 5.4 After paying
- **Primary:** double-tap the back again on the order confirmation → logs merchant, total, order #, card last 4, item → **"Receipt saved · covered until <date>"**.
- **Backup:** one button in the expanded island: "I paid with ••1234."
- Never say "warranty registered": card benefits need no registration; we save evidence and dates.

### 5.5 "What can I claim?" (demo climax)
- In the app, open the purchase → "Something happened" → photo + one line ("lines on the screen, never dropped" / "stolen at the library").
- The AI checks, in order: return window → manufacturer warranty → card extended warranty → purchase protection (theft/damage, ~90–120 days) → merchant dispute.
- Output: **covered / may be eligible / not covered**, the cited Guide to Benefits section + version date, a document checklist, and a deadline countdown. Generates a claim packet PDF the user submits themselves (e.g., Visa eclaims web form, Chase/Card Benefit Services).
- Honest contrast built in: "Cracked from a drop at month 14 → not covered (accidental damage; damage cover ended at 120 days)."

---

## 6. Dynamic Island & Live Activity design

**Constraints (Apple HIG/ActivityKit):** compact sides ~52×37 pt each; expanded/Lock Screen up to ~371×160 pt; expanded shows only on long-press or briefly after an alert update; 4 KB payload; Live Activity has no network access; images must be bundled in the widget's asset catalog (send a `cardId`, not an image); one primary button; animations ≤2 s; avoid sensitive info on Lock Screen.

| State | Compact leading / trailing | Expanded copy | Sound/expand | Dismiss |
|---|---|---|---|---|
| Checking | Fine Print glyph / timer ring | "Reading checkout…" | none | becomes error at 8 s |
| Switch card | card art / "1234" in card color | "Pay with Freedom Unlimited ••1234" · "−$7.49 cash · +1 yr warranty · 120-day cover" · "Tap for why" | alert (expand + sound) | stale at 2 min, end at 3 min or on receipt |
| Default is best | card art / ✓ | "Pay as usual: ••5678 is best here" (+ "Use Apple Pay" if relevant) | quiet | 4 s |
| Low confidence | card art / "1234?" | "Probably Freedom ••1234 · couldn't confirm store type" | quiet | 3 min |
| Couldn't read | ⚠ / – | "Couldn't read this screen · scroll to the total and tap again" | quiet | 5 s |
| Not a checkout | glyph / – | "No checkout here · nothing uploaded" | quiet | 3 s |
| Offline / error | ⚠ / ↻ | "Offline · estimate from saved rules" or "Couldn't check · tap to retry" | quiet | 10 s |
| Receipt saved | shield ✓ / "1234" | "Receipt saved · covered until Oct 2028" | quiet | 4 s; Lock Screen 15 min |

- **Lock Screen:** card art + "Use card ending 1234" only — no amounts, no store. Hide content when Always-On (`isLuminanceReduced`).
- **"Why" sheet (tap):** cash vs protection rows, expected-value formula with editable assumptions, cited clause + "last verified" date, flip conditions ("Cash+ with Electronics selected would win"), "This was wrong."
- **Accessibility:** color is never the only cue (art + digits + shapes ✓ ⚠ shield); VoiceOver: "Use Freedom Unlimited, card ending 1 2 3 4. Adds one-year warranty, about 7 dollars less cash back."; Dynamic Type drops secondary lines first.
- **Phones without Dynamic Island:** Lock Screen Live Activity; alert banner when unlocked. Do not send a separate notification for the same update.
- **Explaining Apple's sheet:** "Apple shows cash back; Fine Print adds the fine print."

---

## 7. Recommendation engine

### 7.1 Inputs
- **Cart (from LLM over redacted OCR text):** merchant, merchant-of-record hints (Shop Pay, PayPal, marketplace seller), line items (name, price, condition: new/renewed, gift card, service plan), total, currency, payment options visible (Apple Pay / saved card / PayPal), "pay in USD" offers.
- **Wallet (on device):** card product IDs, network, plastic last 4 and Apple Pay last 4 (they can differ (u)), user answers (pays in full, activated categories, chosen categories), cap usage estimate.
- **Rules (catalog):** see §8.

### 7.2 Scoring (per order; one card per order)
For each card × payment method:
- **Cash value** = Σ eligible amount × rate (category rules, caps, activation, payment-method requirements such as Apple Card 3% only via Apple Pay at listed merchants), points × user-editable ¢/pt (default 1¢).
- **Protection value (expected, differential vs the runner-up):**
  - Extended warranty ≈ P(failure in extended window) × E[min(repair, price)] × P(claim approved) × P(user files). Demo defaults: 6% × $300 × 0.85 × 0.9 ≈ **$14** (range $8–25) on a $1,499 laptop. Fine Print raises P(user files) by saving receipts and deadlines.
  - Purchase protection ≈ ~1% × min(price, per-item cap) (e.g., Freedom Unlimited $500/item) ≈ $3–5.
  - Only counts if the item qualifies (new, from an authorized seller, valid U.S. manufacturer warranty, paid entirely with the card — no gift cards/BNPL split).
- **Fees:** foreign transaction fee on foreign-processed charges; DCC markup if "pay in USD"; card-funded P2P/tuition fees (P2).
- **Guards:** if the user carries a balance → recommend no rewards optimization ("interest outweighs rewards"); unknown activation/cap → conditional phrasing ("5% if activated and under cap") and ask once.
- **Decision:** switch only if (cash delta + protection EV − fees) beats the default by ≥ $1, or the item is ≥ $100 and protection differs; otherwise "Pay as usual." Suggest splitting an order only if gain ≥ $5.

### 7.3 Where AI is used (and why it isn't a lookup table)
1. Reading arbitrary checkout screens into a structured cart.
2. Eligibility judgments from the screen: "Renewed" listing (warranty excluded), third-party seller, gift cards, AppleCare already in cart, foreign merchant, DCC offer. Demo beat: switch to the Renewed version of the same laptop → the pick flips and cites the exclusion.
3. Turning Guide to Benefits text into cited, structured rules (offline during prep at the event, reviewed by a human).
4. The coverage check: matching an incident description + photo to benefit clauses, producing covered / may be eligible / not covered with citations.

### 7.4 Output (to the island and "Why" sheet)
`cardId`, payment method, instruction type (apple-pay-swipe / change-saved-card / pay-as-usual), cash delta, protections list with EV and limits, fees, confidence (verified / inferred / unknown), two short reasons, flip conditions, sources with version dates.

---

## 8. Data

### 8.1 Card set (15)
Chase Freedom Unlimited, Freedom Flex, Freedom Rise, Sapphire Preferred, Prime Visa · Wells Fargo Active Cash · Citi Double Cash · Capital One Savor/Savor Student, Quicksilver · Discover it (Student) · Apple Card · Amex Blue Cash Everyday, Amex Gold · U.S. Bank Cash+ · BofA Customized Cash Rewards.
Note networks: Freedom Flex, Double Cash and Apple Card are Mastercard; don't present their perks as Visa benefits. Capital One publishes separate benefit guides per network version — capture the network logo at onboarding.

### 8.2 Card catalog fields
- **Card:** issuer, product, network, tier (Signature/Infinite/World Elite), annual fee, point currency, default ¢/pt, base rate, foreign transaction fee.
- **Category rules (each):** category, rate, MCC list or merchant list, exclusions (e.g., Walmart/Target not grocery at Chase), payment-method requirement (Apple Pay only), cap amount + period + shared-cap group, needs activation/user pick + deadline + retroactive?, valid from/to.
- **Merchant exceptions:** e.g., Walgreens single-item carts for Apple Card 3%.
- **Protections (each):** type (extended warranty, purchase protection, return, price, cell phone), rule (e.g., +1 yr on warranties ≤3 yrs), limits (per item/per year), payment requirement, notice and document deadlines, administrator, claim URL/phone, exclusions.
- **Sources:** Guide to Benefits URL, version date, last verified date, verified-by.
- **Per user (on device only):** plastic last 4, Apple Pay last 4, chosen categories, activation status, estimated cap used, pays-in-full flag.

### 8.3 Merchant table (~40 merchants)
domain/app name → likely MCC/category, issuer-specific exclusions, Apple Pay accepted?, merchant-of-record notes (Shop Pay = the store; PayPal may post as "PAYPAL *" → low confidence; Expedia "pay now" = Expedia; pay-at-property = foreign hotel), confidence.

### 8.4 Sources & licenses
- Seed earn rates from `novus-tech-tw/CardWise` `cards.json` (MIT) — data only, notice kept in `THIRD_PARTY.md`; hand-verify every demo card against issuer pages.
- Benefits: Visa Digital Benefits Platform (Visa cards, P1) + public Guide to Benefits PDFs (dated).
- MCC reference: `greggles/mcc-codes` (Unlicense).

---

## 9. Architecture

### 9.1 iOS app (SwiftUI, iOS 26+, demo device iOS 27)
- **Shortcut (2 actions):** Take Screenshot → Check Checkout.
- **`CheckCheckoutIntent`** (`LiveActivityIntent`, `supportedModes = .background`, `IntentFile` image parameter):
  1. `Activity.request` → "Checking…" (stale date 15 min).
  2. Downscale image; on-device OCR (Vision `RecognizeDocumentsRequest` / `VNRecognizeTextRequest`); checkout test; redaction (Luhn-valid digit runs, CVV, names, emails, phones, "Ship to" blocks, one-time codes, notification banner strip).
  3. POST redacted text + card product IDs to backend (6 s timeout). On timeout: local rules on cached catalog → "estimate."
  4. `update(_:alertConfiguration:)` with `{cardId, last4, instruction, cashDelta, protections, reasons[2]}` (<1 KB).
- **`ReceiptIntent`** (same pattern) for the order confirmation; **`MarkPaidIntent`** button as backup.
- **Widget extension:** Live Activity views per §6; card art bundled in asset catalog.
- **App screens:** onboarding, wallet, purchases, "Why" sheet, "What we sent," coverage check + claim packet.
- **Storage:** wallet + purchases on device (Keychain/SwiftData); purchases synced to backend only when the user runs a coverage check.
- **Fallback if Live Activity start fails:** interactive snippet (`SnippetIntent`, iOS 26) with the same content.

### 9.2 Backend (proxy + services)
- `/analyze`: redacted text + card IDs → LLM (paid-tier Gemini Flash-class, JSON output) → cart → engine → result. No request bodies logged.
- `/benefits`: VDBP Card Product Benefits → Benefit Details → Benefit File (Guide to Benefits) for Visa cards; cached; overlaid with hand-verified clauses (labeled).
- `/coverage`: incident + photo + purchase → covered/may be eligible/not covered + citations → claim packet PDF.
- API keys only on the server; per-device rate limit; budget cap; App Attest if time allows.

### 9.3 Demo store (mobile web)
- Electronics store + Nike-style store pages; checkout with Apple Pay via Stripe test mode on a registered HTTPS domain.
- P2: Visa Acceptance (Cybersource) sandbox `pts/v2/payments` + BIN lookup to confirm card product → stronger proof of purchase.

### 9.4 Latency budget (target ≤3 s median)
Screenshot + intent launch ~0.5 s · OCR + redaction ~0.4 s · network + LLM ~1.5 s · engine + island update ~0.2 s. Cache demo responses for replay mode.

---

## 10. Privacy & safety

- **What leaves the phone:** only redacted order-summary text (e.g., "Electronics store, $1,499.00, 1 item: 14-inch laptop (new)") and card product IDs. Never the screenshot, never last 4, never the onboarding screenshot.
- **"What we sent" sheet:** shows the exact payload for every check (strongest trust demo).
- **Consent screen** names the AI provider and offers "Keep on device" (local rules only).
- **Retention copy:** "Screenshots are processed in memory and never saved. Purchases you save stay until you delete them. Our AI provider may keep logs for up to 55 days." (Paid-tier Gemini; never the free tier.)
- **Accidental triggers:** on-device checkout test first; nothing is uploaded from non-checkout screens.
- **Lock Screen:** no amounts or store names.
- **Claims:** free; uses only facts the user confirms; the user submits; wording "may be eligible"; never "you're covered," "filed," "guaranteed," or "best card."
- **Disclaimer:** "Estimates only, not financial, legal or insurance advice. Values use public card terms (last checked [date]) and the assumptions shown. Fine Print can't see your caps, activations or balances. Warranty and purchase protection are insurance benefits with limits and exclusions; only your card's benefit administrator decides claims. If you carry a balance, interest will likely cost more than any reward. Not affiliated with or paid by any issuer."
- **Onboarding privacy copy:**
  > We only look when you double-tap. Never in the background.
  > Card numbers, names and addresses are blurred on your iPhone first.
  > Only the blurred order summary is sent for analysis, then deleted.
- **Judge answer — "Aren't you sending my payment screen to Google?"** "No. The screenshot never leaves your phone. On-device OCR blurs anything that identifies you; only something like 'Target, $84.12, 3 items' is analyzed. Tap 'What we sent' to see it." *(Say this only if on-device redaction is actually built.)*

---

## 11. Visa track fit

- **Commerce journey covered:** decision (which card + how to pay) → checkout (Apple Pay / saved card) → post-purchase (receipts, coverage check, claims). Generative AI does the reading, eligibility judgment and claim reasoning.
- **Visa APIs that matter:** Visa Digital Benefits Platform is the source of truth for Visa card benefits and Guide to Benefits clauses (Card Product Benefits, Benefit Details, Benefit File). Stretch: Visa Acceptance (Cybersource) payments + BIN lookup on the demo store. Skip VDBP Card Account endpoints (need PAN/PCI).
- **Neutrality framing:** the engine recommends whatever is truly best. The demo's winning card is a Visa (Freedom Unlimited vs Active Cash — both Visa Signature per our notes, re-verify): "same network, same tier, different fine print." Protections are issuer-optional, so we say: "Visa built the benefit tiers; Fine Print shows them at the moment you buy."
- **Why Visa benefits:** benefits get used (engagement), fewer misfiled claims and chargebacks, and an inclusive story — protecting students from fees and interest, not just maximizing points for the wealthy.
- **Roadmap line only:** the same engine could pick the credential for AI shopping agents (Visa Intelligent Commerce) or set rules for Visa Flexible Credential. Not built.

---

## 12. Demo & video

### 12.1 Demo wallet
Apple Card (default, Mastercard), Wells Fargo Active Cash (Visa Signature), Chase Freedom Unlimited (Visa Signature). Use team-owned or sample card art; no real card numbers on screen.

### 12.2 Live demo script (3:00)
1. **0:00** Cold open: real hand double-taps the back on the laptop checkout → island: "Pay with Freedom Unlimited ••1234 · −$7.49 cash · +1 yr warranty."
2. **0:20** Problem in one line + the "nobody reads the fine print" stat.
3. **0:35** Onboarding speed-run: one Settings screenshot → wallet appears, counter "1 screenshot · 0 digits typed."
4. **1:00** Apple Pay: island art matches the sheet's art → swipe → double-click → Face ID → double-tap the confirmation → "Receipt saved · covered until Oct 2028."
5. **1:30** Quiet montage: Nike app → "✓ Pay as usual — use Apple Pay (3%)"; Instagram feed → "No checkout here · nothing uploaded."
6. **1:50** Renewed laptop → pick flips, clause cited (AI eligibility judgment).
7. **2:10** "14 months later" (labeled staged): display lines, no impact → "May be eligible: extended warranty, notify by <date>" + packet; "Cracked from a drop → not covered."
8. **2:40** Numbers: latency, read accuracy, scenario accuracy incl. misses; what's real vs simulated.

### 12.3 Video (≤2:00, captions burned in)
Same beats compressed; one continuous real-time take for the core flow; picture-in-picture of the hand doing the Back Tap; latency timer on screen; strip of Visa API request IDs when VDBP is used. Record footage at ~7:30 PM Sat and ~3 AM Sun so the morning is only editing. Verify Friday that QuickTime capture shows the Dynamic Island and Apple Pay sheet (u).

### 12.4 Real vs simulated (disclose on Devpost and in video)
Real: on-device OCR, engine, island, onboarding, Apple Pay sheet, read-only real-app checkouts. Simulated: Stripe test payments, "14 months later," claim submission (packet only).

---

## 13. Success metrics

| Metric | Target | Measurement |
|---|---|---|
| Tap → "Checking…" | ≤0.5 s | screen recording timestamps |
| Tap → result | ≤3 s median, ≤4 s P90 | 20 timed runs on venue network |
| Checkout read (merchant + total) | ≥95% | 30 labeled screenshots from ~10 apps |
| Line items + eligibility flags | ≥85% | same set |
| Onboarding read | 100% of cards on ≥2 phones (≥1 non-Chase issuer), ≤10 s | teammates' Settings screenshots |
| Recommendation accuracy | ≥90% of 20 scenarios | `scenarios.json` written by a teammate who doesn't write the engine, committed before engine code |
| Effort at payment | 1 tap + ≤1 swipe/change | count in demo |
| One-time setup | ≤2.5 min, first result ≤60 s | stopwatch with a non-teammate |
| Demo reliability | 10 consecutive clean runs | rehearsal log |
| Privacy | 0 screenshots uploaded; 0 card numbers stored | "What we sent" log + code check |

---

## 14. Plan

### 14.1 Team
- **A — ML/CV:** on-device OCR + redaction, checkout detection, cart parsing prompts, coverage-check reasoning, accuracy test set.
- **B — Backend/engine:** catalog + merchant table, engine, `/analyze`, `/benefits` (VDBP), `/coverage` + claim PDF.
- **C — iOS lead:** App Intents, Live Activity/widget, Shortcut, onboarding plumbing.
- **D — Design/web/story:** island + app UI with C, demo store (Stripe + Apple Pay), Devpost draft owner, pitch, video.

### 14.2 Before Saturday (no code: accounts, data, designs, docs)
- **Settle the roster tonight:** the repo README lists 5 GitHub handles; DubHacks allows up to 4. The fifth person should come off the README and collaborators and not commit code.
- **Signing:** enroll in the paid Apple Developer Program today (free teams can't share an App ID; free profiles expire in 7 days) — or have one Mac sign everything. Install Xcode 27, enable Developer Mode on the demo iPhone (Dynamic Island required; Action Button needs iPhone 15 Pro+).
- **Accounts/keys:** paid-tier Gemini key; Stripe test mode with Apple Pay domain registered; Visa Developer project with two-way SSL hello-world and VDBP activated; hosting domain.
- **Data:** 15-card catalog with sources and dates; ~40-merchant table; 30 labeled checkout screenshots; Settings screenshots from teammates; `scenarios.json` (20 scenarios, hand-computed by one teammate); Guide to Benefits PDFs for the demo cards.
- **Design:** island states (§6) in Figma, onboarding, "Why" sheet, coverage check.
- **Verify by hand:** Back Tap → Take Screenshot captures the app underneath on iOS 27; QuickTime shows the island.
- **Discord questions:** Do Visa judges visit tables if we add a side track? Can tracks change after the draft? Video length limit? Which deadline is right (Devpost 10:00 AM vs site 10:30 AM — treat 10:00 as hard)?
- **Repo hygiene:** add Xcode entries to `.gitignore` (xcuserdata, DerivedData, *.xcuserstate); add `THIRD_PARTY.md`; update README to describe Fine Print (current README describes a different product).

### 14.3 Event timeline
| Time | Milestone | Kill switch |
|---|---|---|
| 12:30 PM Sat | Tag `event-start`; B commits `scenarios.json`; contracts frozen | — |
| 1:30 PM | D at Visa workshop | — |
| 2:30 PM | **Riskiest-chain test:** Back Tap → screenshot → intent → Live Activity with alert, over a Safari Apple Pay page, captured in QuickTime | No island → `SnippetIntent` fallback |
| 3:30 PM | Chain works end to end with a fake result | — |
| 7:30 PM | Real OCR + engine on demo store; first footage recorded | OCR <80% → per-merchant parsers for demo merchants |
| 9:30 PM | Side-track decision | — |
| 10:00 PM | **Devpost draft submitted** (D owns, B backup); all members accepted invites | Hard deadline 10:30 PM |
| 1:00 AM | Receipt capture + coverage check + claim PDF | Static claim template |
| 1:30–5:30 AM | A & B sleep | — |
| 3:00 AM | Feature freeze; C & D film until 4:00, sleep until 7:30 | — |
| 5:30 AM | A & B: 10 clean runs, accuracy tests, write-up | — |
| 8:45 AM | Video final | — |
| 9:00 AM | Upload over hotspot | — |
| 9:30 AM | Submit | **10:00 AM hard deadline** |

### 14.4 Cut order (first → last)
Cybersource → fee-trap guard extras → Visual Intelligence → money-leak audit → Renewed eligibility beat → VDBP (fall back to public PDFs) → receipt double-tap (keep button) → coverage-check photo analysis (keep text) → claim PDF styling.
**Never cut:** Back Tap → island with the cash-vs-protection trade, and "Pay as usual."

### 14.5 GitHub (70/30 rule)
Everyone commits at least hourly from their own account; merge commits, not squash; data prep committed with timestamps; no API keys in the app or repo.

---

## 15. Risks & open questions

| Risk | Mitigation |
|---|---|
| Live Activity start from a Shortcut-run intent fails on iOS 27 (docs say it works; DTS confirms) | 2:30 PM test; `SnippetIntent` fallback |
| "Take Screenshot" behavior on iOS 27 / Shortcuts banner appears in screenshot (u) | Test Friday; crop top strip |
| Island hidden while Apple Pay sheet is open (u) | Deliver the result before the user taps Apple Pay; card art matches the sheet |
| Apple Pay last 4 differs from plastic last 4 (u which one Settings shows) | Store both; confirm once when a receipt shows an unknown last 4 |
| Latency on venue Wi-Fi | On-device OCR, text-only upload, cached replay mode, two hotspots |
| Wrong benefit data | Hand-verify demo cards; version + "last verified" dates; confidence badges |
| Judges: "iOS 27 already shows rewards" | "Apple shows cash back; we add protections, fees, how to pay, and claims" |
| Judges: "CardPointers has Live Activities / screenshot reading" | Theirs are location-triggered or multi-step Visual Intelligence; ours is one tap at the payment screen, content-aware, total value + coverage follow-through |
| Visa-only = no in-person judging | Video is first-class; consider a side track after Discord answers |
| Team roster (5 names) | Resolve before Saturday |

**Unverified (test or confirm):** Take Screenshot on iOS 27; island during Apple Pay and in QuickTime; Amazon/Walmart/Best Buy in-app Apple Pay; VDBP sandbox contents for our demo cards; Active Cash and Freedom Unlimited tiers; exact notice/claim deadlines in the Freedom Unlimited Guide to Benefits; Cybersource Apple Pay setup time; whether adding a side track changes Visa judging.

---

## 16. Business model (one line)
Free for consumers; revenue from issuers/Visa for benefit engagement via the Digital Benefits Platform (never paid ranking), plus an optional claim concierge fee only when a claim pays.

---

## 17. Sources
- Apple: [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities) · [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) · [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent) · [App Intents supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes) · [Interactive snippets](https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets) · [Vision RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) · [Back Tap with Shortcuts](https://support.apple.com/guide/shortcuts/run-shortcuts-tapping-iphone-apd897693606/ios) · [Visual Intelligence](https://developer.apple.com/documentation/visualintelligence/integrating-your-app-with-visual-intelligence) · [Apple Card Daily Cash merchants](https://support.apple.com/en-us/120400)
- iOS 27 Apple Pay: [9to5Mac](https://9to5mac.com/2026/09/27/ios-27-makes-it-easier-to-switch-between-apple-pay-cards/)
- Visa: [Digital Benefits Platform](https://developer.visa.com/capabilities/vdbp) · [VDBP how-to](https://developer.visa.com/capabilities/vdbp/docs-how-to) · [Extended Warranty](https://usa.review.visa.com/supporting-info/extended-warranty-protection.html) · [DCC](https://www.visa.com/en-us/personal/travel/dynamic-currency-conversion) · [Visa Intelligent Commerce](https://developer.visa.com/capabilities/visa-intelligent-commerce) · [Cybersource BIN Lookup](https://developer.cybersource.com/docs/cybs/en-us/bin-lookup/developer/all/rest/bin-lookup.html)
- Benefits: [Chase Freedom benefits](https://www.chase.com/personal/credit-cards/education/chase-cards/chase-freedom-benefits-guide) · [Wells Fargo Active Cash guide](https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/) · [Consumer Reports laptop reliability](https://www.consumerreports.org/electronics-computers/laptops-chromebooks/most-reliable-laptop-brands-a1961456199/) · [Food delivery rewards rules (NerdWallet)](https://www.nerdwallet.com/credit-cards/learn/credit-cards-and-food-delivery-what-are-the-rules-on-rewards-rates)
- Demand: [J.D. Power 2025 via Financial Brand](https://thefinancialbrand.com/news/payments-trends/card-satisfaction-muted-by-surcharges-rewards-confusion-and-debt-levels-192110) · [CFPB Circular 2024-07](https://www.consumerfinance.gov/compliance/circulars/consumer-financial-protection-circular-2024-07-design-marketing-and-administration-of-credit-card-rewards-programs/) · [HBS Working Knowledge](https://www.library.hbs.edu/working-knowledge/how-credit-card-rewards-became-multibillion-dollar-wealth-transfer) · [Adobe 2025 holiday mobile share](https://www.supplychain247.com/article/online-holiday-spending-2025-adobe-data/e_commerce) · [UW tuition payment fees](https://finance.uw.edu/sfs/tuition/payment)
- Privacy: [Gemini API terms](https://ai.google.dev/gemini-api/terms) · [Gemini abuse monitoring](https://ai.google.dev/gemini-api/docs/abuse-monitoring) · [PCI truncated PAN FAQ](https://www.pcisecuritystandards.org/faq/articles/Frequently_Asked_Question/are-truncated-primary-account-numbers-pan-required-to-be-protected-in-accordance-with-pci-dss)
- Rules: [DubHacks '26 Devpost](https://dubhacks-2026.devpost.com/rules)
- Data: [CardWise (MIT)](https://github.com/novus-tech-tw/CardWise) · [mcc-codes](https://github.com/greggles/mcc-codes)
