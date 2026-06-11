# glowThings workspace management
# Run from the glowThings directory.

.PHONY: help serve deploy deploy-runners deploy-docs deploy-flask build-packages

help:
	@echo "Targets:"
	@echo "  serve            Start all local dev servers (flask :8080, rs :8090, wm :5173)"
	@echo "  deploy           Deploy all four repos"
	@echo "  deploy-flask     Deploy flaskHost to Cloud Run"
	@echo "  deploy-runners   Deploy both runners to GCS"
	@echo "  deploy-docs      Build and deploy VPython docs to GCS"
	@echo "  build-packages   Rebuild rsWVPRunner GlowScript packages from source"

# ── Local dev ─────────────────────────────────────────────────────────────────

serve:
	@echo "Starting all dev servers (Ctrl-C to stop all)..."
	@trap 'kill 0' INT; \
	  (cd flaskHost  && bash serve.sh) & \
	  (cd rsWVPRunner && bash serve.sh) & \
	  (cd wmWVPRunner && bash serve.sh) & \
	  wait

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
