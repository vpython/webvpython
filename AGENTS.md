There is a classic version of GlowScript in the GlowScript directory. That's basically a Flask application that handles everything. There's a more modernized version of the Flask application and separate runners and separate documentation repositories in the Flask host, the WASM runner, the rapid script runner, and the documentation directories 

Classic Glowscript: ./glowscript

Flask Host: ./flaskHost
Wasm Runner: ./wmWVPRunner
Rapyd Script Runner: ./rsWVPRunner
Docs: ./webVPythonDocsHome

The Flask Host and Runners were synced with Classic GlowScript in June 2026. See `docs/superpowers/specs/2026-06-05-glowscript-migration-sync-design.md` for what was done.

## Second public URL: beta.webvpython.org

Added June 2026. Both `https://flaskdstorehost-dhppn6xgeq-uc.a.run.app` and `https://beta.webvpython.org` are live.

### Adding another domain in the future

1. **Cloud Run domain mapping** — add domain to the existing `flaskdstorehost` service:
   ```bash
   gcloud run domain-mappings create --service flaskdstorehost --domain <new-domain> --region us-central1
   ```
   Then add the DNS records Cloud Run provides at the domain registrar.

2. **Redeploy runners** — update `build.env` in both rsWVPRunner and wmWVPRunner to add the new domain
   to the comma-separated list, then run `do_build.sh` in each.

3. **Update Cloud Run env var** — `PUBLIC_RUNNER_GUEST_URL` must point to the root GCS path:
   `https://storage.googleapis.com/rswvprunner/untrusted/run.html` (already correct as of June 2026).

4. **Google OAuth** — add `https://<new-domain>/google/auth` to the authorized redirect URIs
   in Google Cloud Console → APIs & Services → Credentials → OAuth client.

## TODO: cyvector wheel for WASM (Python 3.13)

`cyvector` is a Cython-accelerated vector implementation used by wmWVPRunner. It is currently
disabled in `wmWVPRunner/vpython/vec_js.py` (`#from cyvector import *`) because the existing
wheel (`cyvector-0.1-cp311-cp311-emscripten_3_1_39_wasm32.whl`) was built for Python 3.11 /
Emscripten 3.1.39, but Pyodide v0.29.4 requires Python 3.13 / Emscripten 3.1.58.

Steps to re-enable:

1. **Update the pyodide fork** (`/Users/steve/Development/pyodide`, `sjs` branch) to a version
   that targets Python 3.13 / Emscripten 3.1.58 (merge upstream Pyodide changes into `sjs`).

2. **Rebuild the wheel** — the cyvector package lives at
   `pyodide/packages/cyvector/cyvector/cyvector.pyx` (already has the kwargs fix from June 2026).
   Build with the updated Pyodide toolchain to produce a `cp313` wheel.

3. **Deploy the wheel** — copy the new `.whl` to `wmWVPRunner/static/` and update the filename
   reference in `wmWVPRunner/src/lib/utils/utils.js` line 2.

4. **Re-enable in vec_js.py** — uncomment `from cyvector import *` and remove `from .vector import *`
   in `wmWVPRunner/vpython/vec_js.py`. The `cyvector.vector` class will replace the pure-Python
   `vector` base class, giving a performance boost for vector-heavy programs.

5. **Rebuild vpython.zip** — `npm run zip` in wmWVPRunner, then `do_build.sh`.

## Option C (WebWorker) Implementation — Issue #1 Fix (In Progress)

**Status:** Code complete and committed (14 commits), but runtime integration broken. Iframe at `localhost:5173` refuses to connect from Flask parent.

### What Was Done

Implemented Option C architecture from wmWVPRunner/ISSUES.md to resolve Issue #1 (rate() inside user functions causing SyntaxError). Full 5-phase implementation across 16 tasks:

**Phase 1 (Tasks 1-3):** Worker skeleton
- Created `src/lib/workers/pyodide-worker.js` — Pyodide initialization on worker thread
- Added `initializeWorker()` helper to `src/lib/utils/utils.js` with proper resource cleanup
- Fixed code quality issues: event listener memory leaks, timeout race conditions
- Refactored `src/routes/+page.svelte` runMe() to use worker instead of direct runPythonAsync
- Removed regex substitution array (no longer needed)

