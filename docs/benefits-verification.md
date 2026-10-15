# Demo-card benefits verification (gate G5)

**Checked:** 2026-10-14 by Claude (session `card-benefits`), for SPEC v2.0 §8.1, §14.2 (G5) and §15.3.
**Needs:** a human review by B or D before the Fri 6 PM gate (§7.3 item 3). Every quote below can be checked at its URL.

**Method.** I read every source in the browser. The two PDFs were parsed in the page with pdf.js; nothing was downloaded. Quotes are verbatim and 15 words or fewer. Page numbers are the printed page numbers. The issuer documents have no numbered sections, so "section" means the heading and page.

**Status labels.** **verified**: an issuer or network primary source states it. **partial**: only secondary sources state it, or the primary source covers it only in part. **unverified**: I couldn't find a source.

---

## 1. Gate G5 answers

| # | Question | Answer | Status |
|---|---|---|---|
| 1 | Does Active Cash have extended warranty or purchase protection? | **No.** The Wells Fargo Guide to Benefits (in effect 09/15/2025) lists 7 benefits: cell phone protection, emergency card replacement, auto rental CDW, travel assistance, Roadside Dispatch, Visa Signature Concierge and Luxury Hotel Collection. The full page text has **0 matches** for "warrant", "purchase protection" and "purchase security". The card page's "Added Protections" list has neither. **Source of the conflict:** CardRatings (updated Oct 1, 2026) lists "extended warranty protection" among generic Visa Signature benefits. Visa's network pages describe benefits that issuers choose whether to offer, and Wells Fargo's own guide doesn't include it. | verified |
| 2 | Does Apple Card have any protections in 2026? | **No purchase protection or extended warranty.** The Apple Card Customer Agreement (PDF dated 2026-09-18) has no protection terms. Mastercard's "Mastercard Benefits for Apple Card Customers" page lists only Zero Liability, ID Theft Protection, Travel & Lifestyle Services, Priceless Experiences and Priceless Golf. | verified (public sources; the in-Wallet benefits list was not checked) |
| 3 | Is Freedom Unlimited's $500 limit per item or per claim? | **Per item**, plus "a maximum of $50,000 per Account". The guide states no per-claim cap. The payout is the lesser of the repair cost, the replacement cost, the amount charged to the card, and $500. The same applies to Freedom Rise, which uses the same guide. | verified |
| 4 | What are the notice deadlines? | **Chase purchase protection:** notify within **90 days of the loss**; send documents within **120 days of the loss**. **Chase extended warranty:** notify within **90 days of product failure**; send documents within **120 days of the product failure**. Every Chase deadline adds "or as soon as reasonably possible". **Wells Fargo cell phone protection:** notify within **60 days**; send documents within **120 days of the loss**. | verified |

**Outcome for S1:** "Use Freedom: adds a warranty year + $500 theft cover" is fully verified. The S1 copy can stay as written.

**New finding that affects the demo:** Chase **doesn't exclude refurbished items that come with a warranty** (see §4.3). The Renewed beat's line "Renewed item: no card adds a warranty" is therefore not a fact we can state as written. See Proposed SPEC edits.

---

## 2. Sources

