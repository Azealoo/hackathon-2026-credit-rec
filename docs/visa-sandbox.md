# Visa Acceptance (Cybersource) sandbox: setup for SPEC §11.2 / gate G4

Status: researched 2026-10-14. Items marked **(u)** are unconfirmed; where each was looked up is in [Sources](#sources). Claude does not create the account: you do.

## 1. What you must do today

Owner: B (backend). SPEC §14 says to submit the sign-up in the first 15 minutes of tonight's work, because activation can stall.

1. **Sign up** (about 5 minutes) at <https://developer.cybersource.com/hello-world/sandbox.html>. The form asks for:
   - an **Organization ID**: use something like `fineprint_sandbox` (6–25 letters, digits or underscores; the page says it can't easily be renamed). **This is your merchant ID.**
   - company, name, country, state, city, ZIP, email and phone. Use a real, monitored email: activation arrives there. Use a team inbox, not a personal one, if one exists.
   - the "Payment Technology Provider" question: answer No.
   - Terms and a reCAPTCHA, then **Create Account**. You must tick and solve these yourself.
2. **Watch the inbox** for the email with a link to create your user login for the Test Enterprise Business Center (`ebc2test.cybersource.com`). Open it and set a password.
3. **If it arrives**, log in at <https://ebc2test.cybersource.com/ebc2>, then do the key steps in §3 (about 5 minutes) and put the three values in the host's environment (§3).
4. **If nothing has arrived a few hours after signing up, and no later than Thu 15 Oct, 9 PM**, follow §2 (stall).
5. **Hard stop: Fri 16 Oct, 12 PM.** If the account can't log in and make a key by then, set `PAY_MODE=mock` and remove every Visa-API claim (SPEC G4, §14.4 item 3).

Do **not** paste the password, key ID or secret into chat, an issue, a PR, or any file in the repo.

## 2. Activation time and what to do if it stalls

- **Usual time: unconfirmed (u).** The sign-up page doesn't state one. The REST getting-started guide says creating a merchant user account "takes up to two minutes" (that guide is about a merchant account, so the sandbox may differ). Plan for the email within minutes and treat anything past a few hours as a stall.
- **Known failure mode** (community forum reports, anecdotal): the activation link returns an internal server error. Reported fixes, in order:
  1. Wait 15 minutes; check spam.
  2. Open the link in a private window or another browser.
  3. Re-submit sign-up with a **new** Organization ID (the old one may be half-created) and a different email.
  4. Ask on the [Cybersource developer community](https://community.developer.cybersource.com/) and the Visa developer support channel, and ask at the Visa table / Discord on the day (SPEC §13 Discord questions).
- **Fallback is already designed:** `PAY_MODE=mock` returns the same `/v1/store/pay` response with `processor: "mock"` (SPEC §15.5). The confirmation then must not say "Visa Acceptance" anywhere.

## 3. Credentials: what to create, where each goes

Create these in the **test** Business Center. Test and production keys are separate (per Cybersource's docs), so sandbox keys never work live.

| Credential | How to get it | Env var (SPEC §15.5) |
|---|---|---|
| Merchant ID | The Organization ID you chose at sign-up. | `VISA_ACCEPTANCE_MERCHANT_ID` |
| Key ID (serial number) | Shown with the key after you generate it, and later under Key Management > Key Detail. | `VISA_ACCEPTANCE_KEY_ID` |
| Shared secret | Shown once when you generate the key. | `VISA_ACCEPTANCE_SECRET_KEY` |
| Test card map | You write it, from the published test cards (§5). | `DEMO_TEST_CARD_MAP` |

Key steps (menu names differ between Business Center versions; the doc pages disagree on labels, so follow what you see):
1. Log in at `ebc2test.cybersource.com/ebc2`. If there is a **Switch View** button, switch to your test merchant.
2. **Payment Configuration > Key Management** (older docs: Transaction Processing > API Keys).
3. **Generate Key** > choose **REST – Shared Secret** > **Generate Key**.
4. Copy the key ID and the secret now (clipboard or download). **Once you close the screen the secret can't be retrieved**; you'd have to generate a new key. Keys last 3 years.

Where they go:
- **The deployed backend's environment variables** (the HTTPS host's dashboard), and a local `.env` that is gitignored. Never in the repo, the iOS app, a screenshot, or a log.
- `.env.example` keeps `changeme` placeholders only (already in SPEC §15.5).
- `DEMO_TEST_CARD_MAP` maps our fake saved-card IDs to processor test cards, only in the deployed environment (SPEC §15.2). The format is ours to choose when `visa_acceptance.py` is written, for example JSON `{"demo-visa-1234": "<test card number from §5>"}` in the host's secret store. Real or test card numbers must not appear in code, tests, fixtures, logs or this repo (CLAUDE.md rule).

Hand the three values to whoever sets up the host over a password manager or the host dashboard directly, not chat.

## 4. Sandbox endpoint and auth for one card authorization (Python)

- **Base URL:** `https://apitest.cybersource.com` (sandbox) vs `https://api.cybersource.com` (production). Authorization is `POST /pts/v2/payments`.
- **Sandbox is USD only** (stated by the Visa Acceptance WordPress plugin page; (u) for the REST API itself). Demo amounts are USD, which matches `amountUsd`.

### Auth: HTTP Signature (shared secret)

Headers on every request:

| Header | Value |
|---|---|
| `v-c-merchant-id` | the merchant ID |
| `Host` | `apitest.cybersource.com` |
| `Date` | current time in GMT, RFC 7231 format |
| `Digest` | `SHA-256=` + base64(SHA-256(request body)) |
| `Content-Type` | `application/json` |
| `Signature` | `keyid="<key ID>", algorithm="HmacSHA256", headers="host date (request-target) digest v-c-merchant-id", signature="<base64>"` |

Signature string: one `name: value` line per signed header, in the same order as `headers=`, joined by newlines:

```
host: apitest.cybersource.com
date: <Date header value>
(request-target): post /pts/v2/payments
digest: SHA-256=<digest>
v-c-merchant-id: <merchant ID>
```

`signature` = base64(HMAC-SHA256(that string, **base64-decoded** shared secret)).

Caveats:
- **(u) `(request-target)` spelling.** A Cybersource developer-blog post says the parenthesised form is being retired in favour of `request-target` (both accepted for a time). Start with the form shown in the current Getting Started guide and switch if you get a 401. Whichever is used must match the `headers=` list.
- **(u) Deprecation.** A package listing says HTTP Signature is being deprecated in favour of JWT with the same key ID and secret. I found no official page or date. HTTP Signature is the documented, simplest scheme and works for the demo.
- The official guide's own GET example shows an RSA algorithm value that contradicts the HmacSHA256 text. For a shared-secret key, use HmacSHA256.
- Cybersource also publishes an official Python SDK (`cybersource-rest-client-python`, **(u)** not checked here). It signs for you and is the "off-the-shelf" option from the project preferences. Decide when `backend/app/visa_acceptance.py` is written; this doc ships no code.

### Minimal request (fake values; field names per Cybersource's REST payments docs, **(u)** exact minimal set not re-verified against the Process a Payment page)

```json
{
  "clientReferenceInformation": { "code": "NB-100234" },
  "processingInformation": { "capture": false },
  "paymentInformation": {
    "card": {
      "number": "<TEST CARD NUMBER from §5>",
      "expirationMonth": "12",
      "expirationYear": "2031",
      "securityCode": "123"
    }
  },
  "orderInformation": {
    "amountDetails": { "totalAmount": "1499.00", "currency": "USD" },
    "billTo": {
      "firstName": "Alex",
      "lastName": "Doe",
      "address1": "123 Example St",
      "locality": "Seattle",
      "administrativeArea": "WA",
      "postalCode": "98000",
      "country": "US",
      "email": "alex@example.com",
      "phoneNumber": "5550100000"
    }
  }
}
```

`capture: false` makes it an authorization only (no settlement, no money moves). The bill-to values are the fake identity from SPEC §15.

### Example response (shape only; values fake, **(u)** exact field set)

HTTP `201` on success (reported in Cybersource community material; not confirmed on the official page):

```json
{
  "id": "0000000000000000000000",
  "status": "AUTHORIZED",
  "clientReferenceInformation": { "code": "NB-100234" },
  "orderInformation": { "amountDetails": { "authorizedAmount": "1499.00", "currency": "USD" } },
  "processorInformation": { "approvalCode": "000000", "responseCode": "00" },
  "submitTimeUtc": "2026-10-16T18:00:00Z"
}
```

- `id` is the **transaction ID** to show on the confirmation page and return as `transactionId` from `/v1/store/pay`.
- Mapping to SPEC `status`: `AUTHORIZED` → `approved`; `DECLINED` / `AUTHORIZED_PENDING_REVIEW` / others → `declined`; HTTP errors, timeouts or bad signatures → `error`. **(u)** the full status list isn't confirmed; handle unknown values as `error`.
- Sandbox outcomes are driven by the amount, not the card number (community report, (u)); the "test data" pages list triggers.

## 5. Official test card numbers: link only

Don't copy numbers into the repo, this doc, issues, PR text or chat logs.

- Cybersource's testing guide (sandbox instructions and test data): I could not confirm its URL (several docs URLs I tried returned 404). Open <https://developer.cybersource.com/> and search "Testing" / "test card numbers" under Getting Started. **(u)**
- Per the Account Updater test guide, Cybersource's test environment points to its per-network lists: Visa, Mastercard, American Express test card numbers: <https://developer.cybersource.com/library/documentation/dev_guides/Account_Updater_UG/html/Topics/ch_testing.htm>.
- Visa's own pages on developer.visa.com: I could not find an official test-card page there; Visa's developer site points Cybersource users to developer.cybersource.com / developer.visaacceptance.com **(u)**.
- Use only cards from those pages. Third-party "test card" sites turned up in search; ignore them.

Check: use a **Visa** test card for the Visa ••1234 demo card so the story stays Visa.

## 6. Open questions

- Time to activation: unknown (§2).
- Whether the sandbox account needs a separate "enable payments" step before `/pts/v2/payments` works: unknown (u); the first hello-world call (Fri 9 AM–12 PM in SPEC §14) will show it.
- Whether the sign-up form wants a real company: use "Fine Print (DubHacks '26 project)"; (u) whether anything is checked.

## Sources

Looked up 2026-10-14. Pages fetched successfully are marked ✓; the rest came only from search snippets.

- ✓ Sandbox sign-up: <https://developer.cybersource.com/hello-world/sandbox.html>
- ✓ HTTP Signature auth: <https://developer.cybersource.com/library/documentation/dev_guides/REST_API/Getting_Started/html/REST_GS/ch_authentication.5.3.htm>
- ✓ Creating a shared secret key (older guide): <https://developer.cybersource.com/library/documentation/dev_guides/REST_API/Getting_Started/html/REST_GS/ch_registration.4.2.htm>
- Creating a REST API key (current docs; 404 when fetched, snippet only): <https://developer.cybersource.com/docs/cybs/en-us/security-keys/user/all/ada/security-keys/keys-rest-create.html>
- Getting started with REST (merchant account, "up to two minutes"; snippet only): <https://developer.cas.cybersource.com/docs/cybs/en-us/ebc/gettingstarted/all/rest/doc101_ebc.html>
- Visa Acceptance sandbox / testing overview (snippet only): <https://developer.cybersource.com/docs/vas/en-us/isv-plugins/get-started/all/na/isv-getting-started.html>
- Account Updater testing (test card lists by network; snippet only): <https://developer.cybersource.com/library/documentation/dev_guides/Account_Updater_UG/html/Topics/ch_testing.htm>
- Samsung Pay REST authorization example (field names for payments request/response): <https://developer.cybersource.com/docs/cybs/en-us/samsung-pay/developer/ctv/rest/samsungpay/samsungpay-auth-cybsdecrypt-ex-amex-rest.html>
- Activation-link problems (community, anecdotal): <https://community.developer.cybersource.com/t5/Integration-and-Testing/I-can-t-activate-my-developer-test-account/m-p/94601>
- `(request-target)` change (community blog): <https://community.developer.cybersource.com/t5/cybersource-Developer-Blog/U-p-d-a-t-e-REST-API-Http-Signature-Authentication-Critical/ba-p/87319>
- Visa developer site (no sandbox page found): <https://developer.visa.com>
