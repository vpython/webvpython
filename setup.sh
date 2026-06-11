#!/bin/bash
# Clone all sub-repos into this workspace after checking out the management repo.
# Run once from the glowThings directory.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

clone_if_missing() {
    local dir=$1
    local url=$2
    if [ -d "$dir/.git" ]; then
        echo "  $dir — already present, skipping"
    else
        echo "  Cloning $dir..."
        git clone "$url" "$dir"
    fi
}

echo "=== Setting up glowThings workspace ==="
clone_if_missing flaskHost          git@github.com:vpython/flaskHost.git
clone_if_missing rsWVPRunner        git@github.com:vpython/rsWVPRunner.git
clone_if_missing wmWVPRunner        git@github.com:vpython/wmWVPRunner.git
clone_if_missing webVPythonDocsHome git@github.com:vpython/webVPythonDocsHome.git
clone_if_missing glowscript         git@github.com:vpython/glowscript.git

echo ""
echo "=== Post-clone setup ==="

echo "  wmWVPRunner: installing npm dependencies..."
(cd wmWVPRunner && npm install)

echo "  rsWVPRunner: installing build-tools dependencies..."
if [ -f rsWVPRunner/build-tools/Uglify-ES/uglify-es/package.json ]; then
    (cd rsWVPRunner/build-tools/Uglify-ES/uglify-es && npm install)
fi

echo "  webVPythonDocsHome: creating Python venv..."
if [ ! -d webVPythonDocsHome/.venv ]; then
    (cd webVPythonDocsHome && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt)
else
    echo "    .venv already exists, skipping"
fi

echo ""
echo "=== Done. See README.md for serve and deploy commands. ==="
