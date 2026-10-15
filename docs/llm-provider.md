# LLM provider for Paywise

Decision doc, 2026-10-14. Does not edit SPEC.md; §10 copy below is a proposed replacement. **(u)** = could not confirm.

## Recommendation

**Use Claude Haiku 5.5 (`claude-haiku-5-5`) through the Anthropic API.** Keep Claude Sonnet 5.5 (`claude-sonnet-5-5`) as the one-line fallback if the parser eval misses its bar.

Why, in order of weight:
1. **Credits already exist.** No new billing account, card or Google Cloud project tonight. Gemini's *paid* terms only apply once a Cloud project has an active billing account ([terms](https://ai.google.dev/gemini-api/terms)); that is extra setup and extra risk of landing on the free tier by mistake (free tier trains on prompts and allows human review).
2. **Cleaner privacy story.** One flat default (30 days), no training. Gemini's story needs a "paid tier only" caveat.
3. **Same capability set we need:** schema-constrained JSON on both sides, cost is pennies on both.
4. **Latency is the only open risk, and we can measure it in 10 minutes** (see "Latency check"). If Haiku 5.5 misses 1.5 s p50, we switch the `LLM_PROVIDER` env var, not the architecture.

Gemini stays a valid choice. Nothing below says it is bad; the call is mostly setup friction and privacy simplicity.

## Comparison