| ID | Document | Version date | URL | Read as |
|---|---|---|---|---|
| CH-GTB | *Guide to benefits: Chase Freedom Unlimited®, Chase Freedom Rise® and Chase Freedom Student, Visa Platinum and Visa Signature®* (BGC11366, 28 pp.) | "in effect as of 10/1/24"; server Last-Modified 2026-05-13 | https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf | PDF, pdf.js in the browser. Both live card pages (FU and Rise) link to this exact file as "Guide to Benefits". |
| CH-FU | Chase Freedom Unlimited card page | live 2026-10-14 | https://creditcards.chase.com/cash-back-credit-cards/freedom/unlimited | HTML |
| CH-RISE | Chase Freedom Rise card page | live 2026-10-14 | https://creditcards.chase.com/cash-back-credit-cards/freedom/rise | HTML |
| WF-GTB | *Wells Fargo Active Cash® Card Guide to Benefits* | "in effect as of 09/15/2025"; Additional Terms "Effective 09/01/2024"; page code DT1-06202026 | https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/ (redirects to /credit-cards/documents/active-cash-benefits/) | HTML; this is Wells Fargo's guide (no PDF is linked) |
| WF-AC | Wells Fargo Active Cash card page | live 2026-10-14 | https://creditcards.wellsfargo.com/active-cash-credit-card/ | HTML |
| AP-CA | *Apple Card Customer Agreement* (Goldman Sachs Bank USA, 19 pp.) | no printed date; PDF created 2026-09-18; Last-Modified 2026-10-06 | https://www.goldmansachs.com/terms-and-conditions/Apple-Card-Customer-Agreement.pdf | PDF, pdf.js in the browser |
| AP-3PCT | Apple Support: *Learn how to get 3% Daily Cash back when you use Apple Card with Apple Pay* (HT 120400) | Published Sep 25, 2026 | https://support.apple.com/en-us/120400 | HTML |
| AP-BEN | Apple Card Benefits | live 2026-10-14 | https://learn.applecard.apple/benefits | HTML |
| MC-AP | Mastercard: *Mastercard Benefits for Apple Card Customers* | live 2026-10-14 | https://www.mastercard.com/us/en/personal/find-a-card/card-benefits/apple-card-benefits.html | HTML (linked from AP-BEN) |
| DS-STU | Discover student credit cards page (Discover it Student Cash Back) | live 2026-10-14 | https://www.discover.com/credit-cards/student-credit-card/ | HTML |
| 2nd-CR | CardRatings Active Cash review (secondary; the conflicting source) | updated Oct 1, 2026 | https://www.cardratings.com/credit-card/wells-fargo-active-cash-visa-credit-card.html | HTML |
| 2nd-DS | Doctor of Credit; Clark Howard via WSB-TV (secondary; Discover's 2018 removal) | 2018 | https://www.doctorofcredit.com/discover-remove-many-card-benefits-february-28th-2018/ · https://wsbtv.com/news/clark-howard/discover-is-eliminating-these-5-credit-card-benefits-in-2018/705069034 | search summaries only; not opened |

---

## 3. Earn rates (what the engine uses)

| Card | Rule | Rate | Payment method | Source · section | Quote | Status |
|---|---|---|---|---|---|---|
| Apple Card | Apple Pay, anywhere | 2% | apple_pay | AP-CA · Daily Cash Program › How You Earn Daily Cash, p. 6 | "Apple Pay Purchase Transactions 2% of the transaction amount" | verified |
| Apple Card | base (titanium card or virtual card number) | 1% | card | AP-CA p. 6; AP-BEN | "All other Purchase Transactions 1% of the transaction amount" · "when you use the titanium card or your virtual card number" | verified |
| Apple Card | merchant `apple` | 3% | any (excludes third-party wallets and resellers) | AP-CA p. 6–7 | "Goods or services purchased directly from Apple." · "if you make your payment through a third-party wallet" | verified |
| Apple Card | merchant `nike` | 3% | apple_pay | AP-3PCT, Nike footnote | "using Apple Card with Apple Pay at Nike stores, Nike.com, the Nike mobile app" | verified |
| Apple Card | merchant `walgreens` | 3% | apple_pay | AP-3PCT, Walgreens footnote | "Apple Pay at Walgreens and Duane Reade online, in the Walgreens app, and in stores" | verified |
| Apple Card | other 3% merchants (not in our §8.3 list) | 3% | apple_pay | AP-3PCT | Ace Hardware, Booking.com (via Apple's link), ChargePoint, Duane Reade, Exxon/Mobil, Hertz, Uber, Uber Eats | verified (list as of Sep 25, 2026; "Merchant offers may change at any time") |
| Active Cash | base | 2% | any | WF-AC, hero and footnote 2 | "unlimited 2% cash rewards on purchases" | verified |
| Freedom Unlimited | base | 1.5% | any | CH-FU, Earn Rewards + offer details | "Earn 1.5% on all other purchases." | verified |
| Freedom Unlimited | category `dining` (incl. takeout, eligible delivery) | 3% | any | CH-FU, offer details | "drugstores and dining at restaurants including takeout and eligible delivery services" | verified rate; **P2 per §8.1** |
| Freedom Unlimited | category `pharmacy` (Chase: "drugstores") | 3% | any | CH-FU, offer details | same quote | verified rate; **P2 per §8.1** |
| Freedom Unlimited | Chase Travel | 5% | any | CH-FU | "Earn 5% on travel purchased through Chase Travel" | verified; not modeled (no merchant) |
| Freedom Rise | base | 1.5% | any | CH-RISE | "Establish credit and earn 1.5% cash back on all purchases" | verified |
| Discover it Student | base | 1% | any | DS-STU | "Plus, earn 1% cash back on all other purchases." | verified |
| Discover it Student | rotating quarterly categories | 5% | any | DS-STU | "up to the quarterly maximum when you activate" | verified; not modeled (needs activation and a cap) |

Notes:
- Apple's Walgreens footnote excludes online or in-app orders "with more than one item in the cart", because Apple Pay isn't offered there. The engine's `apple_pay` path already needs an Apple Pay button on screen, so this is consistent.
- Chase decides "dining" and "drugstores" by merchant category code. Whether Walgreens and DoorDash code that way is **partial**: it's the usual coding, but I found no Chase statement about these merchants. Adding the two rules changes no expected result in §15.4: in scenario 19, FU ties Apple Card at 3% and the tie goes to the default.
- Networks: Apple Card is **Mastercard** (AP-CA: "Mastercard International, the payment network associated with your Account"). Active Cash is **Visa Signature** (WF-AC: "Exceptional Visa Signature® privileges"). Freedom Unlimited and **Freedom Rise are Visa**: CH-GTB's title covers Rise under "Visa Platinum and Visa Signature", which settles the (u) in §8.1. Discover is **Discover**.
- Annual fee is $0 on all five (CH-FU "$0 annual fee", CH-RISE "$0 Annual Fee", WF-AC "$0 annual fee", DS-STU "No annual fee", AP-BEN "designed to have no fees at all"). Foreign transaction fees: Apple Card $0 (AP-BEN). Not checked for the other four.

---

## 4. Protections by card

### 4.1 Apple Card: none

| Fact | Source | Quote | Status |
|---|---|---|---|
| No purchase protection or extended warranty terms in the agreement. The only "warrant" match is "represent and warrant" in Payment Authorization. | AP-CA (all 19 pages searched) | — | verified |
| The Mastercard benefits for Apple Card are Zero Liability, ID Theft Protection, Travel & Lifestyle Services, Priceless Experiences and Priceless Golf. None is purchase protection or extended warranty. | MC-AP | "Mastercard Benefits for Apple Card Customers" | verified |
| Apple's own benefits page points only to Mastercard benefits "like identity theft protection" | AP-BEN | "you have access to Mastercard benefits, like identity theft protection" | verified |
| Hertz "discounted loss damage waiver" is a paid add-on, not a protection | AP-3PCT | "Discounted loss damage waiver ($16.95/day + tax)" | verified (not modeled) |

**Not confirmed:** Wallet's in-app "Apple Card Benefits" list (needs a device with Apple Card), and Apple Card's Mastercard tier (World or World Elite). Neither changes the answer.

### 4.2 Wells Fargo Active Cash: cell phone protection only

**Extended warranty and purchase protection: none** (see G5 #1). Cell phone protection isn't counted by the engine (§7.2 rule 3). It's recorded here for completeness.

| Field | Value | Source · section | Quote | Status |
|---|---|---|---|---|
| Covers | Damage, theft, involuntary and accidental parting of phones on the wireless bill | WF-GTB · Cellular Telephone Protection › What is Covered | "Damaged, Stolen, or is unrecoverable due to Involuntary and Accidental Parting" | verified |
| Eligibility | Pay the monthly wireless bill with the card; coverage starts the month after it posts | same | "You must pay the monthly Wireless Bill using Your Covered Card" | verified |
| Per claim | $600, minus a $25 deductible | › Maximum Coverage per Cell Phone; › Deductible | "$600 per claim." · "$25 per claim will be deducted" | verified |
| Per account | 2 paid claims and $1,200 per 12-month period | › Maximum Coverage per Covered Card | "A maximum of 2 paid claims per 12 month period." | verified |
| Exclusions (selected) | Lost or mysteriously disappeared phones; cosmetic damage that doesn't affect function; tablets and smartwatches; accessories; phones in a carrier's custody; resale or commercial use | › What is NOT Covered | "Any Cell Phone that is lost (i.e., mysteriously disappears)" | verified |
| Notice | 60 days from the loss | › How to File a Claim | "notify us of the loss within sixty (60) days of the loss" | verified |
| Documents | 120 days from the loss | same | "submitted within one hundred twenty (120) days of the loss" | verified |
| Administrator | Virginia Surety Company, Inc. (Assurant); 1-800-316-8051; https://mycardbenefits.assurant.com | › How to File a Claim; Additional Terms | "call 1-800-316-8051 ... or visit https://mycardbenefits.assurant.com" | verified |

### 4.3 Chase Freedom Unlimited and Freedom Rise (same guide, CH-GTB)

Both card pages link to the same BGC11366 PDF. Its cover lists "Chase Freedom®, Chase Freedom Unlimited®, Chase Freedom Rise® and Chase Freedom Student". The live card pages (checked 2026-10-14) still match the guide: CH-FU says "against damage or theft up to $500 per item", and both pages say "Purchase Protection – coverage period is 90 days" for New York. The 2024 guide is therefore still current.

**Purchase protection** (CH-GTB pp. 9–11; form code `PP_CON_$500 ITEM_$50K ACCT_20240311`)

| Field | Value | Quote | Status |
|---|---|---|---|
| Covers | Theft, damage, involuntary and accidental parting | "protects an item You purchase against theft, damage, or Involuntary and Accidental Parting" | verified |
| Window | 120 days from purchase; **NY: 90 days** | "within one hundred twenty (120) days (ninety (90) days for New York residents)" | verified |
| Per item | **$500** | "$500 per item and a maximum of $50,000 per Account" | verified |
| Per claim | none stated | — | verified (absence) |
| Per account | $50,000 | same quote | verified |
| Payout | Lesser of repair cost, replacement cost, **amount charged to the card or rewards (excluding shipping)**, $500 | "The amount charged to the Covered Card and/or redeemable Rewards used" | verified |
| Pairs/sets | Only the lost piece is paid, unless the set can't be replaced piece by piece | "You will only be reimbursed for the item that was stolen, damaged" | verified |
| Payment | All or part of the price on the card, or with Chase rewards | "charge all or a portion of the cost of the eligible item" | verified |
| Basis | Secondary to other insurance (homeowner's, renter's…). Covers their deductibles | "Coverage is secondary and in excess of valid and collectible insurance" | verified |
| Refurbished | **Covered if it comes with a warranty.** Used or pre-owned items are excluded | "refurbished items will not be considered used or pre-owned if accompanied by a warranty" | verified |
| Other exclusions | Living animals and plants; antiques and collectibles; motorized vehicles; computer software; resale or commercial use; lost or "mysteriously disappear[ed]" items; items in a common carrier's care; unattended items in baggage on a common carrier; abuse, fraud, war, normal wear and tear, flood, earthquake, inherent defects; mis-delivery or voluntary parting; medical equipment; perishables, consumables and rechargeable batteries; traveler's checks, cash, tickets, cards | "Items that are lost, or that “mysteriously disappear,”" | verified |
| Theft from the delivery location | Claim with the carrier or retailer first | "You are first required to file a claim with the common carrier and/or retailer" | verified |
| Police report | May be required, made within 48 hours or as soon as reasonably possible | "made within forty-eight (48) hours of the incident or as soon as reasonably possible" | verified |
| **Notice** | **90 days from the loss** | "within ninety (90) days of the loss or as soon as reasonably possible" | verified |
| **Documents** | **120 days from the loss** | "submitted within one hundred twenty (120) days of the loss" | verified |
| Documents list | Itemized receipt; card statement (last 4 only); other settlements; repair estimate or statement of non-repair; police or incident report | "Copy of the itemized sales receipt" | verified |
| Administrator / insurer | Virginia Surety Company, Inc., an Assurant company | "Virginia Surety Company, Inc., an Assurant company, the insurance company" | verified |
| Claim | https://chasecardbenefits.com · 1-800-349-2691 (outside the U.S., collect: 001-214-503-2951) | "Visit chasecardbenefits.com or call 1-800-349-2691" | verified |

**Extended warranty protection** (CH-GTB pp. 6–8; form code `EW_CON_$10K ITEM_$50K ACCT_20240311`)

| Field | Value | Quote | Status |
|---|---|---|---|
| Extension | +12 months after the original manufacturer's U.S. repair warranty. If there's a store warranty or service contract, it starts after those end | "extends the original manufacturer’s U.S. repair warranty coverage by one (1) additional year" | verified |
| Max original | Manufacturer + store warranty + service contract **≤ 36 months**, otherwise no coverage | "exceeds three (3) years there would not be coverage under this benefit" | verified |
| Max total | 48 months from purchase | "this coverage exceed four (4) years from the purchase date" | verified |
| Needs | A valid original manufacturer's U.S. repair warranty | "the item must come with a valid original manufacturer’s U.S. repair warranty" | verified |
| Covers | Only what the manufacturer's warranty would have covered (failures, not drops) | "only covers what would have been covered under the original manufacturer’s U.S. repair warranty" | verified |
| Per item / account | **$10,000 per item**, $50,000 per account; payout is the lesser of repair cost, replacement cost, amount charged, cap | "$10,000 per item and a maximum of $50,000 per Account" | verified |
| Payment | All or part of the price on the card, or with rewards; gifts count; purchases outside the U.S. count | "charge all or a portion of the cost of the eligible item" | verified |
| Refurbished | **Covered if it has a warranty and isn't used or pre-owned** | "a refurbished item will be covered as long as it has a warranty with it" | verified |
| Exclusions | Motorized vehicles; costs outside the maker's warranty terms; resale or commercial use; rented or leased items; computer software; medical equipment; used or pre-owned items | "Items purchased for resale, professional, or commercial use" | verified |
| **Notice** | **90 days from product failure** | "within ninety (90) days of product failure or as soon as reasonably possible" | verified |
| **Documents** | **120 days from product failure** | "submitted within one hundred twenty (120) days of the product failure" | verified |
| Documents list | Itemized receipt; card statement (last 4 only); maker's warranty plus any store warranty or service contract; item description and serial number; repair estimate or bill showing the cause | "Original repair estimate or repair bill, indicating cause of failure" | verified |
| Administrator / claim | Same as purchase protection (Virginia Surety / Assurant; chasecardbenefits.com; 1-800-349-2691). Receipts can be stored ahead of time at chasecardbenefits.com | "store Your itemized sales receipt and warranty information online at chasecardbenefits.com" | verified |

Freedom Rise: the same tables apply. CH-RISE repeats "up to $500 per item" and the NY 90-day limit.

### 4.4 Discover it Student Cash Back: none

| Fact | Source | Status |
|---|---|---|
| The current card page lists no purchase protection or extended warranty (0 matches for "warrant", "purchase protection" and "purchase security" in the full page text) | DS-STU | verified (absence) |
| Discover dropped Extended Product Warranty, Purchase Protection, Return Guarantee, Auto Rental and Flight Accident insurance effective Feb 28, 2018 (one outlet says Feb 27) | 2nd-DS | partial (secondary only; I found no Discover notice) |
| Discover is now part of Capital One. The card page says "Capital One uses merchant category codes" | DS-STU | verified (no effect on v1) |

---

## 5. Licenses

| Repo | License | Evidence | Status |
|---|---|---|---|
| github.com/novus-tech-tw/CardWise | **MIT** ("Copyright (c) 2025 Rich627") | GitHub API `license.spdx_id = MIT`; `LICENSE` blob `bf39d24`; head commit `4c054e2` (2026-08-25) | verified |
| github.com/greggles/mcc-codes | **Unlicense** (public domain dedication) | GitHub API `license.spdx_id = Unlicense`; `LICENSE.txt` blob `68a49da`; head commit `df79227` (2024-08-16) | verified |

CardWise's `CardWise/Resources/cards.json` has all 5 demo cards. Two of its values disagree with the issuer sources above: its Apple Card entry gives 2% on "other" with **no Apple Pay condition**, and its Discover rotating categories are **Q4 2025**. Seed from this doc, not from CardWise. `THIRD_PARTY.md` still needs the MIT notice if any CardWise data is copied.

---

## 6. Proposed SPEC edits

Not applied. SPEC.md belongs to another session.

**§8.1: replace the table rows with:**

| id | shortName | Network | Earn | Protections | Status |
|---|---|---|---|---|---|
| `apple-card` | Apple Card | Mastercard | 3% on purchases directly from Apple (any method); 3% via Apple Pay at select merchants (Nike, Walgreens, …); 2% via Apple Pay; 1% with the titanium card or virtual card number | None (no purchase protection or extended warranty) | Verified 2026-10-14 (`docs/benefits-verification.md`) |
| `wf-active-cash` | Active Cash | Visa Signature | 2% flat | Cell phone protection only ($600/claim, $25 deductible, 2 claims and $1,200 per 12 months). **No** extended warranty or purchase protection (WF Guide, in effect 09/15/2025) | Verified |
| `chase-freedom-unlimited` | Freedom | Visa | 1.5% base; 3% dining and drugstores (P2); 5% Chase Travel (not modeled) | Purchase protection: 120 days (90 in NY); **$500 per item**, $50,000 per account; theft, damage, involuntary and accidental parting. Extended warranty: +1 yr on U.S. manufacturer warranties if all warranties total ≤3 yr; ≤4 yr from purchase; $10,000 per item, $50,000 per account. Charging all or part of the price (or using rewards) qualifies. Refurbished items with a warranty are covered. **Notify within 90 days** of the loss or failure; **documents within 120 days** | Verified (Chase Guide BGC11366, in effect 10/1/24) |
| `chase-freedom-rise` | Freedom Rise | Visa | 1.5% flat | Same guide and terms as Freedom Unlimited | Verified |
| `discover-it-student-cash-back` | Discover | Discover | 1% base (5% rotating with activation not modeled) | None (removed Feb 28, 2018, per secondary sources) | Earn and absence verified; removal date partial |

**§6.3 S1 copy:** **no change needed.** `{ppCap}` = "$500" is verified per item. The "Saved" row's "up to $500 to Feb 14, 2027" is right for non-NY residents (Oct 17, 2026 + 120 days).

**Other edits the findings call for:**
1. **Renewed beat (§6.3 "Switch, cash" row, §7.3 item 2, §15.4 scenario 2 and coverage case 8).** Chase covers refurbished items with a warranty under both benefits, so "Renewed item: no card adds a warranty" isn't a verified fact. Proposed fix: list the demo store's renewed laptop as **"Renewed · no warranty"**. Both benefits then clearly exclude it: purchase protection treats it as used, and extended warranty needs a maker's U.S. warranty. Change the note to **"Renewed, no warranty: no card covers it"** (39 characters). In case 8, add "no manufacturer warranty" to the fixture. For real carts later (P1), add a condition value such as `refurbished_with_warranty` so the engine doesn't wrongly refuse cover.
2. **New York window.** The engine doesn't know the user's state. Either say "120 days (90 in NY)" in the Why sheet and the claim screen, or ask for the state once in onboarding (P1). Until then, the 120-day date in the copy is wrong for NY residents.
3. **§5.5 "Notify by {date}"** can now be computed as `incident date + 90 days`. Documents are due by `incident date + 120 days`. Both deadlines add "or as soon as reasonably possible"; say so in the verdict.
4. **§5.5 and §15.5 payout.** The cap is the lesser of repair cost, replacement cost, **amount charged to the card**, and $500 or $10,000. For coverage case 12 (`card_partial`), the payout is capped at the part paid on the card.
5. **§5.5 theft checklist:** "police report (made within 48 hours if you can)". For porch theft, add "claim with the carrier or store first".
6. **§15.4 coverage case 10** (Active Cash headphones, month 14): `not_covered` is now confirmed.
7. **§8.4:** remove both "(u) Confirm the license" notes (MIT and Unlicense are verified).
8. **§16 "Unverified" list:** remove "Apple Card protections in 2026" and "Active Cash extended warranty / purchase protection". Optionally add "Walgreens/DoorDash MCCs for Chase bonus categories (P2)".
9. **§15.3 (optional):** the shape has no field for a deductible, a per-period cap (Active Cash: per 12 months), or the "or as soon as reasonably possible" softening. The data below puts these in `summary` and `verification.note`.

---

## 7. Verified values for `data/cards.json` (§15.3 shape)

Merge these into the scaffold by `id`. Fields I didn't verify are `null`: `art` (team-made), `networkTier` where unknown, and `foreignTransactionFeePct` except for Apple Card. `excludedCategories` is `[]` because the guides' exclusions (software, medical equipment, vehicles…) don't map onto our item categories, and the engine already skips gift cards and service plans (§7.2 rule 3). `conditionsAllowed` stays `["new"]` as v1 requires. The verified refurbished rule is in `verification.note` (see edit 1). The Chase bonus-category rules are included because they are verified; drop them if v1 keeps them P2.

```json
{
  "cards": [
    {
      "id": "apple-card",
      "issuer": "Goldman Sachs Bank USA",
      "product": "Apple Card",
      "displayName": "Apple Card",
      "shortName": "Apple Card",
      "network": "mastercard",
      "networkTier": { "value": null, "status": "unverified" },
      "annualFeeUsd": 0,
      "rewardCurrency": "cash_back",
      "pointValueCents": null,
      "foreignTransactionFeePct": 0,
      "art": null,
      "earn": {
        "baseRatePct": 1,
        "rules": [
          { "id": "apple-card-apple", "category": null, "merchantIds": ["apple"], "paymentMethods": ["any"], "ratePct": 3, "cap": null, "needsActivation": false, "status": "verified" },
          { "id": "apple-card-bonus-merchants", "category": null, "merchantIds": ["nike", "walgreens"], "paymentMethods": ["apple_pay"], "ratePct": 3, "cap": null, "needsActivation": false, "status": "verified" },
          { "id": "apple-card-apple-pay", "category": null, "merchantIds": null, "paymentMethods": ["apple_pay"], "ratePct": 2, "cap": null, "needsActivation": false, "status": "verified" }
        ]
      },
      "protections": [],
      "sources": [
        { "document": "Apple Card Customer Agreement", "section": "Daily Cash Program > How You Earn Daily Cash (p. 6 of 19)", "versionDate": "2026-09-18", "url": "https://www.goldmansachs.com/terms-and-conditions/Apple-Card-Customer-Agreement.pdf", "quote": "Apple Pay Purchase Transactions 2% of the transaction amount", "checkedOn": "2026-10-14" },
        { "document": "Apple Support: Learn how to get 3% Daily Cash back when you use Apple Card with Apple Pay", "section": "Merchants that offer 3% Daily Cash back; Nike and Walgreens footnotes", "versionDate": "2026-09-25", "url": "https://support.apple.com/en-us/120400", "quote": "using Apple Card with Apple Pay at Nike stores, Nike.com, the Nike mobile app", "checkedOn": "2026-10-14" },
        { "document": "Mastercard Benefits for Apple Card Customers", "section": "whole page (no purchase protection or extended warranty listed)", "versionDate": null, "url": "https://www.mastercard.com/us/en/personal/find-a-card/card-benefits/apple-card-benefits.html", "quote": "Mastercard Benefits for Apple Card Customers", "checkedOn": "2026-10-14" }
      ]
    },
    {
      "id": "wf-active-cash",
      "issuer": "Wells Fargo Bank, N.A.",
      "product": "Wells Fargo Active Cash Card",
      "displayName": "Wells Fargo Active Cash",
      "shortName": "Active Cash",
      "network": "visa",
      "networkTier": { "value": "visa_signature", "status": "verified" },
      "annualFeeUsd": 0,
      "rewardCurrency": "cash_back",
      "pointValueCents": null,
      "foreignTransactionFeePct": null,
      "art": null,
      "earn": { "baseRatePct": 2, "rules": [] },
      "protections": [
        {
          "type": "cell_phone_protection",
          "summary": "Phone repair or replacement after damage, theft or involuntary parting when the monthly wireless bill is paid with the card. $600 per claim minus $25 deductible; max 2 paid claims and $1,200 per 12 months.",
          "covers": ["theft", "accidental_damage", "involuntary_parting"],
          "excludes": ["Lost or mysteriously disappeared phones", "Cosmetic damage that doesn't affect function", "Tablets, smartwatches and other non-phone devices", "Accessories not in the original box", "Phones in a carrier's or delivery service's custody", "Phones bought for resale or commercial use"],
          "limits": { "perItemUsd": null, "perClaimUsd": 600, "perAccountUsd": null, "appliesTo": "claim" },
          "eligibility": { "conditionsAllowed": null, "paymentRequirement": "full", "excludedCategories": [] },
          "notice": { "notifyWithinDays": 60, "submitDocsWithinDays": 120 },
          "claim": { "administrator": "Virginia Surety Company, Inc. (Assurant)", "url": "https://mycardbenefits.assurant.com", "phone": "1-800-316-8051" },
          "source": { "document": "Wells Fargo Active Cash Card Guide to Benefits", "section": "Cellular Telephone Protection > How to File a Claim", "versionDate": "2025-09-15", "url": "https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/", "quote": "$600 per claim." },
          "verification": { "status": "verified", "checkedBy": "claude (card-benefits session)", "checkedOn": "2026-10-14", "note": "Per-account cap is per 12-month period (2 claims / $1,200), so perAccountUsd is null. Notice is 60 days 'or as soon as reasonably possible'; documents 120 days. The guide has no extended warranty or purchase protection (0 text matches). Not counted by the v1 engine." }
        }
      ],
      "sources": [
        { "document": "Wells Fargo Active Cash Card Guide to Benefits", "section": "whole guide (benefit list)", "versionDate": "2025-09-15", "url": "https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/", "quote": "describes the benefits in effect as of 09/15/2025", "checkedOn": "2026-10-14" },
        { "document": "Wells Fargo Active Cash card page", "section": "hero; footnote 2", "versionDate": null, "url": "https://creditcards.wellsfargo.com/active-cash-credit-card/", "quote": "unlimited 2% cash rewards on purchases", "checkedOn": "2026-10-14" }
      ]
    },
    {
      "id": "chase-freedom-unlimited",
      "issuer": "JPMorgan Chase Bank, N.A.",
      "product": "Chase Freedom Unlimited",
      "displayName": "Chase Freedom Unlimited",
      "shortName": "Freedom",
      "network": "visa",
      "networkTier": { "value": null, "status": "unverified" },
      "annualFeeUsd": 0,
      "rewardCurrency": "cash_back",
      "pointValueCents": null,
      "foreignTransactionFeePct": null,
      "art": null,
      "earn": {
        "baseRatePct": 1.5,
        "rules": [
          { "id": "cfu-dining", "category": "dining", "merchantIds": null, "paymentMethods": ["any"], "ratePct": 3, "cap": null, "needsActivation": false, "status": "verified" },
          { "id": "cfu-drugstores", "category": "pharmacy", "merchantIds": null, "paymentMethods": ["any"], "ratePct": 3, "cap": null, "needsActivation": false, "status": "verified" }
        ]
      },
      "protections": [
        {
          "type": "purchase_protection",
          "summary": "Theft, damage or involuntary and accidental parting within 120 days of purchase (90 in NY). Up to $500 per item, $50,000 per account. Pays the lesser of repair, replacement, the amount charged to the card, or $500. Secondary to other insurance.",
          "covers": ["theft", "accidental_damage", "involuntary_parting"],
          "excludes": ["Lost or mysteriously disappeared items", "Items in a common carrier's or delivery service's care", "Unattended items in baggage on a common carrier", "Computer software", "Medical equipment", "Living animals and plants", "Antiques or collectibles", "Motorized vehicles and their parts", "Items for resale, professional or commercial use", "Normal wear and tear; inherent product defects; abuse; flood; earthquake", "Mis-delivery or voluntary parting", "Perishables, consumables and rechargeable batteries", "Traveler's checks, cash, tickets, credit or debit cards", "Used or pre-owned items (refurbished with a warranty is not treated as used)"],
          "windowDays": 120,
          "windowDaysByState": { "NY": 90 },
          "limits": { "perItemUsd": 500, "perClaimUsd": null, "perAccountUsd": 50000, "appliesTo": "item" },
          "eligibility": { "conditionsAllowed": ["new"], "paymentRequirement": "some_portion", "excludedCategories": [] },
          "notice": { "notifyWithinDays": 90, "submitDocsWithinDays": 120 },
          "claim": { "administrator": "Virginia Surety Company, Inc. (Assurant)", "url": "https://chasecardbenefits.com", "phone": "1-800-349-2691" },
          "source": { "document": "Chase Freedom Guide to Benefits (BGC11366)", "section": "Purchase Protection, pp. 9-11", "versionDate": "2024-10-01", "url": "https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf", "quote": "$500 per item and a maximum of $50,000 per Account" },
          "verification": { "status": "verified", "checkedBy": "claude (card-benefits session)", "checkedOn": "2026-10-14", "note": "No per-claim cap in the guide. Notice 90 days and documents 120 days from the loss, each 'or as soon as reasonably possible'. Police report may be required within 48 hours. Rewards-paid purchases also qualify. The guide covers refurbished items accompanied by a warranty; conditionsAllowed is ['new'] only because v1 models new items. Needs a human review per SPEC §7.3." }
        },
        {
          "type": "extended_warranty",
          "summary": "Adds 1 year after the manufacturer's U.S. repair warranty (after any store warranty or service contract) when all of them total 3 years or less; never more than 4 years from purchase. Up to $10,000 per item, $50,000 per account.",
          "covers": ["failure"],
          "excludes": ["Items without a valid original manufacturer's U.S. repair warranty", "Combined warranties and service contracts over 3 years", "Costs not covered by the original manufacturer's warranty", "Motorized vehicles and their parts", "Items for resale, professional or commercial use", "Rented or leased items", "Computer software", "Medical equipment", "Used or pre-owned items (refurbished with a warranty is covered)"],
          "extendsByMonths": 12,
          "maxOriginalWarrantyMonths": 36,
          "maxTotalFromPurchaseMonths": 48,
          "limits": { "perItemUsd": 10000, "perClaimUsd": null, "perAccountUsd": 50000, "appliesTo": "item" },
          "eligibility": { "conditionsAllowed": ["new"], "paymentRequirement": "some_portion", "excludedCategories": [] },
          "notice": { "notifyWithinDays": 90, "submitDocsWithinDays": 120 },
          "claim": { "administrator": "Virginia Surety Company, Inc. (Assurant)", "url": "https://chasecardbenefits.com", "phone": "1-800-349-2691" },
          "source": { "document": "Chase Freedom Guide to Benefits (BGC11366)", "section": "Extended Warranty Protection, pp. 6-8", "versionDate": "2024-10-01", "url": "https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf", "quote": "extends the original manufacturer’s U.S. repair warranty coverage by one (1) additional year" },
          "verification": { "status": "verified", "checkedBy": "claude (card-benefits session)", "checkedOn": "2026-10-14", "note": "maxOriginalWarrantyMonths counts manufacturer + store warranty + service contract together. Notice 90 days and documents 120 days from product failure, each 'or as soon as reasonably possible'. Covers only what the maker's warranty would have covered. Refurbished items with a warranty are covered; conditionsAllowed is ['new'] for v1. Needs a human review per SPEC §7.3." }
        }
      ],
      "sources": [
        { "document": "Chase Freedom Unlimited card page", "section": "Earn rewards; offer details; Service & protection", "versionDate": null, "url": "https://creditcards.chase.com/cash-back-credit-cards/freedom/unlimited", "quote": "against damage or theft up to $500 per item", "checkedOn": "2026-10-14" },
        { "document": "Chase Freedom Guide to Benefits (BGC11366)", "section": "cover, p. 2", "versionDate": "2024-10-01", "url": "https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf", "quote": "describes the benefit that is in effect as of 10/1/24", "checkedOn": "2026-10-14" }
      ]
    },
    {
      "id": "chase-freedom-rise",
      "issuer": "JPMorgan Chase Bank, N.A.",
      "product": "Chase Freedom Rise",
      "displayName": "Chase Freedom Rise",
      "shortName": "Freedom Rise",
      "network": "visa",
      "networkTier": { "value": null, "status": "unverified" },
      "annualFeeUsd": 0,
      "rewardCurrency": "cash_back",
      "pointValueCents": null,
      "foreignTransactionFeePct": null,
      "art": null,
      "earn": { "baseRatePct": 1.5, "rules": [] },
      "protections": [
        {
          "type": "purchase_protection",
          "summary": "Theft, damage or involuntary and accidental parting within 120 days of purchase (90 in NY). Up to $500 per item, $50,000 per account. Pays the lesser of repair, replacement, the amount charged to the card, or $500. Secondary to other insurance.",
          "covers": ["theft", "accidental_damage", "involuntary_parting"],
          "excludes": ["Lost or mysteriously disappeared items", "Items in a common carrier's or delivery service's care", "Unattended items in baggage on a common carrier", "Computer software", "Medical equipment", "Living animals and plants", "Antiques or collectibles", "Motorized vehicles and their parts", "Items for resale, professional or commercial use", "Normal wear and tear; inherent product defects; abuse; flood; earthquake", "Mis-delivery or voluntary parting", "Perishables, consumables and rechargeable batteries", "Traveler's checks, cash, tickets, credit or debit cards", "Used or pre-owned items (refurbished with a warranty is not treated as used)"],
          "windowDays": 120,
          "windowDaysByState": { "NY": 90 },
          "limits": { "perItemUsd": 500, "perClaimUsd": null, "perAccountUsd": 50000, "appliesTo": "item" },
          "eligibility": { "conditionsAllowed": ["new"], "paymentRequirement": "some_portion", "excludedCategories": [] },
          "notice": { "notifyWithinDays": 90, "submitDocsWithinDays": 120 },
          "claim": { "administrator": "Virginia Surety Company, Inc. (Assurant)", "url": "https://chasecardbenefits.com", "phone": "1-800-349-2691" },
          "source": { "document": "Chase Freedom Guide to Benefits (BGC11366)", "section": "Purchase Protection, pp. 9-11", "versionDate": "2024-10-01", "url": "https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf", "quote": "$500 per item and a maximum of $50,000 per Account" },
          "verification": { "status": "verified", "checkedBy": "claude (card-benefits session)", "checkedOn": "2026-10-14", "note": "No per-claim cap in the guide. Notice 90 days and documents 120 days from the loss, each 'or as soon as reasonably possible'. Police report may be required within 48 hours. Rewards-paid purchases also qualify. The guide covers refurbished items accompanied by a warranty; conditionsAllowed is ['new'] only because v1 models new items. Needs a human review per SPEC §7.3." }
        },
        {
          "type": "extended_warranty",
          "summary": "Adds 1 year after the manufacturer's U.S. repair warranty (after any store warranty or service contract) when all of them total 3 years or less; never more than 4 years from purchase. Up to $10,000 per item, $50,000 per account.",
          "covers": ["failure"],
          "excludes": ["Items without a valid original manufacturer's U.S. repair warranty", "Combined warranties and service contracts over 3 years", "Costs not covered by the original manufacturer's warranty", "Motorized vehicles and their parts", "Items for resale, professional or commercial use", "Rented or leased items", "Computer software", "Medical equipment", "Used or pre-owned items (refurbished with a warranty is covered)"],
          "extendsByMonths": 12,
          "maxOriginalWarrantyMonths": 36,
          "maxTotalFromPurchaseMonths": 48,
          "limits": { "perItemUsd": 10000, "perClaimUsd": null, "perAccountUsd": 50000, "appliesTo": "item" },
          "eligibility": { "conditionsAllowed": ["new"], "paymentRequirement": "some_portion", "excludedCategories": [] },
          "notice": { "notifyWithinDays": 90, "submitDocsWithinDays": 120 },
          "claim": { "administrator": "Virginia Surety Company, Inc. (Assurant)", "url": "https://chasecardbenefits.com", "phone": "1-800-349-2691" },
          "source": { "document": "Chase Freedom Guide to Benefits (BGC11366)", "section": "Extended Warranty Protection, pp. 6-8", "versionDate": "2024-10-01", "url": "https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf", "quote": "extends the original manufacturer’s U.S. repair warranty coverage by one (1) additional year" },
          "verification": { "status": "verified", "checkedBy": "claude (card-benefits session)", "checkedOn": "2026-10-14", "note": "maxOriginalWarrantyMonths counts manufacturer + store warranty + service contract together. Notice 90 days and documents 120 days from product failure, each 'or as soon as reasonably possible'. Covers only what the maker's warranty would have covered. Refurbished items with a warranty are covered; conditionsAllowed is ['new'] for v1. Needs a human review per SPEC §7.3." }
        }
      ],
      "sources": [
        { "document": "Chase Freedom Rise card page", "section": "Cardmember rewards; Service & protection", "versionDate": null, "url": "https://creditcards.chase.com/cash-back-credit-cards/freedom/rise", "quote": "Establish credit and earn 1.5% cash back on all purchases", "checkedOn": "2026-10-14" },
        { "document": "Chase Freedom Guide to Benefits (BGC11366)", "section": "cover, p. 2 (lists Chase Freedom Rise)", "versionDate": "2024-10-01", "url": "https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf", "quote": "Chase Freedom Rise® and Chase Freedom Student Visa Platinum and Visa Signature®", "checkedOn": "2026-10-14" }
      ]
    },
    {
      "id": "discover-it-student-cash-back",
      "issuer": "Discover",
      "product": "Discover it Student Cash Back",
      "displayName": "Discover it Student Cash Back",
      "shortName": "Discover",
      "network": "discover",
      "networkTier": { "value": null, "status": "unverified" },
      "annualFeeUsd": 0,
      "rewardCurrency": "cash_back",
      "pointValueCents": null,
      "foreignTransactionFeePct": null,
      "art": null,
      "earn": { "baseRatePct": 1, "rules": [] },
      "protections": [],
      "sources": [
        { "document": "Discover student credit cards page", "section": "Discover it Student Cash Back: rewards", "versionDate": null, "url": "https://www.discover.com/credit-cards/student-credit-card/", "quote": "Plus, earn 1% cash back on all other purchases.", "checkedOn": "2026-10-14" }
      ]
    }
  ]
}
```

`chase-freedom-rise.protections` is an exact copy of the Freedom Unlimited objects (same guide, BGC11366). Keep them identical when editing.
