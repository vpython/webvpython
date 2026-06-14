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

## WASM runner issue fixes — session progress (through 2026-06-14)

Working through the open GitHub issues in wmWVPRunner (catalogued in
`wmWVPRunner/ISSUES.md`), one fix per commit, each verified in the browser
before committing.

### Workflow for these fixes
1. Edit `wmWVPRunner/vpython/*.py` (and/or `src/routes/+page.svelte`).
2. `cd wmWVPRunner && npm run zip` — rebuilds `static/vpython.zip` so the dev
   server serves the updated package. (`static/vpython.zip` is gitignored.)
3. Full-reload (or hot-reload) the Flask page at localhost:8080 and run a test
   program. A `+page.svelte` change needs a full page reload; a package-only
   change needs just the program re-run.
4. Commit with `Fixes #N` once verified.

Local dev was already running: Flask :8080 (docker), rs runner :8090, wasm
runner (vite) :5173. Issue #1 (rate() in functions) was fixed earlier via the
AST transformer — see `wmWVPRunner/vpython/_async_transform.py`.

### Done (committed + pushed to wmWVPRunner main)
- **#1** rate()/await — AST transformer (`_async_transform.py`)
- **#8** `copy()` — top-level wrapper delegating to `clone()`
- **#13** `Date()` — js Date constructor wrapper in `__init__.py`
- **#23** MathJax — load MathJax 2.7.0 before glow in `+page.svelte`; proxy in
  `_mathjax.py` so `MathJax.Hub.Queue([...])` converts the Python list to a JS
  array (Pyodide does not auto-convert list args to JS arrays)
- **ghbars** (no GH issue) — was wired to the gdots factory and never exported;
  now imports `js_ghbars`, uses the right factory, exported

### In progress — #11 scene.delete() / obj.delete()  (BRANCH: `wip-scene-delete`)
`delete` is a JS reserved word, so `getattr(jsObj, 'delete')` raised
AttributeError. GlowScript objects expose `remove()` instead (classic GlowScript
rewrites `.delete` -> `.remove` in preprocessing; see
`glowscript/lib/glow/canvas.js:289`).

Added `glowProxy.delete()` calling `self.jsObj.remove()` (committed on branch
`wip-scene-delete`, pushed). Result: it is now callable with no AttributeError,
BUT calling it does NOT actually remove a 3-D primitive — a `box` stays visible
after `b.delete()`.

**Next step:** the `remove()` definitions found in `primitives.js`
(lines 3020/3197/3233/3363/3448/3620/3719) are all WIDGETS
(radio/button/slider/menu/etc.). The 3-D body remove path (box/sphere/compound)
is elsewhere and still needs locating — find what actually removes a rendered
primitive from the canvas (and whether it needs a canvas re-render / object-list
splice), then make `glowProxy.delete()` call the right thing. Verify a box
disappears, then merge `wip-scene-delete` to main with `Fixes #11`.

### Remaining queued issues (suggested order)
- **#19** plot floats — `graphPlotter.plot()` needs `to_js()` on numeric args
- **#3** `input()` — bridge to a browser prompt (design decision needed)
- **#17** `range()` float step — provide `arange()` or document
- Others still open: #2, #4 (#randint/range compat), #5, #6, #9, #12 (sound),
  #14/#15 (slow startup/exec), #16 (print font), #20, #21 — see
  `wmWVPRunner/ISSUES.md`
