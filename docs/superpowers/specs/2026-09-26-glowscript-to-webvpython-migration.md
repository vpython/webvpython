# glowscript.org → webvpython.org Migration Plan

**Date:** 2026-09-26
**Status:** Planning. Nothing below has been executed yet except where marked.
**Supersedes nothing.** The 2026-06-05 sync spec brought flaskHost and the runners up
to date with Classic; this document covers moving production traffic.

---

## End state

| Hostname | Serves | Backend |
|---|---|---|
| `webvpython.org`, `www.webvpython.org` | IDE, API, docs (`/docs/…`) | Cloud Run `flaskdstorehost` (project `glowscript`) |
| `run.webvpython.org` (name TBD) | RS and WASM runners (untrusted user code) | GCS `rswvprunner` / `wmvprunner` via a thin proxy (see Phase 2) |
| `glowscript.org`, `www.glowscript.org` | 301 → `webvpython.org`, path preserved | Cloudflare Redirect Rule (no server) |
| `legacy.glowscript.org` | Classic GlowScript, as a fallback | GAE app, project `glowscript` |
| `sandbox.glowscript.org` | Classic's untrusted runner | GAE app (unchanged) |

All of the above are proxied by Cloudflare.

---

## Current state (verified 2026-09-26)

**Projects**
- `glowscript`: the Classic GAE app (glowscript.org, www, sandbox) **and** the Cloud Run service
  `flaskdstorehost` (beta.webvpython.org, via a Cloud Run domain mapping created 2026-06-11).
- `glowscript-py38`: the GAE app for glowscriptdev.spvi.net, plus the GCS buckets `rswvprunner`,
  `wmvprunner`, `glow-docs`.

**One shared database.** Classic (`main.py:22`, `ide/routes.py:75`) and flaskHost
(`src/ndb_models.py:21`) both call `ndb.Client(project=None)`, so each uses its own GCP
project's Datastore, and both run in project `glowscript`. Beta and Classic read and write the
same users, folders and programs. This is what makes `legacy.glowscript.org` a real fallback: a
user who goes back sees the same work.

> ⚠️ `make serve-prod` points local Flask at **`glowscript-py38`**, not `glowscript`, even though
> it warns about "LIVE production data". Billing shows almost no reads in `glowscript-py38`, so
> it looks like the glowscriptdev database. Decide whether that is intended (a safer prod-like
> copy) and fix either the target or the warning.

**DNS.** Both `glowscript.org` and `webvpython.org` are at GoDaddy (`domaincontrol.com`), with
no DNSSEC (no DS records), so there's no DNSSEC to switch off before changing nameservers.
`webvpython.org` apex is a GoDaddy forward page; `beta.webvpython.org` is a CNAME to
`ghs.googlehosted.com`.

**Cost, Classic GAE** (Cloud Billing export `instructormi.billing.gcp_billing_export_v1_*`):

| Month | App Engine total | Firestore reads+writes | Instances | Out bandwidth |
|---|---|---|---|---|
| 2026-08 | $15.99 | $7.01 | $5.50 | $2.08 (46.7 GB) |
| 2026-09 (26 days) | $37.80 | $17.47 | $12.43 | $6.94 (88.7 GB) |

Beta (`flaskdstorehost` + buckets) costs pennies today, but it has almost no traffic yet.

**Classic traffic profile** (sample of 5,000 requests, 2026-09-26):
- About **95% of outgoing bytes are `/package/*` (82%) and `/lib/*` (13%)**. A single package
  file is ~4.4 MB and is served with `Cache-Control: public, max-age=600`, so browsers fetch
  it again after 10 minutes.
- The most frequent API call is **`PUT …/program/<name>` (autosave)**, about 2× program GETs.
  The IDE saves 1 s after typing stops (`ide/ide.js:1466`), and each save does 3–4 reads plus a
  write. Two of those reads are the same User entity, once in `parseUrlPath` and again in
  `authorize_user`.
- Background noise: `/wp-admin`, `/.aws`, `/.well-known` scans.

---

## Constraints

1. **The runner must stay on a different origin from the IDE.** The runner executes student
   code, and the IDE origin holds the session cookie and returns the CSRF secret from
   `/api/login`. Classic does this with `sandbox.glowscript.org`; the new stack must keep a
   separate hostname (`run.webvpython.org` or similar). Docs are trusted content and can live
   on the IDE origin.
2. **Legacy stays independent.** The fallback only helps if a bug in the new stack doesn't
   also break it. Don't make Classic load its runtime from the new runner buckets; copy fixes
   to it deliberately (Phase 5).
3. **Allowed-origin lists must be updated together:** runner `build.env` `TRUSTED_HOST`
   (rsWVPRunner and wmWVPRunner), Google OAuth authorized redirect URIs, and Classic's
   sandbox parent-origin check if `legacy.glowscript.org` is to use `sandbox.glowscript.org`.
