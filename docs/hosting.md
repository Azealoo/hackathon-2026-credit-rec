# Hosting: HTTPS host for the demo store and FastAPI backend

Written Oct 14, 2026 for SPEC.md §9.2, §9.3, §14.2 and §15.7 step 5.
**Recommendation: Render, Static Site on Thursday, then one paid Starter Web Service ($7/mo) from Friday.**
Marks: **(c)** confirmed on an official page I fetched today; **(u)** not confirmed, check before relying on it.

## Requirements
1. Static store over HTTPS on cellular by Thu Oct 15, 11 PM.
2. From Fri, FastAPI (Python 3.12, uvicorn) serves `/v1/*` and `/store/` on one host.
3. Secrets as environment variables.
4. No sleep or cold start Oct 17–18 (the phone gives up at 6.0 s; §9.1).
5. Cheap or free for one weekend; simple; mature and off the shelf.

## Comparison

| | Render | Railway | Fly.io | Google Cloud Run |
|---|---|---|---|---|
| Cost for the weekend | Starter web service **$7/mo (c, via Render pricing page snippet; the pricing page itself loaded without figures)**; billed pro-rata, so about $1–2 if deleted on Mon (u: proration). Workspace plan fee: Hobby workspace believed $0 (u). Static Site free (u) | Hobby plan **$5/mo, includes $5 usage (c)**; 0.5 GB RAM + 0.5 vCPU running 24/7 ≈ $5 + $10 = ~$7.50/mo at the published rates ($10/GB-mo, $20/vCPU-mo) (c), so likely ≈ $5–8 total | shared-cpu-1x: **$2.19/mo (256 MB), $3.69/mo (512 MB)** (c); no free tier; trial is only 2 machine-hours or 7 days (c); card required (c) | Pay per use with a monthly free tier and `min-instances=1`. Exact rates **not confirmed** (pricing page did not render); idle min-instance is billed at a reduced rate (c, min-instances doc) |
| Sleep / cold start | Free tier spins down after 15 min idle and takes about 1 min to wake (c, render.com/docs/free). Paid instances: not described as sleeping on that page; Render staff say paid avoids it (via search, u). Can be restarted for maintenance (u) | Sleeping is opt-in "Serverless"; off by default, so no cold start unless enabled (c, docs.railway.com app-sleeping) | Machines can auto-stop/auto-start; a Machine kept running (`min_machines_running = 1`, `auto_stop_machines = off`) does not sleep (u: config names from memory) | Scales to zero by default; `min-instances=1` keeps one warm, best-effort (c) |
| Setup effort | Lowest: connect GitHub, a `render.yaml`, or click-through; dashboard env vars; managed TLS (c) | Low: connect GitHub, Nixpacks/Railpack auto-detect (u), env vars in dashboard | Medium: `flyctl`, Dockerfile or buildpacks, `fly secrets` | Highest: GCP project, billing, `gcloud`, container build, IAM |
| Region near Seattle | Oregon (u: from memory) | US West (u) | `sea` (u) | `us-west1` Oregon / `us-west2` (u) |
| Risk | Must pick paid plan; free is a trap | Credit-based billing surprises; less predictable | Cheapest; more ops work, shared IPv4 + 1 cert are free (c) | Billing setup and IAM friction for one weekend |

## Recommendation: Render

- **Simplest** thing that meets every requirement. No Dockerfile, native Python runtime, dashboard secrets, free managed TLS (c), health checks and zero-downtime deploys (c).
- The only trap is the Free web service (sleeps after 15 min, ~1 min wake-up, c). Avoid it by choosing **Starter** for the backend. Free is fine for the **Static Site** on Thursday because it has no process to sleep (u: confirm in the dashboard that Static Site shows $0).
- Cost: about $7 for the month at most, and deleting the service after the event stops billing.
- **Runner-up: Railway Hobby** (nearly as simple, similar cost). **Cheapest: Fly.io** if someone on the team already knows `flyctl`. Cloud Run is the most work for no benefit here.

Not verified: Render's real cold-start latency on Starter after a deploy or maintenance restart. Mitigation below.

## Setup

### Part 1: What you do (about 20 min, Thu night)

Tonight, for the static store:
1. Sign up at render.com with GitHub (`Azealoo`). Add a card only when the dashboard asks.
2. Install the Render GitHub app on `Azealoo/hackathon-2026-credit-rec` (limit it to that repo).
3. **New → Static Site** → select the repo. Branch `main`. Build command empty. **Publish directory `demo-store`**. Create.
   - If `demo-store/` isn't merged yet, tell Claude and it will point the service at the right branch.
4. Open the `https://<name>.onrender.com` URL on your iPhone **on cellular (Wi-Fi off)** and load `checkout.html?item=laptop`. That is the Thu 11 PM gate. Paste the URL into the team chat.