| | Claude Haiku 5.5 (rec.) | Gemini paid tier |
|---|---|---|
| Structured output | `output_config.format` with a JSON schema; supported on Haiku 5.5 (claude-api skill, `shared/tool-use-concepts.md`). Schema is compiled to a grammar, so output is valid against the schema. | `response_format` with `mime_type: application/json` + `schema`; JSON Schema **subset**; "very large or deeply nested schemas may be rejected"; values still need validating ([docs](https://ai.google.dev/gemini-api/docs/structured-output)). |
| Short-prompt latency | **(u)** No published number in the sources I read. Haiku is Anthropic's "fast, low-cost" tier for latency-sensitive extraction/classification. Measure. | **(u)** Not stated on the pricing or structured-output pages. Flash-Lite models are the low-latency tier. Measure. |
| Price (per 1M tokens) | $0.10 in / $0.50 out for prompts ≤100K (skill's cached table, 2026-10-06). New tokenizer counts ~30% more tokens for the same text. | `gemini-2.5-flash-lite` $0.10 / $0.40; `gemini-3.1-flash-lite` $0.25 / $1.50; `gemini-3.5-flash-lite` $0.30 / $2.50; `gemini-3.8-flash` $0.75 / $3.75 through 2026-12-31 ([pricing](https://ai.google.dev/gemini-api/docs/pricing)). |
| Training | Retained data "never used for model training without your express permission" ([Anthropic retention docs](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)). | Paid services: Google "doesn't use your prompts" or responses to improve products. Unpaid: it does, and human reviewers may read them ([terms](https://ai.google.dev/gemini-api/terms)). |
| Retention | Default: inputs/outputs deleted from backend within **30 days** (Anthropic privacy centre, seen only as a search snippet; **(u)** re-read before shipping copy). Flagged traffic: up to 2 years (retention docs). | Prompts, context and outputs logged **55 days** for abuse monitoring ([abuse monitoring](https://ai.google.dev/gemini-api/docs/abuse-monitoring)). The terms page itself gives no period; the abuse page does not mention tiers, so "55 days applies to paid" is an inference **(u)**. |
| Setup | Console key already funded. Create a key (user does this, not Claude), put it in the deployed env and local `.env`. | Create/choose a Cloud project, enable billing, create key, confirm it is on the paid tier. |

## Cost for ~200 checks (estimate)

Assumptions (mine, **(u)**): parse ≈ 1,500 input tokens (system prompt + schema + redacted text), ≈ 400 output; classify ≈ 400 in, ≈ 30 out; 200 parses + 200 classifications.

- Haiku 5.5: 200 × (1,900 in, 430 out) = 380K in, 86K out → ≈ **$0.04 + $0.04 ≈ $0.08**. With the 30% tokenizer uplift, about $0.10.
- Sonnet 5.5 ($2 / $10): ≈ **$1.00–$1.40**.
- Gemini 3.1 Flash-Lite: ≈ **$0.10 + $0.13 ≈ $0.25**.

Budget $5 for eval runs on `fixtures/ocr/*` and retries. Cost is not a deciding factor.

## Settings

Parse and classify both call `POST /v1/messages` (no streaming needed; output is short).

```
model:        claude-haiku-5-5
max_tokens:   1024 (parse), 64 (classify)
thinking:     {"type": "disabled"}     # accepted on Haiku 5.5 at effort high or below
output_config:{"effort": "low",
               "format": {"type": "json_schema", "schema": <Cart | CauseChip schema>}}
timeout:      4.5 s client-side, max_retries: 0
temperature/top_p/top_k: leave unset (non-default values 400 on Haiku 5.5)
```

- **Do not use** assistant prefill (400) or `budget_tokens` (400).
- **Thinking off** keeps latency down; there are no tools in these calls, so the "tool call leaks into text" failure the skill warns about for disabled thinking does not apply. If the eval shows weak parsing, try `{"type": "adaptive"}` at `low` before changing model.
- **Timeout:** phone hard limit is 6.0 s (SPEC §7.3), so the server must answer or fail by ~4.5 s. SDK default is 2 retries over a 10-minute timeout; override both. On timeout or error, fall back to the rules parser (`PARSER_MODE=rules`) as the spec already does.
- **Check `stop_reason`** before reading content: `refusal` and `max_tokens` can return HTTP 200 with no usable JSON. Treat as parse failure → rules parser.
- **Validate in code:** schema-valid is not correct. Σ items vs total stays a code check (SPEC §15.7 step 9). The LLM never does arithmetic.
- **Cause chips:** make `cause` a JSON-schema `enum` of the 4 chips; user confirms (`causeSource: user_confirmed`).
- **Env:** `LLM_PROVIDER=anthropic`, `LLM_MODEL=claude-haiku-5-5`. `.env.example` keeps `LLM_API_KEY=changeme`. Never commit the key.
- **Fallback model:** if Haiku misses "merchant + total 100%, items + condition ≥85%" on the fixtures, change `LLM_MODEL` to `claude-sonnet-5-5` (≈10-20× the price, still about a dollar) and re-measure latency.

### Latency check (do this before locking in)

Run ~20 parses of redacted fixture text through `claude-haiku-5-5` with the settings above and log wall-clock p50/p90 from the server. Pass bar: p50 ≤ 1.5 s, p90 ≤ 3 s so the whole path stays within press → result p50 ≤ 3.5 s (SPEC timing targets). Repeat on `claude-sonnet-5-5` once to know what the fallback costs in time. If both miss, test Gemini Flash-Lite the same way. I have not measured any of this.

### Anthropic-specific caveat

Structured outputs cache the JSON **schema** (not prompts or outputs) for up to 24 hours. Keep personal data out of schema property names and enum values; the chip enum and Cart fields are fine.

## Replacement copy for SPEC §10 (Claude)

**Consent screen:**
> Paywise sends only a redacted order summary, such as "Northbay Electronics, Aero 14 Laptop (New), $1,499.00, Mastercard", to Anthropic's Claude API so it can read the items and prices. Card numbers, names and addresses are removed on your iPhone first, and your screenshot never leaves your phone. Anthropic doesn't use this text to train its models. It deletes API inputs and outputs within 30 days, and can keep them longer, up to 2 years, if its safety systems flag them. Tap "What we sent" any time to see exactly what was sent.

**Retention copy:**
> Screenshots are processed in memory and never saved. Purchases you save stay until you delete them. Our AI provider, Anthropic, may keep the redacted order text for up to 30 days, and longer if its safety systems flag it. It isn't used for model training.

**Onboarding privacy copy:**
> We only look when you press. Never in the background.
> Card numbers, names and addresses are removed on your iPhone first.
> Only that redacted order summary is sent for analysis; our AI provider (Anthropic) deletes it within 30 days and doesn't train on it.

**Judge answer, "Aren't you sending my payment screen to Google?" becomes:** "No. The screenshot never leaves your phone. On-device OCR removes anything that identifies you; only something like 'Northbay Electronics, $1,499, 1 laptop' goes to Anthropic's Claude API, which doesn't train on it and deletes it within 30 days. Tap 'What we sent' to see it." *(Say this only if on-device redaction is actually built.)*

**Also change in SPEC §10 / elsewhere:** "(Paid-tier Gemini: no training on prompts; abuse-monitoring logs kept about 55 days. Never the free tier.)" → "(Anthropic API: not used for training; 30-day default deletion; up to 2 years if flagged.)"; `.env.example` `LLM_PROVIDER=gemini` → `anthropic`; the "paid LLM key and billing (who pays?)" sign-up item → "Anthropic Console credits (owner: @Azealoo)".

Before shipping this copy, re-read [Anthropic's commercial data retention article](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data) and confirm 30 days still holds. Also confirm the Console org is on the standard commercial API terms, not a consumer plan, and has no ZDR/other agreement that changes the wording.

## If we pick Gemini instead

Use `gemini-3.1-flash-lite` or `gemini-2.5-flash-lite` with `response_format` JSON schema; keep SPEC §10 copy as written (55 days, paid tier). Setup is the Cloud billing step above. Everything else in this doc (timeouts, validation, fallback to rules parser) applies unchanged.

## Not confirmed

- Any latency figure for either provider.
- Whether Google's 55-day figure is the same on paid and unpaid tiers (page is silent).
- Anthropic's 30-day default from the primary page (seen via search snippet only).
- Current model prices on the day we ship: Claude prices are from the skill's cache dated 2026-10-06; Gemini from the pricing page fetched today.
- Token counts in the cost estimate are my assumptions, not measurements.
