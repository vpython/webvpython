# WebVPython workspace

Management repo for the Web VPython stack. The four active sub-repos are
separate git repositories cloned into this directory.

## Sub-repos

| Directory | Repo | Purpose |
|---|---|---|
| `flaskHost/` | vpython/flaskHost | Flask app, Cloud Run deployment |
| `rsWVPRunner/` | vpython/rsWVPRunner | RapydScript runner, GCS static |
| `wmWVPRunner/` | vpython/wmWVPRunner | WASM/Pyodide runner, GCS static |
| `webVPythonDocsHome/` | vpython/webVPythonDocsHome | Sphinx docs, GCS static |
| `glowscript/` | vpython/glowscript | Classic GlowScript (being retired) |

## First-time setup

```bash
git clone git@github.com:vpython/glowThings.git
cd glowThings
bash setup.sh
```

`setup.sh` clones each sub-repo and runs post-clone setup:
- `wmWVPRunner`: `npm install`
- `rsWVPRunner`: installs Uglify-ES `node_modules` (needed for `build-packages`)
- `webVPythonDocsHome`: creates `.venv` and installs Sphinx dependencies

## Local development

```bash
make serve          # starts flask :8080, rsWVPRunner :8090, wmWVPRunner :5173
```

Each runner can also be started individually:
```bash
cd flaskHost   && bash serve.sh
cd rsWVPRunner && bash serve.sh
cd wmWVPRunner && bash serve.sh
```

## Deploy

```bash
make deploy           # all four
make deploy-flask     # flaskHost only (Cloud Run)
make deploy-runners   # both runners (GCS)
make deploy-docs      # docs (GCS)
```

## Rebuilding GlowScript packages

After modifying any file in `rsWVPRunner/lib/` or `rsWVPRunner/shaders/`:

```bash
make build-packages
```

This rebuilds all four package files in `rsWVPRunner/package/` and
regenerates `rsWVPRunner/lib/glow/shaders.gen.js` from shader sources.
Then redeploy with `make deploy-runners`.

## Public URLs

| Service | URL |
|---|---|
| Production (beta) | https://beta.webvpython.org |
| Cloud Run direct | https://flaskdstorehost-dhppn6xgeq-uc.a.run.app |
| RS runner (GCS) | https://storage.googleapis.com/rswvprunner/untrusted/run.html |
| WASM runner (GCS) | https://storage.googleapis.com/wmvprunner/index.html |
| Docs (GCS) | https://storage.googleapis.com/glow-docs/VPythonDocs/index.html |