**Phase 2 (Tasks 4-6):** rate() synchronization
- Created `vpython/_worker_bridge.py` — Python module that wraps rate() and graphics calls
- Implemented Atomics.wait/notify synchronization pattern
- Added frame timing handler on main thread
- Code changes committed; manual testing ready (but blocked by iframe connection issue)

**Phase 3 (Tasks 7-9):** Graphics proxy bridge
- Added graphics object registry and proxy system
- Wired sphere(), box(), cylinder(), pyramid(), cone(), torus(), helix(), ring(), vertex(), compound(), curve()
- Graphics calls proxied through SharedArrayBuffer

**Phase 4 (Tasks 10-11):** I/O redirection
- WorkerStdout/WorkerStderr classes redirect print() and errors to main thread
- stdout/stderr handlers already in place from skeleton

**Phase 5 (Tasks 12-16):** Deployment & documentation
- Created comprehensive test scenarios document (TEST_SCENARIOS.md)
- Created implementation notes (IMPLEMENTATION_NOTES.md) with architecture, deployment checklist, known limitations
- Added COOP/COEP header configuration for SharedArrayBuffer support
- Fixed variable shadowing and const reassignment errors
- Build system verified working (npm run build passes)

**All code committed to wmWVPRunner main branch (14 commits total).**

### Current Problem

**"localhost refuses to connect" in iframe — Vite dev server not reachable from Flask**

**Symptoms:**
- Flask app loads at `http://localhost:8080` ✓
- Vite dev server running at `http://localhost:5173` ✓
- Direct browser access to `http://localhost:5173` works ✓
- Iframe src="http://localhost:5173/" in Flask page → "localhost refuses to connect" ✗
- No console logs from wmWVPRunner appear in browser (suggests iframe never loads)

**Setup:**
- SSH from laptop to intelmini with `-L 8080:localhost:8080 -L 5173:localhost:5173` port forwarding
- Flask + datastore running in tmux pane 1
- Vite dev server running in tmux pane 2
- Both report ready, but iframe can't reach Vite

**Recent changes that might be related:**
- Added COOP/COEP headers to Flask (in flaskHost/src/__init__.py) — required for SharedArrayBuffer
- Added Vite plugin to set COOP/COEP headers (in wmWVPRunner/vite.config.js)
- Added check for SharedArrayBuffer availability and helpful error message
- Added detailed console logging to track postMessage flow

### What Needs Investigation on Next Machine

1. **Verify Vite is serving with correct headers** — run curl to check if COOP/COEP headers are actually being sent
2. **Check browser console logs** — See if detailed logging we added (prefixed with `[wmWVPRunner]`) appears
3. **Verify network requests** — DevTools Network tab should show iframe request to localhost:5173
4. **Check origin mismatch** — Flask sends postMessage from `localhost:8080`, wmWVPRunner needs to accept that origin
5. **Test iframe in isolation** — Open wmWVPRunner directly at localhost:5173 to confirm it works

### Key Files Modified

**wmWVPRunner:**
- `src/routes/+page.svelte` — Main runner page, refactored to use worker
- `src/lib/workers/pyodide-worker.js` — New worker entry point
- `src/lib/utils/utils.js` — Worker initialization helper
- `vpython/_worker_bridge.py` — New worker bridge module
- `vpython/__init__.py` — Conditional worker imports
- `vite.config.js` — Vite plugin for COOP/COEP headers (newly created)
- `svelte.config.js` — Documentation of header requirements
- `IMPLEMENTATION_NOTES.md` — New comprehensive docs
- `TEST_SCENARIOS.md` — New test documentation

**flaskHost:**
- `src/__init__.py` — Added COOP/COEP headers via after_request handler

### Git State

**wmWVPRunner repo:**
- 14 commits ahead of origin/main (all pushed)
- Working tree clean
- Latest commits: dec2d1f (debug logging), b69c777 (ready message delay), 4383618 (SharedArrayBuffer check)

**flaskHost repo:**
- 1 commit ahead of origin/main (COOP/COEP headers)

### To Pick Up on Another Machine

1. `git pull origin main` in both wmWVPRunner and flaskHost
2. In wmWVPRunner: `npm install && npm run dev`
3. In flaskHost: `make serve` (or docker compose)
4. Open DevTools and check console for `[wmWVPRunner]` logs
5. Investigate why iframe can't reach localhost:5173 (network tab, headers, origin checks)
6. Once iframe loads, manual tests are ready to go (see TEST_SCENARIOS.md)
