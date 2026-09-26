#!/bin/bash
# Pull the workspace repo and every sub-repo, fast-forward only.
#
# A fast-forward-only pull never creates a merge and never overwrites local
# edits: if a repo has diverged from origin, or a local change conflicts with
# an incoming one, git refuses and this script reports it and moves on.
#
# Usage: bash refreshall.sh   (from anywhere)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

REPOS=". flaskHost rsWVPRunner wmWVPRunner webVPythonDocsHome glowscript"
failed=0
summary=""

for repo in $REPOS; do
    name=$repo
    [ "$repo" = "." ] && name="webvpython (workspace)"
    echo "=== $name ==="

    if [ ! -d "$repo/.git" ]; then
        echo "  missing — run setup.sh to clone it"
        summary="$summary\n  $name: MISSING"
        failed=1
        continue
    fi

    branch=$(git -C "$repo" branch --show-current)
    if [ -z "$branch" ]; then
        echo "  detached HEAD — skipping"
        summary="$summary\n  $name: SKIPPED (detached HEAD)"
        continue
    fi

    before=$(git -C "$repo" rev-parse HEAD)
    if ! git -C "$repo" pull --ff-only --quiet; then
        echo "  pull failed on '$branch' — resolve by hand (diverged, or local edits conflict)"
        summary="$summary\n  $name: FAILED on $branch"
        failed=1
        continue
    fi
    after=$(git -C "$repo" rev-parse HEAD)

    if [ "$before" = "$after" ]; then
        state="up to date"
    else
        count=$(git -C "$repo" rev-list --count "$before..$after")
        state="updated, $count new commit(s)"
        git -C "$repo" log --oneline "$before..$after" | sed 's/^/    /'
    fi

    ahead=$(git -C "$repo" rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    [ "$ahead" != "0" ] && state="$state; $ahead local commit(s) not pushed"
    [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ] && state="$state; uncommitted changes"

    echo "  $branch: $state"
    summary="$summary\n  $name: $state"
done

echo ""
echo "=== Summary ==="
printf "%b\n" "${summary#\\n}"
exit $failed