Friday morning, for the backend (needs a card):
5. **New → Web Service** → same repo, branch `main`. Runtime **Python 3**. Region **Oregon** (closest to Seattle (u)). **Instance type Starter**, never Free.
6. Build command: `pip install ./backend`. Start command: `cd backend && uvicorn app.main:app --host 0.0.0.0 --port $PORT`. Health check path `/health`. (Adjust if the skeleton's `pyproject.toml` layout differs; Claude can fix this.)
7. **Environment**, add each yourself (Claude never sees the values):
   `PYTHON_VERSION=3.12.7` (any 3.12.x), `LLM_API_KEY`, `LLM_MODEL`, `PARSER_MODE`, `COVERAGE_MODE`, `PAY_MODE`, `VISA_ACCEPTANCE_MERCHANT_ID`, `VISA_ACCEPTANCE_KEY_ID`, `VISA_ACCEPTANCE_SECRET_KEY`, `DEMO_TEST_CARD_MAP`, `PUBLIC_BASE_URL=https://<name>.onrender.com`. (Names per `.env.example`, §15.5; the LLM key name may differ.)
8. Turn **Auto-Deploy** on for `main` until Fri 10 PM, then **off** (a surprise deploy during the event is the main outage risk).
9. Give Claude the service URL. Optionally create a Render API key for deploy checks. Skip it if you'd rather click.

Sat morning: Render dashboard → service → Metrics; confirm the instance type shows Starter. **After the event:** delete both services.

### Part 2: What Claude does from the repo

1. Confirm `docs`/skeleton paths: `demo-store/` at repo root; `backend/app/main:app`.
2. In `backend/app/main.py`, mount the store: `app.mount("/store", StaticFiles(directory=ROOT / "demo-store", html=True), name="store")` (ROOT resolved from `__file__`, since the process cwd differs). Add `/health` → `{"ok": true}` (already §15.7 step 0). Do not log request bodies.
3. Commit the proposed config below as `render.yaml` once the skeleton exists (optional; the dashboard route above works without it).
4. Add `PUBLIC_BASE_URL` handling and a smoke script `scripts/smoke.sh` that curls `/health`, `/store/`, and a fake `POST /v1/check`, printing HTTP code and `time_total`.
5. Fri 6 PM and Sat 8:30 AM: run the smoke script against the live URL.
6. **Keep-warm (belt and braces):** if anything is idle for long, ping `/health` every 5 min from a Mac `launchd`/cron job or a free uptime monitor (the monitor is a third-party account; the user's call). Not needed for a paid Starter instance as documented, but cheap insurance against an unannounced restart.
7. Measure cold-ish latency: after a manual restart in the dashboard, time the first `/v1/check`. If it exceeds about 3 s, tell the team so the replay path (§15.8) covers it.

## Proposed deploy config (inline, not committed)

`render.yaml` (Blueprint), to add once the skeleton exists:

```yaml
services:
  - type: web
    name: fineprint
    runtime: python
    plan: starter
    region: oregon
    rootDir: backend
    buildCommand: pip install .
    startCommand: uvicorn app.main:app --host 0.0.0.0 --port $PORT
    healthCheckPath: /health
    autoDeploy: true   # set false after Fri 10 PM
    envVars:
      - key: PYTHON_VERSION
        value: 3.12.7
      - key: PARSER_MODE
        value: llm
      - key: COVERAGE_MODE
        value: llm
      - key: PAY_MODE
        value: mock
      - key: PUBLIC_BASE_URL
        sync: false
      - key: LLM_API_KEY
        sync: false
      - key: VISA_ACCEPTANCE_SECRET_KEY
        sync: false
```

`sync: false` means the dashboard asks for the value; nothing secret enters git. Caveat: with `rootDir: backend`, `demo-store/` sits outside the build root. If Render's build can't see it at runtime (u), either drop `rootDir` and use `pip install ./backend` with `cd backend` in the start command, or copy `demo-store` into the package at build time. Verify on the first Friday deploy.

## Open items
- (u) Exact Render Starter price, workspace plan fee, and Static Site price; I could not load Render's pricing figures from the official page. Confirm in the dashboard before adding the card.
- (u) Cloud Run and Fly auto-stop details, region names.
- (u) Whether Render restarts paid instances on its own during the event window.
- The `LLM_API_KEY` name is a guess; it is not in the `.env.example` excerpt in §15.5.

Sources: render.com/docs/free (c) · render.com/docs/web-services (c) · docs.railway.com/reference/pricing/plans (c) · docs.railway.com/reference/app-sleeping (c) · docs.fly.io/about/pricing (c) · docs.cloud.google.com/run/docs/configuring/min-instances (c) · Render pricing snippet via web search (u) · cloud.google.com/run/pricing (did not render).
