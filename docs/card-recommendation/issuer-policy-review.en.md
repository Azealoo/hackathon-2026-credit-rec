# US Issuer Policy Review for Card Recommendations

Reviewed: October 16, 2026. Scope: nine representative US consumer card products across seven issuer/product families. This is not a review of every product or the user's personalized account agreement. Discover is now part of Capital One, but its products remain separate catalog entries; common ownership does not make their rules interchangeable.

**Rewards, purchase protection, return protection, and extended warranty must be modeled by specific product and card variant. Zero liability for unauthorized charges does not establish protection for merchandise returns.** The tables summarize verified fields. An unlisted term is not necessarily an absent benefit. The current seed supports basic reward calculations and policy display; complete executable exclusion rules are still missing for some products.

## 1. Reward policy summary

Rates apply to eligible net purchases. Returns, refunds, cash equivalents, and similar transactions are excluded or deducted under the relevant rewards terms. Displayed prices, merchant classification, payment channel, and posting information affect eligibility.

| Issuer / product | Base rate for ordinary online merchandise | Relevant bonus rates and caps | Required algorithm checks | Sources |
|---|---:|---|---|---|
| Chase Freedom Unlimited | 1.5% | 3% total on dining/drugstores; 5% total through Chase Travel | Ordinary e-commerce is not the travel portal. The advertised rate is a total, not an increment added to the base. | [CH-FU](https://creditcards.chase.com/cash-back-credit-cards/freedom/unlimited), [CH-RPA](https://asset.chase.com/content/dam/card/rulesregulations/en/RPA0509_Web.pdf) |
| Amex Blue Cash Everyday | 1% | 3% on eligible US online retail, up to $6,000 per calendar year in that category, then 1%. US supermarket and gas categories each have separate $6,000 pools. | A US retailer must sell physical goods directly to consumers. Online travel/entertainment services do not automatically qualify as online retail. | [AMEX-BCE](https://www.americanexpress.com/us/credit-cards/card/blue-cash-everyday/), [AMEX-BCE-T](https://global.americanexpress.com/card-benefits/terms/blue-cash-everyday) |
| Amex Blue Cash Preferred | 1% | 6% on the first $6,000/year at US supermarkets, then 1%; 6% on select US streaming; 3% on transit and US gas | BCP does not inherit BCE's general 3% online-retail category. An ordinary online laptop purchase generally remains at 1%. | [AMEX-BCP](https://www.americanexpress.com/us/credit-cards/card/blue-cash-preferred/) |
| Capital One Quicksilver Rewards | 1.5% | Eligible portal transactions have additional rewards; this seed excludes travel/entertainment portal optimization. | Distinguish QuicksilverOne, Secured, legacy, and other credit-tier variants. No foreign transaction fee. | [CAP-QS](https://www.capitalone.com/credit-cards/cash-back/quicksilver/), [CAP-QS-F](https://www.capitalone.com/credit-cards/quicksilver/) |
| Capital One Savor Rewards | 1% | 3% total on dining, eligible grocery stores, entertainment, and popular streaming; 5% on specified travel-portal purchases | Exclude superstores such as Walmart/Target from the grocery category. Do not apply the legacy $95-fee Savor's 4% rules. No foreign transaction fee. | [CAP-SAVOR](https://www.capitalone.com/credit-cards/savor/) |
| Citi Double Cash | 1% on purchases plus 1% as corresponding purchase balances are paid | An additional 3% on specified Citi Travel purchases, for an eventual 5% total | The second 1% depends on eligible payments and the Purchase Tracker. Cash redemption: 100 points = $1. A 0% balance-transfer offer is not a 0% purchase offer. | [CITI-DC](https://www.citi.com/credit-cards/citi-double-cash-credit-card) |
| Bank of America Customized Cash Rewards | 1% | Ordinarily 3% in the selected category and 2% at grocery stores/wholesale clubs, sharing a $2,500 quarterly spending cap. The current public offer adds 3 percentage points to the choice category in the first year. | Is online shopping selected? What remains in the shared pool? Does the account qualify for the first-year offer? Do not automatically apply new-applicant terms to an existing account. | [BOFA-CCR](https://www.bankofamerica.com/credit-cards/products/cash-back-credit-card/) |
| Discover it Cash Back | 1% | 5% on up to $1,500 combined spending in activated quarterly categories. First-year Cashback Match is deferred. | Verify quarterly categories, activation, cap availability, and first-year eligibility. The calendar did not load its quarterly list during this review; the seed does not populate 2026 Q4 categories. | [DISC-IT](https://www.discover.com/credit-cards/cash-back/it-card/), [DISC-CAL](https://www.discover.com/credit-cards/cash-back/cashback-calendar.html) |
| Wells Fargo Active Cash | 2% | No category cap. Personalized My Wells Fargo Deals require activation and compliance with offer terms. | Foreign transaction fee: 3%. The Visa Signature label does not establish general merchandise protection. | [WF-AC](https://creditcards.wellsfargo.com/active-cash-credit-card/), [WF-DEALS](https://www.wellsfargo.com/assets/pdf/personal/my-wells-fargo-deals/terms-and-conditions-english.pdf) |

**BofA membership bonus:** the current official BofA Rewards table lists Member 10%, Preferred Plus 25%, Preferred Honors 50%, and Premier 75% rewards bonuses. The ordinary choice-category rates become 3.3%, 3.75%, 4.5%, and 5.25%, respectively. Do not hard-code old tier names or infer the user's tier. The reviewed sources did not fully establish stacking between the first-year offer and membership bonuses; the seed prohibits automatic stacking. [BOFA-TIER](https://www.bankofamerica.com/bofa-rewards/increasing-bofa-rewards-with-credit-cards/)

**Annual fees and APRs:** the selected public versions of FU, BCE, Quicksilver, Savor, Citi Double Cash, BofA CCR, Discover it, and Active Cash have no annual fee. BCP's current public page advertises a $0 first-year fee, then $95. These observations are not the user's account APR record. Do not allocate an already incurred annual fee to a single purchase. Verify personal APRs, 0% purchase offers, and expiry dates separately. [AMEX-BCP](https://www.americanexpress.com/us/credit-cards/card/blue-cash-preferred/)

## 2. Purchase protection, extended warranty, and return protection

The limits below are contractual ceilings, not expected payouts. Knowledge states: `verified_rule` means specific terms were read; `verified_summary` means an official source confirms a benefit but its full applicability rules have not been encoded; `not_listed` means the reviewed guide/page does not list it; `unknown` means unverified. None establishes eligibility for a particular item by itself.

| Product | Damage/theft | Extended warranty | Return protection | Engine treatment |
|---|---|---|---|---|
| Freedom Unlimited | 120 days, or 90 days for New York residents; $500/item and $50,000/account | One additional year on a qualifying valid US manufacturer repair warranty, subject to duration rules; $10,000/item | Not listed in the reviewed applicable guide | Use in protection evaluation only after checking purchase eligibility, payment allocation, and exclusions. |
| Blue Cash Everyday | Official summary: 90 days, $1,000/covered purchase and $50,000/account/calendar year | Not listed in the current reviewed product-benefit summary | Not listed in the reviewed product-benefit summary | Treat damage/theft as a confirmed product benefit only. Do not inherit BCP's warranty merely because both are Amex cards. |
| Blue Cash Preferred | Official summary: 90 days, $1,000/covered purchase and $50,000/account/calendar year | Official summary: up to one extra year on original warranties of five years or less; $10,000/item and $50,000/account/calendar year | 90 days, $300/item and $1,000/account/calendar year; eligible full-card US purchase, original condition, and merchant refusal required | Display the terms. Full exclusions are not all executable yet; an item title alone cannot establish eligibility. |
| Quicksilver / Savor | Depends on network and variant | Official guides contain different warranty rules | Variant-by-variant review incomplete | Identify network+tier and the applicable guide first. Product name alone is insufficient. |
| Citi Double Cash | Complete applicable guide not obtained in this review | **The current official page lists extended warranty**, but full account-applicable duration and limits remain unverified | Unverified | Mark warranty as verified_summary. Do not say “none” or fill a fixed two-year extension from old material. |
| BofA Customized Cash Rewards | Account-applicable guide not obtained | Account-applicable guide not obtained | Account-applicable guide not obtained | Unknown. Rewards can be calculated, but do not promise additional protection or a switch that preserves all protection. |
| Discover it Cash Back | Not confirmed on the reviewed product page | Not confirmed on the reviewed product page | Not confirmed on the reviewed product page | Not_listed. Do not apply another Capital One product's guide based on common ownership. |
| Active Cash | Current reviewed guide does not list general merchandise damage/theft protection | Not listed in the current guide | Not listed in the current guide | Not_listed. Say “not listed in the reviewed guide.” Evaluate phone-bill coverage separately. |

Sources: [CH-GTB](https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf) (printed pages 6–11; effective October 1, 2024); [AMEX-BCE-B](https://global.americanexpress.com/card-benefits/view-all/blue-cash-everyday); [AMEX-BCP](https://www.americanexpress.com/us/credit-cards/card/blue-cash-preferred/); [AMEX-BCP-B](https://global.americanexpress.com/card-benefits/view-all/blue-cash-preferred?linknav=en-US-oneAmex-axpSearchResults-1&searchresult=cancel+pay+over+time); [AMEX-RP](https://www.americanexpress.com/content/dam/amex/us/credit-cards/features-benefits/policies/NAC-Benefit-Guides/RP_Benefit_Guide_Rev_10-20_10.09.23.pdf); [CITI-DC](https://www.citi.com/credit-cards/citi-double-cash-credit-card); [CAP-GUIDES](https://www.capitalone.com/credit-cards/benefits-guide/); [WF-GTB](https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/) (effective September 15, 2025); [DISC-IT](https://www.discover.com/credit-cards/cash-back/it-card/).

## 3. Conditions with the largest implementation impact

### Chase: two coverage caps are not enough

Limits also depend on repair/replacement cost and the amount charged. Do not convert the $50,000 account limit into an annual limit. A refurbished item with a warranty is treated differently from an ordinary used item. Extended warranty also checks the combined duration of the underlying warranties. Do not hard-code a 120-day purchase-protection window for New York residents. Purchase-protection and extended-warranty claims generally require notice within 90 days of the loss/failure and documents within 120 days, with the policy's “as soon as reasonably possible” exception. Store notice/document deadlines separately from the post-purchase coverage window. [CH-GTB](https://static.chasecdn.com/content/services/structured-document/document.en.pdf/card/benefits-center/product-benefits-guide-pdf/BGC11366_v2.pdf)

### Amex: return protection does not make every item returnable

The policy excludes formal wear, jewelry/watches, used or altered items, software, tickets, consumables, and other listed categories. If the merchant already offers an equal or better return guarantee covering the request, do not count the card benefit as a new return entitlement. The full-card-payment requirement must not share a generic Boolean with Chase's partial-payment rule. [AMEX-RP](https://www.americanexpress.com/content/dam/amex/us/credit-cards/features-benefits/policies/NAC-Benefit-Guides/RP_Benefit_Guide_Rev_10-20_10.09.23.pdf)

### Capital One: the same product name can have different benefits guides

The official guide selector separates Visa, Mastercard, and Discover Network accounts. The reviewed Discover Network guide specifically names Venture, VentureOne, Savor, SavorOne, Quicksilver, and QuicksilverOne and is effective **February 1, 2026**. It is not a guide for all Discover-branded cards.

- That Discover Network guide provides 90-day damage/theft protection with a $1,000 **per-claim** limit and $25,000 per 12 months. It doubles qualifying warranties of two years or less, adding at most one year. Separate price-protection terms provide a 120-day window, $250/item, and $1,000/year.
- The official World Elite Mastercard guide doubles qualifying original warranties of two years or less, adding up to 24 months, and requires full payment with the eligible card. This differs from the partial-payment allowance in the Discover Network guide. Do not combine favorable terms from both guides into a nonexistent card variant.

Confirm the user's actual applicable variant first. Conditional templates in the seed are disabled by default. [CAP-DISC-GTB](https://ecm.capitalone.com/WCM/card/benefits-guide/discover-benefits-guides/discover-english.pdf) (printed pages 1–5), [CAP-MCWE-GTB](https://ecm.capitalone.com/WCM/card/benefits-guide/20210621-updates-to-wmc-world-and-we/mc-we-gtb_english.pdf) (printed pages 5–6), [CAP-GUIDES](https://www.capitalone.com/credit-cards/benefits-guide/)

### Citi: benefit existence confirmed, numerical terms unresolved

The current official Double Cash page lists Extended warranty, subject to the Guide to Protection Benefits, and describes secondary coverage. The search also found historical reports of a restored benefit and a guide hosted by a third party. No official numerical guide with confirmed applicability to the user's current account was obtained, so the reported “24 months” was not inserted into executable rules. [CITI-DC](https://www.citi.com/credit-cards/citi-double-cash-credit-card)

### Wells Fargo: the phone benefit is triggered by the service bill

The current Active Cash product page lists up to $600 per phone claim with a $25 deductible, subject to paying the monthly wireless bill with the card under the policy terms. **Buying a handset with the card does not by itself trigger this phone-bill benefit.** Do not treat it as general online-shopping insurance. [WF-AC](https://creditcards.wellsfargo.com/active-cash-credit-card/), [WF-GTB](https://www.wellsfargo.com/credit-cards/active-cash/guide-to-benefits/)

## 4. Unverified fields and fallback behavior

| Gap | Official sources checked | Required fallback |
|---|---|---|
| Full current-account Citi extended-warranty terms | Product page lists the benefit; a clearly applicable official guide was not obtained | Display the benefit's existence, leave duration/limits unknown, and do not let it automatically win a protection comparison. |
| BofA account-applicable shopping benefits and first-year/membership stacking | Product page and membership table; the product terms link returned 404 | Benefits remain unknown. Obtain additional terms when first-year and membership offers coexist. |
| Capital One network, tier, and account applicability | Official guide index and two benefits guides | Show conditional coverage until the variant is confirmed. |
| Discover 2026 Q4 category list | Official calendar displayed an error and only generic 5%/$1,500 terms | Do not populate quarterly categories or enable an automatic 5% recommendation. |
| Actual APR, available credit, grace-period status, and spending-cap usage for each account | Public product pages describe products, not an individual's account state | Obtain authorized account data or user confirmation. Unknown is not zero. |
| Full BCE/BCP damage and warranty exclusion rules | Official summaries were reviewed; full return-protection terms were separately read | Preserve the positive summary. Display only until the complete predicates establish item eligibility. |
| Account-applicable foreign-fee terms for Citi, BofA, Chase, BCE, and Discover | This review prioritized rewards and shopping protection; some dynamic fee fields were empty | Keep unverified fees null in the seed. Complete them before recommending on foreign net value. |

Basic reward facts and contract-specific eligibility need separate treatment. Preserve distinct states for a benefit not listed on a page, a failed page retrieval, and an issuer's explicit statement that a benefit is unavailable.

## 5. Using the data package

`card-policy-seed.json` contains nine products, source locations, reward cap pools, and benefit summaries/conditional templates. It contains no personal financial data. Rates use basis points and money uses cents; unresolved values remain null. Loaders must enforce `guardrails` and `readiness` rather than treating them as comments.

Introductory offers, quarterly categories, and account benefits can change. The review date records this reading only. No monitoring job has been created, and an existing account is not assumed to qualify for a current public offer. After a purchase, save the policy snapshot actually used with the purchase record.
