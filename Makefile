# webvpython workspace management
# Run from the webvpython directory.

# Bare `make` prints the target list (explicit so reordering targets can't change it).
.DEFAULT_GOAL := help

.PHONY: help serve serve-prod stop deploy deploy-runners deploy-docs deploy-flask build-packages \
        git-status git-pull git-push

SUBREPOS := flaskHost rsWVPRunner wmWVPRunner webVPythonDocsHome

help:
	@echo "Targets:"
	@echo "  serve            Start all local dev servers (flask :8080, rs :8090, wm :5173)"
	@echo "  serve-prod       Like serve, but flask runs locally against PROD Datastore (glowscript)"
	@echo "  stop             Stop all local dev servers"
	@echo "  deploy           Deploy all four repos"
	@echo "  deploy-flask     Deploy flaskHost to Cloud Run"
	@echo "  deploy-runners   Deploy both runners to GCS"
	@echo "  deploy-docs      Build and deploy VPython docs to GCS"
	@echo "  build-packages   Rebuild rsWVPRunner GlowScript packages from source"
	@echo "  git-status       git status in all sub-repos"
	@echo "  git-pull         git pull in all sub-repos"
	@echo "  git-push         git push in all sub-repos"

# ── Local dev ─────────────────────────────────────────────────────────────────

serve:
	@echo "Starting all dev servers (Ctrl-C to stop all)..."
	@trap 'kill 0' INT; \
	  (cd flaskHost  && bash serve.sh) & \
	  (cd rsWVPRunner && bash serve.sh) & \
	  (cd wmWVPRunner && bash serve.sh) & \
	  wait

serve-prod:
	@if [ ! -x flaskHost/.venv/bin/flask ]; then \
	  echo "ERROR: flaskHost/.venv/bin/flask not found."; \
	  echo "  Create it first:  cd flaskHost && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"; \
	  exit 1; \
	fi
	@if grep -qE '^[[:space:]]*DATASTORE_EMULATOR_HOST' flaskHost/.flaskenv; then \
	  echo "ERROR: DATASTORE_EMULATOR_HOST is active in flaskHost/.flaskenv — comment it out to hit PROD."; \
	  exit 1; \
	fi
	@if [ ! -f "$$HOME/.config/gcloud/application_default_credentials.json" ]; then \
	  echo "ERROR: no gcloud application-default credentials. Run: gcloud auth application-default login"; \
	  exit 1; \
	fi
	@echo "Starting dev servers — flask -> PROD Datastore (glowscript). Ctrl-C to stop all."
	@echo "WARNING: saves/deletes from the UI write to LIVE production data."
	@# Set project and credentials explicitly. flask loads .flaskenv with
	@# python-dotenv override=False, so these win over .flaskenv (which points at
	@# the old glowscript-py38 dev project and svc.json, a py38 key with no access
	@# to glowscript) and over any ambient gcloud config. Credentials are your own
	@# application-default login, not a downloaded key.
	@trap 'kill 0' INT; \
	  (cd flaskHost   && GOOGLE_CLOUD_PROJECT=glowscript GOOGLE_APPLICATION_CREDENTIALS="$$HOME/.config/gcloud/application_default_credentials.json" .venv/bin/flask run) & \
	  (cd rsWVPRunner && bash serve.sh) & \
	  (cd wmWVPRunner && bash serve.sh) & \
	  wait

stop:
	-cd flaskHost && docker compose down
	@for port in 8080 8090 5173; do \
	  pids=$$(lsof -ti tcp:$$port); \
	  if [ -n "$$pids" ]; then echo "Stopping port $$port (pid $$pids)"; kill $$pids; fi; \
	done

# ── Deploy ────────────────────────────────────────────────────────────────────

deploy: deploy-flask deploy-runners deploy-docs

deploy-flask:
	cd flaskHost && bash do_build.sh

deploy-runners:
	cd rsWVPRunner && bash do_build.sh
	cd wmWVPRunner && bash do_build.sh

deploy-docs:
	cd webVPythonDocsHome && bash do_build.sh

# ── Build ─────────────────────────────────────────────────────────────────────

build-packages:
	cd rsWVPRunner && python build_package.py

# ── Git ───────────────────────────────────────────────────────────────────

git-status:
	@for repo in $(SUBREPOS); do \
	  echo "=== $$repo ==="; \
	  git -C $$repo status -s; \
	done

git-pull:
	@for repo in $(SUBREPOS); do \
	  echo "=== $$repo ==="; \
	  git -C $$repo pull; \
	done

git-push:
	@for repo in $(SUBREPOS); do \
	  echo "=== $$repo ==="; \
	  git -C $$repo push; \
	done