4. **Logins don't carry over.** Session cookies are per domain, so users signed in on
   glowscript.org sign in again on webvpython.org. Programs are unaffected (shared database).

---

## Phases

Each phase is independently deployable and reversible.

### Phase 0: Move both zones to Cloudflare (no behavior change)

Same procedure as the trinket migration (see the Cloudflare CDN runbook on the Desktop,
2026-09-20):
1. Export each zone from GoDaddy; import into Cloudflare; verify record by record.
2. SSL/TLS **Full (strict)**, per zone.
3. Flip nameservers at GoDaddy.
4. Turn on the Cloudflare proxy (orange cloud) record by record, checking each host.

**Certificate renewal.** GAE and Cloud Run domain mappings use Google-managed certificates.
Check that they keep renewing once proxied. If one doesn't, upload a Cloudflare **Origin CA**
certificate (valid 15 years) to GAE (`gcloud app ssl-certificates create`, then set the
domain mapping to manual certificates). Don't use Flexible mode.

### Phase 1: Cache Classic's static files at the edge (glowscript.org)

The immediate win, since Classic carries all the real traffic until cutover.
- Cache Rule (operator **wildcard**, not `equals`): `/package/*`, `/lib/*`, `/css/*`
  → eligible for cache, Edge TTL override **1 day**.
- Package files are rebuilt under the same name (e.g. `glow.3.2.min.js`), so **purge the
  Cloudflare cache after every Classic deploy** (dashboard button or API). Add that step to
  whatever deploys Classic.
- Optional: set `default_expiration` in `app.yaml` so browsers keep files longer than 10 min.
- Expected effect: most of the 88.7 GB/month of GAE egress stops reaching Google.

### Phase 2: New-stack hostnames and docs on the main domain

- **Docs:** serve `/docs/…` from `flaskdstorehost` (proxying `glow-docs`), so docs share the
  IDE's URL. With Cloudflare caching `/docs/*`, Cloud Run sees only cache misses.
- **Runners:** a separate hostname. Either a tiny Cloud Run proxy that reads the buckets, or
  keep `storage.googleapis.com` for now. Avoid a Google Cloud Load Balancer with backend
  buckets: its forwarding rule costs ~$18/month before any traffic.
- **Cache headers:** GCS sends `max-age=3600` by default, and `rsWVPRunner/do_build.sh` uploads
  with `gsutil cp -r`, which never deletes stale objects and sets no `Cache-Control`. Either set
  cache-control on upload and rely on the build-date stamp in `run.js`, or purge after each
  runner deploy.
- Update `build.env` in both runners and the OAuth redirect URIs for the new hostnames.
- Move `OAUTH_CLIENT_SECRET` on `flaskdstorehost` from a plain env var to Secret Manager.

### Phase 3: Cut database reads and writes (flaskHost first)

flaskHost copied Classic's pattern (`src/routes.py:357` in `parseUrlPath`, `:272` in
`authorize_user`). Fix it there, since that's where traffic is going:
1. Fetch the User once per request (share it between `parseUrlPath` and `authorize_user`).
2. Autosave: don't `PUT` if the source hasn't changed since the last save; consider a longer
   debounce than 1 s (`src/ide.js:1673`, `:2102`).
3. Measure before and after from the billing export (Firestore Read Ops / Entity Writes).

Optional: backport to Classic, which pays the bill today.

### Phase 4: Cutover

1. `webvpython.org` + `www` → `flaskdstorehost` (Cloud Run domain mappings; keep `beta.` too).
2. Map `legacy.glowscript.org` to the GAE app; add it to OAuth redirect URIs and to the
   sandbox's allowed parents.
3. Cloudflare Redirect Rule: `glowscript.org/*` and `www.glowscript.org/*` →
   `https://webvpython.org/$1`, 301. Program links are hash-based (`/#/user/…`); browsers carry
   the fragment across a redirect, so deep links keep working.
4. Announce `legacy.glowscript.org` as the way back.

**Rollback:** delete the redirect rule. glowscript.org serves Classic again immediately, and no
data needs migrating because the database is shared.

**Check before cutover:** third-party pages that embed glowscript.org in iframes. A redirect
works for top-level pages, but confirm embeds follow it and are allowed to be framed on
webvpython.org.

### Phase 5: Keep legacy in sync, deliberately

`rsWVPRunner` is now ahead of Classic (vec kwargs, acorn fix, `print()` messages). Add a
`make sync-classic` target that copies `rsWVPRunner/package/` and `rsWVPRunner/lib/` into
`glowscript/` for review, commit and deploy, then purges Cloudflare. Run it only when you've
decided a fix belongs in legacy.

### Phase 6: Retire (later)

Once legacy traffic is negligible: remove the GAE domain mappings and disable the app. With
automatic scaling and no minimum instances, an idle GAE app costs almost nothing, so there's no
rush.

---

## Open questions

- `make serve-prod` database target (see Current state).
- Final name for the runner hostname.
- Whether Classic should get the Phase 3 database fixes.
