# GlowScript Migration Sync Design

**Date:** 2026-06-05  
**Goal:** Update flaskHost and the two runners (wmWVPRunner, rsWVPRunner) with changes from Classic GlowScript, with the intent of migrating production traffic from Classic to the new setup.

---

## Context

The project has four repos:

| Repo | Purpose | Status |
|---|---|---|
| `glowscript/` | Classic GlowScript (Flask + App Engine + NDB) | Active, source of truth |
| `flaskHost/` | Modern Flask host (MongoDB DB layer, Monaco editor) | Stagnant ~1 year |
| `wmWVPRunner/` | WASM/Pyodide runner for Python programs (SvelteKit) | In-progress Pyodide upgrade branch |
| `rsWVPRunner/` | RapydScript runner (static file deployment) | Stagnant ~1 year |

Classic has continued to evolve while the other repos have not. The goal is to bring flaskHost and both runners up to date so they can replace Classic in production.

---

## What Is NOT Changing

- **`package/` compiled JS files** — identical across all repos, no action needed
- **`lib/glow/*.js` (flaskHost)** — already in sync with Classic
- **`css/`** — identical across repos
- **`flaskHost` UI** — Monaco editor, `index.html`, `ide.js` UI code are intentional divergences, kept as-is
- **`flaskHost` DB layer** — `db_translate.py`, `mongo_models.py`, `ndb_models.py` preserved; new models added alongside
- **`rsWVPRunner` `untrusted/run.html` and `run.js`** — intentionally modified for runner concept; not synced from Classic
- **`wmWVPRunner` `vpython/` package** — Pyodide-specific, no Classic counterpart

---

## Phase 1: rsWVPRunner

**Scope:** Two file copies only.

1. Copy `lib/glow/extrude.js` from `glowscript/lib/glow/extrude.js`
2. Copy `lib/glow/primitives.js` from `glowscript/lib/glow/primitives.js`

**Verification:** Files match Classic byte-for-byte after copy. Commit to rsWVPRunner.

---

## Phase 2: wmWVPRunner

**Scope:** Merge the Pyodide upgrade branch and fix the build step.

1. **Merge `upgrade-pyodide-v0.29.4` into `main`** — upgrades Pyodide CDN reference from v0.23.3 to v0.29.4 across `+layout.svelte`, `+page.svelte`, and `utils.js`; adds test harness (`test/index.html`) and `netlify.toml`
2. **Update `do_build.sh`** — add `npm run zip` before `npm run build` so `vpython.zip` is always freshly built from the `vpython/` directory before deployment
3. **Confirm `static/vpython.zip` is not tracked in git** — the binary should not be committed; confirm it is gitignored or removed
4. **Update `CLAUDE.md`** — reflect new Pyodide version and updated build step

**Build flow after change:**
```
npm run zip        # builds static/vpython.zip from vpython/
npm run build      # SvelteKit build → build/ (includes vpython.zip via static/)
gsutil cp build/*  # deploys to GCS bucket
```

**Verification:** `npm run zip && npm run build` completes without error; `build/vpython.zip` is present.

---

## Phase 3: flaskHost

**Scope:** Port new backend functionality from Classic, adapted to the MongoDB DB layer.

### 3a. Security and infrastructure

- Upgrade Authlib to 1.6.7 in `requirements.txt` (fixes CVE-2026-28802, JWT alg:none bypass)
- Update `Dockerfile` to Python 3.12
- Review Classic's `requirements.txt` for other dependency updates worth pulling in

### 3b. User count / analytics routes

Port from Classic's `routes.py`, adapting NDB/Datastore calls to MongoDB:

- **`/admin/update-user-count`** — cron endpoint that records a snapshot of current active user count; in Classic uses raw Datastore, in flaskHost stores in a new MongoDB collection (e.g., `user_history`)
- **`/plotusers`** — renders a Plotly chart of user count over time, reading from the history collection

Data model for flaskHost (new, alongside existing models):
```
user_history document: { timestamp: datetime, count: int, points: [...] }
```

### 3c. Templates

- **`plotusers.html`** — port from Classic, adapting template variable style to match flaskHost's Jinja2 conventions
- **`groups.html`** — review whether this is relevant to flaskHost; port if applicable

### 3d. routes.py diff methodology

Perform an annotated diff between `glowscript/ide/routes.py` and `flaskHost/src/routes.py`, categorizing each difference as:

- **(A) New functional addition from Classic** → port, adapt to MongoDB
- **(B) Classic formatting/import reordering** → ignore
- **(C) flaskHost-specific improvement** → keep as-is

Only category (A) changes are ported.

### 3e. ide.js spot-check

Review the 455-line diff between `glowscript/ide/ide.js` and `flaskHost/src/ide.js` to identify any backend-communication changes in Classic (e.g., changed API call signatures, new postMessage protocol changes). Port only those; leave all Monaco editor code untouched.

**Verification:** flaskHost runs locally with Docker; `/plotusers` route loads; `/admin/update-user-count` stores a record; existing program save/load/run flows unaffected.

---

## Execution Order

```
Phase 1: rsWVPRunner   (file copies, ~30 min)
Phase 2: wmWVPRunner   (branch merge + build fix, ~1 hr)
Phase 3: flaskHost     (route porting + templates, ~half day)
```

Each phase is independently committable and testable before the next begins.
