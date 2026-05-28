# Deploy Test Plan

A runnable smoke-test playbook for the three one-click deploy buttons that
ship from this repo: **Render**, **Railway**, and **Koyeb**. All three deploy
the prebuilt image `ghcr.io/liberzon/agents-gateway:latest` via the platform
configs in this repo (`render.yaml`, `railway.toml` + wrapper `Dockerfile`,
`koyeb.yaml`).

The smoke-test sequence at the end is identical across platforms — only
provisioning differs.

---

## Common prerequisites (one-time)

- A **Gemini API key** (cheapest LLM you can use; one provider key is enough
  to smoke-test).
- Pick **one** auth mode for testing:
  - **Easiest:** `AUTH_DISABLED=true` (lets you curl `/v2/*` without a key).
  - **Realistic:** set `ADMIN_SECRET=<random>` and create an API key after
    deploy via `POST /admin/api-keys`.
- Per platform you test, expect ~**$0 to a few cents** if you tear down
  within an hour. Real risk is forgetting to tear down.

---

## Render (easiest — best for first try)

**Button** → <https://render.com/deploy?repo=https://github.com/liberzon/agents-gateway-deploy>

1. Render opens with the blueprint detected (`render.yaml`). Click **Apply**.
2. Add a **Render Postgres** instance (Dashboard → New → PostgreSQL → Free
   tier).
3. On the agents-gateway service → **Environment**, fill the `sync: false`
   vars:
   - `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASS` / `DB_DATABASE` — from
     your Postgres "Connect" panel.
   - `GOOGLE_API_KEY=<your Gemini key>`
   - `ADMIN_SECRET=<anything random>` *(required-for-prod gate)*
   - `AUTH_DISABLED=true` *(add this var even though it's not in the
     blueprint)*
4. **Manual Deploy** → watch logs until "your service is live."
5. Service URL is shown at the top of the service page. Run the
   [smoke test](#smoke-test-identical-for-all-three).
6. **Teardown:** Service → Settings → Delete; Database → Settings → Delete.
   (Free Postgres self-suspends after a week anyway.)

**Cost:** Web Service plan in `render.yaml` is `starter` (~$7/mo prorated)
— you'll be billed ~$0.01 for an hour. Free-tier Postgres is $0.

---

## Railway (next easiest — best Postgres UX)

**Button** → <https://railway.app/template?template=https://github.com/liberzon/agents-gateway-deploy>

1. Railway clones the deploy repo, sees `railway.toml`, builds the wrapper
   `Dockerfile` (fast — just pulls the prebuilt GHCR image).
2. In the project → **+ New** → **Database** → **Add PostgreSQL**.
3. On the agents-gateway service → **Variables**, set these as **Reference
   variables** so they auto-fill from Postgres:

   ```
   DB_HOST     = ${{Postgres.PGHOST}}
   DB_PORT     = ${{Postgres.PGPORT}}
   DB_USER     = ${{Postgres.PGUSER}}
   DB_PASS     = ${{Postgres.PGPASSWORD}}
   DB_DATABASE = ${{Postgres.PGDATABASE}}
   ```

4. Then plain values:

   ```
   GOOGLE_API_KEY = <your Gemini key>
   ADMIN_SECRET   = <random>
   AUTH_DISABLED  = true
   ```

5. **Generate Domain** under Settings → Networking. Run the
   [smoke test](#smoke-test-identical-for-all-three).
6. **Teardown:** Project → Settings → Delete Project.

**Cost:** $5/mo trial credit. A 1-hour smoke test consumes ~$0.05.

---

## Koyeb (most friction because of pre-created secrets)

**Button** → <https://app.koyeb.com/deploy?type=git&repository=github.com/liberzon/agents-gateway-deploy>

`koyeb.yaml` references **named Koyeb secrets** — they must exist *before*
the deploy.

1. Set up Postgres elsewhere first (Koyeb has no first-party managed PG yet):
   - Easiest: **Neon** free tier (<https://neon.tech>) — gives you a
     connection string.
   - Or **Supabase** free.
2. In Koyeb dashboard → **Secrets** → create each of these (only the ones
   actually needed; the others can be empty placeholder strings):
   - `db-host`, `db-port`, `db-user`, `db-pass`, `db-database` →
     Neon/Supabase values.
   - `admin-secret` → random string.
   - `google-api-key` → your Gemini key.
   - For everything else `koyeb.yaml` references (`qdrant-*`,
     `openai-api-key`, `sentry-dsn`, ...), create them with an empty string
     so the YAML resolves.
3. Click the deploy button.
4. Note: you'll need to **manually add `AUTH_DISABLED=true`** as a plain env
   var after the YAML imports (it's not in `koyeb.yaml`).
5. Once "Healthy" → service URL is on the service page. Run the
   [smoke test](#smoke-test-identical-for-all-three).
6. **Teardown:** Service → Settings → Delete; delete Koyeb secrets too;
   delete Neon project.

**Cost:** nano instance free tier (Koyeb gives 1 nano free); Neon free.

---

## Smoke test (identical for all three)

Run this once the service shows healthy. The demo agents are **not** seeded
on these platforms (no `sample_data.sql` is applied), so we create a test
agent ourselves.

```bash
URL=https://your-deployed-service.example.com

# 1. health
curl -fsS "$URL/health"

# 2. proves DB connectivity + ORM table auto-create (lifespan create_all)
curl -fsS "$URL/v2/agents"

# 3. interactive docs load (visit in browser)
echo "$URL/docs"

# 4. create a test agent (requires AUTH_DISABLED=true, or add: -H "X-API-Key: <key>")
curl -fsS -X POST "$URL/v2/agents" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "smoke-test",
    "name": "Smoke Test Agent",
    "template": "Reply with the single word: pong."
  }'

# 5. real LLM call through the deployed gateway (cheapest model, no streaming)
curl -fsS -X POST "$URL/v2/agents/smoke-test/chat" \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Reply with pong",
    "user_id": "smoke",
    "session_id": "smoke",
    "timezone": "UTC",
    "locale": "en-US",
    "model": "gemini-2.5-flash-lite",
    "stream": false
  }'

# 6. cleanup
curl -fsS -X DELETE "$URL/v2/agents/smoke-test"
```

### Pass criteria

| Step | Expected |
|---|---|
| `/health` | `200 {"status":"ok"}` (or similar) |
| `/v2/agents` | `200` returning a JSON array (empty initially) |
| `POST /v2/agents` | `200` with the created agent's record |
| `POST /v2/agents/.../chat` | `200`, body has `content` field with the Gemini reply (e.g. `"pong"`), echoes `model` |
| `DELETE /v2/agents/...` | `200` or `204` |

Anything else (5xx, timeouts, "prompt not found") = real bug → save the
gateway logs and dig in.

---

## Common gotchas

- **Cold-start latency** on first chat (~10–30 s while the agno framework
  loads + makes the first provider call). Subsequent chats are fast.
- **Postgres connection refused** at first boot if the DB isn't ready yet.
  The wrapper image starts on the entrypoint without `WAIT_FOR_DB=true`,
  so set that env var if your platform's DB takes a moment to provision.
- **Render free Postgres** has a connection cap (~5) and pauses after 30
  days idle — fine for a smoke test, not for prod.
- **Koyeb secret resolution** fails the whole deploy if one referenced
  secret is missing — create even the ones you don't use, with an empty
  string.
