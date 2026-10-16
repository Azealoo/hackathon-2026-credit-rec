# Card recommendation v2 research and specification

Research snapshot: October 16, 2026. Scope: choosing among a US user's existing credit cards for an online purchase, covering nine representative products across Chase, American Express, Capital One, Citi, Bank of America, Discover, and Wells Fargo.

| File | Purpose |
|---|---|
| [Algorithm specification](algorithm-spec.en.md) | Proposed inputs, net reward calculations, uncertainty handling, protection comparisons, recommendation modes, and migration boundaries. |
| [Issuer policy review](issuer-policy-review.en.md) | Official source links, reviewed reward and benefit terms, and unresolved policy fields. |
| [Policy seed](card-policy-seed.json) | Structured research data with source IDs, basis-point rates, integer USD cents, and explicit readiness gates. |
| [Acceptance vectors](acceptance-vectors.json) | Twenty hand-computed scenarios describing expected behavior and assumptions for future implementation. |
| [Implementation status](implementation.md) | Supported v2 calculations, opt-in endpoint, local example, and remaining policy/integration work. |

Read the algorithm specification first, then the issuer review and structured files. The acceptance vectors are specification examples, not executed engine tests.

## Integration status

This directory contains a proposed extension to [the current product specification](../../SPEC.md). An initial implementation is available through the opt-in `/v2/recommend` endpoint; see [implementation status](implementation.md) for its supported subset. The existing `/v1/check` runtime catalog remains [data/cards.json](../../data/cards.json); the research seed uses a different schema and must not replace it directly.

The seed is not a production policy bundle. Account applicability must be confirmed, and full item eligibility and exclusion rules remain incomplete. Automatic item eligibility and conditional benefit activation remain disabled. Unknown or unlisted benefits must not be interpreted as guaranteed coverage or as proof that no benefit exists. Issuer terms and account offers require verification before operational use.

The implementation retains the existing engine and introduces `us-online-v2-draft` behind a disabled-by-default feature flag. Automatic item protection eligibility remains gated pending complete executable rules. The app's checkout flow has not been switched to v2.
