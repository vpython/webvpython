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
before committing. Local dev servers: Flask :8080 (docker), rs runner :8090,
wasm runner (vite) :5173.

### Per-fix workflow
1. Edit `wmWVPRunner/vpython/*.py` (and/or `src/routes/+page.svelte`).
2. `cd wmWVPRunner && npm run zip` — rebuilds `static/vpython.zip` (gitignored)
   so the dev server serves the updated package.
3. Reload localhost:8080 and run a test program. A `+page.svelte` change needs a
   full page reload; a package-only change needs just re-running the program.
4. Commit with `Fixes #N` once verified in the browser, then push to main.

### Done — all committed + pushed to wmWVPRunner main
- **#1** rate()/await inside functions — AST transformer
  (`vpython/_async_transform.py`); preserves line numbers/comments. NOTE: this
  is the same root cause as **#9** and **#20** ('await' outside async function)
  — those two are very likely fixed too but were not individually re-tested;
  worth confirming with their programs (Bezier #9, WaveEquation #20) and closing.
- **#8** `copy()` — top-level wrapper delegating to `clone()`
- **#13** `Date()` — js Date constructor wrapper
- **#23** MathJax — load MathJax 2.7.0 before glow in `+page.svelte`; `_mathjax.py`
  proxy so `MathJax.Hub.Queue([...])` converts the Python list to a JS array
- **ghbars** (no GH issue) — was wired to gdots factory and never exported; fixed
- **#11** scene.delete() / obj.delete() — `glowProxy.delete()` calls `remove()`
  when present (canvas/graphs/widgets) else `visible=False` + `__deleted=True`
  (3-D primitives have no remove()). setattr used to avoid name-mangling.
- **#19** plot floats — `graphPlotter.plot()` to_js()-converts positional
  list/tuple args (Pyodide doesn't auto-convert lists to JS arrays)
- **#3** `input()` — uses `window.prompt()` (what GlowScript's winput uses);
  Python's builtin input() raised OSError under Pyodide
- **#17** range() float step — WON'T FIX (documented in ISSUES.md): keep range()
  integer-only (standard Python); recommend numpy.arange. A user-facing
  compatibility note in webVPythonDocsHome would be good but isn't written yet.

### Key facts learned (so we don't re-derive them)
- Removing the COOP/COEP headers (added for the abandoned Option C worker) is
  what fixed the "iframe refuses to connect" — COEP require-corp made the Flask
  page cross-origin-isolated, blocking cross-origin runner iframes.
- Pyodide does NOT auto-convert a Python list to a JS array when calling a JS
  function — it passes an opaque PyProxy. This bit #19 (plot) and #23 (MathJax
  Queue). Use `to_js()`.
- GlowScript removal mechanisms differ by type: canvas/scene, graphs, and
  widgets have `remove()`; 3-D primitives use `visible=False` + `__deleted`.
- The glow library configures MathJax itself, but only if MathJax is already
  loaded when glow evaluates — so MathJax must load BEFORE glow.

### Remaining open issues (suggested next: #6)
- **#9, #20** — confirm fixed by the AST transformer, then close
- **#5** — forward references (bind before def); real-Python limitation → likely
  document, like #17
- **#6** — NameError when clicking a sphere (scene.bind / event-handler path);
  may share a root cause with #21
- **#21** — vector exchange inside a button handler fails
- **#12** sound, **#16** print font differs, **#14/#15** slow startup/exec
- See `wmWVPRunner/ISSUES.md` for the full catalogue.
