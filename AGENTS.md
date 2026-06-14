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
