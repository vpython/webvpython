# WebVPython workspace

Management repo for the Web VPython stack. The four active sub-repos are
separate git repositories cloned into this directory.

## Coming back to this repo?

1. `bash refreshall.sh`: pull this repo and every sub-repo (fast-forward only).
2. `make`: the menu of everything you can run (serve, deploy, build, git).
3. Current plan: [glowscript.org → webvpython.org migration](docs/superpowers/specs/2026-09-26-glowscript-to-webvpython-migration.md).
   Work-in-progress notes for the runners are in [AGENTS.md](AGENTS.md).
4. What's live: `curl -s https://beta.webvpython.org/config` shows the deployed `git_commit`.

Things that bite:
- **One database for everything.** glowscript.org (Classic GAE) and beta.webvpython.org both
  use the Datastore in GCP project `glowscript`. `make serve-prod` writes to it too.
- **Two projects.** Cloud Run (`flaskdstorehost`) and the database are in `glowscript`; the
  runner and docs buckets are in `glowscript-py38`. Deploy scripts pin their targets, so the
  active gcloud config doesn't matter.
- **Runners stay on a separate origin** from the IDE. They run student code; never serve them
  from the IDE's own domain.

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

## Staying up to date

```bash
bash refreshall.sh    # or: make git-pull
```

Pulls this workspace repo and every sub-repo (including `glowscript/`), fast-forward
only. It never merges or overwrites local edits; a repo that has diverged or has
conflicting local changes is reported and skipped. Run it before starting work on a
different machine.

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
